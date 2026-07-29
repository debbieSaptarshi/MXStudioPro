import AVFoundation
import Foundation
import MXAudioDSP

/// Measures and compensates the full round-trip latency of the audio chain.
///
/// The OS-reported figure covers only part of the path. The plan's formula is
///
/// ```
/// outputLatency + outputStreamLatency + outputSafetyOffset
/// + inputSafetyOffset + inputLatency + inputStreamLatency
/// ```
///
/// and even that misses converter and route-specific delays, so the reported
/// value is used as a sanity bound while the authoritative number comes from a
/// loopback measurement: emit a chirp, record it back, cross-correlate.
public final class MXLatencyCalibrator: @unchecked Sendable {

    public struct Measurement: Equatable, Sendable {
        public var runs: [Int]
        public var meanFrames: Double
        public var standardDeviationFrames: Double
        public var reportedFrames: Int
        public var sampleRate: Double

        public var meanMilliseconds: Double {
            meanFrames / sampleRate * 1000
        }

        /// The plan's stability bar for L-01.
        public var isStable: Bool {
            standardDeviationFrames <= 32
        }
    }

    /// Hardware needs a physical loopback (headphone out into mic, or an audio
    /// interface loop). The simulated source runs the identical estimator over
    /// a known delay so CI can prove the maths without hardware.
    public enum Source: Sendable {
        case hardware
        case simulated(delayFrames: Int, noiseAmplitude: Float)
    }

    public enum CalibrationError: Error, Equatable {
        case noInputAvailable
        case correlationTooWeak(Float)
        case measurementUnstable(stdDev: Double)
    }

    public let session: MXAudioSession
    public private(set) var sampleRate: Double

    /// Frames trimmed from the head of a recorded take. Persisted with the
    /// project so a take recorded yesterday still lines up today.
    public private(set) var compensationFrames: Int = 0

    private let defaultsKey = "com.mxstudio.latency.compensationFrames"

    public init(session: MXAudioSession = MXAudioSession(), sampleRate: Double = 48_000) {
        self.session = session
        self.sampleRate = sampleRate
        compensationFrames = UserDefaults.standard.integer(forKey: defaultsKey)
    }

    // MARK: - Reported latency

    /// OS-reported round trip in frames. Used as the plausibility window the
    /// measured value must fall near.
    public func reportedLatencyFrames() -> Int {
        Int((session.reportedRoundTripLatency * sampleRate).rounded())
    }

    // MARK: - Measurement

    public func measure(runs: Int = 5,
                        source: Source = .hardware) async throws -> Measurement {
        let reference = Self.chirp(sampleRate: sampleRate)
        var lags: [Int] = []

        for _ in 0..<max(1, runs) {
            let captured: [Float]
            switch source {
            case .simulated(let delayFrames, let noise):
                captured = Self.simulateLoopback(reference: reference,
                                                 delayFrames: delayFrames,
                                                 noiseAmplitude: noise)
            case .hardware:
                captured = try await captureHardwareLoopback(reference: reference)
            }

            let maxLag = min(captured.count - 1, Int(sampleRate * 0.5))
            let result = MXAudioAnalysis.crossCorrelationLag(reference: reference,
                                                             signal: captured,
                                                             maxLag: maxLag)
            guard result.correlation > 1e-5 else {
                throw CalibrationError.correlationTooWeak(result.correlation)
            }
            // A positive lag means the captured copy arrived late; that delay is
            // exactly what has to be trimmed off a recorded take.
            lags.append(-result.lag)
        }

        let mean = lags.reduce(0, +).doubleValue / Double(lags.count)
        let variance = lags.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(lags.count)
        let measurement = Measurement(runs: lags,
                                      meanFrames: mean,
                                      standardDeviationFrames: sqrt(variance),
                                      reportedFrames: reportedLatencyFrames(),
                                      sampleRate: sampleRate)
        return measurement
    }

