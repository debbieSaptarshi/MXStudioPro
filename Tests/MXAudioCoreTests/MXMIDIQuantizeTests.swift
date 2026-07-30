import XCTest
@testable import MXAudioCore

final class MXMIDIQuantizeTests: XCTestCase {
    func testSnapBeatSixteenthRoundsNearest() {
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.07), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.13), 1.25, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0), 0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(2.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(2.124), 2.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(2.125), 2.25, accuracy: 1e-9)
    }

    func testSnapBeatNonPositiveResolutionPassthrough() {
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.07, resolution: 0), 1.07, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(-0.5, resolution: -1), 0, accuracy: 1e-9)
    }

    func testQuantizeStartsPreservesLengthAndIdentity() {
        let id = UUID()
        let notes = [
            MXMIDINote(id: id, note: 36, velocity: 100, startBeat: 1.07, lengthBeats: 0.4),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1.13, lengthBeats: 0.25),
        ]
        let q = MXMIDIQuantize.quantizeStarts(notes)
        XCTAssertEqual(q.count, 2)
        XCTAssertEqual(q[0].id, id)
        XCTAssertEqual(q[0].note, 36)
        XCTAssertEqual(q[0].velocity, 100)
        XCTAssertEqual(q[0].startBeat, 1.0, accuracy: 1e-9)
        XCTAssertEqual(q[0].lengthBeats, 0.4, accuracy: 1e-9)
        XCTAssertEqual(q[1].startBeat, 1.25, accuracy: 1e-9)
        XCTAssertEqual(q[1].lengthBeats, 0.25, accuracy: 1e-9)
    }

    func testQuantizeStartsEmptyIsEmpty() {
        XCTAssertTrue(MXMIDIQuantize.quantizeStarts([]).isEmpty)
    }

    func testQuantizeStartsClampsNegativeStart() {
        let notes = [MXMIDINote(note: 60, velocity: 80, startBeat: 0.01, lengthBeats: 1)]
        // Already non-negative from init; snapping 0.01 → 0.
        let q = MXMIDIQuantize.quantizeStarts(notes)
        XCTAssertEqual(q[0].startBeat, 0, accuracy: 1e-9)
    }

    func testStrengthZeroIsIdentity() {
        let notes = [MXMIDINote(note: 36, velocity: 100, startBeat: 1.07, lengthBeats: 0.4)]
        let q = MXMIDIQuantize.quantizeStarts(notes, strength: 0)
        XCTAssertEqual(q[0].startBeat, 1.07, accuracy: 1e-9)
    }

    func testStrengthHalfBlendsTowardGrid() {
        // 1.07 snaps to 1.0; half strength → 1.035
        let notes = [MXMIDINote(note: 36, velocity: 100, startBeat: 1.07, lengthBeats: 0.25)]
        let q = MXMIDIQuantize.quantizeStarts(notes, strength: 0.5)
        XCTAssertEqual(q[0].startBeat, 1.035, accuracy: 1e-9)
    }

    func testSwingDelaysOddSixteenths() {
        // Beat 0.25 is odd 16th index 1 → delayed by swing * 0.25 * 0.5
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0.0, lengthBeats: 0.2),
            MXMIDINote(note: 38, velocity: 100, startBeat: 0.25, lengthBeats: 0.2),
        ]
        let q = MXMIDIQuantize.quantizeStarts(notes, strength: 1, swing: 1)
        XCTAssertEqual(q[0].startBeat, 0.0, accuracy: 1e-9)
        XCTAssertEqual(q[1].startBeat, 0.25 + 0.125, accuracy: 1e-9)
    }

    func testSwungGridBeatHelper() {
        XCTAssertEqual(MXMIDIQuantize.swungGridBeat(0.26, swing: 0), 0.25, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.swungGridBeat(0.26, swing: 1), 0.375, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.swungGridBeat(0.01, swing: 1), 0.0, accuracy: 1e-9)
    }
}
