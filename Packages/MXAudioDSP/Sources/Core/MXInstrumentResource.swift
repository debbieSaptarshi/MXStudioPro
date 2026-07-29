import Foundation

/// What a backend can be asked to load. The pack system resolves a manifest
/// down to one of these, which is the only vocabulary a backend understands.
public enum MXInstrumentResource: Equatable, Sendable {
    /// SoundFont / DLS / EXS24 / .aupreset handled by `AVAudioUnitSampler`.
    case soundBank(url: URL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8)

    /// SFZ definition handled by the SFZ engine.
    case sfz(url: URL)

    /// A folder of raw samples. Imported by synthesising an SFZ mapping, so it
    /// converges on the same code path rather than a second mapping engine.
    case sampleFolder(url: URL, rootNote: UInt8)

    /// A parameter-only preset for the synth backend.
    case synthPreset(MXSynthPreset)

    /// A hosted third-party AUv3.
    case auv3(componentDescription: MXComponentDescription)

    public var displayName: String {
        switch self {
        case .soundBank(let url, let program, _, _):
            return "\(url.lastPathComponent) program \(program)"
        case .sfz(let url):
            return url.lastPathComponent
        case .sampleFolder(let url, _):
            return url.lastPathComponent
        case .synthPreset(let preset):
            return preset.name
        case .auv3(let desc):
            return desc.name
        }
    }
}

/// POD mirror of `AudioComponentDescription` so `MXAudioDSP` stays free of
/// AudioToolbox-host concerns and remains `Sendable`.
public struct MXComponentDescription: Equatable, Codable, Sendable {
    public var name: String
    public var manufacturer: String
    public var type: UInt32
    public var subType: UInt32
    public var manufacturerCode: UInt32

    public init(name: String,
                manufacturer: String,
                type: UInt32,
                subType: UInt32,
                manufacturerCode: UInt32) {
        self.name = name
        self.manufacturer = manufacturer
        self.type = type
        self.subType = subType
        self.manufacturerCode = manufacturerCode
    }
}

/// Serialisable synth state. Doubles as the AUv3 preset payload, which is why
/// it is `Codable` rather than a bag of floats.
public struct MXSynthPreset: Equatable, Codable, Sendable {
    public var name: String
    public var parameters: [UInt64: Float]

    public init(name: String, parameters: [MXParamID: Float]) {
        self.name = name
        self.parameters = Dictionary(uniqueKeysWithValues:
            parameters.map { ($0.key.rawValue, $0.value) })
    }

    public init(name: String, rawParameters: [UInt64: Float]) {
        self.name = name
        self.parameters = rawParameters
    }

    public subscript(id: MXParamID) -> Float? {
        get { parameters[id.rawValue] }
        set { parameters[id.rawValue] = newValue }
    }

    /// The default patch behind the Figma "Synthwave 1974" screen: square OSC1,
    /// saw OSC2 detuned, sub on.
    public static let synthwave1974: MXSynthPreset = {
        MXSynthPreset(name: "SYNTHWAVE 1974", parameters: [
            .osc1Level: 0.8,
            .osc1Waveform: Float(MXWaveform.square.rawValue),
            .osc1Coarse: 0,
            .osc1Fine: 0,
            .osc2Level: 0.6,
            .osc2Waveform: Float(MXWaveform.sawtooth.rawValue),
            .osc2Coarse: 0,
            .osc2Detune: 7,
            .fmLevel: 0.0,
            .fmMod: 0.0,
            .subLevel: 0.35,
            .subOctave: 1,
            .ampAttack: 0.01,
            .ampDecay: 0.20,
            .ampSustain: 0.75,
            .ampRelease: 0.30,
            .filterCutoff: 12_000,
            .filterResonance: 0.15,
        ])
    }()
}
