import DayFlowCore
import SwiftUI

/// The weekly plan as a list, earliest first. Tap an item to edit it; swipe left to delete it.
/// With Group repeats on, a repeat's events show as one row.
struct BlockListView: View {
    @Environment(AppModel.self) private var model
    let filter: Int?
    let edit: (Block) -> Void
    /// A repeat's row (when grouped): edits all its events.
    var editRepeat: (Block) -> Void = { _ in }

    @AppStorage("schedule.groupRepeats") private var group = false
    @State private var askDelete: Block?

    var shown: [Block] { model.blocks.filter { filter == nil || $0.days.contains(filter!) } }

    /// The rows: with grouping, the first event of each repeat stands for all of them.
    var rows: [Block] {
        guard group else { return shown }
        var seen = Set<String>()
        return shown.filter { b in b.series.map { seen.insert($0.id).inserted } ?? true }
    }

    var hasRepeats: Bool { model.blocks.contains(where: \.isRepeat) }

    var body: some View {
        List {
            if hasRepeats {
                Toggle("Group repeats", isOn: $group.animation(.smooth))
                    .font(.subheadline)
                    .accessibilityIdentifier("group-repeats")
            }
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(model.blocks.isEmpty ? "Nothing planned yet" : "Nothing on \(ScheduleEdits.dayNames[filter ?? 0])s",
                          systemImage: "calendar.badge.plus")
                } description: {
                    Text(model.blocks.isEmpty ? "Add events and the blocks of your day with ＋."
                         : "None of your events or blocks repeat on that day.")
                } actions: {
                    if model.blocks.isEmpty {
                        Button("Add a sample day") { model.addSampleDay() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("add-sample-day")
                    }
                }
                .listRowBackground(Color.clear)
            }
            ForEach(rows) { b in
                let grouped = group && b.isRepeat
                Button { grouped ? editRepeat(b) : edit(b) } label: {
                    if grouped { RepeatRow(first: b, count: ScheduleEdits.repeatEvents(b.series!.id, in: model.blocks).count) }
                    else { BlockRow(block: b) }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: !b.isRepeat) {
                    Button(role: b.isRepeat ? nil : .destructive) {
                        if b.isRepeat { askDelete = b } else { model.deleteBlock(b) }
                    } label: { Label("Delete", systemImage: "trash") }
                    .tint(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.smooth, value: rows.map(\.id))
        .confirmationDialog(askDelete.map { "Delete \($0.title)" } ?? "", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }),
                            titleVisibility: .visible, presenting: askDelete) { b in
            let n = ScheduleEdits.repeatEvents(b.series!.id, in: model.blocks).count
            Button("Delete all \(n) events in this repeat", role: .destructive) { model.deleteRepeat(b.series!.id) }
            if !(group && b.isRepeat) {
                Button("Delete only this one", role: .destructive) { model.deleteBlock(b) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// An event's bell, or a block's bar, as the lists show them.
struct KindIcon: View {
    let block: Block
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: block.isEvent ? "bell.fill" : "rectangle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .frame(width: size + 6)
            .accessibilityHidden(true)
    }
}

/// ↻ beside an event made by a repeat.
struct RepeatMark: View {
    var size: CGFloat = 11
    var body: some View {
        Image(systemName: "repeat")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("repeats")
            .accessibilityIdentifier("repeat-mark")
    }
}

struct BlockRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var textSize
    let block: Block

    var body: some View {
        let start = HHMM.minutes(block.start).map(Self.time) ?? block.start
        let end = HHMM.minutes(block.end).map(Self.time) ?? block.end
        // At the largest text sizes the time goes above the name, instead of in a narrow column.
        let stacked = textSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            if stacked {
                HStack(spacing: 8) {
                    KindIcon(block: block)
                    Text(block.isEvent ? start : "\(start) – \(end)").font(.subheadline.weight(.semibold))
                }
                .monospacedDigit()
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(start).font(.subheadline.weight(.semibold))
                    if !block.isEvent { Text(end).font(.caption).foregroundStyle(.secondary) }
                }
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
                KindIcon(block: block).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(block.title).font(.body.weight(.medium))
                    if block.isRepeat { RepeatMark() }
                    if model.ringsOnSilent(block) { RingIcon() }
                }
                let detail = "\(ScheduleEdits.daysText(block.days)) · \(block.isEvent ? model.typeName(for: block) : TimeText.length(minutes: block.lengthMin))"
                if stacked {
                    if !block.isEvent { TypeBadge(name: model.typeName(for: block)) }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        if !block.isEvent { TypeBadge(name: model.typeName(for: block)) }
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let overlap = ScheduleEdits.overlapText(block, in: model.blocks) {
                    Label(overlap, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Palette.sun)
                }
            }
            if !stacked { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(block.isEvent ? "Opens the event to edit" : "Opens the block to edit")
    }

    /// "9:20 AM" for a time of day given in minutes.
    static func time(_ minutes: Int) -> String {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())?.timeText ?? HHMM.string(minutes)
    }
}

/// A whole repeat as one row: "Drink water · 17 events · Every 30 min, 9:00 AM – 5:00 PM".
struct RepeatRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let first: Block
    let count: Int

    var body: some View {
        let stacked = textSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let time = BlockRow.time(first.series.flatMap { HHMM.minutes($0.first) } ?? first.startMin)
        layout {
            if stacked {
                HStack(spacing: 8) { KindIcon(block: first); Text(time).font(.subheadline.weight(.semibold)) }
            } else {
                Text(time)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(width: 74, alignment: .trailing)
                KindIcon(block: first).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(first.title).font(.body.weight(.medium))
                    RepeatMark()
                }
                Text("\(count) events · \(first.series.map { ScheduleEdits.repeatText($0, time: BlockRow.time) } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(ScheduleEdits.daysText(first.days)).font(.caption).foregroundStyle(.secondary)
            }
            if !stacked { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the repeat to edit all its events")
    }
}
