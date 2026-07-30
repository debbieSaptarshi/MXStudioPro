import XCTest
@testable import MXAudioDSP

/// Week 73 — CapCut / BandLab vocal harmonies lite.
final class MXHarmonyTests: XCTestCase {

    private let sampleRate: Double = 48_000

    func testSemitoneRatioOctave() {
        XCTAssertEqual(MXHarmony.semitoneRatio(12), 2, accuracy: 1e-9)
        XCTAssertEqual(MXHarmony.semitoneRatio(-12), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MXHarmony.semitoneRatio(0), 1, accuracy: 1e-9)
    }

    func testShiftZeroIsIdentity() {
        let tone = makeTone(hz: 440, seconds: 0.2)
        let out = MXHarmony.shift(mono: tone, sampleRate: sampleRate, semitones: 0)
        XCTAssertEqual(out.count, tone.count)
        for i in tone.indices {
            XCTAssertEqual(out[i], tone[i], accuracy: 1e-7)
        }
    }

    func testShiftPreservesLength() {
        let tone = makeTone(hz: 220, seconds: 0.3)
        let up = MXHarmony.shift(mono: tone, sampleRate: sampleRate, semitones: 4)
        let down = MXHarmony.shift(mono: tone, sampleRate: sampleRate, semitones: -5)
        XCTAssertEqual(up.count, tone.count)
        XCTAssertEqual(down.count, tone.count)
    }

    func testShiftRaisesPitchTowardMajorThird() {
        let tone = makeTone(hz: 440, seconds: 0.4)
        let shifted = MXHarmony.shift(mono: tone, sampleRate: sampleRate, semitones: 4)
        let before = MXPitchCorrect.detectFrequency(mono: tone, sampleRate: sampleRate)
        let after = MXPitchCorrect.detectFrequency(mono: shifted, sampleRate: sampleRate)
        XCTAssertNotNil(before)
        XCTAssertNotNil(after)
        // Major third ≈ ×1.26; allow lag quantization slack.
        let expected = 440 * MXHarmony.semitoneRatio(4)
        XCTAssertEqual(after!, expected, accuracy: expected * 0.06)
        XCTAssertGreaterThan(after!, before!)
    }

    func testStackEmptyIntervalsIsDry() {
        let tone = makeTone(hz: 330, seconds: 0.15)
        let out = MXHarmony.stack(
            mono: tone,
            sampleRate: sampleRate,
            intervals: [],
            mix: 1
        )
        XCTAssertEqual(out.count, tone.count)
        for i in tone.indices {
            XCTAssertEqual(out[i], tone[i], accuracy: 1e-7)
        }
    }

    func testStackMixZeroIsDry() {
        let tone = makeTone(hz: 330, seconds: 0.15)
        let out = MXHarmony.stack(
            mono: tone,
            sampleRate: sampleRate,
            intervals: [4, 7],
            mix: 0
        )
        for i in tone.indices {
            XCTAssertEqual(out[i], tone[i], accuracy: 1e-7)
        }
    }

    func testStackAddsEnergyVersusDry() {
        let tone = makeTone(hz: 262, seconds: 0.35)
        let dryEnergy = energy(tone)
        let stacked = MXHarmony.stack(
            mono: tone,
            sampleRate: sampleRate,
            intervals: [4, 7],
            dryGain: 1,
            voiceGain: 0.55,
            mix: 0.7
        )
        XCTAssertEqual(stacked.count, tone.count)
        let stackedEnergy = energy(stacked)
        XCTAssertGreaterThan(stackedEnergy, dryEnergy * 1.05)
        // Soft normalize keeps peak under ~0.95.
        let peak = stacked.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.96)
    }

    func testSilenceSafe() {
        let silence = [Float](repeating: 0, count: 2048)
        let out = MXHarmony.stack(
            mono: silence,
            sampleRate: sampleRate,
            intervals: [4],
            mix: 1
        )
        XCTAssertEqual(out.count, silence.count)
        for s in out {
            XCTAssertEqual(s, 0, accuracy: 1e-6)
        }
    }

    func testEmptyInput() {
        XCTAssertTrue(MXHarmony.shift(mono: [], sampleRate: sampleRate, semitones: 4).isEmpty)
        XCTAssertTrue(
            MXHarmony.stack(mono: [], sampleRate: sampleRate, intervals: [4], mix: 1).isEmpty
        )
    }

    // MARK: - Helpers

    private func makeTone(hz: Double, seconds: Double, amplitude: Float = 0.4) -> [Float] {
        let n = Int((seconds * sampleRate).rounded())
        var out = [Float](repeating: 0, count: n)
        let omega = 2 * Double.pi * hz / sampleRate
        for i in 0..<n {
            out[i] = amplitude * Float(sin(omega * Double(i)))
        }
        return out
    }

    private func energy(_ samples: [Float]) -> Double {
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        return sum
    }
}
