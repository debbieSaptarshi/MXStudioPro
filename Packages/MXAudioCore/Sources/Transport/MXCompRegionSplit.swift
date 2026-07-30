import Foundation

/// Logic / Pro Tools style punch comps: split an active take around a punch
/// region with short overlapping equal-power crossfades (not abut dips).
public enum MXCompRegionSplit: Sendable {

    /// Default click-guard crossfade at punch seams (~12 ms).
    public static let crossfadeSeconds: Double = 0.012
    /// Discard fragments shorter than `MXClip`’s 50 ms duration floor so a
    /// save/reload cannot inflate a tiny piece and over-read the audio file.
    public static let minFragmentSeconds: Double = 0.05

    public struct SourceClip: Equatable, Sendable {
        public var startBeat: Double
        public var lengthBeats: Double
        public var sourceOffsetSeconds: Double
        public var sourceDurationSeconds: Double?
        public var fadeInSeconds: Double
        public var fadeOutSeconds: Double

        public init(
            startBeat: Double,
            lengthBeats: Double,
            sourceOffsetSeconds: Double,
            sourceDurationSeconds: Double?,
            fadeInSeconds: Double = 0,
            fadeOutSeconds: Double = 0
        ) {
            self.startBeat = startBeat
            self.lengthBeats = lengthBeats
            self.sourceOffsetSeconds = sourceOffsetSeconds
            self.sourceDurationSeconds = sourceDurationSeconds
            self.fadeInSeconds = fadeInSeconds
            self.fadeOutSeconds = fadeOutSeconds
        }

        public var endBeat: Double { startBeat + lengthBeats }
    }

    public struct Piece: Equatable, Sendable {
        public var startBeat: Double
        public var lengthBeats: Double
        public var sourceOffsetSeconds: Double
        public var sourceDurationSeconds: Double
        public var fadeInSeconds: Double
        public var fadeOutSeconds: Double
    }

    public struct Result: Equatable, Sendable {
        public var before: Piece?
        public var after: Piece?
        /// True when the original clip should be deactivated (no before piece kept).
        public var deactivateOriginal: Bool
        public var punchFadeInSeconds: Double
        public var punchFadeOutSeconds: Double
    }

    /// Split `sibling` around punch beat range `[punchStartBeat, punchEndBeat)`.
    ///
    /// Before/after pieces soft-overlap the punch by up to `crossfadeSeconds`
    /// so equal-power fades can sum without an abut dip.
    ///
    /// - Parameter secondsBetween: Tempo-map seconds from `fromBeat` to `toBeat` (`to >= from`).
    public static func split(
        sibling: SourceClip,
        punchStartBeat: Double,
        punchEndBeat: Double,
        secondsBetween: (_ fromBeat: Double, _ toBeat: Double) -> Double,
        crossfadeSeconds: Double = crossfadeSeconds,
        minFragmentSeconds: Double = minFragmentSeconds
    ) -> Result {
        let a0 = sibling.startBeat
        let a1 = sibling.endBeat
        let p0 = min(punchStartBeat, punchEndBeat)
        let p1 = max(punchStartBeat, punchEndBeat)

        // No overlap → leave original alone.
        guard a0 < p1 && p0 < a1, p1 > p0 else {
            return Result(
                before: nil,
                after: nil,
                deactivateOriginal: false,
                punchFadeInSeconds: 0,
                punchFadeOutSeconds: 0
            )
        }

        let cut0 = min(max(p0, a0), a1)
        let cut1 = min(max(p1, a0), a1)

        let beforeSeconds = secondsBetween(a0, cut0)
        let afterSeconds = secondsBetween(cut1, a1)
        let punchSec = secondsBetween(p0, p1)
        let punchBeats = p1 - p0

        let hasBefore = beforeSeconds >= minFragmentSeconds && cut0 > a0
        let hasAfter = afterSeconds >= minFragmentSeconds && a1 > cut1

        // Soft X-fade into the punch; if both seams exist, also bound by afterSeconds
        // and half the punch so before/after X-fades cannot collide mid-punch.
        var xfSec = 0.0
        var xfBeats = 0.0
        if punchSec > 0, hasBefore || hasAfter {
            xfSec = min(crossfadeSeconds, punchSec)
            if hasBefore {
                xfSec = min(xfSec, beforeSeconds)
            }
            if hasAfter {
                xfSec = min(xfSec, afterSeconds)
            }
            if hasBefore && hasAfter {
                xfSec = min(xfSec, punchSec / 2)
            }
            xfBeats = punchBeats * (xfSec / punchSec)

            // Cap: before must not extend past p1; after must not start before p0.
            if hasBefore {
                xfBeats = min(xfBeats, max(0, p1 - cut0))
            }
            if hasAfter {
                xfBeats = min(xfBeats, max(0, cut1 - p0))
            }
            if punchBeats > 0 {
                xfSec = punchSec * (xfBeats / punchBeats)
            }
        }

        var before: Piece?
        var after: Piece?
        var punchFadeIn: Double = 0
        var punchFadeOut: Double = 0

        if hasBefore {
            let dur = beforeSeconds + xfSec
            before = Piece(
                startBeat: a0,
                lengthBeats: (cut0 - a0) + xfBeats,
                sourceOffsetSeconds: sibling.sourceOffsetSeconds,
                sourceDurationSeconds: dur,
                fadeInSeconds: min(sibling.fadeInSeconds, dur),
                fadeOutSeconds: xfSec
            )
            punchFadeIn = xfSec
        }

        if hasAfter {
            let dur = afterSeconds + xfSec
            let rawOffset = sibling.sourceOffsetSeconds + secondsBetween(a0, cut1) - xfSec
            after = Piece(
                startBeat: cut1 - xfBeats,
                lengthBeats: (a1 - cut1) + xfBeats,
                sourceOffsetSeconds: max(0, rawOffset),
                sourceDurationSeconds: dur,
                fadeInSeconds: xfSec,
                fadeOutSeconds: min(sibling.fadeOutSeconds, dur)
            )
            punchFadeOut = xfSec
        }

        // Keep original as the before piece when present; otherwise deactivate it.
        let deactivateOriginal = before == nil
        return Result(
            before: before,
            after: after,
            deactivateOriginal: deactivateOriginal,
            punchFadeInSeconds: punchFadeIn,
            punchFadeOutSeconds: punchFadeOut
        )
    }
}
