import XCTest
@testable import MXAudioCore

final class MXSidechainDuckTests: XCTestCase {
    // MARK: - gain curve

    func testTriggerAtZeroIsDucked() {
        // At the hit the gain drops to 1 − amount (deepest duck).
        let g = MXSidechainDuck.gain(timeSinceTrigger: 0, amount: 0.6)
        XCTAssertEqual(g, 0.4, accuracy: 1e-6)
        XCTAssertLessThan(g, 1)
    }

    func testHeldAtFloorDuringAttack() {
        let attack = 0.02
        let mid = MXSidechainDuck.gain(timeSinceTrigger: attack / 2, amount: 0.5, attack: attack)
        XCTAssertEqual(mid, 0.5, accuracy: 1e-6)
    }

    func testAfterReleaseReturnsToUnity() {
        let attack = 0.02
        let release = 0.18
        let after = MXSidechainDuck.gain(
            timeSinceTrigger: attack + release + 0.05,
            amount: 0.8,
            attack: attack,
            release: release
        )
        XCTAssertEqual(after, 1, accuracy: 1e-6)
    }

    func testExactlyAtReleaseEndIsUnity() {
        let after = MXSidechainDuck.gain(
            timeSinceTrigger: 0.02 + 0.18,
            amount: 0.8,
            attack: 0.02,
            release: 0.18
        )
        XCTAssertEqual(after, 1, accuracy: 1e-6)
    }

    func testAmountZeroAlwaysUnity() {
        for t in stride(from: 0.0, through: 0.5, by: 0.05) {
            XCTAssertEqual(MXSidechainDuck.gain(timeSinceTrigger: t, amount: 0), 1, accuracy: 1e-9)
        }
    }

    func testBeforeTriggerIsUnity() {
        XCTAssertEqual(MXSidechainDuck.gain(timeSinceTrigger: -0.01, amount: 1), 1, accuracy: 1e-9)
    }

    func testReleaseIsMonotonicIncreasing() {
        let attack = 0.02
        let release = 0.18
        var previous = MXSidechainDuck.gain(timeSinceTrigger: attack, amount: 0.7, attack: attack, release: release)
        for step in stride(from: attack, through: attack + release, by: 0.01) {
            let g = MXSidechainDuck.gain(timeSinceTrigger: step, amount: 0.7, attack: attack, release: release)
            XCTAssertGreaterThanOrEqual(g + 1e-9, previous)
            previous = g
        }
    }

    func testAmountClampsAboveOne() {
        // amount > 1 clamps to full mute at the hit.
        XCTAssertEqual(MXSidechainDuck.gain(timeSinceTrigger: 0, amount: 2), 0, accuracy: 1e-9)
    }

    // MARK: - secondsSinceKick

    func testFindsNearestPastKick() {
        let notes: [(startBeat: Double, note: UInt8)] = [
            (0, 36), (1, 38), (2, 36), (3, 42),
        ]
        // Playhead at beat 2.5, 120 bpm → 0.5 beat past the beat-2 kick = 0.25 s.
        let t = MXSidechainDuck.secondsSinceKick(playheadBeat: 2.5, notes: notes, bpm: 120)
        XCTAssertNotNil(t)
        XCTAssertEqual(t!, 0.25, accuracy: 1e-6)
    }

    func testKickExactlyAtPlayheadIsZeroSeconds() {
        let notes: [(startBeat: Double, note: UInt8)] = [(0, 36), (4, 36)]
        let t = MXSidechainDuck.secondsSinceKick(playheadBeat: 4, notes: notes, bpm: 120)
        XCTAssertEqual(t ?? -1, 0, accuracy: 1e-9)
    }

    func testNoKickBeforePlayheadReturnsNil() {
        let notes: [(startBeat: Double, note: UInt8)] = [(8, 36)]
        XCTAssertNil(MXSidechainDuck.secondsSinceKick(playheadBeat: 2, notes: notes, bpm: 120))
    }

    func testIgnoresNonKickNotes() {
        // Only snare (38) present before the playhead → no kick found.
        let notes: [(startBeat: Double, note: UInt8)] = [(0, 38), (1, 42), (2, 46)]
        XCTAssertNil(MXSidechainDuck.secondsSinceKick(playheadBeat: 3, notes: notes, bpm: 120))
    }

    func testTempoScalesSeconds() {
        let notes: [(startBeat: Double, note: UInt8)] = [(0, 36)]
        // 1 beat gap at 60 bpm = 1 s; at 120 bpm = 0.5 s.
        XCTAssertEqual(MXSidechainDuck.secondsSinceKick(playheadBeat: 1, notes: notes, bpm: 60) ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertEqual(MXSidechainDuck.secondsSinceKick(playheadBeat: 1, notes: notes, bpm: 120) ?? 0, 0.5, accuracy: 1e-6)
    }

    func testNonPositiveBPMReturnsNil() {
        let notes: [(startBeat: Double, note: UInt8)] = [(0, 36)]
        XCTAssertNil(MXSidechainDuck.secondsSinceKick(playheadBeat: 1, notes: notes, bpm: 0))
    }

    func testEmptyNotesReturnsNil() {
        XCTAssertNil(MXSidechainDuck.secondsSinceKick(playheadBeat: 4, notes: [], bpm: 120))
    }

    func testIsKickHelper() {
        XCTAssertTrue(MXSidechainDuck.isKick(36))
        XCTAssertFalse(MXSidechainDuck.isKick(38)) // snare
        XCTAssertFalse(MXSidechainDuck.isKick(42)) // closed hat
    }
}
