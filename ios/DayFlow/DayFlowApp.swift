import DayFlowCore
import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

@main
struct DayFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
                .onOpenURL { url in
                    // "Open in DayFlow" from AirDrop, Files or Mail: a sound becomes a clip,
                    // anything else gets the import preview.
                    if url.isFileURL, Specs.clipTypes.contains(url.pathExtension.lowercased()) {
                        model.tab = .settings
                        model.addClip(from: url)
                    } else if url.isFileURL {
                        model.openedFile = url
                        model.tab = .schedule
                    } else if url.scheme == "dayflow" {
                        model.tab = .today
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            model.isForeground = phase == .active
            if phase == .active {
                Task { await model.refresh(); model.showPendingCheer() }
            } else if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.registerCategories()
        BackgroundRefresh.register()
        return true
    }

    /// Reminders that come while DayFlow is open still show their banner and play their sound.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Tapping a reminder opens Today; a meeting's opens its video link, as on the Mac. Join and
    /// Open in Calendar do what they say. Each one is a chance to refill the reminders.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        let meetingStart = (info["meetingStart"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
        let blockId = info["blockId"] as? String, day = info["day"] as? String
        await MainActor.run {
            let model = AppModel.shared
            switch response.actionIdentifier {
            case ReminderScheduler.doneAction:
                if let blockId, let day { model.doneFromAlarm(blockId, day: day) }
            case ReminderScheduler.joinAction:
                if let url { UIApplication.shared.open(url) }
            case ReminderScheduler.calendarAction:
                if let meetingStart { UIApplication.shared.open(Self.calendarURL(meetingStart)) }
            case UNNotificationDefaultActionIdentifier:
                if let url { UIApplication.shared.open(url) } else { model.tab = .today }
            default:
                break
            }
        }
        await AppModel.shared.refresh()
    }

    /// Opens the Calendar app at that moment.
    static func calendarURL(_ date: Date) -> URL {
        URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))")!
    }
}

/// Lets iOS wake DayFlow now and then to refill the reminders and update meetings. iOS decides
/// when; it's usually at least daily if you use the app.
enum BackgroundRefresh {
    static let id = "com.jrantra.dayflow.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await AppModel.shared.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
