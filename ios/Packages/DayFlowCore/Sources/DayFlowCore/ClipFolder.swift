import Foundation

/// What DayFlow can say about a file in the Clips folder that isn't (yet) a clip.
public enum ClipProblem: Hashable, Sendable {
    /// Over 30 seconds or 5 MB, but playable: choose a 30-second piece of it.
    case needsPiece(seconds: Double)
    /// Something DayFlow can't use, with the reason, e.g. "isn't an mp3, wav, m4a, aac or ogg file."
    case unusable(String)
}

/// A file in the Clips folder that isn't a clip, shown in Your clips with what to do about it.
public struct FolderFile: Hashable, Identifiable, Sendable {
    public var file: String
    public var problem: ClipProblem
    public var id: String { file }
    public var name: String { (file as NSString).deletingPathExtension }

    public init(file: String, problem: ClipProblem) { self.file = file; self.problem = problem }

    public var message: String {
        switch problem {
        case .needsPiece(let s): "\(Int(s.rounded())) seconds. Choose 30 seconds of it to use it."
        case .unusable(let why): why
        }
    }
}

/// How a scan found the folder.
public struct ClipScan: Sendable {
    public var added: [CustomClip] = []
    public var renamed: [CustomClip] = []
    /// Reminders that went back to their starting sound because their clip's file is gone.
    public var reset: [String] = []
    public var removed: [String] = []
    public var others: [FolderFile] = []
    public var changed: Bool { !added.isEmpty || !renamed.isEmpty || !removed.isEmpty }
}

/// The Clips folder: your clips as ordinary files you can see and manage.
///
/// - Files you put in the folder become clips, named after the file.
/// - Renaming a file renames its clip; deleting a file removes its clip (its reminders go back
///   to their starting sounds).
/// - Long files stay listed until you choose a 30-second piece; the original then moves into
///   Originals, which isn't scanned.
/// The checks are the same as for Add a clip. Whether a file plays, and how long it is, comes
/// from `inspect`, which the app answers with the system's audio framework.
extension DataStore {
    public static let originalsFolder = "Originals"
    /// The largest file DayFlow will take a piece from.
    public static let maxSourceBytes = 200 * 1024 * 1024

    public enum Inspection: Sendable {
        case plays(seconds: Double)
        case unplayable
    }

    public var originalsDir: URL { clipsDir.appendingPathComponent(Self.originalsFolder, isDirectory: true) }

