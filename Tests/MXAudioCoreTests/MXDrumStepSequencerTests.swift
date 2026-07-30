import XCTest
@testable import MXAudioCore

final class MXDrumStepSequencerTests: XCTestCase {
    func testEmptyVelocityGridHasNoHits() {
        let grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        XCTAssertEqual(grid.count, MXDrumPart.allCases.count)
        XCTAssertTrue(grid.allSatisfy { $0.count == 16 })
        XCTAssertFalse(MXDrumStepSequencer.hasHits(grid))
        XCTAssertTrue(MXDrumStepSequencer.notes(fromVelocityGrid: grid).isEmpty)
    }

    func testEmptyBoolGridCompatibility() {
        let grid = MXDrumStepSequencer.emptyGrid()
        XCTAssertFalse(MXDrumStepSequencer.hasHits(grid))
        XCTAssertTrue(MXDrumStepSequencer.notes(from: grid).isEmpty)
    }

    func testNotesFromFourOnTheFloor() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        // Kick on beats 1–4 (steps 0, 4, 8, 12)
        for step in [0, 4, 8, 12] {
            grid[0][step] = 100
        }
        // Snare on 2 and 4 (steps 4, 12) — row 1
        grid[1][4] = 110
        grid[1][12] = 90

        let notes = MXDrumStepSequencer.notes(fromVelocityGrid: grid)
        XCTAssertEqual(notes.count, 6)
        XCTAssertEqual(notes.filter { $0.note == 36 }.count, 4)
        XCTAssertEqual(notes.filter { $0.note == 38 }.count, 2)
        XCTAssertEqual(notes.map(\.startBeat).sorted(), [0, 1, 1, 2, 3, 3])
        XCTAssertTrue(notes.allSatisfy { abs($0.lengthBeats - 0.2) < 1e-9 })
        XCTAssertEqual(notes.first { $0.note == 38 && abs($0.startBeat - 1) < 1e-9 }?.velocity, 110)
        XCTAssertEqual(notes.first { $0.note == 38 && abs($0.startBeat - 3) < 1e-9 }?.velocity, 90)
        XCTAssertEqual(MXDrumStepSequencer.patternLengthBeats(bars: 1), 4.0, accuracy: 1e-9)
    }

    func testVelocityGridRoundTripPreservesVelocity() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        grid[0][0] = 64
        grid[2][2] = 127
        grid[5][15] = 40
        let notes = MXDrumStepSequencer.notes(fromVelocityGrid: grid)
        let back = MXDrumStepSequencer.velocityGrid(from: notes, bars: 1)
        XCTAssertEqual(back, grid)
    }

    func testMultiBarRoundTrip() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 2)
        XCTAssertEqual(grid[0].count, 32)
        grid[0][0] = 100
        grid[1][16] = 80 // bar 2 beat 1 snare
        grid[2][31] = 70
        let notes = MXDrumStepSequencer.notes(fromVelocityGrid: grid, bars: 2)
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(MXDrumStepSequencer.patternLengthBeats(bars: 2), 8.0, accuracy: 1e-9)
        let back = MXDrumStepSequencer.velocityGrid(from: notes, bars: 2)
        XCTAssertEqual(back, grid)
        XCTAssertEqual(MXDrumStepSequencer.inferredBarCount(from: notes), 2)
    }

    func testInferredBarCountAndResize() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0, lengthBeats: 0.2),
            MXMIDINote(note: 38, velocity: 100, startBeat: 7.75, lengthBeats: 0.2), // step 31
        ]
        XCTAssertEqual(MXDrumStepSequencer.inferredBarCount(from: notes), 2)

        var oneBar = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        oneBar[0][0] = 100
        let twoBars = MXDrumStepSequencer.resizing(oneBar, toBars: 2)
        XCTAssertEqual(twoBars[0].count, 32)
        XCTAssertEqual(twoBars[0][0], 100)
        XCTAssertEqual(twoBars[0][16], 0)

        let truncated = MXDrumStepSequencer.resizing(twoBars, toBars: 1)
        XCTAssertEqual(truncated[0].count, 16)
        XCTAssertEqual(truncated[0][0], 100)
    }

    func testToggleAndSettingVelocity() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        grid = MXDrumStepSequencer.toggling(grid, row: 0, step: 3)
        XCTAssertEqual(grid[0][3], MXDrumStepSequencer.defaultVelocity)
        grid = MXDrumStepSequencer.settingVelocity(grid, row: 0, step: 3, velocity: 40)
        XCTAssertEqual(grid[0][3], 40)
        grid = MXDrumStepSequencer.toggling(grid, row: 0, step: 3)
        XCTAssertEqual(grid[0][3], 0)

        let unchanged = MXDrumStepSequencer.toggling(grid, row: -1, step: 0)
        XCTAssertEqual(unchanged, grid)
        let unchangedStep = MXDrumStepSequencer.settingVelocity(grid, row: 0, step: 99, velocity: 50)
        XCTAssertEqual(unchangedStep, grid)
    }

    func testVelocityGridDropsUnmappedAndOutOfPatternNotes() {
        let notes = [
            MXMIDINote(note: 36, velocity: 100, startBeat: 0.1, lengthBeats: 0.2), // → step 0
            MXMIDINote(note: 60, velocity: 100, startBeat: 1, lengthBeats: 0.2),   // piano — drop
            MXMIDINote(note: 38, velocity: 100, startBeat: 5.0, lengthBeats: 0.2), // past 1 bar — drop
        ]
        let grid = MXDrumStepSequencer.velocityGrid(from: notes, bars: 1)
        XCTAssertEqual(grid[0][0], 100)
        XCTAssertEqual(grid.flatMap { $0 }.filter { $0 > 0 }.count, 1)
    }

    func testLouderVelocityWinsOnSameCell() {
        let notes = [
            MXMIDINote(note: 36, velocity: 40, startBeat: 0, lengthBeats: 0.2),
            MXMIDINote(note: 36, velocity: 110, startBeat: 0.02, lengthBeats: 0.2), // same step
        ]
        let grid = MXDrumStepSequencer.velocityGrid(from: notes, bars: 1)
        XCTAssertEqual(grid[0][0], 110)
    }

    func testPrimaryNotesMatchPadGrid() {
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .kick), 36)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .snare), 38)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .hats), 42)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .toms), 45)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .perc), 37)
        XCTAssertEqual(MXDrumStepSequencer.primaryNote(for: .ride), 51)
    }

    func testClampBars() {
        XCTAssertEqual(MXDrumStepSequencer.clampBars(0), 1)
        XCTAssertEqual(MXDrumStepSequencer.clampBars(3), 3)
        XCTAssertEqual(MXDrumStepSequencer.clampBars(9), 4)
    }
}
