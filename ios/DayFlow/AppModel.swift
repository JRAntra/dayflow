import ActivityKit
import EventKit
import DayFlowCore
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// The tabs at the bottom of the app.
enum AppTab: Hashable { case today, schedule, settings }

/// A long sound you're choosing a 30-second piece of.
struct PieceRequest: Identifiable {
    let id = UUID()
    /// The file: in the Clips folder, or a temporary copy of one you picked or shared.
    var url: URL
    var name: String
    var seconds: Double
    var inFolder: Bool
}

/// A short message at the bottom of the screen, sometimes with Undo.
struct Banner: Identifiable {
    let id = UUID()
    var text: String
    var isError = false
    var undo: (() -> Void)?
}

/// Everything the screens show and change. It wraps the DataStore (the same files and rules as
/// the Mac app) and, after every change, brings the reminders, the Live Activity and the widgets
/// up to date.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store: DataStore
    @ObservationIgnored let calendarService = CalendarService()

    private(set) var blocks: [Block] = []
    private(set) var types: [BlockType] = []
    private(set) var settings = Settings()
    private(set) var clips: [CustomClip] = []
    /// Files in the Clips folder that aren't clips: long songs waiting for a piece, and files
    /// DayFlow can't use, with the reason.
    private(set) var folderFiles: [FolderFile] = []
    /// A long file you're choosing 30 seconds of.
    var pieceRequest: PieceRequest?
    private(set) var meetings: [Meeting] = []

    var tab: AppTab = .today
    var banner: Banner?
    /// A file opened with "Open in DayFlow", waiting for its import preview.
    var openedFile: URL?

    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var calendarAccess = false
    private(set) var widgetsAvailable = true
    private(set) var scheduledCount = 0
    private(set) var lastRefresh: Date?
    var isForeground = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DayFlow", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if DEBUG
        // UI tests start from a fresh install: `-uiTestReset`, optionally past the welcome
        // screens with `-uiTestOnboarded`.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestReset") {
            for url in [support, docs.appendingPathComponent("Backups"), docs.appendingPathComponent("Clips"), SoundLibrary.soundsDir] {
                do { if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) } } catch {
                    NSLog("DFDEBUG reset couldn't remove \(url.lastPathComponent): \(error)")
                }
            }
            if args.contains("-uiTestClips") {
                // A short sound, a 40-second tone and a file DayFlow can't use, in the Clips folder.
                let clipsDir = docs.appendingPathComponent("Clips")
                try? fm.createDirectory(at: clipsDir, withIntermediateDirectories: true)
                if let bell = Bundle.main.url(forResource: "class-bell", withExtension: "mp3", subdirectory: "sounds") {
                    try? fm.copyItem(at: bell, to: clipsDir.appendingPathComponent("Gong.mp3"))
                }
                try? Self.toneWAV(seconds: 40).write(to: clipsDir.appendingPathComponent("Long tone.wav"))
                try? Data("hello".utf8).write(to: clipsDir.appendingPathComponent("notes.txt"))
            }
            if args.contains("-uiTestOnboarded") {
                try? fm.createDirectory(at: support, withIntermediateDirectories: true)
                try? Data(#"{"onboarded": true}"#.utf8).write(to: support.appendingPathComponent("settings.json"))
            }
        }
        #endif
        store = DataStore(dir: support, backupsDir: docs.appendingPathComponent("Backups", isDirectory: true),
                          clipsDir: docs.appendingPathComponent("Clips", isDirectory: true))
        sync()
        calendarAccess = calendarService.hasAccess
    }

    var onboarded: Bool { settings.onboarded }

    #if DEBUG
    /// A quiet 440 Hz tone as 16-bit mono WAV, for UI tests.
    static func toneWAV(seconds: Int, rate: Int = 22_050) -> Data {
        let n = seconds * rate
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(36 + n * 2); d.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(n * 2)
        for i in 0..<n { var v = Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 6000).littleEndian; d.append(Data(bytes: &v, count: 2)) }
        return d
    }
    #endif

    var planner: Planner {
        Planner(blocks: blocks, types: types, meetingReminders: settings.meetings, meetings: meetings)
    }

    func typeOf(_ id: String) -> BlockType { store.typeOf(id) }
    func soundName(_ id: String) -> String { Specs.soundName(id, clips: clips) }

    private func sync() {
        blocks = store.blocks
        types = store.types
        settings = store.settings
        clips = store.clips
    }

    // MARK: Refreshing

    /// Brings everything up to date: meetings, scheduled reminders, the Live Activity and widgets.
    func refresh() async {
        refreshTask?.cancel()
        refreshTask = nil
        scanClips()
        if settings.pausedUntil.map({ $0 <= Date() }) == true {
            var s = settings; s.pausedUntil = nil
            try? store.saveSettings(s); sync()
        }
        calendarAccess = calendarService.hasAccess
        if calendarAccess {
            addTestMeetingIfAsked()
            // Access given before any calendar was chosen (in iOS Settings, say): start with
            // the default calendar, as when you allow access in DayFlow.
            if settings.calendars == nil, let id = calendarService.defaultCalendarId {
                var s = settings; s.calendars = [id]
                try? store.saveSettings(s); sync()
            }
        }
        meetings = calendarService.meetings(calendarIds: settings.calendars ?? [])
        notificationStatus = await ReminderScheduler.authorization()
        let planner = self.planner
        if settings.onboarded {
            scheduledCount = await ReminderScheduler.reschedule(planner: planner, store: store)
        }
        await LiveActivityController.update(planner: planner, enabled: settings.liveActivity && settings.onboarded && !isOff,
                                            canStart: isForeground)
        widgetsAvailable = LiveActivityController.writeWidgetSnapshot(planner: planner, offUntil: settings.offUntil(at: Date()))
        lastRefresh = Date()
    }

    /// Refreshes shortly, so several quick changes reschedule once.
    func refreshSoon() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: Messages

    func show(_ text: String, isError: Bool = false, undo: (() -> Void)? = nil) {
        banner = Banner(text: text, isError: isError, undo: undo)
        bannerTask?.cancel()
        let id = banner!.id
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 3 : 5))
            guard !Task.isCancelled, self?.banner?.id == id else { return }
            withAnimation(.snappy) { self?.banner = nil }
        }
    }

    func showError(_ error: Error) {
        show((error as? DataError)?.message ?? error.localizedDescription, isError: true)
    }

    // MARK: Schedule

    /// Saves the whole block list, with Undo going back to `previous`.
    func saveBlocks(_ list: [Block], message: String? = nil, undoTo previous: [Block]? = nil) {
        do {
            try store.saveBlocks(list)
            sync()
            refreshSoon()
            if let message {
                if let previous {
                    show(message) { [weak self] in self?.saveBlocks(previous, message: "Undone") }
                } else {
                    show(message)
                }
            }
        } catch { showError(error) }
    }

    /// Saves one block from the edit sheet. In the day view, `day` and `allDays` decide whether
    /// a repeating block changes everywhere or is split off for that day.
    func saveBlock(_ edited: Block, original: Block?, day: Int? = nil, allDays: Bool = true) {
        let previous = blocks
        var list = blocks
        if let original, list.contains(where: { $0.id == original.id }) {
            list = ScheduleEdits.apply(edited, original: original, day: day ?? -1, allDays: day == nil || allDays, in: list)
        } else {
            list.append(edited)
        }
        saveBlocks(list, message: original == nil ? "Added \(edited.title)" : "Saved \(edited.title)", undoTo: previous)
    }

    /// Deletes a block (or, from the day view, takes it off just that day) with Undo.
    func deleteBlock(_ b: Block, day: Int? = nil) {
        let previous = blocks
        let list = ScheduleEdits.removing(b, day: day, from: blocks)
        let onlyDay = day != nil && b.days.count > 1
        saveBlocks(list, message: onlyDay ? "Removed \(b.title) from \(ScheduleEdits.dayNames[day!])s" : "Deleted \(b.title)", undoTo: previous)
    }

    // MARK: Block types

    func saveTypes(_ list: [BlockType]) throws {
        try store.saveTypes(list)
        sync()
        refreshSoon()
    }

    func updateType(_ t: BlockType) {
        guard let i = types.firstIndex(where: { $0.id == t.id }) else { return }
        var list = types
        list[i] = t
        do { try saveTypes(list) } catch { showError(error) }
    }

    /// Adds "New type" (or "New type 2"…) with the starting reminders.
    func addType() -> BlockType? {
        let names = Set(types.map { $0.name.lowercased() })
        var name = "New type"
        var n = 2
        while names.contains(name.lowercased()) { name = "New type \(n)"; n += 1 }
        let t = BlockType(id: UUID().uuidString.lowercased(), name: name)
        do { try saveTypes(types + [t]); return t } catch { showError(error); return nil }
    }

    /// Deletes a type; its blocks move to Default.
    func deleteType(_ id: String) {
        guard id != Specs.defaultType, let t = types.first(where: { $0.id == id }) else { return }
        let used = store.usedBy(id)
        do {
            try saveTypes(types.filter { $0.id != id })
            show(used > 0 ? "Deleted \(t.name). \(used == 1 ? "Its block" : "Its \(used) blocks") moved to \(typeOf(Specs.defaultType).name)." : "Deleted \(t.name)")
        } catch { showError(error) }
    }

    // MARK: Settings

    func saveSettings(_ s: Settings) {
        do {
            try store.saveSettings(s)
            sync()
            refreshSoon()
        } catch { showError(error) }
    }

    func update(_ change: (inout Settings) -> Void) {
        var s = settings
        change(&s)
        saveSettings(s)
    }

    /// Turns reminders off: nothing rings until they're back on. Every scheduled notification is
    /// removed and the Live Activity ends, so nothing rings even if you swipe DayFlow away.
    func turnOff(_ choice: TurnOff) {
        saveSettings(choice.apply(to: settings))
        show(TurnOff.status(settings) ?? "Reminders off")
    }

    func turnOn() {
        saveSettings(TurnOff.turnOn(settings))
        show("Reminders on")
    }

    var isOff: Bool { settings.isOff(at: Date()) }

    // MARK: Notifications and calendars

    func requestNotifications() async {
        await ReminderScheduler.requestPermission()
        notificationStatus = await ReminderScheduler.authorization()
        refreshSoon()
    }

    /// Asks for calendar access the first time; your default calendar is chosen to start with.
    func requestCalendarAccess() async {
        let ok = await calendarService.requestAccess()
        calendarAccess = ok
        if ok { addTestMeetingIfAsked() }
        if ok && settings.calendars == nil {
            update { $0.calendars = calendarService.defaultCalendarId.map { [$0] } ?? [] }
        } else {
            refreshSoon()
        }
    }

    /// UI tests: `-uiTestMeeting` adds a meeting with a Meet link in its notes, the way Google
    /// events arrive on an iPhone, starting in 20 minutes. Does nothing in release builds.
    private func addTestMeetingIfAsked() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-uiTestMeeting"), !addedTestMeeting,
              let cal = calendarService.store.defaultCalendarForNewEvents else { return }
        addedTestMeeting = true
        let e = EKEvent(eventStore: calendarService.store)
        e.title = "Standup"
        e.startDate = Date().addingTimeInterval(20 * 60)
        e.endDate = e.startDate.addingTimeInterval(15 * 60)
        e.notes = "Join with Google Meet: https://meet.google.com/abc-defg-hij\nOr dial: +1 555 0100"
        e.calendar = cal
        try? calendarService.store.save(e, span: .thisEvent)
        #endif
    }
    @ObservationIgnored private var addedTestMeeting = false

    func setCalendar(_ id: String, on: Bool) {
        update { s in
            var list = s.calendars ?? []
            list.removeAll { $0 == id }
            if on { list.append(id) }
            s.calendars = list
        }
    }

    func sendTestNotification() async {
        notificationStatus = await ReminderScheduler.authorization()
        if notificationStatus == .notDetermined { await requestNotifications() }
        await ReminderScheduler.sendTest(store: store)
        show("A test notification arrives in 2 seconds. Leave DayFlow to see it on the Lock Screen.")
    }

    // MARK: Sounds

    func preview(_ soundId: String, fade: Bool, fallback: String? = nil) {
        SoundPlayer.shared.play(soundId, fade: fade, volume: settings.volume, store: store, fallback: fallback)
    }

    /// Brings Your clips in line with the Clips folder (Files › On My iPhone › DayFlow › Clips).
    /// Runs when DayFlow opens and when you open Sounds; iOS doesn't let an app watch a folder
    /// while it's closed.
    func scanClips() {
        do {
            let scan = try store.scanClipsFolder(inspect: AudioEdit.inspect)
            folderFiles = scan.others
            guard scan.changed else { return }
            sync()
            refreshSoon()
            var parts: [String] = []
            if !scan.added.isEmpty { parts.append("Added \(Self.list(scan.added.map(\.name))) from the Clips folder.") }
            if !scan.removed.isEmpty {
                parts.append("\(Self.list(scan.removed)) left the Clips folder" + (scan.reset.isEmpty ? "." : ", so \(scan.reset.joined(separator: ", ")) went back to the starting sound."))
            }
            if !parts.isEmpty { show(parts.joined(separator: " ")) }
        } catch {
            folderFiles = []
        }
    }

    static func list(_ names: [String]) -> String {
        names.count <= 2 ? names.joined(separator: " and ") : "\(names.count) clips"
    }

    /// Adds a sound from Choose a file, Share or AirDrop. A short one is copied into the Clips
    /// folder; a long one opens Choose 30 seconds.
    func addClip(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            guard Specs.clipTypes.contains(ext) else { throw DataError("\"\(name)\" isn't an mp3, wav, m4a, aac or ogg file.") }
            guard size <= DataStore.maxSourceBytes else { throw DataError("\"\(name)\" is larger than 200 MB.") }
            // Work on a copy, so the file can be read after Files' permission ends.
            let copy = AudioEdit.tempURL(ext)
            try FileManager.default.copyItem(at: url, to: copy)
            guard let seconds = AudioEdit.seconds(copy) else {
                throw DataError("DayFlow can't play \"\(name)\". Try converting it to mp3 or wav.")
            }
            if seconds > Specs.maxClipSeconds + 0.5 || size > Specs.maxClipBytes {
                pieceRequest = PieceRequest(url: copy, name: name, seconds: seconds, inFolder: false)
                return
            }
            let clip = try store.installClip(name: name, ext: ext, data: Data(contentsOf: copy))
            try? FileManager.default.removeItem(at: copy)
            sync()
            show("Added \(clip.name). Choose it in any reminder's Sound menu.")
        } catch { showError(error) }
    }

    /// Opens Choose 30 seconds for a long file in the Clips folder.
    func choosePiece(of f: FolderFile) {
        guard case .needsPiece(let seconds) = f.problem else { return }
        pieceRequest = PieceRequest(url: store.clipsDir.appendingPathComponent(f.file), name: f.name, seconds: seconds, inFolder: true)
    }

    /// Saves the 30 seconds from `start` as "<name> (clip)". A song from the Clips folder then
    /// moves into Clips › Originals.
    /// Throws so the sheet can show what went wrong (a banner would be hidden behind it).
    func savePiece(_ r: PieceRequest, start: Double, fadeIn: Bool) throws {
        do {
            let buffer = try AudioEdit.read(r.url, from: start, duration: Specs.maxClipSeconds)
            let out = AudioEdit.tempURL()
            try AudioEdit.writeM4A(buffer, fadeIn: fadeIn, fadeOut: 0.6, to: out)
            defer { try? FileManager.default.removeItem(at: out) }
            let clip = try store.savePiece(Data(contentsOf: out), ext: "m4a", name: r.name, source: r.inFolder ? r.url : nil)
            if !r.inFolder { try? FileManager.default.removeItem(at: r.url) }
            pieceRequest = nil
            sync()
            scanClips()
            show("Added \(clip.name)\(r.inFolder ? ". The full song is in Clips › Originals." : ".") Choose it in any reminder's Sound menu.")
        } catch let e as DataError { throw e } catch {
            throw DataError("DayFlow couldn't save the piece. (\(error.localizedDescription))")
        }
    }

    /// Saves a recording (already trimmed) as a clip.
    func saveRecording(_ url: URL, name: String) throws {
        let clip = try store.installClip(name: name, ext: "m4a", data: Data(contentsOf: url))
        sync()
        show("Added \(clip.name). Choose it in any reminder's Sound menu.")
    }

    func renameClip(_ id: String, to name: String) {
        do {
            let clip = try store.renameClip(id, to: name)
            sync()
            show("Renamed to \(clip.name)")
        } catch { showError(error) }
    }

    /// Removes a clip and deletes its file; reminders that used it go back to their starting sound.
    func removeClip(_ id: String) {
        do {
            let name = clips.first { $0.id == id }?.name ?? "the clip"
            let reset = try store.removeClip(id)
            sync()
            refreshSoon()
            show(reset.isEmpty ? "Removed \(name)" : "Removed \(name). \(reset.joined(separator: ", ")) went back to the starting sound.")
        } catch { showError(error) }
    }

    /// Deletes a file from the Clips folder that isn't a clip.
    func deleteFolderFile(_ f: FolderFile) {
        try? FileManager.default.removeItem(at: store.clipsDir.appendingPathComponent(f.file))
        scanClips()
    }

    // MARK: Export, import and backups

    /// Writes an export file to a temporary folder, ready for the share sheet.
    func exportFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(DataStore.exportFileName())
        try JSONFile.encode(store.exportPayload()).write(to: url, options: .atomic)
        return url
    }

    func readImport(_ url: URL) throws -> ImportPreview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try store.readImport(data, fileName: url.lastPathComponent)
    }

    /// Clips in the file that won't play on the iPhone (OGG, say) give way to the starting sound.
    func unplayableClips(in p: ImportPreview) -> [ImportPreview.Clip] {
        p.clips.filter { (try? SoundLibrary.check($0.data, name: $0.name, ext: $0.ext)) == nil }
    }

    func applyImport(_ p: ImportPreview, applySettings: Bool) {
        let rejected = Set(unplayableClips(in: p).map(\.id))
        do {
            let r = try store.applyImport(p, applySettings: applySettings, rejectClips: rejected)
            sync()
            refreshSoon()
            show("Imported \(r.blocks) block\(r.blocks == 1 ? "" : "s"). Your previous schedule is in Backups.")
        } catch { showError(error) }
    }

    func backups() -> [URL] { store.backups() }

    // MARK: Welcome

    func finishWelcome(sample: Bool, importing: (ImportPreview, Bool)? = nil) async {
        do {
            if let (p, applySettings) = importing {
                try store.startSchedule(sample: false)
                try store.applyImport(p, applySettings: applySettings, rejectClips: Set(unplayableClips(in: p).map(\.id)))
            } else {
                try store.startSchedule(sample: sample)
            }
            var s = store.settings
            s.onboarded = true
            try store.saveSettings(s)
            sync()
        } catch { showError(error) }
        await refresh()
    }
}
