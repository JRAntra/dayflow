import DayFlowCore
import SwiftUI

/// One weekday of your plan as an hour grid, like the Calendar app.
///
/// - Press and hold a block, then drag, to move it; both ends move together.
/// - A held block shows handles at its top and bottom edges; drag them to change its times.
/// - Times snap to 5 minutes with a light tick; a block stays at least 5 minutes long.
/// - Tap a block to edit it; tap an empty slot to add a 30-minute block there.
/// - A block that repeats on several days asks "This day only / All N days" after a change.
struct DayGridView: View {
    @Environment(AppModel.self) private var model
    let day: Int
    let edit: (BlockEditing) -> Void

    static let hourHeight: CGFloat = 64
    static let labelWidth: CGFloat = 56
    static var perMinute: CGFloat { hourHeight / 60 }

    @State private var selected: String?
    @State private var pending: PendingChange?

    struct PendingChange: Identifiable {
        let id = UUID()
        var edited: Block
        var original: Block
    }

    var dayBlocks: [Block] { model.blocks.filter { $0.days.contains(day) } }

    var body: some View {
        let columns = ScheduleEdits.columns(dayBlocks)
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let width = geo.size.width - Self.labelWidth - 12
                    ZStack(alignment: .topLeading) {
                        HourGrid()
                            .contentShape(.rect)
                            .onTapGesture { location in
                                if selected != nil { withAnimation(.snappy) { selected = nil }; return }
                                let minute = Int((location.y / Self.perMinute).rounded(.down))
                                let b = ScheduleEdits.newBlock(at: minute - minute % 15, day: day, blocks: model.blocks)
                                edit(BlockEditing(block: b, original: nil, day: day))
                            }
                        if isToday {
                            NowLine().padding(.leading, Self.labelWidth - 4).zIndex(3)
                        }
                        ForEach(dayBlocks.filter(\.isMoment)) { m in
                            MomentMark(block: m, typeName: model.typeName(for: m), rings: model.ringsOnSilent(m), width: width,
                                       onTap: { edit(BlockEditing(block: m, original: m, day: day)) },
                                       onCommit: { commit($0, original: m) })
                                .padding(.leading, Self.labelWidth)
                                .zIndex(1.5)
                        }
                        ForEach(dayBlocks.filter { !$0.isMoment }) { b in
                            let col = columns[b.id] ?? (0, 1)
                            let colWidth = width / CGFloat(col.of)
                            GridBlock(block: b, typeName: model.typeName(for: b), rings: model.ringsOnSilent(b), selected: selected == b.id,
                                      width: colWidth - 3,
                                      onSelect: { withAnimation(.snappy) { selected = b.id } },
                                      onTap: { edit(BlockEditing(block: b, original: b, day: day)) },
                                      onCommit: { commit($0, original: b) })
                                .padding(.leading, Self.labelWidth + CGFloat(col.column) * colWidth)
                                .zIndex(selected == b.id ? 2 : 1)
                        }
                    }
                }
                .frame(height: Self.hourHeight * 24)
                .padding(.vertical, 12)
            }
            .onAppear { scrollToFirst(proxy) }
            .onChange(of: day) { scrollToFirst(proxy); selected = nil }
        }
        .confirmationDialog(pending.map { "Change \($0.original.title)" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { p in
            Button("This day only") { model.saveBlock(p.edited, original: p.original, day: day, allDays: false) }
            Button("All \(p.original.days.count) days") { model.saveBlock(p.edited, original: p.original, day: day, allDays: true) }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text("\(p.original.title) repeats on \(ScheduleEdits.daysText(p.original.days)).")
        }
    }

    var isToday: Bool { Calendar.current.component(.weekday, from: Date()) - 1 == day }

    func commit(_ edited: Block, original: Block) {
        guard edited.start != original.start || edited.end != original.end else { return }
        if ScheduleEdits.needsDayChoice(original, day: day) {
            pending = PendingChange(edited: edited, original: original)
        } else {
            model.saveBlock(edited, original: original, day: day, allDays: true)
        }
    }

    func scrollToFirst(_ proxy: ScrollViewProxy) {
        let first = dayBlocks.map(\.startMin).min() ?? 8 * 60
        proxy.scrollTo("hour-\(max(0, first / 60 - (first % 60 < 20 ? 1 : 0)))", anchor: .top)
    }
}

