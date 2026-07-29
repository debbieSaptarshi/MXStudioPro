import AVFoundation
import Foundation
import MXAudioDSP

/// Builds audio and instrument fixtures on demand.
///
/// Fixtures are *generated* rather than committed. Two reasons: the repository
/// stays small, and there is no way for an unlicensed sample to enter the test
/// corpus — which is the same risk section 9 of the plan raises about shipped
/// content.
public enum MXFixtureFactory {

    public static let sampleRate: Double = 48_000

    /// Root for generated fixtures, cleaned per run.
    public static func makeTemporaryDirectory(named name: String = "mxfixtures") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Raw signal

    public static func sine(frequency: Double,
                            seconds: Double,
                            amplitude: Float = 0.8,
                            sampleRate: Double = sampleRate) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    /// Decaying noise burst — stands in for a drum hit.
    public static func noiseBurst(seconds: Double,
                                  amplitude: Float = 0.9,
                                  decaySeconds: Double = 0.08,
                                  seed: UInt64 = 1,
                                  sampleRate: Double = sampleRate) -> [Float] {
        let count = Int(seconds * sampleRate)
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = Float(exp(-t / decaySeconds))
            return Float.random(in: -1...1, using: &generator) * amplitude * envelope
        }
    }

    /// Sine with an exponential decay, so a "note" has a clear onset and tail.
    public static func pluck(frequency: Double,
                             seconds: Double,
                             amplitude: Float = 0.8,
                             decaySeconds: Double = 0.4,
                             sampleRate: Double = sampleRate) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let envelope = Float(exp(-t / decaySeconds))
            return amplitude * envelope * Float(sin(2 * Double.pi * frequency * t))
        }
    }

    // MARK: - Files

    @discardableResult
    public static func writeWAV(_ samples: [Float],
                                to url: URL,
                                sampleRate: Double = sampleRate,
                                channels: AVAudioChannelCount = 1) throws -> URL {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: channels,
                                         interleaved: false) else {
            throw MXAudioError.exportFailed("could not build fixture format")
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw MXAudioError.exportFailed("could not allocate fixture buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(channels) {
                channelData[channel].update(from: samples, count: samples.count)
            }
        }
        try file.write(from: buffer)
        return url
    }

    public static func readWAV(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: frames) else {
            return []
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    // MARK: - SFZ instruments

    /// Single-region instrument at middle C. The baseline for I-01…I-06.
    public static func simpleSFZ(in directory: URL) throws -> URL {
        let sample = directory.appendingPathComponent("c4.wav")
        try writeWAV(pluck(frequency: 261.63, seconds: 1.5), to: sample)

        let sfz = """
        // Single-region fixture
        <region> sample=c4.wav key=60 pitch_keycenter=60 ampeg_release=0.2
        """
        let url = directory.appendingPathComponent("simple.sfz")
        try sfz.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Two velocity layers with sonically distinct samples, so SFZ-01 can prove
    /// that velocity actually selects a different sample rather than just
    /// scaling gain.
    public static func velocityLayeredSFZ(in directory: URL) throws -> URL {
        try writeWAV(pluck(frequency: 220, seconds: 1.0, amplitude: 0.5),
                     to: directory.appendingPathComponent("soft.wav"))
        try writeWAV(noiseBurst(seconds: 1.0, amplitude: 0.9, seed: 7),
                     to: directory.appendingPathComponent("hard.wav"))

        let sfz = """
        <group> key=60 pitch_keycenter=60 ampeg_release=0.1
        <region> sample=soft.wav lovel=1 hivel=63
        <region> sample=hard.wav lovel=64 hivel=127
        """
        let url = directory.appendingPathComponent("velocity.sfz")
        try sfz.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Four-way round robin, each variation a different noise seed so the
    /// rendered buffers hash differently (SFZ-02).
    public static func roundRobinSFZ(in directory: URL, variations: Int = 4) throws -> URL {
        var lines = ["<group> key=60 pitch_keycenter=60 seq_length=\(variations) ampeg_release=0.05"]
        for index in 0..<variations {
            let name = "rr\(index).wav"
            try writeWAV(noiseBurst(seconds: 0.4, seed: UInt64(index + 1) &* 9973),
                         to: directory.appendingPathComponent(name))
            lines.append("<region> sample=\(name) seq_position=\(index + 1)")
        }
        let url = directory.appendingPathComponent("roundrobin.sfz")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Drum kit covering the 13 Figma lanes, with the hi-hat choke group wired
    /// the way D-02 expects: the closed hat is in group 1 and the open hat is
    /// `off_by=1`, so a closed hit silences a ringing open hat.
    public static func drumKitSFZ(in directory: URL) throws -> URL {
        var lines: [String] = ["// Generated drum fixture"]

        for lane in MXDrumLaneFixture.allLanes {
            let name = "\(lane.id).wav"
            try writeWAV(noiseBurst(seconds: lane.lengthSeconds,
                                    amplitude: 0.85,
                                    decaySeconds: lane.decaySeconds,
                                    seed: UInt64(lane.midiNote) &* 7919),
                         to: directory.appendingPathComponent(name))
            var region = "<region> sample=\(name) key=\(lane.midiNote) pitch_keycenter=\(lane.midiNote) loop_mode=one_shot"
            if let group = lane.group { region += " group=\(group)" }
            if let offBy = lane.offBy { region += " off_by=\(offBy)" }
            lines.append(region)
        }

        let url = directory.appendingPathComponent("kit.sfz")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Impulse response for the convolution cabinet: a decaying noise tail with
    /// a resonant colouring so FX-05 has a fingerprint to match.
    @discardableResult
    public static func cabinetIR(in directory: URL,
                                 named name: String = "cab.wav",
                                 resonanceHz: Float = 2_400) throws -> URL {
        var samples = noiseBurst(seconds: 0.12, amplitude: 0.6, decaySeconds: 0.02, seed: 42)
        var filter = MXBiquad()
        filter.configure(kind: .peaking, frequency: resonanceHz, q: 2.5,
                         gainDB: 12, sampleRate: sampleRate)
        for i in samples.indices {
            samples[i] = filter.process(samples[i])
        }
        // Normalise so convolution gain is predictable.
        let peak = MXAudioAnalysis.peak(samples)
        if peak > 0 {
            for i in samples.indices { samples[i] /= peak }
        }
        return try writeWAV(samples, to: directory.appendingPathComponent(name))
    }
}

/// The 13 lanes from the Figma drum grid, in fixture form.
public struct MXDrumLaneFixture: Sendable {
    public let id: String
    public let midiNote: UInt8
    public let group: Int?
    public let offBy: Int?
    public let lengthSeconds: Double
    public let decaySeconds: Double

    public static let allLanes: [MXDrumLaneFixture] = [
        .init(id: "crash", midiNote: 49, group: nil, offBy: nil, lengthSeconds: 1.2, decaySeconds: 0.5),
        .init(id: "cymbal_l", midiNote: 55, group: nil, offBy: nil, lengthSeconds: 1.0, decaySeconds: 0.4),
        .init(id: "cymbal_r", midiNote: 57, group: nil, offBy: nil, lengthSeconds: 1.0, decaySeconds: 0.4),
        // Open hat rings until something in group 1 cuts it.
        .init(id: "open_hh", midiNote: 46, group: 1, offBy: 1, lengthSeconds: 1.0, decaySeconds: 0.45),
        .init(id: "foot_close_hh", midiNote: 44, group: 1, offBy: 1, lengthSeconds: 0.3, decaySeconds: 0.05),
        .init(id: "close_hh", midiNote: 42, group: 1, offBy: 1, lengthSeconds: 0.3, decaySeconds: 0.05),
        .init(id: "tom_high", midiNote: 48, group: nil, offBy: nil, lengthSeconds: 0.6, decaySeconds: 0.18),
        .init(id: "tom_mid", midiNote: 45, group: nil, offBy: nil, lengthSeconds: 0.6, decaySeconds: 0.2),
        .init(id: "tom_low", midiNote: 41, group: nil, offBy: nil, lengthSeconds: 0.7, decaySeconds: 0.25),
        .init(id: "snare_mid", midiNote: 40, group: nil, offBy: nil, lengthSeconds: 0.5, decaySeconds: 0.12),
        .init(id: "snare", midiNote: 38, group: nil, offBy: nil, lengthSeconds: 0.5, decaySeconds: 0.12),
        .init(id: "stick", midiNote: 37, group: nil, offBy: nil, lengthSeconds: 0.2, decaySeconds: 0.03),
        .init(id: "kick", midiNote: 36, group: nil, offBy: nil, lengthSeconds: 0.6, decaySeconds: 0.15),
    ]
}

/// Deterministic RNG so a regenerated fixture is bit-identical to the one a
/// golden file was captured against.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
