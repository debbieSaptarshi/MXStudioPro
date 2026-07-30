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

    func testSnapBeatEighthResolution() {
        XCTAssertEqual(MXMIDIQuantize.eighth, 0.5, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.2, resolution: 0.5), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.3, resolution: 0.5), 1.5, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.24, resolution: 0.5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.25, resolution: 0.5), 0.5, accuracy: 1e-9)
    }

    func testSnapBeatThirtySecondResolution() {
        XCTAssertEqual(MXMIDIQuantize.thirtySecond, 0.125, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.18, resolution: 0.125), 0.125, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.0624, resolution: 0.125), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.0626, resolution: 0.125), 0.125, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.0, resolution: 0.125), 1.0, accuracy: 1e-9)
    }

    func testSnapBeatEighthTripletResolution() {
        let r = MXMIDIQuantize.eighthTriplet
        XCTAssertEqual(r, 1.0 / 3.0, accuracy: 1e-12)
        // Near 0 → 0; near 1/3 → 1/3; near 2/3 → 2/3; near 1 → 1
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.1, resolution: r), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.2, resolution: r), r, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.5, resolution: r), 2.0 * r, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.9, resolution: r), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.0 / 3.0, resolution: r), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testSnapBeatSixteenthTripletResolution() {
        let r = MXMIDIQuantize.sixteenthTriplet
        XCTAssertEqual(r, 1.0 / 6.0, accuracy: 1e-12)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.05, resolution: r), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.1, resolution: r), r, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.5, resolution: r), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.0 / 6.0, resolution: r), 1.0 / 6.0, accuracy: 1e-9)
    }

    func testSnapBeatDottedResolutions() {
        XCTAssertEqual(MXMIDIQuantize.dottedEighth, 0.75, accuracy: 1e-12)
        XCTAssertEqual(MXMIDIQuantize.dottedSixteenth, 0.375, accuracy: 1e-12)
        // Dotted 1/8: 0.4 → 0.0? midpoint of 0 and 0.75 is 0.375; 0.4 rounds up to 0.75
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.37, resolution: 0.75), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.4, resolution: 0.75), 0.75, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.75, resolution: 0.75), 0.75, accuracy: 1e-9)
        // Midpoint 0.75↔1.5 is 1.125; 1.2 rounds up to 1.5
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.2, resolution: 0.75), 1.5, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(1.4, resolution: 0.75), 1.5, accuracy: 1e-9)
        // Dotted 1/16
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.2, resolution: 0.375), 0.375, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.1, resolution: 0.375), 0.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDIQuantize.snapBeat(0.75, resolution: 0.375), 0.75, accuracy: 1e-9)
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
