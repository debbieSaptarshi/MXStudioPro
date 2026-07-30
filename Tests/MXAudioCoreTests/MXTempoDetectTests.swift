import XCTest
@testable import MXAudioDSP

/// Synthetic click-train checks for import tempo-detect lite (Week 48).
final class MXTempoDetectTests: XCTestCase {

    private let sampleRate: Double = 44_100

    func testClickTrain120BPM() {
        let mono = makeClickTrain(bpm: 120, seconds: 6)
        let bpm = MXTempoDetect.estimateBPM(mono: mono, sampleRate: sampleRate)
        XCTAssertNotNil(bpm)
        XCTAssertEqual(bpm!, 120, accuracy: 2)
    }

    func testClickTrain90BPM() {
        let mono = makeClickTrain(bpm: 90, seconds: 8)
        let bpm = MXTempoDetect.estimateBPM(mono: mono, sampleRate: sampleRate)
        XCTAssertNotNil(bpm)
        XCTAssertEqual(bpm!, 90, accuracy: 2)
    }

    func testClickTrain140BPM() {
        let mono = makeClickTrain(bpm: 140, seconds: 6)
        let estimate = MXTempoDetect.estimate(mono: mono, sampleRate: sampleRate)
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate!.bpm, 140, accuracy: 2)
        XCTAssertGreaterThanOrEqual(estimate!.confidence, MXTempoDetect.defaultMinConfidence)
    }

    func testSilenceReturnsNil() {
        let mono = [Float](repeating: 0, count: Int(6 * sampleRate))
        XCTAssertNil(MXTempoDetect.estimateBPM(mono: mono, sampleRate: sampleRate))
        XCTAssertNil(MXTempoDetect.estimate(mono: mono, sampleRate: sampleRate))
    }

    func testEmptyAndBadSampleRateReturnNil() {
        XCTAssertNil(MXTempoDetect.estimateBPM(mono: [], sampleRate: sampleRate))
        XCTAssertNil(MXTempoDetect.estimateBPM(mono: [0.1, 0.2], sampleRate: 0))
        XCTAssertNil(MXTempoDetect.estimateBPM(mono: [0.1, 0.2], sampleRate: -1))
    }

    func testTooShortReturnsNil() {
        let mono = makeClickTrain(bpm: 120, seconds: 1.0)
        XCTAssertNil(MXTempoDetect.estimateBPM(mono: mono, sampleRate: sampleRate))
    }

    func testEstimateRespectsRequestedBPMRange() {
        // 75 BPM fundamental sits below minBPM=100; no in-range period → nil.
        let mono = makeClickTrain(bpm: 75, seconds: 8)
        let bpm = MXTempoDetect.estimateBPM(
            mono: mono,
            sampleRate: sampleRate,
            minBPM: 100,
            maxBPM: 200
        )
        XCTAssertNil(bpm)
    }

    // MARK: - Fixtures

    /// Exponential-decay impulses at a fixed BPM (one hit per beat).
    private func makeClickTrain(bpm: Double, seconds: Double, amplitude: Float = 1) -> [Float] {
        let n = Int(seconds * sampleRate)
        var samples = [Float](repeating: 0, count: n)
        let periodFrames = sampleRate * 60.0 / bpm
        var t = 0.0
        let clickLen = 48
        while t < Double(n) {
            let start = Int(t.rounded())
            guard start < n else { break }
            for k in 0..<min(clickLen, n - start) {
                samples[start + k] = amplitude * exp(-Float(k) / 10)
            }
            t += periodFrames
        }
        return samples
    }
}
