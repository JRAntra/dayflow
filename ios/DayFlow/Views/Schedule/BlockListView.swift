import DayFlowCore
import SwiftUI

/// The weekly plan as a list, earliest first. Tap a block to edit it; swipe left to delete it.
struct BlockListView: View {
    @Environment(AppModel.self) private var model
    let filter: Int?
    let edit: (Block) -> Void

    var shown: [Block] { model.blocks.filter { filter == nil || $0.days.contains(filter!) } }

    var body: some View {
        List {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(model.blocks.isEmpty ? "No blocks yet" : "Nothing on \(ScheduleEdits.dayNames[filter ?? 0])s",
                          systemImage: "calendar.badge.plus")
                } description: {
                    Text(model.blocks.isEmpty ? "Add the phases of your day with ＋. Each one gets reminders from its type."
                         : "None of your blocks repeat on that day.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(shown) { b in
                Button { edit(b) } label: { BlockRow(block: b) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { model.deleteBlock(b) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.smooth, value: shown.map(\.id))
    }
}

struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block

    var body: some View {
        let start = HHMM.minutes(block.start).map(Self.time) ?? block.start
        let end = HHMM.minutes(block.end).map(Self.time) ?? block.end
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(start).font(.subheadline.weight(.semibold))
                if !block.isMoment { Text(end).font(.caption).foregroundStyle(.secondary) }
            }
            .monospacedDigit()
            .frame(width: 74, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(block.title).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    TypeBadge(name: model.typeName(for: block))
                    Text("\(ScheduleEdits.daysText(block.days)) · \(block.isMoment ? "Moment" : TimeText.length(minutes: block.lengthMin))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let overlap = ScheduleEdits.overlapText(block, in: model.blocks) {
                    Label(overlap, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Palette.sun)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the block to edit")
    }

    /// "9:20 AM" for a time of day given in minutes.
    static func time(_ minutes: Int) -> String {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())?.timeText ?? HHMM.string(minutes)
    }
}
