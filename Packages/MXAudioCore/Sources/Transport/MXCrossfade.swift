import Foundation

/// Equal-power crossfade gains (Logic / Pro Tools style).
///
/// At matched progress `t`, `equalPowerOut(t)² + equalPowerIn(t)² ≈ 1`, so
/// overlapping seams keep constant perceived power instead of an equal-gain dip.
public enum MXCrossfade: Sendable {
    /// Equal-power fade-in gain for progress `t` in `[0,1]`: `sin(π/2 · t)`.
    /// Values outside `[0,1]` are clamped.
    public static func equalPowerIn(_ t: Double) -> Float {
        let x = min(1, max(0, t))
        return Float(sin(.pi / 2 * x))
    }

    /// Equal-power fade-out gain for progress `t` in `[0,1]`: `cos(π/2 · t)`.
    /// Values outside `[0,1]` are clamped.
    public static func equalPowerOut(_ t: Double) -> Float {
        let x = min(1, max(0, t))
        return Float(cos(.pi / 2 * x))
    }

    /// Default soft-overlap tolerance in beats (~40 ms at 120 BPM).
    public static let defaultSoftOverlapBeats: Double = 0.08
}
