import XCTest
@testable import MXAudioDSP

/// Offline LUFS MVP checks for Reels/TikTok export helpers.
///
/// Tolerance: after `normalizeToLUFS(target: -14)`, measured LUFS should land
/// within ~1.5 LU of −14 for a constant-amplitude tone (mean-square gated
/// estimator without full K-weighting).
final class MXLoudnessTests: XCTestCase {

    private let sampleRate: Double = 48_000
    /// Documented acceptance window for the MVP meter vs target.
    private let lufsTolerance: Float = 1.5

    func testConstantToneIntegratedLUFSIsFinite() {
        let (left, right) = makeStereoTone(amplitude: 0.25, seconds: 3)
        let lufs = MXLoudness.integratedLUFS(left: left, right: right, sampleRate: sampleRate)
        XCTAssertTrue(lufs.isFinite, "expected finite LUFS, got \(lufs)")
        XCTAssertGreaterThan(lufs, -60)
        XCTAssertLessThan(lufs, 0)
    }

    func testNormalizeToLUFSHitsTargetAndCapsPeak() {
        var (left, right) = makeStereoTone(amplitude: 0.35, seconds: 3)

        MXLoudness.normalizeToLUFS(left: &left, right: &right, targetLUFS: -14, maxPeak: 0.99)

        let measured = MXLoudness.integratedLUFS(left: left, right: right, sampleRate: sampleRate)
        XCTAssertTrue(measured.isFinite, "normalized LUFS should be finite")
        XCTAssertEqual(measured, -14, accuracy: lufsTolerance,
                       "expected ~−14 LUFS (±\(lufsTolerance)), got \(measured)")

        let peak = max(MXAudioAnalysis.peak(left), MXAudioAnalysis.peak(right))
        XCTAssertLessThanOrEqual(peak, 1.0 + 1e-4,
                                 "peak should be ≤ ~1.0 after normalize, got \(peak)")
        XCTAssertLessThanOrEqual(peak, 0.99 + 1e-3)
    }

    func testGainToTargetLUFSAndApplyGain() {
        let current: Float = -20
        let target: Float = -14
        let gain = MXLoudness.gainToTargetLUFS(currentLUFS: current, target: target)
        XCTAssertEqual(gain, pow(10, (target - current) / 20), accuracy: 1e-5)

        var left: [Float] = [0.1, -0.2, 0.3]
        var right: [Float] = [0.05, 0.05, 0.05]
        MXLoudness.applyGain(2, left: &left, right: &right)
        XCTAssertEqual(left, [0.2, -0.4, 0.6])
        XCTAssertEqual(right, [0.1, 0.1, 0.1])
    }

    func testApplyMasterLimiterCapsTruePeak() {
        var left: [Float] = [0.5, 1.2, -1.5, 0.99, 2.0]
        var right: [Float] = [0.4, -1.1, 0.8, 1.4, -0.2]
        MXLoudness.applyMasterLimiter(left: &left, right: &right, ceiling: 0.99)
        let peak = max(MXAudioAnalysis.peak(left), MXAudioAnalysis.peak(right))
        XCTAssertLessThanOrEqual(peak, 0.99 + 1e-5)
        // Quiet samples below the knee stay unchanged.
        XCTAssertEqual(left[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(right[0], 0.4, accuracy: 1e-6)
    }

    // MARK: - Fixtures

    private func makeStereoTone(amplitude: Float, seconds: Double, hz: Float = 440) -> ([Float], [Float]) {
        let n = Int(seconds * sampleRate)
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        let twoPiF = 2 * Float.pi * hz / Float(sampleRate)
        for i in 0..<n {
            let sample = amplitude * sin(twoPiF * Float(i))
            left[i] = sample
            right[i] = sample
        }
        return (left, right)
    }
}
