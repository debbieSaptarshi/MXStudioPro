import XCTest
@testable import MXAudioCore

final class MXClipFadeGeometryTests: XCTestCase {
    func testWidthBeatsAt120BPM() {
        // 0.5 s at 120 BPM = 1 beat
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: 0.5, bpm: 120), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: 0, bpm: 120), 0, accuracy: 1e-9)
        XCTAssertEqual(MXClipFadeGeometry.widthBeats(fadeSeconds: -1, bpm: 120), 0, accuracy: 1e-9)
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
}
