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

    // MARK: - Week 57

    func testStepIndexAtBeatLoopsAcrossBars() {
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 0, bars: 1), 0)
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 0.24, bars: 1), 0)
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 0.25, bars: 1), 1)
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 3.99, bars: 1), 15)
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 4.0, bars: 1), 0) // wrap 1 bar
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 4.0, bars: 2), 16) // into bar 2
        XCTAssertEqual(MXDrumStepSequencer.stepIndex(atBeat: 8.0, bars: 2), 0)
        XCTAssertNil(MXDrumStepSequencer.stepIndex(atBeat: -1, bars: 1))
        XCTAssertNil(MXDrumStepSequencer.stepIndex(atBeat: .nan, bars: 1))
    }

    func testExtractAndReplaceBar() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 2)
        grid[0][0] = 100
        grid[1][16] = 80 // bar 2 snare
        let bar0 = MXDrumStepSequencer.extractBar(grid, barIndex: 0)
        XCTAssertEqual(bar0[0].count, 16)
        XCTAssertEqual(bar0[0][0], 100)
        XCTAssertEqual(bar0[1][0], 0)

        let bar1 = MXDrumStepSequencer.extractBar(grid, barIndex: 1)
        XCTAssertEqual(bar1[1][0], 80)

        let pasted = MXDrumStepSequencer.replacingBar(grid, barIndex: 1, with: bar0)
        XCTAssertEqual(pasted[0][16], 100)
        XCTAssertEqual(pasted[1][16], 0)

        let copied = MXDrumStepSequencer.copyingBar(grid, from: 1, to: 0)
        XCTAssertEqual(copied[1][0], 80)
        XCTAssertEqual(copied[0][0], 0)

        let oob = MXDrumStepSequencer.extractBar(grid, barIndex: 9)
        XCTAssertFalse(MXDrumStepSequencer.hasHits(oob))
    }

    func testPatternLibraryPresets() {
        let four = MXDrumStepSequencer.pattern(.fourOnFloor, bars: 1)
        XCTAssertTrue(MXDrumStepSequencer.hasHits(four))
        XCTAssertEqual(four[0][0], 110)
        XCTAssertEqual(four[0][4], 110)
        XCTAssertEqual(four[1][4], 100)
        XCTAssertEqual(four[2][0], 80)

        let twoBars = MXDrumStepSequencer.pattern(.fourOnFloor, bars: 2)
        XCTAssertEqual(twoBars[0].count, 32)
        XCTAssertEqual(twoBars[0][16], 110)
        XCTAssertEqual(twoBars[1][20], 100)

        let boom = MXDrumStepSequencer.patternMotif(.boomBap)
        XCTAssertEqual(boom[0][0], 115)
        XCTAssertEqual(boom[1][4], 110)

        let half = MXDrumStepSequencer.patternMotif(.halfTime)
        XCTAssertEqual(half[0][0], 120)
        XCTAssertEqual(half[1][8], 110)

        let disco = MXDrumStepSequencer.patternMotif(.discoHats)
        XCTAssertEqual(disco[2][1], 90)
        XCTAssertEqual(MXDrumStepSequencer.PatternPreset.allCases.count, 4)
    }

    // MARK: - Week 61

    func testStepSwingDelaysOddSixteenthsIndependently() {
        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
        grid[0][0] = 100 // even — straight
        grid[0][1] = 100 // odd — swung
        grid[1][4] = 90  // even

        let straight = MXDrumStepSequencer.notes(fromVelocityGrid: grid, swing: 0)
        XCTAssertEqual(straight.map(\.startBeat).sorted(), [0, 0.25, 1.0])

        let swung = MXDrumStepSequencer.notes(fromVelocityGrid: grid, swing: 1)
        let starts = swung.map(\.startBeat).sorted()
        XCTAssertEqual(starts[0], 0, accuracy: 1e-9)
        // Odd 16th delayed by swing * 0.25 * 0.5 = 0.125 → 0.375
        XCTAssertEqual(starts[1], 0.375, accuracy: 1e-9)
        XCTAssertEqual(starts[2], 1.0, accuracy: 1e-9)

        // Default swing is straight (API default).
        let defaulted = MXDrumStepSequencer.notes(fromVelocityGrid: grid)
        XCTAssertEqual(defaulted.map(\.startBeat).sorted(), straight.map(\.startBeat).sorted())
    }

    func testPatternSlotBankSaveRecallClear() {
        var bank = MXDrumStepSequencer.PatternSlotBank()
        XCTAssertEqual(bank.slots.count, 4)
        XCTAssertNil(bank.slot(at: 0))

        var grid = MXDrumStepSequencer.emptyVelocityGrid(bars: 2)
        grid[0][0] = 110
        grid[1][16] = 80
        bank = bank.saving(grid, bars: 2, at: 0)
        XCTAssertEqual(bank.slot(at: 0)?.bars, 2)
        XCTAssertEqual(bank.slot(at: 0)?.velocityGrid[0][0], 110)
        XCTAssertEqual(bank.slot(at: 0)?.velocityGrid[1][16], 80)
        XCTAssertTrue(bank.slot(at: 0)?.hasHits == true)

        // Empty grid clears the slot.
        bank = bank.saving(MXDrumStepSequencer.emptyVelocityGrid(bars: 1), bars: 1, at: 0)
        XCTAssertNil(bank.slot(at: 0))

        bank = bank.saving(grid, bars: 2, at: 2)
        XCTAssertNotNil(bank.slot(at: 2))
        bank = bank.clearing(at: 2)
        XCTAssertNil(bank.slot(at: 2))

        // Out of range is a no-op.
        let unchanged = bank.saving(grid, bars: 1, at: 9)
        XCTAssertEqual(unchanged, bank)

        XCTAssertEqual(MXDrumStepSequencer.patternSlotLabels, ["A", "B", "C", "D"])

        // Codable round-trip.
        let encoded = try! JSONEncoder().encode(bank.saving(grid, bars: 2, at: 1))
        let decoded = try! JSONDecoder().decode(MXDrumStepSequencer.PatternSlotBank.self, from: encoded)
        XCTAssertEqual(decoded.slot(at: 1)?.velocityGrid[0][0], 110)
        XCTAssertEqual(decoded.slot(at: 1)?.bars, 2)
    }
}
