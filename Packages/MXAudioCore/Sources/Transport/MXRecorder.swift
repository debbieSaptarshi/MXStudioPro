import AVFoundation
import Foundation
import MXAudioDSP

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
    private var interrupted = false
    private let lock = NSLock()
    /// When true, stereo (or multi-channel) tap buffers are downmixed to mono on write.
    private var writeMono = false
    private var monoWriteFormat: AVAudioFormat?

    /// Direct monitoring routes input to the output. Off by default because on
    /// a speaker route it feeds back (L-04 checks there is no howl).
    public var isMonitoringEnabled = false {
        didSet { updateMonitoring() }
    }

    private let monitorMixer = AVAudioMixerNode()
    private var monitorAttached = false
    /// When true, Monitor may route input→master even before Rec (armed / record mode).
    private var liveInputArmed = false

    public private(set) var isRecording = false
    /// Peak input level 0…1, updated from the write tap for UI meters.
    public private(set) var inputLevel: Float = 0

    /// Arm live input for monitoring while in record mode (not only while writing a take).
    public func setLiveInputArmed(_ armed: Bool) {
        liveInputArmed = armed
        if !armed && !isRecording {
            detachMonitoring()
        } else {
            updateMonitoring()
        }
    }

    public init(graph: MXGraph, transport: MXTransport, calibrator: MXLatencyCalibrator) {
        self.graph = graph
        self.transport = transport
        self.calibrator = calibrator

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

        lock.lock()
        file = audioFile
        currentURL = url
        startSample = transport.currentSample
        framesWritten = 0
        interrupted = false
        isRecording = true
        writeMono = useMono && format.channelCount > 1
        monoWriteFormat = writeMono ? fileFormat : nil
        lock.unlock()

        // Prefer hardware format for the tap; `nil` lets AVAudioEngine pick when
        // Simulator reports an empty input format.
        let tapFormat = input.inputFormat(forBus: 0)
        let installFormat: AVAudioFormat? =
            (tapFormat.channelCount > 0 && tapFormat.sampleRate > 0) ? tapFormat : nil
        input.installTap(onBus: 0, bufferSize: 2_048, format: installFormat) { [weak self] buffer, _ in
            self?.write(buffer)
        }
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
                        wasInterrupted: interrupted)
        isRecording = false
        file = nil
        currentURL = nil
        writeMono = false
        monoWriteFormat = nil
        lock.unlock()

        graph.engine.inputNode.removeTap(onBus: 0)
        detachMonitoring()
        return take
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard isRecording, let file else {
            lock.unlock()
            return
        }
        let downmix = writeMono
        let monoFormat = monoWriteFormat
        lock.unlock()

        do {
            if downmix, let monoFormat, let mono = Self.downmixToMono(buffer, format: monoFormat) {
                try file.write(from: mono)
            } else {
                try file.write(from: buffer)
            }
            let peak = Self.peakLevel(in: buffer)
            lock.lock()
            framesWritten += buffer.frameLength
            inputLevel = peak
            lock.unlock()
        } catch {
            handleInterruption()
        }
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

        graph.engine.inputNode.removeTap(onBus: 0)
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

    // MARK: - Monitoring

    private func updateMonitoring() {
        // Allow Monitor in record mode before Rec (liveInputArmed), or while writing a take.
        guard isRecording || liveInputArmed else {
            detachMonitoring()
            return
        }
        if isMonitoringEnabled {
            guard !monitorAttached else { return }
            let input = graph.engine.inputNode
            var format = input.inputFormat(forBus: 0)
            if format.channelCount == 0 || format.sampleRate <= 0 {
                format = input.outputFormat(forBus: 0)
            }
            guard format.channelCount > 0, format.sampleRate > 0 else { return }
            graph.attachUtilityNode(monitorMixer)
            graph.connect(input, to: monitorMixer, format: format)
            graph.connect(monitorMixer, to: graph.masterBus, format: nil)
            monitorAttached = true
        } else {
            detachMonitoring()
        }
    }

    private func detachMonitoring() {
        guard monitorAttached else { return }
        graph.detachUtilityNode(monitorMixer)
        monitorAttached = false
    }
}
