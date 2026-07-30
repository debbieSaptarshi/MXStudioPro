import Foundation

/// Musical-grid quantize for MIDI note starts (GarageBand / BandLab Quantize lite).
///
/// Matches arrangement 16th-note snap: `resolution = 0.25` quarter-note beats.
/// Live pad/key feel stays free; apply only when committing a performance clip.
public enum MXMIDIQuantize: Sendable {
    /// Sixteenth-note grid in quarter-note beats (same as Studio `snapBeat`).
    public static let sixteenth: Double = 0.25

    /// Snap a beat to the nearest multiple of `resolution`.
    /// Non-positive `resolution` returns `max(0, beat)` unchanged.
    public static func snapBeat(
        _ beat: Double,
        resolution: Double = sixteenth
    ) -> Double {
        guard resolution > 0 else { return max(0, beat) }
        return (beat / resolution).rounded() * resolution
    }

    /// Snap each note’s `startBeat`; keep `lengthBeats`, pitch, velocity, and id.
    /// Ends move with the start (length preserved). Starts are clamped to ≥ 0.
    public static func quantizeStarts(
        _ notes: [MXMIDINote],
        resolution: Double = sixteenth
    ) -> [MXMIDINote] {
        notes.map { note in
            MXMIDINote(
                id: note.id,
                note: note.note,
                velocity: note.velocity,
                startBeat: max(0, snapBeat(note.startBeat, resolution: resolution)),
                lengthBeats: note.lengthBeats
            )
        }
    }
}
