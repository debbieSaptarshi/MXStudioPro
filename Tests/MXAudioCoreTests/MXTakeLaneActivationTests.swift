import XCTest
@testable import MXAudioCore

final class MXTakeLaneActivationTests: XCTestCase {

    private func ref(
        _ id: UUID,
        take: Int,
        start: Double,
        length: Double
    ) -> MXTakeLaneActivation.ClipRef {
        .init(id: id, takeIndex: take, startBeat: start, lengthBeats: length)
    }

    func testInteriorPunchSelectingOriginalTakeDeactivatesPunch() {
        let before = UUID()
        let after = UUID()
        let punch = UUID()
        let clips = [
            ref(before, take: 0, start: 0, length: 2),
            ref(after, take: 0, start: 4, length: 4),
            ref(punch, take: 1, start: 2, length: 2)
        ]

        let active = MXTakeLaneActivation.activeIDs(afterSelecting: before, clips: clips)
        XCTAssertEqual(active, [before, after])
    }

    func testInteriorPunchSelectingPunchDeactivatesSplitTake() {
        let before = UUID()
        let after = UUID()
        let punch = UUID()
        let clips = [
            ref(before, take: 0, start: 0, length: 2),
            ref(after, take: 0, start: 4, length: 4),
            ref(punch, take: 1, start: 2, length: 2)
        ]

        let active = MXTakeLaneActivation.activeIDs(afterSelecting: punch, clips: clips)
        XCTAssertEqual(active, [punch])
    }

    func testSequentialAbuttingTakesStayMutuallyActive() {
        let verse = UUID()
        let chorus = UUID()
        let clips = [
            ref(verse, take: 0, start: 0, length: 4),
            ref(chorus, take: 1, start: 4, length: 4)
        ]

        let active = MXTakeLaneActivation.activeIDs(afterSelecting: chorus, clips: clips)
        XCTAssertEqual(active, [verse, chorus])
    }

    func testOverlappingFullTakesExclusive() {
        let a = UUID()
        let b = UUID()
        let clips = [
            ref(a, take: 0, start: 0, length: 8),
            ref(b, take: 1, start: 0, length: 8)
        ]

        let active = MXTakeLaneActivation.activeIDs(afterSelecting: b, clips: clips)
        XCTAssertEqual(active, [b])
    }
}
