import Foundation

/// Ableton / BandLab-style **time-stretch lite** for mono clips.
///
/// Offline MVP: pitch-preserving WSOLA-lite / granular overlap-add. Analysis hop
/// `Ha` steps through the source; synthesis hop `Hs = Ha * factor` places grains
/// so duration becomes ≈ `input * factor` while pitch stays put. Optional
/// ±`Ha/2` cross-correlation search aligns successive grains. Not warp markers,
/// not transient mode, not a live `AVAudioUnitTimePitch` insert.
public enum MXTimeStretch {

    /// Default analysis window (~46 ms @ 48 kHz).
    public static let defaultWindowSeconds: Double = 0.046
    /// Default analysis hop (~25% of the window).
    public static let defaultAnalysisHopSeconds: Double = 0.0115

    // MARK: - Length

    /// Expected output frame count for a stretch `factor` (`>1` lengthens).
    /// Factor is clamped to `0.5…2.0`.
    public static func outputFrameCount(inputFrames: Int, factor: Double) -> Int {
        guard inputFrames > 0 else { return 0 }
        let f = max(0.5, min(2.0, factor))
        return max(1, Int((Double(inputFrames) * f).rounded()))
    }

    // MARK: - Stretch

    /// Pitch-preserving time-stretch of mono PCM.
    ///
    /// - Parameters:
    ///   - factor: Duration scale (`>1` lengthens, `<1` shortens). Clamped to
    ///     `0.5…2.0`. Values within `±1e-4` of `1` return a copy of `mono`.
    ///   - windowSeconds: Grain / OLA window length.
    ///   - analysisHopSeconds: Analysis hop `Ha`; synthesis hop is `Ha * factor`.
    /// - Returns: Stretched buffer of approximate length `input.count * factor`,
    ///   or empty when `mono` is empty.
    public static func stretch(
        mono: [Float],
        sampleRate: Double,
        factor: Double,
        windowSeconds: Double = defaultWindowSeconds,
        analysisHopSeconds: Double = defaultAnalysisHopSeconds
    ) -> [Float] {
        guard !mono.isEmpty else { return [] }
        guard sampleRate > 0 else { return mono }

        let clamped = max(0.5, min(2.0, factor))
        if abs(clamped - 1.0) <= 1e-4 {
            return mono
        }

        let outCount = outputFrameCount(inputFrames: mono.count, factor: clamped)
        let windowFrames = max(64, Int((windowSeconds * sampleRate).rounded()))
        let ha = max(16, Int((analysisHopSeconds * sampleRate).rounded()))
        // Synthesis hop scales with factor; keep at least one-sample progress and
        // prefer overlap (Hs < window) when the window allows it.
        var hs = max(1, Int((Double(ha) * clamped).rounded()))
        if hs >= windowFrames {
            hs = max(1, windowFrames / 2)
        }

        guard mono.count >= windowFrames / 2, outCount > 0 else {
            return resizeCopy(mono, to: outCount)
        }

        let hann = hannWindow(length: windowFrames)
        let searchRadius = max(0, ha / 2)
        let overlapFrames = max(8, windowFrames - hs)

        var output = [Float](repeating: 0, count: outCount)
        var weight = [Float](repeating: 0, count: outCount)

        var prevAnaStart = 0
        var hasPrev = false
        var synPos = 0

        while synPos < outCount {
            let expectedAna = Int((Double(synPos) / clamped).rounded())
            let anaStart: Int
            if hasPrev, searchRadius > 0 {
                anaStart = bestAnalysisStart(
                    mono: mono,
                    expectedStart: expectedAna,
                    prevStart: prevAnaStart,
                    windowFrames: windowFrames,
                    overlapFrames: overlapFrames,
                    searchRadius: searchRadius
                )
            } else {
                anaStart = clampAnalysisStart(expectedAna, inputCount: mono.count)
            }

            addGrain(
                mono: mono,
                anaStart: anaStart,
                synPos: synPos,
                windowFrames: windowFrames,
                hann: hann,
                output: &output,
                weight: &weight
            )

            prevAnaStart = anaStart
            hasPrev = true
            synPos += hs
        }

        for i in output.indices {
            if weight[i] > 1e-8 {
                output[i] /= weight[i]
            }
        }
        return output
    }

    // MARK: - Internals

    /// Cross-correlation search for the analysis start that best matches the
    /// overlapping region of the previous grain (WSOLA-lite).
    private static func bestAnalysisStart(
        mono: [Float],
        expectedStart: Int,
        prevStart: Int,
        windowFrames: Int,
        overlapFrames: Int,
        searchRadius: Int
    ) -> Int {
        let overlap = max(8, overlapFrames)
        let lo = max(0, expectedStart - searchRadius)
        let hi = min(max(0, mono.count - 1), expectedStart + searchRadius)
        guard lo <= hi else {
            return clampAnalysisStart(expectedStart, inputCount: mono.count)
        }

        var bestStart = clampAnalysisStart(expectedStart, inputCount: mono.count)
        var bestCorr: Float = -Float.greatestFiniteMagnitude

        // Reference: end of previous grain (overlap region).
        let refStart = prevStart + max(0, windowFrames - overlap)

        for candidate in lo...hi {
            var corr: Float = 0
            var energy: Float = 0
            var i = 0
            while i < overlap {
                let aIdx = refStart + i
                let bIdx = candidate + i
                let a: Float = (aIdx >= 0 && aIdx < mono.count) ? mono[aIdx] : 0
                let b: Float = (bIdx >= 0 && bIdx < mono.count) ? mono[bIdx] : 0
                corr += a * b
                energy += b * b
                i += 1
            }
            // Prefer stronger correlation; tiny energy penalty avoids silence locks.
            let score = corr - 1e-6 * energy
            if score > bestCorr {
                bestCorr = score
                bestStart = candidate
            }
        }
        return bestStart
    }

    private static func clampAnalysisStart(_ start: Int, inputCount: Int) -> Int {
        guard inputCount > 0 else { return 0 }
        return max(0, min(start, inputCount - 1))
    }

    private static func addGrain(
        mono: [Float],
        anaStart: Int,
        synPos: Int,
        windowFrames: Int,
        hann: [Float],
        output: inout [Float],
        weight: inout [Float]
    ) {
        for i in 0..<windowFrames {
            let dest = synPos + i
            guard dest < output.count else { break }
            let src = anaStart + i
            let sample: Float = (src >= 0 && src < mono.count) ? mono[src] : 0
            let w = i < hann.count ? hann[i] : 0
            output[dest] += sample * w
            weight[dest] += w
        }
    }

    private static func resizeCopy(_ input: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        if input.count == count { return input }
        var out = [Float](repeating: 0, count: count)
        let n = min(input.count, count)
        for i in 0..<n { out[i] = input[i] }
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
}
