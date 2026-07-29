import Foundation

/// Offline placeholder audio for AI compose until real generation ships.
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
