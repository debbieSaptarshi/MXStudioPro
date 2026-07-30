import AudioToolbox
import AVFoundation
import Foundation
import MXAudioDSP

/// Live guitar monitor pedalboard settings (BandLab / GarageBand amp-path lite).
/// Applied on the parallel monitor graph only — write tap stays dry DI.
public struct MXMonitorGuitarFX: Equatable, Sendable {
    public var enabled: Bool
    public var distortionMix: Float // 0…100
    public var delayMix: Float
    public var delayTime: Float // seconds
    public var reverbMix: Float
    public var eqMidGain: Float // −12…+12 dB

    public init(
        enabled: Bool,
        distortionMix: Float,
        delayMix: Float,
        delayTime: Float,
        reverbMix: Float,
        eqMidGain: Float
    ) {
        self.enabled = enabled
        self.distortionMix = distortionMix
        self.delayMix = delayMix
        self.delayTime = delayTime
        self.reverbMix = reverbMix
        self.eqMidGain = eqMidGain
    }

    public static let disabled = MXMonitorGuitarFX(
        enabled: false,
        distortionMix: 0,
        delayMix: 0,
        delayTime: 0.3,
        reverbMix: 0,
        eqMidGain: 0
    )

    /// Clamp mix / gain / time into the ranges used by the pedalboard UI.
    public static func clamped(
        enabled: Bool,
        distortionMix: Float,
        delayMix: Float,
        delayTime: Float,
        reverbMix: Float,
        eqMidGain: Float
    ) -> MXMonitorGuitarFX {
        MXMonitorGuitarFX(
            enabled: enabled,
            distortionMix: min(max(distortionMix, 0), 100),
            delayMix: min(max(delayMix, 0), 100),
            delayTime: min(max(delayTime, 0.01), 2),
            reverbMix: min(max(reverbMix, 0), 100),
            eqMidGain: min(max(eqMidGain, -12), 12)
        )
    }
}

/// Captures the input node to disk, aligned to the transport.
///
/// Frames are written as they arrive rather than buffered to the end, so an
/// interruption leaves a shorter but completely valid file instead of a
/// zero-byte one (plan scenario L-05).
public final class MXRecorder: @unchecked Sendable {

    public struct Take: Sendable {
        public var url: URL
        public var startSample: Int64
        public var frameCount: AVAudioFrameCount
        public var compensationFrames: Int
        public var wasInterrupted: Bool
        /// Frames prepended from the pre-roll ring buffer (capture before Rec).
        public var preRollFrames: AVAudioFrameCount
    }

