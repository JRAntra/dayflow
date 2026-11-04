import AVFoundation
import DayFlowCore
import SwiftUI
import os

/// Records a clip with the microphone: up to 30 seconds, the quiet start and end trimmed off,
/// heard back before you keep it.
@MainActor
@Observable
final class ClipRecorder: NSObject, AVAudioRecorderDelegate {
    enum Phase { case ready, recording, recorded, denied }
    private(set) var phase: Phase = .ready
    /// The last recording came out empty (the microphone gave nothing).
    private(set) var cameOutEmpty = false
    private(set) var elapsed: Double = 0
    /// 0 to 1, for the level meter.
    private(set) var level: Double = 0
    private(set) var playing = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let raw = AudioEdit.tempURL()
    @ObservationIgnored private var processed: [Bool: URL] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.jrantra.dayflow", category: "recorder")

    func start() async {
        stopPlaying()
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else { phase = .denied; return }
        do {
            // Off the main thread: switching the audio session can take a moment. Right after
            // the microphone prompt it can fail once, so it's tried again after a moment.
            let activate = {
                try await Task.detached {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                }.value
            }
            do { try await activate() } catch {
                log.info("Audio session didn't start, trying again: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: .milliseconds(400))
                try await activate()
            }
            let r = try AVAudioRecorder(url: raw, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            r.delegate = self
            r.isMeteringEnabled = true
            processed = [:]
            if !r.record(forDuration: Specs.maxClipSeconds) {
                try await Task.sleep(for: .milliseconds(400))
                guard r.record(forDuration: Specs.maxClipSeconds) else { throw DataError("Recording didn't start.") }
            }
            recorder = r
            phase = .recording
            elapsed = 0
            // Ten readings a second, drawn without animation: a meter that animates non-stop
            // keeps the app from ever settling (VoiceOver and UI tests wait for that).
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            log.error("Recording didn't start: \(error.localizedDescription, privacy: .public)")
            phase = .ready
        }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        elapsed = r.currentTime
        level = max(0, min(1, (Double(r.averagePower(forChannel: 0)) + 50) / 50))
    }

    func stop() {
        recorder?.stop()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        log.info("Recording finished: \(AudioEdit.seconds(self.raw) ?? -1, privacy: .public) s")
        timer?.invalidate()
        timer = nil
        level = 0
        let ok = AudioEdit.seconds(raw).map { $0 > 0.2 } == true
        cameOutEmpty = !ok
        phase = ok ? .recorded : .ready
    }

    /// The recording as it will be saved: trimmed unless you keep the silence.
    func file(keepSilence: Bool) -> URL? {
        if let url = processed[keepSilence] { return url }
        guard phase == .recorded else { return nil }
        if keepSilence { processed[true] = raw; return raw }
        guard let buffer = try? AudioEdit.read(raw) else { return raw }
        let out = AudioEdit.tempURL()
        guard (try? AudioEdit.writeM4A(buffer, range: AudioEdit.soundRange(buffer), fadeOut: 0.05, to: out)) != nil else { return raw }
        processed[false] = out
        return out
    }

    func play(keepSilence: Bool) {
        stopPlaying()
        guard let url = file(keepSilence: keepSilence) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        playing = player != nil
        let length = player?.duration ?? 0
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(length))
            self?.playing = false
        }
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        playing = false
    }

    func discard() {
        stopPlaying()
        recorder?.stop()
        recorder?.deleteRecording()
        timer?.invalidate()
        for url in Set(processed.values) where url != raw { try? FileManager.default.removeItem(at: url) }
    }
}

