import XCTest
@testable import MXAudioCore

final class MXClipFadeGeometryTests: XCTestCase {
    func testWidthBeatsAt120BPM() {
        // 0.5 s at 120 BPM = 1 beat
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: 0.5, bpm: 120), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: 0, bpm: 120), 0, accuracy: 1e-9)
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: -1, bpm: 120), 0, accuracy: 1e-9)
    }

    func testSecondsInverseRoundTrip() {
        let sec = 0.75
        let beats = MXClipFadeGeometry.widthBeats(fadeSeconds: sec, bpm: 100)
        let back = MXClipFadeGeometry.seconds(widthBeats: beats, bpm: 100)
        XCTAssertEqual(back, sec, accuracy: 1e-9)
        XCTAssertEqual(MXClipFadeGeometry.seconds(widthBeats: -2, bpm: 120), 0, accuracy: 1e-9)
        // 1 beat at 120 BPM = 0.5 s
        XCTAssertEqual(MXClipFadeGeometry.seconds(widthBeats: 1, bpm: 120), 0.5, accuracy: 1e-9)
    }

    func testFadeGainsMatchCrossfade() {
        XCTAssertEqual(MXClipFadeGeometry.fadeInGain(0), 0, accuracy: 1e-5)
        XCTAssertEqual(MXClipFadeGeometry.fadeInGain(1), 1, accuracy: 1e-5)
        XCTAssertEqual(MXClipFadeGeometry.fadeOutGain(0), 1, accuracy: 1e-5)
        XCTAssertEqual(MXClipFadeGeometry.fadeOutGain(1), 0, accuracy: 1e-5)
        let midIn = MXClipFadeGeometry.fadeInGain(0.5)
        let midOut = MXClipFadeGeometry.fadeOutGain(0.5)
        XCTAssertEqual(midIn * midIn + midOut * midOut, 1, accuracy: 1e-4)
    }

    func testMeetInMiddleProportional() {
        let result = MXClipFadeGeometry.meetInMiddle(fadeIn: 0.8, fadeOut: 0.8, duration: 1.0)
        XCTAssertEqual(result.fadeIn + result.fadeOut, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.fadeIn, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.fadeOut, 0.5, accuracy: 1e-9)
    }

    func testMeetInMiddlePreferFadeIn() {
        let result = MXClipFadeGeometry.meetInMiddle(
            fadeIn: 0.9,
            fadeOut: 0.9,
            duration: 1.0,
            prefer: .fadeIn
        )
        XCTAssertEqual(result.fadeIn, 0.9, accuracy: 1e-9)
        XCTAssertEqual(result.fadeOut, 0.1, accuracy: 1e-9)
    }

    func testMeetInMiddlePreferFadeOut() {
        let result = MXClipFadeGeometry.meetInMiddle(
            fadeIn: 0.7,
            fadeOut: 0.8,
            duration: 1.0,
            prefer: .fadeOut
        )
        XCTAssertEqual(result.fadeOut, 0.8, accuracy: 1e-9)
        XCTAssertEqual(result.fadeIn, 0.2, accuracy: 1e-9)
    }

    func testMeetInMiddleNoOverflowUnchanged() {
        let result = MXClipFadeGeometry.meetInMiddle(fadeIn: 0.2, fadeOut: 0.3, duration: 1.0)
        XCTAssertEqual(result.fadeIn, 0.2, accuracy: 1e-9)
        XCTAssertEqual(result.fadeOut, 0.3, accuracy: 1e-9)
    }
}