/// Hour lines and labels, midnight to midnight.
struct HourGrid: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.hourLabel(h))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .frame(width: DayGridView.labelWidth - 8, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle().fill(.separator).frame(height: 0.5)
                        Spacer()
                        Rectangle().fill(.separator.opacity(0.4)).frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: DayGridView.hourHeight, alignment: .top)
                .id("hour-\(h)")
            }
        }
        .accessibilityHidden(true)
    }

    /// "9 AM", "12 PM", or "09" in 24-hour regions, like the Calendar app.
    static func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(.dateTime.hour())
    }
}

/// A red line at the current time, on today's weekday.
struct NowLine: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
            let y = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) * DayGridView.perMinute
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .offset(y: y - 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A moment in the grid: a thin line with its name at its time. Hold and drag to move it; it
/// has no length to resize. Tap to edit it.
struct MomentMark: View {
    let block: Block
    let typeName: String
    /// Rings even on silent: shows the alarm icon.
    var rings = false
    let width: CGFloat
    let onTap: () -> Void
    let onCommit: (Block) -> Void

    @GestureState private var dy: CGFloat?
    @State private var held = false

    func minutes(_ dy: CGFloat) -> Int { ScheduleEdits.snap(Int((dy / DayGridView.perMinute).rounded())) }
    var preview: Block { dy.map { ScheduleEdits.moved(block, by: minutes($0)) } ?? block }

    var body: some View {
        let b = preview
        HStack(spacing: 6) {
            Rectangle().fill(Palette.accent).frame(width: 9, height: 9).rotationEffect(.degrees(45))
            Text(b.title).font(.caption.weight(.semibold)).lineLimit(1)
            if rings { RingIcon(size: 9) }
            Text(dy != nil ? BlockRow.time(b.startMin) : typeName)
                .font(.caption2).foregroundStyle(dy != nil ? Palette.accent : .secondary).monospacedDigit()
            Rectangle().fill(Palette.accent.opacity(0.6)).frame(height: 1.5)
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: 18, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.85), in: .capsule)
        .contentShape(.rect)
        .shadow(color: .black.opacity(dy != nil ? 0.18 : 0), radius: 6, y: 3)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .updating($dy) { v, state, _ in if case .second(true, let d?) = v { state = d.translation.height } }
                .onChanged { v in if case .second(true, _) = v { held = true } }
                .onEnded { v in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { held = false }
                    if case .second(true, let d?) = v { onCommit(ScheduleEdits.moved(block, by: minutes(d.translation.height))) }
                }
        )
        .simultaneousGesture(TapGesture().onEnded { if held { held = false } else { onTap() } })
        .sensoryFeedback(.selection, trigger: dy.map(minutes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), a moment at \(BlockRow.time(block.startMin)), \(typeName)\(rings ? ", \(RingIcon.spoken)" : "")")
        .accessibilityHint("Double-tap to edit. Swipe up or down for actions to move it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: "Move 5 minutes earlier") { onCommit(ScheduleEdits.moved(block, by: -5)) }
        .accessibilityAction(named: "Move 5 minutes later") { onCommit(ScheduleEdits.moved(block, by: 5)) }
        // Centred on its time.
        .padding(.top, max(0, CGFloat(b.startMin) * DayGridView.perMinute - 9))
    }
}

/// One block in the grid, with its own move and resize gestures. While you drag, it shows the
/// times it will have; the change is only saved when you let go.
struct GridBlock: View {
    let block: Block
    let typeName: String
    /// Rings even on silent: shows the alarm icon.
    var rings = false
    let selected: Bool
    let width: CGFloat
    let onSelect: () -> Void
    let onTap: () -> Void
    let onCommit: (Block) -> Void

    enum DragMode { case move, top, bottom }
    @GestureState private var drag: (mode: DragMode, dy: CGFloat)?
    @State private var lifted = false
    /// A hold happened; the tap that ends it shouldn't open the editor.
    @State private var held = false

    func minutes(_ dy: CGFloat) -> Int { ScheduleEdits.snap(Int((dy / DayGridView.perMinute).rounded())) }

    /// The block as it would be after the current drag.
    var preview: Block {
        guard let drag else { return block }
        let d = minutes(drag.dy)
        switch drag.mode {
        case .move: return ScheduleEdits.moved(block, by: d)
        case .top: return ScheduleEdits.resized(block, start: ScheduleEdits.snap(block.startMin + d))
        case .bottom: return ScheduleEdits.resized(block, end: ScheduleEdits.snap(block.endMin + d))
        }
    }

    var body: some View {
        let b = preview
        // A point of space above and below, so blocks that touch still read as two.
        let height = max(CGFloat(b.lengthMin) * DayGridView.perMinute - 2, 16)
        let compact = height < 40
        let dragging = drag != nil
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(b.title).font(.caption.weight(.semibold)).lineLimit(compact ? 1 : 2)
                if rings { RingIcon(size: 9) }
            }
            if !compact || dragging {
                Text(dragging ? "\(BlockRow.time(b.startMin)) – \(BlockRow.time(b.endMin))" : typeName)
                    .font(.caption2).foregroundStyle(dragging ? Palette.accent : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 1 : 4)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Palette.accent.opacity(selected ? 0.28 : 0.16), in: .rect(cornerRadius: 6))
        .background(Color(.systemBackground), in: .rect(cornerRadius: 6))
        // The block's own touch area, set before the handles so theirs (just outside its
        // edges) still receive touches.
        .contentShape(.rect)
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6).fill(Palette.accent).frame(width: 3) }
        .overlay { if selected { RoundedRectangle(cornerRadius: 6).stroke(Palette.accent, lineWidth: 1.5) } }
        .overlay(alignment: .top) { if selected { handle(.top).offset(y: -11) } }
        .overlay(alignment: .bottom) { if selected { handle(.bottom).offset(y: 11) } }
        .scaleEffect(lifted || dragging ? 1.02 : 1, anchor: .center)
        .shadow(color: .black.opacity(dragging ? 0.18 : 0), radius: 8, y: 4)
        // The hold-and-drag is the block's gesture; a tap runs alongside it (a separate tap
        // gesture would keep the hold from being recognised), and is ignored after a hold.
        .gesture(moveGesture)
        .simultaneousGesture(TapGesture().onEnded {
            if held { held = false } else { onTap() }
        })
        .sensoryFeedback(.selection, trigger: drag.map { minutes($0.dy) })
        .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
        .animation(.snappy(duration: 0.2), value: b)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.title), \(BlockRow.time(block.startMin)) to \(BlockRow.time(block.endMin)), \(typeName)\(rings ? ", \(RingIcon.spoken)" : "")")
        .accessibilityHint("Double-tap to edit. Swipe up or down for actions to move or resize.")
        .accessibilityAction(named: "Move 5 minutes earlier") { onCommit(ScheduleEdits.moved(block, by: -5)) }
        .accessibilityAction(named: "Move 5 minutes later") { onCommit(ScheduleEdits.moved(block, by: 5)) }
        .accessibilityAction(named: "Make 5 minutes longer") { onCommit(ScheduleEdits.resized(block, end: block.endMin + 5)) }
        .accessibilityAction(named: "Make 5 minutes shorter") { onCommit(ScheduleEdits.resized(block, end: block.endMin - 5)) }
        // Placed with padding rather than an offset, so VoiceOver and touches find it where it's drawn.
        .padding(.top, CGFloat(b.startMin) * DayGridView.perMinute + 1)
    }

    /// Press and hold to lift the block, then drag to move it.
    var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($drag) { value, state, _ in
                if case .second(true, let d?) = value { state = (.move, d.translation.height) }
            }
            .onChanged { value in
                if case .second(true, _) = value, !lifted { lifted = true; held = true; onSelect() }
            }
            .onEnded { value in
                lifted = false
                // If no tap follows the hold, forget it shortly so the next tap works.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { held = false }
                if case .second(true, let d?) = value { onCommit(moved(d.translation.height)) }
            }
    }

    func moved(_ dy: CGFloat) -> Block { ScheduleEdits.moved(block, by: minutes(dy)) }

    func handle(_ mode: DragMode) -> some View {
        Capsule()
            .fill(Palette.accent)
            .frame(width: 28, height: 6)
            .padding(8) // a bigger area to grab
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($drag) { v, state, _ in state = (mode, v.translation.height) }
                    .onChanged { _ in held = true } // the touch that ends this isn't a tap on the block
                    .onEnded { v in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { held = false }
                        let d = minutes(v.translation.height)
                        onCommit(mode == .top ? ScheduleEdits.resized(block, start: ScheduleEdits.snap(block.startMin + d))
                                              : ScheduleEdits.resized(block, end: ScheduleEdits.snap(block.endMin + d)))
                    }
            )
            .accessibilityHidden(true)
    }
}
