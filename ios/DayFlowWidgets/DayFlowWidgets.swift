import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DayFlowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DayFlowLiveActivity()
        CurrentBlockWidget()
    }
}

// MARK: - Live Activity

/// The current block on the Lock Screen and in the Dynamic Island, counting down to its end.
/// After it ends (the activity is "stale"), it shows what's next until DayFlow runs again.
struct DayFlowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DayFlowActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Palette.accent)
                .widgetURL(URL(string: "dayflow://today"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(s.typeName).font(.caption.weight(.semibold)) } icon: { Image(systemName: "sun.horizon.fill") }
                        .foregroundStyle(Palette.accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale { Text("Ended").font(.caption).foregroundStyle(.secondary) } else {
                        Text(timerInterval: s.start...s.end, countsDown: true)
                            .font(.title3.weight(.semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(.headline).lineLimit(1)
                        if !context.isStale {
                            ProgressView(timerInterval: s.start...s.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(Palette.accent)
                        }
                        if let next = s.nextTitle, let at = s.nextStart {
                            Text("Next: \(next) at \(at.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill").foregroundStyle(Palette.accent)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                } else {
                    Text(timerInterval: s.start...s.end, countsDown: true)
                        .monospacedDigit().frame(maxWidth: 52).foregroundStyle(Palette.accent)
                }
            } minimal: {
                Image(systemName: "sun.horizon.fill").foregroundStyle(Palette.accent)
            }
            .widgetURL(URL(string: "dayflow://today"))
            .keylineTint(Palette.accent)
        }
    }
}

struct LockScreenActivityView: View {
    let state: DayFlowActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stale ? "Up next" : state.typeName.uppercased())
                    .font(.caption2.weight(.bold)).foregroundStyle(Palette.accent)
                if stale {
                    Text(state.nextTitle ?? "Done for today").font(.headline).lineLimit(1)
                    if let at = state.nextStart {
                        Text(at.formatted(date: .omitted, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("\(state.title) ended at \(state.end.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text(state.title).font(.headline).lineLimit(1)
                    if let next = state.nextTitle, let at = state.nextStart {
                        Text("Next: \(next) at \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("Last block today").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if !stale {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                    ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(Palette.accent)
                        .frame(width: 100)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Widgets

/// Small and medium Home Screen widgets and Lock Screen widgets: the current block and its
/// countdown. They read the next two days of blocks that DayFlow writes to the shared App Group
/// folder, and switch blocks on their own at each start and end.
struct CurrentBlockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentBlock", provider: BlockTimeline()) { entry in
            CurrentBlockView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Current block")
        .description("What's happening now and how long is left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct BlockEntry: TimelineEntry {
    let date: Date
    let current: WidgetSnapshot.Item?
    let next: WidgetSnapshot.Item?
    /// false when the widgets can't read DayFlow's data (no App Group with this signing).
    let hasData: Bool
    /// Reminders are turned off at this moment.
    var off = false
}

struct BlockTimeline: TimelineProvider {
    func placeholder(in context: Context) -> BlockEntry {
        let now = Date()
        return BlockEntry(date: now, current: .init(title: "Deep work", typeName: "Focus", start: now, end: now.addingTimeInterval(4200)),
                          next: .init(title: "Email and messages", typeName: "Default", start: now.addingTimeInterval(4200), end: now.addingTimeInterval(6000)),
                          hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BlockEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(from: Date()).first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlockEntry>) -> Void) {
        let list = entries(from: Date())
        completion(Timeline(entries: list, policy: .after(list.last?.date.addingTimeInterval(60) ?? Date().addingTimeInterval(3600))))
    }

    /// An entry now and at every start and end over the snapshot, so the widget switches on time.
    func entries(from now: Date) -> [BlockEntry] {
        guard let snap = WidgetSnapshot.read() else { return [BlockEntry(date: now, current: nil, next: nil, hasData: false)] }
        // An entry at each start and end, and when a 1-hour or 24-hour stop ends.
        let ends = [snap.offUntil].compactMap { $0 }.filter { $0 > now && $0 != .distantFuture }
        let moments = Set(snap.items.flatMap { [$0.start, $0.end] }.filter { $0 > now } + ends)
        let dates = [now] + moments.sorted().prefix(60)
        return dates.map { d in
            BlockEntry(date: d, current: snap.current(at: d), next: snap.next(after: d), hasData: true, off: snap.remindersOff(at: d))
        }
    }
}

struct CurrentBlockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BlockEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    @ViewBuilder var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if let c = entry.current {
                Text(c.title).font(.headline).lineLimit(2)
                Text(timerInterval: c.start...c.end, countsDown: true)
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.accent)
            } else if let n = entry.next {
                Text("Free until").font(.caption).foregroundStyle(.secondary)
                Text(n.title).font(.headline).lineLimit(2)
                Text(n.start, style: .time).font(.subheadline).foregroundStyle(Palette.sun)
            } else {
                Text(entry.hasData ? "Nothing more today" : "Open DayFlow").font(.headline)
            }
            if entry.off { offLine }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var offLine: some View {
        Label("Reminders off", systemImage: "bell.slash.fill")
            .font(.caption2.weight(.semibold)).foregroundStyle(Palette.sun)
            .lineLimit(1)
    }

    @ViewBuilder var medium: some View {
        HStack(spacing: 16) {
            small
            if let n = entry.next, entry.current != nil {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(n.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(n.start, style: .time).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.horizon.fill")
            Text(entry.current?.typeName.uppercased() ?? "DAYFLOW")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Palette.accent)
    }

    @ViewBuilder var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let c = entry.current {
                Text(c.title).font(.headline).lineLimit(1).widgetAccentable()
                Text(timerInterval: c.start...c.end, countsDown: true).monospacedDigit()
                if entry.off { Text("Reminders off").font(.caption).lineLimit(1) }
                else if let n = entry.next { Text("Next: \(n.title)").font(.caption).lineLimit(1).foregroundStyle(.secondary) }
            } else if let n = entry.next {
                Text("Up next").font(.caption).foregroundStyle(.secondary)
                Text(n.title).font(.headline).lineLimit(1).widgetAccentable()
                Text(n.start, style: .time)
            } else {
                Text(entry.hasData ? "Nothing more today" : "Open DayFlow").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder var circular: some View {
        if let c = entry.current {
            ProgressView(timerInterval: c.start...c.end, countsDown: true) { Image(systemName: "sun.horizon.fill") }
                .progressViewStyle(.circular)
        } else {
            Image(systemName: "sun.horizon").font(.title2)
        }
    }

    @ViewBuilder var inline: some View {
        if entry.off {
            Text("DayFlow reminders off")
        } else if let c = entry.current {
            Text("\(c.title) until \(c.end.formatted(date: .omitted, time: .shortened))")
        } else if let n = entry.next {
            Text("Next: \(n.title) at \(n.start.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("DayFlow")
        }
    }
}
