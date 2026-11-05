import Foundation

/// A problem with data, with a message that can be shown as it is.
public struct DataError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The cleaning rules from src/main.js. Anything missing or unusable takes its starting value.
public enum Sanitize {
    /// JavaScript's `clamp(v, lo, hi, d)`: a usable number is rounded into range, anything else is d.
    static func clamp(_ v: JSONValue?, _ lo: Int, _ hi: Int, _ d: Int) -> Int {
        guard let v, let n = v.numberValue else { return d }
        return min(hi, max(lo, Int(n.rounded(.toNearestOrAwayFromZero))))
    }

    /// JavaScript's `flag(v, d)`: missing means d, anything else is its truthiness.
    static func flag(_ v: JSONValue?, _ d: Bool) -> Bool {
        guard let v else { return d }
        return v.truthy
    }

    private static func reminder(_ r: JSONValue?, _ s: Specs.ReminderSpec, isSound: (String) -> Bool) -> Reminder {
        let sound = r?["sound"]?.string.flatMap { isSound($0) ? $0 : nil } ?? s.sound
        return Reminder(on: flag(r?["on"], s.on), sound: sound, fade: flag(r?["fade"], false),
                        lead: s.hasLead ? clamp(r?["lead"], 1, 60, Specs.defaultLead) : nil)
    }

    public static func typeReminders(_ v: JSONValue?, isSound: (String) -> Bool) -> TypeReminders {
        TypeReminders(prep: reminder(v?["prep"], Specs.spec(.prep), isSound: isSound),
                      start: reminder(v?["start"], Specs.spec(TypeReminderKey.start), isSound: isSound),
                      warn: reminder(v?["warn"], Specs.spec(.warn), isSound: isSound),
                      end: reminder(v?["end"], Specs.spec(.end), isSound: isSound))
    }

    public static func meetingReminders(_ v: JSONValue?, isSound: (String) -> Bool) -> MeetingReminders {
        MeetingReminders(before: reminder(v?["before"], Specs.spec(MeetingReminderKey.before), isSound: isSound),
                         start: reminder(v?["start"], Specs.spec(MeetingReminderKey.start), isSound: isSound))
    }

