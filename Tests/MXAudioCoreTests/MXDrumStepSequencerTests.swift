import XCTest
@testable import MXAudioCore

final class MXDrumStepSequencerTests: XCTestCase {
    func testEmptyGridHasNoHits() {
        let grid = MXDrumStepSequencer.emptyGrid()
        XCTAssertEqual(grid.count, MXDrumPart.allCases.count)
        XCTAssertTrue(grid.allSatisfy { $0.count == 16 })
        XCTAssertFalse(MXDrumStepSequencer.hasHits(grid))
        XCTAssertTrue(MXDrumStepSequencer.notes(from: grid).isEmpty)
    }

    func testNotesFromFourOnTheFloor() {
        var grid = MXDrumStepSequencer.emptyGrid()
        // Kick on beats 1–4 (steps 0, 4, 8, 12)
        for step in [0, 4, 8, 12] {
            grid[0][step] = true
        }
        // Snare on 2 and 4 (steps 4, 12) — row 1
        grid[1][4] = true
        grid[1][12] = true

        let notes = MXDrumStepSequencer.notes(from: grid)
        XCTAssertEqual(notes.count, 6)
        XCTAssertEqual(notes.filter { $0.note == 36 }.count, 4)
        XCTAssertEqual(notes.filter { $0.note == 38 }.count, 2)
        XCTAssertEqual(notes.map(\.startBeat).sorted(), [0, 1, 1, 2, 3, 3])
        XCTAssertTrue(notes.allSatisfy { abs($0.lengthBeats - 0.2) < 1e-9 })
        XCTAssertEqual(MXDrumStepSequencer.patternLengthBeats, 4.0, accuracy: 1e-9)
    }

    func testGridRoundTrip() {
        var grid = MXDrumStepSequencer.emptyGrid()
        grid[0][0] = true
        grid[2][2] = true
        grid[5][15] = true
        let notes = MXDrumStepSequencer.notes(from: grid)
        let back = MXDrumStepSequencer.grid(from: notes)
        XCTAssertEqual(back, grid)
    }

    func testToggleAndOutOfRange() {
        var grid = MXDrumStepSequencer.emptyGrid()
        grid = MXDrumStepSequencer.toggling(grid, row: 0, step: 3)
        XCTAssertTrue(grid[0][3])
        grid = MXDrumStepSequencer.toggling(grid, row: 0, step: 3)
        XCTAssertFalse(grid[0][3])

        let unchanged = MXDrumStepSequencer.toggling(grid, row: -1, step: 0)
        XCTAssertEqual(unchanged, grid)
        let unchangedStep = MXDrumStepSequencer.toggling(grid, row: 0, step: 99)
        XCTAssertEqual(unchangedStep, grid)
    }

    func testGridDropsUnmappedAndOutOfBarNotes() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0.1, lengthBeats: 0.2), // → step 0
            MXMIDINote(note: 60, velocity: 100, startBeat: 1, lengthBeats: 0.2),   // piano — drop
            MXMIDINote(note: 38, velocity: 100, startBeat: 5.0, lengthBeats: 0.2), // past bar — drop
        ]
        let grid = MXDrumStepSequencer.grid(from: notes)
        XCTAssertTrue(grid[0][0])
        // Only kick step 0 should be on among kit rows.
        XCTAssertEqual(grid.flatMap { $0 }.filter { $0 }.count, 1)
    }

    func testPrimaryNotesMatchPadGrid() {
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .kick), 36)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .snare), 38)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .hats), 42)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .toms), 45)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .perc), 37)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .ride), 51)
    }
}
