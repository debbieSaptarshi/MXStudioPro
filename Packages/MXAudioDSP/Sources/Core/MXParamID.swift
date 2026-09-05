import Foundation

/// Stable identifiers for anything automatable. Raw values are persisted in
/// project files and in AUv3 parameter addresses, so they must never be
/// renumbered once shipped.
public enum MXParamID: UInt64, CaseIterable, Sendable, Codable {
    // Channel strip
    case volume = 0
    case pan = 1
    case mute = 2
    case solo = 3

    // Oscillator 1
    case osc1Level = 100
    case osc1Waveform = 101
    case osc1Coarse = 102
    case osc1Fine = 103
    case osc1Shape = 104

    // Oscillator 2
    case osc2Level = 200
    case osc2Waveform = 201
    case osc2Coarse = 202
    case osc2Fine = 203
    case osc2Detune = 204

    // FM + sub
    case fmLevel = 300
    case fmMod = 301
    case subLevel = 310
    case subOctave = 311

    // Amp envelope
    case ampAttack = 400
    case ampDecay = 401
    case ampSustain = 402
    case ampRelease = 403

    // Filter
    case filterCutoff = 500
    case filterResonance = 501

    // Amp sim / EQ (Figma "Amp" screen)
    case ampGain = 600
    case ampBass = 601
    case ampMids = 602
    case ampTreble = 603
    case ampPresence = 604
    case ampMaster = 605

    // Generic pedal parameters (Figma "Pedalboard" screen)
    case fxTime = 700
    case fxMix = 701
    case fxFeedback = 702
    case fxBalance = 703
    case fxFilter = 704
    case fxDepth = 705
    case fxSpeed = 706
    case fxLevel = 707
    case fxBypass = 708

    // Master bus
    case masterPitch = 800

    /// Value range enforced before the value reaches the render thread.
    public var range: ClosedRange<Float> {
        switch self {
        case .pan:
            return -1.0...1.0
        case .mute, .solo, .fxBypass:
            return 0.0...1.0
        case .volume, .osc1Level, .osc2Level, .fmLevel, .subLevel, .ampMaster, .fxLevel:
            return 0.0...1.0
        case .osc1Coarse, .osc2Coarse:
            return -24.0...24.0
        case .osc1Fine, .osc2Fine, .osc2Detune:
            return -100.0...100.0
        case .osc1Waveform, .osc2Waveform:
            return 0.0...3.0
        case .subOctave:
            return 1.0...2.0
        case .ampAttack, .ampDecay, .ampRelease:
            return 0.0...10.0
        case .ampSustain:
            return 0.0...1.0
        case .filterCutoff:
            return 20.0...20_000.0
        case .filterResonance:
            return 0.0...1.0
        case .fxTime:
            return 0.0...2000.0
        case .masterPitch:
            return -12.0...12.0
        default:
            return 0.0...100.0
        }
    }

    public func clamp(_ value: Float) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