    /// Names must be unique (ignoring case), every name is needed, and Default comes first.
    public static func types(_ v: JSONValue?, isSound: (String) -> Bool) throws -> [BlockType] {
        guard let list = v?.array else { throw DataError("Block types must be a list.") }
        guard list.contains(where: { $0["id"]?.stringValue == Specs.defaultType }) else {
            throw DataError("The Default type can't be deleted.")
        }
        var seen = Set<String>()
        var out: [BlockType] = []
        for t in list {
            let name = String((t["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            if name.isEmpty { throw DataError("Every block type needs a name.") }
            if seen.contains(name.lowercased()) { throw DataError("There are two block types called \"\(name)\".") }
            seen.insert(name.lowercased())
            let id = t["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.lowercased()
            out.append(BlockType(id: id, name: name, reminders: typeReminders(t["reminders"], isSound: isSound)))
        }
        return defaultFirst(out)
    }

    /// The same checks for types already in memory, e.g. after editing on the Block types page.
    public static func types(_ list: [BlockType], isSound: (String) -> Bool) throws -> [BlockType] {
        try types(JSONValue.from(list), isSound: isSound)
    }

    static func defaultFirst(_ list: [BlockType]) -> [BlockType] {
        list.filter(\.isDefault) + list.filter { !$0.isDefault }
    }

    /// Every block needs a name, a valid start, an end after it (or no end, for a moment) and a
    /// type that exists; an unknown type becomes `fallback`. A block with type "own" keeps its own
    /// reminders (it falls back too if it has none). Days are cleaned and sorted, blocks sorted by start.
    public static func blocks(_ v: JSONValue?, typeIds: Set<String>, fallback: String = Specs.defaultType,
                              isSound: (String) -> Bool = { _ in true }) throws -> [Block] {
        guard let list = v?.array else { throw DataError("Schedule must be a list.") }
        var out: [Block] = []
        for (i, b) in list.enumerated() {
            let title = String((b["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            if title.isEmpty { throw DataError("Block \(i + 1) needs a name.") }
            guard let start = b["start"]?.string, let s = HHMM.minutes(start) else { throw DataError("\"\(title)\" has an invalid time.") }
            // No end (missing, null or empty) makes a moment.
            let rawEnd = b["end"]?.string ?? ""
            if !rawEnd.isEmpty {
                guard let e = HHMM.minutes(rawEnd) else { throw DataError("\"\(title)\" has an invalid time.") }
                if e <= s { throw DataError("\"\(title)\" must end after it starts.") }
            }
            let days = Array(Set((b["days"]?.array ?? []).compactMap { $0.numberValue }
                .filter { $0 == $0.rounded() && $0 >= 0 && $0 <= 6 }.map { Int($0) })).sorted()
            var type = b["type"]?.stringValue.flatMap { typeIds.contains($0) ? $0 : nil } ?? fallback
            var own: TypeReminders?
            if b["type"]?.stringValue == Specs.ownType, let r = b["reminders"], r.object != nil {
                type = Specs.ownType
                own = typeReminders(r, isSound: isSound)
            }
            let id = b["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.lowercased()
            let rings = flag(b["ringOnSilent"], false)
            out.append(Block(id: id, title: title, start: start, end: rawEnd, days: days, type: type, reminders: own,
                             ringsOnSilent: rings))
        }
        return sortByStart(out)
    }

    public static func blocks(_ list: [Block], typeIds: Set<String>, isSound: (String) -> Bool = { _ in true }) throws -> [Block] {
        try blocks(JSONValue.from(list), typeIds: typeIds, isSound: isSound)
    }

    /// Stable sort by start time, like Array.prototype.sort in JavaScript.
    public static func sortByStart(_ list: [Block]) -> [Block] {
        list.enumerated().sorted { a, b in
            a.element.startMin != b.element.startMin ? a.element.startMin < b.element.startMin : a.offset < b.offset
        }.map(\.element)
    }

    /// The iPhone's settings file. Missing values keep `prev`.
    public static func settings(_ v: JSONValue?, prev: Settings = Settings(), isSound: (String) -> Bool) -> Settings {
        var s = prev
        s.sound = flag(v?["sound"], prev.sound)
        s.volume = clamp(v?["volume"], 0, 100, prev.volume)
        if let m = v?["meetings"], m.object != nil { s.meetings = meetingReminders(m, isSound: isSound) }
        s.liveActivity = flag(v?["liveActivity"], prev.liveActivity)
        if let c = v?["calendars"] {
            s.calendars = c.array.map { $0.compactMap(\.string) }
        }
        if let p = v?["pausedUntil"] {
            s.pausedUntil = p.numberValue.map { Date(timeIntervalSinceReferenceDate: $0) }
            if case .null = p { s.pausedUntil = nil }
        }
        s.remindersOff = flag(v?["remindersOff"], prev.remindersOff)
        s.onboarded = flag(v?["onboarded"], prev.onboarded)
        return s
    }

    /// A clip's file type, checked the way the Mac checks it.
    public static func clipType(name: String, ext: String?, bytes: Int) throws -> String {
        let type = (ext ?? "").lowercased()
        if !Specs.clipTypes.contains(type) { throw DataError("\"\(name)\" isn't an mp3, wav, m4a, aac or ogg file.") }
        if bytes == 0 { throw DataError("\"\(name)\" is empty.") }
        if bytes > Specs.maxClipBytes { throw DataError("\"\(name)\" is larger than 5 MB.") }
        return type
    }
}

/// Version 1 files set one sound per kind of reminder, and types could say "same as default".
/// This turns that into types with four reminders without changing anything you'd hear,
/// exactly as the Mac's upgradeV1 does. Sounds are passed through; the caller checks them.
public enum UpgradeV1 {
    public struct Result {
        public var types: [JSONValue]
        public var blocks: [JSONValue]
        public var meetings: JSONValue
    }

    public static func run(settings s: JSONValue?, blockTypes oldTypes: JSONValue?, blocks: [JSONValue]) -> Result {
        func pick(_ v: JSONValue?, _ d: String) -> String {
            if let str = v?.string, !str.isEmpty, str != "default" { return str }
            return d
        }
        let old = s?["sounds"]
        let gStart = pick(old?["transition"], Specs.spec(TypeReminderKey.start).sound)
        let gWarn = pick(old?["warning"], Specs.spec(.warn).sound)
        let gEnd = pick(old?["end"], Specs.spec(.end).sound)
        let gMeeting = pick(old?["meeting"], Specs.spec(MeetingReminderKey.start).sound)
        let warn = Sanitize.clamp(s?["warnBeforeEndMin"], 0, 60, Specs.defaultLead) // 0 used to mean "no heads-up"
        let lead5 = JSONValue.number(Double(Specs.defaultLead))
        func reminders(_ sounds: JSONValue?) -> JSONValue {
            .object([
                "prep": .object(["on": .bool(false), "lead": lead5, "sound": .string(Specs.spec(.prep).sound)]),
                "start": .object(["on": .bool(true), "sound": .string(pick(sounds?["transition"], gStart))]),
                "warn": .object(["on": .bool(warn > 0), "lead": .number(Double(warn > 0 ? warn : Specs.defaultLead)),
                                 "sound": .string(pick(sounds?["warning"], gWarn))]),
                "end": .object(["on": .bool(true), "sound": .string(pick(sounds?["end"], gEnd))]),
            ])
        }
        let source: [JSONValue] = oldTypes?.array
            ?? Specs.starterNames.map { .object(["id": .string($0.lowercased()), "name": .string($0)]) }
        let list = source.filter { !(($0["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        let trimmedName = { (t: JSONValue) in (nameOf(t)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let namedIndex = list.firstIndex { trimmedName($0).lowercased() == "default" }
        let named = namedIndex.map { list[$0] }
        var types: [JSONValue] = [.object([
            "id": .string(Specs.defaultType),
            "name": .string(named.map(trimmedName) ?? "Default"),
            "isDefault": .bool(true),
            "reminders": reminders(named?["sounds"]),
        ])]
        var ids: [String: String] = [:]
        for (i, t) in list.enumerated() {
            let tid = t["id"]?.stringValue ?? ""
            if i == namedIndex { ids[tid] = Specs.defaultType; continue }
            let id = tid == Specs.defaultType ? UUID().uuidString.lowercased() : tid
            ids[tid] = id
            types.append(.object(["id": .string(id), "name": .string(trimmedName(t)), "reminders": reminders(t["sounds"])]))
        }
        let lead = Sanitize.clamp(s?["meetingLeadMin"], 0, 60, Specs.defaultLead)
        let newBlocks: [JSONValue] = blocks.map { b in
            var o = b.object ?? [:]
            o["type"] = .string(ids[b["type"]?.stringValue ?? "\u{0}"] ?? Specs.defaultType)
            return .object(o)
        }
        let meetings: JSONValue = .object([
            "before": .object(["on": .bool(lead > 0), "lead": .number(Double(lead > 0 ? lead : Specs.defaultLead)), "sound": .string(gMeeting)]),
            "start": .object(["on": .bool(true), "sound": .string(gMeeting)]),
        ])
        return Result(types: types, blocks: newBlocks, meetings: meetings)
    }

    private static func nameOf(_ t: JSONValue) -> String { t["name"]?.stringValue ?? "" }
}
