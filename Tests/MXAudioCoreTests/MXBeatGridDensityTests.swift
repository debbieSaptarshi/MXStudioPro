import XCTest
@testable import MXAudioCore

final class MXBeatGridDensityTests: XCTestCase {
    func testShouldDrawWhenWideEnough() {
        // 8 beats across ~320pt → 40 px/beat; 1/16 = 0.25 → 10 px ≥ 6
        XCTAssertTrue(MXBeatGridDensity.shouldDrawSubdivisions(pixelsPerBeat: 40, subdivBeats: 0.25))
        // 32 beats across 320pt → 10 px/beat; 1/32 = 0.125 → 1.25 px < 6
        XCTAssertFalse(MXBeatGridDensity.shouldDrawSubdivisions(pixelsPerBeat: 10, subdivBeats: 0.125))
    }

    func testShouldNotDrawWholeBeatOrInvalid() {
        XCTAssertFalse(MXBeatGridDensity.shouldDrawSubdivisions(pixelsPerBeat: 40, subdivBeats: 1.0))
        XCTAssertFalse(MXBeatGridDensity.shouldDrawSubdivisions(pixelsPerBeat: 40, subdivBeats: 0))
        XCTAssertFalse(MXBeatGridDensity.shouldDrawSubdivisions(pixelsPerBeat: 0, subdivBeats: 0.25))
    }

    func testVisibleSubdivCoarsensThenNils() {
        // Dense 1/32 at 10 px/beat: 1.25 → double to 0.25 (2.5) → 0.5 (5) → 1.0 → nil
        XCTAssertNil(MXBeatGridDensity.visibleSubdivBeats(snapBeats: 0.125, pixelsPerBeat: 10))
        // Same snap at 40 px/beat: 5 px for 1/32 < 6 → coarsen to 0.25 (10 px)
        let step = MXBeatGridDensity.visibleSubdivBeats(snapBeats: 0.125, pixelsPerBeat: 40)
        XCTAssertEqual(step!, 0.25, accuracy: 1e-9)
        // Wide enough for native 1/16
        XCTAssertEqual(
            MXBeatGridDensity.visibleSubdivBeats(snapBeats: 0.25, pixelsPerBeat: 40)!,
            0.25,
            accuracy: 1e-9
        )
    }

    func testVisibleSubdivTriplets() {
        // 1/6 at 12 px/beat → 2 px < 6 → 1/3 (4) → 2/3 (8) ≥ 6
        let step = MXBeatGridDensity.visibleSubdivBeats(snapBeats: 1.0 / 6.0, pixelsPerBeat: 12)
        XCTAssertEqual(step!, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testZoomClampAndSteps() {
        XCTAssertEqual(MXBeatGridDensity.clampBeatsVisible(8), 8, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.clampBeatsVisible(2), 4, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.clampBeatsVisible(64), 32, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.zoomOutBeatsVisible(8), 16, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.zoomOutBeatsVisible(32), 32, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.zoomInBeatsVisible(8), 4, accuracy: 1e-9)
        XCTAssertEqual(MXBeatGridDensity.zoomInBeatsVisible(4), 4, accuracy: 1e-9)
    }
}
