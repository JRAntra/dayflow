import DayFlowCore
import SwiftUI

/// The welcome screens the first time, then three tabs: Today, Schedule and Settings.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.onboarded {
                TabView(selection: $model.tab) {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "sun.horizon") }
                        .tag(AppTab.today)
                    ScheduleView()
                        .tabItem { Label("Schedule", systemImage: "calendar.day.timeline.left") }
                        .tag(AppTab.schedule)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: model.onboarded)
        .overlay(alignment: .bottom) {
            if let banner = model.banner {
                BannerView(banner: banner)
                    .padding(.horizontal, 16)
                    .padding(.bottom, model.onboarded ? 60 : 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(banner.id)
            }
        }
        .animation(.snappy, value: model.banner?.id)
        // The cheer-up after checking an event off.
        .overlay(alignment: .top) {
            if let cheer = model.cheer {
                CheerView(cheer: cheer)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .id(cheer.id)
                    .onTapGesture { withAnimation(.smooth) { model.cheer = nil } }
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.35), value: model.cheer?.id)
        // Choose 30 seconds, from Sounds or from a song shared or AirDropped to DayFlow.
        .sheet(item: $model.pieceRequest) { r in PieceSheet(request: r) }
        #if DEBUG
        // UI tests check this to know the app really started with their launch options (the
        // Simulator sometimes hands them an app that's already running without them).
        .overlay(alignment: .topLeading) {
            Text(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))
                .font(.system(size: 1)).opacity(0.02).allowsHitTesting(false)
                .accessibilityIdentifier("launch-arguments")
        }
        .overlay(alignment: .topTrailing) {
            Text("alarms \(model.alarmCount)")
                .font(.system(size: 1)).opacity(0.02).allowsHitTesting(false)
                .accessibilityIdentifier("alarm-count")
        }
        // For testing in the Simulator: `simctl launch … -startTab schedule` opens that tab.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "startTab") {
            case "schedule": model.tab = .schedule
            case "settings": model.tab = .settings
            default: break
            }
        }
        #endif
    }
}

/// "Nice! 3 of 6 done today", a ring filling to the day's share, and the streak. All done says so.
struct CheerView: View {
    let cheer: Cheer
    @State private var filled = false

    var share: Double { cheer.total > 0 ? Double(cheer.done) / Double(cheer.total) : 1 }
    var headline: String {
        if cheer.total > 0 && cheer.done >= cheer.total { return "All \(cheer.total) done today! 🎉" }
        return ["Nice!", "Well done!", "Great job!", "Keep it up!"][cheer.done % 4]
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Palette.sun.opacity(0.22), lineWidth: 6)
                Circle().trim(from: 0, to: filled ? share : max(0, share - 1 / Double(max(cheer.total, 1))))
                    .stroke(Palette.sun, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "star.fill").foregroundStyle(Palette.sun).font(.system(size: 16, weight: .bold))
                    .scaleEffect(filled ? 1 : 0.4)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                Text(cheer.total > 0 && cheer.done < cheer.total ? "\(cheer.done) of \(cheer.total) done today" : "Every event checked off")
                    .font(.subheadline).foregroundStyle(.secondary)
                if cheer.streak > 0 {
                    Text("\(cheer.streak)-day streak 🔥").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.sun)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(Palette.sun.opacity(0.35), lineWidth: 1) }
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.4).delay(0.15)) { filled = true } }
        .sensoryFeedback(.success, trigger: filled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("cheer")
    }
}

/// A floating message, like the Mac's toast, with Undo when it can be undone.
struct BannerView: View {
    @Environment(AppModel.self) private var model
    let banner: Banner

    var body: some View {
        HStack(spacing: 12) {
            if banner.isError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Text(banner.text)
                .accessibilityIdentifier("banner-text")
                .font(.subheadline)
                .foregroundStyle(banner.isError ? .red : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let undo = banner.undo {
                Button("Undo") {
                    model.banner = nil
                    undo()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .contain) // the message and Undo are read and pressed separately
    }
}

/// A type's name in a small rounded label, like the Mac's badge.
/// The alarm clock beside a block that rings even on silent.
struct RingIcon: View {
    static let spoken = "rings even on silent"
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "alarm.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.sun)
            .accessibilityLabel(Self.spoken)
            .accessibilityIdentifier("ring-icon")
    }
}

struct TypeBadge: View {
    let name: String
    var tint: Color = Palette.accent

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

/// M T W T F S S. Tapping a day picks it; "All" is shown when `allowsAll` is on.
struct DayStrip: View {
    @Binding var selection: Int?
    var allowsAll = false

    var body: some View {
        HStack(spacing: 6) {
            if allowsAll {
                chip("All", selected: selection == nil) { selection = nil }
            }
            ForEach(ScheduleEdits.weekOrder, id: \.self) { d in
                chip(ScheduleEdits.dayLetters[d], selected: selection == d) { selection = d }
                    .accessibilityLabel(ScheduleEdits.dayNames[d])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        // Eight chips share one row: past a point, bigger letters wouldn't fit in them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selected ? Color.white : .primary)
                .background(selected ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.fill.tertiary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Repeats on: seven toggles, S M T W T F S, Monday first.
struct DayToggles: View {
    @Binding var days: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleEdits.weekOrder, id: \.self) { d in
                let on = days.contains(d)
                Button {
                    if on { days.removeAll { $0 == d } } else { days = (days + [d]).sorted() }
                } label: {
                    Text(ScheduleEdits.dayLetters[d])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(on ? Color.white : .secondary)
                        .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.fill.tertiary), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ScheduleEdits.dayNames[d])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: days)
        .frame(maxWidth: .infinity)
    }
}

extension Date {
    var timeText: String { TimeText.time(self) }
}
