import Foundation
import Testing
@testable import DayFlowCore

/// A fixed calendar and locale, so times read "9:20 AM" whatever the Mac running the tests uses.
let testCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()
let testLocale = Locale(identifier: "en_US")

/// 2026-11-02 is a Monday.
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

/// Times use a narrow no-break space before AM/PM on recent systems; compare with plain spaces.
func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

func samplePlanner(types: [BlockType] = Specs.starterTypes(), meetings: [Meeting] = [],
                   meetingReminders: MeetingReminders = Specs.startingMeetingReminders) -> Planner {
    Planner(blocks: Specs.sampleSchedule(), types: types, meetingReminders: meetingReminders, meetings: meetings,
            calendar: testCalendar, locale: testLocale)
}

@Suite struct PlannerTests {
    @Test func sampleMondayMatchesTheMac() {
        let evs = samplePlanner().events(on: date(2026, 11, 2))
        let lines = evs.map { "\(plain(TimeText.time($0.at, calendar: testCalendar, locale: testLocale))) \($0.role.rawValue) \($0.title) | \(plain($0.body))" }
        // Start, heads-up and Time's up are on by default; preparation is off. A Time's up that
        // meets the next block's Start merges into the Start.
        #expect(lines == [
            "9:00 AM start Now: Plan the day | Runs until 9:20 AM.",
            "9:15 AM warn 5 min left: Plan the day | Next: Deep work at 9:20 AM.",
            "9:20 AM start Now: Deep work | Plan the day is done. Deep work runs until 11:30 AM.",
            "11:25 AM warn 5 min left: Deep work | Next: Email and messages at 11:30 AM.",
            "11:30 AM start Now: Email and messages | Deep work is done. Email and messages runs until 12:00 PM.",
            "11:55 AM warn 5 min left: Email and messages | Next: Lunch at 12:00 PM.",
            "12:00 PM start Now: Lunch | Email and messages is done. Lunch runs until 1:00 PM.",
            "12:55 PM warn 5 min left: Lunch | Next: Focus block at 1:00 PM.",
            "1:00 PM start Now: Focus block | Lunch is done. Focus block runs until 3:00 PM.",
            "2:55 PM warn 5 min left: Focus block | Next: Walk and stretch at 3:00 PM.",
            "3:00 PM start Now: Walk and stretch | Focus block is done. Walk and stretch runs until 3:15 PM.",
            "3:10 PM warn 5 min left: Walk and stretch | Next: Admin and follow-ups at 3:15 PM.",
            "3:15 PM start Now: Admin and follow-ups | Walk and stretch is done. Admin and follow-ups runs until 5:00 PM.",
            "4:55 PM warn 5 min left: Admin and follow-ups | Next: Shut down for the day at 5:00 PM.",
            "5:00 PM start Now: Shut down for the day | Admin and follow-ups is done. Shut down for the day runs until 5:15 PM.",
            "5:10 PM warn 5 min left: Shut down for the day | This is your last block today.",
            "5:15 PM end Time's up: Shut down for the day | That was your last block today.",
        ])
        // The merged hand-off carries both keys, and the incoming block's sound.
        let handOff = evs[2]
        #expect(handOff.keys == ["2026-11-2|block|b1|end", "2026-11-2|block|b2|start"])
        #expect(handOff.sound == Specs.spec(TypeReminderKey.start).sound)
        #expect(handOff.day == "2026-11-2")
    }

    @Test func weekendHasNothing() {
        #expect(samplePlanner().events(on: date(2026, 11, 7)).isEmpty)
    }

    @Test func prepMeetingAHeadsUpTakesTheOutgoingTitle() {
        var types = Specs.starterTypes()
        types[0].reminders.prep.on = true // Default: prep 5 min before, heads-up 5 min before the end
        let evs = samplePlanner(types: types).events(on: date(2026, 11, 2))
        let at1125 = evs.filter { $0.at == date(2026, 11, 2, 11, 25) }
        #expect(at1125.count == 1)
        let ev = at1125[0]
        #expect(ev.role == .prep) // the incoming block wins: its sound
        #expect(ev.title == "5 min left: Deep work")
        #expect(plain(ev.body) == "Next: Email and messages at 11:30 AM.")
        #expect(ev.sound == Specs.spec(.prep).sound)
        #expect(Set(ev.keys) == ["2026-11-2|block|b3|prep", "2026-11-2|block|b2|warn"])
        // The first block's prep stands alone.
        let first = evs.first { $0.at == date(2026, 11, 2, 8, 55) }!
        #expect(first.title == "In 5 min: Plan the day")
        #expect(plain(first.body) == "Get ready. It starts at 9:00 AM.")
    }

    @Test func gapsSayFreeUntil() {
        var blocks = Specs.sampleSchedule()
        blocks.removeAll { $0.id == "b4" } // no Lunch block: a gap from 12:00 to 1:00
        let p = Planner(blocks: blocks, types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders,
                        calendar: testCalendar, locale: testLocale)
        let end = p.events(on: date(2026, 11, 2)).first { $0.at == date(2026, 11, 2, 12) }!
        #expect(end.title == "Time's up: Email and messages")
        #expect(plain(end.body) == "Free until Focus block at 1:00 PM.")
        let warn = p.events(on: date(2026, 11, 2)).first { $0.at == date(2026, 11, 2, 11, 55) }!
        #expect(plain(warn.body) == "Next: Focus block at 1:00 PM.")
    }

    @Test func headsUpNeedsALongEnoughBlock() {
        var types = Specs.starterTypes()
        types[0].reminders.warn.lead = 20 // longer than Walk and stretch (15 min) and Plan the day (20 min)
        let evs = samplePlanner(types: types).events(on: date(2026, 11, 2))
        #expect(!evs.contains { $0.role == .warn && $0.blockId == "b6" })
        #expect(!evs.contains { $0.role == .warn && $0.blockId == "b1" })
        #expect(evs.contains { $0.role == .warn && $0.blockId == "b2" })
    }

    @Test func prepBeforeMidnightIsSkipped() {
        let blocks = [Block(id: "x", title: "Early", start: "00:02", end: "01:00", days: [1], type: "default")]
        var types = Specs.starterTypes()
        types[0].reminders.prep.on = true
        let p = Planner(blocks: blocks, types: types, meetingReminders: Specs.startingMeetingReminders, calendar: testCalendar, locale: testLocale)
        #expect(!p.events(on: date(2026, 11, 2)).contains { $0.role == .prep })
    }

    @Test func meetings() {
        let withLink = Meeting(id: "m1", title: "Standup", start: date(2026, 11, 2, 9, 30), end: date(2026, 11, 2, 9, 45),
                               url: URL(string: "https://meet.google.com/abc-defg-hij"))
        let noLink = Meeting(id: "m2", title: "1:1", start: date(2026, 11, 2, 14), end: date(2026, 11, 2, 14, 30))
        let tomorrow = Meeting(id: "m3", title: "Later", start: date(2026, 11, 3, 10), end: date(2026, 11, 3, 11))
        let evs = samplePlanner(meetings: [withLink, noLink, tomorrow]).events(on: date(2026, 11, 2))
        let meet = evs.filter { $0.meeting != nil }.map { "\($0.role.rawValue) \($0.title) | \(plain($0.body))" }
        #expect(meet == [
            "meetBefore In 5 min: Standup | Starts at 9:30 AM. Tap to join.",
            "meetStart Starting now: Standup | Tap to join.",
            "meetBefore In 5 min: 1:1 | Starts at 2:00 PM.",
            "meetStart Starting now: 1:1 | Started at 2:00 PM.",
        ])
        // Meeting reminders aren't merged with block reminders at the same moment.
        #expect(evs.filter { $0.at == date(2026, 11, 2, 14, 55) }.count == 1)
    }

    @Test func windowFillsUpAndEndsWithTheNotice() {
        let now = date(2026, 11, 2, 10) // Monday 10:00
        let w = samplePlanner().window(from: now)
        #expect(w.reminders.count == Planner.windowLimit)
        #expect(w.reminders.allSatisfy { $0.at > now })
        #expect(w.reminders.map(\.at) == w.reminders.map(\.at).sorted())
        #expect(w.reminders.first?.at == date(2026, 11, 2, 11, 25))
        // 14 left on Monday, 17 each on Tuesday and Wednesday, then 14 on Thursday: 62
        #expect(w.reminders.last?.at == date(2026, 11, 5, 16, 55))
        let notice = try! #require(w.notice)
        #expect(notice.at == date(2026, 11, 5, 16, 56))
        #expect(notice.sound == nil)
        #expect(notice.title == "Open DayFlow to keep your reminders coming")
        #expect(Set(w.all.map(\.id)).count == w.all.count) // identifiers are unique
    }

    @Test func windowSkipsAPauseAndCanBeSilent() {
        let now = date(2026, 11, 2, 10)
        let w = samplePlanner().window(from: now, pausedUntil: date(2026, 11, 2, 12, 1), sound: false)
        #expect(w.reminders.first?.at == date(2026, 11, 2, 12, 55))
        #expect(w.reminders.allSatisfy { $0.sound == nil })
    }

    @Test func emptyScheduleHasNoNotice() {
        let p = Planner(blocks: [], types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders, calendar: testCalendar)
        let w = p.window(from: date(2026, 11, 2))
        #expect(w.reminders.isEmpty && w.notice == nil)
    }

    @Test func daylightSavingKeepsWallClockTimes() {
        // US clocks went back on 2026-11-01 (a Sunday); Monday's 9:00 is still 9:00 local.
        let p = Planner(blocks: [Block(id: "a", title: "A", start: "09:00", end: "10:00", days: [0, 1], type: "default")],
                        types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders, calendar: testCalendar)
        for d in [date(2026, 10, 31), date(2026, 11, 1), date(2026, 11, 2)] {
            for ev in p.events(on: d) where ev.role == .start {
                #expect(testCalendar.component(.hour, from: ev.at) == 9)
            }
        }
    }

    @Test func timeText() {
        let a = date(2026, 11, 2, 9, 20), b = date(2026, 11, 2, 11, 30), c = date(2026, 11, 2, 13)
        #expect(plain(TimeText.range(a, b, calendar: testCalendar, locale: testLocale)) == "9:20 – 11:30 AM")
        #expect(plain(TimeText.range(b, c, calendar: testCalendar, locale: testLocale)) == "11:30 AM – 1:00 PM")
        #expect(TimeText.countdown(3909) == "1:05:09")
        #expect(TimeText.countdown(249.2) == "4:10")
        #expect(TimeText.length(minutes: 130) == "2 h 10 min")
        #expect(TimeText.length(minutes: 60) == "1 h")
        #expect(TimeText.length(minutes: 45) == "45 min")
    }
}
