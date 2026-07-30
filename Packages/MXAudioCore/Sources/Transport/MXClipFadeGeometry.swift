import Foundation

/// Timeline geometry helpers for clip fade visualization (Logic / Pro Tools wedges).
public enum MXClipFadeGeometry: Sendable {
    /// Convert a fade duration in seconds to quarter-note beats at `bpm`.
    public static func widthBeats(fadeSeconds: Double, bpm: Double) -> Double {
        max(0, fadeSeconds) * max(bpm, 1) / 60.0
    }

    /// Equal-power fade-in attenuation used to draw the wedge height (0 = silent, 1 = full).
    /// Progress `t` is 0…1 across the fade-in region.
    public static func fadeInGain(_ t: Double) -> Double {
        Double(MXCrossfade.equalPowerIn(t))
    }

    /// Equal-power fade-out attenuation (1 at start of fade-out, 0 at end).
    public static func fadeOutGain(_ t: Double) -> Double {
        Double(MXCrossfade.equalPowerOut(t))
    }
}
