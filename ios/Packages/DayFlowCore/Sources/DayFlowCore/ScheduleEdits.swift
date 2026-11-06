import Foundation

/// The rules for editing the schedule, shared by the list, the edit sheet and the day view.
public enum ScheduleEdits {
    public static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]
    public static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let shortDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// Monday first, as the day strip shows them.
    public static let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    /// The smallest block the day view lets you make, and how far drags snap.
    public static let minimumMinutes = 5
    public static let snapMinutes = 5

    /// The first problem that stops a block being saved, or nil. Overlaps don't stop it.
    public static func problem(_ b: Block) -> String? {
        if b.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return b.isEvent ? "Give this event a name." : "Give this block a name." }
        guard let s = HHMM.minutes(b.start) else { return "Set a start time." }
        if !b.isMoment {
            guard let e = HHMM.minutes(b.end) else { return "Set a start and end time." }
            if e <= s { return "End time must be after the start time." }
        }
        if b.days.isEmpty { return b.isEvent ? "Pick at least one day, or this event never rings." : "Pick at least one day, or this block never runs." }
        return nil
    }

    // MARK: Events and blocks

    /// A new event: at `start`, with the Start sound of your Default type.
    public static func newEvent(start: Int, days: [Int], types: [BlockType]) -> Block {
        .event(title: "", start: HHMM.string(start), days: days, alert: eventAlert(from: defaultStart(types)))
    }

    static func defaultStart(_ types: [BlockType]) -> Reminder {
        (types.first(where: \.isDefault) ?? types.first)?.reminders.start ?? Specs.startingEventAlert
    }

    static func eventAlert(from r: Reminder) -> Reminder {
        Reminder(on: true, sound: r.sound, fade: r.fade, sounds: r.sounds)
    }

    /// Event to block: it gets an end 30 minutes later and the Default type's reminders.
    /// Block to event: it drops its end and reminders, and rings with its Start sound.
    public static func switched(_ b: Block, toEvent: Bool, types: [BlockType]) -> Block {
        var out = b
        if toEvent {
            guard !b.isEvent else { return b }
            let start = b.hasOwnReminders ? (b.reminders ?? Specs.startingTypeReminders).start
                : (types.first { $0.id == b.type } ?? types.first(where: \.isDefault))?.reminders.start ?? Specs.startingEventAlert
            out.end = ""
            out.type = Specs.eventType
            out.reminders = nil
            out.ringOnSilent = nil
            out.alert = eventAlert(from: start)
        } else {
            guard b.isEvent else { return b }
            out.end = HHMM.string(min(b.startMin + 30, 23 * 60 + 59))
            if out.endMin <= out.startMin { out.start = HHMM.string(out.endMin - 30) }
            out.type = Specs.defaultType
            out.alert = nil
            out.series = nil
        }
        return out
    }

    // MARK: Repeats

    /// The times a repeat rings, in minutes: from `first`, every `every` minutes, up to `last`
    /// (included when the gap lands on it). Stops early past the most a repeat may make.
    public static func repeatTimes(_ r: RepeatRule) -> [Int] {
        guard let f = HHMM.minutes(r.first), let l = HHMM.minutes(r.last), r.every > 0, l > f else { return [] }
        return Array(stride(from: f, through: l, by: r.every).prefix(Specs.maxRepeatEvents + 1))
    }

    /// What stops a repeat being made, or nil.
    public static func repeatProblem(title: String, days: [Int], rule: RepeatRule) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this event a name." }
        guard let f = HHMM.minutes(rule.first), let l = HHMM.minutes(rule.last) else { return "Set the first and last times." }
        if l <= f { return "The last time must be after the first." }
        if !Specs.repeatEvery.contains(rule.every) { return "Every must be from 1 to 720 minutes." }
        if days.isEmpty { return "Pick at least one day, or this event never rings." }
        let n = repeatTimes(rule).count
        if n < 2 { return "That makes only one event. Make the gap shorter, or the last time later." }
        if n > Specs.maxRepeatEvents { return "That would make more than \(Specs.maxRepeatEvents) events. Make the gap longer." }
        return nil
    }

    /// The events a repeat makes. Each id is the repeat's id and its time, so making the repeat
    /// again keeps the ids (and today's checks and skips) of the times it still has.
    public static func makeRepeat(title: String, days: [Int], alert: Reminder, rule: RepeatRule) -> [Block] {
        repeatTimes(rule).map { m in
            .event(id: "\(rule.id)-\(HHMM.string(m).replacingOccurrences(of: ":", with: ""))", title: title,
                   start: HHMM.string(m), days: days, alert: alert, series: rule)
        }
    }

    /// The events of the repeat with this id.
    public static func repeatEvents(_ id: String, in blocks: [Block]) -> [Block] {
        blocks.filter { $0.series?.id == id }
    }

    /// Your plan with a repeat's events replaced by `events` (or removed, with none).
    public static func replacingRepeat(_ id: String, with events: [Block], in blocks: [Block]) -> [Block] {
        Sanitize.sortByStart(blocks.filter { $0.series?.id != id } + events)
    }

    /// "Every 30 min, 9:00 AM – 5:00 PM".
    public static func repeatText(_ r: RepeatRule, time: (Int) -> String) -> String {
        "Every \(TimeText.length(minutes: r.every)), \(time(HHMM.minutes(r.first) ?? 0)) – \(time(HHMM.minutes(r.last) ?? 0))"
    }

    /// Takes one event out of its repeat, as its own event with a new id; later changes to the
    /// repeat leave it alone. Returns the event and the new plan.
    public static func detached(_ b: Block, in blocks: [Block]) -> (Block, [Block]) {
        var one = b
        one.id = Block.newId()
        one.series = nil
        return (one, Sanitize.sortByStart(blocks.filter { $0.id != b.id } + [one]))
    }

    /// The first other block this one overlaps on a shared day. Moments never overlap anything.
    public static func overlap(_ b: Block, in blocks: [Block]) -> Block? {
        if b.isMoment { return nil }
        return blocks.first { o in
            o.id != b.id && !o.isMoment && o.days.contains(where: b.days.contains) && o.startMin < b.endMin && b.startMin < o.endMin
        }
    }

    /// "Overlaps Lunch", "Overlaps Lunch on Tuesday".
    public static func overlapText(_ b: Block, in blocks: [Block]) -> String? {
        guard let o = overlap(b, in: blocks) else { return nil }
        let shared = b.days.filter(o.days.contains)
        let when = shared.count == 1 ? " on \(dayNames[shared[0]])" : ""
        return "Overlaps \(o.title.isEmpty ? "an unnamed block" : o.title)\(when)"
    }

    /// "Every day", "Weekdays", "Weekends", "Mon, Wed, Fri", "No days".
    public static func daysText(_ days: [Int]) -> String {
        let set = Set(days)
        if set.count == 7 { return "Every day" }
        if set == [1, 2, 3, 4, 5] { return "Weekdays" }
        if set == [0, 6] { return "Weekends" }
        if set.isEmpty { return "No days" }
        if set.count == 1 { return dayNames[set.first!] + "s" }
        return weekOrder.filter(set.contains).map { shortDayNames[$0] }.joined(separator: ", ")
    }

    /// ＋ in the list, Block: the new block starts where your latest block ends, lasts 30 minutes, and
    /// copies that block's days and type, as on the Mac.
    public static func newBlockAfterLatest(_ blocks: [Block]) -> Block {
        let last = blocks.enumerated().sorted { a, b in
            a.element.endMin != b.element.endMin ? a.element.endMin < b.element.endMin : a.offset < b.offset
        }.last?.element
        // After a moment, the new block starts at the moment's time.
        let s = last.map(\.endMin) ?? 9 * 60
        let endMin = min(s + 30, 23 * 60 + 59)
        // A block that ends at 23:59 leaves no room after it; start 30 minutes earlier instead.
        let startMin = endMin <= s ? max(0, endMin - 30) : s
        return Block(title: "", start: HHMM.string(startMin), end: HHMM.string(endMin),
                     days: last?.days ?? Specs.weekdays, type: last.map(blockType) ?? Specs.defaultType, reminders: last?.reminders)
    }

    /// Tapping an empty slot in the day view: a 30-minute block there on that day, with the type
    /// and days of the block before it (or that day and Default if there isn't one).
    public static func newBlock(at minute: Int, day: Int, blocks: [Block]) -> Block {
        let startMin = min(max(0, snap(minute)), 23 * 60 + 59 - minimumMinutes)
        let endMin = min(startMin + 30, 23 * 60 + 59)
        let before = blocks.filter { $0.days.contains(day) && $0.endMin <= startMin }.max { $0.endMin < $1.endMin }
        return Block(title: "", start: HHMM.string(startMin), end: HHMM.string(endMin),
                     days: before?.days ?? [day], type: before.map(blockType) ?? Specs.defaultType, reminders: before?.reminders)
    }

    /// The type a new block copies from `b`: an event has none, so Default.
    static func blockType(_ b: Block) -> String { b.isEvent ? Specs.defaultType : b.type }

    public static func snap(_ minute: Int) -> Int {
        Int((Double(minute) / Double(snapMinutes)).rounded()) * snapMinutes
    }

    /// Moves a block by `delta` minutes, keeping its length, within the day.
    public static func moved(_ b: Block, by delta: Int) -> Block {
        let len = b.lengthMin
        let s = min(max(0, b.startMin + delta), 23 * 60 + 59 - len)
        var out = b
        out.start = HHMM.string(s)
        if !b.isMoment { out.end = HHMM.string(s + len) }
        return out
    }

    /// Changes one end of a block, keeping it at least 5 minutes long and within the day.
    public static func resized(_ b: Block, start newStart: Int? = nil, end newEnd: Int? = nil) -> Block {
        if b.isMoment { return b } // a moment has no length to change
        var out = b
        if let ns = newStart { out.start = HHMM.string(min(max(0, ns), b.endMin - minimumMinutes)) }
        if let ne = newEnd { out.end = HHMM.string(max(min(23 * 60 + 59, ne), b.startMin + minimumMinutes)) }
        return out
    }

    /// Applies an edit made while looking at one day. With `allDays` it changes the block
    /// everywhere; otherwise that day is split off as its own block and the original keeps its
    /// other days. A block on just that one day is simply changed.
    public static func apply(_ edited: Block, original: Block, day: Int, allDays: Bool, in blocks: [Block]) -> [Block] {
        var list = blocks
        guard let i = list.firstIndex(where: { $0.id == original.id }) else { return list }
        if allDays || original.days == [day] || !original.days.contains(day) {
            list[i] = edited
            return Sanitize.sortByStart(list)
        }
        var rest = original
        rest.days = original.days.filter { $0 != day }
        var single = edited
        single.id = Block.newId()
        single.days = [day]
        list[i] = rest
        list.append(single)
        return Sanitize.sortByStart(list)
    }

    /// Whether an edit made in the day view needs to ask "This day only / All N days".
    public static func needsDayChoice(_ original: Block, day: Int) -> Bool {
        original.days.count > 1 && original.days.contains(day)
    }

    /// Removes a block from one day only (or deletes it if that was its only day).
    public static func removing(_ b: Block, day: Int?, from blocks: [Block]) -> [Block] {
        guard let day, b.days.count > 1 else { return blocks.filter { $0.id != b.id } }
        return blocks.map { x in
            guard x.id == b.id else { return x }
            var y = x
            y.days = x.days.filter { $0 != day }
            return y
        }
    }

    /// Lays out one day's blocks in columns, so overlapping blocks sit side by side.
    /// Returns, for each block id, its column and how many columns its cluster has.
    public static func columns(_ dayBlocks: [Block]) -> [String: (column: Int, of: Int)] {
        let sorted = dayBlocks.filter { !$0.isMoment }.sorted { $0.startMin != $1.startMin ? $0.startMin < $1.startMin : $0.endMin > $1.endMin }
        var result: [String: (Int, Int)] = [:]
        var cluster: [(Block, Int)] = []
        var clusterEnd = -1
        func flush() {
            let n = (cluster.map(\.1).max() ?? -1) + 1
            for (b, c) in cluster { result[b.id] = (c, n) }
            cluster = []
        }
        var colEnds: [Int] = []
        for b in sorted {
            if b.startMin >= clusterEnd { flush(); colEnds = [] }
            if let c = colEnds.firstIndex(where: { $0 <= b.startMin }) {
                colEnds[c] = b.endMin
                cluster.append((b, c))
            } else {
                colEnds.append(b.endMin)
                cluster.append((b, colEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, b.endMin)
        }
        flush()
        return result
    }
}