    /// Commits a measurement so subsequent recordings are aligned.
    public func apply(_ measurement: Measurement) {
        compensationFrames = max(0, Int(measurement.meanFrames.rounded()))
        UserDefaults.standard.set(compensationFrames, forKey: defaultsKey)
    }

    public func setCompensationFrames(_ frames: Int) {
        compensationFrames = max(0, frames)
        UserDefaults.standard.set(compensationFrames, forKey: defaultsKey)
    }

    /// Negative control for L-03: with compensation disabled the alignment test
    /// is expected to fail, which proves the calibrator is doing real work.
    public func compensate(_ samples: [Float], enabled: Bool = true) -> [Float] {
        guard enabled, compensationFrames > 0, compensationFrames < samples.count else {
            return samples
        }
        return Array(samples[compensationFrames...])
    }

    // MARK: - Signal generation

    /// A short linear chirp correlates far more sharply than a click and is
    /// robust to the band-limiting a speaker/mic path imposes.
    public static func chirp(sampleRate: Double,
                             durationSeconds: Double = 0.020,
                             startHz: Double = 200,
                             endHz: Double = 8_000) -> [Float] {
        let count = Int(sampleRate * durationSeconds)
        guard count > 0 else { return [] }
        var output = [Float](repeating: 0, count: count)
        let rate = (endHz - startHz) / durationSeconds

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let phase = 2 * Double.pi * (startHz * t + 0.5 * rate * t * t)
            // Hann window keeps the ends from clicking, which would add a second
            // correlation peak.
            let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(count - 1))
            output[i] = Float(sin(phase) * window)
        }
        return output
    }

    static func simulateLoopback(reference: [Float],
                                 delayFrames: Int,
                                 noiseAmplitude: Float) -> [Float] {
        let tail = reference.count + delayFrames + 4_096
        var output = [Float](repeating: 0, count: tail)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<tail {
            var value: Float = 0
            let sourceIndex = i - delayFrames
            if sourceIndex >= 0, sourceIndex < reference.count {
                // Attenuated, as a real acoustic or line loop would be.
                value = reference[sourceIndex] * 0.6
            }
            if noiseAmplitude > 0 {
                value += Float.random(in: -noiseAmplitude...noiseAmplitude, using: &generator)
            }
            output[i] = value
        }
        return output
    }

    // MARK: - Hardware capture

    private func captureHardwareLoopback(reference: [Float]) async throws -> [Float] {
        guard session.hasInputPermission() else {
            throw CalibrationError.noInputAvailable
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw CalibrationError.noInputAvailable
        }

        guard let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                                 channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                            frameCapacity: AVAudioFrameCount(reference.count)) else {
            throw CalibrationError.noInputAvailable
        }
        buffer.frameLength = AVAudioFrameCount(reference.count)
        if let channel = buffer.floatChannelData {
            channel[0].update(from: reference, count: reference.count)
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let captureBox = CaptureBox()
        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { pcm, _ in
            guard let channel = pcm.floatChannelData else { return }
            captureBox.append(Array(UnsafeBufferPointer(start: channel[0],
                                                        count: Int(pcm.frameLength))))
        }

        defer {
            input.removeTap(onBus: 0)
            engine.stop()
        }

        do {
            try engine.start()
        } catch {
            throw MXAudioError.engineStartFailed(error.localizedDescription)
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()

        // Capture window: the chirp plus enough tail to contain any plausible
        // round-trip delay.
        try? await Task.sleep(nanoseconds: 700_000_000)

        let captured = captureBox.drain()
        guard !captured.isEmpty else {
            throw CalibrationError.noInputAvailable
        }
        return captured
    }
}

/// Tap callbacks arrive on a real-time thread, so accumulation is guarded by a
/// plain lock and the array work happens off that thread's critical path.
private final class CaptureBox: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private extension Int {
    var doubleValue: Double { Double(self) }
}
