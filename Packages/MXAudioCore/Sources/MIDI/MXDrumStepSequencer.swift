import Foundation

/// BandLab / FL Mobile–style drum step grid ↔ MIDI notes (Weeks 49 / 53).
///
/// Grid cells store velocity: `0` = off, `1…127` = on. One bar = 16 sixteenths;
/// patterns span `bars` (1…4). Step `i` lands at `i * 0.25` beats.
/// Rows map to kit parts via each part’s primary pad note (Kick/Snare/Hats…).
public enum MXDrumStepSequencer: Sendable {
    /// Steps per bar (16th-note grid).
    public static let stepsPerBar: Int = 16
    /// Alias for callers that still say “stepCount” for one bar.
    public static let stepCount: Int = stepsPerBar
    /// Supported pattern length in bars (BandLab multi-bar lite).
    public static let minBars: Int = 1
    public static let maxBars: Int = 4
    /// Quarter-note beats per step (1/16 note).
    public static let stepBeats: Double = 0.25
    /// Default hit length so one-shots don’t hang into the next step.
    public static let defaultHitLengthBeats: Double = 0.2
    /// Default velocity for toggled steps (BandLab default pad feel).
    public static let defaultVelocity: UInt8 = 100

    /// Ordered kit rows shown in the step sequencer (Kick → Ride).
    public static var rowParts: [MXDrumPart] { MXDrumPart.allCases.sorted() }

    /// Clamp bar count into the supported range.
    public static func clampBars(_ bars: Int) -> Int {
        min(maxBars, max(minBars, bars))
    }

    /// Total step columns for a pattern length.
    public static func stepCount(bars: Int) -> Int {
        clampBars(bars) * stepsPerBar
    }

    /// Pattern length in quarter-note beats.
    public static func patternLengthBeats(bars: Int = 1) -> Double {
        Double(stepCount(bars: bars)) * stepBeats
    }

    /// One-bar pattern length (Week 49 compatibility).
    public static var patternLengthBeats: Double {
        patternLengthBeats(bars: 1)
    }

    /// Primary MIDI note for a kit part row (first pad mapped to that part).
    public static func primaryNote(for part: MXDrumPart) -> UInt8 {
        if let pad = MXDrumPart.allPads.first(where: { $0.part == part }) {
            return pad.note
        }
        return part.midiNotes.min() ?? 36
    }

    /// Empty velocity grid — all zeros. Shape: `rowParts.count` × `stepCount(bars:)`.
    public static func emptyVelocityGrid(bars: Int = 1) -> [[UInt8]] {
        let cols = stepCount(bars: bars)
        return rowParts.map { _ in Array(repeating: UInt8(0), count: cols) }
    }

    /// Empty boolean grid (Week 49 compatibility) — one bar.
    public static func emptyGrid() -> [[Bool]] {
        boolGrid(from: emptyVelocityGrid(bars: 1))
    }

    /// Convert a velocity grid into clip-local MIDI notes.
    ///
    /// - Parameters:
    ///   - velocityGrid: `rowParts.count` rows × `stepCount(bars:)` columns.
    ///     Extra rows/cols ignored; missing cells treated as off.
    ///   - bars: Pattern length used when the grid is shorter than expected
    ///     (pads missing columns with silence conceptually by not emitting notes).
    ///   - hitLengthBeats: Note length (clamped ≥ 0.0625).
    public static func notes(
        fromVelocityGrid velocityGrid: [[UInt8]],
        bars: Int = 1,
        hitLengthBeats: Double = defaultHitLengthBeats
    ) -> [MXMIDINote] {
        let parts = rowParts
        let cols = stepCount(bars: bars)
        let length = max(0.0625, hitLengthBeats)
        var result: [MXMIDINote] = []
        result.reserveCapacity(cols)
        for (row, part) in parts.enumerated() {
            guard row < velocityGrid.count else { break }
            let note = primaryNote(for: part)
            let steps = velocityGrid[row]
            for step in 0..<cols {
                guard step < steps.count else { break }
                let vel = steps[step]
                guard vel > 0 else { continue }
                result.append(
                    MXMIDINote(
                        note: note,
                        velocity: min(127, max(1, vel)),
                        startBeat: Double(step) * stepBeats,
                        lengthBeats: length
                    )
                )
            }
        }
        return result
    }

    /// Week 49 boolean-grid → notes (uniform velocity).
    public static func notes(
        from grid: [[Bool]],
        velocity: UInt8 = defaultVelocity,
        hitLengthBeats: Double = defaultHitLengthBeats
    ) -> [MXMIDINote] {
        notes(
            fromVelocityGrid: velocityGrid(fromBool: grid, velocity: velocity),
            bars: 1,
            hitLengthBeats: hitLengthBeats
        )
    }

