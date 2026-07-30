import Foundation

/// BandLab-style 16-step drum grid ↔ MIDI notes (Week 49).
///
/// One bar of sixteenth notes: step `i` lands at `i * 0.25` beats.
/// Rows map to kit parts via each part’s primary pad note (Kick/Snare/Hats…).
public enum MXDrumStepSequencer: Sendable {
    /// Steps per bar (16th-note grid).
    public static let stepCount: Int = 16
    /// Quarter-note beats per step (1/16 note).
    public static let stepBeats: Double = 0.25
    /// Default hit length so one-shots don’t hang into the next step.
    public static let defaultHitLengthBeats: Double = 0.2
    /// Default velocity for toggled steps (BandLab default pad feel).
    public static let defaultVelocity: UInt8 = 100

    /// Ordered kit rows shown in the step sequencer (Kick → Ride).
    public static var rowParts: [MXDrumPart] { MXDrumPart.allCases.sorted() }

    /// Primary MIDI note for a kit part row (first pad mapped to that part).
    public static func primaryNote(for part: MXDrumPart) -> UInt8 {
        if let pad = MXDrumPart.allPads.first(where: { $0.part == part }) {
            return pad.note
        }
        return part.midiNotes.min() ?? 36
    }

    /// Empty `[part][step]` grid — all false.
    public static func emptyGrid() -> [[Bool]] {
        rowParts.map { _ in Array(repeating: false, count: stepCount) }
    }

    /// Convert a boolean grid into clip-local MIDI notes.
    ///
    /// - Parameters:
    ///   - grid: `rowParts.count` rows × `stepCount` columns. Extra rows/cols ignored;
    ///     missing cells treated as off.
    ///   - velocity: Hit velocity for active steps.
    ///   - hitLengthBeats: Note length (clamped ≥ 0.0625).
    public static func notes(
        from grid: [[Bool]],
        velocity: UInt8 = defaultVelocity,
        hitLengthBeats: Double = defaultHitLengthBeats
    ) -> [MXMIDINote] {
        let parts = rowParts
        let length = max(0.0625, hitLengthBeats)
        var result: [MXMIDINote] = []
        result.reserveCapacity(stepCount)
        for (row, part) in parts.enumerated() {
            guard row < grid.count else { break }
            let note = primaryNote(for: part)
            let steps = grid[row]
            for step in 0..<stepCount {
                guard step < steps.count, steps[step] else { continue }
                result.append(
                    MXMIDINote(
                        note: note,
                        velocity: max(1, velocity),
                        startBeat: Double(step) * stepBeats,
                        lengthBeats: length
                    )
                )
            }
        }
        return result
    }

    /// Project MIDI notes onto a step grid (nearest 16th; same pitch family as row).
    ///
    /// Notes outside `[0, stepCount)` steps or unmapped pitches are dropped.
    public static func grid(from notes: [MXMIDINote]) -> [[Bool]] {
        var grid = emptyGrid()
        let parts = rowParts
        for note in notes {
            guard let part = MXDrumPart.part(forNote: note.note),
                  let row = parts.firstIndex(of: part)
            else { continue }
            let step = Int((note.startBeat / stepBeats).rounded())
            guard step >= 0, step < stepCount else { continue }
            grid[row][step] = true
        }
        return grid
    }

    /// Toggle one cell; returns a new grid (copy-on-write friendly).
    public static func toggling(
        _ grid: [[Bool]],
        row: Int,
        step: Int
    ) -> [[Bool]] {
        var next = grid
        while next.count < rowParts.count {
            next.append(Array(repeating: false, count: stepCount))
        }
        guard row >= 0, row < next.count else { return next }
        var steps = next[row]
        while steps.count < stepCount {
            steps.append(false)
        }
        guard step >= 0, step < stepCount else {
            next[row] = steps
            return next
        }
        steps[step].toggle()
        next[row] = Array(steps.prefix(stepCount))
        return next
    }

    /// Pattern length in quarter-note beats (always one bar for MVP).
    public static var patternLengthBeats: Double {
        Double(stepCount) * stepBeats
    }

    /// True when any step is active.
    public static func hasHits(_ grid: [[Bool]]) -> Bool {
        grid.contains { row in row.contains(true) }
    }
}
