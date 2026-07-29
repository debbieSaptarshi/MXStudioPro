import AVFoundation
import Foundation
import MXAudioDSP

/// Minimal reference implementation of `MXInstrument`.
///
/// Its job is to make the shared I-01…I-06 scenarios runnable before any real
/// backend exists, and to stay in the suite afterwards as the control: if a
/// shared instrument test fails for a real backend but passes here, the fault
/// is in the backend and not in the harness.
public final class MXStubInstrument: MXSourceInstrument, @unchecked Sendable {

    private struct Voice {
        var oscillator = MXOscillator()
        var envelope = MXEnvelope()
        var velocity: Float = 0
        var active = false
    }

    private let allocator: MXVoiceAllocator
    private var voices: [Voice]
    private let events = MXEventRing(capacity: 256)
    private let store = MXParameterStore()

    public override var polyphony: Int {
        get { allocator.capacity }
        set {
            allocator.setCapacity(newValue) { index in
                if index < voices.count { voices[index].active = false }
            }
        }
    }

    public init(displayName: String = "Stub", sampleRate: Double = 48_000, polyphony: Int = 16) {
        allocator = MXVoiceAllocator(capacity: polyphony, maxCapacity: 64)
        voices = Array(repeating: Voice(), count: 64)
        super.init(displayName: displayName, sampleRate: sampleRate)
        for i in 0..<voices.count {
            voices[i].oscillator.setSampleRate(sampleRate)
            voices[i].oscillator.waveform = .sine
            voices[i].envelope.setSampleRate(sampleRate)
            voices[i].envelope.attackSeconds = 0.005
            voices[i].envelope.decaySeconds = 0.05
            voices[i].envelope.sustainLevel = 0.8
            voices[i].envelope.releaseSeconds = 0.15
        }
        store.set(.volume, 1)
    }

    public override func load(_ resource: MXInstrumentResource) async throws {
        // The stub is parameter-only; it accepts a synth preset and ignores the
        // rest rather than pretending to load samples.
        guard case .synthPreset(let preset) = resource else {
            throw MXAudioError.unsupportedResource(resource.displayName)
        }
        store.restore(preset.parameters)
    }

    public override func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        guard velocity > 0 else {
            noteOff(note, channel: channel)
            return
        }
        let index = allocator.allocate(note: note, channel: channel)
        events.push(MXVoiceEvent(kind: .noteOn, note: note, velocity: velocity,
                                 channel: channel, chokeGroup: Int32(index)))
    }

    public override func noteOff(_ note: UInt8, channel: UInt8) {
        allocator.release(note: note, channel: channel) { index in
            events.push(MXVoiceEvent(kind: .noteOff, note: note, channel: channel,
                                     chokeGroup: Int32(index)))
        }
    }

    public override func allNotesOff() {
        allocator.releaseAll { _ in }
        events.push(MXVoiceEvent(kind: .allNotesOff))
    }

    public override func setParameter(_ id: MXParamID, value: Float) {
        store.set(id, value)
    }

    public override func parameter(_ id: MXParamID) -> Float {
        store.value(id)
    }

    public override func captureState() -> Data {
        let preset = MXSynthPreset(name: displayName, rawParameters: store.snapshot())
        return (try? JSONEncoder().encode(preset)) ?? Data()
    }

    public override func restoreState(_ data: Data) throws {
        do {
            let preset = try JSONDecoder().decode(MXSynthPreset.self, from: data)
            store.restore(preset.parameters)
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }
    }

    public var activeVoiceCount: Int { allocator.activeVoiceCount }

    public override func render(left: UnsafeMutablePointer<Float>,
                                right: UnsafeMutablePointer<Float>,
                                frameCount: Int) {
        while let event = events.pop() {
            let vi = Int(event.chokeGroup)
            switch event.kind {
            case .noteOn:
                guard vi >= 0, vi < voices.count else { break }
                voices[vi].oscillator.setFrequency(mxNoteToHz(Float(event.note)))
                voices[vi].oscillator.resetPhase()
                voices[vi].velocity = Float(event.velocity) / 127
                voices[vi].envelope.reset()
                voices[vi].envelope.noteOn()
                voices[vi].active = true
            case .noteOff:
                guard vi >= 0, vi < voices.count, voices[vi].active else { break }
                voices[vi].envelope.noteOff()
            case .allNotesOff:
                for j in 0..<voices.count where voices[j].active {
                    voices[j].envelope.noteOff()
                }
            case .choke:
                guard vi >= 0, vi < voices.count else { break }
                voices[vi].envelope.choke()
            }
        }

        for i in 0..<frameCount {
            left[i] = 0
            right[i] = 0
        }

        let gain = store.value(.volume)

        for vi in 0..<voices.count where voices[vi].active {
            for i in 0..<frameCount {
                let env = voices[vi].envelope.next()
                if voices[vi].envelope.stage == .idle {
                    voices[vi].active = false
                    allocator.recycle(vi)
                    break
                }
                let value = voices[vi].oscillator.next() * env * voices[vi].velocity * gain * 0.4
                left[i] += value
                right[i] += value
            }
        }
    }
}
