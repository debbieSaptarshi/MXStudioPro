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

        applyMasterLimiter(left: &left, right: &right, ceiling: maxPeak)
    }

    /// Soft master limiter / brickwall safety so true peak stays ≤ `ceiling`
    /// (~0.99 ≈ −0.1 dBTP). Shared by peak-normalize and LUFS bounce paths.
    ///
    /// Soft-knees samples above ~92% of the ceiling, then hard-clamps and
    /// applies a final global scale if anything still exceeds the ceiling.
    public static func applyMasterLimiter(left: inout [Float],
                                          right: inout [Float],
                                          ceiling: Float = 0.99) {
        guard ceiling > 0, !left.isEmpty else { return }
        let knee = ceiling * 0.92
        let count = min(left.count, right.count)
        for i in 0..<count {
            left[i] = softLimitSample(left[i], knee: knee, ceiling: ceiling)
            right[i] = softLimitSample(right[i], knee: knee, ceiling: ceiling)
        }
        if left.count > count {
            for i in count..<left.count {
                left[i] = softLimitSample(left[i], knee: knee, ceiling: ceiling)
            }
        } else if right.count > count {
            for i in count..<right.count {
                right[i] = softLimitSample(right[i], knee: knee, ceiling: ceiling)
            }
        }

        let peak = max(MXAudioAnalysis.peak(left), MXAudioAnalysis.peak(right))
        guard peak > ceiling else { return }
        applyGain(ceiling / peak, left: &left, right: &right)
    }

    // MARK: - Report (Week 71)

    /// Post-bounce loudness report: integrated LUFS, sample-peak dBFS, optional target.
    ///
    /// `truePeakDBFS` is **approx true-peak / sample peak** — `MXAudioAnalysis.peakDB`
    /// of the louder channel (max of L/R). Not inter-sample true peak (ITU-R BS.1770).
    public struct Report: Sendable, Equatable {
        public var integratedLUFS: Float
        /// Approx true-peak / sample peak in dBFS (max of L/R sample peak).
        public var truePeakDBFS: Float
        public var targetLUFS: Float?
        public var sampleRate: Double

        public init(integratedLUFS: Float,
                    truePeakDBFS: Float,
                    targetLUFS: Float? = nil,
                    sampleRate: Double = 48_000) {
            self.integratedLUFS = integratedLUFS
            self.truePeakDBFS = truePeakDBFS
            self.targetLUFS = targetLUFS
            self.sampleRate = sampleRate
        }

        /// Headroom in LU relative to target (`target - measured`).
        /// Nil if no target or non-finite measured LUFS.
        public var headroomLU: Float? {
            guard let targetLUFS, integratedLUFS.isFinite else { return nil }
            return targetLUFS - integratedLUFS
        }
    }

    /// Build a bounce/export loudness report from mono or stereo float buffers.
    ///
    /// - Parameters:
    ///   - left: Left (or mono) channel samples.
    ///   - right: Optional right channel; when `nil`, `left` is treated as mono.
    ///   - sampleRate: Sample rate of the buffers.
    ///   - targetLUFS: Optional export target (e.g. −14 for Reels).
    /// - Returns: Report with integrated LUFS and sample-peak dBFS (approx true-peak).
    public static func report(left: [Float],
                              right: [Float]? = nil,
                              sampleRate: Double = 48_000,
                              targetLUFS: Float? = nil) -> Report {
        let integrated = integratedLUFS(left: left, right: right, sampleRate: sampleRate)
        let leftPeakDB = MXAudioAnalysis.peakDB(left)
        let rightPeakDB = right.map { MXAudioAnalysis.peakDB($0) } ?? -.infinity
        let truePeak = max(leftPeakDB, rightPeakDB)
        return Report(integratedLUFS: integrated,
                      truePeakDBFS: truePeak,
                      targetLUFS: targetLUFS,
                      sampleRate: sampleRate)
    }

    // MARK: - Live / momentary (Week 59)

    /// Momentary loudness from a short buffer (GarageBand / Reels live meter lite).
    ///
    /// Uses the same ungated mean-square → LUFS map as integrated blocks — not
    /// K-weighted. Returns `-∞` for silence / empty input.
    public static func momentaryLUFS(left: [Float],
                                     right: [Float]? = nil,
                                     sampleRate: Double = 48_000) -> Float {
        guard sampleRate > 0, !left.isEmpty else { return -.infinity }
        let frameCount = right.map { min(left.count, $0.count) } ?? left.count
        guard frameCount > 0 else { return -.infinity }
        let z = meanSquarePower(left: left, right: right, start: 0, count: frameCount)
        return loudnessFromMeanSquare(z)
    }

    /// Convert channel-summed mean-square power to approximate LUFS.
    public static func loudnessFromMeanSquare(_ z: Float) -> Float {
        guard z > 1e-20 else { return -.infinity }
        return -0.691 + 10 * log10(z)
    }

    /// Soft-knee map toward `ceiling`, then hard clamp.
    private static func softLimitSample(_ x: Float, knee: Float, ceiling: Float) -> Float {
        let a = abs(x)
        if a <= knee { return x }
        let headroom = max(ceiling - knee, 1e-6)
        let over = a - knee
        let compressed = knee + headroom * (over / (over + headroom))
        let limited = min(compressed, ceiling)
        return x >= 0 ? limited : -limited
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

    private static func meanSquareFromLoudness(_ lufs: Float) -> Float {
        guard lufs.isFinite else { return 0 }
        return pow(10, (lufs + 0.691) / 10)
    }
}
