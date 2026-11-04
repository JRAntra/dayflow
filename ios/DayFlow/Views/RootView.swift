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
        #if DEBUG
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
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
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
