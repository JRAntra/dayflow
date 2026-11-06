import DayFlowCore
import SwiftUI

/// What the edit sheet is editing: a new block or an existing one, and, from the day view,
/// which day you were looking at (for "This day only / All N days").
struct BlockEditing: Identifiable {
    let id = UUID()
    var block: Block
    var original: Block?
    var day: Int?
}

/// Schedule: your weekly plan, as a list or one day at a time.
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
                            // Like Calendar's day view, the hour grid's text grows only so far, so
                            // blocks and events keep their names on screen.
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Schedule")
            .toolbar {
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
}
