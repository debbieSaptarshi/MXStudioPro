import Foundation

/// Animated Reels waveform layout math (Week 84 — CapCut / Instagram lite).
///
/// Pure + `Sendable` so `StudioReelsVideoExporter` and Linux CI share the same
/// peak envelope + playhead mapping without UIKit.
public enum MXReelsWaveform: Sendable {

    public static let defaultBarCount = 256
    public static let defaultVisibleBars = 96
    public static let defaultFloorDB: Float = -48

    /// Max-abs peak per equal segment. Output length == `barCount` (min 1).
    public static func peaks(mono: [Float], barCount: Int) -> [Float] {
        let count = max(1, barCount)
        guard !mono.isEmpty else { return [Float](repeating: 0, count: count) }
        let segment = max(1, mono.count / count)
        var out = [Float](repeating: 0, count: count)
        for bar in 0..<count {
            let start = bar * segment
            let end = bar == count - 1 ? mono.count : min(mono.count, start + segment)
            guard start < end else { continue }
            out[bar] = MXAudioAnalysis.peak(Array(mono[start..<end]))
        }
        return out
    }

    /// Normalize peaks to 0…1 with a dB noise floor.
    public static func normalizedPeaks(_ peaks: [Float], floorDB: Float = defaultFloorDB) -> [Float] {
        guard !peaks.isEmpty else { return [] }
        let floorLin = pow(10, floorDB / 20)
        return peaks.map { peak in
            let lin = max(peak, floorLin)
            let db = 20 * log10(lin)
            let span = abs(floorDB)
            let norm = (db - floorDB) / span
            return min(1, max(0, norm))
        }
    }

    /// Playhead progress 0…1 at a presentation time.
    public static func playheadProgress(presentationSeconds: Double, durationSeconds: Double) -> Double {
        guard durationSeconds > 1e-9, presentationSeconds.isFinite, durationSeconds.isFinite else { return 0 }
        return min(1, max(0, presentationSeconds / durationSeconds))
    }

    /// Center bar index for a playhead progress value.
    public static func centerBar(progress: Double, totalBars: Int) -> Int {
        let total = max(1, totalBars)
        let p = min(1, max(0, progress))
        return min(total - 1, Int((p * Double(total - 1)).rounded()))
    }

    /// Visible bar range for a scrolling window centered on `centerBar`.
    public static func visibleBarRange(totalBars: Int, visibleBars: Int, centerBar: Int) -> Range<Int> {
        let total = max(1, totalBars)
        let visible = max(1, min(visibleBars, total))
        let half = visible / 2
        var start = centerBar - half
        start = max(0, min(start, total - visible))
        return start..<(start + visible)
    }

    /// Normalized bar layout for drawing: x and height in 0…1 track coordinates.
    public static func barLayout(
        peaks: [Float],
        visibleRange: Range<Int>,
        maxHeight: Double = 1
    ) -> [(x: Double, height: Double)] {
        guard !peaks.isEmpty, !visibleRange.isEmpty else { return [] }
        let count = visibleRange.count
        guard count > 0 else { return [] }
        let step = 1.0 / Double(count)
        return visibleRange.enumerated().map { offset, bar in
            let clamped = min(peaks.count - 1, max(0, bar))
            let h = Double(peaks[clamped]) * maxHeight
            let x = (Double(offset) + 0.5) * step
            return (x: x, height: h)
        }
    }

    /// Playhead X in 0…1 track coordinates.
    public static func playheadX(progress: Double) -> Double {
        min(1, max(0, progress))
    }
}
