import Foundation

/// One volume automation breakpoint (Logic / Ableton lane lite).
///
/// `value` is a linear gain multiplier (0…2). Unity = 1. Multiplies track volume.
public struct MXAutomationPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Absolute project beat.
    public var beat: Double
    /// Linear gain 0…2 (1 = unity).
    public var value: Float

    public init(id: UUID = UUID(), beat: Double, value: Float) {
        self.id = id
        self.beat = max(0, beat)
        self.value = min(2, max(0, value))
    }
}

/// Evaluate and mutate track volume automation polylines.
public enum MXVolumeAutomation: Sendable {
    public static let unity: Float = 1
    public static let minValue: Float = 0
    public static let maxValue: Float = 2

    /// Linear interpolation across sorted points. Empty → unity. Outside range → endpoint hold.
    public static func value(atBeat beat: Double, points: [MXAutomationPoint]) -> Float {
        guard !points.isEmpty else { return unity }
        let sorted = points.sorted { $0.beat < $1.beat }
        if beat <= sorted[0].beat { return sorted[0].value }
        if beat >= sorted[sorted.count - 1].beat { return sorted[sorted.count - 1].value }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if beat >= a.beat && beat <= b.beat {
                let span = b.beat - a.beat
                if span < 1e-9 { return b.value }
                let t = Float((beat - a.beat) / span)
                return a.value + (b.value - a.value) * t
            }
        }
        return unity
    }

    /// Insert or replace a point near `beat` (within `toleranceBeats`); returns updated array.
    public static func upserting(
        _ points: [MXAutomationPoint],
        beat: Double,
        value: Float,
        toleranceBeats: Double = 0.08
    ) -> [MXAutomationPoint] {
        var next = points
        let clampedBeat = max(0, beat)
        let clampedValue = min(maxValue, max(minValue, value))
        if let idx = next.firstIndex(where: { abs($0.beat - clampedBeat) <= toleranceBeats }) {
            next[idx].beat = clampedBeat
            next[idx].value = clampedValue
        } else {
            next.append(MXAutomationPoint(beat: clampedBeat, value: clampedValue))
        }
        return next.sorted { $0.beat < $1.beat }
    }

    public static func removing(_ points: [MXAutomationPoint], id: UUID) -> [MXAutomationPoint] {
        points.filter { $0.id != id }
    }

    public static func moving(
        _ points: [MXAutomationPoint],
        id: UUID,
        beat: Double,
        value: Float
    ) -> [MXAutomationPoint] {
        guard let idx = points.firstIndex(where: { $0.id == id }) else { return points }
        var next = points
        next[idx].beat = max(0, beat)
        next[idx].value = min(maxValue, max(minValue, value))
        return next.sorted { $0.beat < $1.beat }
    }
}
