import Foundation
import Testing
@testable import DayFlowCore

func tempStore() -> DataStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dayflow-tests-\(UUID().uuidString)")
    return DataStore(dir: root.appendingPathComponent("data"), backupsDir: root.appendingPathComponent("Backups"))
}

/// An export in the shape the Mac app writes (src/main.js exportPayload), with a custom clip.
let macExport = """
{
  "dayflowExport": 2,
  "exportedAt": "2026-11-03T15:04:05.000Z",
  "schedule": { "blocks": [
    { "id": "b2", "title": "Deep work", "start": "09:20", "end": "11:30", "days": [1,2,3,4,5], "type": "focus" },
    { "id": "b1", "title": "Plan the day", "start": "09:00", "end": "09:20", "days": [1,2,3,4,5], "type": "default" },
    { "id": "bx", "title": "Gym", "start": "18:00", "end": "19:00", "days": [6,2,2,9], "type": "sport" }
  ]},
  "blockTypes": [
    { "id": "default", "name": "Everyday", "isDefault": true, "reminders": {
      "prep": { "on": true, "sound": "custom:0123456789abcdef", "fade": true, "lead": 10 },
      "start": { "on": true, "sound": "class-bell", "fade": false },
      "warn": { "on": false, "sound": "notification-bell", "fade": false, "lead": 3 },
      "end": { "on": true, "sound": "custom:ffffffffffffffff", "fade": false } } },
    { "id": "focus", "name": "Focus", "reminders": {
      "prep": { "on": false, "sound": "fairy-bell-bless", "fade": false, "lead": 5 },
      "start": { "on": true, "sound": "flute-notification", "fade": true },
      "warn": { "on": true, "sound": "notification-bell", "fade": false, "lead": 99 },
      "end": { "on": true, "sound": "clock-bells-hour-signal", "fade": false } } },
    { "id": "sport", "name": "Sport", "reminders": {} }
  ],
  "settings": { "volume": 55, "meetings": {
    "before": { "on": true, "sound": "airport-announcement-ding", "fade": false, "lead": 2 },
    "start": { "on": false, "sound": "elegant-door-announcement", "fade": false } } },
  "clips": [ { "id": "0123456789abcdef", "name": "My chime", "ext": "wav", "data": "UklGRgAAAAA=" } ]
}
"""

@Suite struct DataTests {
    @Test func freshStoreStartsWithTheSample() throws {
        let s = tempStore()
        #expect(!s.hasSchedule)
        #expect(s.blocks.count == 8)
        #expect(s.types.map(\.name) == ["Default", "Focus", "Break", "Admin", "Meal"])
        try s.startSchedule(sample: false)
        #expect(s.blocks.isEmpty && s.hasSchedule)
        s.load()
        #expect(s.blocks.isEmpty)
    }

    @Test func filesMatchTheMacShapes() throws {
        let s = tempStore()
        try s.startSchedule(sample: true)
        let sched = try JSONValue.decode(Data(contentsOf: s.dir.appendingPathComponent("schedule.json")))
        let first = try #require(sched["blocks"]?.array?.first?.object)
        #expect(Set(first.keys) == ["id", "title", "start", "end", "days", "type"])
        let types = try JSONValue.decode(Data(contentsOf: s.dir.appendingPathComponent("block-types.json")))
        let rem = try #require(types.array?.first?["reminders"])
        #expect(Set(rem["prep"]!.object!.keys) == ["on", "sound", "fade", "lead"])
        #expect(Set(rem["start"]!.object!.keys) == ["on", "sound", "fade"]) // no lead on Start
    }

