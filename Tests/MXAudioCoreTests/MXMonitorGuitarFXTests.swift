import XCTest
@testable import MXAudioCore

final class MXMonitorGuitarFXTests: XCTestCase {
    func testDisabledStatic() {
        let fx = MXMonitorGuitarFX.disabled
        XCTAssertFalse(fx.enabled)
        XCTAssertEqual(fx.distortionMix, 0)
        XCTAssertEqual(fx.delayMix, 0)
        XCTAssertEqual(fx.reverbMix, 0)
        XCTAssertEqual(fx.eqMidGain, 0, accuracy: 1e-5)
        XCTAssertEqual(fx.delayTime, 0.3, accuracy: 1e-5)
    }

    func testClampedMixAndGainRanges() {
        let fx = MXMonitorGuitarFX.clamped(
            enabled: true,
            distortionMix: 150,
            delayMix: -10,
            delayTime: 5,
            reverbMix: 50,
            eqMidGain: -40
        )
        XCTAssertTrue(fx.enabled)
        XCTAssertEqual(fx.distortionMix, 100)
        XCTAssertEqual(fx.delayMix, 0)
        XCTAssertEqual(fx.delayTime, 2, accuracy: 1e-5)
        XCTAssertEqual(fx.reverbMix, 50)
        XCTAssertEqual(fx.eqMidGain, -12, accuracy: 1e-5)
    }

    func testClampedPreservesInRangeValues() {
        let fx = MXMonitorGuitarFX.clamped(
            enabled: true,
            distortionMix: 42,
            delayMix: 22,
            delayTime: 0.32,
            reverbMix: 18,
            eqMidGain: 2
        )
        XCTAssertEqual(fx.distortionMix, 42)
        XCTAssertEqual(fx.delayMix, 22)
        XCTAssertEqual(fx.delayTime, 0.32, accuracy: 1e-5)
        XCTAssertEqual(fx.reverbMix, 18)
        XCTAssertEqual(fx.eqMidGain, 2, accuracy: 1e-5)
    }
}
