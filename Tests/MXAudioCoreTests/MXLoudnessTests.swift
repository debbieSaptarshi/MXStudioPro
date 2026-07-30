import XCTest
@testable import MXAudioDSP

/// Offline LUFS checks for Reels/TikTok export helpers (Week 76 K-weighted).
///
/// Tolerance: after `normalizeToLUFS(target: -14)`, measured LUFS should land
/// within ~1.5 LU of −14 for a constant-amplitude tone.
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

    // MARK: - Week 59

    func testMomentaryLUFSFromTone() {
        let (left, right) = makeStereoTone(amplitude: 0.25, seconds: 0.5)
        let lufs = MXLoudness.momentaryLUFS(left: left, right: right, sampleRate: sampleRate)
        XCTAssertTrue(lufs.isFinite)
        XCTAssertGreaterThan(lufs, -60)
        XCTAssertLessThan(lufs, 0)

        let silence = [Float](repeating: 0, count: 2048)
        XCTAssertEqual(
            MXLoudness.momentaryLUFS(left: silence, right: silence, sampleRate: sampleRate),
            -.infinity
        )
    }

    func testLoudnessFromMeanSquareMatchesKnownPoint() {
        // z = 1 → −0.691 LUFS
        XCTAssertEqual(MXLoudness.loudnessFromMeanSquare(1), -0.691, accuracy: 1e-4)
        XCTAssertEqual(MXLoudness.loudnessFromMeanSquare(0), -.infinity)
    }

    // MARK: - Week 71 / 76 report

    func testReportFiniteForTone() {
        let (left, right) = makeStereoTone(amplitude: 0.25, seconds: 3)
        let report = MXLoudness.report(left: left, right: right, sampleRate: sampleRate)
        XCTAssertTrue(report.integratedLUFS.isFinite, "expected finite LUFS, got \(report.integratedLUFS)")
        XCTAssertGreaterThan(report.integratedLUFS, -60)
        XCTAssertLessThan(report.integratedLUFS, 0)
        XCTAssertTrue(report.truePeakDBFS.isFinite)
        XCTAssertLessThan(report.truePeakDBFS, 0)
        XCTAssertEqual(report.sampleRate, sampleRate)
        XCTAssertNil(report.targetLUFS)
        XCTAssertNil(report.headroomLU)

        let samplePeak = max(MXAudioAnalysis.peakDB(left), MXAudioAnalysis.peakDB(right))
        // Inter-sample TP ≥ sample peak.
        XCTAssertGreaterThanOrEqual(report.truePeakDBFS + 1e-4, samplePeak)
    }

    func testReportHeadroomAgainstTarget() {
        let (left, right) = makeStereoTone(amplitude: 0.25, seconds: 3)
        let target: Float = -14
        let report = MXLoudness.report(left: left, right: right, sampleRate: sampleRate, targetLUFS: target)
        XCTAssertEqual(report.targetLUFS, target)
        XCTAssertTrue(report.integratedLUFS.isFinite)
        let headroom = report.headroomLU
        XCTAssertNotNil(headroom)
        XCTAssertEqual(headroom!, target - report.integratedLUFS, accuracy: 1e-5)
    }

    func testReportSilenceNonFiniteLUFS() {
        let silence = [Float](repeating: 0, count: Int(3 * sampleRate))
        let report = MXLoudness.report(left: silence, right: silence, sampleRate: sampleRate, targetLUFS: -14)
        XCTAssertEqual(report.integratedLUFS, -.infinity)
        XCTAssertNil(report.headroomLU, "headroom should be nil when measured LUFS is non-finite")
        XCTAssertEqual(report.targetLUFS, -14)
        XCTAssertLessThan(report.truePeakDBFS, -100)
    }

    // MARK: - Week 76 K-weight + true peak

    func testKWeightChangesBassVersusTrebleEnergy() {
        let bass = makeStereoTone(amplitude: 0.3, seconds: 1.5, hz: 100).0
        let treble = makeStereoTone(amplitude: 0.3, seconds: 1.5, hz: 3000).0
        let kBass = MXLoudness.kWeight(bass, sampleRate: sampleRate)
        let kTreble = MXLoudness.kWeight(treble, sampleRate: sampleRate)
        let energy: ([Float]) -> Double = { samples in
            var s: Double = 0
            for x in samples { s += Double(x) * Double(x) }
            return s
        }
        // High shelf boosts treble relative to bass after K-weight.
        XCTAssertGreaterThan(energy(kTreble), energy(kBass) * 1.2)
    }

    func testTruePeakAtLeastSamplePeak() {
        let n = 4096
        var samples = [Float](repeating: 0, count: n)
        let hz = 18_000.0
        for i in 0..<n {
            samples[i] = Float(sin(2 * .pi * hz * Double(i) / sampleRate))
        }
        let samplePeak = MXAudioAnalysis.peak(samples)
        let tp = MXLoudness.truePeakLinear(samples, oversample: 4)
        XCTAssertGreaterThanOrEqual(tp + 1e-6, samplePeak)
        XCTAssertGreaterThan(tp, 0.5)
    }

    func testTruePeakIdentityOnDC() {
        let samples = [Float](repeating: 0.5, count: 64)
        XCTAssertEqual(MXLoudness.truePeakLinear(samples), 0.5, accuracy: 1e-6)
        XCTAssertEqual(MXLoudness.truePeakDB(samples), 20 * log10(0.5), accuracy: 1e-4)
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
