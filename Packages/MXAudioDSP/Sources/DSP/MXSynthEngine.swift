import Foundation

/// Polyphonic dual-oscillator synth behind the Figma "Synthwave 1974" screen.
///
/// Lives in `MXAudioDSP` because the AUv3 extension links this module and
/// nothing above it — the extension ships this exact engine.
///
/// Signal path per voice:
/// `OSC1 + OSC2(detuned) + Sub + FM` -> lowpass -> amp envelope
public final class MXSynthEngine: @unchecked Sendable {

    private struct Voice {
        var osc1 = MXOscillator()
        var osc2 = MXOscillator()
        var sub = MXOscillator()
        var modulator = MXOscillator()
        var filter = MXBiquad()
        var envelope = MXEnvelope()
        var note: UInt8 = 60
        var velocity: Float = 1
        var active = false
    }

    public let parameters = MXParameterStore()
    private let events = MXEventRing(capacity: 512)
    private let allocator: MXVoiceAllocator
    private var voices: [Voice]
    private var sampleRate: Double

    /// Smoothed so a fader move never steps the output.
    private var masterGain: MXSmoothedParameter
    private var cutoffSmoother: MXSmoothedParameter

    public init(sampleRate: Double = 48_000, polyphony: Int = 16) {
        self.sampleRate = sampleRate
        allocator = MXVoiceAllocator(capacity: polyphony, maxCapacity: 64)
        voices = Array(repeating: Voice(), count: 64)
        masterGain = MXSmoothedParameter(initial: 1, smoothingMs: 15, sampleRate: sampleRate)
        cutoffSmoother = MXSmoothedParameter(initial: 20_000, smoothingMs: 30, sampleRate: sampleRate)
        configureVoices()
        apply(preset: .synthwave1974)
    }

    private func configureVoices() {
        for i in 0..<voices.count {
            voices[i].osc1.setSampleRate(sampleRate)
            voices[i].osc2.setSampleRate(sampleRate)
            voices[i].sub.setSampleRate(sampleRate)
            voices[i].modulator.setSampleRate(sampleRate)
            voices[i].envelope.setSampleRate(sampleRate)
            voices[i].sub.waveform = .square
            voices[i].modulator.waveform = .sine
        }
    }

    public func setSampleRate(_ rate: Double) {
        sampleRate = rate
        configureVoices()
        masterGain = MXSmoothedParameter(initial: masterGain.current,
                                         smoothingMs: 15, sampleRate: rate)
        cutoffSmoother = MXSmoothedParameter(initial: cutoffSmoother.current,
                                             smoothingMs: 30, sampleRate: rate)
    }

    public var polyphony: Int {
        get { allocator.capacity }
        set {
            allocator.setCapacity(newValue) { index in
                if index < voices.count { voices[index].active = false }
            }
        }
    }

    public var activeVoiceCount: Int { allocator.activeVoiceCount }

    public func apply(preset: MXSynthPreset) {
        parameters.restore(preset.parameters)
    }

    public func currentPreset(named name: String) -> MXSynthPreset {
        MXSynthPreset(name: name, rawParameters: parameters.snapshot())
    }

    // MARK: - Control thread

