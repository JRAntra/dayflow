import DayFlowCore
import SwiftUI

/// One weekday of your plan as an hour grid, like the Calendar app.
///
/// - Press and hold a block, then drag, to move it; both ends move together.
/// - A held block shows handles at its top and bottom edges; drag them to change its times.
/// - Times snap to 5 minutes with a light tick; a block stays at least 5 minutes long.
/// - Events are pills at their time; a repeat's events don't drag (change the repeat instead).
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
    /// An event pill's height, which grows with the text size.
    @ScaledMetric(relativeTo: .caption) private var pillHeight: CGFloat = 20

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
                        // Events sit at the right, over any block (whose name stays readable on
                        // the left); events too close to share a line go side by side.
                        let lanes = Self.eventLanes(dayBlocks.filter(\.isEvent), minutesTall: Double(pillHeight / Self.perMinute) + 1)
                        let region = min(width, max(170, width * 0.62))
                        ForEach(dayBlocks.filter(\.isEvent)) { m in
                            let lane = lanes[m.id] ?? (0, 1)
                            let laneWidth = region / CGFloat(lane.of)
                            EventMark(block: m, done: isToday && model.isDone(m.id), skipped: isToday && model.isSkipped(m.id),
                                      width: laneWidth - 3, height: pillHeight,
                                      onTap: { edit(BlockEditing(block: m, original: m, day: day)) },
                                      onCommit: { commit($0, original: m) })
                                .padding(.leading, Self.labelWidth + width - region + CGFloat(lane.lane) * laneWidth)
                                .zIndex(1.5)
                        }
                        ForEach(dayBlocks.filter { !$0.isMoment }) { b in
                            let col = columns[b.id] ?? (0, 1)
                            let colWidth = width / CGFloat(col.of)
                            GridBlock(block: b, typeName: model.typeName(for: b), rings: model.ringsOnSilent(b), selected: selected == b.id,
                                      skipped: isToday && model.isSkipped(b.id),
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

    /// Side-by-side lanes for events whose pills (`minutesTall` minutes of grid) would touch:
    /// each event's lane, and how many lanes its cluster has.
    static func eventLanes(_ events: [Block], minutesTall: Double) -> [String: (lane: Int, of: Int)] {
        var result: [String: (Int, Int)] = [:]
        var cluster: [(String, Int)] = []
        var laneEnds: [Double] = []
        var clusterEnd = -Double.infinity
        func flush() {
            let n = (cluster.map(\.1).max() ?? -1) + 1
            for (id, l) in cluster { result[id] = (l, n) }
            cluster = []; laneEnds = []
        }
        for e in events.sorted(by: { $0.startMin < $1.startMin }) {
            let start = Double(e.startMin) - minutesTall / 2
            if start >= clusterEnd { flush() }
            let end = start + minutesTall
            if let l = laneEnds.firstIndex(where: { $0 <= start }) { laneEnds[l] = end; cluster.append((e.id, l)) }
            else { laneEnds.append(end); cluster.append((e.id, laneEnds.count - 1)) }
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return result
    }

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

/// An event in the grid: a pill with a bell, its name and its time. Hold and drag to move it
/// (it has no length to resize), except an event from a repeat: change those in the repeat.
/// Tap to edit it. On today's weekday, a checked-off event is gold and a skipped one struck through.
struct EventMark: View {
    let block: Block
    var done = false
    var skipped = false
    let width: CGFloat
    var height: CGFloat = 20
    let onTap: () -> Void
    let onCommit: (Block) -> Void

    @GestureState private var dy: CGFloat?
    @State private var held = false

    func minutes(_ dy: CGFloat) -> Int { ScheduleEdits.snap(Int((dy / DayGridView.perMinute).rounded())) }
    var preview: Block { dy.map { ScheduleEdits.moved(block, by: minutes($0)) } ?? block }

    var body: some View {
        let b = preview
        let tint = done ? Palette.sun : Palette.accent
        // With room, the name and the time; in a narrow lane, just the name.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Image(systemName: done ? "star.fill" : "bell.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                Text(b.title).font(.caption.weight(.semibold)).lineLimit(1).strikethrough(skipped)
                if block.isRepeat { RepeatMark(size: 8) }
                Text(BlockRow.time(b.startMin))
                    .font(.caption2).foregroundStyle(dy != nil ? Palette.accent : .secondary).monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()
            HStack(spacing: 5) {
                Image(systemName: done ? "star.fill" : "bell.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
                Text(b.title).font(.caption.weight(.semibold)).lineLimit(1).strikethrough(skipped)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: height, alignment: .leading)
        .background(tint.opacity(done ? 0.22 : 0.14), in: .capsule)
        .background(Color(.systemBackground), in: .capsule)
        .overlay { Capsule().stroke(tint.opacity(0.5), lineWidth: 1) }
        .opacity(skipped ? 0.45 : 1)
        .contentShape(.rect)
        .shadow(color: .black.opacity(dy != nil ? 0.18 : 0), radius: 6, y: 3)
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .updating($dy) { v, state, _ in
                    if !block.isRepeat, case .second(true, let d?) = v { state = d.translation.height }
                }
                .onChanged { v in if case .second(true, _) = v { held = true } }
                .onEnded { v in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { held = false }
                    if !block.isRepeat, case .second(true, let d?) = v { onCommit(ScheduleEdits.moved(block, by: minutes(d.translation.height))) }
                }
        )
        .simultaneousGesture(TapGesture().onEnded { if held { held = false } else { onTap() } })
        .sensoryFeedback(.selection, trigger: dy.map(minutes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), an event at \(BlockRow.time(block.startMin))\(block.isRepeat ? ", repeats" : "")\(done ? ", done" : "")\(skipped ? ", skipped today" : "")")
        .accessibilityHint(block.isRepeat ? "Double-tap to edit the repeat or this event." : "Double-tap to edit. Swipe up or down for actions to move it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .modifier(MoveActions(enabled: !block.isRepeat, block: block, onCommit: onCommit))
        // Centred on its time.
        .padding(.top, max(0, CGFloat(b.startMin) * DayGridView.perMinute - height / 2))
    }
}

/// "Move 5 minutes earlier/later" for VoiceOver, when the item can be moved.
struct MoveActions: ViewModifier {
    let enabled: Bool
    let block: Block
    let onCommit: (Block) -> Void
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named: "Move 5 minutes earlier") { onCommit(ScheduleEdits.moved(block, by: -5)) }
                .accessibilityAction(named: "Move 5 minutes later") { onCommit(ScheduleEdits.moved(block, by: 5)) }
        } else {
            content
        }
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
    /// Skipped today: struck through and greyed.
    var skipped = false
    let width: CGFloat
    let onSelect: () -> Void
    let onTap: () -> Void
    let onCommit: (Block) -> Void

    @ScaledMetric(relativeTo: .caption) private var twoLines: CGFloat = 40

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
        // Room for a second line (the type) only when the block is tall enough for it at this
        // text size; whatever doesn't fit is cut at the block's edge, never drawn over the next.
        let compact = height < twoLines
        let dragging = drag != nil
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(b.title).font(.caption.weight(.semibold)).lineLimit(compact ? 1 : 2).strikethrough(skipped)
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
        .clipped()
        .background(Palette.accent.opacity(selected ? 0.28 : 0.16), in: .rect(cornerRadius: 6))
        .background(Color(.systemBackground), in: .rect(cornerRadius: 6))
        // The block's own touch area, set before the handles so theirs (just outside its
        // edges) still receive touches.
        .contentShape(.rect)
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6).fill(Palette.accent).frame(width: 3) }
        .overlay { if selected { RoundedRectangle(cornerRadius: 6).stroke(Palette.accent, lineWidth: 1.5) } }
        .overlay(alignment: .top) { if selected { handle(.top).offset(y: -11) } }
        .overlay(alignment: .bottom) { if selected { handle(.bottom).offset(y: 11) } }
        .opacity(skipped ? 0.45 : 1)
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
