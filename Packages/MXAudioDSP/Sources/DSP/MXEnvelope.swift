import Foundation

/// Exponential ADSR.
///
/// The release stage is what makes scenario I-02 ("silence after release")
/// meaningful, so `isFinished` reports only once the tail has actually decayed
/// below the silence floor rather than the moment the note-off arrives.
public struct MXEnvelope {
    public enum Stage: Sendable {
        case idle, attack, decay, sustain, release
    }

    public private(set) var stage: Stage = .idle
    public private(set) var value: Float = 0

    public var attackSeconds: Float = 0.01
    public var decaySeconds: Float = 0.2
    public var sustainLevel: Float = 0.75
    public var releaseSeconds: Float = 0.3

    /// Below this the voice is considered done and can be recycled.
    public static let silenceFloor: Float = 1e-4

    private var sampleRate: Double = 48_000
    private var coefficient: Float = 0
    private var target: Float = 0

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
    }

    public mutating func setSampleRate(_ rate: Double) {
        sampleRate = rate
    }

    public var isActive: Bool { stage != .idle }

    public mutating func noteOn() {
        stage = .attack
        target = 1
        coefficient = Self.coefficient(seconds: attackSeconds, sampleRate: sampleRate)
    }

    public mutating func noteOff() {
        guard stage != .idle else { return }
        stage = .release
        target = 0
        coefficient = Self.coefficient(seconds: releaseSeconds, sampleRate: sampleRate)
    }

    /// Immediate cut used by drum choke groups, with a short ramp so the cut
    /// itself does not click.
    public mutating func choke(fadeSeconds: Float = 0.005) {
        stage = .release
        target = 0
        coefficient = Self.coefficient(seconds: fadeSeconds, sampleRate: sampleRate)
    }

    public mutating func reset() {
        stage = .idle
        value = 0
        target = 0
    }

    @inline(__always)
    public mutating func next() -> Float {
        switch stage {
        case .idle:
            return 0

        case .attack:
            value += (target - value) * coefficient
            if value >= 0.999 {
                value = 1
                stage = .decay
                target = sustainLevel
                coefficient = Self.coefficient(seconds: decaySeconds, sampleRate: sampleRate)
            }

        case .decay:
            value += (target - value) * coefficient
            if abs(value - sustainLevel) < 1e-4 {
                value = sustainLevel
                stage = .sustain
            }

        case .sustain:
            value = sustainLevel
            if sustainLevel <= Self.silenceFloor {
                stage = .idle
                value = 0
            }

        case .release:
            value += (target - value) * coefficient
            if value <= Self.silenceFloor {
                value = 0
                stage = .idle
            }
        }
        return value
    }

    /// One-pole coefficient that reaches ~99.9% of target in `seconds`.
    @inline(__always)
    private static func coefficient(seconds: Float, sampleRate: Double) -> Float {
        let samples = max(1, Float(sampleRate) * max(seconds, 0.0001))
        return 1 - exp(-6.91 / samples)
    }
}
