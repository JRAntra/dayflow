import Foundation
import Testing
@testable import DayFlowCore

@Suite struct TurnOffTests {
    let now = date(2026, 11, 4, 10) // a Wednesday

    @Test func theThreeChoices() {
        let hour = TurnOff.hour.apply(to: Settings(), now: now)
        #expect(hour.offUntil(at: now) == date(2026, 11, 4, 11) && !hour.remindersOff)
        let day = TurnOff.day.apply(to: Settings(), now: now)
        #expect(day.offUntil(at: now) == date(2026, 11, 5, 10))
        let forever = TurnOff.untilOn.apply(to: hour, now: now)
        #expect(forever.offUntil(at: now) == .distantFuture && forever.pausedUntil == nil)
        #expect(forever.isOff(at: date(2027, 1, 1)))
        #expect(!TurnOff.turnOn(forever).isOff(at: now))
        // A timed stop ends by itself.
        #expect(!hour.isOff(at: date(2026, 11, 4, 11, 0, 1)))
    }

    @Test func statusLines() {
        let p = { (s: Settings) in TurnOff.status(s, now: now, calendar: testCalendar, locale: testLocale).map(plain) }
        #expect(p(Settings()) == nil)
        #expect(p(TurnOff.hour.apply(to: Settings(), now: now)) == "Reminders off until 11:00 AM")
        #expect(p(TurnOff.day.apply(to: Settings(), now: now)) == "Reminders off until Thu 10:00 AM")
        #expect(p(TurnOff.untilOn.apply(to: Settings(), now: now)) == "Reminders off until you turn them on")
    }

    @Test func nothingIsScheduledWhileOff() {
        let p = samplePlanner()
        let forever = TurnOff.untilOn.apply(to: Settings(), now: now)
        let w = p.window(from: now, pausedUntil: forever.offUntil(at: now))
        #expect(w.reminders.isEmpty && w.notice == nil)
        // For 24 hours: tomorrow's reminders after 10:00 are scheduled, today's are skipped.
        let day = TurnOff.day.apply(to: Settings(), now: now)
        let w2 = p.window(from: now, pausedUntil: day.offUntil(at: now))
        #expect(w2.reminders.first?.at == date(2026, 11, 5, 11, 25))
    }

    @Test func itSurvivesARestart() throws {
        let s = tempStore()
        try s.saveSettings(TurnOff.untilOn.apply(to: s.settings))
        s.load()
        #expect(s.settings.remindersOff && s.settings.isOff(at: Date()))
        try s.saveSettings(TurnOff.turnOn(s.settings))
        s.load()
        #expect(!s.settings.remindersOff && s.settings.pausedUntil == nil)
    }
}
