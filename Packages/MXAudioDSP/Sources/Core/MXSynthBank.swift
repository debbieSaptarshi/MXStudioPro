import Foundation

/// Named synth / keys bank for Piano Studio (GarageBand Keyboard / BandLab Keys lite).
public enum MXSynthBankPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case synthwave1974
    case softKeys
    case warmPad
    case pulseBass
    case pluckLead
    case drumKit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .synthwave1974: return "Synthwave"
        case .softKeys: return "Soft Keys"
        case .warmPad: return "Warm Pad"
        case .pulseBass: return "Pulse Bass"
        case .pluckLead: return "Pluck"
        case .drumKit: return "Drum Kit"
        }
    }

    public var subtitle: String {
        switch self {
        case .synthwave1974: return "Square + detuned saw"
        case .softKeys: return "Gentle piano-ish tone"
        case .warmPad: return "Slow attack wash"
        case .pulseBass: return "Low pulse foundation"
        case .pluckLead: return "Short bright lead"
        case .drumKit: return "Short one-shot percussion"
        }
    }

    /// Presets shown in Piano FX (excludes drum kit).
    public static var pianoBank: [MXSynthBankPreset] {
        allCases.filter { $0 != .drumKit }
    }

    public var preset: MXSynthPreset {
        switch self {
        case .synthwave1974:
            return .synthwave1974
        case .softKeys:
            return MXSynthPreset(name: "SOFT KEYS", parameters: [
                .osc1Level: 0.85,
                .osc1Waveform: Float(MXWaveform.sine.rawValue),
                .osc1Coarse: 0,
                .osc1Fine: 0,
                .osc2Level: 0.25,
                .osc2Waveform: Float(MXWaveform.triangle.rawValue),
                .osc2Coarse: 0,
                .osc2Detune: 3,
                .fmLevel: 0.0,
                .fmMod: 0.0,
                .subLevel: 0.12,
                .subOctave: 1,
                .ampAttack: 0.005,
                .ampDecay: 0.35,
                .ampSustain: 0.55,
                .ampRelease: 0.45,
                .filterCutoff: 6_500,
                .filterResonance: 0.08,
            ])
        case .warmPad:
            return MXSynthPreset(name: "WARM PAD", parameters: [
                .osc1Level: 0.55,
                .osc1Waveform: Float(MXWaveform.sawtooth.rawValue),
                .osc1Coarse: 0,
                .osc1Fine: 0,
                .osc2Level: 0.55,
                .osc2Waveform: Float(MXWaveform.sawtooth.rawValue),
                .osc2Coarse: 0,
                .osc2Detune: 12,
                .fmLevel: 0.0,
                .fmMod: 0.0,
                .subLevel: 0.2,
                .subOctave: 1,
                .ampAttack: 0.55,
                .ampDecay: 0.4,
                .ampSustain: 0.85,
                .ampRelease: 1.2,
                .filterCutoff: 3_200,
                .filterResonance: 0.2,
            ])
        case .pulseBass:
            return MXSynthPreset(name: "PULSE BASS", parameters: [
                .osc1Level: 0.9,
                .osc1Waveform: Float(MXWaveform.square.rawValue),
                .osc1Coarse: -12,
                .osc1Fine: 0,
                .osc2Level: 0.35,
                .osc2Waveform: Float(MXWaveform.sawtooth.rawValue),
                .osc2Coarse: -12,
                .osc2Detune: 4,
                .fmLevel: 0.05,
                .fmMod: 0.1,
                .subLevel: 0.55,
                .subOctave: 1,
                .ampAttack: 0.01,
                .ampDecay: 0.25,
                .ampSustain: 0.7,
                .ampRelease: 0.2,
                .filterCutoff: 2_400,
                .filterResonance: 0.28,
            ])
        case .pluckLead:
            return MXSynthPreset(name: "PLUCK", parameters: [
                .osc1Level: 0.8,
                .osc1Waveform: Float(MXWaveform.sawtooth.rawValue),
                .osc1Coarse: 0,
                .osc1Fine: 0,
                .osc2Level: 0.4,
                .osc2Waveform: Float(MXWaveform.square.rawValue),
                .osc2Coarse: 12,
                .osc2Detune: 2,
                .fmLevel: 0.15,
                .fmMod: 0.25,
                .subLevel: 0.0,
                .subOctave: 1,
                .ampAttack: 0.002,
                .ampDecay: 0.18,
                .ampSustain: 0.15,
                .ampRelease: 0.22,
                .filterCutoff: 9_000,
                .filterResonance: 0.22,
            ])
        case .drumKit:
            // Short one-shots — different pad MIDI notes read as pitched percussion.
            return MXSynthPreset(name: "DRUM KIT", parameters: [
                .osc1Level: 0.95,
                .osc1Waveform: Float(MXWaveform.square.rawValue),
                .osc1Coarse: 0,
                .osc1Fine: 0,
                .osc2Level: 0.55,
                .osc2Waveform: Float(MXWaveform.sawtooth.rawValue),
                .osc2Coarse: 0,
                .osc2Detune: 18,
                .fmLevel: 0.35,
                .fmMod: 0.55,
                .subLevel: 0.45,
                .subOctave: 1,
                .ampAttack: 0.001,
                .ampDecay: 0.12,
                .ampSustain: 0.05,
                .ampRelease: 0.08,
                .filterCutoff: 7_500,
                .filterResonance: 0.35,
            ])
        }
    }

    public static let trackSeed: MXSynthBankPreset = .softKeys

    public static func matching(displayName: String) -> MXSynthBankPreset? {
        allCases.first { $0.preset.name.caseInsensitiveCompare(displayName) == .orderedSame }
            ?? allCases.first { $0.title.caseInsensitiveCompare(displayName) == .orderedSame }
    }
}
