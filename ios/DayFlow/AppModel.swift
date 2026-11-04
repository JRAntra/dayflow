import ActivityKit
import EventKit
import DayFlowCore
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// The tabs at the bottom of the app.
enum AppTab: Hashable { case today, schedule, settings }

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
            for url in [support, docs.appendingPathComponent("Backups"), SoundLibrary.soundsDir] { try? fm.removeItem(at: url) }
            if args.contains("-uiTestOnboarded") {
                try? fm.createDirectory(at: support, withIntermediateDirectories: true)
                try? Data(#"{"onboarded": true}"#.utf8).write(to: support.appendingPathComponent("settings.json"))
            }
        }
        #endif
        store = DataStore(dir: support, backupsDir: docs.appendingPathComponent("Backups", isDirectory: true))
        sync()
        calendarAccess = calendarService.hasAccess
    }

    var onboarded: Bool { settings.onboarded }

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
        await LiveActivityController.update(planner: planner, enabled: settings.liveActivity && settings.onboarded,
                                            canStart: isForeground)
        widgetsAvailable = LiveActivityController.writeWidgetSnapshot(planner: planner)
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

    /// Pauses every reminder for an hour (banners and sounds); they come back on their own.
    func pauseForAnHour() {
        update { $0.pausedUntil = Date().addingTimeInterval(3600) }
    }

    func resume() { update { $0.pausedUntil = nil } }

    var pausedUntil: Date? { settings.isPaused(at: Date()) ? settings.pausedUntil : nil }

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

    /// Adds a clip picked in Files, after checking it plays and is short enough.
    func addClip(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()
            _ = try Sanitize.clipType(name: name, ext: ext, bytes: data.count)
            try SoundLibrary.check(data, name: name, ext: ext)
            let clip = try store.installClip(name: name, ext: ext, data: data)
            sync()
            show("Added \(clip.name)")
        } catch { showError(error) }
    }

    func removeClip(_ id: String) {
        do {
            let name = clips.first { $0.id == id }?.name ?? "the clip"
            let reset = try store.removeClip(id)
            sync()
            refreshSoon()
            show(reset.isEmpty ? "Removed \(name)" : "Removed \(name). \(reset.joined(separator: ", ")) went back to the starting sound.")
        } catch { showError(error) }
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
