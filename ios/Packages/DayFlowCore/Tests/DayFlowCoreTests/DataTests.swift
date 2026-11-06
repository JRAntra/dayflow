import Foundation
import Testing
@testable import DayFlowCore

func tempStore() -> DataStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dayflow-tests-\(UUID().uuidString)")
    return DataStore(dir: root.appendingPathComponent("data"))
}

/// A store with Default and three more types (Focus, Break, Meal), as tests need them.
func storeWithTypes() throws -> DataStore {
    let s = tempStore()
    try s.startSchedule()
    try s.saveTypes(s.types + ["Focus", "Break", "Meal"].map { BlockType(id: $0.lowercased(), name: $0) })
    return s
}

@Suite struct DataTests {
    @Test func freshStoreStartsEmptyWithDefault() throws {
        let s = tempStore()
        #expect(!s.hasSchedule)
        #expect(s.blocks.isEmpty)
        #expect(s.types.map(\.name) == ["Default"])
        try s.startSchedule()
        #expect(s.blocks.isEmpty && s.hasSchedule)
        s.load()
        #expect(s.blocks.isEmpty)
    }

    @Test func addASampleDay() throws {
        let s = tempStore()
        try s.startSchedule()
        try s.saveBlocks([Block(id: "b1", title: "Mine", start: "07:00", end: "08:00", days: [1], type: "default")])
        try s.addSampleDay()
        #expect(s.blocks.count == 9)
        #expect(Set(s.blocks.map(\.id)).count == 9) // the sample's b1 gets a new id
        #expect(s.blocks.allSatisfy { $0.type == "default" })
    }

