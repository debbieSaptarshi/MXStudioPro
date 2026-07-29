import XCTest
@testable import MXAudioDSP

/// Offline bounce-path FX primitives (HPF / EQ mid / delay / reverb) for Week 30 Slice B.
final class MXBounceFXTests: XCTestCase {

    private let sampleRate: Double = 48_000

    func testHighPassAttenuates50HzVs1kHz() {
        var hpf = MXBiquad()
        hpf.configure(kind: .highpass, frequency: 100, q: 0.707, sampleRate: sampleRate)
        let low = hpf.magnitudeDB(at: 50, sampleRate: sampleRate)
        let high = hpf.magnitudeDB(at: 1_000, sampleRate: sampleRate)
        XCTAssertLessThan(low, high - 6, "50 Hz should be well below 1 kHz (low=\(low), high=\(high))")
        XCTAssertLessThan(low, -6, "expected >6 dB cut at 50 Hz, got \(low)")
        XCTAssertGreaterThan(high, -1.5, "1 kHz should stay near unity, got \(high)")
    }

    func testEQMidBoostRaises1200Hz() {
        var eq = MXBiquad()
        eq.configure(kind: .peaking, frequency: 1_200, q: 1.0, gainDB: 6, sampleRate: sampleRate)
        let mid = eq.magnitudeDB(at: 1_200, sampleRate: sampleRate)
        let side = eq.magnitudeDB(at: 200, sampleRate: sampleRate)
        XCTAssertGreaterThan(mid, 4, "expected ~+6 dB at 1.2 kHz, got \(mid)")
        XCTAssertLessThan(abs(side), 1.5, "far sideband should stay near unity, got \(side)")
    }

    func testDelayWetDiffersFromDryImpulse() {
        let delay = MXDelayLine(maxDelaySeconds: 1.0, sampleRate: sampleRate)
        delay.setDelay(milliseconds: 20)
        delay.feedback = 0.35
        delay.mix = 0.5

        // Impulse then silence — wet path must carry delayed energy.
        var wetEnergy: Float = 0
        var dryEnergy: Float = 0
        let frames = Int(sampleRate * 0.1)
        for i in 0..<frames {
            let input: Float = i == 0 ? 1 : 0
            dryEnergy += input * input
            let out = delay.process(input)
            wetEnergy += out * out
        }
        XCTAssertGreaterThan(wetEnergy, dryEnergy + 0.01, "wet delay should add delayed energy")
        // Also ensure the first sample is not purely dry (mix blends delayed = 0 initially).
        // After the delay time, output should be non-zero from the echo.
        let delay2 = MXDelayLine(maxDelaySeconds: 1.0, sampleRate: sampleRate)
        delay2.setDelay(milliseconds: 10)
        delay2.feedback = 0
        delay2.mix = 1.0
        _ = delay2.process(1)
        var foundEcho = false
        let echoSearch = Int(sampleRate * 0.02)
        for _ in 0..<echoSearch {
            if abs(delay2.process(0)) > 0.1 {
                foundEcho = true
                break
            }
        }
        XCTAssertTrue(foundEcho, "expected delayed impulse when mix=1")
    }

    func testReverbWetIncreasesTailEnergy() {
        let frames = Int(sampleRate * 0.25)
        // Dry: impulse only — energy ≈ 1.
        var dryEnergy: Float = 0
        for i in 0..<frames {
            let s: Float = i == 0 ? 1 : 0
            dryEnergy += s * s
        }

        let reverb = MXSimpleReverb(sampleRate: sampleRate, smallRoom: false)
        reverb.wetDryMix = 100
        var wetEnergy: Float = 0
        for i in 0..<frames {
            let input: Float = i == 0 ? 1 : 0
            let out = reverb.process(input)
            wetEnergy += out * out
        }
        XCTAssertGreaterThan(wetEnergy, dryEnergy * 1.5, "wet reverb should leave a longer/louder tail")

        let small = MXSimpleReverb(sampleRate: sampleRate, smallRoom: true)
        small.wetDryMix = 100
        var smallEnergy: Float = 0
        for i in 0..<frames {
            let input: Float = i == 0 ? 1 : 0
            let out = small.process(input)
            smallEnergy += out * out
        }
        // Small room should still produce a wet tail, but typically less total energy than medium.
        XCTAssertGreaterThan(smallEnergy, dryEnergy, "smallRoom reverb should still wet the impulse")
    }
}
