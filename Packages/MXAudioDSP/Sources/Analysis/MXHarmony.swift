import Foundation

/// CapCut / BandLab-style **vocal harmonies lite**.
///
/// Offline MVP: duration-preserving pitch shift by fixed semitone intervals,
/// then mix dry + 1–2 harmony voices into one mono buffer. Not live formant
/// preserve, not separate track-per-voice, not MIDI harmony.
public enum MXHarmony {

    public static let defaultWindowSeconds: Double = 0.046
    public static let defaultHopSeconds: Double = 0.0115

    /// Semitone → frequency ratio (equal temperament).
    public static func semitoneRatio(_ semitones: Double) -> Double {
        pow(2.0, semitones / 12.0)
    }

    /// Common stack presets (BandLab / CapCut lite).
    public enum Interval: Int, CaseIterable, Sendable {
        /// Major third above.
        case majorThird = 4
        /// Perfect fifth above.
        case perfectFifth = 7
        /// Perfect fourth below (low harmony).
        case perfectFourthBelow = -5

        public var semitones: Int { rawValue }

        public var label: String {
            switch self {
            case .majorThird: return "3rd"
            case .perfectFifth: return "5th"
            case .perfectFourthBelow: return "Low 4th"
            }
        }
    }

    /// Duration-preserving pitch shift by a fixed interval (OLA + linear resample).
    /// `semitones` 0 → identity copy. Empty input → empty.
    public static func shift(
        mono: [Float],
        sampleRate: Double,
        semitones: Double,
        windowSeconds: Double = defaultWindowSeconds,
        hopSeconds: Double = defaultHopSeconds
    ) -> [Float] {
        guard !mono.isEmpty, sampleRate > 0 else { return mono }
        let ratio = semitoneRatio(semitones)
        guard abs(ratio - 1) > 1e-9 else { return mono }

        let windowFrames = max(64, Int((windowSeconds * sampleRate).rounded()))
        let hopFrames = max(16, Int((hopSeconds * sampleRate).rounded()))
        guard mono.count >= windowFrames / 2 else {
            return durationPreserveResample(mono, ratio: ratio)
        }

        let hann = hannWindow(length: windowFrames)
        var output = [Float](repeating: 0, count: mono.count)
        var weight = [Float](repeating: 0, count: mono.count)

        var start = 0
        while start < mono.count {
            let end = min(start + windowFrames, mono.count)
            let length = end - start
            guard length > 16 else { break }

            var grain = [Float](repeating: 0, count: windowFrames)
            for i in 0..<length {
                grain[i] = mono[start + i] * (i < hann.count ? hann[i] : 0)
            }

            let shifted = resample(grain, ratio: ratio)
            let outLen = min(shifted.count, windowFrames)
            for i in 0..<outLen {
                let dest = start + i
                guard dest < output.count else { break }
                let w = i < hann.count ? hann[i] : 0
                output[dest] += shifted[i] * w
                weight[dest] += w * w
            }
            start += hopFrames
        }

        for i in output.indices {
            if weight[i] > 1e-8 {
                output[i] /= weight[i]
            } else {
                output[i] = mono[i]
            }
        }
        return output
    }

    /// Mix dry + harmony voices. `mix` 0 → dry only; 1 → dry + full voice gains.
    /// Soft peak-normalizes to ≤0.95 so stacked voices don't clip.
    ///
    /// - Parameters:
    ///   - intervals: Semitone offsets (e.g. `[4, 7]` for 3rd+5th). Empty → dry copy.
    ///   - dryGain: Dry level (default 1).
    ///   - voiceGain: Per-voice level before mix (default 0.55).
    ///   - mix: 0…1 blend of harmony energy into the stack.
    public static func stack(
        mono: [Float],
        sampleRate: Double,
        intervals: [Int],
        dryGain: Float = 1,
        voiceGain: Float = 0.55,
        mix: Float = 0.55,
        windowSeconds: Double = defaultWindowSeconds,
        hopSeconds: Double = defaultHopSeconds
    ) -> [Float] {
        guard !mono.isEmpty, sampleRate > 0 else { return mono }
        let clampedMix = max(0, min(1, mix))
        let uniqueIntervals = Array(Set(intervals.filter { $0 != 0 })).sorted()
        guard !uniqueIntervals.isEmpty, clampedMix > 1e-4 else {
            return mono.map { $0 * dryGain }
        }

        var output = mono.map { $0 * dryGain }
        let voiceScale = voiceGain * clampedMix
        for semitones in uniqueIntervals {
            let shifted = shift(
                mono: mono,
                sampleRate: sampleRate,
                semitones: Double(semitones),
                windowSeconds: windowSeconds,
                hopSeconds: hopSeconds
            )
            let n = min(output.count, shifted.count)
            for i in 0..<n {
                output[i] += shifted[i] * voiceScale
            }
        }

        // Soft peak normalize to avoid hard clip when stacking.
        var peak: Float = 0
        for s in output { peak = max(peak, abs(s)) }
        if peak > 0.95 {
            let scale = 0.95 / peak
            for i in output.indices { output[i] *= scale }
        }
        return output
    }

    // MARK: - Internals

    private static func durationPreserveResample(_ input: [Float], ratio: Double) -> [Float] {
        let shifted = resample(input, ratio: ratio)
        if shifted.count == input.count { return shifted }
        var out = [Float](repeating: 0, count: input.count)
        let n = min(out.count, shifted.count)
        for i in 0..<n { out[i] = shifted[i] }
        return out
    }

    private static func hannWindow(length: Int) -> [Float] {
        guard length > 1 else { return [1] }
        var w = [Float](repeating: 0, count: length)
        let denom = Float(length - 1)
        for i in 0..<length {
            w[i] = 0.5 - 0.5 * cos(2 * Float.pi * Float(i) / denom)
        }
        return w
    }

    /// Linear-interpolation resample. `ratio` > 1 raises pitch (reads source faster).
    private static func resample(_ input: [Float], ratio: Double) -> [Float] {
        guard !input.isEmpty else { return [] }
        let r = max(0.5, min(2.0, ratio))
        if abs(r - 1) < 1e-9 { return input }
        let outCount = max(1, Int((Double(input.count) / r).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) * r
            let i0 = Int(src)
            let frac = Float(src - Double(i0))
            let s0 = i0 < input.count ? input[i0] : 0
            let s1 = i0 + 1 < input.count ? input[i0 + 1] : s0
            out[i] = s0 + (s1 - s0) * frac
        }
        return out
    }
}
