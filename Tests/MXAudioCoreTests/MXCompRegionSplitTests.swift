import XCTest
@testable import MXAudioCore

final class MXCompRegionSplitTests: XCTestCase {

    /// Constant-tempo helper: 120 BPM → 0.5 s per beat.
    private func secondsBetween(_ from: Double, _ to: Double) -> Double {
        (to - from) * 0.5
    }

    private var longTake: MXCompRegionSplit.SourceClip {
        MXCompRegionSplit.SourceClip(
            startBeat: 0,
            lengthBeats: 8,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: 4
        )
    }

    func testInteriorPunchKeepsBeforeAndAfterWithCrossfades() {
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 2,
            punchEndBeat: 4,
            secondsBetween: secondsBetween
        )

        // At 120 BPM: xfSec = 0.012 → xfBeats = 0.012/0.5 = 0.024
        XCTAssertFalse(result.deactivateOriginal)
        XCTAssertEqual(result.before?.startBeat ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(result.before?.lengthBeats ?? -1, 2.024, accuracy: 1e-9)
        XCTAssertGreaterThan(result.before?.lengthBeats ?? 0, 2)
        XCTAssertEqual(result.before?.sourceDurationSeconds ?? -1, 1.012, accuracy: 1e-9)
        XCTAssertEqual(result.before?.fadeOutSeconds ?? -1, 0.012, accuracy: 1e-9)
        // before ends after punch start (overlap)
        let beforeEnd = (result.before?.startBeat ?? 0) + (result.before?.lengthBeats ?? 0)
        XCTAssertGreaterThan(beforeEnd, 2)

        XCTAssertEqual(result.after?.startBeat ?? -1, 3.976, accuracy: 1e-9)
        XCTAssertLessThan(result.after?.startBeat ?? 99, 4)
        XCTAssertEqual(result.after?.lengthBeats ?? -1, 4.024, accuracy: 1e-9)
        XCTAssertEqual(result.after?.sourceOffsetSeconds ?? -1, 1.988, accuracy: 1e-9)
        XCTAssertEqual(result.after?.sourceDurationSeconds ?? -1, 2.012, accuracy: 1e-9)
        XCTAssertEqual(result.after?.fadeInSeconds ?? -1, 0.012, accuracy: 1e-9)

        XCTAssertEqual(result.punchFadeInSeconds, 0.012, accuracy: 1e-9)
        XCTAssertEqual(result.punchFadeOutSeconds, 0.012, accuracy: 1e-9)
    }

    func testPunchAtStartKeepsAfterOnly() {
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 0,
            punchEndBeat: 3,
            secondsBetween: secondsBetween
        )

        XCTAssertNil(result.before)
        XCTAssertTrue(result.deactivateOriginal)
        // Soft-overlap into punch: start pulled earlier by xfBeats = 0.024
        XCTAssertEqual(result.after?.startBeat ?? -1, 2.976, accuracy: 1e-9)
        XCTAssertEqual(result.after?.fadeInSeconds ?? -1, 0.012, accuracy: 1e-9)
        XCTAssertEqual(result.punchFadeInSeconds, 0, accuracy: 1e-9)
        XCTAssertEqual(result.punchFadeOutSeconds, 0.012, accuracy: 1e-9)
    }

    func testPunchAtEndKeepsBeforeOnly() {
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 5,
            punchEndBeat: 8,
            secondsBetween: secondsBetween
        )

        XCTAssertNil(result.after)
        XCTAssertFalse(result.deactivateOriginal)
        // Soft-overlap into punch: length grown by xfBeats = 0.024
        XCTAssertEqual(result.before?.lengthBeats ?? -1, 5.024, accuracy: 1e-9)
        XCTAssertEqual(result.before?.fadeOutSeconds ?? -1, 0.012, accuracy: 1e-9)
        XCTAssertEqual(result.punchFadeInSeconds, 0.012, accuracy: 1e-9)
        XCTAssertEqual(result.punchFadeOutSeconds, 0, accuracy: 1e-9)
    }

    func testWholeCoverDeactivatesWithoutPieces() {
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 0,
            punchEndBeat: 8,
            secondsBetween: secondsBetween
        )

        XCTAssertNil(result.before)
        XCTAssertNil(result.after)
        XCTAssertTrue(result.deactivateOriginal)
    }

    func testTinyFragmentDiscarded() {
        // 40 ms before fragment at 120 BPM: 0.08 beats = 40 ms — below 50 ms floor.
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 0.08,
            punchEndBeat: 4,
            secondsBetween: secondsBetween,
            minFragmentSeconds: 0.05
        )

        XCTAssertNil(result.before)
        XCTAssertTrue(result.deactivateOriginal)
        XCTAssertNotNil(result.after)
    }

    func testNoOverlapLeavesOriginalAlone() {
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 10,
            punchEndBeat: 12,
            secondsBetween: secondsBetween
        )

        XCTAssertNil(result.before)
        XCTAssertNil(result.after)
        XCTAssertFalse(result.deactivateOriginal)
    }
}
