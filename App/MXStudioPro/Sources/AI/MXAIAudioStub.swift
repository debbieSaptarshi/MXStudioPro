import AVFoundation
import Foundation

/// Writes ElevenLabs-generated audio into the AI compose staging folder and
/// copies it into a project's `Audio/` directory on import.
enum MXAIAudioFileWriter {
    enum WriteError: Error, LocalizedError {
        case stagingMissing(String)

        var errorDescription: String? {
            switch self {
            case .stagingMissing(let name):
                return "Generated audio file is missing: \(name)"
            }
        }
    }

    static var stagingDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("AICompose", isDirectory: true)
    }

    /// Writes MP3 bytes to `Documents/AICompose/` and returns the staged file name.
    @discardableResult
    static func writeStagedMP3(data: Data, id: UUID = UUID()) throws -> (fileName: String, durationSeconds: Double) {
        let fileName = "ai_\(id.uuidString.prefix(8)).mp3"
        let url = stagingDirectory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: [.atomic])
        return (fileName, probeDuration(url: url))
    }

    /// Copies a staged file into a project's `Audio/` folder for Studio import.
    static func copyStagedFile(_ stagedFileName: String, to projectAudioDir: URL) throws -> (fileName: String, durationSeconds: Double) {
        let source = stagingDirectory.appendingPathComponent(stagedFileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WriteError.stagingMissing(stagedFileName)
        }

        try FileManager.default.createDirectory(at: projectAudioDir, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension
        let destName = "ai_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext)"
        let destURL = projectAudioDir.appendingPathComponent(destName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: source, to: destURL)
        return (destName, probeDuration(url: destURL))
    }

    static func probeDuration(url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0.05 else { return 30 }
        return seconds
    }
}

/// Offline placeholder audio for Discover cards and demo templates.
enum MXAIAudioStub {
    /// Writes a short stereo PCM WAV (two soft sine tones, low amplitude).
    static func writeStubWAV(
        to url: URL,
        durationSeconds: Double = 4,
        sampleRate: Double = 48_000,
        freqA: Double = 220,
        freqB: Double = 330
    ) throws {
        let duration = max(0.25, durationSeconds)
        let rate = Int(sampleRate.rounded())
        let frameCount = Int((duration * sampleRate).rounded(.down))
        guard frameCount > 0 else { return }
        let amplitude = 0.12

        var samples = [Int16](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            let t = Double(frame) / sampleRate
            let fadeIn = min(1, t / 0.08)
            let fadeOut = min(1, (duration - t) / 0.12)
            let envelope = min(fadeIn, fadeOut)

            let sample = sin(2 * .pi * freqA * t) * 0.55
                + sin(2 * .pi * freqB * t) * 0.45
            let scaled = Int16((sample * amplitude * envelope * Double(Int16.max)).rounded())

            samples[frame * 2] = scaled
            samples[frame * 2 + 1] = scaled
        }

        let byteRate = rate * 4
        let dataSize = samples.count * MemoryLayout<Int16>.size
        let riffSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: uint32LE(UInt32(riffSize)))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: uint32LE(16))
        data.append(contentsOf: uint16LE(1))
        data.append(contentsOf: uint16LE(2))
        data.append(contentsOf: uint32LE(UInt32(rate)))
        data.append(contentsOf: uint32LE(UInt32(byteRate)))
        data.append(contentsOf: uint16LE(4))
        data.append(contentsOf: uint16LE(16))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: uint32LE(UInt32(dataSize)))

        samples.withUnsafeBytes { raw in
            data.append(contentsOf: raw)
        }

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: [.atomic])
    }

    private static func uint16LE(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func uint32LE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8(value >> 24),
        ]
    }
}
