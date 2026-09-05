import Foundation

/// Interpolation between automation breakpoints (Week 86 Bezier lite).
public enum MXAutomationCurve: String, Codable, Equatable, Sendable, CaseIterable {
    /// Straight line between points (default).
    case linear
    /// Smooth ease-in-out curve (Logic / Ableton Bezier lite).
    case bezier
}

/// One automation breakpoint (Logic / Ableton lane lite).
///
/// For **volume** lanes, `value` is linear gain 0…2 (1 = unity).
/// For **pan** lanes, `value` is −1…1 (0 = center) — see `MXPanAutomation`.
public struct MXAutomationPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Beat position (project-absolute for tracks; clip-local for clip automation).
    public var beat: Double
    /// Lane-dependent value (see type docs).
    public var value: Float
    /// Curve leaving this point toward the next (Week 86).
    public var curve: MXAutomationCurve

    public init(
        id: UUID = UUID(),
        beat: Double,
        value: Float,
        curve: MXAutomationCurve = .linear
    ) {
        self.id = id
        self.beat = max(0, beat)
        self.value = value
        self.curve = curve
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        beat = try c.decode(Double.self, forKey: .beat)
        value = try c.decode(Float.self, forKey: .value)
        curve = try c.decodeIfPresent(MXAutomationCurve.self, forKey: .curve) ?? .linear
    }

    private enum CodingKeys: String, CodingKey {
        case id, beat, value, curve
    }
}

/// Evaluate and mutate track volume automation polylines.
public enum MXVolumeAutomation: Sendable {
    public static let unity: Float = 1
    public static let minValue: Float = 0
    public static let maxValue: Float = 2

    /// Interpolate across sorted points. Empty → unity. Outside range → endpoint hold.
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
                let eased = a.curve == .bezier ? MXAutomationCurveMath.easeInOut(t) : t
                return a.value + (b.value - a.value) * eased
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

    /// Clamp point beats into `[0, lengthBeats]` (clip-local automation).
    public static func clampingBeats(
        _ points: [MXAutomationPoint],
        lengthBeats: Double
    ) -> [MXAutomationPoint] {
        let end = max(0, lengthBeats)
        return points.map { point in
            var p = point
            p.beat = min(end, max(0, p.beat))
            p.value = min(maxValue, max(minValue, p.value))
            return p
        }.sorted { $0.beat < $1.beat }
    }
}

/// Pan automation helpers (Ableton / Logic clip pan lane lite).
///
/// `value` on points is −1…1. Empty curve → 0 (no offset). Outside range → endpoint hold.
public enum MXPanAutomation: Sendable {
    public static let center: Float = 0
    public static let minValue: Float = -1
    public static let maxValue: Float = 1

    public static func value(atBeat beat: Double, points: [MXAutomationPoint]) -> Float {
        guard !points.isEmpty else { return center }
        let sorted = points.sorted { $0.beat < $1.beat }
        if beat <= sorted[0].beat { return clamp(sorted[0].value) }
        if beat >= sorted[sorted.count - 1].beat { return clamp(sorted[sorted.count - 1].value) }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i]
            let b = sorted[i + 1]
            if beat >= a.beat && beat <= b.beat {
                let span = b.beat - a.beat
                if span < 1e-9 { return clamp(b.value) }
                let t = Float((beat - a.beat) / span)
                let eased = a.curve == .bezier ? MXAutomationCurveMath.easeInOut(t) : t
                return clamp(a.value + (b.value - a.value) * eased)
            }
        }
        return center
    }

    public static func upserting(
        _ points: [MXAutomationPoint],
        beat: Double,
        value: Float,
        toleranceBeats: Double = 0.08
    ) -> [MXAutomationPoint] {
        var next = points
        let clampedBeat = max(0, beat)
        let clampedValue = clamp(value)
        if let idx = next.firstIndex(where: { abs($0.beat - clampedBeat) <= toleranceBeats }) {
            next[idx].beat = clampedBeat
            next[idx].value = clampedValue
        } else {
            next.append(MXAutomationPoint(beat: clampedBeat, value: clampedValue))
        }
        return next.sorted { $0.beat < $1.beat }
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
        next[idx].value = clamp(value)
        return next.sorted { $0.beat < $1.beat }
    }

    public static func removing(_ points: [MXAutomationPoint], id: UUID) -> [MXAutomationPoint] {
        points.filter { $0.id != id }
    }

    public static func clampingBeats(
        _ points: [MXAutomationPoint],
        lengthBeats: Double
    ) -> [MXAutomationPoint] {
        let end = max(0, lengthBeats)
        return points.map { point in
            var p = point
            p.beat = min(end, max(0, p.beat))
            p.value = clamp(p.value)
            return p
        }.sorted { $0.beat < $1.beat }
    }

    /// Combine track pan with clip pan offset, clamped to −1…1.
    public static func combined(trackPan: Float, clipOffset: Float) -> Float {
        clamp(trackPan + clipOffset)
    }

    /// Track pan at `beat`: automation overrides the static fader when non-empty (Week 82).
    public static func trackPan(atBeat beat: Double, staticPan: Float, automation: [MXAutomationPoint]) -> Float {
        automation.isEmpty ? staticPan : value(atBeat: beat, points: automation)
    }

    private static func clamp(_ value: Float) -> Float {
        min(maxValue, max(minValue, value))
    }
}

/// Shared easing for Bezier automation segments (Week 86).
public enum MXAutomationCurveMath: Sendable {
    /// Smoothstep ease-in-out on 0…1.
    public static func easeInOut(_ t: Float) -> Float {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// Toggle curve on a point (linear ↔ bezier).
    public static func togglingCurve(_ points: [MXAutomationPoint], id: UUID) -> [MXAutomationPoint] {
        guard let idx = points.firstIndex(where: { $0.id == id }) else { return points }
        var next = points
        next[idx].curve = next[idx].curve == .linear ? .bezier : .linear
        return next
    }
}

/// Logic / Ableton-style clip gain automation modes (Week 77).
///
/// Lane values stay linear gain **0…2** (1 = unity), matching `MXVolumeAutomation`.
public enum MXClipGainAutomationMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Multiply static `clip.gain` by the automation curve (empty curve = unity).
    case relative
    /// Automation curve **is** the gain when non-empty; empty curve falls back to `clip.gain`.
    case absolute
}

/// Resolve clip contribution to the mix gain chain (before track volume / duck).
public enum MXClipGainAutomation: Sendable {
    public static let minGain: Float = 0.1
    public static let maxGain: Float = 2

    /// Effective clip gain at a sample / playhead.
    /// - `automationValue`: evaluated lane (pass `MXVolumeAutomation.unity` when empty).
    /// - `hasAutomation`: whether the clip has any gain automation points.
    public static func effectiveGain(
        clipGain: Float,
        mode: MXClipGainAutomationMode,
        automationValue: Float,
        hasAutomation: Bool
    ) -> Float {
        let staticGain = min(maxGain, max(minGain, clipGain))
        switch mode {
        case .relative:
            let auto = hasAutomation ? automationValue : MXVolumeAutomation.unity
            return staticGain * auto
        case .absolute:
            guard hasAutomation else { return staticGain }
            return min(maxGain, max(0, automationValue))
        }
    }
}
