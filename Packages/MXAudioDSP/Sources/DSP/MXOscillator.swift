import Foundation

/// Matches the four waveform selectors on the Figma synth screen.
public enum MXWaveform: Int, CaseIterable, Sendable, Codable {
    case sine = 0
    case square = 1
    case sawtooth = 2
    case triangle = 3
}

/// PolyBLEP-corrected oscillator.
///
/// Naive saw and square alias badly, which would smear the spectral peak the
/// SY-01 test asserts on. PolyBLEP rounds the discontinuities so the harmonic
/// series stays where it belongs without the cost of full band-limiting.
public struct MXOscillator {
    public var waveform: MXWaveform = .sine
    /// Pulse width for `.square`; 0.5 is a true square.
    public var pulseWidth: Float = 0.5

    private var phase: Double = 0
    private var phaseIncrement: Double = 0
    private var sampleRate: Double = 48_000

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
    }

    public mutating func setSampleRate(_ rate: Double) {
        sampleRate = rate
    }

    public mutating func setFrequency(_ hz: Float) {
        phaseIncrement = Double(max(0, hz)) / sampleRate
    }

    public mutating func resetPhase(_ value: Double = 0) {
        phase = value
    }

    @inline(__always)
    public mutating func next() -> Float {
        let t = phase
        let dt = phaseIncrement
        var out: Float

        switch waveform {
        case .sine:
            out = Float(sin(2 * Double.pi * t))

        case .sawtooth:
            out = Float(2 * t - 1)
            out -= Self.polyBLEP(t: t, dt: dt)

        case .square:
            let pw = Double(min(max(pulseWidth, 0.01), 0.99))
            out = t < pw ? 1 : -1
            out += Self.polyBLEP(t: t, dt: dt)
            var t2 = t + (1 - pw)
            if t2 >= 1 { t2 -= 1 }
            out -= Self.polyBLEP(t: t2, dt: dt)

        case .triangle:
            // Integrating a corrected square gives an alias-suppressed triangle.
            var sq: Float = t < 0.5 ? 1 : -1
            sq += Self.polyBLEP(t: t, dt: dt)
            var t2 = t + 0.5
            if t2 >= 1 { t2 -= 1 }
            sq -= Self.polyBLEP(t: t2, dt: dt)
            triangleState += Float(4 * dt) * sq
            out = triangleState
        }

        phase += dt
        if phase >= 1 { phase -= 1 }
        return out
    }

    private var triangleState: Float = 0

    /// Two-sample polynomial approximation of a band-limited step.
    @inline(__always)
    private static func polyBLEP(t: Double, dt: Double) -> Float {
        guard dt > 0 else { return 0 }
        if t < dt {
            let x = t / dt
            return Float(x + x - x * x - 1)
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            return Float(x * x + x + x + 1)
        }
        return 0
    }
}

/// Equal-tempered MIDI note to frequency, A4 = 69 = 440 Hz.
@inline(__always)
public func mxNoteToHz(_ note: Float, tuningA4: Float = 440) -> Float {
    tuningA4 * pow(2, (note - 69) / 12)
}
