import Foundation

/// Autocorrelation / energy-onset BPM estimate for imported audio
/// (Mixed In Key / GarageBand / BandLab tempo-detect lite).
///
/// Offline MVP on mono `Float` PCM — not a full beat tracker. Best on clicky /
/// rhythmic material; returns `nil` for silence or weak periodicity.
public enum MXTempoDetect: Sendable {

    public static let defaultMinBPM: Double = 60
    public static let defaultMaxBPM: Double = 200
    /// Minimum peak prominence (0…1) required by `estimateBPM`.
    public static let defaultMinConfidence: Double = 0.22
    /// Envelope rate (~Hz). Higher → finer lag resolution; 200 covers ≤200 BPM.
    public static let envelopeRateHz: Double = 200
    /// Need enough audio for a few periods at `minBPM`.
    public static let minimumDurationSeconds: Double = 2.5

    public struct Estimate: Sendable, Equatable {
        public let bpm: Double
        /// Rough 0…1 prominence of the winning lag vs mean autocorrelation in-range.
        public let confidence: Double

        public init(bpm: Double, confidence: Double) {
            self.bpm = bpm
            self.confidence = confidence
        }
    }

    /// BPM when confidence clears `minConfidence`; otherwise `nil`.
    public static func estimateBPM(
        mono: [Float],
        sampleRate: Double,
        minBPM: Double = defaultMinBPM,
        maxBPM: Double = defaultMaxBPM,
        minConfidence: Double = defaultMinConfidence
    ) -> Double? {
        guard let estimate = estimate(
            mono: mono,
            sampleRate: sampleRate,
            minBPM: minBPM,
            maxBPM: maxBPM
        ), estimate.confidence >= minConfidence
        else { return nil }
        return estimate.bpm
    }

    /// Full estimate (BPM + confidence), or `nil` when input is unusable.
    public static func estimate(
        mono: [Float],
        sampleRate: Double,
        minBPM: Double = defaultMinBPM,
        maxBPM: Double = defaultMaxBPM
    ) -> Estimate? {
        guard sampleRate > 0,
              minBPM > 0,
              maxBPM > minBPM,
              !mono.isEmpty
        else { return nil }

        let duration = Double(mono.count) / sampleRate
        guard duration >= minimumDurationSeconds else { return nil }

        let hop = max(1, Int((sampleRate / envelopeRateHz).rounded()))
        let envelope = onsetEnvelope(mono: mono, hopFrames: hop)
        guard envelope.count >= 32 else { return nil }

        let hopRate = sampleRate / Double(hop)
        // Lag in envelope hops: period = 60/BPM seconds → lag = period * hopRate.
        let minLag = max(1, Int((60.0 / maxBPM * hopRate).rounded()))
        let maxLag = min(envelope.count / 2, Int((60.0 / minBPM * hopRate).rounded()))
        guard maxLag > minLag else { return nil }

        let acf = autocorrelate(envelope, minLag: minLag, maxLag: maxLag)
        guard acf.count == (maxLag - minLag + 1) else { return nil }

        let mean = acf.reduce(0, +) / Float(acf.count)
        guard mean > 1e-12 else { return nil }

        var bestIndex = 0
        var bestValue = acf[0]
        for i in 1..<acf.count where acf[i] > bestValue {
            bestValue = acf[i]
            bestIndex = i
        }

        // Prefer a half-period (double tempo) when it is nearly as strong — avoids
        // locking onto every-other-beat for busy click trains.
        let bestLag = minLag + bestIndex
        if bestLag % 2 == 0 {
            let halfLag = bestLag / 2
            if halfLag >= minLag {
                let halfIndex = halfLag - minLag
                let halfValue = acf[halfIndex]
                if halfValue > bestValue * 0.88 {
                    bestIndex = halfIndex
                    bestValue = halfValue
                }
            }
        }

        let lag = minLag + bestIndex
        let periodSeconds = Double(lag) / hopRate
        guard periodSeconds > 0 else { return nil }

        var bpm = 60.0 / periodSeconds
        // Snap to nearest integer BPM for DAW display / metronome.
        bpm = bpm.rounded()
        guard bpm >= minBPM, bpm <= maxBPM else { return nil }

        let confidence = Double(max(0, (bestValue - mean) / max(bestValue, 1e-9)))
        guard confidence.isFinite else { return nil }
        return Estimate(bpm: bpm, confidence: min(1, confidence))
    }

    // MARK: - Internals

    /// Per-hop energy, then positive first difference (onset strength).
    private static func onsetEnvelope(mono: [Float], hopFrames: Int) -> [Float] {
        let hopCount = mono.count / hopFrames
        guard hopCount >= 4 else { return [] }

        var energy = [Float](repeating: 0, count: hopCount)
        for h in 0..<hopCount {
            let start = h * hopFrames
            let end = start + hopFrames
            var sum: Float = 0
            for i in start..<end {
                let s = mono[i]
                sum += s * s
            }
            energy[h] = sum / Float(hopFrames)
        }

        var onset = [Float](repeating: 0, count: hopCount)
        onset[0] = 0
        for h in 1..<hopCount {
            onset[h] = max(0, energy[h] - energy[h - 1])
        }
        return onset
    }

    /// Normalized autocorrelation for lags `minLag...maxLag` (inclusive).
    private static func autocorrelate(_ signal: [Float], minLag: Int, maxLag: Int) -> [Float] {
        var result = [Float](repeating: 0, count: maxLag - minLag + 1)
        let n = signal.count
        for lag in minLag...maxLag {
            var sum: Float = 0
            let count = n - lag
            guard count > 0 else { continue }
            for i in 0..<count {
                sum += signal[i] * signal[i + lag]
            }
            result[lag - minLag] = sum / Float(count)
        }
        return result
    }
}
