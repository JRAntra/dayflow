import CryptoKit
import DayFlowCore
import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Rings the reminders of blocks set to "Ring even on silent" as alarms (AlarmKit, iOS 26 and
/// later). Unlike notifications, alarms ring through the silent switch and Focus, show on the
/// Lock Screen and in the Dynamic Island, and keep going until you tap Stop.
///
/// Like notifications, they're set ahead of time and replaced whenever DayFlow runs. Each alarm's
/// id comes from what it says and when, so an unchanged alarm is left alone rather than set again.
enum AlarmScheduler {
    enum Access: Equatable {
        /// iOS 25 or earlier: no alarms, so the switch is hidden.
        case unsupported
        case notDetermined
        case denied
        case authorized
    }

    static var access: Access {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return map(AlarmManager.shared.authorizationState) }
        #endif
        return .unsupported
    }

    /// Asks "Allow DayFlow to schedule alarms?" the first time; afterwards returns the answer.
    static func requestAccess() async -> Access {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if let state = try? await AlarmManager.shared.requestAuthorization() { return map(state) }
            return access
        }
        #endif
        return .unsupported
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func map(_ s: AlarmManager.AuthorizationState) -> Access {
        switch s {
        case .authorized: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }
    #endif

    /// What DayFlow tells AlarmKit about an alarm (nothing it needs, but AlarmKit asks for a type).
    struct Info: Codable, Hashable, Sendable {
        var blockId: String?
    }

    /// The same id every time for the same reminder, saying the same thing at the same time.
    static func alarmId(_ ev: PlannedReminder, sound: String?) -> UUID {
        let key = "\(ev.id)|\(ev.at.timeIntervalSinceReferenceDate)|\(ev.title)|\(sound ?? "-")"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // a name-based UUID
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Replaces DayFlow's alarms with `events`, each with its sound (a file in Library/Sounds, or
    /// nil for the system alarm sound). An alarm that's ringing right now is left to ring.
    /// Returns the reminders that couldn't be set as alarms, to send as normal reminders instead.
    static func sync(_ events: [(PlannedReminder, String?)]) async -> [PlannedReminder] {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return await syncAlarms(events) }
        #endif
        return events.map(\.0)
    }

    /// Cancels every alarm DayFlow has set, except one that's ringing.
    static func cancelAll() async {
        _ = await sync([])
    }

    /// How many alarms are set (for tests and the debug overlay).
    static var scheduledCount: Int {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return (try? AlarmManager.shared.alarms.count) ?? 0 }
        #endif
        return 0
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func syncAlarms(_ events: [(PlannedReminder, String?)]) async -> [PlannedReminder] {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return events.map(\.0) }
        let now = Date()
        var wanted: [UUID: (PlannedReminder, String?)] = [:]
        for (ev, sound) in events where ev.at > now { wanted[alarmId(ev, sound: sound)] = (ev, sound) }

        let existing = (try? manager.alarms) ?? []
        for alarm in existing where wanted[alarm.id] == nil && alarm.state != .alerting {
            try? manager.cancel(id: alarm.id)
        }
        let have = Set(existing.map(\.id))
        var failed: [PlannedReminder] = []
        for (id, (ev, sound)) in wanted.sorted(by: { $0.value.0.at < $1.value.0.at }) where !have.contains(id) {
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(ev, sound: sound))
            } catch {
                failed.append(ev)
            }
        }
        return failed
    }

    @available(iOS 26.0, *)
    private static func configuration(_ ev: PlannedReminder, sound: String?) -> AlarmManager.AlarmConfiguration<Info> {
        let title = LocalizedStringResource(stringLiteral: ev.title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(title: title, stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
        }
        let attributes = AlarmAttributes<Info>(presentation: AlarmPresentation(alert: alert),
                                               metadata: Info(blockId: ev.blockId), tintColor: Palette.accent)
        return .alarm(schedule: .fixed(ev.at), attributes: attributes,
                      sound: sound.map { .named($0) } ?? .default)
    }
    #endif
}

// AlarmKit's metadata protocol, conformed to only where AlarmKit exists.
#if canImport(AlarmKit)
@available(iOS 26.0, *)
extension AlarmScheduler.Info: AlarmMetadata {}
#endif
