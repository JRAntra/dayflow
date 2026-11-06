import DayFlowCore
import SwiftUI

/// The first time DayFlow opens: what it does, then notifications. Your schedule starts empty;
/// Today and Schedule offer "Add a sample day".
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    enum Step { case welcome, reminders }

    @State private var step: Step = .welcome
    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.accent.opacity(0.18), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcome
                case .reminders: reminders
                }
            }
            .padding(24)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.smooth, value: step)
    }

    var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("WelcomeIcon")
                .resizable().scaledToFit().frame(width: 112, height: 112)
                .clipShape(.rect(cornerRadius: 26))
                .shadow(color: Palette.accent.opacity(0.35), radius: 20, y: 10)
            Text("DayFlow").font(.largeTitle.weight(.bold))
            Text("Plan your week once: blocks for the phases of your day, and events for the things that happen at one moment. DayFlow reminds you as each block starts, nears its end and finishes, and rings for each event.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            primary("Get started") { step = .reminders }
        }
    }

    var reminders: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64)).foregroundStyle(Palette.sun, Palette.accent)
                .symbolEffect(.bounce, value: step)
            Text("Reminders").font(.largeTitle.weight(.bold))
            Text("DayFlow plays your chosen sound at each reminder. It follows your silent switch and Focus, so it stays quiet when your iPhone does, except for events, which ring like alarms.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            primary(busy ? "Setting up…" : "Turn on notifications") {
                Task {
                    busy = true
                    await model.requestNotifications()
                    await finish()
                }
            }
            Button("Not now") { Task { busy = true; await finish() } }
                .foregroundStyle(.secondary)
        }
    }

    func finish() async {
        await model.finishWelcome()
        busy = false
    }

    func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .disabled(busy)
    }
}
