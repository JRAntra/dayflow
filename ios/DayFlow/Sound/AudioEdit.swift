import AVFoundation
import DayFlowCore
import Foundation

/// Cutting and saving clips: the recorder's silence trim and the 30-second piece of a song.
/// Clips are saved as m4a (AAC), which is small and plays on both the iPhone and the Mac.
enum AudioEdit {
    /// How long a file is, or nil if the system can't read it.
    static func seconds(_ url: URL) -> Double? {
        guard let f = try? AVAudioFile(forReading: url), f.processingFormat.sampleRate > 0 else { return nil }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    static func inspect(_ url: URL) -> DataStore.Inspection {
        seconds(url).map { .plays(seconds: $0) } ?? .unplayable
    }

    /// Reads `duration` seconds from `start` (the whole file if nil).
    static func read(_ url: URL, from start: Double = 0, duration: Double? = nil) throws -> AVAudioPCMBuffer {
        let f = try AVAudioFile(forReading: url)
        let rate = f.processingFormat.sampleRate
        let first = AVAudioFramePosition(max(0, start) * rate)
        let available = max(0, f.length - first)
        let count = AVAudioFrameCount(min(Double(available), (duration ?? Double(available) / rate) * rate))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: count) else {
            throw DataError("That part of the file is empty.")
        }
        f.framePosition = first
        try f.read(into: buffer, frameCount: count)
        return buffer
    }

    /// The frames between the first and last moment louder than the background, with a little
    /// room either side: the quiet before you start and after you stop is cut off.
    static func soundRange(_ b: AVAudioPCMBuffer) -> Range<Int> {
        let n = Int(b.frameLength)
        guard n > 0, let ch = b.floatChannelData else { return 0..<n }
        let channels = Int(b.format.channelCount)
        func level(_ i: Int) -> Float { (0..<channels).map { abs(ch[$0][i]) }.max() ?? 0 }
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, level(i)) }
        let threshold = max(0.01, peak * 0.08)
        guard let first = (0..<n).first(where: { level($0) > threshold }),
              let last = (0..<n).last(where: { level($0) > threshold }) else { return 0..<n }
        let rate = b.format.sampleRate
        return max(0, first - Int(0.05 * rate)) ..< min(n, last + Int(0.25 * rate))
    }

    /// Writes frames of a buffer as an m4a, with an optional fade in (DayFlow's `FadeIn`, over
    /// its first 15 seconds or the whole piece if it's shorter) and a short fade out so a cut doesn't click.
    static func writeM4A(_ b: AVAudioPCMBuffer, range: Range<Int>? = nil, fadeIn: Bool = false, fadeOut: Double = 0, to url: URL) throws {
        let r = range ?? 0..<Int(b.frameLength)
        let format = b.format
        guard r.count > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(r.count)),
              let src = b.floatChannelData, let dst = out.floatChannelData else { throw DataError("There's nothing to save.") }
        out.frameLength = AVAudioFrameCount(r.count)
        let rate = format.sampleRate
        let inSeconds = min(Double(r.count) / rate, FadeIn.seconds)
        let outFrames = Int(fadeOut * rate)
        for c in 0..<Int(format.channelCount) {
            for i in 0..<r.count {
                var g: Float = 1
                if fadeIn { g *= FadeIn.gain(at: Double(i) / rate, over: inSeconds) }
                if outFrames > 0 && i >= r.count - outFrames { g *= Float(r.count - i) / Float(outFrames) }
                dst[c][i] = src[c][r.lowerBound + i] * g
            }
        }
        try? FileManager.default.removeItem(at: url)
        defer { if (try? AVAudioFile(forReading: url)) == nil { try? FileManager.default.removeItem(at: url) } }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: format.channelCount,
            // A quality rather than a bit rate: the encoder turns down bit rates it can't do at
            // low sample rates (96 kbps at 22 kHz mono, say).
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: out)
        }
    }

    /// A temporary file for a clip being made.
    static func tempURL(_ ext: String = "m4a") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).\(ext)")
    }
}
