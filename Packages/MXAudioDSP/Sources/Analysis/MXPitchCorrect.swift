import Foundation

/// GarageBand / CapCut-style **pitch correction lite** for vocal (and mono) clips.
///
/// Offline MVP: windowed autocorrelation F0 → snap to chromatic or scale pitch
/// classes → overlap-add resample grains so duration stays fixed. Not Flex Pitch
/// note editing, not formant-preserving, not a live `AUTimePitch` insert.
public enum MXPitchCorrect {

    public static let referenceA4: Double = 440
    /// Default analysis window (~46 ms @ 48 kHz) — short enough for syllables.
    public static let defaultWindowSeconds: Double = 0.046
    /// Default hop (~25% overlap of the window).
    public static let defaultHopSeconds: Double = 0.0115

    // MARK: - Pitch math

    /// Continuous MIDI note number from frequency (A4 = 69).
    public static func frequencyToMidi(_ hz: Double, referenceA4: Double = referenceA4) -> Double {
        guard hz > 0, referenceA4 > 0 else { return 0 }
        return 69.0 + 12.0 * log2(hz / referenceA4)
    }

    /// Frequency for a continuous MIDI note number.
    public static func midiToFrequency(_ midi: Double, referenceA4: Double = referenceA4) -> Double {
        guard referenceA4 > 0 else { return 0 }
        return referenceA4 * pow(2.0, (midi - 69.0) / 12.0)
    }

    /// Snap a continuous MIDI value to the nearest chromatic integer, or to the
    /// nearest pitch whose class (0…11) is in `pitchClasses` (Limit to Key).
    public static func snapMidi(_ midi: Double, pitchClasses: Set<UInt8>? = nil) -> Double {
        if let pitchClasses, !pitchClasses.isEmpty {
            let rounded = Int(midi.rounded())
            var best = Double(rounded)
            var bestDist = Double.greatestFiniteMagnitude
            for delta in -12...12 {
                let candidate = rounded + delta
                guard (0...127).contains(candidate) else { continue }
                let pc = UInt8(((candidate % 12) + 12) % 12)
                guard pitchClasses.contains(pc) else { continue }
                let dist = abs(midi - Double(candidate))
                if dist < bestDist {
                    bestDist = dist
                    best = Double(candidate)
                }
            }
            return best
        }
        return midi.rounded()
    }

    /// Linear blend of pitch ratios: `amount` 0 → 1.0 (no change), 1 → full snap.
    public static func correctionRatio(
        detectedHz: Double,
        targetHz: Double,
        amount: Float
    ) -> Double {
        let a = Double(max(0, min(1, amount)))
        guard detectedHz > 0, targetHz > 0 else { return 1 }
        let full = targetHz / detectedHz
        return 1.0 + (full - 1.0) * a
    }

    // MARK: - Detection

    /// Autocorrelation fundamental estimate (tuner-style). Returns `nil` for
    /// silence / unpitched / out-of-range windows.
    public static func detectFrequency(
        mono: [Float],
        sampleRate: Double,
        minHz: Double = 50,
        maxHz: Double = 1_500
    ) -> Double? {
        let frameCount = mono.count
        guard sampleRate > 0, frameCount >= 256 else { return nil }

        var sumSquares: Float = 0
        for s in mono { sumSquares += s * s }
        let rms = sqrt(sumSquares / Float(frameCount))
        guard rms > 0.006 else { return nil }

        let minLag = max(2, Int((sampleRate / maxHz).rounded(.up)))
        let maxLag = min(frameCount / 2, Int((sampleRate / minHz).rounded(.down)))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestCorrelation: Float = 0
        for lag in minLag..<maxLag {
            var correlation: Float = 0
            let limit = frameCount - lag
            var i = 0
            while i < limit {
                correlation += mono[i] * mono[i + lag]
                i += 1
            }
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }
        guard bestCorrelation > 0.0005 else { return nil }

        let frequency = sampleRate / Double(bestLag)
        guard (minHz...maxHz).contains(frequency) else { return nil }
        return frequency
    }

    // MARK: - Correct

    /// Pitch-correct mono PCM. `amount` 0 returns an identity copy; empty input
    /// returns empty. Output length matches input (duration-preserving).
    ///
    /// - Parameters:
    ///   - pitchClasses: When non-nil / non-empty, Limit-to-Key snap (0…11).
    ///     `nil` snaps chromatically (GarageBand without Limit to Key).
    public static func correct(
        mono: [Float],
        sampleRate: Double,
        amount: Float,
        pitchClasses: Set<UInt8>? = nil,
        windowSeconds: Double = defaultWindowSeconds,
        hopSeconds: Double = defaultHopSeconds,
        referenceA4: Double = referenceA4
    ) -> [Float] {
        let clampedAmount = max(0, min(1, amount))
        guard !mono.isEmpty, sampleRate > 0 else { return mono }
        guard clampedAmount > 1e-6 else { return mono }

        let windowFrames = max(64, Int((windowSeconds * sampleRate).rounded()))
        let hopFrames = max(16, Int((hopSeconds * sampleRate).rounded()))
        guard mono.count >= windowFrames / 2 else {
            // Short buffer: one-shot global correct.
            return correctWholeBuffer(
                mono: mono,
                sampleRate: sampleRate,
                amount: clampedAmount,
                pitchClasses: pitchClasses,
                referenceA4: referenceA4
            )
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

            let detected = detectFrequency(
                mono: Array(grain[0..<length]),
                sampleRate: sampleRate
            )
            let ratio: Double
            if let hz = detected {
                let midi = frequencyToMidi(hz, referenceA4: referenceA4)
                let targetMidi = snapMidi(midi, pitchClasses: pitchClasses)
                let targetHz = midiToFrequency(targetMidi, referenceA4: referenceA4)
                ratio = correctionRatio(detectedHz: hz, targetHz: targetHz, amount: clampedAmount)
            } else {
                ratio = 1
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

    // MARK: - Internals

    /// Single global F0 estimate + constant-ratio resample (short clips / tests).
    private static func correctWholeBuffer(
        mono: [Float],
        sampleRate: Double,
        amount: Float,
        pitchClasses: Set<UInt8>?,
        referenceA4: Double
    ) -> [Float] {
        guard let hz = detectFrequency(mono: mono, sampleRate: sampleRate) else {
            return mono
        }
        let midi = frequencyToMidi(hz, referenceA4: referenceA4)
        let targetMidi = snapMidi(midi, pitchClasses: pitchClasses)
        let targetHz = midiToFrequency(targetMidi, referenceA4: referenceA4)
        let ratio = correctionRatio(detectedHz: hz, targetHz: targetHz, amount: amount)
        guard abs(ratio - 1) > 1e-6 else { return mono }
        let shifted = resample(mono, ratio: ratio)
        // Duration-preserving: truncate or zero-pad to original length.
        if shifted.count == mono.count { return shifted }
        var out = [Float](repeating: 0, count: mono.count)
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
