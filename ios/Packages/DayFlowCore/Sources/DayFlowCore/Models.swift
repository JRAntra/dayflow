import Foundation

// The data model. Field names and shapes match the Mac app's files (schedule.json,
// block-types.json, settings.json, sounds.json), so export files move between them unchanged.

/// One item of your weekly plan. Times are "HH:mm" in local time; days are 0 (Sunday) to 6.
///
/// There are two kinds:
/// - An **event** has an empty `end`: it happens at its start time and rings once, with its
///   own `alert`. On iPhone it always rings as an alarm. Its `type` is "event".
///   An event made by a repeat ("Drink water every 30 min") carries that repeat in `series`.
/// - A **block** has an end and its block type's four reminders. With `ringOnSilent` each
///   reminder rings as an alarm on iPhone.
public struct Block: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: String
    public var end: String
    public var days: [Int]
    public var type: String
    /// true, or left out of the file when off.
    public var ringOnSilent: Bool?
    /// An event's one reminder: its sound(s) and fade.
    public var alert: Reminder?
    /// The repeat that made this event, if any.
    public var series: RepeatRule?

    public init(id: String = Block.newId(), title: String, start: String, end: String, days: [Int], type: String,
                ringsOnSilent: Bool = false, alert: Reminder? = nil, series: RepeatRule? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.days = days; self.type = type
        self.ringOnSilent = ringsOnSilent ? true : nil
        self.alert = alert
        self.series = series
    }

    /// A new event, ringing with `alert`.
    public static func event(id: String = Block.newId(), title: String, start: String, days: [Int], alert: Reminder,
                             series: RepeatRule? = nil) -> Block {
        Block(id: id, title: title, start: start, end: "", days: days, type: Specs.eventType, alert: alert, series: series)
    }

    /// "Ring even on silent": on iPhone each reminder rings as an alarm, until you tap Stop.
    /// Events always ring as alarms.
    public var ringsOnSilent: Bool {
        get { ringOnSilent == true }
        set { ringOnSilent = newValue ? true : nil }
    }

    /// Only a start time: it happens at that moment and rings once.
    public var isEvent: Bool { end.isEmpty }
    /// The old name for an event.
    public var isMoment: Bool { isEvent }
    /// Made by a repeat.
    public var isRepeat: Bool { series != nil }
    /// An event's reminder, or the starting one if it has none.
    public var eventAlert: Reminder {
        get { alert ?? Specs.startingEventAlert }
        set { alert = newValue }
    }

    /// Ids look like the Mac's: "b" + base-36 time + 4 random characters.
    public static func newId(now: Date = Date()) -> String {
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let tail = String((0..<4).map { _ in chars.randomElement()! })
        return "b" + String(ms, radix: 36) + tail
    }

    public var startMin: Int { HHMM.minutes(start) ?? 0 }
    /// A moment "ends" where it starts.
    public var endMin: Int { isMoment ? startMin : (HHMM.minutes(end) ?? 0) }
    public var lengthMin: Int { endMin - startMin }
}

/// The rule a repeated event was made by: every `every` minutes from `first` to `last`
/// ("HH:mm"), `last` included when the gap lands on it. Every event it made carries the same
/// rule; `id` ties them together.
public struct RepeatRule: Codable, Hashable, Sendable {
    public var id: String
    public var first: String
    public var last: String
    public var every: Int

    public init(id: String = RepeatRule.newId(), first: String, last: String, every: Int) {
        self.id = id; self.first = first; self.last = last; self.every = every
    }

    public static func newId(now: Date = Date()) -> String { "r" + Block.newId(now: now).dropFirst() }
}

/// One reminder: whether it's on, its sound, whether it fades in, and (for the ones that come
/// early) how many minutes ahead.
///
/// A reminder can have several sounds; each time it rings one is picked at random, never the
/// one it played last. `sound` is always the first of them, so a file read by an older DayFlow
/// still has a sound; `sounds` lists them all, and is left out when there's only one.
public struct Reminder: Codable, Hashable, Sendable {
    public var on: Bool
    public var sound: String
    public var fade: Bool
    public var lead: Int?
    public var sounds: [String]?

    public init(on: Bool, sound: String, fade: Bool = false, lead: Int? = nil, sounds: [String]? = nil) {
        self.on = on; self.sound = sound; self.fade = fade; self.lead = lead
        self.sounds = nil
        if let sounds { choices = sounds }
    }

    /// Every sound it can play, at least one.
    public var choices: [String] {
        get { (sounds?.isEmpty == false ? sounds! : [sound]) }
        set {
            var seen = Set<String>()
            let list = newValue.filter { seen.insert($0).inserted }
            guard let first = list.first else { return }
            sound = first
            sounds = list.count > 1 ? list : nil
        }
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
