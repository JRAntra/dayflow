import Foundation
import CryptoKit

/// Your data on disk: the same four files as the Mac app, plus your clips and backups.
///
///     <dir>/schedule.json      { "blocks": [...] }
///     <dir>/block-types.json   [ { id, name, reminders } ]
///     <dir>/settings.json      the iPhone's settings
///     <dir>/sounds.json        [ { id, name, ext } ]
///     <dir>/sounds/<id>.<ext>  your clips
///     <backups>/schedule-YYYY-MM-DD-HHMMSS-mmm.json   the newest ten
public final class DataStore {
    public let dir: URL
    public let backupsDir: URL
    public internal(set) var blocks: [Block] = []
    public internal(set) var types: [BlockType] = []
    public internal(set) var settings = Settings()
    public internal(set) var clips: [CustomClip] = []

    public static let exportVersion = 2
    public static let maxImportBytes = 40 * 1024 * 1024
    public static let maxBackups = 10

    var scheduleFile: URL { dir.appendingPathComponent("schedule.json") }
    var typesFile: URL { dir.appendingPathComponent("block-types.json") }
    var settingsFile: URL { dir.appendingPathComponent("settings.json") }
    var clipsFile: URL { dir.appendingPathComponent("sounds.json") }
    public var clipsDir: URL { dir.appendingPathComponent("sounds", isDirectory: true) }

    public init(dir: URL, backupsDir: URL) {
        self.dir = dir
        self.backupsDir = backupsDir
        load()
    }

    /// Whether this store has ever been saved (false before the welcome screens finish).
    public var hasSchedule: Bool { FileManager.default.fileExists(atPath: scheduleFile.path) }

