import XCTest
@testable import MXAudioDSP

/// Week 69 — GarageBand / CapCut pitch-correction lite.
final class MXPitchCorrectTests: XCTestCase {

    private let sampleRate: Double = 48_000
    private let a4: Double = 440

    // MARK: - Math

    func testFrequencyMidiRoundTrip() {
        let midi = MXPitchCorrect.frequencyToMidi(a4, referenceA4: a4)
        XCTAssertEqual(midi, 69, accuracy: 1e-9)
        let back = MXPitchCorrect.midiToFrequency(69, referenceA4: a4)
        XCTAssertEqual(back, a4, accuracy: 1e-9)
    }

    func testSnapMidiChromatic() {
        XCTAssertEqual(MXPitchCorrect.snapMidi(60.4), 60)
        XCTAssertEqual(MXPitchCorrect.snapMidi(60.6), 61)
    }

    func testSnapMidiLimitToKeyCMajor() {
        // Pitch classes for C major: 0,2,4,5,7,9,11
        let cMajor: Set<UInt8> = [0, 2, 4, 5, 7, 9, 11]
        // 61 = C# — nearest in C major is C (60) or D (62); ties prefer lower → 60
        let snapped = MXPitchCorrect.snapMidi(61, pitchClasses: cMajor)
        XCTAssertTrue(snapped == 60 || snapped == 62)
        XCTAssertEqual(MXPitchCorrect.snapMidi(60.2, pitchClasses: cMajor), 60)
    }

    func testCorrectionRatioBlends() {
        XCTAssertEqual(
            MXPitchCorrect.correctionRatio(detectedHz: 400, targetHz: 440, amount: 0),
            1,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            MXPitchCorrect.correctionRatio(detectedHz: 400, targetHz: 440, amount: 1),
            440.0 / 400.0,
            accuracy: 1e-9
        )
        let half = MXPitchCorrect.correctionRatio(detectedHz: 400, targetHz: 440, amount: 0.5)
        XCTAssertEqual(half, 1.0 + (440.0 / 400.0 - 1.0) * 0.5, accuracy: 1e-9)
    }

    // MARK: - Detect

    func testDetectFrequencyNearA4() {
        let tone = makeTone(hz: 440, seconds: 0.25)
        let detected = MXPitchCorrect.detectFrequency(mono: tone, sampleRate: sampleRate)
        XCTAssertNotNil(detected)
        // Autocorrelation lag quantization → allow ~2% error.
        XCTAssertEqual(detected!, 440, accuracy: 12)
    }

    func testDetectSilenceReturnsNil() {
        let silence = [Float](repeating: 0, count: 4096)
        XCTAssertNil(MXPitchCorrect.detectFrequency(mono: silence, sampleRate: sampleRate))
    }

    // MARK: - Correct

    func testAmountZeroIsIdentity() {
        let tone = makeTone(hz: 430, seconds: 0.2)
        let out = MXPitchCorrect.correct(mono: tone, sampleRate: sampleRate, amount: 0)
        XCTAssertEqual(out.count, tone.count)
        for i in tone.indices {
            XCTAssertEqual(out[i], tone[i], accuracy: 1e-7)
        }
    }

    func testCorrectPullsFlatToneTowardChromatic() {
        // ~A4 − 35 cents ≈ 431.2 Hz; chromatic target is 440.
        let flatA = a4 * pow(2.0, -35.0 / 1200.0)
        let tone = makeTone(hz: flatA, seconds: 0.35)
        let before = MXPitchCorrect.detectFrequency(mono: tone, sampleRate: sampleRate)
        XCTAssertNotNil(before)

        let corrected = MXPitchCorrect.correct(
            mono: tone,
            sampleRate: sampleRate,
            amount: 1,
            pitchClasses: nil
        )
        XCTAssertEqual(corrected.count, tone.count)
        let after = MXPitchCorrect.detectFrequency(mono: corrected, sampleRate: sampleRate)
        XCTAssertNotNil(after)

        let beforeCents = abs(1200 * log2(before! / a4))
        let afterCents = abs(1200 * log2(after! / a4))
        XCTAssertLessThan(
            afterCents,
            beforeCents - 5,
            "expected correction to reduce cents error (before \(beforeCents), after \(afterCents))"
        )
        XCTAssertLessThan(afterCents, 25, "fully corrected tone should land near A4")
    }

    func testEmptyAndShortBuffersSafe() {
        XCTAssertEqual(MXPitchCorrect.correct(mono: [], sampleRate: sampleRate, amount: 1), [])
        let short = makeTone(hz: 220, seconds: 0.01)
        let out = MXPitchCorrect.correct(mono: short, sampleRate: sampleRate, amount: 0.8)
        XCTAssertEqual(out.count, short.count)
    }

    // MARK: - Fixtures

    private func makeTone(hz: Double, seconds: Double, amplitude: Float = 0.4) -> [Float] {
        let n = Int((seconds * sampleRate).rounded())
        var samples = [Float](repeating: 0, count: max(n, 1))
        let twoPi = 2.0 * Double.pi
        for i in 0..<samples.count {
            samples[i] = amplitude * Float(sin(twoPi * hz * Double(i) / sampleRate))
        }
        return samples
    }
}
