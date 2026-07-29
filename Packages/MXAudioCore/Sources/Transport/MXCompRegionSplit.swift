import Foundation

/// Logic-style punch comps: split an active take around a punch region and
/// suggest short abut crossfades (GarageBand / BandLab playlist-comp lite).
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

        var before: Piece?
        var after: Piece?
        var punchFadeIn: Double = 0
        var punchFadeOut: Double = 0

        let beforeSeconds = secondsBetween(a0, cut0)
        if beforeSeconds >= minFragmentSeconds, cut0 > a0 {
            let dur = beforeSeconds
            before = Piece(
                startBeat: a0,
                lengthBeats: cut0 - a0,
                sourceOffsetSeconds: sibling.sourceOffsetSeconds,
                sourceDurationSeconds: dur,
                fadeInSeconds: min(sibling.fadeInSeconds, dur),
                fadeOutSeconds: min(crossfadeSeconds, dur)
            )
            punchFadeIn = crossfadeSeconds
        }

        let afterSeconds = secondsBetween(cut1, a1)
        if afterSeconds >= minFragmentSeconds, a1 > cut1 {
            let dur = afterSeconds
            after = Piece(
                startBeat: cut1,
                lengthBeats: a1 - cut1,
                sourceOffsetSeconds: sibling.sourceOffsetSeconds + secondsBetween(a0, cut1),
                sourceDurationSeconds: dur,
                fadeInSeconds: min(crossfadeSeconds, dur),
                fadeOutSeconds: min(sibling.fadeOutSeconds, dur)
            )
            punchFadeOut = crossfadeSeconds
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
