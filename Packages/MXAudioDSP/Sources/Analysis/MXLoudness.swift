import Foundation

/// Practical BS.1770-style loudness helpers for **Reels / TikTok export** (~−14 LUFS).
///
/// This is an offline MVP: mean-square block energy with absolute and relative
/// gating, **not** a certified K-weighted meter. Suitable for music-export
/// targeting; do not treat readings as broadcast-legal LUFS.
public enum MXLoudness {

    /// Absolute gate floor used by BS.1770 (LUFS).
    public static let absoluteGateLUFS: Float = -70
    /// Relative gate offset below the absolute-gated mean (LU).
    public static let relativeGateOffsetLU: Float = 10
    /// Block length for gating (seconds).
    public static let blockDurationSeconds: Double = 0.4
    /// Block hop as a fraction of block length (BS.1770 uses 75% overlap → 0.25).
    public static let blockHopFraction: Double = 0.25

    // MARK: - Integrated loudness

    /// Absolute-gated integrated loudness approximation for mono or stereo float buffers.
    ///
    /// - Parameters:
    ///   - left: Left (or mono) channel samples.
    ///   - right: Optional right channel; when `nil`, `left` is treated as mono.
    ///   - sampleRate: Sample rate of the buffers.
    /// - Returns: Approximate integrated LUFS, or `-∞` for silence / empty input.
    public static func integratedLUFS(left: [Float],
                                      right: [Float]? = nil,
                                      sampleRate: Double = 48_000) -> Float {
        guard sampleRate > 0, !left.isEmpty else { return -.infinity }
        let frameCount = right.map { min(left.count, $0.count) } ?? left.count
        guard frameCount > 0 else { return -.infinity }

        let blockFrames = max(1, Int((blockDurationSeconds * sampleRate).rounded()))
        let hopFrames = max(1, Int((Double(blockFrames) * blockHopFraction).rounded()))
        guard frameCount >= blockFrames else {
            // Short buffers: one ungated mean-square estimate.
            let z = meanSquarePower(left: left, right: right, start: 0, count: frameCount)
            return loudnessFromMeanSquare(z)
        }

        var blockMeanSquares: [Float] = []
        blockMeanSquares.reserveCapacity(max(1, (frameCount - blockFrames) / hopFrames + 1))
        var start = 0
        while start + blockFrames <= frameCount {
            blockMeanSquares.append(
                meanSquarePower(left: left, right: right, start: start, count: blockFrames)
            )
            start += hopFrames
        }

        // Pass 1 — absolute gate (−70 LUFS).
        let absoluteFloor = meanSquareFromLoudness(absoluteGateLUFS)
        let absoluteGated = blockMeanSquares.filter { $0 > absoluteFloor }
        guard !absoluteGated.isEmpty else { return -.infinity }

        let absoluteMean = absoluteGated.reduce(0, +) / Float(absoluteGated.count)
        let absoluteLoudness = loudnessFromMeanSquare(absoluteMean)

        // Pass 2 — relative gate (mean − 10 LU).
        let relativeFloor = meanSquareFromLoudness(absoluteLoudness - relativeGateOffsetLU)
        let relativeGated = absoluteGated.filter { $0 > relativeFloor }
        let gated = relativeGated.isEmpty ? absoluteGated : relativeGated
        let gatedMean = gated.reduce(0, +) / Float(gated.count)
        return loudnessFromMeanSquare(gatedMean)
    }

    // MARK: - Gain helpers

    /// Linear gain that moves `currentLUFS` to `target` LUFS.
    public static func gainToTargetLUFS(currentLUFS: Float, target: Float) -> Float {
        guard currentLUFS.isFinite else { return 1 }
        let deltaLU = target - currentLUFS
        return pow(10, deltaLU / 20)
    }

    /// Multiply stereo buffers by a linear gain in place.
    public static func applyGain(_ gain: Float, left: inout [Float], right: inout [Float]) {
        guard gain != 1 else { return }
        for i in left.indices {
            left[i] *= gain
        }
        for i in right.indices {
            right[i] *= gain
        }
    }

    /// Scale the mix toward `targetLUFS`, then soft-limit / peak-cap so peak ≤ `maxPeak`.
    ///
    /// Default target (−14 LUFS) matches common Reels / TikTok music export practice.
    public static func normalizeToLUFS(left: inout [Float],
                                       right: inout [Float],
                                       targetLUFS: Float = -14,
                                       maxPeak: Float = 0.99) {
        guard !left.isEmpty || !right.isEmpty else { return }

        let current = integratedLUFS(left: left, right: right.isEmpty ? nil : right)
        if current.isFinite {
            applyGain(gainToTargetLUFS(currentLUFS: current, target: targetLUFS),
                      left: &left,
                      right: &right)
        }

        let peak = max(MXAudioAnalysis.peak(left), MXAudioAnalysis.peak(right))
        guard peak > maxPeak, peak > 0 else { return }

        // Soft peak cap: scale so max abs ≤ maxPeak (hard ceiling after LUFS gain).
        let ceilingGain = maxPeak / peak
        applyGain(ceilingGain, left: &left, right: &right)
    }

    // MARK: - Internals

    /// Channel-summed mean-square power for one block (L/R weights = 1, as in BS.1770 stereo).
    private static func meanSquarePower(left: [Float],
                                        right: [Float]?,
                                        start: Int,
                                        count: Int) -> Float {
        var sumL: Float = 0
        let end = start + count
        for i in start..<end {
            let s = left[i]
            sumL += s * s
        }
        let zL = sumL / Float(count)

        guard let right, right.count >= end else {
            return zL
        }
        var sumR: Float = 0
        for i in start..<end {
            let s = right[i]
            sumR += s * s
        }
        return zL + (sumR / Float(count))
    }

    /// BS.1770 mean-square → LUFS (without K-weighting).
    private static func loudnessFromMeanSquare(_ z: Float) -> Float {
        guard z > 1e-20 else { return -.infinity }
        return -0.691 + 10 * log10(z)
    }

    private static func meanSquareFromLoudness(_ lufs: Float) -> Float {
        guard lufs.isFinite else { return 0 }
        return pow(10, (lufs + 0.691) / 10)
    }
}
