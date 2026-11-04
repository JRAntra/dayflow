import Foundation
import Testing
@testable import DayFlowCore

/// Pretends every audio file plays: ones whose name contains "long" for 200 seconds, others for 3.
func fakeInspect(_ url: URL) -> DataStore.Inspection {
    url.lastPathComponent.contains("broken") ? .unplayable : .plays(seconds: url.lastPathComponent.contains("long") ? 200 : 3)
}

func write(_ bytes: [UInt8], _ url: URL) { try! Data(bytes).write(to: url) }

@Suite struct ClipFolderTests {
    @Test func oldClipsMoveIntoTheFolderUnderTheirNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dayflow-legacy-\(UUID().uuidString)")
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data.appendingPathComponent("sounds"), withIntermediateDirectories: true)
        let audio = Data([9, 9, 9])
        let id = DataStore.clipHash(audio)
        try audio.write(to: data.appendingPathComponent("sounds/\(id).mp3"))
        try Data(#"[{"id":"\#(id)","name":"Old: bell","ext":"mp3"}]"#.utf8).write(to: data.appendingPathComponent("sounds.json"))

        let s = DataStore(dir: data, backupsDir: root.appendingPathComponent("Backups"))
        #expect(s.clips.count == 1)
        #expect(s.clips[0].file == "Old- bell.mp3") // colons can't be in file names
        #expect(s.clips[0].id == id && s.clips[0].name == "Old: bell")
        #expect(FileManager.default.fileExists(atPath: s.clipsDir.appendingPathComponent("Old- bell.mp3").path))
        #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("sounds").path))
        // And it sticks.
        let again = DataStore(dir: data, backupsDir: root.appendingPathComponent("Backups"))
        #expect(again.clips[0].file == "Old- bell.mp3")
    }

    @Test func addedClipsGetReadableFiles() throws {
        let s = tempStore()
        let a = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        let b = try s.installClip(name: "ding", ext: "mp3", data: Data([2]))
        #expect(a.file == "Ding.mp3")
        #expect(b.name == "ding (2)" && b.file == "ding (2).mp3")
        #expect(FileManager.default.fileExists(atPath: s.clipURL(b).path))
    }

    @Test func filesDroppedInTheFolderBecomeClips() throws {
        let s = tempStore()
        try FileManager.default.createDirectory(at: s.clipsDir, withIntermediateDirectories: true)
        let existing = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        write([5, 5], s.clipsDir.appendingPathComponent("Gong.wav"))
        write([6], s.clipsDir.appendingPathComponent("A long song.mp3"))
        write([7], s.clipsDir.appendingPathComponent("notes.txt"))
        write([8], s.clipsDir.appendingPathComponent("broken.m4a"))
        write([1], s.clipsDir.appendingPathComponent("Ding copy.mp3"))
        write([3], s.clipsDir.appendingPathComponent(".hidden.mp3"))

        let scan = try s.scanClipsFolder(inspect: fakeInspect)
        #expect(scan.added.map(\.name) == ["Gong"])
        #expect(s.clips.map(\.name) == ["Ding", "Gong"])
        #expect(s.clips[1].id == DataStore.clipHash(Data([5, 5])) && s.clips[1].file == "Gong.wav")
        let others = Dictionary(uniqueKeysWithValues: scan.others.map { ($0.file, $0.problem) })
        #expect(others["A long song.mp3"] == .needsPiece(seconds: 200))
        #expect(others["notes.txt"] == .unusable("Isn't an mp3, wav, m4a, aac or ogg file."))
        #expect(others["broken.m4a"] == .unusable("DayFlow can't play this file. Try converting it to mp3 or wav."))
        #expect(others["Ding copy.mp3"] == .unusable("The same sound as \(existing.name)."))
        #expect(others[".hidden.mp3"] == nil)
        // A second scan finds nothing new.
        #expect(try !s.scanClipsFolder(inspect: fakeInspect).changed)
        s.load()
        #expect(s.clips.map(\.name) == ["Ding", "Gong"])
    }

    @Test func renamingOrDeletingTheFileChangesTheClip() throws {
        let s = tempStore()
        try s.startSchedule(sample: true)
        let clip = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        var types = s.types
        types[0].reminders.start.sound = clip.soundId
        try s.saveTypes(types)

        try FileManager.default.moveItem(at: s.clipURL(clip), to: s.clipsDir.appendingPathComponent("Morning ding.mp3"))
        let scan = try s.scanClipsFolder(inspect: fakeInspect)
        #expect(scan.renamed.map(\.name) == ["Morning ding"] && scan.removed.isEmpty)
        #expect(s.clips[0].id == clip.id && s.clips[0].file == "Morning ding.mp3")
        #expect(s.typeOf("default").reminders.start.sound == clip.soundId) // reminders keep it

        try FileManager.default.removeItem(at: s.clipsDir.appendingPathComponent("Morning ding.mp3"))
        let gone = try s.scanClipsFolder(inspect: fakeInspect)
        #expect(gone.removed == ["Morning ding"])
        #expect(gone.reset == ["Default · Start"])
        #expect(s.clips.isEmpty)
        #expect(s.typeOf("default").reminders.start.sound == Specs.spec(TypeReminderKey.start).sound)
    }

    @Test func anUnreadableFolderRemovesNothing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dayflow-noread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clipsPath = root.appendingPathComponent("Clips")
        let s = DataStore(dir: root.appendingPathComponent("data"), backupsDir: root.appendingPathComponent("B"), clipsDir: clipsPath)
        try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        // The folder is replaced by a file, so it can't be listed.
        try FileManager.default.removeItem(at: clipsPath)
        try Data([0]).write(to: clipsPath)
        #expect(throws: (any Error).self) { try s.scanClipsFolder(inspect: fakeInspect) }
        #expect(s.clips.count == 1)
    }

    @Test func renameInTheApp() throws {
        let s = tempStore()
        let a = try s.installClip(name: "Ding", ext: "mp3", data: Data([1]))
        try s.installClip(name: "Gong", ext: "wav", data: Data([2]))
        let renamed = try s.renameClip(a.id, to: "  Soft ding/2  ")
        #expect(renamed.name == "Soft ding/2" && renamed.file == "Soft ding-2.mp3")
        #expect(FileManager.default.fileExists(atPath: s.clipsDir.appendingPathComponent("Soft ding-2.mp3").path))
        #expect(!FileManager.default.fileExists(atPath: s.clipsDir.appendingPathComponent("Ding.mp3").path))
        #expect(throws: DataError("There's already a clip called \"gong\".")) { try s.renameClip(a.id, to: "gong") }
        #expect(throws: DataError("A clip needs a name.")) { try s.renameClip(a.id, to: " ") }
        // Changing only the case works.
        #expect(try s.renameClip(a.id, to: "SOFT DING/2").file == "SOFT DING-2.mp3")
        #expect(try !s.scanClipsFolder(inspect: fakeInspect).changed)
    }

    @Test func aPieceOfALongSongMovesTheOriginalAside() throws {
        let s = tempStore()
        try FileManager.default.createDirectory(at: s.clipsDir, withIntermediateDirectories: true)
        let song = s.clipsDir.appendingPathComponent("Moonlight long.mp3")
        write([1, 2, 3, 4], song)
        #expect(try s.scanClipsFolder(inspect: fakeInspect).others.count == 1)
        let clip = try s.savePiece(Data([4, 4]), ext: "m4a", name: "Moonlight", source: song)
        #expect(clip.name == "Moonlight (clip)" && clip.file == "Moonlight (clip).m4a")
        #expect(FileManager.default.fileExists(atPath: s.originalsDir.appendingPathComponent("Moonlight long.mp3").path))
        let scan = try s.scanClipsFolder(inspect: fakeInspect)
        #expect(scan.others.isEmpty && !scan.changed) // Originals isn't scanned
        // A piece of a file from elsewhere leaves that file alone.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).mp3")
        write([7, 7, 7], outside)
        try s.savePiece(Data([5]), ext: "m4a", name: "Elsewhere", source: outside)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func exportAndImportUseTheFolder() throws {
        let a = tempStore()
        try a.startSchedule(sample: true)
        let clip = try a.installClip(name: "Ding", ext: "mp3", data: Data([1, 2]))
        var types = a.types
        types[0].reminders.end.sound = clip.soundId
        try a.saveTypes(types)
        let file = try JSONFile.encode(a.exportPayload())
        let b = tempStore()
        try b.applyImport(try b.readImport(file, fileName: "x.json"), applySettings: true)
        #expect(b.clips.map(\.file) == ["Ding.mp3"])
        #expect(try Data(contentsOf: b.clipURL(b.clips[0])) == Data([1, 2]))
    }
}
