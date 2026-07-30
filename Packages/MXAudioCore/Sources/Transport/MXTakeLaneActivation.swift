import Foundation

/// Resolves which clips should stay active when the user picks a take lane
/// after punch comps have split a take into soft-overlapping before/after pieces.
public enum MXTakeLaneActivation: Sendable {

    public struct ClipRef: Equatable, Sendable {
        public var id: UUID
        public var takeIndex: Int
        public var startBeat: Double
        public var lengthBeats: Double

        public init(id: UUID, takeIndex: Int, startBeat: Double, lengthBeats: Double) {
            self.id = id
            self.takeIndex = takeIndex
            self.startBeat = startBeat
            self.lengthBeats = lengthBeats
        }

        public var endBeat: Double { startBeat + lengthBeats }
    }

    /// Returns the set of clip IDs that should be `isActive` after selecting `chosenID`.
    ///
    /// Rules (GarageBand / Logic take-lane lite):
    /// - Activate every clip that shares `takeIndex` with the chosen clip.
    /// - Deactivate other-take clips that hard-overlap any activated piece.
    /// - Soft overlaps (duration ≤ `softOverlapBeats`) are treated like abuts and
    ///   do not deactivate — they enable equal-power X-fade seams.
    /// - When the chosen take has multiple pieces, also deactivate others that
    ///   fall inside the take’s bounding beat range (covers the punch hole).
    /// - When the chosen take is a single piece, also deactivate pieces of a
    ///   multi-piece other take that abut or soft-overlap it (punch sandwiched).
    /// - Sequential single-piece takes that only abut / soft-overlap stay mutually active.
    public static func activeIDs(
        afterSelecting chosenID: UUID,
        clips: [ClipRef],
        abutEpsilon: Double = 1e-6,
        softOverlapBeats: Double = MXCrossfade.defaultSoftOverlapBeats
    ) -> Set<UUID> {
        guard let chosen = clips.first(where: { $0.id == chosenID }) else {
            return Set(clips.map(\.id))
        }
        let takeIndex = chosen.takeIndex
        let takePieces = clips.filter { $0.takeIndex == takeIndex }
        var active = Set(takePieces.map(\.id))

        let bboxStart = takePieces.map(\.startBeat).min() ?? chosen.startBeat
        let bboxEnd = takePieces.map(\.endBeat).max() ?? chosen.endBeat
        let multiPiece = takePieces.count > 1

        for other in clips where other.takeIndex != takeIndex {
            let hardOverlapsPiece = takePieces.contains {
                overlaps($0, other) && !softOverlaps($0, other, softOverlapBeats: softOverlapBeats, epsilon: abutEpsilon)
            }
            if hardOverlapsPiece {
                continue
            }
            if multiPiece, overlapsRange(other, start: bboxStart, end: bboxEnd) {
                continue
            }
            if !multiPiece {
                let otherTakePieces = clips.filter { $0.takeIndex == other.takeIndex }
                if otherTakePieces.count > 1,
                   takePieces.contains(where: {
                       abuts($0, other, epsilon: abutEpsilon)
                           || softOverlaps($0, other, softOverlapBeats: softOverlapBeats, epsilon: abutEpsilon)
                   }) {
                    continue
                }
            }
            active.insert(other.id)
        }
        return active
    }

    private static func overlapBeats(_ a: ClipRef, _ b: ClipRef) -> Double {
        max(0, min(a.endBeat, b.endBeat) - max(a.startBeat, b.startBeat))
    }

    private static func softOverlaps(
        _ a: ClipRef,
        _ b: ClipRef,
        softOverlapBeats: Double,
        epsilon: Double
    ) -> Bool {
        let o = overlapBeats(a, b)
        return o > 0 && o <= softOverlapBeats + epsilon
    }

    private static func overlaps(_ a: ClipRef, _ b: ClipRef) -> Bool {
        a.startBeat < b.endBeat && b.startBeat < a.endBeat
    }

    private static func overlapsRange(_ clip: ClipRef, start: Double, end: Double) -> Bool {
        clip.startBeat < end && start < clip.endBeat
    }

    private static func abuts(_ a: ClipRef, _ b: ClipRef, epsilon: Double) -> Bool {
        abs(a.endBeat - b.startBeat) < epsilon || abs(b.endBeat - a.startBeat) < epsilon
    }
}