    /// A file name made from a clip name: no slashes, colons or leading dots.
    public static func safeFileName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Sound clip" : String(s.prefix(60))
    }

    /// "Name", or "Name (2)"… if another clip has that name (ignoring case).
    func uniqueClipName(_ base: String, except id: String? = nil) -> String {
        let taken = Set(clips.filter { $0.id != id }.map { $0.name.lowercased() })
        var label = base
        var n = 2
        while taken.contains(label.lowercased()) { label = "\(base) (\(n))"; n += 1 }
        return label
    }

    /// "Name.ext", or "Name (2).ext"… if that file already exists.
    func uniqueFileName(_ base: String, ext: String, in folder: URL? = nil, except: String? = nil) -> String {
        let dir = folder ?? clipsDir
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).map { $0.lowercased() })
            .subtracting([except?.lowercased()].compactMap { $0 })
        var file = "\(base).\(ext)"
        var n = 2
        while existing.contains(file.lowercased()) { file = "\(base) (\(n)).\(ext)"; n += 1 }
        return file
    }

    /// Clips saved before the Clips folder existed (sounds/<id>.<ext>) move in under their names.
    func moveLegacyClips() {
        var moved = false
        for i in clips.indices where clips[i].file == nil {
            let old = legacyClipsDir.appendingPathComponent("\(clips[i].id).\(clips[i].ext)")
            guard FileManager.default.fileExists(atPath: old.path) else { continue }
            try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
            let file = uniqueFileName(Self.safeFileName(clips[i].name), ext: clips[i].ext)
            if (try? FileManager.default.moveItem(at: old, to: clipsDir.appendingPathComponent(file))) != nil {
                clips[i].file = file
                moved = true
            }
        }
        if moved {
            try? write(clipsFile, clips)
            // The old folder goes only if nothing is left in it.
            if ((try? FileManager.default.contentsOfDirectory(atPath: legacyClipsDir.path)) ?? ["?"]).isEmpty {
                try? FileManager.default.removeItem(at: legacyClipsDir)
            }
        }
    }

    /// Brings the clip list in line with the folder. Unknown files are hashed: one with the
    /// same audio as a clip whose file is gone is that clip, renamed; others are checked and
    /// added, or listed with what's wrong. Clips whose file is gone are removed.
    /// If the folder can't be read at all, nothing is removed.
    @discardableResult
    public func scanClipsFolder(inspect: (URL) -> Inspection) throws -> ClipScan {
        var scan = ClipScan()
        let fm = FileManager.default
        try fm.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        let names = try fm.contentsOfDirectory(atPath: clipsDir.path).filter { name in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: clipsDir.appendingPathComponent(name).path, isDirectory: &isDir)
            return !name.hasPrefix(".") && !isDir.boolValue
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let known = Set(clips.compactMap(\.file).map { $0.lowercased() })
        var missing = clips.filter { c in !names.contains { $0.lowercased() == c.fileName.lowercased() } }

        for name in names where !known.contains(name.lowercased()) {
            let url = clipsDir.appendingPathComponent(name)
            let ext = (name as NSString).pathExtension.lowercased()
            let base = (name as NSString).deletingPathExtension
            guard Specs.clipTypes.contains(ext) else {
                scan.others.append(.init(file: name, problem: .unusable("Isn't an mp3, wav, m4a, aac or ogg file.")))
                continue
            }
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            if size == 0 { scan.others.append(.init(file: name, problem: .unusable("The file is empty."))); continue }
            if size > Self.maxSourceBytes { scan.others.append(.init(file: name, problem: .unusable("Larger than 200 MB."))); continue }
            if size <= Self.maxImportBytes, let data = try? Data(contentsOf: url) {
                let id = Self.clipHash(data)
                // The same audio as a clip whose file is gone: you renamed it.
                if let i = missing.firstIndex(where: { $0.id == id }), let ci = clips.firstIndex(where: { $0.id == id }) {
                    missing.remove(at: i)
                    clips[ci].file = name
                    clips[ci].name = uniqueClipName(base, except: id)
                    clips[ci].ext = ext
                    scan.renamed.append(clips[ci])
                    continue
                }
                // A copy of a clip you already have.
                if let twin = clips.first(where: { $0.id == id }) {
                    scan.others.append(.init(file: name, problem: .unusable("The same sound as \(twin.name).")))
                    continue
                }
            }
            switch inspect(url) {
            case .unplayable:
                scan.others.append(.init(file: name, problem: .unusable("DayFlow can't play this file. Try converting it to mp3 or wav.")))
            case .plays(let seconds):
                if seconds > Specs.maxClipSeconds + 0.5 || size > Specs.maxClipBytes {
                    scan.others.append(.init(file: name, problem: .needsPiece(seconds: seconds)))
                } else if let data = try? Data(contentsOf: url) {
                    let clip = CustomClip(id: Self.clipHash(data), name: uniqueClipName(base), ext: ext, file: name)
                    clips.append(clip)
                    scan.added.append(clip)
                }
            }
        }

        for gone in missing {
            scan.reset += try removeClip(gone.id, deleteFile: false)
            scan.removed.append(gone.name)
        }
        if scan.changed { try write(clipsFile, clips) }
        return scan
    }

    /// Renames a clip and its file. Reminders that use it keep it.
    @discardableResult
    public func renameClip(_ id: String, to newName: String) throws -> CustomClip {
        let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { throw DataError("A clip needs a name.") }
        guard let i = clips.firstIndex(where: { $0.id == id }) else { throw DataError("That clip has been removed.") }
        if clips.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            throw DataError("There's already a clip called \"\(name)\".")
        }
        let old = clipURL(clips[i])
        let file = uniqueFileName(Self.safeFileName(name), ext: clips[i].ext, except: clips[i].fileName)
        if file != clips[i].fileName {
            try FileManager.default.moveItem(at: old, to: clipsDir.appendingPathComponent(file))
        }
        clips[i].name = name
        clips[i].file = file
        try write(clipsFile, clips)
        return clips[i]
    }

    /// Saves a 30-second piece as "<name> (clip).<ext>". A source in the Clips folder then moves
    /// into Originals, so the long file isn't listed any more and nothing of yours is deleted.
    @discardableResult
    public func savePiece(_ data: Data, ext: String, name: String, source: URL?) throws -> CustomClip {
        let clip = try installClip(name: "\(name) (clip)", ext: ext, data: data)
        if let source, source.deletingLastPathComponent().standardizedFileURL == clipsDir.standardizedFileURL {
            try FileManager.default.createDirectory(at: originalsDir, withIntermediateDirectories: true)
            let base = (source.lastPathComponent as NSString).deletingPathExtension
            let file = uniqueFileName(base, ext: source.pathExtension, in: originalsDir)
            try FileManager.default.moveItem(at: source, to: originalsDir.appendingPathComponent(file))
        }
        return clip
    }
}
