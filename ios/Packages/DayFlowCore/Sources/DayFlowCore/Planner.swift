import Foundation

/// A block placed on a particular date.
public struct DayBlock: Hashable, Identifiable, Sendable {
    public var block: Block
    public var start: Date
    public var end: Date
    public var id: String { block.id }
    public var title: String { block.title }
    public var type: String { block.type }
}

/// What a reminder is about.
public enum ReminderRole: String, Codable, Hashable, Sendable {
    case prep, start, warn, end, meetBefore, meetStart
    /// "Open DayFlow to keep your reminders coming", after the last reminder that fits.
    case notice
}

/// One notification to schedule.
public struct PlannedReminder: Hashable, Identifiable, Sendable {
    /// Every reminder that was merged into this one; the first is the notification's identifier.
    public var keys: [String]
    public var at: Date
    public var role: ReminderRole
    public var blockId: String?
    public var title: String
    public var body: String
    /// The sound id, or nil for no sound.
    public var sound: String?
    public var fade: Bool
    public var meeting: Meeting?
    /// The calendar day it belongs to, e.g. "2026-11-4"; notifications are grouped by it.
    public var day: String

    public var id: String { keys[0] }
    /// The sound to fall back on if this reminder's clip can't be used.
    public var fallbackSound: String? {
        switch role {
        case .prep: Specs.spec(.prep).sound
        case .start: Specs.spec(TypeReminderKey.start).sound
        case .warn: Specs.spec(.warn).sound
        case .end: Specs.spec(.end).sound
        case .meetBefore: Specs.spec(MeetingReminderKey.before).sound
        case .meetStart: Specs.spec(MeetingReminderKey.start).sound
        case .notice: nil
        }
    }
}

/// The reminders to schedule now: as many upcoming ones as fit, then the notice.
public struct ReminderWindow: Sendable {
    public var reminders: [PlannedReminder]
    public var notice: PlannedReminder?
    public var all: [PlannedReminder] { reminders + (notice.map { [$0] } ?? []) }
}

/// Works out every reminder, with the same wording and merge rules as the Mac app.
public struct Planner: Sendable {
    public var blocks: [Block]
    public var types: [BlockType]
    public var meetingReminders: MeetingReminders
    public var meetings: [Meeting]
    public var calendar: Calendar
    public var locale: Locale

    public init(blocks: [Block], types: [BlockType], meetingReminders: MeetingReminders, meetings: [Meeting] = [],
                calendar: Calendar = .current, locale: Locale = .current) {
        self.blocks = blocks; self.types = types; self.meetingReminders = meetingReminders; self.meetings = meetings
        self.calendar = calendar; self.locale = locale
    }

    /// iOS keeps at most 64 scheduled notifications for an app. This leaves one free, so the
    /// Test notification always has room, and one for the notice.
    public static let windowLimit = 62
    public static let horizonDays = 14

    public func typeOf(_ id: String) -> BlockType {
        types.first { $0.id == id } ?? types.first { $0.isDefault } ?? BlockType(id: Specs.defaultType, name: "Default")
    }

    /// The reminders a block uses: its own, or its type's.
    public func reminders(for b: Block) -> TypeReminders {
        b.hasOwnReminders ? (b.reminders ?? Specs.startingTypeReminders) : typeOf(b.type).reminders
    }

    /// "Focus", or "Own" for a block with its own reminders.
    public func typeName(for b: Block) -> String {
        b.hasOwnReminders ? Specs.ownTypeName : typeOf(b.type).name
    }

    // MARK: Times

    public func time(_ d: Date) -> String { TimeText.time(d, calendar: calendar, locale: locale) }

    public func dayKey(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    func at(_ day: Date, _ minutes: Int) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }

    /// The blocks (and moments) that run on this date, earliest first. A moment's end is its start,
    /// so it's never "the current block".
    public func blocksFor(_ date: Date) -> [DayBlock] {
        let dow = calendar.component(.weekday, from: date) - 1 // Calendar: 1 is Sunday
        let list = blocks.filter { $0.days.contains(dow) && ($0.isMoment || $0.endMin > $0.startMin) }
            .map { b -> DayBlock in
                var copy = b
                if !b.hasOwnReminders { copy.type = typeOf(b.type).id }
                return DayBlock(block: copy, start: at(date, b.startMin), end: at(date, b.endMin))
            }
        return list.enumerated().sorted { a, b in
            a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: One day's reminders

    public func events(on date: Date) -> [PlannedReminder] {
        let day = dayKey(date)
        let midnight = calendar.startOfDay(for: date)
        let all = blocksFor(date)
        // Blocks hand over to blocks; moments are reminded about separately, never merged.
        let list = all.filter { !$0.block.isMoment }
        var events: [PlannedReminder] = []

        for b in list {
            let r = reminders(for: b.block)
            let prev = list.first { $0.block.id != b.block.id && $0.end == b.start }
            let next = list.first { $0.block.id != b.block.id && $0.start >= b.end }
            func key(_ role: String) -> String { "\(day)|block|\(b.block.id)|\(role)" }
            func make(_ role: ReminderRole, _ at: Date, _ rem: Reminder, _ title: String, _ body: String) -> PlannedReminder {
                PlannedReminder(keys: [key(role.rawValue)], at: at, role: role, blockId: b.block.id, title: title, body: body,
                                sound: rem.sound, fade: rem.fade, meeting: nil, day: day)
            }

            let prepLead = r.prep.lead ?? Specs.defaultLead
            let prepAt = b.start.addingTimeInterval(-Double(prepLead) * 60)
            if r.prep.on && prepAt >= midnight {
                events.append(make(.prep, prepAt, r.prep, "In \(prepLead) min: \(b.title)", "Get ready. It starts at \(time(b.start))."))
            }
            if r.start.on {
                let body = prev.map { "\($0.title) is done. \(b.title) runs until \(time(b.end))." } ?? "Runs until \(time(b.end))."
                events.append(make(.start, b.start, r.start, "Now: \(b.title)", body))
            }
            let warnLead = r.warn.lead ?? Specs.defaultLead
            if r.warn.on && b.end.timeIntervalSince(b.start) > Double(warnLead) * 60 {
                let body = next.map { "Next: \($0.title) at \(time($0.start))." } ?? "This is your last block today."
                events.append(make(.warn, b.end.addingTimeInterval(-Double(warnLead) * 60), r.warn, "\(warnLead) min left: \(b.title)", body))
            }
            if r.end.on {
                var body = "That was your last block today."
                if let next {
                    body = next.start == b.end ? "\(next.title) starts now." : "Free until \(next.title) at \(time(next.start))."
                }
                events.append(make(.end, b.end, r.end, "Time's up: \(b.title)", body))
            }
        }

        var merged = mergeSameMoment(events, list)

        // Moments: "In 5 min: Take medicine" and "Now: Take medicine", with the block they fall in.
        for m in all where m.block.isMoment {
            let r = reminders(for: m.block)
            let during = list.first { $0.start <= m.start && m.start < $0.end }
            func key(_ role: String) -> String { "\(day)|moment|\(m.block.id)|\(role)" }
            let lead = r.prep.lead ?? Specs.defaultLead
            let prepAt = m.start.addingTimeInterval(-Double(lead) * 60)
            if r.prep.on && prepAt >= midnight {
                merged.append(PlannedReminder(keys: [key("prep")], at: prepAt, role: .prep, blockId: m.block.id,
                                              title: "In \(lead) min: \(m.title)", body: "Get ready. It's at \(time(m.start)).",
                                              sound: r.prep.sound, fade: r.prep.fade, meeting: nil, day: day))
            }
            if r.start.on {
                let body = during.map { "It's \(time(m.start)), during \($0.title)." } ?? "It's \(time(m.start))."
                merged.append(PlannedReminder(keys: [key("start")], at: m.start, role: .start, blockId: m.block.id,
                                              title: "Now: \(m.title)", body: body, sound: r.start.sound, fade: r.start.fade,
                                              meeting: nil, day: day))
            }
        }

        let m = meetingReminders
        for mt in meetings where dayKey(mt.start) == day {
            let startKey = ISO.string(mt.start)
            if m.before.on {
                let lead = m.before.lead ?? Specs.defaultLead
                merged.append(PlannedReminder(
                    keys: ["\(day)|meet|\(mt.id)|\(startKey)|lead"], at: mt.start.addingTimeInterval(-Double(lead) * 60),
                    role: .meetBefore, blockId: nil, title: "In \(lead) min: \(mt.title)",
                    body: "Starts at \(time(mt.start)).\(mt.url != nil ? " Tap to join." : "")",
                    sound: m.before.sound, fade: m.before.fade, meeting: mt, day: day))
            }
            if m.start.on {
                merged.append(PlannedReminder(
                    keys: ["\(day)|meet|\(mt.id)|\(startKey)|start"], at: mt.start, role: .meetStart, blockId: nil,
                    title: "Starting now: \(mt.title)", body: mt.url != nil ? "Tap to join." : "Started at \(time(mt.start)).",
                    sound: m.start.sound, fade: m.start.fade, meeting: mt, day: day))
            }
        }
        return merged
    }

    /// Block reminders at the same moment become one, and the block that's coming up wins: its
    /// sound plays. "Now: Email. Deep work is done." at a hand-off, and "5 min left: Deep work.
    /// Next: Email at 11:30" when a heads-up meets the next block's preparation.
    func mergeSameMoment(_ events: [PlannedReminder], _ list: [DayBlock]) -> [PlannedReminder] {
        var order: [Date] = []
        var groups: [Date: [PlannedReminder]] = [:]
        for ev in events {
            if groups[ev.at] == nil { order.append(ev.at) }
            groups[ev.at, default: []].append(ev)
        }
        return order.map { t in
            let group = groups[t]!
            let keys = group.flatMap(\.keys)
            func find(_ role: ReminderRole) -> PlannedReminder? { group.first { $0.role == role } }
            if var start = find(.start) { start.keys = keys; return start }
            let outgoing = find(.end) ?? find(.warn)
            if var prep = find(.prep), let outgoing {
                let b = list.first { $0.block.id == prep.blockId }
                prep.keys = keys
                prep.title = outgoing.title
                prep.body = "Next: \(b?.title ?? "") at \(b.map { time($0.start) } ?? "")."
                return prep
            }
            var one = find(.prep) ?? outgoing!
            one.keys = keys
            return one
        }
    }

    // MARK: The rolling window

    /// The next reminders after `now`, up to `limit`, looking up to `horizonDays` ahead. Reminders
    /// during a pause are left out. If more reminders would follow, a quiet notice comes a minute
    /// after the last one, asking you to open DayFlow.
    public func window(from now: Date, pausedUntil: Date? = nil, limit: Int = Planner.windowLimit,
                       horizonDays: Int = Planner.horizonDays, sound: Bool = true) -> ReminderWindow {
        var upcoming: [PlannedReminder] = []
        var more = false
        let today = calendar.startOfDay(for: now)
        outer: for offset in 0...horizonDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let kept: [PlannedReminder] = events(on: date).filter { ev in
                if ev.at <= now { return false }
                if let p = pausedUntil, ev.at < p { return false }
                return true
            }
            let day: [PlannedReminder] = kept.enumerated()
                .sorted { (a: (offset: Int, element: PlannedReminder), b: (offset: Int, element: PlannedReminder)) -> Bool in
                    a.element.at != b.element.at ? a.element.at < b.element.at : a.offset < b.offset
                }
                .map { $0.element }
            for var ev in day {
                if upcoming.count == limit { more = true; break outer }
                if !sound { ev.sound = nil }
                upcoming.append(ev)
            }
        }
        // Blocks repeat every week, so there are always more after the horizon if any exist.
        if !more && !upcoming.isEmpty { more = true }
        var notice: PlannedReminder?
        if more, let last = upcoming.last {
            notice = PlannedReminder(
                keys: ["notice|\(ISO.string(last.at))"], at: last.at.addingTimeInterval(60), role: .notice, blockId: nil,
                title: "Open DayFlow to keep your reminders coming",
                body: "DayFlow schedules your reminders a few days ahead. Opening it schedules the next ones.",
                sound: nil, fade: false, meeting: nil, day: dayKey(last.at))
        }
        return ReminderWindow(reminders: upcoming, notice: notice)
    }
}

/// Times as the Mac shows them, e.g. "9:20 AM".
public enum TimeText {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    public static func time(_ d: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let key = "\(locale.identifier)|\(calendar.timeZone.identifier)"
        lock.lock(); defer { lock.unlock() }
        let f = cache[key] ?? {
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate("jmm")
            cache[key] = f
            return f
        }()
        return f.string(from: d)
    }

    /// "9:20 – 11:30 AM" when both ends share AM/PM, otherwise "11:30 AM – 1:00 PM".
    public static func range(_ a: Date, _ b: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let A = time(a, calendar: calendar, locale: locale), B = time(b, calendar: calendar, locale: locale)
        func suffix(_ s: String) -> String? {
            guard let r = s.range(of: #"\s?[AaPp]\.?[Mm]\.?$"#, options: .regularExpression) else { return nil }
            return String(s[r])
        }
        if let sa = suffix(A), sa == suffix(B) { return "\(A.dropLast(sa.count)) – \(B)" }
        return "\(A) – \(B)"
    }

    /// "1:05:09" or "4:09", as on the dial.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "2 h 10 min", "45 min", "1 h".
    public static func length(minutes d: Int) -> String {
        guard d > 0 else { return "" }
        let h = d / 60, m = d % 60
        return h > 0 ? "\(h) h\(m > 0 ? " \(m) min" : "")" : "\(d) min"
    }
}

enum ISO {
    static func string(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
