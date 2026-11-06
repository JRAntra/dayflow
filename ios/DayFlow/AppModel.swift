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

/// The cheer-up after checking an event off: "Nice! 3 of 6 done today · 5-day streak 🔥".
struct Cheer: Identifiable, Equatable {
    let id = UUID()
    var done: Int
    var total: Int
    var streak: Int
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
    /// Checks and skips, day by day (this iPhone only).
    private(set) var progress = DayProgress()
    /// The cheer-up showing now.
    var cheer: Cheer?

    var tab: AppTab = .today
    var banner: Banner?

    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var calendarAccess = false
    private(set) var widgetsAvailable = true
    private(set) var scheduledCount = 0
    /// Whether DayFlow may set alarms, for blocks that ring even on silent. `.unsupported`
    /// before iOS 26, where the switch is hidden.
    private(set) var alarmAccess: AlarmScheduler.Access = AlarmScheduler.access
    /// How many alarms are set right now.
    private(set) var alarmCount = 0
    private(set) var lastRefresh: Date?
    var isForeground = false

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var cheerTask: Task<Void, Never>?

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DayFlow", isDirectory: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if DEBUG
        // UI tests start from a fresh install: `-uiTestReset`, optionally past the welcome
        // screens with `-uiTestOnboarded`.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestReset") {
            // Remembered view choices (List or Day, Group repeats, a pending cheer-up) start over too.
            for key in ["schedule.mode", "schedule.groupRepeats", Self.pendingCheerKey] { UserDefaults.standard.removeObject(forKey: key) }
            for url in [support, docs.appendingPathComponent("Clips"), SoundLibrary.soundsDir] {
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
        store = DataStore(dir: support, clipsDir: docs.appendingPathComponent("Clips", isDirectory: true))
        #if DEBUG
        // UI tests past the welcome screens start from the sample day (`-uiTestEmpty`: nothing).
        if args.contains("-uiTestReset"), args.contains("-uiTestOnboarded"), !args.contains("-uiTestEmpty"), !store.hasSchedule {
            try? store.startSchedule()
            try? store.addSampleDay()
        }
        #endif
        sync()
        calendarAccess = calendarService.hasAccess
        #if DEBUG
        // `-uiTestRingSoon` adds a block, "Ring test", starting two minutes from now, to set ringing.
        // `-uiTestEventSoon` adds an event, "Pill", two minutes from now; `-uiTestEvents` adds
        // three events later today (late enough not to ring during a test).
        let now = Date(), cal = Calendar.current
        let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let today = [cal.component(.weekday, from: now) - 1]
        if args.contains("-uiTestRingSoon"), nowMin + 12 < 24 * 60 {
            let b = Block(title: "Ring test", start: HHMM.string(nowMin + 2), end: HHMM.string(nowMin + 12), days: today,
                          type: Specs.defaultType)
            try? store.saveBlocks(store.blocks + [b]); sync()
        }
        if args.contains("-uiTestEventSoon"), nowMin + 2 < 24 * 60 {
            let e = Block.event(title: "Pill", start: HHMM.string(nowMin + 2), days: today, alert: Specs.startingEventAlert)
            try? store.saveBlocks(store.blocks + [e]); sync()
            Task { _ = await allowAlarms(); refreshSoon() } // as saving a first event does
        }
        if args.contains("-uiTestEvents") {
            let start = min(nowMin + 60, 23 * 60)
            let list = ["Vitamins", "Stretch", "Call home"].enumerated().map { i, t in
                Block.event(title: t, start: HHMM.string(min(start + i * 15, 23 * 60 + 59)), days: today, alert: Specs.startingEventAlert)
            }
            try? store.saveBlocks(store.blocks + list); sync()
        }
        #endif
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
        Planner(blocks: blocks, types: types, meetingReminders: settings.meetings, meetings: meetings, progress: progress)
    }

    func typeOf(_ id: String) -> BlockType { store.typeOf(id) }
    /// "Focus", "Event" or "Repeated event".
    func typeName(for b: Block) -> String { planner.typeName(for: b) }
    func soundName(_ id: String) -> String { Specs.soundName(id, clips: clips) }
    /// "Soft bell", or "3 sounds, shuffled".
    func soundsName(_ r: Reminder) -> String {
        r.choices.count > 1 ? "\(r.choices.count) sounds, shuffled" : soundName(r.sound)
    }

