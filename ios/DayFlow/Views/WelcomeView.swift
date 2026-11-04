import DayFlowCore
import SwiftUI

/// The first time DayFlow opens: what it does, how to start your schedule, and notifications.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    enum Step { case welcome, schedule, reminders }
    enum Start { case sample, empty, file }

    @State private var step: Step = .welcome
    @State private var start: Start = .sample
    @State private var importing = false
    @State private var preview: ImportPreview?
    @State private var applySettings = true
    @State private var busy = false
    @State private var showPreview = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.accent.opacity(0.18), Color(.systemBackground)], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcome
                case .schedule: schedule
                case .reminders: reminders
                }
            }
            .padding(24)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.smooth, value: step)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do { preview = try model.readImport(url); start = .file; showPreview = true } catch { model.showError(error) }
            case .failure(let error): model.showError(error)
            }
        }
        .sheet(isPresented: $showPreview) {
            if let preview {
                ImportPreviewSheet(preview: preview, replaceTitle: "Use this") { apply in
                    applySettings = apply
                    step = .reminders
                }
            }
        }
    }

    var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("WelcomeIcon")
                .resizable().scaledToFit().frame(width: 112, height: 112)
                .clipShape(.rect(cornerRadius: 26))
                .shadow(color: Palette.accent.opacity(0.35), radius: 20, y: 10)
            Text("DayFlow").font(.largeTitle.weight(.bold))
            Text("Plan the phases of your day once, and DayFlow reminds you as each one starts, nears its end and finishes, with the sound you choose for each kind of block.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            primary("Get started") { step = .schedule }
        }
    }

    var schedule: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your schedule").font(.largeTitle.weight(.bold)).padding(.top, 40)
            Text("You can change everything later in Schedule.").foregroundStyle(.secondary)
            choice(.sample, "Start with the sample weekday", "Eight blocks from 9:00 to 5:15, Monday to Friday, like the Mac app's.", "sun.horizon")
            choice(.file, preview.map { "Import \($0.fileName)" } ?? "Import from a file…",
                   preview.map { "\($0.blocks.count) blocks" } ?? "An export from DayFlow on your Mac, AirDropped or saved to Files.", "square.and.arrow.down")
            choice(.empty, "Start empty", "Add your own blocks with ＋.", "square.dashed")
            Spacer()
            primary("Continue") {
                if start == .file && preview == nil { importing = true } else { step = .reminders }
            }
        }
    }

    var reminders: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 64)).foregroundStyle(Palette.sun, Palette.accent)
                .symbolEffect(.bounce, value: step)
            Text("Reminders").font(.largeTitle.weight(.bold))
            Text("DayFlow plays your chosen sound at each reminder. It follows your silent switch and Focus, so it stays quiet when your iPhone does.")
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
        switch start {
        case .sample: await model.finishWelcome(sample: true)
        case .empty: await model.finishWelcome(sample: false)
        case .file:
            if let preview { await model.finishWelcome(sample: false, importing: (preview, applySettings)) }
            else { await model.finishWelcome(sample: true) }
        }
        busy = false
    }

    func choice(_ value: Start, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button {
            start = value
            if value == .file && preview == nil { importing = true }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(Palette.accent).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: start == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(start == value ? Palette.accent : Color.secondary.opacity(0.5))
            }
            .padding(16)
            .background(.background, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(start == value ? Palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: start)
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
