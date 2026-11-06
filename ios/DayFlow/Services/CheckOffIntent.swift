import AppIntents
import DayFlowCore
import Foundation
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Done on an event's alarm: stops it and checks the event off for that day, without opening
/// DayFlow. iOS runs it in DayFlow's own process, starting the app in the background if needed.
struct CheckOffIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Check off"
    static let description = IntentDescription("Checks an event off for today.")
    static let isDiscoverable = false

    @Parameter(title: "Event") var eventId: String
    @Parameter(title: "Day") var day: String
    @Parameter(title: "Alarm") var alarmId: String

    init() {}

    init(eventId: String, day: String, alarmId: String) {
        self.eventId = eventId
        self.day = day
        self.alarmId = alarmId
    }

    func perform() async throws -> some IntentResult {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = UUID(uuidString: alarmId) { try? AlarmManager.shared.stop(id: id) }
        #endif
        await MainActor.run { AppModel.shared.doneFromAlarm(eventId, day: day) }
        await AppModel.shared.refresh()
        return .result()
    }
}
