import XCTest
@testable import MXAudioDSP

/// Week 70 — Ableton / BandLab time-stretch lite.
final class MXTimeStretchTests: XCTestCase {

    private let sampleRate: Double = 48_000

    // MARK: - Stretch

    func testIdentityFactorReturnsSameSamples() {
        let tone = makeTone(hz: 440, seconds: 0.3)
        let out = MXTimeStretch.stretch(mono: tone, sampleRate: sampleRate, factor: 1.0)
        XCTAssertEqual(out.count, tone.count)
        for i in tone.indices {
            XCTAssertEqual(out[i], tone[i], accuracy: 1e-7)
        }

        // Near-identity (±1e-4) also copies.
        let near = MXTimeStretch.stretch(mono: tone, sampleRate: sampleRate, factor: 1.0 + 5e-5)
        XCTAssertEqual(near.count, tone.count)
        XCTAssertEqual(near[0], tone[0], accuracy: 1e-7)
    }

    func testFactor1_5ProducesLongerOutput() {
        let tone = makeTone(hz: 440, seconds: 0.3)
        let out = MXTimeStretch.stretch(mono: tone, sampleRate: sampleRate, factor: 1.5)
        let expected = MXTimeStretch.outputFrameCount(inputFrames: tone.count, factor: 1.5)
        XCTAssertEqual(out.count, expected)
        // ~1.5× length ±5%.
        let ratio = Double(out.count) / Double(tone.count)
        XCTAssertEqual(ratio, 1.5, accuracy: 0.075)
    }

    func testFactor0_75ProducesShorterOutput() {
        let tone = makeTone(hz: 440, seconds: 0.3)
        let out = MXTimeStretch.stretch(mono: tone, sampleRate: sampleRate, factor: 0.75)
        let expected = MXTimeStretch.outputFrameCount(inputFrames: tone.count, factor: 0.75)
        XCTAssertEqual(out.count, expected)
        XCTAssertLessThan(out.count, tone.count)
        let ratio = Double(out.count) / Double(tone.count)
        XCTAssertEqual(ratio, 0.75, accuracy: 0.05)
    }

    func testEmptySafe() {
        XCTAssertEqual(
            MXTimeStretch.stretch(mono: [], sampleRate: sampleRate, factor: 1.5),
            []
        )
        XCTAssertEqual(MXTimeStretch.outputFrameCount(inputFrames: 0, factor: 1.5), 0)
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
