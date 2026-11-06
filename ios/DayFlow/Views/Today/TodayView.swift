import DayFlowCore
import SwiftUI

/// Today: the dial with what's happening now, Pause, and the day's timeline.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            // The list updates once a minute (everything in it changes on the minute); only the
            // dial and its countdown update every second. Redrawing the whole list every second
            // would cancel a swipe in progress on iOS 17.
            TimelineView(.everyMinute) { context in
                let now = context.date
                let planner = model.planner
                let withSkipped = planner.blocksFor(now, includeSkipped: true)
                let meetings = model.meetings.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
                // A list, so the day's flow gets the system's own swipe to skip.
                List {
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        header(tick.date)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    DayTimeline(blocks: withSkipped, meetings: meetings, now: now)
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(12)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .background(Color(.systemGroupedBackground))
                .navigationTitle(now.formatted(.dateTime.weekday(.wide)))
                .navigationBarTitleDisplayMode(.large)
            }
        }
    }

    /// The date and time, today's progress, any notice, and the dial with the countdown.
    func header(_ now: Date) -> some View {
        let blocks = model.planner.blocksFor(now)
        let meetings = model.meetings.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(now.formatted(.dateTime.month(.wide).day()) + " · " + now.timeText)
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ProgressPill(now: now)
            }
            .padding(.leading, 4)
            .padding(.top, -8)
            notices
            VStack(spacing: 0) {
                ZStack {
                    DialView(blocks: blocks, meetings: meetings, now: now)
                    NowReadout(blocks: blocks, now: now)
                        .padding(.horizontal, 84)
                }
                .frame(maxWidth: 360)
                .padding(.vertical, 4)
                TurnOffRow(now: now)
                    .padding(.bottom, 4)
            }
            .padding(16)
            .background(.background, in: .rect(cornerRadius: 22))
        }
    }

    /// Reminders off, or the free plan's App Group missing: say so at the top.
    @ViewBuilder var notices: some View {
        if model.notificationStatus == .denied {
            NoticeCard(icon: "bell.slash.fill", tint: .red, text: "Reminders are off. Allow notifications for DayFlow in Settings.",
                       button: "Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }
}

/// The centre of the dial: the current block's type, name and countdown, or the free time left.
struct NowReadout: View {
    @Environment(AppModel.self) private var model
    let blocks: [DayBlock]
    let now: Date

    var body: some View {
        let current = blocks.first { $0.start <= now && now < $0.end }
        let next = blocks.first { $0.start > now }
        VStack(spacing: 6) {
            if blocks.isEmpty {
                Text("Nothing planned today").font(.headline).multilineTextAlignment(.center)
                Text(model.blocks.isEmpty ? "Add events and the blocks of your day to get reminders."
                     : "Nothing repeats on \(ScheduleEdits.dayNames[Calendar.current.component(.weekday, from: now) - 1])s, or you've skipped it all.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Plan your day") { model.tab = .schedule }
                    .buttonStyle(.borderedProminent).controlSize(.small).padding(.top, 4)
            } else if let current {
                TypeBadge(name: model.typeName(for: current.block))
                Text(current.title).font(.headline).multilineTextAlignment(.center).lineLimit(2)
                countdown(current.end.timeIntervalSince(now))
                let after = blocks.first { $0.start >= current.end }
                Text(after.map { "Ends at \(current.end.timeText). Next is \($0.title)." } ?? "Ends at \(current.end.timeText). Last block today.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            } else if let next {
                Text("Free time").font(.headline)
                countdown(next.start.timeIntervalSince(now))
                Text("\(next.title) starts at \(next.start.timeText).")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            } else {
                Text("Done for today").font(.headline)
                Text("Everything has finished.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    func countdown(_ seconds: TimeInterval) -> some View {
        Text(TimeText.countdown(seconds))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: Int(seconds))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

/// Turn off reminders…, or how long they're off for, with Turn on.
struct TurnOffRow: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        Group {
            if let status = TurnOff.status(model.settings, now: now) {
                HStack {
                    Label(status, systemImage: "bell.slash.fill")
                        .font(.subheadline).foregroundStyle(Palette.sun)
                    Spacer(minLength: 8)
                    Button("Turn on") { model.turnOn() }.font(.subheadline.weight(.semibold))
                }
            } else {
                TurnOffMenu {
                    Label("Turn off reminders…", systemImage: "bell.slash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                }
                .disabled(!model.onboarded)
            }
        }
        .sensoryFeedback(.success, trigger: model.settings.remindersOff)
    }
}

/// The three choices: For 1 hour, For 24 hours, Until I turn them on.
struct TurnOffMenu<Label: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Section("Turn off reminders") {
                ForEach(TurnOff.allCases) { c in Button(c.label) { model.turnOff(c) } }
            }
        } label: {
            label().contentShape(.rect)
        }
    }
}

/// Today's events done so far, and the streak: "3 of 6 · 🔥 5".
struct ProgressPill: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let r = model.planner.result(on: now)
        let streak = model.streak
        if r.total > 0 || streak > 0 {
            HStack(spacing: 6) {
                if r.total > 0 {
                    Label("\(r.done) of \(r.total)", systemImage: r.done == r.total ? "star.fill" : "star")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(r.done > 0 ? Palette.sun : .secondary)
                }
                if streak > 0 { Text("🔥 \(streak)").foregroundStyle(.primary) }
            }
            .font(.subheadline.weight(.semibold)).monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(r.done) of \(r.total) events done today\(streak > 0 ? ", \(streak)-day streak" : "")")
            .accessibilityIdentifier("progress-pill")
        }
    }
}

/// The day's flow: events, blocks and meetings in time order, the current block highlighted.
/// Each event has a check: done, it turns gold. Swipe a row left to skip it today (struck
/// through and quiet until tomorrow), and again to bring it back. A section of Today's list.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let blocks: [DayBlock]
    let meetings: [Meeting]
    let now: Date

    enum Item: Identifiable {
        case block(DayBlock), meeting(Meeting)
        var id: String { switch self { case .block(let b): "b|\(b.id)"; case .meeting(let m): "m|\(m.id)|\(m.start)" } }
        var start: Date { switch self { case .block(let b): b.start; case .meeting(let m): m.start } }
        var end: Date { switch self { case .block(let b): b.end; case .meeting(let m): m.end } }
        var title: String { switch self { case .block(let b): b.title; case .meeting(let m): m.title } }
        var isMeeting: Bool { if case .meeting = self { return true }; return false }
        var isEvent: Bool { if case .block(let b) = self { return b.block.isEvent }; return false }
        var block: Block? { if case .block(let b) = self { return b.block }; return nil }
    }

    var items: [Item] {
        (blocks.map(Item.block) + meetings.map(Item.meeting)).enumerated().sorted { a, b in
            if a.element.start != b.element.start { return a.element.start < b.element.start }
            if a.element.isMeeting != b.element.isMeeting { return !a.element.isMeeting }
            return a.offset < b.offset
        }.map(\.element)
    }

    var body: some View {
        Section {
            if items.isEmpty {
                Text(model.calendarAccess ? "Nothing planned and no meetings today." : "Nothing planned today. To see meetings too, choose calendars in Settings › Calendars.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(items) { item in
                let done = item.isEvent && item.block.map { model.isDone($0.id) } == true
                row(item)
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 10))
                    .listRowBackground(rowBackground(item, done: done))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if let b = item.block {
                            let skipped = model.isSkipped(b.id)
                            Button {
                                withAnimation(.snappy) { model.setSkipped(b.id, !skipped) }
                            } label: {
                                Label(skipped ? "Bring back" : "Skip today", systemImage: skipped ? "arrow.uturn.backward" : "forward.end")
                            }
                            .tint(skipped ? Palette.accent : .gray)
                        }
                    }
            }
        } header: {
            Text("Today's flow").font(.title3.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
                .padding(.leading, -12)
        }
        .animation(.smooth, value: items.first { isCurrent($0) }?.id)
    }

    /// Gold behind a checked-off event, the accent behind the current block.
    func rowBackground(_ i: Item, done: Bool) -> some View {
        ZStack {
            Color(.secondarySystemGroupedBackground)
            if done { RoundedRectangle(cornerRadius: 12).fill(Palette.sun.opacity(0.16)).padding(4) }
            else if isCurrent(i) { RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.1)).padding(4) }
        }
    }

    func isCurrent(_ i: Item) -> Bool {
        if case .block(let b) = i, !model.isSkipped(b.id) { return i.start <= now && now < i.end }
        return false
    }

    func row(_ i: Item) -> some View {
        let skipped = i.block.map { model.isSkipped($0.id) } ?? false
        let done = i.isEvent && i.block.map { model.isDone($0.id) } == true
        let past = now >= i.end && !done
        let current = isCurrent(i)
        let tint = i.isMeeting ? Palette.sun : Palette.accent
        return HStack(spacing: 12) {
            Text(i.start.timeText)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
                .monospacedDigit()
            if i.isEvent, let b = i.block {
                CheckButton(done: done, disabled: skipped) { withAnimation(.snappy) { model.setDone(b.id, !done) } }
                    .frame(width: 24)
            } else {
                Group {
                    if i.isMeeting { RoundedRectangle(cornerRadius: 3).fill(tint) }
                    else { Circle().fill(tint) }
                }
                .frame(width: current ? 12 : 9, height: current ? 12 : 9)
                .overlay { if current { Circle().stroke(tint.opacity(0.25), lineWidth: 6) } }
                .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(i.title).font(.body.weight(current || done ? .semibold : .regular)).strikethrough(skipped)
                    if i.block?.isRepeat == true { RepeatMark() }
                    if case .block(let b) = i, model.ringsOnSilent(b.block) { RingIcon() }
                }
                HStack(spacing: 6) {
                    switch i {
                    case .block(let b): Text(model.typeName(for: b.block))
                    case .meeting: Text("Meeting")
                    }
                    // An event happens at its time; blocks and meetings last until their end.
                    Text(skipped ? "· skipped today" : done ? "· done" : i.isEvent ? "· at \(i.start.timeText)" : "· until \(i.end.timeText)")
                }
                .font(.caption).foregroundStyle(done ? Palette.sun : .secondary)
            }
            Spacer(minLength: 4)
            if case .meeting(let m) = i, let url = m.url, now < m.end {
                Button("Join") { openURL(url) }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.sun)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .foregroundStyle(skipped ? .secondary : .primary)
        .opacity(skipped ? 0.5 : past ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(skipped ? "Skipped today" : done ? "Done" : "")
        .accessibilityIdentifier("today-\(i.title)")
    }
}

/// An event's check in Today: a circle, or a gold star once it's done.
struct CheckButton: View {
    let done: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "star.circle.fill" : "circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(done ? Palette.sun : .secondary)
                .symbolEffect(.bounce, value: done)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .accessibilityLabel(done ? "Done" : "Check off")
        .accessibilityIdentifier("check")
    }
}

/// A coloured note at the top of a screen, with one button.
struct NoticeCard: View {
    let icon: String
    let tint: Color
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.subheadline)
                Button(button, action: action).font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}
