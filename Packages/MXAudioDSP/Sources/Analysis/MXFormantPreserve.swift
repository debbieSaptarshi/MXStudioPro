import Foundation

/// Melodyne / GarageBand-style formant preservation lite for pitch correction (Week 85).
///
/// After pitch shifting by ratio `R`, compensates the spectral envelope so vocals
/// don't sound "chipmunk" or "monster" at strong correction amounts.
public enum MXFormantPreserve: Sendable {

    /// Blend formant-corrected output with raw pitch-shifted audio.
    ///
    /// - Parameters:
    ///   - shifted: Pitch-shifted grain/buffer (same length as `original`).
    ///   - original: Source grain before pitch shift.
    ///   - pitchRatio: Applied pitch ratio (>1 = higher pitch).
    ///   - amount: 0 = no formant fix, 1 = full compensation.
    public static func compensate(
        shifted: [Float],
        original: [Float],
        pitchRatio: Double,
        amount: Float
    ) -> [Float] {
        let blend = Double(max(0, min(1, amount)))
        guard blend > 1e-4, abs(pitchRatio - 1) > 1e-4, !shifted.isEmpty else { return shifted }

        let invRatio = 1.0 / max(0.5, min(2.0, pitchRatio))
        let formantShifted = resample(shifted, ratio: invRatio)
        let restored = resample(formantShifted, ratio: pitchRatio)
        let n = shifted.count

        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let ri = min(restored.count - 1, i)
            let env = abs(restored[ri])
            let pit = abs(shifted[i])
            let target: Float
            if pit > 1e-6 {
                let scale = env / max(pit, 1e-6)
                target = shifted[i] * min(max(scale, 0.25), 4)
            } else {
                target = shifted[i]
            }
            out[i] = Float((1 - blend) * shifted[i] + blend * target)
        }
        return out
    }

    /// Linear-interpolation resample (shared with pitch correct).
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
