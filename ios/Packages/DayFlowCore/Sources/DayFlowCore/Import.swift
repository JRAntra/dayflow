import Foundation

/// What an export file would change, shown before anything is replaced. The same rules as the
/// Mac's readImport: the file's Default is your Default, other types match by name, and a
/// sound that can't be used falls back to that reminder's starting sound.
public struct ImportPreview: Sendable {
    public struct PreviewBlock: Hashable, Sendable {
        public var block: Block
        public var typeName: String
    }
    public struct Clip: Hashable, Sendable {
        public var id: String
        public var name: String
        public var ext: String
        public var data: Data
        /// The reminders that use it, e.g. "Focus · Start, Meetings · Starting now".
        public var slots: String
    }
    struct FileType: Sendable {
        var id: String
        var name: String
        var isDefault: Bool
        var reminders: TypeReminders
    }

    public var fileName: String
    /// How many blocks you have now.
    public var current: Int
    public var blocks: [PreviewBlock]
    /// Types the file brings that you don't have yet.
    public var newTypes: [String]
    public var isBackup: Bool
    /// Whether the file has reminder settings that can be applied.
    public var hasSettings: Bool
    public var problems: [String]
    /// Clips the file brings. The app checks each one plays before applying.
    public var clips: [Clip]

    var fileTypes: [FileType]
    var incoming: (volume: Int, meetings: MeetingReminders)?
    var rawBlocks: [Block]
}

