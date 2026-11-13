import AVFoundation
import CryptoKit
import DayFlowCore
import Foundation

/// Turns DayFlow's clips into notification sounds.
///
/// iOS plays a notification's sound itself, at the ringer volume, from start to end, so DayFlow
/// can't turn it down or fade it in while it plays. Instead each sound is written out once with
/// your volume and Fade in already applied, as a CAF file in Library/Sounds, where notifications
/// look for sounds. The fade is the Mac's (`FadeIn`): 15 seconds, low for most of it, with a
/// sound shorter than that written out several times back to back so the fade can finish. The
/// volume is squared so the slider feels even.
enum SoundLibrary {
    /// Library/Sounds: the folder notifications read custom sounds from.
    static var soundsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds", isDirectory: true)
    }

    /// The original audio for a sound id: a built-in in the app bundle, or one of your clips.
    static func sourceURL(_ soundId: String, store: DataStore) -> URL? {
        if Specs.builtinIds.contains(soundId) {
            return Bundle.main.url(forResource: soundId, withExtension: "mp3", subdirectory: "sounds")
        }
        if let clip = store.clips.first(where: { $0.soundId == soundId }) {
            let url = store.clipURL(clip)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    /// The file name of a rendered sound, e.g. "df-1a2b3c4d5e6f7a8b.caf".
    static func fileName(_ soundId: String, fade: Bool, volume: Int) -> String {
        let key = "\(soundId)|\(fade ? "fade" : "flat")|\(volume)|v3"
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "df-\(hash).caf"
    }

    /// Makes sure the rendered sound exists and returns its file name, or nil if the clip
    /// can't be read (it's then left to the caller to fall back to the starting sound).
    @discardableResult
    static func prepare(_ soundId: String, fade: Bool, volume: Int, store: DataStore) -> String? {
        let name = fileName(soundId, fade: fade, volume: volume)
        let out = soundsDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: out.path) { return name }
        guard let src = sourceURL(soundId, store: store) else { return nil }
        do {
            try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
            try render(src, to: out, gain: level(volume), fade: fade)
            return name
        } catch {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
    }

    static func level(_ volume: Int) -> Float { pow(Float(min(max(volume, 0), 100)) / 100, 2) }

    /// Deletes rendered sounds that no scheduled reminder uses any more.
    static func removeUnused(keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: soundsDir.path)) ?? []
        for f in files where f.hasPrefix("df-") && !names.contains(f) {
            try? FileManager.default.removeItem(at: soundsDir.appendingPathComponent(f))
        }
    }

    /// Reads the clip (up to 30 seconds), repeats it until the fade is done if Fade in is on,
    /// applies the gain and fade, and writes 16-bit PCM.
    static func render(_ src: URL, to out: URL, gain: Float, fade: Bool) throws {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let maxFrames = AVAudioFrameCount(min(Double(input.length), Specs.maxClipSeconds * format.sampleRate))
        guard maxFrames > 0, let one = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else {
            throw DataError("That clip is empty.")
        }
        try input.read(into: one, frameCount: maxFrames)
        let length = Int(one.frameLength)
        let plays = fade ? FadeIn.plays(Double(length) / format.sampleRate) : 1
        guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length * plays)) else {
            throw DataError("That clip is empty.")
        }
        buffer.frameLength = AVAudioFrameCount(length * plays)
        if let from = one.floatChannelData, let channels = buffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                let data = channels[ch]
                for i in 0..<(length * plays) {
                    var g = gain
                    if fade { g *= FadeIn.gain(at: Double(i) / format.sampleRate) }
                    data[i] = from[ch][i % length] * g
                }
            }
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let temp = out.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).caf")
        do {
            let file = try AVAudioFile(forWriting: temp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: temp, to: out)
    }

    /// Checks a clip will play and isn't too long before DayFlow keeps it, like the Mac does.
    static func check(_ data: Data, name: String, ext: String) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: temp) } catch {
            throw DataError("DayFlow can't play \"\(name)\". Try converting it to mp3 or wav.")
        }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        if seconds > Specs.maxClipSeconds + 0.5 {
            throw DataError("\"\(name)\" is \(Int(seconds.rounded())) seconds long. Clips can be up to \(Int(Specs.maxClipSeconds)) seconds.")
        }
    }
}
