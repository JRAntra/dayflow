import Foundation
import CryptoKit

/// Your data on disk: the same files as the Mac app, plus your clips.
///
///     <dir>/schedule.json      { "blocks": [...] }
///     <dir>/block-types.json   [ { id, name, reminders } ]
///     <dir>/settings.json      the iPhone's settings
///     <dir>/sounds.json        [ { id, name, ext, file } ]
///     <dir>/progress.json      checks, skips and each day's result (this device only)
///     <clips>/<name>.<ext>     your clips, in a folder you can see (On My iPhone › DayFlow › Clips)
///     <clips>/Originals/       long songs you took a 30-second piece from
public final class DataStore {
    public let dir: URL
    /// The Clips folder. Files you put here become clips (see ClipFolder.swift).
    public let clipsDir: URL
    public internal(set) var blocks: [Block] = []
    public internal(set) var types: [BlockType] = []
    public internal(set) var settings = Settings()
    public internal(set) var clips: [CustomClip] = []
    /// What you checked off and skipped, day by day. Kept on this device only, never exported.
    public internal(set) var progress = DayProgress()

    var scheduleFile: URL { dir.appendingPathComponent("schedule.json") }
    var typesFile: URL { dir.appendingPathComponent("block-types.json") }
    var settingsFile: URL { dir.appendingPathComponent("settings.json") }
    var clipsFile: URL { dir.appendingPathComponent("sounds.json") }
    var progressFile: URL { dir.appendingPathComponent("progress.json") }
    /// Where clips were kept before the Clips folder, as sounds/<id>.<ext>.
    var legacyClipsDir: URL { dir.appendingPathComponent("sounds", isDirectory: true) }

    public init(dir: URL, clipsDir: URL? = nil) {
        self.dir = dir
        self.clipsDir = clipsDir ?? dir.appendingPathComponent("Clips", isDirectory: true)
        load()
    }

    /// Whether this store has ever been saved (false before the welcome screens finish).
    public var hasSchedule: Bool { FileManager.default.fileExists(atPath: scheduleFile.path) }

    public func load() {
        clips = (read(clipsFile)?.array ?? []).compactMap { c in
            guard let id = c["id"]?.stringValue, let name = c["name"]?.stringValue, let ext = c["ext"]?.stringValue else { return nil }
            return CustomClip(id: id, name: name, ext: ext, file: c["file"]?.string)
        }
        moveLegacyClips()
        types = (try? Sanitize.types(read(typesFile) ?? JSONValue.from(Specs.starterTypes()), isSound: isSound)) ?? Specs.starterTypes()
        settings = Sanitize.settings(read(settingsFile), isSound: isSound)
        var raw = read(scheduleFile)?["blocks"] ?? .array([])
        // Blocks with their own reminders become types of their own.
        let own = OwnReminders.toTypes(raw, types: types, isSound: isSound)
        if own.changed, let clean = try? Sanitize.types(own.types, isSound: isSound) {
            types = clean
            raw = own.blocks
            try? write(typesFile, types)
        }
        blocks = (try? Sanitize.blocks(raw, typeIds: Set(types.map(\.id)), types: types, isSound: isSound)) ?? []
        if own.changed { try? write(scheduleFile, ["blocks": blocks]) }
        progress = DayProgress.read(read(progressFile))
    }

    /// Reads progress again, for changes made while DayFlow wasn't in front (Done on an alarm).
    public func reloadProgress() { progress = DayProgress.read(read(progressFile)) }

    public func saveProgress(_ p: DayProgress) throws {
        progress = p
        try write(progressFile, p)
    }

    public func isSound(_ id: String) -> Bool {
        Specs.builtinIds.contains(id) || clips.contains { $0.soundId == id }
    }

    public func clipURL(_ c: CustomClip) -> URL { clipsDir.appendingPathComponent(c.fileName) }

    public func typeOf(_ id: String) -> BlockType {
        types.first { $0.id == id } ?? types.first(where: \.isDefault)!
    }

    public func usedBy(_ typeId: String) -> Int { blocks.filter { $0.type == typeId }.count }

    // MARK: Saving

    /// Starts an empty schedule (with whatever types there are).
    public func startSchedule() throws {
        try saveBlocks(blocks)
        try write(typesFile, types)
    }

    /// "Add a sample day": the eight sample blocks, added to whatever you have, using Default.
    public func addSampleDay() throws {
        let taken = Set(blocks.map(\.id))
        try saveBlocks(blocks + Specs.sampleSchedule().map { b in var c = b; if taken.contains(c.id) { c.id = Block.newId() }; return c })
    }