    public func load() {
        clips = (read(clipsFile)?.array ?? []).compactMap { c in
            guard let id = c["id"]?.stringValue, let name = c["name"]?.stringValue, let ext = c["ext"]?.stringValue else { return nil }
            return CustomClip(id: id, name: name, ext: ext)
        }
        types = (try? Sanitize.types(read(typesFile) ?? JSONValue.from(Specs.starterTypes()), isSound: isSound)) ?? Specs.starterTypes()
        settings = Sanitize.settings(read(settingsFile), isSound: isSound)
        let raw = read(scheduleFile)?["blocks"] ?? JSONValue.from(Specs.sampleSchedule())
        blocks = (try? Sanitize.blocks(raw, typeIds: Set(types.map(\.id)))) ?? []
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

    /// Starts the schedule: the sample, an empty one, or whatever was already there.
    public func startSchedule(sample: Bool) throws {
        try saveBlocks(sample ? Specs.sampleSchedule() : [])
        try write(typesFile, types)
    }

    public func saveBlocks(_ list: [Block]) throws {
        blocks = try Sanitize.blocks(list, typeIds: Set(types.map(\.id)))
        try write(scheduleFile, ["blocks": blocks])
    }

    /// Saves the type list; blocks whose type was deleted move to Default.
    public func saveTypes(_ list: [BlockType]) throws {
        let clean = try Sanitize.types(list, isSound: isSound)
        let ids = Set(clean.map(\.id))
        types = clean
        try write(typesFile, types)
        if blocks.contains(where: { !ids.contains($0.type) }) {
            try saveBlocks(blocks.map { b in var c = b; if !ids.contains(c.type) { c.type = Specs.defaultType }; return c })
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

    /// Copies a clip in. The same audio is only ever stored once; a different clip whose name
    /// is taken becomes "Name (2)".
    @discardableResult
    public func installClip(name: String, ext: String?, data: Data) throws -> CustomClip {
        let type = try Sanitize.clipType(name: name, ext: ext, bytes: data.count)
        let id = Self.clipHash(data)
        if let existing = clips.first(where: { $0.id == id }) { return existing }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let base = trimmed.isEmpty ? "Sound clip" : trimmed
        var label = base
        var n = 2
        while clips.contains(where: { $0.name == label }) { label = "\(base) (\(n))"; n += 1 }
        let clip = CustomClip(id: id, name: label, ext: type)
        try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        try data.write(to: clipURL(clip), options: .atomic)
        clips.append(clip)
        try write(clipsFile, clips)
        return clip
    }

    /// Deletes a clip; any reminder that used it goes back to that reminder's starting sound.
    /// Returns the names of the reminders that changed, e.g. "Focus · Heads-up".
    @discardableResult
    public func removeClip(_ id: String) throws -> [String] {
        guard let clip = clips.first(where: { $0.id == id }) else { return [] }
        try? FileManager.default.removeItem(at: clipURL(clip))
        clips.removeAll { $0.id == id }
        try write(clipsFile, clips)
        var reset: [String] = []
        for i in types.indices {
            for key in TypeReminderKey.allCases where types[i].reminders[key].sound == clip.soundId {
                types[i].reminders[key].sound = Specs.spec(key).sound
                reset.append("\(types[i].name) · \(Specs.spec(key).label)")
            }
        }
        for key in MeetingReminderKey.allCases where settings.meetings[key].sound == clip.soundId {
            settings.meetings[key].sound = Specs.spec(key).sound
            reset.append("Meetings · \(Specs.spec(key).label)")
        }
        if !reset.isEmpty {
            try write(typesFile, types)
            try write(settingsFile, settings)
        }
        return reset
    }

    // MARK: Export and backups

    /// A backup carries every block type, so importing it puts the type list back exactly; an
    /// ordinary export carries only the types its blocks use. Default is marked, so it matches
    /// the Default of whoever imports the file, whatever either is called.
    public func exportPayload(backup: Bool = false, now: Date = Date()) -> JSONValue {
        let usedTypes = Set(blocks.map(\.type))
        let list = types.filter { backup || usedTypes.contains($0.id) }
        let usedSounds = Set(list.flatMap { $0.reminders.all.map(\.sound) } + settings.meetings.all.map(\.sound))
        var typeValues: [JSONValue] = []
        for t in list {
            var o = JSONValue.from(t).object ?? [:]
            if t.isDefault { o["isDefault"] = .bool(true) }
            typeValues.append(.object(o))
        }
        var out: [String: JSONValue] = [
            "dayflowExport": .number(Double(Self.exportVersion)),
            "exportedAt": .string(ISO.string(now)),
            "schedule": .object(["blocks": JSONValue.from(blocks)]),
            "blockTypes": .array(typeValues),
            "settings": .object(["volume": .number(Double(settings.volume)), "meetings": JSONValue.from(settings.meetings)]),
            "clips": .array(clips.filter { usedSounds.contains($0.soundId) }.compactMap { c in
                guard let data = try? Data(contentsOf: clipURL(c)) else { return nil }
                return .object(["id": .string(c.id), "name": .string(c.name), "ext": .string(c.ext), "data": .string(data.base64EncodedString())])
            }),
        ]
        if backup { out["backup"] = .bool(true) }
        return .object(out)
    }

    public static func exportFileName(now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "DayFlow schedule %04d-%02d-%02d.json", c.year!, c.month!, c.day!)
    }

    /// Saves a payload to the backups folder, keeping the newest ten.
    @discardableResult
    public func writeBackup(_ payload: JSONValue, now: Date = Date(), calendar: Calendar = .current) throws -> URL {
        try FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: now)
        let name = String(format: "schedule-%04d-%02d-%02d-%02d%02d%02d-%03d.json",
                          c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, (c.nanosecond ?? 0) / 1_000_000)
        var url = backupsDir.appendingPathComponent(name)
        // Two backups in the same millisecond: keep both.
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupsDir.appendingPathComponent(name.replacingOccurrences(of: ".json", with: "-\(n).json")); n += 1
        }
        try JSONFile.encode(payload).write(to: url, options: .atomic)
        let old = backups().dropFirst(Self.maxBackups)
        for f in old { try? FileManager.default.removeItem(at: f) }
        return url
    }

    /// Backups, newest first.
    public func backups() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsDir.path)) ?? []
        return names.filter { $0.hasPrefix("schedule-") && $0.hasSuffix(".json") }.sorted().reversed()
            .map { backupsDir.appendingPathComponent($0) }
    }

    @discardableResult
    public func backupNow() throws -> URL { try writeBackup(exportPayload(backup: true)) }

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
