import Foundation

/// Zoom-adaptive arrange grid density (Logic / Ableton style).
///
/// Snap resolution still governs edits; this only decides which subdivision
/// lines stay legible as `pixelsPerBeat` shrinks when zoomed out.
public enum MXBeatGridDensity: Sendable {
    /// Minimum horizontal pixels between subdivision lines before they are hidden.
    public static let minSubdivPixels: Double = 6

    /// Whether to draw snap-resolution subdivision lines at the current zoom.
    ///
    /// Whole-beat / bar lines are drawn separately and are unaffected.
    public static func shouldDrawSubdivisions(
        pixelsPerBeat: Double,
        subdivBeats: Double,
        minPixels: Double = minSubdivPixels
    ) -> Bool {
        guard pixelsPerBeat > 0, subdivBeats > 0, subdivBeats < 1.0 - 1e-12 else { return false }
        return pixelsPerBeat * subdivBeats >= minPixels
    }

    /// Coarsen the visual subdiv step until lines are at least `minPixels` apart.
    ///
    /// Returns `nil` when only whole-beat lines should show (step would reach ≥ 1 beat).
    /// Step grows by doubling so binary grids stay on musical multiples; triplets
    /// coarsen 1/6 → 1/3 → 2/3 → (nil).
    public static func visibleSubdivBeats(
        snapBeats: Double,
        pixelsPerBeat: Double,
        minPixels: Double = minSubdivPixels
    ) -> Double? {
        guard pixelsPerBeat > 0, snapBeats > 0, snapBeats < 1.0 - 1e-12 else { return nil }
        var step = snapBeats
        var guardCount = 0
        while pixelsPerBeat * step < minPixels, guardCount < 16 {
            step *= 2
            guardCount += 1
            if step >= 1.0 - 1e-12 { return nil }
        }
        return step
    }

    /// Clamp arrange `beatsVisible` for stepped zoom (GarageBand / BandLab lite).
    public static func clampBeatsVisible(_ value: Double, min: Double = 4, max: Double = 32) -> Double {
        Swift.min(max, Swift.max(min, value))
    }

    /// Next zoomed-out `beatsVisible` (show more beats → smaller pixels/beat).
    public static func zoomOutBeatsVisible(_ current: Double, factor: Double = 2, max: Double = 32) -> Double {
        clampBeatsVisible(current * factor, max: max)
    }

    /// Next zoomed-in `beatsVisible` (show fewer beats → larger pixels/beat).
    public static func zoomInBeatsVisible(_ current: Double, factor: Double = 2, min: Double = 4) -> Double {
        clampBeatsVisible(current / factor, min: min)
    }
}