    /// Project MIDI notes onto a velocity grid (nearest 16th; same pitch family as row).
    ///
    /// When multiple notes land on the same cell, the louder velocity wins.
    /// Notes outside `[0, stepCount(bars:))` or unmapped pitches are dropped.
    public static func velocityGrid(
        from notes: [MXMIDINote],
        bars: Int = 1
    ) -> [[UInt8]] {
        var grid = emptyVelocityGrid(bars: bars)
        let parts = rowParts
        let cols = stepCount(bars: bars)
        for note in notes {
            guard let part = MXDrumPart.part(forNote: note.note),
                  let row = parts.firstIndex(of: part)
            else { continue }
            let step = Int((note.startBeat / stepBeats).rounded())
            guard step >= 0, step < cols else { continue }
            let vel = min(127, max(1, note.velocity))
            grid[row][step] = max(grid[row][step], vel)
        }
        return grid
    }

    /// Project MIDI notes onto a boolean step grid (Week 49 compatibility).
    public static func grid(from notes: [MXMIDINote]) -> [[Bool]] {
        boolGrid(from: velocityGrid(from: notes, bars: 1))
    }

    /// Smallest bar count (1…maxBars) that fits every kit-mapped note, or `fallback`
    /// when the pattern is empty / exceeds maxBars (clamped).
    public static func inferredBarCount(
        from notes: [MXMIDINote],
        maxBars: Int = maxBars,
        fallback: Int = 1
    ) -> Int {
        let kitNotes = notes.filter { MXDrumPart.part(forNote: $0.note) != nil }
        guard let lastBeat = kitNotes.map(\.startBeat).max() else {
            return clampBars(fallback)
        }
        let lastStep = Int((lastBeat / stepBeats).rounded())
        guard lastStep >= 0 else { return clampBars(fallback) }
        let needed = (lastStep / stepsPerBar) + 1
        return min(clampBars(maxBars), max(minBars, needed))
    }

    /// Toggle one cell; off → `defaultVelocity`, on → off. Returns a new grid.
    public static func toggling(
        _ velocityGrid: [[UInt8]],
        row: Int,
        step: Int,
        defaultVelocity: UInt8 = defaultVelocity
    ) -> [[UInt8]] {
        var next = normalize(velocityGrid, bars: inferredBars(fromColumnCount: velocityGrid.first?.count ?? stepsPerBar))
        guard row >= 0, row < next.count else { return next }
        guard step >= 0, step < next[row].count else { return next }
        if next[row][step] > 0 {
            next[row][step] = 0
        } else {
            next[row][step] = min(127, max(1, defaultVelocity))
        }
        return next
    }

    /// Week 49 boolean toggle.
    public static func toggling(
        _ grid: [[Bool]],
        row: Int,
        step: Int
    ) -> [[Bool]] {
        let vel = toggling(velocityGrid(fromBool: grid), row: row, step: step)
        return boolGrid(from: vel)
    }

    /// Set absolute velocity for a cell (`0` clears). Returns a new grid.
    public static func settingVelocity(
        _ velocityGrid: [[UInt8]],
        row: Int,
        step: Int,
        velocity: UInt8
    ) -> [[UInt8]] {
        var next = normalize(velocityGrid, bars: inferredBars(fromColumnCount: velocityGrid.first?.count ?? stepsPerBar))
        guard row >= 0, row < next.count else { return next }
        guard step >= 0, step < next[row].count else { return next }
        next[row][step] = velocity == 0 ? 0 : min(127, max(1, velocity))
        return next
    }

    /// Resize a velocity grid to a new bar count (truncate or pad with silence).
    public static func resizing(
        _ velocityGrid: [[UInt8]],
        toBars bars: Int
    ) -> [[UInt8]] {
        let cols = stepCount(bars: bars)
        let parts = rowParts
        return (0..<parts.count).map { row in
            var rowSteps = row < velocityGrid.count ? velocityGrid[row] : []
            if rowSteps.count > cols {
                rowSteps = Array(rowSteps.prefix(cols))
            } else if rowSteps.count < cols {
                rowSteps.append(contentsOf: Array(repeating: UInt8(0), count: cols - rowSteps.count))
            }
            return rowSteps
        }
    }

    /// True when any step has velocity &gt; 0.
    public static func hasHits(_ velocityGrid: [[UInt8]]) -> Bool {
        velocityGrid.contains { row in row.contains { $0 > 0 } }
    }

    /// Boolean overload (Week 49).
    public static func hasHits(_ grid: [[Bool]]) -> Bool {
        grid.contains { row in row.contains(true) }
    }

    // MARK: - Helpers

    public static func boolGrid(from velocityGrid: [[UInt8]]) -> [[Bool]] {
        velocityGrid.map { row in row.map { $0 > 0 } }
    }

    public static func velocityGrid(
        fromBool grid: [[Bool]],
        velocity: UInt8 = defaultVelocity
    ) -> [[UInt8]] {
        let vel = min(127, max(1, velocity))
        return grid.map { row in row.map { $0 ? vel : 0 } }
    }

    private static func inferredBars(fromColumnCount cols: Int) -> Int {
        guard cols > 0 else { return 1 }
        let raw = Int(ceil(Double(cols) / Double(stepsPerBar)))
        return clampBars(raw)
    }

    private static func normalize(_ velocityGrid: [[UInt8]], bars: Int) -> [[UInt8]] {
        resizing(velocityGrid, toBars: bars)
    }
}
