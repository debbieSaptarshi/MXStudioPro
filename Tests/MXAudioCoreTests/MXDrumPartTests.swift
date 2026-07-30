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

    func testExcludingMutedDropsMutedPartsKeepsOthers() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
            MXMIDINote(note: 42, velocity: 80, startBeat: 0.5, lengthBeats: 0.125),
            MXMIDINote(note: 60, velocity: 70, startBeat: 2, lengthBeats: 1),
        ]
        let muted: Set<MXDrumPart> = [.kick, .hats]
        let audible = MXDrumPart.excludingMuted(notes, muted: muted)
        XCTAssertEqual(audible.map(\.note), [38, 60])

        let viaArray = notes.excludingMuted([.snare])
        XCTAssertEqual(viaArray.map(\.note), [36, 42, 60])
    }

    func testExcludingMutedEmptySetIsIdentity() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
        ]
        XCTAssertEqual(MXDrumPart.excludingMuted(notes, muted: []).map(\.note), [36, 38])
    }

    func testAudibleNotesSoloIsolatesParts() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
            MXMIDINote(note: 42, velocity: 80, startBeat: 0.5, lengthBeats: 0.125),
            MXMIDINote(note: 60, velocity: 70, startBeat: 2, lengthBeats: 1),
        ]
        let solo: Set<MXDrumPart> = [.snare]
        let audible = MXDrumPart.audibleNotes(notes, muted: [], soloed: solo)
        XCTAssertEqual(audible.map(\.note), [38])
    }

    func testAudibleNotesMuteWinsOverSolo() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
        ]
        let audible = MXDrumPart.audibleNotes(
            notes,
            muted: [.kick],
            soloed: [.kick, .snare]
        )
        XCTAssertEqual(audible.map(\.note), [38])
    }

    func testAudibleNotesEmptySoloIsMuteOnly() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.25),
            MXMIDINote(note: 38, velocity: 90, startBeat: 1, lengthBeats: 0.25),
            MXMIDINote(note: 60, velocity: 70, startBeat: 2, lengthBeats: 1),
        ]
        let audible = notes.audibleDrumNotes(muted: [.snare], soloed: [])
        XCTAssertEqual(audible.map(\.note), [36, 60])
    }

    func testMutedPartsFromRawValuesIgnoresUnknown() {
        let set = MXDrumPart.mutedParts(fromRawValues: ["kick", "nope", "ride"])
        XCTAssertEqual(set, [.kick, .ride])
    }

    func testWriteSilenceWAVProducesRIFF() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mx_silence_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try MXMIDIClipRenderer.writeSilenceWAV(durationSeconds: 0.2, to: url, sampleRate: 48_000)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
    }
}
