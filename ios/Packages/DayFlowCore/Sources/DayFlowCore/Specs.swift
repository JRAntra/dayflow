import Foundation

/// The starting values and fixed lists, the same as the Mac app's.
public enum Specs {
    public static let defaultType = "default"
    /// The type of a block with its own reminders (Own reminders in the Type menu).
    public static let ownType = "own"
    public static let ownTypeName = "Own"
    public static let defaultLead = 5

    /// The built-in sounds, in menu order. The files are assets/sounds/<id>.mp3 in the repo.
    public static let builtinSounds: [BuiltinSound] = [
        ("notification-bell", "Soft bell"),
        ("alert-bells-echo", "Echo bells"),
        ("fairy-bell-bless", "Fairy bell"),
        ("christmas-magic-bell", "Magic bell"),
        ("bells-of-mystery", "Mystery bells"),
        ("magic-glitter", "Magic glitter"),
        ("fantasy-bells", "Fantasy bells"),
        ("flute-notification", "Flute"),
        ("elevator-announcement-bells", "Elevator bells"),
        ("elegant-door-announcement", "Elegant chime"),
        ("airport-announcement-ding", "Airport ding"),
        ("melodic-classic-door-bell", "Classic door bell"),
        ("doorbell-tone", "Doorbell tone"),
        ("clock-bells-hour-signal", "Hour bells"),
        ("class-bell", "Class bell"),
        ("sleigh-bells", "Sleigh bells"),
        ("classic-alarm", "Classic alarm"),
        ("rooster-crowing", "Rooster crowing"),
    ].map { BuiltinSound(id: $0.0, name: $0.1) }
    public static let builtinIds = Set(builtinSounds.map(\.id))

    public static let clipTypes = ["mp3", "wav", "m4a", "aac", "ogg"]
    public static let maxClipBytes = 5 * 1024 * 1024
    public static let maxClipSeconds = 30.0

    /// Labels and starting values for a type's four reminders.
    public struct ReminderSpec: Sendable {
        public let label: String
        public let on: Bool
        public let hasLead: Bool
        public let sound: String
        public var starting: Reminder { Reminder(on: on, sound: sound, fade: false, lead: hasLead ? Specs.defaultLead : nil) }
    }

    public static func spec(_ key: TypeReminderKey) -> ReminderSpec {
        switch key {
        case .prep: ReminderSpec(label: "Start preparation", on: false, hasLead: true, sound: "fairy-bell-bless")
        case .start: ReminderSpec(label: "Start", on: true, hasLead: false, sound: "elevator-announcement-bells")
        case .warn: ReminderSpec(label: "Heads-up", on: true, hasLead: true, sound: "notification-bell")
        case .end: ReminderSpec(label: "Time's up", on: true, hasLead: false, sound: "clock-bells-hour-signal")
        }
    }

    public static func spec(_ key: MeetingReminderKey) -> ReminderSpec {
        switch key {
        case .before: ReminderSpec(label: "Before it starts", on: true, hasLead: true, sound: "airport-announcement-ding")
        case .start: ReminderSpec(label: "Starting now", on: true, hasLead: false, sound: "elegant-door-announcement")
        }
    }

    public static var startingTypeReminders: TypeReminders {
        TypeReminders(prep: spec(.prep).starting, start: spec(TypeReminderKey.start).starting, warn: spec(.warn).starting, end: spec(.end).starting)
    }

    public static var startingMeetingReminders: MeetingReminders {
        MeetingReminders(before: spec(MeetingReminderKey.before).starting, start: spec(MeetingReminderKey.start).starting)
    }

    public static let starterNames = ["Focus", "Break", "Admin", "Meal"]

    public static func starterTypes() -> [BlockType] {
        [BlockType(id: defaultType, name: "Default")] + starterNames.map { BlockType(id: $0.lowercased(), name: $0) }
    }

    public static let weekdays = [1, 2, 3, 4, 5]

    /// The sample weekday schedule, the same eight blocks as the Mac's.
    public static func sampleSchedule() -> [Block] {
        [
            ("b1", "Plan the day", "09:00", "09:20"),
            ("b2", "Deep work", "09:20", "11:30"),
            ("b3", "Email and messages", "11:30", "12:00"),
            ("b4", "Lunch", "12:00", "13:00"),
            ("b5", "Focus block", "13:00", "15:00"),
            ("b6", "Walk and stretch", "15:00", "15:15"),
            ("b7", "Admin and follow-ups", "15:15", "17:00"),
            ("b8", "Shut down for the day", "17:00", "17:15"),
        ].map { Block(id: $0.0, title: $0.1, start: $0.2, end: $0.3, days: weekdays, type: defaultType) }
    }

    public static func soundName(_ id: String, clips: [CustomClip]) -> String {
        if let b = builtinSounds.first(where: { $0.id == id }) { return b.name }
        if let c = clips.first(where: { $0.soundId == id }) { return c.name }
        return "Unknown sound"
    }
}

/// "HH:mm" times.
public enum HHMM {
    /// Minutes since midnight, or nil if the text isn't a 24-hour "HH:mm" time.
    public static func minutes(_ s: String) -> Int? {
        let p = s.split(separator: ":", omittingEmptySubsequences: false)
        guard s.count == 5, p.count == 2, p[0].count == 2, p[1].count == 2,
              p[0].allSatisfy(\.isASCII), p[1].allSatisfy(\.isASCII),
              let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func string(_ minutes: Int) -> String {
        let m = min(max(minutes, 0), 23 * 60 + 59)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static func isValid(_ s: String) -> Bool { minutes(s) != nil }
}