    @Test func ownRemindersBecomeTypes() throws {
        let s = tempStore()
        try s.startSchedule()
        try s.saveTypes(s.types + [BlockType(id: "run", name: "Run")])
        // A schedule saved by an earlier DayFlow: two blocks with their own reminders.
        let file = #"""
        {"blocks":[
          {"id":"a","title":"Run","start":"07:00","end":"08:00","days":[1],"type":"own",
           "reminders":{"start":{"on":true,"sound":"rooster-crowing"},"warn":{"on":false},"end":{"on":true}}},
          {"id":"b","title":"Read","start":"21:00","end":"22:00","days":[1],"type":"own","reminders":{}},
          {"id":"c","title":"Plan","start":"09:00","end":"09:20","days":[1],"type":"default"}]}
        """#
        try Data(file.utf8).write(to: s.dir.appendingPathComponent("schedule.json"))
        s.load()
        let run = try #require(s.blocks.first { $0.id == "a" })
        let runType = s.typeOf(run.type)
        #expect(runType.name == "Run (2)") // "Run" was taken
        #expect(runType.reminders.start.sound == "rooster-crowing" && !runType.reminders.warn.on)
        #expect(s.typeOf(s.blocks.first { $0.id == "b" }!.type).name == "Read")
        #expect(s.blocks.first { $0.id == "c" }?.type == "default")
        // It's saved that way: loading again changes nothing.
        let types = s.types.count
        s.load()
        #expect(s.types.count == types && s.blocks.allSatisfy { $0.type != "own" })
        let saved = String(decoding: try Data(contentsOf: s.dir.appendingPathComponent("schedule.json")), as: UTF8.self)
        #expect(!saved.contains("\"own\"") && !saved.contains("reminders"))
    }

    @Test func filesMatchTheMacShapes() throws {
        let s = tempStore()
        try s.startSchedule()
        try s.addSampleDay()
        let sched = try JSONValue.decode(Data(contentsOf: s.dir.appendingPathComponent("schedule.json")))
        let first = try #require(sched["blocks"]?.array?.first?.object)
        #expect(Set(first.keys) == ["id", "title", "start", "end", "days", "type"])
        let types = try JSONValue.decode(Data(contentsOf: s.dir.appendingPathComponent("block-types.json")))
        let rem = try #require(types.array?.first?["reminders"])
        #expect(Set(rem["prep"]!.object!.keys) == ["on", "sound", "fade", "lead"])
        #expect(Set(rem["start"]!.object!.keys) == ["on", "sound", "fade"]) // no lead on Start
    }

    @Test func blockChecks() throws {
        let s = try storeWithTypes()
        #expect(throws: DataError("Block 1 needs a name.")) {
            try s.saveBlocks([Block(title: " ", start: "09:00", end: "10:00", days: [1], type: "default")])
        }
        #expect(throws: DataError("\"A\" must end after it starts.")) {
            try s.saveBlocks([Block(title: "A", start: "10:00", end: "10:00", days: [1], type: "default")])
        }
        #expect(throws: DataError("\"A\" has an invalid time.")) {
            try s.saveBlocks([Block(title: "A", start: "9:00", end: "10:00", days: [1], type: "default")])
        }
        // An unknown type becomes Default; days are cleaned; blocks are sorted.
        try s.saveBlocks([Block(id: "2", title: "B", start: "11:00", end: "12:00", days: [3, 3, 1], type: "nope"),
                          Block(id: "1", title: "A", start: "09:00", end: "10:00", days: [1], type: "focus")])
        #expect(s.blocks.map(\.id) == ["1", "2"])
        #expect(s.blocks[1].type == "default" && s.blocks[1].days == [1, 3])
    }

    @Test func typeChecksAndDeletingMovesBlocksToDefault() throws {
        let s = try storeWithTypes()
        try s.addSampleDay()
        var types = s.types
        #expect(throws: DataError("The Default type can't be deleted.")) { try s.saveTypes(Array(types.dropFirst())) }
        types[1].name = "default "
        types[2].name = "DEFAULT"
        #expect(throws: DataError("There are two block types called \"default\".")) { try s.saveTypes(types) }
        var blocks = s.blocks
        blocks[0].type = "meal"
        try s.saveBlocks(blocks)
        try s.saveTypes(s.types.filter { $0.id != "meal" })
        #expect(s.blocks[0].type == "default")
        // Default always comes first.
        try s.saveTypes(s.types.reversed())
        #expect(s.types.first?.isDefault == true)
    }

    @Test func clips() throws {
        let s = try storeWithTypes()
        #expect(throws: DataError("\"x\" isn't an mp3, wav, m4a, aac or ogg file.")) { try s.installClip(name: "x", ext: "flac", data: Data([1])) }
        #expect(throws: DataError("\"x\" is empty.")) { try s.installClip(name: "x", ext: "mp3", data: Data()) }
        let a = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        let again = try s.installClip(name: "Other name", ext: "mp3", data: Data([1]))
        #expect(a == again)
        let b = try s.installClip(name: "Ding", ext: "mp3", data: Data([2]))
        #expect(b.name == "Ding (2)")
        #expect(a.id == String(DataStore.clipHash(Data([1]))) && a.id.count == 16)

        var types = s.types
        types[1].reminders.warn.sound = b.soundId
        try s.saveTypes(types)
        var settings = s.settings
        settings.meetings.start.sound = b.soundId
        try s.saveSettings(settings)
        #expect(try s.removeClip(b.id) == ["Focus · Heads-up", "Meetings · Starting now"])
        #expect(s.types[1].reminders.warn.sound == Specs.spec(.warn).sound)
        s.load()
        #expect(s.clips == [a])
        #expect(s.settings.meetings.start.sound == Specs.spec(MeetingReminderKey.start).sound)
    }

    @Test func settingsSurviveAReload() throws {
        let s = tempStore()
        var settings = s.settings
        settings.pausedUntil = Date(timeIntervalSinceReferenceDate: 800_000_000)
        settings.calendars = ["A", "B"]
        settings.onboarded = true
        settings.volume = 140
        try s.saveSettings(settings)
        s.load()
        #expect(s.settings.pausedUntil == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(s.settings.calendars == ["A", "B"])
        #expect(s.settings.onboarded && s.settings.volume == 100)
        // Clearing the pause (Resume) sticks.
        settings = s.settings
        settings.pausedUntil = nil
        try s.saveSettings(settings)
        #expect(s.settings.pausedUntil == nil)
        s.load()
        #expect(s.settings.pausedUntil == nil && s.settings.calendars == ["A", "B"])
    }
}
