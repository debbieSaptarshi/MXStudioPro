import Foundation

/// Transposed direct form II biquad. Used for the synth filter and as the
/// building block of the parametric EQ behind the Figma EQ screen.
public struct MXBiquad {
    public enum Kind: Sendable {
        case lowpass, highpass, bandpass, peaking, lowShelf, highShelf, notch
    }

    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    public init() {}

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }

    public mutating func configure(kind: Kind,
                                   frequency: Float,
                                   q: Float,
                                   gainDB: Float = 0,
                                   sampleRate: Double) {
        let nyquist = Float(sampleRate * 0.5)
        let f = min(max(frequency, 10), nyquist * 0.99)
        let qq = max(q, 0.05)
        let omega = 2 * Float.pi * f / Float(sampleRate)
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2 * qq)
        let A = pow(10, gainDB / 40)

        var nb0: Float, nb1: Float, nb2: Float, na0: Float, na1: Float, na2: Float

        switch kind {
        case .lowpass:
            nb0 = (1 - cosOmega) / 2
            nb1 = 1 - cosOmega
            nb2 = (1 - cosOmega) / 2
            na0 = 1 + alpha
            na1 = -2 * cosOmega
            na2 = 1 - alpha

        case .highpass:
            nb0 = (1 + cosOmega) / 2
            nb1 = -(1 + cosOmega)
            nb2 = (1 + cosOmega) / 2
            na0 = 1 + alpha
            na1 = -2 * cosOmega
            na2 = 1 - alpha

        case .bandpass:
            nb0 = alpha
            nb1 = 0
            nb2 = -alpha
            na0 = 1 + alpha
            na1 = -2 * cosOmega
            na2 = 1 - alpha

        case .notch:
            nb0 = 1
            nb1 = -2 * cosOmega
            nb2 = 1
            na0 = 1 + alpha
            na1 = -2 * cosOmega
            na2 = 1 - alpha

        case .peaking:
            nb0 = 1 + alpha * A
            nb1 = -2 * cosOmega
            nb2 = 1 - alpha * A
            na0 = 1 + alpha / A
            na1 = -2 * cosOmega
            na2 = 1 - alpha / A

        case .lowShelf:
            let sqrtA = sqrt(A)
            let beta = 2 * sqrtA * alpha
            nb0 = A * ((A + 1) - (A - 1) * cosOmega + beta)
            nb1 = 2 * A * ((A - 1) - (A + 1) * cosOmega)
            nb2 = A * ((A + 1) - (A - 1) * cosOmega - beta)
            na0 = (A + 1) + (A - 1) * cosOmega + beta
            na1 = -2 * ((A - 1) + (A + 1) * cosOmega)
            na2 = (A + 1) + (A - 1) * cosOmega - beta

        case .highShelf:
            let sqrtA = sqrt(A)
            let beta = 2 * sqrtA * alpha
            nb0 = A * ((A + 1) + (A - 1) * cosOmega + beta)
            nb1 = -2 * A * ((A - 1) + (A + 1) * cosOmega)
            nb2 = A * ((A + 1) + (A - 1) * cosOmega - beta)
            na0 = (A + 1) - (A - 1) * cosOmega + beta
            na1 = 2 * ((A - 1) - (A + 1) * cosOmega)
            na2 = (A + 1) - (A - 1) * cosOmega - beta
        }

        b0 = nb0 / na0
        b1 = nb1 / na0
        b2 = nb2 / na0
        a1 = na1 / na0
        a2 = na2 / na0
    }

    @inline(__always)
    public mutating func process(_ input: Float) -> Float {
        let out = b0 * input + z1
        z1 = b1 * input - a1 * out + z2
        z2 = b2 * input - a2 * out
        return out
    }

    /// Magnitude response in dB at a frequency. Backs the EQ curve rendering and
    /// lets FX-07 assert on the filter analytically instead of by ear.
    public func magnitudeDB(at frequency: Float, sampleRate: Double) -> Float {
        let omega = 2 * Float.pi * frequency / Float(sampleRate)
        let cosW = cos(omega), sinW = sin(omega)
        let cos2W = cos(2 * omega), sin2W = sin(2 * omega)

        let numReal = b0 + b1 * cosW + b2 * cos2W
        let numImag = -(b1 * sinW + b2 * sin2W)
        let denReal = 1 + a1 * cosW + a2 * cos2W
        let denImag = -(a1 * sinW + a2 * sin2W)

        let numMag = sqrt(numReal * numReal + numImag * numImag)
        let denMag = sqrt(denReal * denReal + denImag * denImag)
        guard denMag > 0 else { return -120 }
        return 20 * log10(max(numMag / denMag, 1e-9))
    }
}
