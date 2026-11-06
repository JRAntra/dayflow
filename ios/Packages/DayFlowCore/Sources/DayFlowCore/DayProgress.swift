import Foundation

/// One day's checks and skips, and its result as last seen.
public struct DayRecord: Codable, Hashable, Sendable {
    /// Events checked off that day.
    public var done: [String]
    /// Events and blocks skipped that day: no reminders, struck through in Today.
    public var skipped: [String]
    /// How many events counted that day (skipped ones don't), and how many of them were done,
    /// as they were the last time DayFlow looked. The streak uses these for past days, so a
    /// change to your plan later doesn't rewrite them.
    public var total: Int?
    public var count: Int?

    public init(done: [String] = [], skipped: [String] = [], total: Int? = nil, count: Int? = nil) {
        self.done = done; self.skipped = skipped; self.total = total; self.count = count
    }

    var isEmpty: Bool { done.isEmpty && skipped.isEmpty && total == nil }
}

/// What you checked off and skipped, by day ("2026-11-5", as `Planner.dayKey` writes it).
/// Skips and checks only ever apply to their own day, so everything is back the next morning.
/// It stays on the device it was made on; exports don't carry it.
public struct DayProgress: Codable, Hashable, Sendable {
    /// The first day DayFlow kept progress: the streak never looks further back.
    public var since: String?
    public var days: [String: DayRecord]

    public init(since: String? = nil, days: [String: DayRecord] = [:]) {
        self.since = since; self.days = days
    }

    /// Days kept: about a year, enough for any streak worth showing.
    public static let keepDays = 400

    public static func read(_ v: JSONValue?) -> DayProgress {
        var p = DayProgress(since: v?["since"]?.string)
        for (key, d) in v?["days"]?.object ?? [:] where Self.date(key) != nil {
            let ids = { (k: String) in Array(Set(d[k]?.array?.compactMap(\.string) ?? [])).sorted() }
            let num = { (k: String) in d[k]?.numberValue.map { max(0, Int($0)) } }
            p.days[key] = DayRecord(done: ids("done"), skipped: ids("skipped"), total: num("total"), count: num("count"))
        }
        if let s = p.since, Self.date(s) == nil { p.since = nil }
        return p
    }

    public func record(_ day: String) -> DayRecord { days[day] ?? DayRecord() }
    public func isDone(_ id: String, on day: String) -> Bool { days[day]?.done.contains(id) == true }
    public func isSkipped(_ id: String, on day: String) -> Bool { days[day]?.skipped.contains(id) == true }

    public mutating func setDone(_ id: String, _ on: Bool, day: String) {
        change(day) { r in
            r.done.removeAll { $0 == id }
            if on { r.done.append(id); r.skipped.removeAll { $0 == id } }
        }
    }

    public mutating func setSkipped(_ id: String, _ on: Bool, day: String) {
        change(day) { r in
            r.skipped.removeAll { $0 == id }
            if on { r.skipped.append(id); r.done.removeAll { $0 == id } }
        }
    }

    /// Keeps the day's result for the streak.
    public mutating func note(done: Int, total: Int, day: String) {
        guard total > 0 || days[day] != nil else { return }
        change(day) { r in r.total = total; r.count = done }
    }

    mutating func change(_ day: String, _ edit: (inout DayRecord) -> Void) {
        if since == nil || (Self.date(day).map { d in Self.date(since!).map { d < $0 } ?? true } ?? false) { since = day }
        var r = record(day)
        edit(&r)
        days[day] = r.isEmpty ? nil : r
    }

    /// Without checks and skips of anything that's no longer in your plan, and without days
    /// older than `keepDays` before `now`.
    public func pruned(keeping ids: Set<String>, now: Date = Date(), calendar: Calendar = .current) -> DayProgress {
        var p = self
        let oldest = calendar.date(byAdding: .day, value: -Self.keepDays, to: calendar.startOfDay(for: now)) ?? now
        for (key, r) in days {
            guard let d = Self.date(key, calendar: calendar), d >= oldest else { p.days[key] = nil; continue }
            var c = r
            c.done = r.done.filter(ids.contains)
            c.skipped = r.skipped.filter(ids.contains)
            p.days[key] = c.isEmpty ? nil : c
        }
        return p
    }

    /// The date a day key names, at midnight.
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// Picking one of a reminder's sounds each time it rings, never the one it played last.
///
/// The pick is worked out from which time it is (its place in the run of times that reminder
/// rings) rather than remembered, so every device and every reschedule picks the same: even
/// places pick freely; odd places avoid both neighbours; with two sounds they take turns.
public enum SoundPick {
    public static func pick(_ choices: [String], stream: String, index: Int) -> String {
        let n = choices.count
        guard n > 1 else { return choices.first ?? "" }
        if n == 2 { return choices[Int((UInt64(bitPattern: Int64(index)) + UInt64(hash(stream) % 2)) % 2)] }
        func free(_ i: Int) -> Int { Int(hash("\(stream)|\(i)") % UInt32(n)) }
        if index % 2 == 0 { return choices[free(index)] }
        let avoid = Set([free(index - 1), free(index + 1)])
        let options = (0..<n).filter { !avoid.contains($0) }
        return choices[options[Int(hash("\(stream)|\(index)|odd") % UInt32(options.count))]]
    }

    /// FNV-1a, 32-bit: the same on the Mac (`soundPick` in main.js).
    public static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return h
    }
}
