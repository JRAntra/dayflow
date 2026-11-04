import DayFlowCore
import EventKit
import Foundation

/// Meetings from the calendars on your iPhone: iCloud, and any Google, Outlook or Exchange
/// accounts added in Settings › Calendar › Accounts. The same rules as the Mac: timed events
/// only, and cancelled or declined ones are skipped.
final class CalendarService {
    let store = EKEventStore()

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Calendars that can hold events, grouped by account, with the default calendar's id.
    func calendars() -> [EKCalendar] {
        store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
    }

    var defaultCalendarId: String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    /// Timed events from the chosen calendars, from the start of today for `days` days.
    func meetings(calendarIds: [String], from now: Date = Date(), days: Int = Planner.horizonDays + 1) -> [Meeting] {
        guard hasAccess, !calendarIds.isEmpty else { return [] }
        let chosen = store.calendars(for: .event).filter { calendarIds.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.declined($0) && $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                Meeting(id: e.calendarItemIdentifier, title: (e.title?.isEmpty == false ? e.title! : "(No title)"),
                        start: e.startDate, end: e.endDate, url: Self.videoLink(e))
            }
    }

    static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    /// Video-call hosts DayFlow recognises.
    static let videoHosts = ["meet.google.com", "zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

    /// Google events synced to the iPhone carry the Meet link in their notes rather than in a
    /// field of its own, so the event's URL, location and notes are all searched.
    static func videoLink(_ e: EKEvent) -> URL? {
        videoLink(in: [e.url?.absoluteString, e.location, e.notes].compactMap { $0 })
    }

    static func videoLink(in texts: [String]) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url, url.scheme == "https", let host = url.host?.lowercased() else { continue }
                if videoHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return url }
            }
        }
        return nil
    }
}
