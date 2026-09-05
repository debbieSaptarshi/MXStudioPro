import Foundation

/// CapCut-style animated waveform peaks for Reels video export (Week 84).
///
/// Downsamples mono PCM into normalized bar heights for per-frame drawing.
public enum MXReelsWaveform: Sendable {

    public struct Peaks: Equatable, Sendable {
        /// Normalized amplitudes 0…1 for each bar.
        public var bars: [Float]
        /// Bar count (typically 48–96 for vertical Reels).
        public var barCount: Int { bars.count }

        public init(bars: [Float]) {
            self.bars = bars.map { max(0, min(1, $0)) }
        }
    }

    public static let defaultBarCount = 64

    /// Extract peak envelope from mono PCM for waveform visualization.
    public static func peaks(
        mono: [Float],
        barCount: Int = defaultBarCount
    ) -> Peaks {
        let count = max(8, barCount)
        guard !mono.isEmpty else { return Peaks(bars: [Float](repeating: 0, count: count)) }

        let framesPerBar = max(1, mono.count / count)
        var bars = [Float](repeating: 0, count: count)
        var globalPeak: Float = 1e-8

        for b in 0..<count {
            let start = b * framesPerBar
            let end = min(mono.count, start + framesPerBar)
            guard start < end else { continue }
            var peak: Float = 0
            for i in start..<end {
                peak = max(peak, abs(mono[i]))
            }
            bars[b] = peak
            globalPeak = max(globalPeak, peak)
        }

        let inv = 1 / globalPeak
        for i in bars.indices { bars[i] *= inv }
        return Peaks(bars: bars)
    }

    /// Playhead position as a fraction 0…1 for frame `frameIndex` of `frameCount`.
    public static func playheadFraction(frameIndex: Int, frameCount: Int) -> Double {
        guard frameCount > 1 else { return 0 }
        return Double(frameIndex) / Double(frameCount - 1)
    }

    /// Bar index under the playhead for highlighting.
    public static func playheadBarIndex(
        fraction: Double,
        barCount: Int
    ) -> Int {
        guard barCount > 0 else { return 0 }
        let clamped = max(0, min(1, fraction))
        return min(barCount - 1, Int((clamped * Double(barCount)).rounded(.down)))
    }
}
