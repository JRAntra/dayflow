import Foundation

/// Fade in: a reminder's sound starts at 10% of your volume, stays low for most of the fade and
/// rises smoothly to full at 15 seconds (it's under 50% at 10 seconds). A sound shorter than the
/// fade plays again and again until the fade is done, so it always gets the whole 15 seconds.
/// The Mac's `fadeGain` (renderer.js) is the same curve.
public enum FadeIn {
    public static let seconds = 15.0
    public static let start = 0.1

    /// How loud the sound is `t` seconds in, from 0.1 to 1, as a share of your volume. The curve
    /// is a smoothstep of (t/length)², so it starts and ends gently with no jump in between.
    public static func gain(at t: Double, over length: Double = seconds) -> Float {
        let x = length > 0 ? min(max(t / length, 0), 1) : 1
        let u = x * x
        return Float(start + (1 - start) * u * u * (3 - 2 * u))
    }

    /// How many times a sound this long plays back to back so the fade can finish: enough to
    /// reach 15 seconds, and once for a sound that's already that long.
    public static func plays(_ duration: Double) -> Int {
        guard duration > 0, duration < seconds else { return 1 }
        return Int((seconds / duration).rounded(.up))
    }
}