struct RecorderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rec = ClipRecorder()
    @State private var keepSilence = false
    @State private var name = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)
                Text(TimeText.countdown(rec.phase == .recording ? rec.elapsed : (rec.file(keepSilence: keepSilence).flatMap(AudioEdit.seconds) ?? 0)))
                    .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                LevelMeter(level: rec.level, active: rec.phase == .recording)
                    .frame(height: 36)
                    .padding(.horizontal, 40)
                recordButton
                if rec.phase == .recorded {
                    HStack(spacing: 16) {
                        Button { rec.playing ? rec.stopPlaying() : rec.play(keepSilence: keepSilence) } label: {
                            Label(rec.playing ? "Stop" : "Play", systemImage: rec.playing ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)
                        Button { Task { await rec.start() } } label: { Label("Record again", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.bordered)
                    }
                    Form {
                        TextField("Name", text: $name)
                        Toggle("Keep the silence", isOn: $keepSilence)
                    }
                    .scrollDisabled(true)
                    .frame(height: 140)
                }
                if let saveError { Text(saveError).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("Record a clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rec.discard(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url = rec.file(keepSilence: keepSilence) else { return }
                        do {
                            try model.saveRecording(url, name: name)
                            rec.discard()
                            dismiss()
                        } catch { saveError = (error as? DataError)?.message ?? error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                    .disabled(rec.phase != .recorded || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = nextName }
            #if DEBUG
            // UI tests: `-uiTestAutoRecord` records two seconds by itself. (UI tests can't read
            // the screen while the level meter is live.)
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-uiTestAutoRecord") else { return }
                await rec.start()
                // Until two seconds have actually been recorded (the Simulator's audio can be
                // slow to start), or ten seconds have passed.
                for _ in 0..<100 where rec.phase != .recording || rec.elapsed < 2 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                rec.stop()
            }
            #endif
        }
        .interactiveDismissDisabled(rec.phase != .ready)
    }

    var caption: String {
        switch rec.phase {
        case .ready: rec.cameOutEmpty ? "Nothing was recorded. Check that your microphone isn't muted, then try again." : "Tap to record. Recording stops by itself at 30 seconds."
        case .recording: "Recording… Tap to stop."
        case .recorded: keepSilence ? "Kept as recorded." : "The quiet start and end are trimmed off."
        case .denied: "DayFlow needs the microphone to record. Allow it in Settings › Privacy & Security › Microphone."
        }
    }

    @ViewBuilder var recordButton: some View {
        if rec.phase == .denied {
            Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
        } else {
            Button {
                if rec.phase == .recording { rec.stop() } else { Task { await rec.start() } }
            } label: {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.4), lineWidth: 4).frame(width: 84, height: 84)
                    RoundedRectangle(cornerRadius: rec.phase == .recording ? 8 : 34)
                        .fill(.red)
                        .frame(width: rec.phase == .recording ? 34 : 68, height: rec.phase == .recording ? 34 : 68)
                }
                .animation(.snappy, value: rec.phase)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rec.phase == .recording ? "Stop recording" : "Record")
            .sensoryFeedback(.impact, trigger: rec.phase)
        }
    }

    /// "Recording 1", "Recording 2"… whichever isn't taken.
    var nextName: String {
        let taken = Set(model.clips.map { $0.name.lowercased() })
        var n = 1
        while taken.contains("recording \(n)") { n += 1 }
        return "Recording \(n)"
    }
}

/// Bars that rise with the microphone level.
struct LevelMeter: View {
    let level: Double
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let bars = 24
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let lit = active && Double(i) / Double(bars) < level
                    Capsule().fill(lit ? (i > bars * 3 / 4 ? Palette.sun : Palette.accent) : Color.secondary.opacity(0.2))
                        .frame(width: max(2, (geo.size.width - CGFloat(bars - 1) * 3) / CGFloat(bars)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Choose 30 seconds of a long sound: where the piece starts, a preview, and Fade in.
struct PieceSheet: View {
    @Environment(AppModel.self) private var model
    let request: PieceRequest
    @State private var start: Double = 0
    @State private var fadeIn = false
    @State private var player: AVAudioPlayer?
    @State private var stopTask: Task<Void, Never>?
    @State private var saveError: String?

    var maxStart: Double { max(0, request.seconds - Specs.maxClipSeconds) }
    var end: Double { min(request.seconds, start + Specs.maxClipSeconds) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(request.name, value: "\(TimeText.countdown(request.seconds)) long")
                } footer: {
                    Text("Clips play for up to 30 seconds. Choose which 30 seconds to use.")
                }
                Section("The piece") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(TimeText.countdown(start)) – \(TimeText.countdown(end))").monospacedDigit().font(.headline)
                            Spacer()
                            Button { player == nil ? play() : stop() } label: {
                                Label(player == nil ? "Play" : "Stop", systemImage: player == nil ? "play.fill" : "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        Slider(value: $start, in: 0...max(maxStart, 0.001), step: 0.5) { editing in
                            if !editing && player != nil { play() }
                        }
                        .disabled(maxStart == 0)
                        .accessibilityLabel("Start of the piece")
                        .accessibilityValue(TimeText.countdown(start))
                    }
                    Toggle(isOn: $fadeIn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fade in")
                            Text("Starts quiet and grows to full volume").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let saveError {
                    Section { Text(saveError).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                } footer: {
                    Text(request.inFolder ? "The piece is saved as \"\(request.name) (clip)\". The full song moves to Clips › Originals." : "The piece is saved as \"\(request.name) (clip)\". Your original file isn't changed.")
                }
            }
            .navigationTitle("Choose 30 seconds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stop()
                        if !request.inFolder { try? FileManager.default.removeItem(at: request.url) }
                        model.pieceRequest = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        stop()
                        do { try model.savePiece(request, start: start, fadeIn: fadeIn) } catch {
                            saveError = (error as? DataError)?.message ?? error.localizedDescription
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled()
        .onDisappear { stop() }
    }

    func play() {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: request.url) else { return }
        p.currentTime = start
        p.play()
        player = p
        let length = end - start
        stopTask = Task {
            try? await Task.sleep(for: .seconds(length))
            if !Task.isCancelled { stop() }
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
    }
}
