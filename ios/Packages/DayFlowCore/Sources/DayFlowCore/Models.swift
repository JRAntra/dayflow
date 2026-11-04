import Foundation

// The data model. Field names and shapes match the Mac app's files (schedule.json,
// block-types.json, settings.json, sounds.json), so export files move between them unchanged.

/// One block of your weekly plan. Times are "HH:mm" in local time; days are 0 (Sunday) to 6.
public struct Block: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: String
    public var end: String
    public var days: [Int]
    public var type: String

    public init(id: String = Block.newId(), title: String, start: String, end: String, days: [Int], type: String) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.days = days; self.type = type
    }

    /// Ids look like the Mac's: "b" + base-36 time + 4 random characters.
    public static func newId(now: Date = Date()) -> String {
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let tail = String((0..<4).map { _ in chars.randomElement()! })
        return "b" + String(ms, radix: 36) + tail
    }

    public var startMin: Int { HHMM.minutes(start) ?? 0 }
    public var endMin: Int { HHMM.minutes(end) ?? 0 }
    public var lengthMin: Int { endMin - startMin }
}

/// One reminder: whether it's on, its sound, whether it fades in, and (for the ones that come
/// early) how many minutes ahead.
public struct Reminder: Codable, Hashable, Sendable {
    public var on: Bool
    public var sound: String
    public var fade: Bool
    public var lead: Int?

    public init(on: Bool, sound: String, fade: Bool = false, lead: Int? = nil) {
        self.on = on; self.sound = sound; self.fade = fade; self.lead = lead
    }
}

/// The four reminders every block type has.
public struct TypeReminders: Codable, Hashable, Sendable {
    public var prep: Reminder
    public var start: Reminder
    public var warn: Reminder
    public var end: Reminder

    public init(prep: Reminder, start: Reminder, warn: Reminder, end: Reminder) {
        self.prep = prep; self.start = start; self.warn = warn; self.end = end
    }

    public subscript(key: TypeReminderKey) -> Reminder {
        get {
            switch key { case .prep: prep; case .start: start; case .warn: warn; case .end: end }
        }
        set {
            switch key { case .prep: prep = newValue; case .start: start = newValue; case .warn: warn = newValue; case .end: end = newValue }
        }
    }

    public var all: [Reminder] { [prep, start, warn, end] }
}

/// The two reminders for meetings.
public struct MeetingReminders: Codable, Hashable, Sendable {
    public var before: Reminder
    public var start: Reminder

    public init(before: Reminder, start: Reminder) { self.before = before; self.start = start }

    public subscript(key: MeetingReminderKey) -> Reminder {
        get { key == .before ? before : start }
        set { if key == .before { before = newValue } else { start = newValue } }
    }

    public var all: [Reminder] { [before, start] }
}

public enum TypeReminderKey: String, CaseIterable, Sendable { case prep, start, warn, end }
public enum MeetingReminderKey: String, CaseIterable, Sendable { case before, start }

/// A block type. Every block has one; Default (id "default") can be renamed but never deleted.
public struct BlockType: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var reminders: TypeReminders

    public init(id: String, name: String, reminders: TypeReminders = Specs.startingTypeReminders) {
        self.id = id; self.name = name; self.reminders = reminders
    }

    public var isDefault: Bool { id == Specs.defaultType }
}

/// One of your own sound clips. The id is a hash of the audio, so reminders and export files
/// keep finding it whatever the file is called; `file` is its file in the Clips folder, e.g.
/// "Ding.mp3". (Clips saved before the Clips folder existed have no `file` and are moved in.)
public struct CustomClip: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var ext: String
    public var file: String?

    public init(id: String, name: String, ext: String, file: String? = nil) {
        self.id = id; self.name = name; self.ext = ext; self.file = file
    }

    public var soundId: String { "custom:\(id)" }
    public var fileName: String { file ?? "\(id).\(ext)" }
}

/// The iPhone's settings. `sound`, `volume` and `meetings` mean the same as on the Mac;
/// the rest only exist on the iPhone.
public struct Settings: Codable, Hashable, Sendable {
    public var sound: Bool
    public var volume: Int
    public var meetings: MeetingReminders
    /// Show the current block on the Lock Screen and in the Dynamic Island.
    public var liveActivity: Bool
    /// The calendars whose events count as meetings (EventKit identifiers). nil until you
    /// first allow calendar access, when it becomes your default calendar.
    public var calendars: [String]?
    /// Reminders are turned off until this moment (For 1 hour, For 24 hours).
    public var pausedUntil: Date?
    /// Reminders are turned off until you turn them back on.
    public var remindersOff: Bool
    /// The welcome screens have been seen.
    public var onboarded: Bool

    public init(sound: Bool = true, volume: Int = 80, meetings: MeetingReminders = Specs.startingMeetingReminders,
                liveActivity: Bool = true, calendars: [String]? = nil, pausedUntil: Date? = nil, remindersOff: Bool = false,
                onboarded: Bool = false) {
        self.sound = sound; self.volume = volume; self.meetings = meetings; self.liveActivity = liveActivity
        self.calendars = calendars; self.pausedUntil = pausedUntil; self.remindersOff = remindersOff; self.onboarded = onboarded
    }

    /// When reminders come back: `.distantFuture` for "until I turn them on", nil when they're on.
    public func offUntil(at now: Date) -> Date? {
        if remindersOff { return .distantFuture }
        return pausedUntil.flatMap { now < $0 ? $0 : nil }
    }

    public func isOff(at now: Date) -> Bool { offUntil(at: now) != nil }

    /// Kept for older callers: the same as `isOff`.
    public func isPaused(at now: Date) -> Bool { isOff(at: now) }
}

/// A timed calendar event that counts as a meeting.
public struct Meeting: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    /// The video link (Meet, Zoom, Teams, Webex), when one was found.
    public var url: URL?

    public init(id: String, title: String, start: Date, end: Date, url: URL? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.url = url
    }
}

/// A built-in sound: a clip shipped with the app.
public struct BuiltinSound: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
}
