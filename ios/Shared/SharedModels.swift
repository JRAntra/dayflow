import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// Used by both the app and the widget extension.

#if canImport(ActivityKit)
/// The Live Activity for the current block, on the Lock Screen and in the Dynamic Island.
/// It counts down by itself; when the block ends it shows what's next until the app runs again.
struct DayFlowActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var typeName: String
        var start: Date
        var end: Date
        var nextTitle: String?
        var nextStart: Date?
    }
    /// The calendar day, e.g. "2026-11-4".
    var day: String
}
#endif

/// The next two days of blocks, written by the app for the widgets, which read it from the
/// shared App Group folder and switch blocks on their own as the day goes.
struct WidgetSnapshot: Codable, Hashable {
    struct Item: Codable, Hashable {
        var title: String
        var typeName: String
        var start: Date
        var end: Date
    }
    var items: [Item]
    var written: Date
    /// Reminders are off until then (`.distantFuture` until you turn them on); nil when on.
    var offUntil: Date? = nil

    func remindersOff(at date: Date) -> Bool { offUntil.map { date < $0 } ?? false }

    static let groupId = "group.com.jrantra.dayflow"

    /// nil when the App Group isn't available (a free Apple ID may not be allowed to sign it).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when there's nowhere to write it.
    @discardableResult
    func write() -> Bool {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The block running at `date`, and the next one after it.
    func current(at date: Date) -> Item? { items.first { $0.start <= date && date < $0.end } }
    func next(after date: Date) -> Item? { items.first { $0.start > date } }
}

/// DayFlow's colours, the same "Sunrise" teal and amber as the Mac app.
enum Palette {
    /// Teal: your blocks, selection, primary actions.
    static let accent = Color("AccentColor")
    /// Amber: coming up, heads-up, meetings.
    static let sun = Color("Sun")
}
