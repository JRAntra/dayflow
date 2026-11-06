import DayFlowCore
import SwiftUI
import UniformTypeIdentifiers

/// What the edit sheet is editing: a new block or an existing one, and, from the day view,
/// which day you were looking at (for "This day only / All N days").
struct BlockEditing: Identifiable {
    let id = UUID()
    var block: Block
    var original: Block?
    var day: Int?
}

/// Schedule: your weekly plan, as a list or one day at a time, with Import, Export and Backups.
struct ScheduleView: View {
    @Environment(AppModel.self) private var model

    enum Mode: String { case list = "List", day = "Day" }
    @AppStorage("schedule.mode") private var mode: Mode = .list
    @State private var filter: Int?
    @State private var day: Int = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var editing: BlockEditing?
    @State private var repeatEditing: RepeatEditing?
    /// A repeat's event you tapped: edit all its events, or only this one?
    @State private var askRepeat: (block: Block, day: Int?)?
    @State private var importing = false
    @State private var preview: ImportPreview?
    @State private var shareURL: URL?
    @State private var showBackups = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Picker("View", selection: $mode.animation(.smooth)) {
                        Text("List").tag(Mode.list)
                        Text("Day").tag(Mode.day)
                    }
                    .pickerStyle(.segmented)
                    if mode == .list {
                        DayStrip(selection: $filter, allowsAll: true)
                    } else {
                        DayStrip(selection: Binding(get: { day }, set: { day = $0 ?? day }))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Group {
                    if mode == .list {
                        BlockListView(filter: filter, edit: { b in open(BlockEditing(block: b, original: b)) },
                                      editRepeat: { b in repeatEditing = RepeatEditing(event: b) })
                    } else {
                        DayGridView(day: day) { open($0) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { moreMenu }
                ToolbarItem(placement: .topBarTrailing) { addMenu }
            }
            .sheet(item: $editing) { e in BlockEditSheet(editing: e) }
            .sheet(item: $repeatEditing) { e in RepeatEditSheet(editing: e) }
            .confirmationDialog(askRepeat.map { "\($0.block.title) repeats" } ?? "",
                                isPresented: Binding(get: { askRepeat != nil }, set: { if !$0 { askRepeat = nil } }),
                                titleVisibility: .visible, presenting: askRepeat) { a in
                Button("Edit all events in this repeat") { repeatEditing = RepeatEditing(event: a.block) }
                Button("Edit only this one") {
                    let (one, _) = ScheduleEdits.detached(a.block, in: model.blocks)
                    editing = BlockEditing(block: one, original: a.block, day: a.day)
                }
                Button("Cancel", role: .cancel) {}
            } message: { a in
                Text(a.block.series.map { ScheduleEdits.repeatText($0, time: BlockRow.time) } ?? "")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): openImport(url)
                case .failure(let error): model.showError(error)
                }
            }
            .sheet(item: Binding(get: { preview.map { PreviewBox(preview: $0) } }, set: { preview = $0?.preview })) { box in
                ImportPreviewSheet(preview: box.preview) { applySettings in
                    model.applyImport(box.preview, applySettings: applySettings)
                }
            }
            .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { item in
                ShareSheet(items: [item.url]).presentationDetents([.medium, .large])
            }
            .navigationDestination(isPresented: $showBackups) {
                BackupsView { url in openImport(url) }
            }
            .onChange(of: model.openedFile, initial: true) { _, url in
                guard let url else { return }
                model.openedFile = nil
                openImport(url)
            }
        }
    }

    /// ＋: an event, a repeated event or a block. In the day view each starts on that day.
    var addMenu: some View {
        Menu {
            Button { add(event: true) } label: { Label("Event", systemImage: "bell") }
            Button {
                repeatEditing = RepeatEditing(days: mode == .day ? [day] : Specs.weekdays,
                                              alert: ScheduleEdits.newEvent(start: 0, days: [], types: model.types).eventAlert)
            } label: { Label("Repeated event", systemImage: "repeat") }
            Button { add(event: false) } label: { Label("Block", systemImage: "rectangle") }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add")
        .accessibilityIdentifier("add-menu")
    }

    func add(event: Bool) {
        var b = ScheduleEdits.newBlockAfterLatest(model.blocks)
        if mode == .day {
            b = ScheduleEdits.newBlock(at: b.startMin, day: day, blocks: model.blocks)
        }
        if event { b = ScheduleEdits.newEvent(start: b.startMin, days: b.days, types: model.types) }
        editing = BlockEditing(block: b, original: nil, day: mode == .day ? day : nil)
    }

    /// Opens the edit sheet; a repeat's event asks first whether to edit all of them.
    func open(_ e: BlockEditing) {
        if let original = e.original, original.isRepeat {
            askRepeat = (original, e.day)
        } else {
            editing = e
        }
    }

    var moreMenu: some View {
        Menu {
            Button { importing = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            Button {
                do { shareURL = try model.exportFile() } catch { model.showError(error) }
            } label: { Label("Export…", systemImage: "square.and.arrow.up") }
            Button { showBackups = true } label: { Label("Backups", systemImage: "clock.arrow.circlepath") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    func openImport(_ url: URL) {
        do { preview = try model.readImport(url) } catch { model.showError(error) }
    }
}

private struct PreviewBox: Identifiable {
    let id = UUID()
    let preview: ImportPreview
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// The share sheet (AirDrop, Files, Mail, Messages).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
