import AVFoundation
import Foundation

/// Lightweight chromatic pitch detector for the in-app tuner (A4 = 440 Hz).
@MainActor
@Observable
final class MXTunerEngine {
    enum PermissionState: Equatable {
        case unknown
        case granted
        case denied
    }

    var permissionState: PermissionState = .unknown
    var noteName: String = "—"
    var octave: Int = 4
    var frequencyHz: Double = 0
    var cents: Double = 0
    var isListening = false
    var signalPresent = false

    var isInTune: Bool { abs(cents) < 5 && signalPresent }

    var displayNote: String {
        noteName == "—" ? "—" : "\(noteName)\(octave)"
    }

    private let referenceA4 = 440.0
    private var audioEngine: AVAudioEngine?
    private var isConfigured = false

    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    func requestPermissionAndStart() async {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }

        permissionState = granted ? .granted : .denied
        guard granted else { return }
        startListening()
    }

    func startListening() {
        guard permissionState == .granted || permissionState == .unknown else { return }
        permissionState = .granted
        guard !isListening else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let sampleRate = format.sampleRate

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let result = Self.analyze(buffer: buffer, sampleRate: sampleRate) else {
                    Task { @MainActor in
                        self?.applySilence()
                    }
                    return
                }
                let note = Self.note(from: result.frequency, referenceA4: 440)
                Task { @MainActor in
                    self?.apply(pitch: result.frequency, note: note, rms: result.rms)
                }
            }

            engine.prepare()
            try engine.start()
            audioEngine = engine
            isListening = true
            isConfigured = true
        } catch {
            stopListening()
            permissionState = .denied
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false

        if isConfigured {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isConfigured = false
        }

        applySilence()
    }

    private func apply(pitch frequency: Double, note: (name: String, octave: Int, cents: Double), rms: Float) {
        frequencyHz = frequency
        noteName = note.name
        octave = note.octave
        cents = note.cents
        signalPresent = rms > 0.008
    }

    private func applySilence() {
        signalPresent = false
        cents = 0
        frequencyHz = 0
        noteName = "—"
    }

    // MARK: - Pitch analysis

    private struct AnalysisResult {
        var frequency: Double
        var rms: Float
    }

    nonisolated private static func analyze(buffer: AVAudioPCMBuffer, sampleRate: Double) -> AnalysisResult? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= 512 else { return nil }

        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let s = channelData[i]
            sumSquares += s * s
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        guard rms > 0.006 else { return nil }

        let minLag = max(2, Int(sampleRate / 1_500))
        let maxLag = min(frameCount / 2, Int(sampleRate / 50))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestCorrelation: Float = 0

        for lag in minLag..<maxLag {
            var correlation: Float = 0
            let limit = frameCount - lag
            var i = 0
            while i < limit {
                correlation += channelData[i] * channelData[i + lag]
                i += 1
            }
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        guard bestCorrelation > 0.0005 else { return nil }

        let frequency = sampleRate / Double(bestLag)
        guard (50...1_500).contains(frequency) else { return nil }
        return AnalysisResult(frequency: frequency, rms: rms)
    }

    nonisolated private static func note(
        from frequency: Double,
        referenceA4: Double
    ) -> (name: String, octave: Int, cents: Double) {
        let midiFloat = 69.0 + 12.0 * log2(frequency / referenceA4)
        let nearestMidi = Int(round(midiFloat))
        let targetFrequency = referenceA4 * pow(2.0, Double(nearestMidi - 69) / 12.0)
        let centsOffset = 1200.0 * log2(frequency / targetFrequency)
        let noteIndex = ((nearestMidi % 12) + 12) % 12
        let octaveNumber = nearestMidi / 12 - 1
        return (noteNames[noteIndex], octaveNumber, centsOffset)
    }
}
