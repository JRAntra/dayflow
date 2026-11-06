import Foundation
import Testing
@testable import DayFlowCore

/// Blocks that ring even on silent: their reminders become alarms on iPhone.
@Suite struct RingTests {
    let monday = date(2026, 11, 2)

    func schedule(ringing ids: Set<String>, extra: [Block] = []) -> [Block] {
        (Specs.sampleSchedule() + extra).map { var b = $0; b.ringsOnSilent = ids.contains(b.id); return b }
    }

    func planner(_ blocks: [Block]) -> Planner {
        Planner(blocks: blocks, types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders,
                calendar: testCalendar, locale: testLocale)
    }

    @Test func everyReminderOfARingingBlockIsAnAlarm() {
        let evs = planner(schedule(ringing: ["b2"])).events(on: monday)
        let deep = evs.filter { $0.blockId == "b2" }
        #expect(!deep.isEmpty && deep.allSatisfy { $0.alarm })
        // Deep work's Time's up merges into Email's Now, which rings because Deep work does.
        let handOff = evs.first { $0.at == date(2026, 11, 2, 11, 30) }!
        #expect(handOff.title == "Now: Email and messages" && handOff.alarm)
        // The rest of the day is untouched.
        #expect(!evs.contains { $0.alarm && $0.at > date(2026, 11, 2, 11, 30) })
    }

    @Test func eventsAlwaysRing() {
        let pill = Block.event(id: "m", title: "Take medicine", start: "13:10", days: [1], alert: Specs.startingEventAlert)
        let evs = Planner(blocks: Specs.sampleSchedule() + [pill], types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders,
                          calendar: testCalendar, locale: testLocale).events(on: monday).filter { $0.blockId == "m" }
        #expect(evs.map(\.role) == [.event])
        #expect(evs.allSatisfy { $0.alarm && $0.canCheck })
    }

    @Test func alarmsOnlyWhenAllowedAndSoundsAreOn() {
        let p = planner(schedule(ringing: ["b2"]))
        let now = date(2026, 11, 2, 8)
        func alarms(_ w: ReminderWindow) -> Int { w.reminders.filter(\.alarm).count }
        #expect(alarms(p.window(from: now)) == 0) // alarms not allowed: normal reminders
        let on = p.window(from: now, alarms: true)
        #expect(alarms(on) > 0)
        #expect(alarms(p.window(from: now, sound: false, alarms: true)) == 0)
        // Alarms aren't notifications, so they don't use up the notification limit.
        #expect(on.reminders.filter { !$0.alarm }.count == Planner.windowLimit)
        #expect(on.reminders.count == Planner.windowLimit + alarms(on))
    }

    @Test func alarmsPastTheLimitAreNormalReminders() {
        let w = planner(schedule(ringing: Set((1...8).map { "b\($0)" }))).window(from: date(2026, 11, 2, 8), alarms: true, alarmLimit: 3)
        #expect(w.reminders.prefix(3).allSatisfy { $0.alarm })
        #expect(w.reminders.filter(\.alarm).count == 3)
    }

    @Test func savedOnlyWhenOn() throws {
        let a = tempStore()
        try a.saveBlocks(schedule(ringing: ["b4"]))
        #expect(a.blocks.first { $0.id == "b4" }?.ringsOnSilent == true)
        #expect(a.blocks.first { $0.id == "b1" }?.ringsOnSilent == false)
        let data = try JSONFile.encode(JSONValue.from(a.blocks))
        let file = String(decoding: data, as: UTF8.self)
        #expect(file.components(separatedBy: "ringOnSilent").count == 2) // only Lunch has the key
        a.load()
        #expect(a.blocks.first { $0.id == "b4" }?.ringsOnSilent == true)
    }

    @Test func readsTheMacsTruthiness() throws {
        let v = try JSONValue.decode(Data(#"[{"title":"A","start":"09:00","end":"10:00","days":[1],"type":"default","ringOnSilent":1},{"title":"B","start":"10:00","end":"11:00","days":[1],"type":"default","ringOnSilent":false}]"#.utf8))
        let list = try Sanitize.blocks(v, typeIds: ["default"])
        #expect(list.map { $0.ringsOnSilent } == [true, false])
    }
}
