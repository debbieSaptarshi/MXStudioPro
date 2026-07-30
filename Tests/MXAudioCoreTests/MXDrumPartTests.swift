import XCTest
@testable import MXAudioCore

final class MXDrumPartTests: XCTestCase {
    func testPadNotesMapToExpectedParts() {
        XCTAssertEqual(MXDrumPart.part(forNote: 36), .kick)
        XCTAssertEqual(MXDrumPart.part(forNote: 38), .snare)
        XCTAssertEqual(MXDrumPart.part(forNote: 39), .snare)
        XCTAssertEqual(MXDrumPart.part(forNote: 42), .hats)
        XCTAssertEqual(MXDrumPart.part(forNote: 46), .hats)
        XCTAssertEqual(MXDrumPart.part(forNote: 45), .toms)
        XCTAssertEqual(MXDrumPart.part(forNote: 37), .perc)
        XCTAssertEqual(MXDrumPart.part(forNote: 51), .ride)
    }

    func testFixtureAliasesMapIntoLanes() {
        XCTAssertEqual(MXDrumPart.part(forNote: 40), .snare)
        XCTAssertEqual(MXDrumPart.part(forNote: 44), .hats)
        XCTAssertEqual(MXDrumPart.part(forNote: 41), .toms)
        XCTAssertEqual(MXDrumPart.part(forNote: 48), .toms)
        XCTAssertEqual(MXDrumPart.part(forNote: 49), .ride)
    }

    func testUnmappedNoteReturnsNil() {
        XCTAssertNil(MXDrumPart.part(forNote: 60))
        XCTAssertNil(MXDrumPart.part(forNote: 0))
    }

    func testFilterKeepsOnlyPartNotes() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
            MXMIDINote(note: 42, velocity: 80, startBeat: 0.5, lengthBeats: 0.125),
            MXMIDINote(note: 60, velocity: 70, startBeat: 2, lengthBeats: 1),
        ]
        let kicks = MXDrumPart.filter(notes, part: .kick)
        XCTAssertEqual(kicks.map(\.note), [36])

        let snares = notes.filtered(to: .snare)
        XCTAssertEqual(snares.map(\.note), [38])

        let hats = MXDrumPart.filter(notes, part: .hats)
        XCTAssertEqual(hats.map(\.note), [42])
    }

    func testHasDrumPartsIgnoresUnmapped() {
        let pianoOnly = [MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 1)]
        XCTAssertFalse(MXDrumPart.hasDrumParts(pianoOnly))

        let mixed = pianoOnly + [MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25)]
        XCTAssertTrue(MXDrumPart.hasDrumParts(mixed))
    }

    func testPadGridCoversEightPadsAndAllParts() {
        let pads = MXDrumPart.allPads
        XCTAssertEqual(pads.count, 8)
        XCTAssertEqual(Set(pads.map(\.note)).count, 8)
        let parts = Set(pads.map(\.part))
        XCTAssertEqual(parts, Set(MXDrumPart.allCases))
    }

    func testLaneOrderIsKickToRide() {
        let ordered = MXDrumPart.allCases.sorted()
        XCTAssertEqual(ordered.map(\.shortLabel), ["Kick", "Snare", "Hats", "Toms", "Perc", "Ride"])
    }
}
