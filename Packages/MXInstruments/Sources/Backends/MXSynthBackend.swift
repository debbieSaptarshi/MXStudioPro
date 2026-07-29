import AVFoundation
import Foundation
import MXAudioDSP

/// The dual-oscillator synth from the Figma "Synthwave 1974" screen.
///
/// The DSP itself lives in `MXAudioDSP` (`MXSynthEngine`) rather than here,
/// because the AUv3 extension ships the same engine and cannot link this
/// module. This class is only the `AVAudioNode` wrapper plus the parameter and
/// preset surface the UI binds to.
public final class MXSynthBackend: MXSourceInstrument, @unchecked Sendable {

    public let synth: MXSynthEngine
    private var presetName: String

    public init(displayName: String = "SYNTHWAVE 1974",
                sampleRate: Double = 48_000,
                polyphony: Int = 16) {
        synth = MXSynthEngine(sampleRate: sampleRate, polyphony: polyphony)
        presetName = displayName
        super.init(displayName: displayName, sampleRate: sampleRate)
    }

    public override var polyphony: Int {
        get { synth.polyphony }
        set { synth.polyphony = newValue }
    }

    public var activeVoiceCount: Int { synth.activeVoiceCount }

    public override func setSampleRate(_ rate: Double) {
        super.setSampleRate(rate)
        synth.setSampleRate(rate)
    }

    public override func load(_ resource: MXInstrumentResource) async throws {
        guard case .synthPreset(let preset) = resource else {
            throw MXAudioError.unsupportedResource(
                "\(resource.displayName) cannot be loaded by the synth backend")
        }
        synth.apply(preset: preset)
        presetName = preset.name
        displayName = preset.name
    }

    public override func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        synth.noteOn(note, velocity: velocity, channel: channel)
    }

    public override func noteOff(_ note: UInt8, channel: UInt8) {
        synth.noteOff(note, channel: channel)
    }

    public override func allNotesOff() {
        synth.allNotesOff()
    }

    public override func setParameter(_ id: MXParamID, value: Float) {
        synth.parameters.set(id, value)
    }

    public override func parameter(_ id: MXParamID) -> Float {
        synth.parameters.value(id)
    }

    // MARK: - Screen-facing conveniences

    public var osc1Waveform: MXWaveform {
        get { MXWaveform(rawValue: Int(parameter(.osc1Waveform))) ?? .square }
        set { setParameter(.osc1Waveform, value: Float(newValue.rawValue)) }
    }

    public var osc2Waveform: MXWaveform {
        get { MXWaveform(rawValue: Int(parameter(.osc2Waveform))) ?? .sawtooth }
        set { setParameter(.osc2Waveform, value: Float(newValue.rawValue)) }
    }

    public func currentPreset() -> MXSynthPreset {
        synth.currentPreset(named: presetName)
    }

    public override func captureState() -> Data {
        (try? JSONEncoder().encode(currentPreset())) ?? Data()
    }

    public override func restoreState(_ data: Data) throws {
        do {
            let preset = try JSONDecoder().decode(MXSynthPreset.self, from: data)
            synth.apply(preset: preset)
            presetName = preset.name
            displayName = preset.name
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }
    }

    public override func render(left: UnsafeMutablePointer<Float>,
                                right: UnsafeMutablePointer<Float>,
                                frameCount: Int) {
        synth.render(left: left, right: right, frameCount: frameCount)
    }
}
