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

    // MARK: - Week 58

    func testResizingLengthClampsToClip() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 3.0, lengthBeats: 0.25)
        let grown = MXMIDINoteEdit.resizing(note, lengthBeats: 2.0, clipLengthBeats: 4)
        XCTAssertEqual(grown.startBeat, 3.0, accuracy: 1e-9)
        XCTAssertEqual(grown.lengthBeats, 1.0, accuracy: 1e-9)

        let shrunk = MXMIDINoteEdit.resizing(note, lengthBeats: 0.01, clipLengthBeats: 4)
        XCTAssertEqual(shrunk.lengthBeats, 0.0625, accuracy: 1e-9)
    }

    func testSettingVelocity() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let soft = MXMIDINoteEdit.settingVelocity(note, velocity: 1, clipLengthBeats: 4)
        XCTAssertEqual(soft.velocity, 1)
        let loud = MXMIDINoteEdit.settingVelocity(note, velocity: 200, clipLengthBeats: 4)
        XCTAssertEqual(loud.velocity, 127)
        let zero = MXMIDINoteEdit.settingVelocity(note, velocity: 0, clipLengthBeats: 4)
        XCTAssertEqual(zero.velocity, 1)
    }

    // MARK: - Week 62 (multi-select)

    func testTransposingOnlySelectedNotes() {
        let a = MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let b = MXMIDINote(note: 64, velocity: 100, startBeat: 1, lengthBeats: 0.5)
        let notes = [a, b]
        let transposed = MXMIDINoteEdit.transposing(
            notes,
            ids: [a.id],
            semitones: 2,
            clipLengthBeats: 4
        )
        XCTAssertEqual(transposed[0].note, 62)
        XCTAssertEqual(transposed[1].note, 64) // unselected untouched
    }

    func testTransposingClampsAndPreservesTiming() {
        let note = MXMIDINote(note: 125, velocity: 90, startBeat: 2, lengthBeats: 0.75)
        let up = MXMIDINoteEdit.transposing(
            [note],
            ids: [note.id],
            semitones: 12,
            clipLengthBeats: 8
        )
        XCTAssertEqual(up[0].note, 127) // clamped at ceiling
        XCTAssertEqual(up[0].startBeat, 2, accuracy: 1e-9)
        XCTAssertEqual(up[0].lengthBeats, 0.75, accuracy: 1e-9)

        let low = MXMIDINote(note: 3, velocity: 90, startBeat: 0, lengthBeats: 0.5)
        let down = MXMIDINoteEdit.transposing(
            [low],
            ids: [low.id],
            semitones: -12,
            clipLengthBeats: 4
        )
        XCTAssertEqual(down[0].note, 0) // clamped at floor
    }

    func testTransposingNoOpWhenEmptyOrZero() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let sameIDsEmpty = MXMIDINoteEdit.transposing(
            [note], ids: [], semitones: 5, clipLengthBeats: 4
        )
        XCTAssertEqual(sameIDsEmpty[0].note, 60)
        let sameZero = MXMIDINoteEdit.transposing(
            [note], ids: [note.id], semitones: 0, clipLengthBeats: 4
        )
        XCTAssertEqual(sameZero[0].note, 60)
    }

    func testMovingManyAppliesDeltaToSelection() {
        let a = MXMIDINote(note: 60, velocity: 100, startBeat: 1, lengthBeats: 0.5)
        let b = MXMIDINote(note: 62, velocity: 100, startBeat: 2, lengthBeats: 0.5)
        let moved = MXMIDINoteEdit.movingMany(
            [a, b],
            ids: [a.id, b.id],
            deltaStartBeats: 0.5,
            deltaPitch: 3,
            clipLengthBeats: 8
        )
        XCTAssertEqual(moved[0].startBeat, 1.5, accuracy: 1e-9)
        XCTAssertEqual(moved[0].note, 63)
        XCTAssertEqual(moved[1].startBeat, 2.5, accuracy: 1e-9)
        XCTAssertEqual(moved[1].note, 65)
    }

    func testMovingManyLeavesUnselectedAndClampsToClip() {
        let a = MXMIDINote(note: 60, velocity: 100, startBeat: 3.5, lengthBeats: 0.5)
        let b = MXMIDINote(note: 62, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let moved = MXMIDINoteEdit.movingMany(
            [a, b],
            ids: [a.id],
            deltaStartBeats: 2.0, // would push past clip end → clamped
            deltaPitch: -1,
            clipLengthBeats: 4
        )
        XCTAssertEqual(moved[0].note, 59)
        XCTAssertLessThanOrEqual(moved[0].endBeat, 4.0 + 1e-9)
        XCTAssertEqual(moved[1].startBeat, 0, accuracy: 1e-9) // unselected untouched
        XCTAssertEqual(moved[1].note, 62)
    }

    func testMovingManyNoOpWhenNoDelta() {
        let note = MXMIDINote(note: 60, velocity: 100, startBeat: 1, lengthBeats: 0.5)
        let same = MXMIDINoteEdit.movingMany(
            [note], ids: [note.id], deltaStartBeats: 0, deltaPitch: 0, clipLengthBeats: 4
        )
        XCTAssertEqual(same[0].startBeat, 1, accuracy: 1e-9)
        XCTAssertEqual(same[0].note, 60)
    }

    func testRemovingManyByIDs() {
        let a = MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let b = MXMIDINote(note: 62, velocity: 100, startBeat: 1, lengthBeats: 0.5)
        let c = MXMIDINote(note: 64, velocity: 100, startBeat: 2, lengthBeats: 0.5)
        let remaining = MXMIDINoteEdit.removing([a, b, c], ids: [a.id, c.id])
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, b.id)
    }

    // MARK: - Week 68 (draw / paint)

    func testCellStartFloorsToGrid() {
        XCTAssertEqual(MXMIDINoteEdit.cellStart(beat: 1.24, resolution: 0.25), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDINoteEdit.cellStart(beat: 1.0, resolution: 0.25), 1.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDINoteEdit.cellStart(beat: 0.9, resolution: 1.0 / 3.0), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(MXMIDINoteEdit.cellStart(beat: -1, resolution: 0.25), 0, accuracy: 1e-9)
    }

    func testPaintCellInsertsOnce() {
        var notes: [MXMIDINote] = []
        notes = MXMIDINoteEdit.applyingPaintCell(
            notes, beat: 0.1, pitch: 60, snapBeats: 0.25, clipLengthBeats: 4, erase: false
        )
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].startBeat, 0.0, accuracy: 1e-9)
        XCTAssertEqual(notes[0].lengthBeats, 0.25, accuracy: 1e-9)
        // Second paint on same cell is a no-op
        let again = MXMIDINoteEdit.applyingPaintCell(
            notes, beat: 0.2, pitch: 60, snapBeats: 0.25, clipLengthBeats: 4, erase: false
        )
        XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again[0].id, notes[0].id)
    }

    func testEraseCellRemovesOverlapping() {
        let a = MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 0.5)
        let b = MXMIDINote(note: 62, velocity: 100, startBeat: 0, lengthBeats: 0.25)
        let erased = MXMIDINoteEdit.applyingPaintCell(
            [a, b], beat: 0.1, pitch: 60, snapBeats: 0.25, clipLengthBeats: 4, erase: true
        )
        XCTAssertEqual(erased.count, 1)
        XCTAssertEqual(erased[0].note, 62)
    }

    func testPaintRespectsScaleLock() {
        let scale = MXMIDIScale.cMajor
        // Pitch 61 (C#) snaps to nearest scale tone under C major.
        let notes = MXMIDINoteEdit.applyingPaintCell(
            [], beat: 0, pitch: 61, snapBeats: 0.25, clipLengthBeats: 4, erase: false, scale: scale
        )
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].note, scale.snapPitch(61))
        XCTAssertTrue(MXMIDINoteEdit.cellOccupied(
            notes, beat: 0, pitch: 61, snapBeats: 0.25, scale: scale
        ))
    }
}
