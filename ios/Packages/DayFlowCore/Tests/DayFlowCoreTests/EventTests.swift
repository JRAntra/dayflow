import Foundation
import Testing
@testable import DayFlowCore

/// Repeated events, checking off, skipping for today, the streak, and reminders with several sounds.
@Suite struct EventTests {
    let monday = date(2026, 11, 2)
    let water = RepeatRule(id: "rw", first: "09:00", last: "17:00", every: 30)

    func planner(_ blocks: [Block], progress: DayProgress = DayProgress()) -> Planner {
        Planner(blocks: blocks, types: Specs.starterTypes(), meetingReminders: Specs.startingMeetingReminders,
                calendar: testCalendar, locale: testLocale, progress: progress)
    }
    func key(_ d: Date) -> String { planner([]).dayKey(d) }

    // MARK: Repeats

    @Test func repeatTimes() {
        #expect(ScheduleEdits.repeatTimes(water).count == 17) // 9:00, 9:30 … 17:00
        let t45 = ScheduleEdits.repeatTimes(RepeatRule(first: "09:00", last: "17:00", every: 45))
        #expect(t45.count == 11 && t45.last == 16 * 60 + 30) // 17:00 isn't on the 45-minute beat
        #expect(ScheduleEdits.repeatProblem(title: "Water", days: [1], rule: water) == nil)
        #expect(ScheduleEdits.repeatProblem(title: " ", days: [1], rule: water) == "Give this event a name.")
        #expect(ScheduleEdits.repeatProblem(title: "W", days: [], rule: water) == "Pick at least one day, or this event never rings.")
        #expect(ScheduleEdits.repeatProblem(title: "W", days: [1], rule: RepeatRule(first: "17:00", last: "09:00", every: 30))
                == "The last time must be after the first.")
        #expect(ScheduleEdits.repeatProblem(title: "W", days: [1], rule: RepeatRule(first: "09:00", last: "17:00", every: 0))
                == "Every must be from 1 to 720 minutes.")
        #expect(ScheduleEdits.repeatProblem(title: "W", days: [1], rule: RepeatRule(first: "09:00", last: "09:20", every: 30))
                == "That makes only one event. Make the gap shorter, or the last time later.")
        #expect(ScheduleEdits.repeatProblem(title: "W", days: [1], rule: RepeatRule(first: "00:00", last: "23:59", every: 1))
                == "That would make more than 200 events. Make the gap longer.")
    }

    @Test func remakingARepeatKeepsTheTimesItStillHas() throws {
        let made = ScheduleEdits.makeRepeat(title: "Water", days: [1, 2], alert: Specs.startingEventAlert, rule: water)
        #expect(made.count == 17 && made.allSatisfy { $0.isEvent && $0.series == water })
        #expect(made[0].id == "rw-0900" && made[16].id == "rw-1700")
        var p = DayProgress()
        p.setDone("rw-0900", true, day: key(monday))
        p.setSkipped("rw-0930", true, day: key(monday))

        let s = tempStore()
        try s.saveBlocks(Specs.sampleSchedule() + made)
        try s.saveProgress(p)
        // Every 45 minutes instead: 11 events, 9:00 still among them; 9:30 isn't.
        var rule = water
        rule.every = 45
        let remade = ScheduleEdits.makeRepeat(title: "Water", days: [1, 2], alert: Specs.startingEventAlert, rule: rule)
        try s.saveBlocks(ScheduleEdits.replacingRepeat("rw", with: remade, in: s.blocks))
        #expect(ScheduleEdits.repeatEvents("rw", in: s.blocks).count == 11)
        #expect(s.progress.isDone("rw-0900", on: key(monday)))
        #expect(!s.progress.isSkipped("rw-0930", on: key(monday))) // gone, so dropped
        // Deleting them all.
        try s.saveBlocks(ScheduleEdits.replacingRepeat("rw", with: [], in: s.blocks))
        #expect(s.blocks.count == 8)

        // Saved and read back with the rule.
        let t = tempStore()
        try t.saveBlocks(made)
        t.load()
        #expect(t.blocks.allSatisfy { $0.series == water })
    }

    @Test func editingOnlyOneTakesItOut() {
        let made = ScheduleEdits.makeRepeat(title: "Water", days: [1], alert: Specs.startingEventAlert, rule: water)
        let (one, list) = ScheduleEdits.detached(made[3], in: made)
        #expect(one.series == nil && one.id != made[3].id && one.start == made[3].start)
        #expect(ScheduleEdits.repeatEvents("rw", in: list).count == 16 && list.count == 17)
    }

    @Test func switchingBetweenEventAndBlock() {
        let b = Specs.sampleSchedule()[1] // Deep work, Default
        let e = ScheduleEdits.switched(b, toEvent: true, types: Specs.starterTypes())
        #expect(e.isEvent && e.type == "event" && e.reminders == nil && e.alert?.sound == Specs.spec(TypeReminderKey.start).sound)
        let back = ScheduleEdits.switched(e, toEvent: false, types: Specs.starterTypes())
        #expect(!back.isEvent && back.end == "09:50" && back.type == "default" && back.alert == nil)
        let late = ScheduleEdits.switched(.event(title: "L", start: "23:50", days: [1], alert: Specs.startingEventAlert),
                                          toEvent: false, types: Specs.starterTypes())
        #expect(late.start == "23:50" && late.end == "23:59")
    }

    @Test func badRulesAreDropped() throws {
        let raw = try JSONValue.decode(Data(#"""
        [{"id":"a","title":"W","start":"09:00","days":[1],"series":{"id":"r1","first":"09:00","last":"10:00","every":0}},
         {"id":"b","title":"W","start":"09:00","days":[1],"series":{"id":"r1","first":"09:00","last":"10:00","every":30}}]
        """#.utf8))
        let list = try Sanitize.blocks(raw, typeIds: ["default"])
        #expect(list.map { $0.series?.every } == [nil, 30])
    }

    // MARK: Checking off and skipping

    @Test func aCheckedOffEventDoesntRing() {
        let pill = Block.event(id: "p", title: "Pill", start: "13:10", days: [1], alert: Specs.startingEventAlert)
        var progress = DayProgress()
        progress.setDone("p", true, day: key(monday))
        let p = planner([pill], progress: progress)
        #expect(p.events(on: monday).isEmpty)
        // It's still in the day, checked off.
        #expect(p.blocksFor(monday).map(\.id) == ["p"] && p.isDone("p", on: monday))
        // Only that day: next Monday it rings.
        #expect(p.events(on: date(2026, 11, 9)).count == 1)
    }

    @Test func aSkippedBlockIsGoneForTheDay() {
        var progress = DayProgress()
        progress.setSkipped("b2", true, day: key(monday)) // Deep work
        let p = planner(Specs.sampleSchedule(), progress: progress)
        #expect(!p.blocksFor(monday).contains { $0.id == "b2" })
        #expect(p.blocksFor(monday, includeSkipped: true).contains { $0.id == "b2" })
        let evs = p.events(on: monday)
        #expect(!evs.contains { $0.blockId == "b2" })
        // Plan the day hands straight over to nothing at 9:20; Email starts at 11:30 on its own.
        #expect(plain(evs.first { $0.at == date(2026, 11, 2, 9, 20) }!.body) == "Free until Email and messages at 11:30 AM.")
        // The next day it's back.
        #expect(p.blocksFor(date(2026, 11, 3)).contains { $0.id == "b2" })
    }

    @Test func skippingAndCheckingAreExclusive() {
        var p = DayProgress()
        p.setDone("x", true, day: "2026-11-2")
        p.setSkipped("x", true, day: "2026-11-2")
        #expect(!p.isDone("x", on: "2026-11-2") && p.isSkipped("x", on: "2026-11-2"))
        p.setSkipped("x", false, day: "2026-11-2")
        #expect(p.days["2026-11-2"] == nil) // nothing left: the day goes
        #expect(p.since == "2026-11-2")
    }

    @Test func progressIsSavedButNeverExported() throws {
        let s = tempStore()
        var p = DayProgress()
        p.setDone("b1", true, day: "2026-11-2")
        try s.saveProgress(p)
        s.load()
        #expect(s.progress.isDone("b1", on: "2026-11-2"))
        #expect(s.exportPayload().object?.keys.contains { $0.lowercased().contains("progress") } == false)
    }

    // MARK: The streak

    func events(_ days: [Int] = [0, 1, 2, 3, 4, 5, 6]) -> [Block] {
        (1...5).map { Block.event(id: "e\($0)", title: "E\($0)", start: HHMM.string(9 * 60 + $0 * 60), days: days, alert: Specs.startingEventAlert) }
    }

    @Test func streakCountsDaysWithEightyPercentDone() {
        var progress = DayProgress()
        // Wed 28 Oct: 3 of 5 (60%) breaks it. Thu–Sun: 4 of 5. Mon 2 Nov (today): 2 so far.
        let d = { (n: Int) in date(2026, 10, 28 + n) }
        for i in 0..<6 {
            let done = i == 0 ? 3 : (i == 5 ? 2 : 4)
            for e in 1...done { progress.setDone("e\(e)", true, day: key(d(i))) }
        }
        let now = date(2026, 11, 2, 15)
        var p = planner(events(), progress: progress)
        #expect(p.result(on: now) == (done: 2, total: 5))
        #expect(p.streak(at: now) == 4) // Thu, Fri, Sat, Sun
        // Two more done today: today joins.
        progress.setDone("e3", true, day: key(now))
        progress.setDone("e4", true, day: key(now))
        p.progress = progress
        #expect(p.streak(at: now) == 5)
    }

    @Test func skippedEventsDontCountAndEmptyDaysDontBreakIt() {
        var progress = DayProgress()
        let sat = date(2026, 10, 31), sun = date(2026, 11, 1), now = date(2026, 11, 2, 20)
        // Saturday: 1 skipped, the other 4 done: 4 of 4.
        progress.setSkipped("e5", true, day: key(sat))
        for e in 1...4 { progress.setDone("e\(e)", true, day: key(sat)) }
        // Sunday: no events planned (they're weekdays and Saturdays only).
        // Today: all done.
        for e in 1...5 { progress.setDone("e\(e)", true, day: key(now)) }
        let p = planner(events([1, 2, 3, 4, 5, 6]), progress: progress)
        #expect(p.result(on: sat) == (done: 4, total: 4))
        #expect(p.result(on: sun).total == 0)
        #expect(p.streak(at: now) == 2) // Saturday, (Sunday passed over), today
    }

    @Test func pastDaysUseWhatDayFlowSaw() {
        var progress = DayProgress()
        let sun = date(2026, 11, 1), now = date(2026, 11, 2, 8)
        for e in 1...4 { progress.setDone("e\(e)", true, day: key(sun)) }
        let seen = planner(events(), progress: progress).noting(sun) // 4 of 5
        #expect(seen.days[key(sun)]?.total == 5 && seen.days[key(sun)]?.count == 4)
        // Then two of its events were deleted from the plan: Sunday still counts as 4 of 5.
        let p = planner(Array(events().prefix(3)), progress: seen)
        #expect(p.streak(at: now) == 1)
        // A day DayFlow never saw, with events planned, breaks the streak.
        var gap = seen
        gap.since = key(date(2026, 10, 30))
        #expect(planner(events(), progress: gap).streak(at: now) == 1) // Sunday, then Saturday unseen
    }

    // MARK: Several sounds

    @Test func neverTheSameSoundTwiceInARow() {
        for n in 2...5 {
            let choices = (0..<n).map { "s\($0)" }
            let picks = (0..<300).map { SoundPick.pick(choices, stream: "x\(n)", index: $0) }
            #expect(zip(picks, picks.dropFirst()).allSatisfy { $0 != $1 }, "n = \(n)")
            #expect(Set(picks).count == n, "every sound gets a turn, n = \(n)")
        }
        #expect(SoundPick.pick(["only"], stream: "x", index: 5) == "only")
        #expect(SoundPick.hash("DayFlow") == 0xb37bb78d) // FNV-1a, the same as the Mac's soundPick
    }

    /// The Mac's soundPick (main.js) makes exactly these picks too.
    @Test func picksMatchTheMac() {
        func seq(_ c: [String], _ stream: String) -> String { (0..<12).map { SoundPick.pick(c, stream: stream, index: $0) }.joined(separator: ",") }
        #expect(seq(["a", "b", "c"], "series|rw") == "a,c,b,a,c,b,a,b,c,b,c,b")
        #expect(seq(["a", "b"], "b2|start") == "b,a,b,a,b,a,b,a,b,a,b,a")
        #expect(seq(["a", "b", "c", "d"], "x") == "d,c,b,c,d,c,b,c,d,c,a,b")
    }

    @Test func aRepeatsEventsDontRepeatASound() {
        var alert = Specs.startingEventAlert
        alert.choices = ["class-bell", "flute-notification", "sleigh-bells"]
        let made = ScheduleEdits.makeRepeat(title: "Water", days: [1, 2], alert: alert, rule: water)
        let p = planner(made)
        let sounds = (p.events(on: monday) + p.events(on: date(2026, 11, 3))).sorted { $0.at < $1.at }.compactMap(\.sound)
        #expect(sounds.count == 34)
        #expect(zip(sounds, sounds.dropFirst()).allSatisfy { $0 != $1 })
        // The same every time it's worked out, so alarms aren't set again needlessly.
        #expect(p.events(on: monday).compactMap(\.sound) == planner(made).events(on: monday).compactMap(\.sound))
    }

    @Test func soundListsAreCleanedAndSaved() throws {
        let raw = try JSONValue.decode(Data(#"""
        {"on":true,"sound":"class-bell","sounds":["class-bell","nope","flute-notification","class-bell"]}
        """#.utf8))
        let r = Sanitize.reminder(raw, Specs.eventSpec, isSound: { Specs.builtinIds.contains($0) })
        #expect(r.choices == ["class-bell", "flute-notification"] && r.sound == "class-bell")
        let one = Sanitize.reminder(raw, Specs.eventSpec, many: false, isSound: { Specs.builtinIds.contains($0) })
        #expect(one.choices == ["class-bell"] && one.sounds == nil)
        // Meetings keep one sound.
        let m = Sanitize.meetingReminders(.object(["start": raw]), isSound: { Specs.builtinIds.contains($0) })
        #expect(m.start.sounds == nil)
        // One sound is written as before, without `sounds`.
        let file = String(decoding: try JSONFile.encode(Specs.startingEventAlert), as: UTF8.self)
        #expect(!file.contains("sounds"))
    }

    @Test func removingAClipFromAListKeepsTheRest() throws {
        let s = tempStore()
        try s.startSchedule(sample: false)
        let clip = try s.installClip(name: "Ding", ext: "mp3", data: Data([1, 2]))
        var alert = Specs.startingEventAlert
        alert.choices = [clip.soundId, "class-bell"]
        var lone = Specs.startingEventAlert
        lone.choices = [clip.soundId]
        try s.saveBlocks([.event(id: "a", title: "Pill", start: "09:00", days: [1], alert: alert),
                          .event(id: "b", title: "Stretch", start: "10:00", days: [1], alert: lone)])
        #expect(try s.removeClip(clip.id) == ["Stretch"])
        s.load()
        #expect(s.blocks.first { $0.id == "a" }?.alert?.choices == ["class-bell"])
        #expect(s.blocks.first { $0.id == "b" }?.alert?.choices == [Specs.eventSpec.sound])
    }

    @Test func eventsAndTheirClipsTravelInExports() throws {
        let a = tempStore()
        try a.startSchedule(sample: false)
        let clip = try a.installClip(name: "Ding", ext: "mp3", data: Data([3, 3]))
        var alert = Specs.startingEventAlert
        alert.choices = ["class-bell", clip.soundId]
        try a.saveBlocks(ScheduleEdits.makeRepeat(title: "Water", days: [1], alert: alert, rule: water))
        let export = a.exportPayload()
        #expect(export["dayflowExport"] == .number(5) && export["clips"]?.array?.count == 1)
        let b = tempStore()
        try b.startSchedule(sample: false)
        let preview = try b.readImport(try JSONFile.encode(export), fileName: "x.json")
        #expect(preview.blocks.first?.typeName == "Repeated event")
        try b.applyImport(preview, applySettings: false)
        #expect(b.blocks.count == 17 && b.blocks.allSatisfy { $0.series == water && $0.type == "event" })
        #expect(b.blocks[0].alert?.choices == ["class-bell", clip.soundId] && b.clips.count == 1)
    }
}
