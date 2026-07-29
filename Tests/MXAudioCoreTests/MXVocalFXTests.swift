import XCTest
@testable import MXAudioDSP

/// Offline vocal FX helpers used by bounce (noise gate soft-knee + de-esser peaking).
final class MXVocalFXTests: XCTestCase {

    private let sampleRate: Double = 48_000

    func testNoiseGatePassesAboveThreshold() {
        // Mirror StudioBounceExporter.applyNoiseGate soft-knee.
        let threshold: Float = 0.05
        let loud: Float = 0.2
        let result = softGate(loud, threshold: threshold)
        XCTAssertEqual(result, loud, accuracy: 1e-6)
    }

    func testNoiseGateAttenuatesBelowThreshold() {
        let threshold: Float = 0.05
        let quiet: Float = 0.01
        let result = softGate(quiet, threshold: threshold)
        XCTAssertLessThan(abs(result), abs(quiet))
        // Soft knee: (abs/thresh)² → 0.01 * (0.2)² = 0.0004
        XCTAssertEqual(result, quiet * 0.04, accuracy: 1e-6)
    }

    func testDeEsserPeakingCutsSibilanceBand() {
        var filter = MXBiquad()
        filter.configure(
            kind: .peaking,
            frequency: 6_500,
            q: 1.4,
            gainDB: -12,
            sampleRate: sampleRate
        )
        let cut = filter.magnitudeDB(at: 6_500, sampleRate: sampleRate)
        let low = filter.magnitudeDB(at: 500, sampleRate: sampleRate)
        XCTAssertLessThan(cut, -6, "expected strong cut at sibilance band, got \(cut) dB")
        XCTAssertGreaterThan(low, -1.5, "low mids should stay near unity, got \(low) dB")
    }

    func testDeEsserDisabledIsUnity() {
        var filter = MXBiquad()
        filter.configure(
            kind: .peaking,
            frequency: 6_500,
            q: 1.4,
            gainDB: 0,
            sampleRate: sampleRate
        )
        let mid = filter.magnitudeDB(at: 6_500, sampleRate: sampleRate)
        XCTAssertEqual(mid, 0, accuracy: 0.25)
    }

    // MARK: - Helpers (keep in sync with StudioBounceExporter.applyNoiseGate)

    private func softGate(_ sample: Float, threshold: Float) -> Float {
        let thresh = max(threshold, 1e-6)
        let magnitude = abs(sample)
        guard magnitude < thresh else { return sample }
        let ratio = magnitude / thresh
        return sample * ratio * ratio
    }
}
