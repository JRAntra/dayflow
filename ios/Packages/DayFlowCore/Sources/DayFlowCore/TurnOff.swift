import Foundation

/// Turning reminders off: For 1 hour, For 24 hours, or Until I turn them on. While off, nothing
/// rings: no notifications, no sounds, no Live Activity. Reminders that fall in that time are
/// skipped, not delivered late. The same three choices as the Mac app.
public enum TurnOff: String, CaseIterable, Identifiable, Sendable {
    case hour, day, untilOn
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hour: "For 1 hour"
        case .day: "For 24 hours"
        case .untilOn: "Until I turn them on"
        }
    }

    /// Settings with reminders turned off this way from `now`.
    public func apply(to s: Settings, now: Date = Date()) -> Settings {
        var out = s
        switch self {
        case .hour: out.pausedUntil = now.addingTimeInterval(3600); out.remindersOff = false
        case .day: out.pausedUntil = now.addingTimeInterval(24 * 3600); out.remindersOff = false
        case .untilOn: out.pausedUntil = nil; out.remindersOff = true
        }
        return out
    }

    /// Settings with reminders back on.
    public static func turnOn(_ s: Settings) -> Settings {
        var out = s
        out.pausedUntil = nil
        out.remindersOff = false
        return out
    }

    /// "Reminders off until 3:15 PM", "…until Thu 3:15 PM", "…until you turn them on".
    public static func status(_ s: Settings, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let until = s.offUntil(at: now) else { return nil }
        if until == .distantFuture { return "Reminders off until you turn them on" }
        let time = TimeText.time(until, calendar: calendar, locale: locale)
        if calendar.isDate(until, inSameDayAs: now) { return "Reminders off until \(time)" }
        let f = DateFormatter()
        f.locale = locale; f.calendar = calendar; f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEE")
        return "Reminders off until \(f.string(from: until)) \(time)"
    }
}
