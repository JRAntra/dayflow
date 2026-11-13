import Foundation
import Testing
@testable import DayFlowCore

/// Fade in: 15 seconds, low for most of it, smooth all the way.
@Suite struct FadeInTests {
    @Test func startsQuietAndEndsFull() {
        #expect(abs(FadeIn.gain(at: 0) - 0.1) < 0.0001)
        #expect(FadeIn.gain(at: 15) == 1)
        #expect(FadeIn.gain(at: 40) == 1)
        #expect(FadeIn.gain(at: -1) == FadeIn.gain(at: 0))
    }

    @Test func staysLowForTheFirstTenSeconds() {
        #expect(FadeIn.gain(at: 5) < 0.15)
        #expect(FadeIn.gain(at: 10) < 0.6)
        #expect(FadeIn.gain(at: 12.5) > 0.7)
    }

    @Test func risesSmoothlyWithNoJumps() {
        var last = FadeIn.gain(at: 0)
        for i in 1...1500 {
            let g = FadeIn.gain(at: Double(i) / 100)
            #expect(g >= last)
            #expect(g - last < 0.002) // no step bigger than 0.2% of your volume in 10 ms
            last = g
        }
    }

    @Test func aShorterLengthSqueezesTheCurve() {
        #expect(FadeIn.gain(at: 5, over: 7.5) == FadeIn.gain(at: 10))
    }

    @Test func shortSoundsPlayUntilTheFadeIsDone() {
        #expect(FadeIn.plays(4.05) == 4)   // Alert bells echo: 16.2 seconds
        #expect(FadeIn.plays(7.58) == 2)   // Flute notification: 15.2 seconds
        #expect(FadeIn.plays(8.96) == 2)   // Class bell
        #expect(FadeIn.plays(5) == 3)      // exactly 15
        #expect(FadeIn.plays(15) == 1)
        #expect(FadeIn.plays(28) == 1)
        #expect(FadeIn.plays(0) == 1)
        // Every repeated sound stays under iOS's 30-second limit for notification sounds.
        for d in stride(from: 0.5, to: 15, by: 0.01) { #expect(Double(FadeIn.plays(d)) * d < 30) }
    }
}
