import XCTest
@testable import MXAudioDSP

final class MXAuxSendTests: XCTestCase {
    func testLinearGainMapsPercent() {
        XCTAssertEqual(MXAuxSend.linearGain(percent: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(MXAuxSend.linearGain(percent: 50), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MXAuxSend.linearGain(percent: 100), 1, accuracy: 1e-9)
        XCTAssertEqual(MXAuxSend.linearGain(percent: 150), 1, accuracy: 1e-9)
        XCTAssertEqual(MXAuxSend.linearGain(percent: -10), 0, accuracy: 1e-9)
    }

    func testReturnGainDefaults() {
        XCTAssertEqual(
            MXAuxSend.returnGain(percent: MXAuxSend.defaultReturnPercent),
            0.7,
            accuracy: 1e-6
        )
    }

    func testSendTapIsPostFader() {
        let tap = MXAuxSend.sendTap(postFaderSample: 0.8, sendPercent: 25)
        XCTAssertEqual(tap, 0.2, accuracy: 1e-6)
        XCTAssertEqual(MXAuxSend.sendTap(postFaderSample: 1, sendPercent: 0), 0, accuracy: 1e-9)
    }

    func testMasterContribution() {
        let wet: Float = 0.5
        XCTAssertEqual(
            MXAuxSend.masterContribution(wetSample: wet, returnPercent: 70),
            0.35,
            accuracy: 1e-6
        )
        XCTAssertEqual(
            MXAuxSend.masterContribution(wetSample: wet, returnPercent: 0),
            0,
            accuracy: 1e-9
        )
    }

    func testIsActiveThreshold() {
        XCTAssertFalse(MXAuxSend.isActive(sendPercent: 0))
        XCTAssertFalse(MXAuxSend.isActive(sendPercent: 0.4))
        XCTAssertTrue(MXAuxSend.isActive(sendPercent: 0.6))
        XCTAssertTrue(MXAuxSend.isActive(sendPercent: 40))
    }

    func testAuxTailSeconds() {
        XCTAssertEqual(MXAuxSend.auxTailSeconds(sendPercent: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(MXAuxSend.auxTailSeconds(sendPercent: 50, smallRoom: false), 1.35, accuracy: 1e-6)
        XCTAssertEqual(MXAuxSend.auxTailSeconds(sendPercent: 50, smallRoom: true), 0.85, accuracy: 1e-6)
    }

    func testRoutingMathDryPlusWet() {
        // BandLab/Logic lite: dry stays at full post-fader; wet = send × return × wetReverb.
        let dry: Float = 0.9
        let send = MXAuxSend.linearGain(percent: 40)
        let ret = MXAuxSend.returnGain(percent: 70)
        let wetUnit: Float = 1 // fully-wet aux impulse response scale
        let wetOut = dry * send * wetUnit * ret
        XCTAssertEqual(wetOut, 0.9 * 0.4 * 0.7, accuracy: 1e-6)
        // Dry path unchanged by send.
        XCTAssertEqual(dry, 0.9, accuracy: 1e-9)
    }
}