    public enum RecorderError: Error, Equatable, LocalizedError {
        case alreadyRecording
        case notRecording
        case inputUnavailable
        case fileCreationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Already recording."
            case .notRecording: return "Not currently recording."
            case .inputUnavailable: return "Microphone input is unavailable."
            case .fileCreationFailed(let detail): return "Could not create take file: \(detail)"
            }
        }
    }

    private let graph: MXGraph
    private let transport: MXTransport
    private let calibrator: MXLatencyCalibrator

    private var file: AVAudioFile?
    private var currentURL: URL?
    private var startSample: Int64 = 0
    private var framesWritten: AVAudioFrameCount = 0
    private var preRollFramesWritten: AVAudioFrameCount = 0
    private var interrupted = false
    private let lock = NSLock()
    /// When true, stereo (or multi-channel) tap buffers are downmixed to mono on write.
    private var writeMono = false
    private var monoWriteFormat: AVAudioFormat?
    private var tapInstalled = false
    /// True while `startRecording` drains/prepends pre-roll — tap skips writes.
    private var isStartingTake = false

    /// Direct monitoring routes input to the output. Off by default because on
    /// a speaker route it feeds back (L-04 checks there is no howl).
    public var isMonitoringEnabled = false {
        didSet { updateMonitoring() }
    }

    /// Soft expander on the monitor path (BandLab / GarageBand-style vocal gate).
    public var monitorGateEnabled = false {
        didSet { updateMonitoring() }
    }

    /// Linear amplitude threshold 0…0.2 for the monitor expander.
    public var monitorGateThreshold: Float = 0.02 {
        didSet { configureMonitorGate() }
    }

    /// Wet guitar pedalboard on the monitor path (Dist→Delay→Rev). Off for vocals.
    /// Topology rebuilds when `enabled` flips; param-only changes reconfigure in place.
    public var monitorGuitarFX: MXMonitorGuitarFX = .disabled {
        didSet {
            if oldValue.enabled != monitorGuitarFX.enabled {
                if monitorAttached { detachMonitoring() }
                updateMonitoring()
            } else if monitorGuitarFX.enabled {
                configureMonitorGuitarFX()
            }
        }
    }

    /// Milliseconds of input kept in a ring buffer while armed (pre-roll).
    /// 0 disables. Typical phone-vocal value: 250–500 ms.
    public var preRollMilliseconds: Double = 250 {
        didSet { resizePreRollBuffer() }
    }

    private let monitorMixer = AVAudioMixerNode()
    private var monitorGate: AVAudioUnitEffect?
    private var monitorEQ: AVAudioUnitEQ?
    private var monitorDistortion: AVAudioUnitDistortion?
    private var monitorDelay: AVAudioUnitDelay?
    private var monitorReverb: AVAudioUnitReverb?
    private var monitorAttached = false
    /// When true, Monitor may route input→master even before Rec (armed / record mode).
    private var liveInputArmed = false

    // Pre-roll ring (mono float) filled while armed and not yet recording.
    private var preRollCapacity = 0
    private var preRollBuffer: [Float] = []
    private var preRollWriteIndex = 0
    private var preRollFilled = 0

    public private(set) var isRecording = false
    /// Peak input level 0…1, updated from the write tap for UI meters.
    public private(set) var inputLevel: Float = 0

    /// Arm live input for monitoring while in record mode (not only while writing a take).
    public func setLiveInputArmed(_ armed: Bool) {
        liveInputArmed = armed
        if armed {
            ensureInputTap()
            updateMonitoring()
        } else if !isRecording {
            removeInputTap()
            detachMonitoring()
            clearPreRoll()
        } else {
            updateMonitoring()
        }
    }

    public init(graph: MXGraph, transport: MXTransport, calibrator: MXLatencyCalibrator) {
        self.graph = graph
        self.transport = transport
        self.calibrator = calibrator
        resizePreRollBuffer()

        let previous = graph.session.onEvent
        graph.session.onEvent = { [weak self] event in
            previous?(event)
            switch event {
            case .interruptionBegan, .mediaServicesReset:
                self?.handleInterruption()
            default:
                break
            }
        }
    }

    /// - Parameter preferMono: When true, ask the session for 1 input channel and
    ///   write a mono take (downmix if hardware still delivers stereo). Used for
    ///   vocal-category tracks; guitar / import paths leave this false.
    public func startRecording(to url: URL, preferMono: Bool = false) throws {
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            throw RecorderError.alreadyRecording
        }
        lock.unlock()

        guard graph.session.hasInputPermission() else {
            throw RecorderError.inputUnavailable
        }

        if preferMono {
            graph.session.preferInputChannelCount(1)
        }

        let input = graph.engine.inputNode
        var format = input.inputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate <= 0 {
            // Simulator / cold route: touch the node and retry once.
            _ = input.outputFormat(forBus: 0)
            format = input.inputFormat(forBus: 0)
        }
        if format.channelCount == 0 || format.sampleRate <= 0 {
            // Last resort: a mono float format at the graph rate so Simulator can still write takes.
            guard let fallback = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: graph.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw RecorderError.inputUnavailable
            }
            format = fallback
        }

        let useMono = preferMono || format.channelCount == 1
        let fileFormat: AVAudioFormat
        if useMono, format.channelCount != 1 {
            guard let mono = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw RecorderError.inputUnavailable
            }
            fileFormat = mono
        } else {
            fileFormat = format
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
        } catch {
            let fallbackSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: fileFormat.sampleRate,
                AVNumberOfChannelsKey: useMono ? 1 : max(1, Int(fileFormat.channelCount)),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            do {
                audioFile = try AVAudioFile(forWriting: url, settings: fallbackSettings)
            } catch {
                throw RecorderError.fileCreationFailed(error.localizedDescription)
            }
        }

        // Pause shared-tap file/ring writes while we drain + prepend pre-roll so
        // live buffers cannot interleave ahead of the capture-before-Rec audio.
        lock.lock()
        isStartingTake = true
        writeMono = useMono && format.channelCount > 1
        monoWriteFormat = writeMono ? fileFormat : nil
        lock.unlock()

        let preRoll = drainPreRoll()
        let preRollCount = AVAudioFrameCount(preRoll.count)
        var writtenPreRoll: AVAudioFrameCount = 0
        if !preRoll.isEmpty {
            do {
                try writePreRollSamples(preRoll, to: audioFile, channels: Int(fileFormat.channelCount))
                writtenPreRoll = preRollCount
            } catch {
                // Non-fatal — continue with live capture only.
                writtenPreRoll = 0
            }
        }

        lock.lock()
        file = audioFile
        currentURL = url
        startSample = transport.currentSample
        framesWritten = writtenPreRoll
        preRollFramesWritten = writtenPreRoll
        interrupted = false
        isRecording = true
        isStartingTake = false
        lock.unlock()

        ensureInputTap()
        updateMonitoring()
    }

    @discardableResult
    public func stopRecording() throws -> Take {
        lock.lock()
        guard isRecording, let url = currentURL else {
            lock.unlock()
            throw RecorderError.notRecording
        }
        let take = Take(url: url,
                        startSample: startSample,
                        frameCount: framesWritten,
                        compensationFrames: calibrator.compensationFrames,
                        wasInterrupted: interrupted,
                        preRollFrames: preRollFramesWritten)
        isRecording = false
        file = nil
        currentURL = nil
        writeMono = false
        monoWriteFormat = nil
        preRollFramesWritten = 0
        lock.unlock()

        if liveInputArmed {
            // Keep tap for meters / next pre-roll; drop only the write target.
            clearPreRoll()
            updateMonitoring()
        } else {
            removeInputTap()
            detachMonitoring()
        }
        return take
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let starting = isStartingTake
        let recording = isRecording
        let file = self.file
        let downmix = writeMono
        let monoFormat = monoWriteFormat
        let armed = liveInputArmed
        lock.unlock()

        let peak = Self.peakLevel(in: buffer)
        lock.lock()
        inputLevel = peak
        lock.unlock()

        // Drop buffers while pre-roll is being prepended to avoid file races.
        if starting { return }

        if recording, let file {
            do {
                if downmix, let monoFormat, let mono = Self.downmixToMono(buffer, format: monoFormat) {
                    try file.write(from: mono)
                } else {
                    try file.write(from: buffer)
                }
                lock.lock()
                framesWritten += buffer.frameLength
                lock.unlock()
            } catch {
                handleInterruption()
            }
            return
        }

        // Armed but not recording — fill pre-roll ring for capture-before-Rec.
        if armed {
            pushPreRoll(from: buffer)
        }
    }

    // MARK: - Pre-roll ring

    private func resizePreRollBuffer() {
        let sr = max(graph.sampleRate, 1)
        let ms = max(0, preRollMilliseconds)
        let capacity = Int((ms / 1_000.0) * sr)
        lock.lock()
        preRollCapacity = capacity
        preRollBuffer = capacity > 0 ? [Float](repeating: 0, count: capacity) : []
        preRollWriteIndex = 0
        preRollFilled = 0
        lock.unlock()
    }

    private func clearPreRoll() {
        lock.lock()
        preRollWriteIndex = 0
        preRollFilled = 0
        if !preRollBuffer.isEmpty {
            for i in preRollBuffer.indices { preRollBuffer[i] = 0 }
        }
        lock.unlock()
    }

    private func pushPreRoll(from buffer: AVAudioPCMBuffer) {
        lock.lock()
        let capacity = preRollCapacity
        guard capacity > 0, !preRollBuffer.isEmpty else {
            lock.unlock()
            return
        }
        guard let channels = buffer.floatChannelData else {
            lock.unlock()
            return
        }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0 else {
            lock.unlock()
            return
        }
        for i in 0..<frames {
            var sample: Float
            if channelCount >= 2 {
                sample = 0.5 * (channels[0][i] + channels[1][i])
            } else {
                sample = channels[0][i]
            }
            preRollBuffer[preRollWriteIndex] = sample
            preRollWriteIndex = (preRollWriteIndex + 1) % capacity
            if preRollFilled < capacity {
                preRollFilled += 1
            }
        }
        lock.unlock()
    }

    /// Returns chronological mono samples from the ring (oldest → newest).
    private func drainPreRoll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let capacity = preRollCapacity
        let filled = preRollFilled
        guard capacity > 0, filled > 0, !preRollBuffer.isEmpty else { return [] }
        var out = [Float](repeating: 0, count: filled)
        let start = filled < capacity ? 0 : preRollWriteIndex
        for i in 0..<filled {
            out[i] = preRollBuffer[(start + i) % capacity]
        }
        preRollWriteIndex = 0
        preRollFilled = 0
        return out
    }

    private func writePreRollSamples(_ samples: [Float], to file: AVAudioFile, channels: Int) throws {
        guard !samples.isEmpty else { return }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let dst = buffer.floatChannelData else { return }
        let ch = max(1, min(channels, Int(format.channelCount)))
        for c in 0..<ch {
            samples.withUnsafeBufferPointer { src in
                dst[c].update(from: src.baseAddress!, count: samples.count)
            }
        }
        try file.write(from: buffer)
    }

    /// Average L/R (or first channel) into a mono float buffer for vocal takes.
    private static func downmixToMono(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = Int(buffer.frameLength)
        guard frames > 0,
              let src = buffer.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)
        else { return nil }
        mono.frameLength = buffer.frameLength
        guard let dst = mono.floatChannelData?[0] else { return nil }
        let channels = Int(buffer.format.channelCount)
        if channels <= 1 {
            dst.update(from: src[0], count: frames)
        } else {
            let left = src[0]
            let right = src[1]
            for i in 0..<frames {
                dst[i] = 0.5 * (left[i] + right[i])
            }
        }
        return mono
    }

    private static func peakLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var peak: Float = 0
        let channelCount = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            let data = channels[ch]
            for i in 0..<frames {
                peak = max(peak, abs(data[i]))
            }
        }
        return min(1, peak)
    }

    /// Closes the file where it stands. The take is still importable.
    private func handleInterruption() {
        lock.lock()
        guard isRecording else {
            lock.unlock()
            return
        }
        interrupted = true
        file = nil
        isRecording = false
        writeMono = false
        monoWriteFormat = nil
        lock.unlock()

        removeInputTap()
        detachMonitoring()
    }

    /// Reads a take back with latency compensation applied, so it lines up with
    /// the click it was played against.
    public func alignedSamples(from take: Take, compensationEnabled: Bool = true) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: take.url)
        let frames = AVAudioFrameCount(audioFile.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                            frameCapacity: frames) else {
            return []
        }
        try audioFile.read(into: buffer)
        guard let channel = buffer.floatChannelData else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        return calibrator.compensate(samples, enabled: compensationEnabled)
    }

    // MARK: - Input tap (shared for meters, pre-roll, and take write)

    private func ensureInputTap() {
        lock.lock()
        let already = tapInstalled
        lock.unlock()
        guard !already else { return }

        let input = graph.engine.inputNode
        let tapFormat = input.inputFormat(forBus: 0)
        let installFormat: AVAudioFormat? =
            (tapFormat.channelCount > 0 && tapFormat.sampleRate > 0) ? tapFormat : nil
        input.installTap(onBus: 0, bufferSize: 2_048, format: installFormat) { [weak self] buffer, _ in
            self?.write(buffer)
        }
        lock.lock()
        tapInstalled = true
        lock.unlock()
    }

    private func removeInputTap() {
        lock.lock()
        let installed = tapInstalled
        tapInstalled = false
        lock.unlock()
        guard installed else { return }
        graph.engine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Monitoring (+ optional live noise gate / guitar pedalboard)

    private func updateMonitoring() {
        // Allow Monitor in record mode before Rec (liveInputArmed), or while writing a take.
        guard isRecording || liveInputArmed else {
            detachMonitoring()
            return
        }
        if isMonitoringEnabled {
            if monitorAttached {
                // Params-only refresh for the active topology.
                if monitorGuitarFX.enabled {
                    configureMonitorGuitarFX()
                } else {
                    configureMonitorGate()
                }
                return
            }
            let input = graph.engine.inputNode
            var format = input.inputFormat(forBus: 0)
            if format.channelCount == 0 || format.sampleRate <= 0 {
                format = input.outputFormat(forBus: 0)
            }
            guard format.channelCount > 0, format.sampleRate > 0 else { return }

            // Write tap stays on inputNode (dry DI). Monitor is a parallel graph fan-out.
            if monitorGuitarFX.enabled {
                // Guitar wet: input → EQ → Distortion → Delay → Reverb → monitorMixer → master
                // No dynamics gate on this path (GarageBand amp hears pedals; gate is vocal).
                let eq = AVAudioUnitEQ(numberOfBands: 3)
                let distortion = AVAudioUnitDistortion()
                let delay = AVAudioUnitDelay()
                let reverb = AVAudioUnitReverb()
                monitorEQ = eq
                monitorDistortion = distortion
                monitorDelay = delay
                monitorReverb = reverb
                graph.attachUtilityNode(eq)
                graph.attachUtilityNode(distortion)
                graph.attachUtilityNode(delay)
                graph.attachUtilityNode(reverb)
                graph.attachUtilityNode(monitorMixer)
                graph.connect(input, to: eq, format: format)
                graph.connect(eq, to: distortion, format: format)
                graph.connect(distortion, to: delay, format: format)
                graph.connect(delay, to: reverb, format: format)
                graph.connect(reverb, to: monitorMixer, format: format)
                graph.connect(monitorMixer, to: graph.masterBus, format: nil)
                monitorAttached = true
                configureMonitorGuitarFX()
            } else {
                // Vocal / dry: input → gate → monitorMixer → master
                let gate = makeMonitorGate()
                monitorGate = gate
                graph.attachUtilityNode(gate)
                graph.attachUtilityNode(monitorMixer)
                graph.connect(input, to: gate, format: format)
                graph.connect(gate, to: monitorMixer, format: format)
                graph.connect(monitorMixer, to: graph.masterBus, format: nil)
                monitorAttached = true
                configureMonitorGate()
            }
        } else {
            detachMonitoring()
        }
    }

    private func makeMonitorGate() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    private func configureMonitorGate() {
        guard let gate = monitorGate else { return }
        let au = gate.audioUnit
        let linearThresh = max(min(monitorGateThreshold, 0.2), 1e-6)
        let expansionThreshDB = max(-60, min(-10, 20 * log10(linearThresh)))
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -18, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 5, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 12, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, expansionThreshDB, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.005, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.08, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
        gate.bypass = !monitorGateEnabled
    }

    /// Match StudioSessionController guitar insert style (HPF + mid, multiBrokenSpeaker, mediumRoom).
    private func configureMonitorGuitarFX() {
        guard monitorGuitarFX.enabled else { return }
        let fx = monitorGuitarFX

        if let eq = monitorEQ {
            let hpf = eq.bands[0]
            hpf.filterType = .highPass
            hpf.frequency = 100
            hpf.bandwidth = 0.5
            hpf.bypass = false

            if eq.bands.count > 1 {
                let mid = eq.bands[1]
                mid.filterType = .parametric
                mid.frequency = 1_200
                mid.bandwidth = 1.0
                mid.gain = fx.eqMidGain
                mid.bypass = abs(mid.gain) < 0.05
            }
            if eq.bands.count > 2 {
                eq.bands[2].bypass = true
            }
            eq.globalGain = 0
        }

        if let distortion = monitorDistortion {
            distortion.loadFactoryPreset(.multiBrokenSpeaker)
            distortion.preGain = -3
            distortion.wetDryMix = fx.distortionMix
        }

        if let delay = monitorDelay {
            delay.delayTime = TimeInterval(max(fx.delayTime, 0.01))
            delay.feedback = 35
            delay.lowPassCutoff = 12_000
            delay.wetDryMix = fx.delayMix
        }

        if let reverb = monitorReverb {
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = fx.reverbMix
        }
    }

    private func detachMonitoring() {
        guard monitorAttached else { return }
        if let gate = monitorGate {
            graph.detachUtilityNode(gate)
            monitorGate = nil
        }
        if let eq = monitorEQ {
            graph.detachUtilityNode(eq)
            monitorEQ = nil
        }
        if let distortion = monitorDistortion {
            graph.detachUtilityNode(distortion)
            monitorDistortion = nil
        }
        if let delay = monitorDelay {
            graph.detachUtilityNode(delay)
            monitorDelay = nil
        }
        if let reverb = monitorReverb {
            graph.detachUtilityNode(reverb)
            monitorReverb = nil
        }
        graph.detachUtilityNode(monitorMixer)
        monitorAttached = false
    }
}
