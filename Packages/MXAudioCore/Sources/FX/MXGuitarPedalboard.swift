import Foundation

/// Named guitar pedalboard presets (BandLab / GarageBand amp-path lite).
/// Order of the live board is Dist → Delay → Reverb (Select Guitar Effect).
public enum MXGuitarPedalPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case clean
    case crunch
    case lead
    case ambient

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clean: return "Clean"
        case .crunch: return "Crunch"
        case .lead: return "Lead"
        case .ambient: return "Ambient"
        }
    }

    public var subtitle: String {
        switch self {
        case .clean: return "DI sparkle, light space"
        case .crunch: return "Amp grit + slap delay"
        case .lead: return "Saturated lead, longer trail"
        case .ambient: return "Washes of delay + reverb"
        }
    }

    /// Distortion wet/dry 0…100.
    public var distortionMix: Float {
        switch self {
        case .clean: return 8
        case .crunch: return 42
        case .lead: return 72
        case .ambient: return 18
        }
    }

    /// Delay wet/dry 0…100.
    public var delayMix: Float {
        switch self {
        case .clean: return 8
        case .crunch: return 22
        case .lead: return 28
        case .ambient: return 45
        }
    }

    /// Delay time in seconds.
    public var delayTime: Float {
        switch self {
        case .clean: return 0.22
        case .crunch: return 0.32
        case .lead: return 0.38
        case .ambient: return 0.48
        }
    }

    /// Reverb wet/dry 0…100.
    public var reverbMix: Float {
        switch self {
        case .clean: return 12
        case .crunch: return 18
        case .lead: return 28
        case .ambient: return 48
        }
    }

    /// Mild tone nudge for the mid EQ band (−12…+12 dB).
    public var eqMidGain: Float {
        switch self {
        case .clean: return 1.0
        case .crunch: return 2.0
        case .lead: return 3.0
        case .ambient: return -0.5
        }
    }

    /// Default seed when creating a guitar track (Crunch ≈ BandLab starter).
    public static let trackSeed: MXGuitarPedalPreset = .crunch

    /// True when the track mixes are within a small epsilon of this preset.
    public func matches(
        distortionMix: Float,
        delayMix: Float,
        delayTime: Float,
        reverbMix: Float,
        tolerance: Float = 1.5
    ) -> Bool {
        abs(distortionMix - self.distortionMix) <= tolerance
            && abs(delayMix - self.delayMix) <= tolerance
            && abs(delayTime - self.delayTime) <= 0.03
            && abs(reverbMix - self.reverbMix) <= tolerance
    }

    /// Soft-clip distortion approximation for offline bounce (no AVAudioUnit).
    /// `amount` is 0…100 wet mix; returns processed mono sample.
    public static func bounceDistortion(sample: Float, amount: Float) -> Float {
        let wet = min(max(amount, 0), 100) / 100
        guard wet > 1e-4 else { return sample }
        // Soft fold + gentle drive (Logic/GarageBand grit lite).
        let driven = sample * (1 + 3.5 * wet)
        let shaped = tanhf(driven * (0.85 + 1.4 * wet))
        return sample * (1 - wet) + shaped * wet
    }
}
