import Foundation
import Testing
@testable import DayFlowCore

/// Moments (blocks with only a start time) and blocks with their own reminders.
@Suite struct MomentTests {
    let monday = date(2026, 11, 2)
    var medicine: Block { Block(id: "m", title: "Take medicine", start: "13:00", end: "", days: [1], type: "default") }

    func planner(_ extra: [Block], types: [BlockType] = Specs.starterTypes()) -> Planner {
        Planner(blocks: Specs.sampleSchedule() + extra, types: types, meetingReminders: Specs.startingMeetingReminders,
                calendar: testCalendar, locale: testLocale)
    }

    @Test func aMomentGetsPrepAndStartOnly() {
        var types = Specs.starterTypes()
        types[0].reminders.prep.on = true
        let evs = planner([medicine], types: types).events(on: monday).filter { $0.blockId == "m" }
        #expect(evs.map { "\($0.role.rawValue) \($0.title) | \(plain($0.body))" } == [
            "prep In 5 min: Take medicine | Get ready. It's at 1:00 PM.",
            "start Now: Take medicine | It's 1:00 PM, during Focus block.",
        ])
    }

    @Test func momentsAreNeverMergedWithBlocks() {
        // 1:00 PM is also Lunch's end and Focus block's start: both notifications stay.
        let evs = planner([medicine]).events(on: monday).filter { $0.at == date(2026, 11, 2, 13) }
        #expect(evs.count == 2)
        #expect(evs.contains { $0.title == "Now: Focus block" } && evs.contains { $0.title == "Now: Take medicine" })
        // And a moment between blocks isn't "next" in their wording.
        let lunchWarn = planner([medicine]).events(on: monday).first { $0.at == date(2026, 11, 2, 12, 55) }!
        #expect(plain(lunchWarn.body) == "Next: Focus block at 1:00 PM.")
    }

    @Test func aMomentIsNeverCurrentButCanBeNext() {
        let p = planner([Block(id: "x", title: "Call mum", start: "12:30", end: "", days: [1], type: "default")])
        let day = p.blocksFor(monday)
        let now = date(2026, 11, 2, 12, 30)
        #expect(day.first { $0.start <= now && now < $0.end }?.title == "Lunch")
        #expect(day.first { $0.start > date(2026, 11, 2, 12, 10) }?.title == "Call mum")
        #expect(p.blocksFor(monday).first { $0.title == "Call mum" }.map { $0.start == $0.end } == true)
    }

    @Test func checksAndEdits() {
        #expect(ScheduleEdits.problem(medicine) == nil)
        #expect(ScheduleEdits.overlap(medicine, in: Specs.sampleSchedule() + [medicine]) == nil)
        let lunch = Specs.sampleSchedule()[3]
        #expect(ScheduleEdits.overlap(lunch, in: [lunch, medicine]) == nil) // a moment isn't a clash
        let moved = ScheduleEdits.moved(medicine, by: 30)
        #expect(moved.start == "13:30" && moved.isMoment)
        #expect(ScheduleEdits.resized(medicine, end: 900) == medicine)
        let after = ScheduleEdits.newBlockAfterLatest([medicine])
        #expect(after.start == "13:00" && after.end == "13:30" && !after.isMoment)
        #expect(ScheduleEdits.columns([medicine, lunch])["m"] == nil)
    }

    @Test func ownReminders() {
        var own = Specs.startingTypeReminders
        own.start.sound = "rooster-crowing"
        own.warn.on = false
        let b = Block(id: "o", title: "Run", start: "18:00", end: "19:00", days: [1], type: Specs.ownType, reminders: own)
        let p = planner([b])
        #expect(p.typeName(for: b) == "Own")
        let evs = p.events(on: monday).filter { $0.blockId == "o" }
        #expect(evs.map(\.role) == [.start, .end])
        #expect(evs[0].sound == "rooster-crowing")
    }

    @Test func savingAndReloading() throws {
        let s = tempStore()
        var own = Specs.startingTypeReminders
        own.prep.on = true
        try s.saveBlocks([medicine, Block(id: "o", title: "Run", start: "18:00", end: "19:00", days: [1], type: "own", reminders: own)])
        s.load()
        #expect(s.blocks.first { $0.id == "m" }?.isMoment == true)
        #expect(s.blocks.first { $0.id == "o" }?.reminders?.prep.on == true)
        // "own" without reminders isn't a type: it falls back to Default.
        let raw = try JSONValue.decode(Data(#"[{"title":"X","start":"09:00","end":"","days":[1],"type":"own"}]"#.utf8))
        #expect(try Sanitize.blocks(raw, typeIds: ["default"]).first?.type == "default")
    }

    @Test func removingAClipResetsAnOwnReminder() throws {
        let s = tempStore()
        let clip = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        var own = Specs.startingTypeReminders
        own.start.sound = clip.soundId
        try s.saveBlocks([Block(id: "o", title: "Run", start: "18:00", end: "19:00", days: [1], type: "own", reminders: own)])
        #expect(try s.removeClip(clip.id) == ["Run · Start"])
        #expect(s.blocks[0].reminders?.start.sound == Specs.spec(TypeReminderKey.start).sound)
        s.load()
        #expect(s.blocks[0].reminders?.start.sound == Specs.spec(TypeReminderKey.start).sound)
    }

    @Test func versionThreeFilesRoundTrip() throws {
        let a = tempStore()
        let clip = try a.installClip(name: "Ding", ext: "mp3", data: Data([7, 7]))
        var own = Specs.startingTypeReminders
        own.start.sound = clip.soundId
        try a.saveBlocks([medicine, Block(id: "o", title: "Run", start: "18:00", end: "19:00", days: [1], type: "own", reminders: own)])
        let export = a.exportPayload()
        #expect(export["dayflowExport"] == .number(3))
        #expect(export["clips"]?.array?.count == 1) // the own reminder's clip travels too
        let b = tempStore()
        let p = try b.readImport(try JSONFile.encode(export), fileName: "x.json")
        #expect(p.blocks.map(\.typeName).contains("Own"))
        try b.applyImport(p, applySettings: true)
        #expect(b.blocks.first { $0.id == "m" }?.isMoment == true)
        let run = try #require(b.blocks.first { $0.id == "o" })
        #expect(run.hasOwnReminders && run.reminders?.start.sound == clip.soundId && b.clips.count == 1)
    }

    @Test func deletingATypeLeavesOwnBlocksAlone() throws {
        let s = tempStore()
        try s.startSchedule(sample: false)
        try s.saveBlocks([Block(id: "o", title: "Run", start: "18:00", end: "19:00", days: [1], type: "own", reminders: Specs.startingTypeReminders),
                          Block(id: "f", title: "Read", start: "20:00", end: "21:00", days: [1], type: "focus")])
        try s.saveTypes(s.types.filter { $0.id != "focus" })
        #expect(s.blocks.first { $0.id == "o" }?.hasOwnReminders == true)
        #expect(s.blocks.first { $0.id == "f" }?.type == "default")
    }
}
