import Foundation

/// Timeline geometry helpers for clip fade visualization (Logic / Pro Tools wedges).
public enum MXClipFadeGeometry: Sendable {
    /// Convert a fade duration in seconds to quarter-note beats at `bpm`.
    public static func widthBeats(fadeSeconds: Double, bpm: Double) -> Double {
        max(0, fadeSeconds) * max(bpm, 1) / 60.0
    }

    /// Inverse of `widthBeats` — beats on the timeline → fade duration in seconds.
    public static func seconds(widthBeats: Double, bpm: Double) -> Double {
        max(0, widthBeats) * 60.0 / max(bpm, 1)
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

    /// Logic / Pro Tools meet-in-middle: `fadeIn + fadeOut` never exceeds `duration`.
    ///
    /// - Parameters:
    ///   - fadeIn / fadeOut: Requested lengths (seconds). Negative values clamp to 0.
    ///   - duration: Audible clip length (seconds).
    ///   - prefer: Which edge to preserve when the sum overflows (`nil` = shrink both equally).
    public static func meetInMiddle(
        fadeIn: Double,
        fadeOut: Double,
        duration: Double,
        prefer: FadeEdge? = nil
    ) -> (fadeIn: Double, fadeOut: Double) {
        let dur = max(0, duration)
        var inn = min(max(0, fadeIn), dur)
        var out = min(max(0, fadeOut), dur)
        let sum = inn + out
        guard sum > dur, dur > 1e-9 else {
            return (inn, out)
        }
        let overflow = sum - dur
        switch prefer {
        case .fadeIn:
            out = max(0, out - overflow)
            inn = min(inn, dur - out)
        case .fadeOut:
            inn = max(0, inn - overflow)
            out = min(out, dur - inn)
        case nil:
            // Shrink both proportionally (Logic default when both dragged / trim).
            if sum > 1e-9 {
                let scale = dur / sum
                inn *= scale
                out *= scale
            } else {
                inn = 0
                out = 0
            }
        }
        return (inn, out)
    }

    public enum FadeEdge: Sendable {
        case fadeIn
        case fadeOut
    }
}