    private func sync() {
        blocks = store.blocks
        types = store.types
        settings = store.settings
        clips = store.clips
        progress = store.progress
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
        alarmAccess = AlarmScheduler.access
        // Done on an alarm may have checked something off while DayFlow was in the background.
        store.reloadProgress()
        noteToday()
        sync()
        let planner = self.planner
        if settings.onboarded {
            scheduledCount = await ReminderScheduler.reschedule(planner: planner, store: store)
            alarmCount = AlarmScheduler.scheduledCount
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
        // An event taken out of its repeat has a new id: today's check or skip goes with it.
        if let original, original.id != edited.id, original.isRepeat, !edited.isRepeat {
            var p = progress
            let key = planner.dayKey(Date())
            if p.isDone(original.id, on: key) { p.setDone(edited.id, true, day: key) }
            if p.isSkipped(original.id, on: key) { p.setSkipped(edited.id, true, day: key) }
            try? store.saveProgress(p)
        }
        if let original, list.contains(where: { $0.id == original.id }) {
            list = ScheduleEdits.apply(edited, original: original, day: day ?? -1, allDays: day == nil || allDays, in: list)
        } else {
            list.append(edited)
        }
        saveBlocks(list, message: original == nil ? "Added \(edited.title)" : "Saved \(edited.title)", undoTo: previous)
    }

    /// Saves a repeat: its events are made (again) from `rule`, replacing any it had.
    func saveRepeat(title: String, days: [Int], alert: Reminder, rule: RepeatRule, isNew: Bool) {
        let previous = blocks
        let events = ScheduleEdits.makeRepeat(title: title, days: days, alert: alert, rule: rule)
        saveBlocks(ScheduleEdits.replacingRepeat(rule.id, with: events, in: blocks),
                   message: "\(isNew ? "Added" : "Saved") \(events.count) \(title) events", undoTo: previous)
    }

    /// Deletes every event of a repeat, with Undo.
    func deleteRepeat(_ id: String) {
        let previous = blocks
        let events = ScheduleEdits.repeatEvents(id, in: blocks)
        saveBlocks(ScheduleEdits.replacingRepeat(id, with: [], in: blocks),
                   message: "Deleted \(events.count) \(events.first?.title ?? "") events", undoTo: previous)
    }

    /// Deletes a block (or, from the day view, takes it off just that day) with Undo.
    func deleteBlock(_ b: Block, day: Int? = nil) {
        let previous = blocks
        let list = ScheduleEdits.removing(b, day: day, from: blocks)
        let onlyDay = day != nil && b.days.count > 1
        saveBlocks(list, message: onlyDay ? "Removed \(b.title) from \(ScheduleEdits.dayNames[day!])s" : "Deleted \(b.title)", undoTo: previous)
    }

    // MARK: Checking off and skipping

    var todayKey: String { planner.dayKey(Date()) }
    func isDone(_ id: String) -> Bool { progress.isDone(id, on: todayKey) }
    func isSkipped(_ id: String) -> Bool { progress.isSkipped(id, on: todayKey) }
    var streak: Int { planner.streak(at: Date()) }

    /// Checks an event off for today (its alarm today is cancelled), or unchecks it (the alarm
    /// comes back if its time hasn't passed). Checking off shows the cheer-up.
    func setDone(_ id: String, _ on: Bool) {
        var p = progress
        p.setDone(id, on, day: todayKey)
        saveProgress(p)
        if on { showCheer() }
    }

    /// Skips an event or block today, or brings it back.
    func setSkipped(_ id: String, _ on: Bool) {
        var p = progress
        p.setSkipped(id, on, day: todayKey)
        saveProgress(p)
        let title = blocks.first { $0.id == id }?.title ?? "It"
        show(on ? "Skipped \(title) today. It's back tomorrow." : "\(title) is back today")
    }

    private func saveProgress(_ p: DayProgress) {
        do {
            try store.saveProgress(p)
            sync()
            noteToday()
            refreshSoon()
        } catch { showError(error) }
    }

    /// Keeps today's result for the streak.
    private func noteToday() {
        let p = planner.noting(Date())
        if p != store.progress { try? store.saveProgress(p) }
        progress = store.progress
    }

    func showCheer() {
        let r = planner.result(on: Date())
        cheer = Cheer(done: r.done, total: r.total, streak: streak)
        cheerTask?.cancel()
        let id = cheer!.id
        cheerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, self?.cheer?.id == id else { return }
            withAnimation(.smooth) { self?.cheer = nil }
        }
    }

    /// Done on an event's alarm or notification: checks it off without opening DayFlow. The
    /// cheer-up shows the next time DayFlow is in front.
    func doneFromAlarm(_ id: String, day: String) {
        store.reloadProgress()
        sync()
        var p = progress
        p.setDone(id, true, day: day)
        try? store.saveProgress(p)
        sync()
        noteToday()
        if day == todayKey { UserDefaults.standard.set(true, forKey: Self.pendingCheerKey) }
    }

    static let pendingCheerKey = "pendingCheer"

    /// Shows the cheer-up for a Done tapped while DayFlow was in the background.
    func showPendingCheer() {
        guard UserDefaults.standard.bool(forKey: Self.pendingCheerKey) else { return }
        UserDefaults.standard.set(false, forKey: Self.pendingCheerKey)
        showCheer()
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

    // MARK: Notifications, alarms and calendars

    /// Shows the alarm icon: the block rings even on silent, and this iPhone can set alarms.
    /// (Every event rings as an alarm, so events don't show it.)
    func ringsOnSilent(_ b: Block) -> Bool { !b.isEvent && b.ringsOnSilent && alarmAccess != .unsupported }

    /// Asks to set alarms the first time "Ring even on silent" is turned on. Returns whether
    /// alarms are allowed.
    func allowAlarms() async -> Bool {
        alarmAccess = alarmAccess == .notDetermined ? await AlarmScheduler.requestAccess() : AlarmScheduler.access
        return alarmAccess == .authorized
    }

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

    // MARK: Welcome

    /// Finishes the welcome screens: an empty schedule to start ("Add a sample day" is on Today
    /// and Schedule).
    func finishWelcome() async {
        do {
            try store.startSchedule()
            var s = store.settings
            s.onboarded = true
            try store.saveSettings(s)
            sync()
        } catch { showError(error) }
        await refresh()
    }

    /// "Add a sample day": the eight sample weekday blocks, using Default.
    func addSampleDay() {
        let previous = blocks
        do {
            try store.addSampleDay()
            sync()
            refreshSoon()
            show("Added the sample day: 8 blocks, Monday to Friday") { [weak self] in self?.saveBlocks(previous, message: "Undone") }
        } catch { showError(error) }
    }
}
