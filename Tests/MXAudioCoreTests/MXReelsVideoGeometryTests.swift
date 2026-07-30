import XCTest
@testable import MXAudioDSP

final class MXReelsVideoGeometryTests: XCTestCase {
    func testEvenSizes() {
        XCTAssertTrue(MXReelsVideoGeometry.isValidEvenSize(.reels720))
        XCTAssertTrue(MXReelsVideoGeometry.isValidEvenSize(.reels1080))
        XCTAssertFalse(MXReelsVideoGeometry.isValidEvenSize(.init(width: 721, height: 1280)))
        XCTAssertFalse(MXReelsVideoGeometry.isValidEvenSize(.init(width: 0, height: 1280)))
    }

    func testPortraitAspect() {
        XCTAssertTrue(MXReelsVideoGeometry.isPortraitReelsAspect(.reels720))
        XCTAssertTrue(MXReelsVideoGeometry.isPortraitReelsAspect(.reels1080))
        XCTAssertFalse(MXReelsVideoGeometry.isPortraitReelsAspect(.init(width: 1280, height: 720)))
    }

    func testClampedDuration() {
        XCTAssertEqual(MXReelsVideoGeometry.clampedDuration(12.5), 12.5, accuracy: 1e-9)
        XCTAssertEqual(MXReelsVideoGeometry.clampedDuration(120), 90, accuracy: 1e-9)
        XCTAssertEqual(MXReelsVideoGeometry.clampedDuration(-1), 0, accuracy: 1e-9)
        XCTAssertEqual(MXReelsVideoGeometry.clampedDuration(.nan), 0, accuracy: 1e-9)
    }

    func testFrameCountAndPTS() {
        XCTAssertEqual(MXReelsVideoGeometry.frameCount(durationSeconds: 0), 0)
        XCTAssertEqual(MXReelsVideoGeometry.frameCount(durationSeconds: 1, fps: 24), 24)
        XCTAssertEqual(MXReelsVideoGeometry.frameCount(durationSeconds: 0.1, fps: 24), 3)
        XCTAssertEqual(MXReelsVideoGeometry.presentationTime(frame: 0, fps: 24), 0, accuracy: 1e-12)
        XCTAssertEqual(MXReelsVideoGeometry.presentationTime(frame: 24, fps: 24), 1, accuracy: 1e-9)
    }
}
