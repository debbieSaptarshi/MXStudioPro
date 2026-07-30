import Foundation

/// Musical-grid quantize for MIDI note starts (GarageBand / BandLab / Logic Quantize).
///
/// Matches arrangement 16th-note snap: `resolution = 0.25` quarter-note beats.
/// Live pad/key feel stays free; apply only when committing or re-quantizing a clip.
public enum MXMIDIQuantize: Sendable {
    /// Eighth-note grid in quarter-note beats.
    public static let eighth: Double = 0.5

    /// Eighth-note triplet grid (three notes per quarter) in quarter-note beats.
    public static let eighthTriplet: Double = 1.0 / 3.0

    /// Dotted eighth-note grid (⅜ note = ¾ beat) in quarter-note beats.
    public static let dottedEighth: Double = 0.75

    /// Sixteenth-note grid in quarter-note beats (same as Studio `snapBeat`).
    public static let sixteenth: Double = 0.25

    /// Sixteenth-note triplet grid (three notes per eighth) in quarter-note beats.
    public static let sixteenthTriplet: Double = 1.0 / 6.0

    /// Dotted sixteenth-note grid (³⁄₁₆ note = ⅜ beat) in quarter-note beats.
    public static let dottedSixteenth: Double = 0.375

    /// Thirty-second-note grid in quarter-note beats.
    public static let thirtySecond: Double = 0.125

    /// Snap a beat to the nearest multiple of `resolution`.
    /// Non-positive `resolution` returns `max(0, beat)` unchanged.
    public static func snapBeat(
        _ beat: Double,
        resolution: Double = sixteenth
    ) -> Double {
        guard resolution > 0 else { return max(0, beat) }
        return (beat / resolution).rounded() * resolution
    }

    /// Target grid position after optional swing (Logic-style off-beat delay).
    ///
    /// Odd 16th slots (1, 3, 5…) are delayed by `swing * resolution * 0.5`
    /// so `swing = 1` shifts by an eighth of a beat at 16th resolution.
    public static func swungGridBeat(
        _ beat: Double,
        resolution: Double = sixteenth,
        swing: Double = 0
    ) -> Double {
        guard resolution > 0 else { return max(0, beat) }
        var snapped = snapBeat(beat, resolution: resolution)
        let amount = min(1, max(0, swing))
        guard amount > 1e-9 else { return snapped }
        let index = Int((snapped / resolution).rounded())
        if index % 2 != 0 {
            snapped += amount * resolution * 0.5
        }
        return max(0, snapped)
    }

    /// Snap each note’s `startBeat`; keep `lengthBeats`, pitch, velocity, and id.
    ///
    /// - Parameters:
    ///   - strength: 0 = leave starts unchanged; 1 = full grid (GarageBand Strength).
    ///   - swing: 0…1 off-beat delay applied to the quantize target before blending.
    public static func quantizeStarts(
        _ notes: [MXMIDINote],
        resolution: Double = sixteenth,
        strength: Double = 1,
        swing: Double = 0
    ) -> [MXMIDINote] {
        let amount = min(1, max(0, strength))
        return notes.map { note in
            let target = swungGridBeat(note.startBeat, resolution: resolution, swing: swing)
            let start: Double
            if amount <= 1e-9 {
                start = max(0, note.startBeat)
            } else if amount >= 1 - 1e-9 {
                start = target
            } else {
                start = max(0, note.startBeat + (target - note.startBeat) * amount)
            }
            return MXMIDINote(
                id: note.id,
                note: note.note,
                velocity: note.velocity,
                startBeat: start,
                lengthBeats: note.lengthBeats
            )
        }
    }
}
