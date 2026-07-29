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

        XCTAssertFalse(result.deactivateOriginal)
        XCTAssertEqual(result.before?.startBeat ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(result.before?.lengthBeats ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(result.before?.sourceDurationSeconds ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(result.before?.fadeOutSeconds ?? -1, 0.012, accuracy: 1e-9)

        XCTAssertEqual(result.after?.startBeat ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(result.after?.lengthBeats ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(result.after?.sourceOffsetSeconds ?? -1, 2, accuracy: 1e-9)
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
        XCTAssertEqual(result.after?.startBeat ?? -1, 3, accuracy: 1e-9)
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
        XCTAssertEqual(result.before?.lengthBeats ?? -1, 5, accuracy: 1e-9)
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
        // 8 ms before fragment at 120 BPM: 0.016 beats ≈ 8 ms — below 12 ms min.
        let result = MXCompRegionSplit.split(
            sibling: longTake,
            punchStartBeat: 0.016,
            punchEndBeat: 4,
            secondsBetween: secondsBetween,
            minFragmentSeconds: 0.012
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
