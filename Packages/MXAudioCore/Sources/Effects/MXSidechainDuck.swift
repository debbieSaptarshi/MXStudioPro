import Foundation

/// Sidechain "lite" ducking math (Week 63 — Ableton / GarageBand pump).
///
/// Apple's `DynamicsProcessor` AU is self-keyed only (no external key input), so
/// a true kick→bass sidechain can't be built by feeding one track into another's
/// detector. Instead we model the classic pump as an *envelope duck*: sample the
/// most recent kick hit relative to the playhead and multiply a recovering gain
/// into the destination track's volume.
///
/// Pure + `Sendable` so it can be unit-tested and called from the mix apply
/// without touching AVAudioEngine.
public enum MXSidechainDuck: Sendable {

    /// Linear gain 0…1 at `timeSinceTrigger` seconds after a kick hit.
    ///
    /// The pump is modelled as an *instant duck* down to `1 − amount` at the hit,
    /// held for `attack` seconds, then a linear release back to unity over
    /// `release` seconds. This keeps the deepest duck aligned with the transient
    /// (what you hear/see in Ableton's sidechain meter) rather than ramping into
    /// it after the beat has passed.
    ///
    /// - Parameters:
    ///   - timeSinceTrigger: Seconds since the keyed kick (negative → before hit → unity).
    ///   - amount: Duck depth 0…1 (0 = no ducking, 1 = full mute at the hit).
    ///   - attack: Seconds the gain holds at the ducked floor before releasing.
    ///   - release: Seconds to recover from the floor back to unity.
    public static func gain(
        timeSinceTrigger: Double,
        amount: Double,
        attack: Double = 0.02,
        release: Double = 0.18
    ) -> Double {
        let depth = min(max(amount, 0), 1)
        guard depth > 0 else { return 1 }
        guard timeSinceTrigger >= 0 else { return 1 }

        let floor = 1 - depth
        let hold = max(0, attack)
        let rel = max(1e-6, release)

        if timeSinceTrigger <= hold { return floor }

        let releaseElapsed = timeSinceTrigger - hold
        if releaseElapsed >= rel { return 1 }
        // Linear recovery from floor → unity across the release window.
        return floor + depth * (releaseElapsed / rel)
    }

    /// Seconds since the most recent kick trigger at or before `playheadBeat`.
    ///
    /// Kick detection uses `MXDrumPart` (note 36 / `.kick`) with a raw note-36
    /// fallback. Returns `nil` when no kick precedes the playhead or `bpm` is
    /// non-positive.
    ///
    /// - Parameters:
    ///   - playheadBeat: Current playhead position in quarter-note beats.
    ///   - notes: Absolute-beat drum triggers `(startBeat, note)` to scan.
    ///   - bpm: Tempo used to convert the beat gap into seconds.
    public static func secondsSinceKick(
        playheadBeat: Double,
        notes: [(startBeat: Double, note: UInt8)],
        bpm: Double
    ) -> Double? {
        guard bpm > 0 else { return nil }

        var nearestKickBeat: Double?
        for trigger in notes where isKick(trigger.note) {
            guard trigger.startBeat <= playheadBeat + 1e-9 else { continue }
            if let current = nearestKickBeat {
                if trigger.startBeat > current { nearestKickBeat = trigger.startBeat }
            } else {
                nearestKickBeat = trigger.startBeat
            }
        }

        guard let kickBeat = nearestKickBeat else { return nil }
        let beatsSince = max(0, playheadBeat - kickBeat)
        return beatsSince * 60.0 / bpm
    }

    /// True when `note` maps to the kit's kick lane (or the raw GM kick, note 36).
    public static func isKick(_ note: UInt8) -> Bool {
        if let part = MXDrumPart.part(forNote: note) { return part == .kick }
        return note == 36
    }
}
