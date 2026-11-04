import DayFlowCore
import SwiftUI

/// Today: the dial with what's happening now, Pause, and the day's timeline.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let planner = model.planner
                let blocks = planner.blocksFor(now)
                let meetings = model.meetings.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
                ScrollView {
                    VStack(spacing: 16) {
                        Text(now.formatted(.dateTime.month(.wide).day()) + " · " + now.timeText)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                            PauseRow(now: now)
                                .padding(.bottom, 4)
                        }
                        .padding(16)
                        .background(.background, in: .rect(cornerRadius: 22))

                        DayTimeline(blocks: blocks, meetings: meetings, now: now)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(now.formatted(.dateTime.weekday(.wide)))
                .navigationBarTitleDisplayMode(.large)
            }
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
                Text(model.blocks.isEmpty ? "Add the phases of your day to get reminders."
                     : "None of your blocks repeat on \(ScheduleEdits.dayNames[Calendar.current.component(.weekday, from: now) - 1])s.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Plan your day") { model.tab = .schedule }
                    .buttonStyle(.borderedProminent).controlSize(.small).padding(.top, 4)
            } else if let current {
                TypeBadge(name: model.typeOf(current.type).name)
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
                Text("Every block has finished.").font(.caption).foregroundStyle(.secondary)
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

/// Pause reminders for 1 hour, or how long they're paused for, with Resume.
struct PauseRow: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        Group {
            if let until = model.settings.pausedUntil, now < until {
                HStack {
                    Label("Paused until \(until.timeText)", systemImage: "pause.circle.fill")
                        .font(.subheadline).foregroundStyle(Palette.sun)
                    Spacer()
                    Button("Resume") { model.resume() }.font(.subheadline.weight(.semibold))
                }
            } else {
                Button {
                    model.pauseForAnHour()
                } label: {
                    Label("Pause reminders for 1 hour", systemImage: "pause.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.onboarded)
            }
        }
        .sensoryFeedback(.success, trigger: model.settings.pausedUntil)
    }
}

/// The day's flow: blocks and meetings in time order, the current one highlighted.
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
    }

    var items: [Item] {
        (blocks.map(Item.block) + meetings.map(Item.meeting)).enumerated().sorted { a, b in
            if a.element.start != b.element.start { return a.element.start < b.element.start }
            if a.element.isMeeting != b.element.isMeeting { return !a.element.isMeeting }
            return a.offset < b.offset
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's flow").font(.title3.weight(.semibold)).padding(.leading, 4)
            if items.isEmpty {
                Text(model.calendarAccess ? "No blocks or meetings today." : "No blocks today. To see meetings too, choose calendars in Settings › Calendars.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: .rect(cornerRadius: 16))
            } else {
                VStack(spacing: 2) {
                    ForEach(items) { item in row(item) }
                }
                .padding(.vertical, 8)
                .background(.background, in: .rect(cornerRadius: 16))
                .animation(.smooth, value: items.first { isCurrent($0) }?.id)
            }
        }
    }

    func isCurrent(_ i: Item) -> Bool { if case .block = i { return i.start <= now && now < i.end }; return false }

    func row(_ i: Item) -> some View {
        let past = now >= i.end
        let current = isCurrent(i)
        let tint = i.isMeeting ? Palette.sun : Palette.accent
        return HStack(spacing: 12) {
            Text(i.start.timeText)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
                .monospacedDigit()
            Group {
                if i.isMeeting { RoundedRectangle(cornerRadius: 3).fill(tint) } else { Circle().fill(tint) }
            }
            .frame(width: current ? 12 : 9, height: current ? 12 : 9)
            .overlay { if current { Circle().stroke(tint.opacity(0.25), lineWidth: 6) } }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).font(.body.weight(current ? .semibold : .regular))
                HStack(spacing: 6) {
                    switch i {
                    case .block(let b): Text(model.typeOf(b.type).name)
                    case .meeting: Text("Meeting")
                    }
                    Text("· until \(i.end.timeText)")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if case .meeting(let m) = i, let url = m.url, now < m.end {
                Button("Join") { openURL(url) }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.sun)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if current { RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.1)).padding(.horizontal, 6) }
        }
        .opacity(past ? 0.45 : 1)
        .accessibilityElement(children: .combine)
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
