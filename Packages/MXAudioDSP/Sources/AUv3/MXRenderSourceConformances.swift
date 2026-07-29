import Foundation

/// Conformances that let the engines be hosted by `MXInstrumentAudioUnit`.
///
/// Kept separate from the engines themselves so the AU shell stays an optional
/// wrapper rather than something every engine has to know about.

extension MXSynthEngine: MXAudioUnitRenderSource {

    public var exposedParameters: [MXParamID] {
        [.osc1Level, .osc1Waveform, .osc1Coarse, .osc1Fine,
         .osc2Level, .osc2Waveform, .osc2Coarse, .osc2Detune,
         .fmLevel, .fmMod, .subLevel, .subOctave,
         .ampAttack, .ampDecay, .ampSustain, .ampRelease,
         .filterCutoff, .filterResonance, .volume]
    }

    public func setParameter(_ id: MXParamID, value: Float) {
        parameters.set(id, value)
    }

    public func parameter(_ id: MXParamID) -> Float {
        parameters.value(id)
    }

    public func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, frameOffset: Int) {
        noteOn(note, velocity: velocity, channel: channel, frameOffset: frameOffset)
    }

    public func noteOff(note: UInt8, channel: UInt8, frameOffset: Int) {
        noteOff(note, channel: channel, frameOffset: frameOffset)
    }

    public func captureState() -> Data {
        (try? JSONEncoder().encode(currentPreset(named: "AUv3"))) ?? Data()
    }

    public func restoreState(_ data: Data) throws {
        do {
            apply(preset: try JSONDecoder().decode(MXSynthPreset.self, from: data))
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }
    }
}

extension MXSFZSampler: MXAudioUnitRenderSource {

    public var exposedParameters: [MXParamID] {
        [.volume, .pan, .filterCutoff, .filterResonance]
    }

    public func setParameter(_ id: MXParamID, value: Float) {
        auParameters.set(id, value)
    }

    public func parameter(_ id: MXParamID) -> Float {
        auParameters.value(id)
    }

    /// The sampler's own state is the SFZ path plus parameters. Sample data is
    /// never embedded — a preset that inlined a multi-gigabyte library would be
    /// unusable in a host document.
    private struct AUState: Codable {
        var sfzPath: String?
        var parameters: [UInt64: Float]
    }

    public func captureState() -> Data {
        let state = AUState(sfzPath: loadedURL?.path, parameters: auParameters.snapshot())
        return (try? JSONEncoder().encode(state)) ?? Data()
    }

    public func restoreState(_ data: Data) throws {
        let state: AUState
        do {
            state = try JSONDecoder().decode(AUState.self, from: data)
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }
        auParameters.restore(state.parameters)
        if let path = state.sfzPath {
            try loadSFZ(url: URL(fileURLWithPath: path))
        }
    }
}
