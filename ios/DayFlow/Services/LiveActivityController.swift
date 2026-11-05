import ActivityKit
import DayFlowCore
import Foundation
import WidgetKit

/// Keeps the Live Activity on the current block, and the widgets' copy of the day up to date.
///
/// A Live Activity can only be started or changed while DayFlow runs, so it's brought up to date
/// whenever the app opens, a notification is tapped, or iOS lets DayFlow refresh. It counts down
/// by itself; at the block's end it shows what's next until the app runs again.
@MainActor
enum LiveActivityController {
    /// - Parameters:
    ///   - canStart: Live Activities can only be started while the app is in the foreground.
    static func update(planner: Planner, enabled: Bool, canStart: Bool, now: Date = Date()) async {
        let activities = Activity<DayFlowActivityAttributes>.activities
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = currentState(planner: planner, now: now) else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let day = planner.dayKey(now)
        let content = ActivityContent(state: state, staleDate: state.end)
        // One activity at a time; one from an earlier day is replaced.
        var kept: Activity<DayFlowActivityAttributes>?
        for a in activities {
            if kept == nil && a.attributes.day == day && a.activityState == .active { kept = a } else {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
        if let kept {
            if kept.content.state != state { await kept.update(content) }
        } else if canStart {
            _ = try? Activity.request(attributes: DayFlowActivityAttributes(day: day), content: content, pushType: nil)
        }
    }

    static func currentState(planner: Planner, now: Date) -> DayFlowActivityAttributes.ContentState? {
        let blocks = planner.blocksFor(now)
        guard let cur = blocks.first(where: { $0.start <= now && now < $0.end }) else { return nil }
        let next = blocks.first { $0.start >= cur.end }
        return .init(title: cur.title, typeName: planner.typeName(for: cur.block), start: cur.start, end: cur.end,
                     nextTitle: next?.title, nextStart: next?.start)
    }

    static func endAll() async {
        for a in Activity<DayFlowActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// Writes today's and tomorrow's blocks for the widgets. Returns false when the App Group
    /// isn't available, so the widgets can't be used with this signing.
    @discardableResult
    static func writeWidgetSnapshot(planner: Planner, offUntil: Date? = nil, now: Date = Date()) -> Bool {
        let cal = planner.calendar
        let days = (0..<3).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        let items = days.flatMap { planner.blocksFor($0) }.map {
            WidgetSnapshot.Item(title: $0.title, typeName: planner.typeName(for: $0.block), start: $0.start, end: $0.end)
        }
        let ok = WidgetSnapshot(items: items, written: now, offUntil: offUntil).write()
        if ok { WidgetCenter.shared.reloadAllTimelines() }
        return ok
    }
}
