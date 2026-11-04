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
                        BlockListView(filter: filter) { b in editing = BlockEditing(block: b, original: b) }
                    } else {
                        DayGridView(day: day) { editing = $0 }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { moreMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var b = ScheduleEdits.newBlockAfterLatest(model.blocks)
                        if mode == .day {
                            b = ScheduleEdits.newBlock(at: b.startMin, day: day, blocks: model.blocks)
                        }
                        editing = BlockEditing(block: b, original: nil, day: mode == .day ? day : nil)
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add block")
                }
            }
            .sheet(item: $editing) { e in BlockEditSheet(editing: e) }
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