    public func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8 = 0, frameOffset: Int = 0) {
        guard velocity > 0 else {
            noteOff(note, channel: channel, frameOffset: frameOffset)
            return
        }
        let index = allocator.allocate(note: note, channel: channel)
        events.push(MXVoiceEvent(kind: .noteOn,
                                 note: note,
                                 velocity: velocity,
                                 channel: channel,
                                 frameOffset: Int32(frameOffset),
                                 chokeGroup: Int32(index)))
    }

    public func noteOff(_ note: UInt8, channel: UInt8 = 0, frameOffset: Int = 0) {
        allocator.release(note: note, channel: channel) { index in
            events.push(MXVoiceEvent(kind: .noteOff,
                                     note: note,
                                     channel: channel,
                                     frameOffset: Int32(frameOffset),
                                     chokeGroup: Int32(index)))
        }
    }

    public func allNotesOff() {
        allocator.releaseAll { _ in }
        events.push(MXVoiceEvent(kind: .allNotesOff))
    }

    // MARK: - Render thread

    public func render(left: UnsafeMutablePointer<Float>,
                       right: UnsafeMutablePointer<Float>,
                       frameCount: Int) {
        while let event = events.pop() {
            let vi = Int(event.chokeGroup)
            switch event.kind {
            case .noteOn:
                guard vi >= 0, vi < voices.count else { break }
                startVoice(at: vi, note: event.note, velocity: event.velocity)
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

        let osc1Level = parameters.value(.osc1Level)
        let osc2Level = parameters.value(.osc2Level)
        let subLevel = parameters.value(.subLevel)
        let fmLevel = parameters.value(.fmLevel)
        let fmMod = parameters.value(.fmMod)
        let resonance = parameters.value(.filterResonance)
        let cutoffTarget = parameters.value(.filterCutoff)
        let volumeTarget = parameters.value(.volume)

        let osc1Wave = MXWaveform(rawValue: Int(parameters.value(.osc1Waveform))) ?? .square
        let osc2Wave = MXWaveform(rawValue: Int(parameters.value(.osc2Waveform))) ?? .sawtooth
        let osc1Coarse = parameters.value(.osc1Coarse)
        let osc1Fine = parameters.value(.osc1Fine)
        let osc2Coarse = parameters.value(.osc2Coarse)
        let osc2Detune = parameters.value(.osc2Detune)
        let subOctave = max(1, Int(parameters.value(.subOctave)))

        for i in 0..<frameCount {
            left[i] = 0
            right[i] = 0
        }

        for vi in 0..<voices.count where voices[vi].active {
            voices[vi].osc1.waveform = osc1Wave
            voices[vi].osc2.waveform = osc2Wave

            let note = Float(voices[vi].note)
            let f1 = mxNoteToHz(note + osc1Coarse + osc1Fine / 100)
            let f2 = mxNoteToHz(note + osc2Coarse + osc2Detune / 100)
            let fSub = mxNoteToHz(note - Float(12 * subOctave))

            voices[vi].osc1.setFrequency(f1)
            voices[vi].osc2.setFrequency(f2)
            voices[vi].sub.setFrequency(fSub)
            // Modulator tracks the note so FM depth is timbral, not a fixed beat.
            voices[vi].modulator.setFrequency(f1 * (1 + fmMod / 100 * 3))

            for i in 0..<frameCount {
                let env = voices[vi].envelope.next()
                if voices[vi].envelope.stage == .idle {
                    voices[vi].active = false
                    allocator.recycle(vi)
                    break
                }

                var sample: Float = 0
                if fmLevel > 0.0001 {
                    // Phase-modulate OSC1 by re-tuning it per sample; cheap and
                    // stable, and enough to move harmonic content for SY-03.
                    let mod = voices[vi].modulator.next() * fmLevel
                    voices[vi].osc1.setFrequency(f1 * (1 + mod * 0.5))
                }
                sample += voices[vi].osc1.next() * osc1Level
                sample += voices[vi].osc2.next() * osc2Level
                if subLevel > 0.0001 {
                    sample += voices[vi].sub.next() * subLevel
                }

                let cutoff = cutoffSmoother.next(target: cutoffTarget)
                voices[vi].filter.configure(kind: .lowpass,
                                            frequency: cutoff,
                                            q: 0.707 + resonance * 6,
                                            sampleRate: sampleRate)
                sample = voices[vi].filter.process(sample)

                let amplitude = env * voices[vi].velocity
                let out = sample * amplitude
                left[i] += out
                right[i] += out
            }
        }

        // Master gain and a soft ceiling so stacked voices cannot hard-clip the
        // bus; I-01 asserts "not clipped".
        for i in 0..<frameCount {
            let g = masterGain.next(target: volumeTarget)
            left[i] = MXSynthEngine.softClip(left[i] * g * 0.3)
            right[i] = MXSynthEngine.softClip(right[i] * g * 0.3)
        }
    }

    private func startVoice(at index: Int, note: UInt8, velocity: UInt8) {
        voices[index].note = note
        voices[index].velocity = Float(velocity) / 127
        voices[index].envelope.setSampleRate(sampleRate)
        voices[index].envelope.attackSeconds = parameters.value(.ampAttack)
        voices[index].envelope.decaySeconds = parameters.value(.ampDecay)
        voices[index].envelope.sustainLevel = parameters.value(.ampSustain)
        voices[index].envelope.releaseSeconds = parameters.value(.ampRelease)
        voices[index].envelope.reset()
        voices[index].envelope.noteOn()
        voices[index].osc1.resetPhase()
        voices[index].osc2.resetPhase(0.25)
        voices[index].sub.resetPhase()
        voices[index].modulator.resetPhase()
        voices[index].filter.reset()
        voices[index].active = true
    }

    @inline(__always)
    private static func softClip(_ x: Float) -> Float {
        if x > 1 { return 1 }
        if x < -1 { return -1 }
        return x - (x * x * x) / 3
    }
}
