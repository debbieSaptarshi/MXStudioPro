import XCTest
@testable import MXAudioCore

final class MXMIDINoteEditTests: XCTestCase {
    func testClampPitch() {
        XCTAssertEqual(MXMIDINoteEdit.clampPitch(0), 0)
        XCTAssertEqual(MXMIDINoteEdit.clampPitch(60), 60)
        XCTAssertEqual(MXMIDINoteEdit.clampPitch(200), 127)
    }

    func testClampingKeepsNoteInsideClip() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 3.9, lengthBeats: 1.0)
        let clamped = MXMIDINoteEdit.clamping(note, clipLengthBeats: 4)
        XCTAssertEqual(clamped.startBeat, 3.0, accuracy: 1e-9)
        XCTAssertEqual(clamped.lengthBeats, 1.0, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(clamped.endBeat, 4.0 + 1e-9)
    }

    func testMovingPitchAndStart() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 1, lengthBeats: 0.5)
        let moved = MXMIDINoteEdit.moving(note, startBeat: 2, pitch: 64, clipLengthBeats: 4)
        XCTAssertEqual(moved.note, 64)
        XCTAssertEqual(moved.startBeat, 2, accuracy: 1e-9)
        XCTAssertEqual(moved.lengthBeats, 0.5, accuracy: 1e-9)
    }

    func testMakingAndReplaceRemove() {
        let made = MXMIDINoteEdit.making(pitch: 48, startBeat: 0.1, clipLengthBeats: 4)
        XCTAssertEqual(made.note, 48)
        XCTAssertEqual(made.lengthBeats, MXMIDINoteEdit.defaultLengthBeats, accuracy: 1e-9)

        var notes = [made]
        let updated = MXMIDINote(id: made.id, note: 50, velocity: 90, startBeat: 1, lengthBeats: 0.25)
        notes = MXMIDINoteEdit.replacing(notes, id: made.id, with: updated, clipLengthBeats: 4)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].note, 50)
        notes = MXMIDINoteEdit.removing(notes, id: made.id)
        XCTAssertTrue(notes.isEmpty)
    }

    func testAppend() {
        let a = MXMIDINoteEdit.making(pitch: 36, startBeat: 0, clipLengthBeats: 2)
        let b = MXMIDINoteEdit.making(pitch: 38, startBeat: 1, clipLengthBeats: 2)
        let notes = MXMIDINoteEdit.appending([a], note: b, clipLengthBeats: 2)
        XCTAssertEqual(notes.count, 2)
    }
}