extension DataStore {
    /// Reads and checks an export file. Nothing changes until `applyImport`.
    public func readImport(_ data: Data, fileName: String) throws -> ImportPreview {
        let notExport = "That file isn't a DayFlow export."
        if data.count > Self.maxImportBytes { throw DataError("That file is too large to be a DayFlow export.") }
        guard let raw = try? JSONValue.decode(data), raw.object != nil,
              let versionNumber = raw["dayflowExport"]?.numberValueIfNumber, versionNumber == versionNumber.rounded() else {
            throw DataError(notExport)
        }
        let version = Int(versionNumber)
        if version > Self.exportVersion {
            throw DataError("That file was made by a newer version of DayFlow. Update DayFlow to import it.")
        }

        // Version 1 files had global sounds; convert them the same way the Mac does.
        var schedule = raw["schedule"]
        var fileTypesValue = raw["blockTypes"]
        var fileSettings = raw["settings"]
        if version == 1 {
            let up = UpgradeV1.run(settings: raw["settings"] ?? .object([:]), blockTypes: raw["blockTypes"] ?? .array([]),
                                   blocks: raw["schedule"]?["blocks"]?.array ?? [])
            schedule = .object(["blocks": .array(up.blocks)])
            // Without settings the file has no Default of its own, so its blocks join yours.
            let hasSettings = raw["settings"].map { v -> Bool in if case .null = v { return false }; return true } ?? false
            fileTypesValue = .array(hasSettings ? up.types : up.types.filter { $0["isDefault"] != .bool(true) })
            fileSettings = hasSettings ? .object(["volume": raw["settings"]?["volume"] ?? .null, "meetings": up.meetings]) : nil
        }

        var clipData: [String: (name: String, ext: String, data: Data)] = [:]
        var badClips: [String: String] = [:]
        for c in raw["clips"]?.array ?? [] {
            let name = String((c["name"]?.stringValue ?? "Sound clip").prefix(60))
            let id = c["id"]?.stringValue ?? ""
            let bytes = Data(base64Encoded: c["data"]?.stringValue ?? "", options: .ignoreUnknownCharacters) ?? Data()
            do {
                clipData[id] = (name, try Sanitize.clipType(name: name, ext: c["ext"]?.stringValue, bytes: bytes.count), bytes)
            } catch {
                badClips[id] = (error as? DataError)?.message ?? error.localizedDescription
            }
        }

        // Each sound is checked against the file's clips; clipSlots records which reminders
        // each usable clip serves, so the preview can name them if it turns out not to play.
        var problems: [String] = []
        var missing: [String] = []
        var clipSlots: [(String, [String])] = []
        func soundFromFile(_ v: JSONValue?, _ label: String, _ fallback: String) -> String {
            guard let s = v?.string else { return fallback }
            if Specs.builtinIds.contains(s) { return s }
            guard s.hasPrefix("custom:") else { return fallback }
            let fid = String(s.dropFirst("custom:".count))
            if clipData[fid] != nil {
                if let i = clipSlots.firstIndex(where: { $0.0 == fid }) { clipSlots[i].1.append(label) } else { clipSlots.append((fid, [label])) }
                return s
            }
            if let why = badClips[fid] { problems.append("\(why) \(label) will use its starting sound.") } else { missing.append(label) }
            return fallback
        }
        func withSounds<K: RawRepresentable>(_ src: JSONValue?, _ keys: [K], _ spec: (K) -> Specs.ReminderSpec, _ owner: String) -> JSONValue
        where K.RawValue == String {
            var o: [String: JSONValue] = [:]
            for k in keys {
                var r = src?[k.rawValue]?.object ?? [:]
                r["sound"] = .string(soundFromFile(src?[k.rawValue]?["sound"], "\(owner) · \(spec(k).label)", spec(k).sound))
                o[k.rawValue] = .object(r)
            }
            return .object(o)
        }
        let anyString: (String) -> Bool = { _ in true }

        var fileTypes: [ImportPreview.FileType] = []
        var typeNames = Set<String>()
        var fileDefault: String?
        for t in fileTypesValue?.array ?? [] {
            let name = String((t["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            if name.isEmpty || typeNames.contains(name.lowercased()) { continue }
            typeNames.insert(name.lowercased())
            let id = t["id"]?.stringValue ?? ""
            let isDefault = t["isDefault"] == .bool(true) && fileDefault == nil
            if isDefault { fileDefault = id }
            let rem = Sanitize.typeReminders(withSounds(t["reminders"], TypeReminderKey.allCases, Specs.spec, name), isSound: anyString)
            fileTypes.append(.init(id: id, name: name, isDefault: isDefault, reminders: rem))
        }

        var incoming: (Int, MeetingReminders)?
        if let s = fileSettings, s.object != nil {
            incoming = (Sanitize.clamp(s["volume"], 0, 100, settings.volume),
                        Sanitize.meetingReminders(withSounds(s["meetings"], MeetingReminderKey.allCases, Specs.spec, "Meetings"), isSound: anyString))
        }
        if !missing.isEmpty {
            problems.append("A sound clip is missing from the file, so \(missing.joined(separator: ", ")) will use the starting sound.")
        }

        let blocks: [Block]
        do {
            blocks = try Sanitize.blocks(schedule?["blocks"], typeIds: Set(fileTypes.map(\.id)), fallback: fileDefault ?? Specs.defaultType)
        } catch {
            throw DataError("The schedule in that file has a problem: \((error as? DataError)?.message ?? error.localizedDescription)")
        }

        let known = Set(types.map { $0.name.lowercased() })
        let defaultName = typeOf(Specs.defaultType).name
        return ImportPreview(
            fileName: fileName,
            current: self.blocks.count,
            blocks: blocks.map { b in
                let t = fileTypes.first { $0.id == b.type }
                return .init(block: b, typeName: t.map { $0.isDefault ? defaultName : $0.name } ?? defaultName)
            },
            newTypes: fileTypes.filter { !$0.isDefault && !known.contains($0.name.lowercased()) }.map(\.name),
            isBackup: raw["backup"] == .bool(true),
            hasSettings: incoming != nil || !fileTypes.isEmpty,
            problems: problems,
            clips: clipSlots.map { id, slots in
                let c = clipData[id]!
                return .init(id: id, name: c.name, ext: c.ext, data: c.data, slots: slots.joined(separator: ", "))
            },
            fileTypes: fileTypes,
            incoming: incoming.map { (volume: $0.0, meetings: $0.1) },
            rawBlocks: blocks)
    }

    /// Replaces your schedule with the file's, after backing up. With `applySettings`, the
    /// file's reminder settings are used too. Clips in `rejectClips` (ones that won't play)
    /// give way to the starting sound. Returns the backup's file name and the block count.
    @discardableResult
    public func applyImport(_ p: ImportPreview, applySettings: Bool, rejectClips: Set<String> = []) throws -> (backup: String, blocks: Int) {
        let backup: URL
        do { backup = try backupNow() } catch {
            throw DataError("DayFlow couldn't back up your current schedule, so nothing was changed. (\(error.localizedDescription))")
        }

        func fromFile<K>(_ reminder: Reminder, _ key: K, _ spec: (K) -> Specs.ReminderSpec) throws -> Reminder {
            guard reminder.sound.hasPrefix("custom:") else { return reminder }
            let fid = String(reminder.sound.dropFirst("custom:".count))
            var r = reminder
            if let clip = p.clips.first(where: { $0.id == fid }), !rejectClips.contains(fid) {
                r.sound = try installClip(name: clip.name, ext: clip.ext, data: clip.data).soundId
            } else {
                r.sound = spec(key).sound
            }
            return r
        }
        func typeFromFile(_ r: TypeReminders) throws -> TypeReminders {
            var out = r
            for k in TypeReminderKey.allCases { out[k] = try fromFile(r[k], k, Specs.spec) }
            return out
        }

        // The file's Default is your Default; other types match by name. A backup with its
        // settings applied replaces the list outright.
        var typeIds: [String: String] = [:]
        var list = types
        if p.isBackup && applySettings {
            var restored: [BlockType] = []
            for t in p.fileTypes {
                let mine = t.isDefault ? Specs.defaultType : t.id
                typeIds[t.id] = mine
                restored.append(BlockType(id: mine, name: t.name, reminders: try typeFromFile(t.reminders)))
            }
            if !restored.contains(where: \.isDefault) { restored.insert(typeOf(Specs.defaultType), at: 0) }
            list = restored
        } else {
            for t in p.fileTypes {
                var index = t.isDefault
                    ? list.firstIndex(where: \.isDefault)
                    : list.firstIndex { $0.name.lowercased() == t.name.lowercased() }
                if index == nil {
                    list.append(BlockType(id: UUID().uuidString.lowercased(), name: t.name))
                    index = list.count - 1
                }
                if applySettings { list[index!].reminders = try typeFromFile(t.reminders) }
                typeIds[t.id] = list[index!].id
            }
        }
        types = try Sanitize.types(list, isSound: isSound)
        try write(typesFile, types)

        try saveBlocks(p.rawBlocks.map { b in var c = b; c.type = typeIds[b.type] ?? Specs.defaultType; return c })

        if applySettings, let s = p.incoming {
            var next = settings
            next.volume = s.volume
            var m = s.meetings
            for k in MeetingReminderKey.allCases { m[k] = try fromFile(s.meetings[k], k, Specs.spec) }
            next.meetings = m
            try saveSettings(next)
        }
        return (backup.lastPathComponent, blocks.count)
    }
}

extension JSONValue {
    /// Only an actual JSON number (Number.isInteger in JavaScript doesn't accept "2").
    var numberValueIfNumber: Double? { if case .number(let n) = self { return n }; return nil }
}