    public func saveBlocks(_ list: [Block]) throws {
        blocks = try Sanitize.blocks(list, typeIds: Set(types.map(\.id)), types: types, isSound: isSound)
        try write(scheduleFile, ["blocks": blocks])
        // Checks and skips of events that are gone are dropped; one that's been remade keeps its id.
        let ids = Set(blocks.map(\.id))
        let today = progress.pruned(keeping: ids)
        if today != progress { try saveProgress(today) }
    }

    /// Saves the type list; blocks whose type was deleted move to Default.
    public func saveTypes(_ list: [BlockType]) throws {
        let clean = try Sanitize.types(list, isSound: isSound)
        let ids = Set(clean.map(\.id))
        types = clean
        try write(typesFile, types)
        if blocks.contains(where: { !$0.isEvent && !ids.contains($0.type) }) {
            try saveBlocks(blocks.map { b in var c = b; if !b.isEvent && !ids.contains(c.type) { c.type = Specs.defaultType }; return c })
        }
    }

    public func saveSettings(_ s: Settings) throws {
        // Cleaned against the starting values, not the previous ones: a value you cleared
        // (a pause, say) is left out of the encoded settings and must stay cleared.
        settings = Sanitize.settings(JSONValue.from(s), prev: Settings(), isSound: isSound)
        try write(settingsFile, settings)
    }

    // MARK: Clips

    public static func clipHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Copies a clip into the Clips folder. The same audio is only ever stored once; a
    /// different clip whose name is taken becomes "Name (2)", and so does its file.
    @discardableResult
    public func installClip(name: String, ext: String?, data: Data) throws -> CustomClip {
        let type = try Sanitize.clipType(name: name, ext: ext, bytes: data.count)
        let id = Self.clipHash(data)
        if let existing = clips.first(where: { $0.id == id }) { return existing }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let label = uniqueClipName(trimmed.isEmpty ? "Sound clip" : trimmed)
        try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        let file = uniqueFileName(Self.safeFileName(label), ext: type)
        try data.write(to: clipsDir.appendingPathComponent(file), options: .atomic)
        let clip = CustomClip(id: id, name: label, ext: type, file: file)
        clips.append(clip)
        try write(clipsFile, clips)
        return clip
    }

    /// Deletes a clip. A reminder that had other sounds too just loses it; one that used only
    /// this clip goes back to its starting sound. Returns the names of the reminders that went
    /// back, e.g. "Focus · Heads-up".
    /// With `deleteFile` off, the file is left alone (it's already gone, or the app moves it to
    /// the Trash itself).
    @discardableResult
    public func removeClip(_ id: String, deleteFile: Bool = true) throws -> [String] {
        guard let clip = clips.first(where: { $0.id == id }) else { return [] }
        if deleteFile { try? FileManager.default.removeItem(at: clipURL(clip)) }
        clips.removeAll { $0.id == id }
        try write(clipsFile, clips)
        var reset: [String] = []
        var changed = false, blocksChanged = false
        /// Takes the clip out of one reminder. Returns whether it was its only sound.
        func drop(_ r: inout Reminder, _ starting: String) -> Bool {
            guard r.choices.contains(clip.soundId) else { return false }
            changed = true
            let rest = r.choices.filter { $0 != clip.soundId }
            r.choices = rest.isEmpty ? [starting] : rest
            return rest.isEmpty
        }
        for i in types.indices {
            for key in TypeReminderKey.allCases where drop(&types[i].reminders[key], Specs.spec(key).sound) {
                reset.append("\(types[i].name) · \(Specs.spec(key).label)")
            }
        }
        for key in MeetingReminderKey.allCases where drop(&settings.meetings[key], Specs.spec(key).sound) {
            reset.append("Meetings · \(Specs.spec(key).label)")
        }
        let settingsChanged = changed
        changed = false
        for i in blocks.indices {
            if var a = blocks[i].alert {
                if drop(&a, Specs.eventSpec.sound) { reset.append(blocks[i].title) }
                blocks[i].alert = a
            }
        }
        blocksChanged = changed
        if settingsChanged {
            try write(typesFile, types)
            try write(settingsFile, settings)
        }
        if blocksChanged { try write(scheduleFile, ["blocks": blocks]) }
        return reset
    }

    // MARK: Files

    func read(_ url: URL) -> JSONValue? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONValue.decode(data)
    }

    func write<T: Encodable>(_ url: URL, _ value: T) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONFile.encode(value).write(to: url, options: .atomic)
    }
}
