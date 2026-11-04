import DayFlowCore
import Foundation
import UserNotifications

/// Schedules DayFlow's reminders as system notifications.
///
/// iOS suspends an app soon after you leave it, so nothing can run at the moment a reminder is
/// due. Instead the next reminders are scheduled ahead of time: up to 62 of them (iOS keeps at
/// most 64 per app), then a quiet notice asking you to open DayFlow. Whenever the app runs, the
/// list is refilled. Each one plays its sound at your ringer volume and follows the silent
/// switch and Focus.
enum ReminderScheduler {
    static let joinCategory = "meeting-join"
    static let calendarCategory = "meeting-calendar"
    static let joinAction = "join"
    static let calendarAction = "calendar"
    static let testId = "test-notification"

    static func registerCategories() {
        let join = UNNotificationCategory(
            identifier: joinCategory,
            actions: [UNNotificationAction(identifier: joinAction, title: "Join", options: [.foreground])],
            intentIdentifiers: [])
        let calendar = UNNotificationCategory(
            identifier: calendarCategory,
            actions: [UNNotificationAction(identifier: calendarAction, title: "Open in Calendar", options: [.foreground])],
            intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([join, calendar])
    }

    /// Replaces every scheduled reminder with the current window. Returns how many were scheduled.
    @discardableResult
    static func reschedule(planner: Planner, store: DataStore, now: Date = Date()) async -> Int {
        let center = UNUserNotificationCenter.current()
        let s = store.settings
        let window = planner.window(from: now, pausedUntil: s.pausedUntil, sound: s.sound)

        var requests: [UNNotificationRequest] = []
        var soundFiles = Set<String>()
        for ev in window.all {
            let content = UNMutableNotificationContent()
            content.title = ev.title
            content.body = ev.body
            content.threadIdentifier = ev.day
            content.interruptionLevel = .active
            if let sound = ev.sound {
                let name = SoundLibrary.prepare(sound, fade: ev.fade, volume: s.volume, store: store)
                    ?? ev.fallbackSound.flatMap { SoundLibrary.prepare($0, fade: ev.fade, volume: s.volume, store: store) }
                if let name {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
                    soundFiles.insert(name)
                }
            }
            var info: [String: Any] = ["role": ev.role.rawValue, "at": ev.at.timeIntervalSinceReferenceDate]
            if let blockId = ev.blockId { info["blockId"] = blockId }
            if let mt = ev.meeting {
                info["meetingStart"] = mt.start.timeIntervalSinceReferenceDate
                if let url = mt.url {
                    info["url"] = url.absoluteString
                    content.categoryIdentifier = joinCategory
                } else {
                    content.categoryIdentifier = calendarCategory
                }
            }
            content.userInfo = info
            // Floating local time: a reminder at 9:00 rings at 9:00 wherever you are.
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: ev.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            requests.append(UNNotificationRequest(identifier: ev.id, content: content, trigger: trigger))
        }

        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0 != testId }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for r in requests { try? await center.add(r) }
        SoundLibrary.removeUnused(keeping: soundFiles.union(previewKeep(store)))
        return window.reminders.count
    }

    /// Sounds the open settings pages may preview straight away; kept so previews start quickly.
    private static func previewKeep(_ store: DataStore) -> Set<String> {
        let v = store.settings.volume
        let reminders = store.types.flatMap(\.reminders.all) + store.settings.meetings.all
        return Set(reminders.map { SoundLibrary.fileName($0.sound, fade: $0.fade, volume: v) })
    }

    /// Shows what a block starting looks like, with Default's Start sound, in two seconds.
    static func sendTest(store: DataStore) async {
        let r = store.typeOf(Specs.defaultType).reminders.start
        let content = UNMutableNotificationContent()
        content.title = "Now: Test block"
        content.body = "This is what a block starting looks like."
        if store.settings.sound, let name = SoundLibrary.prepare(r.sound, fade: r.fade, volume: store.settings.volume, store: store) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }
        let request = UNNotificationRequest(identifier: testId, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func authorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}
