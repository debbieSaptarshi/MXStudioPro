import Foundation

/// BS.1770-style loudness helpers for **Reels / TikTok export** (~−14 LUFS).
///
/// Week 76: K-weighted (pre-filter + RLB) gated integrated loudness + 4×
/// inter-sample true peak. Still not a certified broadcast meter — suitable for
/// music-export targeting.
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

    /// Absolute-gated integrated loudness for mono or stereo float buffers.
    ///
    /// Applies ITU BS.1770 K-weighting (48 kHz stage coeffs) before gated
    /// mean-square. Returns `-∞` for silence / empty input.
    public static func integratedLUFS(left: [Float],
                                      right: [Float]? = nil,
                                      sampleRate: Double = 48_000) -> Float {
        guard sampleRate > 0, !left.isEmpty else { return -.infinity }
        let frameCount = right.map { min(left.count, $0.count) } ?? left.count
        guard frameCount > 0 else { return -.infinity }

        let kLeft = kWeight(left, sampleRate: sampleRate)
        let kRight = right.map { kWeight($0, sampleRate: sampleRate) }

        let blockFrames = max(1, Int((blockDurationSeconds * sampleRate).rounded()))
        let hopFrames = max(1, Int((Double(blockFrames) * blockHopFraction).rounded()))
        guard frameCount >= blockFrames else {
            let z = meanSquarePower(left: kLeft, right: kRight, start: 0, count: frameCount)
            return loudnessFromMeanSquare(z)
        }

        var blockMeanSquares: [Float] = []
        blockMeanSquares.reserveCapacity(max(1, (frameCount - blockFrames) / hopFrames + 1))
        var start = 0
        while start + blockFrames <= frameCount {
            blockMeanSquares.append(
                meanSquarePower(left: kLeft, right: kRight, start: start, count: blockFrames)
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

    /// Soft master limiter / brickwall safety so sample peak stays ≤ `ceiling`
    /// (~0.99 ≈ −0.1 dBTP). Shared by peak-normalize and LUFS bounce paths.
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

    // MARK: - Report (Week 71 / 76)

    /// Post-bounce loudness report: K-weighted integrated LUFS + inter-sample true peak.
    public struct Report: Sendable, Equatable {
        public var integratedLUFS: Float
        /// Inter-sample true peak in dBFS (4× linear oversample, max of L/R).
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
    public static func report(left: [Float],
                              right: [Float]? = nil,
                              sampleRate: Double = 48_000,
                              targetLUFS: Float? = nil) -> Report {
        let integrated = integratedLUFS(left: left, right: right, sampleRate: sampleRate)
        let leftTP = truePeakDB(left)
        let rightTP = right.map { truePeakDB($0) } ?? -.infinity
        let truePeak = max(leftTP, rightTP)
        return Report(integratedLUFS: integrated,
                      truePeakDBFS: truePeak,
                      targetLUFS: targetLUFS,
                      sampleRate: sampleRate)
    }

    // MARK: - True peak (Week 76)

    /// Linear peak of `samples` after 4× linear oversampling (inter-sample lite).
    public static func truePeakLinear(_ samples: [Float], oversample: Int = 4) -> Float {
        guard !samples.isEmpty else { return 0 }
        let factor = max(1, oversample)
        var peak = abs(samples[0])
        if samples.count == 1 { return peak }
        for i in 0..<(samples.count - 1) {
            let a = samples[i]
            let b = samples[i + 1]
            peak = max(peak, abs(a), abs(b))
            if factor > 1 {
                for k in 1..<factor {
                    let t = Float(k) / Float(factor)
                    let y = a + (b - a) * t
                    peak = max(peak, abs(y))
                }
            }
        }
        return peak
    }

    /// Inter-sample true peak in dBFS (20·log10). Floor for silence.
    public static func truePeakDB(_ samples: [Float], oversample: Int = 4) -> Float {
        let peak = truePeakLinear(samples, oversample: oversample)
        guard peak > 1e-20 else { return -160 }
        return 20 * log10(peak)
    }

    // MARK: - Live / momentary (Week 59 / 76)

    /// Momentary loudness from a short buffer (GarageBand / Reels live meter lite).
    ///
    /// K-weighted ungated mean-square → LUFS. Returns `-∞` for silence / empty.
    public static func momentaryLUFS(left: [Float],
                                     right: [Float]? = nil,
                                     sampleRate: Double = 48_000) -> Float {
        guard sampleRate > 0, !left.isEmpty else { return -.infinity }
        let frameCount = right.map { min(left.count, $0.count) } ?? left.count
        guard frameCount > 0 else { return -.infinity }
        let kLeft = kWeight(left, sampleRate: sampleRate)
        let kRight = right.map { kWeight($0, sampleRate: sampleRate) }
        let z = meanSquarePower(left: kLeft, right: kRight, start: 0, count: frameCount)
        return loudnessFromMeanSquare(z)
    }

    /// Convert channel-summed mean-square power to LUFS (BS.1770 constant).
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

    // MARK: - K-weighting (ITU BS.1770-4 Annex 1 @ 48 kHz)

    /// Apply K-weighting (pre-filter high shelf + RLB highpass) to one channel.
    ///
    /// Uses the published 48 kHz stage coefficients for all rates (MVP). Primary
    /// path is 48 kHz project audio.
    public static func kWeight(_ input: [Float], sampleRate: Double) -> [Float] {
        guard !input.isEmpty, sampleRate > 0 else { return input }
        // Pre-filter (high shelf) — BS.1770-4 @ 48 kHz.
        var pre = BiquadDF2(
            b0: 1.53512485958697,
            b1: -2.69169618940638,
            b2: 1.19839281085285,
            a1: -1.69065929318241,
            a2: 0.73248077421585
        )
        // RLB highpass — BS.1770-4 @ 48 kHz.
        var rlb = BiquadDF2(
            b0: 1.0,
            b1: -2.0,
            b2: 1.0,
            a1: -1.99004745483398,
            a2: 0.99007225036621
        )
        var out = [Float](repeating: 0, count: input.count)
        for i in input.indices {
            out[i] = rlb.process(pre.process(input[i]))
        }
        return out
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

    /// Direct-form II biquad (a0 normalized to 1).
    private struct BiquadDF2 {
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float
        var z1: Float = 0
        var z2: Float = 0

        init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
            self.b0 = Float(b0)
            self.b1 = Float(b1)
            self.b2 = Float(b2)
            self.a1 = Float(a1)
            self.a2 = Float(a2)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }
}
