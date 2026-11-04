import DayFlowCore
import EventKit
import UserNotifications
import SwiftUI
import UniformTypeIdentifiers

/// Meetings: the two meeting reminders, like the Mac's Meetings tab.
struct MeetingsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            if !model.calendarAccess || (model.settings.calendars ?? []).isEmpty {
                Section {
                    NavigationLink { CalendarsView() } label: {
                        Label("Choose the calendars your meetings come from", systemImage: "calendar.badge.plus")
                    }
                }
            }
            ForEach(MeetingReminderKey.allCases, id: \.self) { key in
                ReminderSection(spec: Specs.spec(key), example: key == .before ? "\"In \(model.settings.meetings.before.lead ?? 5) min: Standup\"" : "\"Starting now: Standup\"",
                                reminder: Binding(get: { model.settings.meetings[key] }, set: { r in model.update { $0.meetings[key] = r } }))
            }
            Section {
            } footer: {
                Text("A meeting reminder with a video link has a Join button; tapping the notification joins too. Without a link, it offers Open in Calendar.")
            }
        }
        .navigationTitle("Meetings")
    }
}

/// Calendars: which of the iPhone's calendars your meetings come from.
struct CalendarsView: View {
    @Environment(AppModel.self) private var model
    @State private var calendars: [EKCalendar] = []

    var body: some View {
        Form {
            if model.calendarAccess {
                let chosen = Set(model.settings.calendars ?? [])
                ForEach(groups, id: \.0) { source, list in
                    Section(source) {
                        ForEach(list, id: \.calendarIdentifier) { c in
                            Toggle(isOn: Binding(get: { chosen.contains(c.calendarIdentifier) },
                                                 set: { model.setCalendar(c.calendarIdentifier, on: $0) })) {
                                HStack(spacing: 10) {
                                    Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10)
                                    Text(c.title)
                                }
                            }
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Timed events from these calendars become meetings. All-day, cancelled and declined events are skipped. To add your Google calendar, go to iOS Settings › Apps › Calendar › Calendar Accounts.")
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Meetings from your calendars").font(.headline)
                        Text("DayFlow can remind you before meetings start, using the calendars on this iPhone: iCloud, and Google, Outlook or Exchange accounts you've added in iOS Settings. It only reads them.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if model.calendarService.status == .notDetermined {
                        Button("Allow calendar access") {
                            Task { await model.requestCalendarAccess(); calendars = model.calendarService.calendars() }
                        }
                    } else {
                        Button("Open Settings to allow access") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .onAppear { calendars = model.calendarService.calendars() }
    }

    var groups: [(String, [EKCalendar])] {
        Dictionary(grouping: calendars, by: { $0.source.title }).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

/// General: the Live Activity, notification permission, a test, and how far ahead reminders go.
struct GeneralView: View {
    @Environment(AppModel.self) private var model
    @State private var nextScheduled: [UNNotificationRequest] = []

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.settings.liveActivity }, set: { v in model.update { $0.liveActivity = v } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show the current block on the Lock Screen")
                        Text("A Live Activity, also in the Dynamic Island").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("It counts down by itself. When a block ends it shows what's next, and moves on the next time DayFlow runs: when you open it, tap a reminder, or iOS lets it refresh.")
            }

            Section("Notifications") {
                LabeledContent("Reminders", value: statusText)
                if model.notificationStatus == .notDetermined {
                    Button("Turn on notifications") { Task { await model.requestNotifications() } }
                } else if model.notificationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("Send a test notification") { Task { await model.sendTestNotification() } }
                if let last = nextScheduled.last?.trigger as? UNCalendarNotificationTrigger, let d = last.nextTriggerDate() {
                    LabeledContent("Scheduled ahead", value: "\(model.scheduledCount) reminders, until \(d.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                }
            }

            Section {
                LabeledContent("Background refresh", value: refreshText)
                if !model.widgetsAvailable {
                    Label("Widgets can't read your schedule with this signing (the App Group isn't available). The Live Activity still works.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("DayFlow schedules your reminders a few days ahead. If it hasn't run for a while, a notification asks you to open it so the next ones are scheduled. With background refresh on, iOS lets DayFlow do this by itself now and then.")
            }

            Section("Focus") {
                Text("During a Focus, iOS holds DayFlow's notifications back unless you allow DayFlow in that Focus: Settings › Focus › (the Focus) › Apps › Add DayFlow.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("General")
        .task { nextScheduled = await UNUserNotificationCenter.current().pendingNotificationRequests().sorted { a, b in
            ((a.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture) < ((b.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture)
        }.filter { !$0.identifier.hasPrefix("notice|") } }
    }

    var statusText: String {
        switch model.notificationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        default: "Not set up"
        }
    }

    var refreshText: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "On"
        case .denied: "Off: open DayFlow every few days"
        default: "Restricted"
        }
    }
}
