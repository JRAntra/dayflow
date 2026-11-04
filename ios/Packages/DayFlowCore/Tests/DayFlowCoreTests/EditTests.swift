import Foundation
import Testing
@testable import DayFlowCore

@Suite struct EditTests {
    let deep = Block(id: "b2", title: "Deep work", start: "09:20", end: "11:30", days: [1, 2, 3, 4, 5], type: "focus")

    @Test func problems() {
        #expect(ScheduleEdits.problem(Block(title: "", start: "09:00", end: "10:00", days: [1], type: "default")) == "Give this block a name.")
        #expect(ScheduleEdits.problem(Block(title: "A", start: "10:00", end: "09:00", days: [1], type: "default")) == "End time must be after the start time.")
        #expect(ScheduleEdits.problem(Block(title: "A", start: "09:00", end: "10:00", days: [], type: "default")) == "Pick at least one day, or this block never runs.")
        #expect(ScheduleEdits.problem(deep) == nil)
    }

    @Test func overlaps() {
        let lunch = Block(id: "l", title: "Lunch", start: "11:00", end: "12:00", days: [2], type: "default")
        let other = Block(id: "o", title: "Other", start: "11:00", end: "12:00", days: [6], type: "default")
        #expect(ScheduleEdits.overlapText(deep, in: [deep, other]) == nil)
        #expect(ScheduleEdits.overlapText(deep, in: [deep, lunch, other]) == "Overlaps Lunch on Tuesday")
        let touching = Block(id: "t", title: "T", start: "11:30", end: "12:00", days: [1], type: "default")
        #expect(ScheduleEdits.overlap(deep, in: [touching]) == nil)
    }

    @Test func daysText() {
        #expect(ScheduleEdits.daysText([1, 2, 3, 4, 5]) == "Weekdays")
        #expect(ScheduleEdits.daysText([0, 1, 2, 3, 4, 5, 6]) == "Every day")
        #expect(ScheduleEdits.daysText([6, 0]) == "Weekends")
        #expect(ScheduleEdits.daysText([2]) == "Tuesdays")
        #expect(ScheduleEdits.daysText([0, 1, 3]) == "Mon, Wed, Sun")
    }

    @Test func addBlockFollowsTheLatestOne() {
        let b = ScheduleEdits.newBlockAfterLatest(Specs.sampleSchedule())
        #expect((b.start, b.end, b.days, b.type) == ("17:15", "17:45", [1, 2, 3, 4, 5], "default"))
        let first = ScheduleEdits.newBlockAfterLatest([])
        #expect((first.start, first.end) == ("09:00", "09:30"))
        let late = ScheduleEdits.newBlockAfterLatest([Block(title: "L", start: "23:00", end: "23:59", days: [1], type: "x")])
        #expect((late.start, late.end, late.type) == ("23:29", "23:59", "x"))
    }

    @Test func tapAnEmptySlot() {
        let b = ScheduleEdits.newBlock(at: 12 * 60 + 2, day: 2, blocks: Specs.sampleSchedule())
        #expect((b.start, b.end, b.days) == ("12:00", "12:30", [1, 2, 3, 4, 5])) // after Email and messages
        let sat = ScheduleEdits.newBlock(at: 600, day: 6, blocks: Specs.sampleSchedule())
        #expect((sat.start, sat.days, sat.type) == ("10:00", [6], "default"))
    }

    @Test func moveAndResize() {
        let m = ScheduleEdits.moved(deep, by: 40)
        #expect((m.start, m.end) == ("10:00", "12:10"))
        #expect(ScheduleEdits.moved(deep, by: -1000).start == "00:00")
        #expect(ScheduleEdits.moved(deep, by: 2000).end == "23:59")
        #expect(ScheduleEdits.resized(deep, end: 9 * 60).end == "09:25") // at least 5 minutes
        #expect(ScheduleEdits.resized(deep, start: 11 * 60 + 29).start == "11:25")
        #expect(ScheduleEdits.snap(563) == 565 && ScheduleEdits.snap(562) == 560)
    }

    @Test func thisDayOnlySplitsTheBlock() {
        let blocks = [deep, Specs.sampleSchedule()[0]]
        let edited = ScheduleEdits.moved(deep, by: 40)
        #expect(ScheduleEdits.needsDayChoice(deep, day: 2))
        let split = ScheduleEdits.apply(edited, original: deep, day: 2, allDays: false, in: blocks)
        #expect(split.count == 3)
        let rest = split.first { $0.id == "b2" }!
        #expect(rest.days == [1, 3, 4, 5] && rest.start == "09:20")
        let tue = split.first { $0.id != "b2" && $0.id != "b1" }!
        #expect(tue.days == [2] && tue.start == "10:00" && tue.end == "12:10" && tue.type == "focus" && tue.title == "Deep work")

        let all = ScheduleEdits.apply(edited, original: deep, day: 2, allDays: true, in: blocks)
        #expect(all.count == 2 && all.first { $0.id == "b2" }?.start == "10:00")

        // One-day blocks never ask, and are just changed.
        let single = Block(id: "s", title: "S", start: "09:00", end: "10:00", days: [2], type: "default")
        #expect(!ScheduleEdits.needsDayChoice(single, day: 2))
        #expect(ScheduleEdits.apply(ScheduleEdits.moved(single, by: 30), original: single, day: 2, allDays: false, in: [single]).map(\.start) == ["09:30"])
    }

    @Test func removeFromOneDay() {
        let out = ScheduleEdits.removing(deep, day: 3, from: [deep])
        #expect(out.first?.days == [1, 2, 4, 5])
        #expect(ScheduleEdits.removing(deep, day: nil, from: [deep]).isEmpty)
    }

    @Test func overlappingBlocksSitSideBySide() {
        let a = Block(id: "a", title: "A", start: "09:00", end: "10:00", days: [1], type: "d")
        let b = Block(id: "b", title: "B", start: "09:30", end: "10:30", days: [1], type: "d")
        let c = Block(id: "c", title: "C", start: "10:00", end: "11:00", days: [1], type: "d")
        let d = Block(id: "d", title: "D", start: "12:00", end: "13:00", days: [1], type: "d")
        let cols = ScheduleEdits.columns([a, b, c, d])
        #expect(cols["a"]! == (0, 2) && cols["b"]! == (1, 2) && cols["c"]! == (0, 2))
        #expect(cols["d"]! == (0, 1))
    }
}