    @Test func blockChecks() throws {
        let s = tempStore()
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
        let s = tempStore()
        try s.startSchedule(sample: true)
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

    @Test func importAMacExport() throws {
        let s = tempStore()
        try s.startSchedule(sample: true)
        let p = try s.readImport(Data(macExport.utf8), fileName: "DayFlow schedule 2026-11-03.json")
        #expect(p.current == 8)
        #expect(p.blocks.map(\.block.title) == ["Plan the day", "Deep work", "Gym"])
        #expect(p.blocks.map(\.typeName) == ["Default", "Focus", "Sport"]) // the file's Default shows as yours
        #expect(p.blocks[2].block.days == [2, 6])
        #expect(p.newTypes == ["Sport"])
        #expect(p.hasSettings && !p.isBackup)
        #expect(p.clips.map(\.name) == ["My chime"])
        #expect(p.clips[0].slots == "Everyday · Start preparation")
        #expect(p.problems == ["A sound clip is missing from the file, so Everyday · Time's up will use the starting sound."])

        let result = try s.applyImport(p, applySettings: true)
        #expect(result.blocks == 3)
        #expect(result.backup.hasPrefix("schedule-"))
        #expect(s.backups().count == 1)
        let def = s.typeOf("default")
        #expect(def.name == "Default") // your Default keeps its name
        #expect(def.reminders.prep == Reminder(on: true, sound: s.clips[0].soundId, fade: true, lead: 10))
        #expect(def.reminders.start.sound == "class-bell")
        #expect(def.reminders.end.sound == Specs.spec(.end).sound)
        #expect(s.typeOf("focus").reminders.warn.lead == 60) // clamped
        let sport = try #require(s.types.first { $0.name == "Sport" })
        #expect(sport.reminders == Specs.startingTypeReminders)
        #expect(s.blocks.first { $0.title == "Gym" }?.type == sport.id)
        #expect(s.settings.volume == 55)
        #expect(s.settings.meetings.before.lead == 2 && !s.settings.meetings.start.on)
        #expect(s.clips.map(\.name) == ["My chime"])
        #expect(FileManager.default.fileExists(atPath: s.clipURL(s.clips[0]).path))
    }

    @Test func importWithoutSettingsKeepsYourReminders() throws {
        let s = tempStore()
        try s.startSchedule(sample: true)
        let before = s.typeOf("focus").reminders
        let p = try s.readImport(Data(macExport.utf8), fileName: "x.json")
        try s.applyImport(p, applySettings: false)
        #expect(s.typeOf("focus").reminders == before)
        #expect(s.settings.volume == 80)
        #expect(s.clips.isEmpty) // clips only come in with the settings that use them
    }

    @Test func rejectedClipsUseTheStartingSound() throws {
        let s = tempStore()
        let p = try s.readImport(Data(macExport.utf8), fileName: "x.json")
        try s.applyImport(p, applySettings: true, rejectClips: ["0123456789abcdef"])
        #expect(s.typeOf("default").reminders.prep.sound == Specs.spec(.prep).sound)
        #expect(s.clips.isEmpty)
    }

    @Test func badFiles() throws {
        let s = tempStore()
        #expect(throws: DataError("That file isn't a DayFlow export.")) { try s.readImport(Data("{}".utf8), fileName: "a") }
        #expect(throws: DataError("That file isn't a DayFlow export.")) { try s.readImport(Data("nope".utf8), fileName: "a") }
        #expect(throws: DataError("That file isn't a DayFlow export.")) { try s.readImport(Data(#"{"dayflowExport":"2"}"#.utf8), fileName: "a") }
        #expect(throws: DataError("That file was made by a newer version of DayFlow. Update DayFlow to import it.")) {
            try s.readImport(Data(#"{"dayflowExport":6}"#.utf8), fileName: "a")
        }
        #expect(throws: DataError("The schedule in that file has a problem: Schedule must be a list.")) {
            try s.readImport(Data(#"{"dayflowExport":2}"#.utf8), fileName: "a")
        }
    }

    @Test func exportRoundTripsAndBackupsRestoreTypesExactly() throws {
        let a = tempStore()
        try a.startSchedule(sample: true)
        var types = a.types
        types[1].reminders.start.fade = true
        types[1].name = "Deep focus"
        try a.saveTypes(types)
        var blocks = a.blocks
        blocks[1].type = types[1].id
        try a.saveBlocks(blocks)
        let clip = try a.installClip(name: "Bell", ext: "WAV", data: Data([1, 2, 3]))
        types = a.types
        types[1].reminders.end.sound = clip.soundId
        try a.saveTypes(types)

        // An ordinary export carries only the types its blocks use, and the clips they use.
        let export = a.exportPayload()
        #expect(export["blockTypes"]?.array?.map { $0["name"]?.string } == ["Default", "Deep focus"])
        #expect(export["blockTypes"]?.array?.first?["isDefault"] == .bool(true))
        #expect(export["clips"]?.array?.count == 1)
        #expect(export["backup"] == nil)
        let data = try JSONFile.encode(export)

        let b = tempStore()
        try b.startSchedule(sample: false)
        try b.applyImport(try b.readImport(data, fileName: "e.json"), applySettings: true)
        let expected = a.blocks.map { (blk: Block) -> Block in
            var x = blk
            let name = a.typeOf(blk.type).name
            x.type = b.types.first(where: { $0.name == name })!.id
            return x
        }
        #expect(b.blocks == expected)
        #expect(b.types.map(\.name) == ["Default", "Focus", "Break", "Admin", "Meal", "Deep focus"])
        #expect(b.types.last?.reminders.end.sound == clip.soundId) // same audio, same id

        // A backup replaces the type list exactly.
        let backup = try JSONFile.encode(a.exportPayload(backup: true))
        let c = tempStore()
        try c.applyImport(try c.readImport(backup, fileName: "b.json"), applySettings: true)
        #expect(c.types == a.types)
        #expect(c.blocks == a.blocks)
    }

    @Test func backupsKeepTheNewestTen() throws {
        let s = tempStore()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<12 { try s.writeBackup(.object([:]), now: start.addingTimeInterval(Double(i))) }
        #expect(s.backups().count == 10)
        #expect(s.backups().first!.lastPathComponent > s.backups().last!.lastPathComponent)
        // Two in the same millisecond both survive.
        try s.writeBackup(.object([:]), now: start.addingTimeInterval(100))
        try s.writeBackup(.object([:]), now: start.addingTimeInterval(100))
        #expect(s.backups().count == 10)
    }

    @Test func clips() throws {
        let s = tempStore()
        try s.startSchedule(sample: true)
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

    @Test func versionOneFilesUpgrade() throws {
        let v1 = """
        { "dayflowExport": 1, "settings": { "volume": 40, "warnBeforeEndMin": 0, "meetingLeadMin": 3,
            "sounds": { "transition": "flute-notification", "warning": "default", "end": "class-bell", "meeting": "sleigh-bells" } },
          "blockTypes": [ { "id": "focus", "name": "Focus", "sounds": { "end": "rooster-crowing" } }, { "id": "x", "name": "default" } ],
          "schedule": { "blocks": [ { "id": "a", "title": "A", "start": "08:00", "end": "09:00", "days": [1], "type": "x" },
                                    { "id": "b", "title": "B", "start": "09:00", "end": "10:00", "days": [1], "type": "focus" } ] } }
        """
        let s = tempStore()
        let p = try s.readImport(Data(v1.utf8), fileName: "old.json")
        try s.applyImport(p, applySettings: true)
        let def = s.typeOf("default")
        #expect(def.reminders.start.sound == "flute-notification")
        #expect(def.reminders.end.sound == "class-bell")
        #expect(!def.reminders.warn.on)
        #expect(s.typeOf("focus").reminders.end.sound == "rooster-crowing")
        #expect(s.blocks.first { $0.id == "a" }?.type == "default")
        #expect(s.settings.meetings.before.lead == 3 && s.settings.meetings.start.sound == "sleigh-bells")
        #expect(s.settings.volume == 40)
    }
}
