import AVFoundation
import DayFlowCore
import Foundation

/// Plays sound previews. A preview plays the same file the notification will use, with your
/// volume and Fade in, so it sounds the way the reminder will. Previews play even when the
/// phone is on silent, because you tapped them on purpose; reminders follow the silent switch.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    func play(_ soundId: String, fade: Bool, volume: Int, store: DataStore, fallback: String? = nil) {
        stop()
        let name = SoundLibrary.prepare(soundId, fade: fade, volume: volume, store: store)
            ?? fallback.flatMap { SoundLibrary.prepare($0, fade: fade, volume: volume, store: store) }
        guard let name else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: SoundLibrary.soundsDir.appendingPathComponent(name))
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
