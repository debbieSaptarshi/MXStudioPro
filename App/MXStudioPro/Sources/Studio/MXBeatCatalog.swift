import Foundation

/// BandLab / Loopcloud-style **beat browser** catalog (Week 74).
///
/// Procedural PCM only — no binary pack assets. Loops and one-shots are
/// synthesized on import into the project `Audio/` folder.
public enum MXBeatKind: String, Sendable {
    case loop
    case oneShot
}

public struct MXBeatCatalogItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let kind: MXBeatKind
    public let bpmHint: Double?
    public let durationSeconds: Double
    public let systemImage: String

    public init(
        id: String,
        name: String,
        subtitle: String,
        kind: MXBeatKind,
        bpmHint: Double?,
        durationSeconds: Double,
        systemImage: String
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.kind = kind
        self.bpmHint = bpmHint
        self.durationSeconds = durationSeconds
        self.systemImage = systemImage
    }
}

public enum MXBeatCatalog {
    public static let all: [MXBeatCatalogItem] = [
        .init(
            id: "lofi_4bar",
            name: "Lo-Fi Loop",
            subtitle: "4 bars · 90 BPM",
            kind: .loop,
            bpmHint: 90,
            durationSeconds: 4 * 4 * 60 / 90,
            systemImage: "waveform"
        ),
        .init(
            id: "boom_bap_2bar",
            name: "Boom-Bap",
            subtitle: "2 bars · 88 BPM",
            kind: .loop,
            bpmHint: 88,
            durationSeconds: 2 * 4 * 60 / 88,
            systemImage: "metronome"
        ),
        .init(
            id: "disco_hats",
            name: "Disco Hats",
            subtitle: "2 bars · 120 BPM",
            kind: .loop,
            bpmHint: 120,
            durationSeconds: 2 * 4 * 60 / 120,
            systemImage: "music.quarternote.3"
        ),
        .init(
            id: "four_floor",
            name: "Four-on-Floor",
            subtitle: "2 bars · 124 BPM",
            kind: .loop,
            bpmHint: 124,
            durationSeconds: 2 * 4 * 60 / 124,
            systemImage: "speaker.wave.2"
        ),
        .init(
            id: "kick_808",
            name: "Kick 808",
            subtitle: "One-shot",
            kind: .oneShot,
            bpmHint: nil,
            durationSeconds: 0.55,
            systemImage: "circle.fill"
        ),
        .init(
            id: "snare_clap",
            name: "Snare Clap",
            subtitle: "One-shot",
            kind: .oneShot,
            bpmHint: nil,
            durationSeconds: 0.35,
            systemImage: "circle"
        ),
        .init(
            id: "hat_closed",
            name: "Closed Hat",
            subtitle: "One-shot",
            kind: .oneShot,
            bpmHint: nil,
            durationSeconds: 0.12,
            systemImage: "diamond"
        ),
        .init(
            id: "perc_rim",
            name: "Rim Shot",
            subtitle: "One-shot",
            kind: .oneShot,
            bpmHint: nil,
            durationSeconds: 0.18,
            systemImage: "smallcircle.filled.circle"
        ),
    ]

    /// Render procedural mono float PCM for a catalog item.
    static func renderPCM(
        _ item: MXBeatCatalogItem,
        sampleRate: Double = 48_000
    ) -> [Float] {
        let n = max(1, Int((item.durationSeconds * sampleRate).rounded()))
        switch item.id {
        case "kick_808":
            return renderKick(frames: n, sampleRate: sampleRate)
        case "snare_clap":
            return renderSnare(frames: n, sampleRate: sampleRate)
        case "hat_closed":
            return renderHat(frames: n, sampleRate: sampleRate, open: false)
        case "perc_rim":
            return renderRim(frames: n, sampleRate: sampleRate)
        case "lofi_4bar":
            return renderLoop(frames: n, sampleRate: sampleRate, bpm: 90, style: .lofi)
        case "boom_bap_2bar":
            return renderLoop(frames: n, sampleRate: sampleRate, bpm: 88, style: .boomBap)
        case "disco_hats":
            return renderLoop(frames: n, sampleRate: sampleRate, bpm: 120, style: .discoHats)
        case "four_floor":
            return renderLoop(frames: n, sampleRate: sampleRate, bpm: 124, style: .fourFloor)
        default:
            return renderKick(frames: n, sampleRate: sampleRate)
        }
    }

    /// Write a stereo 16-bit PCM WAV from mono float samples.
    static func writeWAV(mono: [Float], sampleRate: Double, to url: URL) throws {
        let rate = Int(sampleRate.rounded())
        var samples = [Int16](repeating: 0, count: mono.count * 2)
        for i in mono.indices {
            let clamped = max(-1, min(1, mono[i]))
            let s = Int16((Double(clamped) * Double(Int16.max) * 0.92).rounded())
            samples[i * 2] = s
            samples[i * 2 + 1] = s
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

    // MARK: - One-shots

    private static func renderKick(frames: Int, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let env = exp(-t * 8.5)
            let freq = 55.0 * exp(-t * 12) + 35
            out[i] = Float(sin(2 * .pi * freq * t) * env * 0.85)
        }
        return out
    }

    private static func renderSnare(frames: Int, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        var seed: UInt64 = 0xC0FFEE
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let env = exp(-t * 18)
            seed = seed &* 6364136223846793005 &+ 1
            let noise = Float(Int64(seed >> 33) - (1 << 30)) / Float(1 << 30)
            let body = Float(sin(2 * .pi * 180 * t) * exp(-t * 22) * 0.35)
            out[i] = (noise * 0.55 + body) * Float(env)
        }
        return out
    }

    private static func renderHat(frames: Int, sampleRate: Double, open: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        var seed: UInt64 = 0xBADC0DE
        let decay = open ? 9.0 : 45.0
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let env = exp(-t * decay)
            seed = seed &* 6364136223846793005 &+ 1
            let noise = Float(Int64(seed >> 33) - (1 << 30)) / Float(1 << 30)
            // Cheap high-pass feel: difference of noise samples.
            out[i] = noise * Float(env) * 0.4
            if i > 0 { out[i] = (out[i] - out[i - 1] * 0.55) }
        }
        return out
    }

    private static func renderRim(frames: Int, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let env = exp(-t * 55)
            out[i] = Float(
                (sin(2 * .pi * 780 * t) + 0.4 * sin(2 * .pi * 1240 * t)) * env * 0.5
            )
        }
        return out
    }

    // MARK: - Loops

    private enum LoopStyle {
        case lofi, boomBap, discoHats, fourFloor
    }

    private static func renderLoop(
        frames: Int,
        sampleRate: Double,
        bpm: Double,
        style: LoopStyle
    ) -> [Float] {
        var out = [Float](repeating: 0, count: frames)
        let beatSec = 60.0 / max(bpm, 1)
        let sixteenth = beatSec / 4

        func place(_ hit: [Float], atSeconds start: Double, gain: Float = 1) {
            let startFrame = Int((start * sampleRate).rounded())
            guard startFrame < frames else { return }
            let n = min(hit.count, frames - startFrame)
            for i in 0..<n {
                out[startFrame + i] += hit[i] * gain
            }
        }

        let kick = renderKick(frames: Int(0.5 * sampleRate), sampleRate: sampleRate)
        let snare = renderSnare(frames: Int(0.35 * sampleRate), sampleRate: sampleRate)
        let hat = renderHat(frames: Int(0.1 * sampleRate), sampleRate: sampleRate, open: false)
        let openHat = renderHat(frames: Int(0.22 * sampleRate), sampleRate: sampleRate, open: true)

        let totalBeats = Double(frames) / sampleRate / beatSec
        let barCount = max(1, Int((totalBeats / 4).rounded(.down)))

        for bar in 0..<barCount {
            let barStart = Double(bar) * 4 * beatSec
            switch style {
            case .lofi, .boomBap:
                place(kick, atSeconds: barStart + 0 * beatSec)
                place(kick, atSeconds: barStart + 2.5 * beatSec, gain: 0.7)
                place(snare, atSeconds: barStart + 1 * beatSec)
                place(snare, atSeconds: barStart + 3 * beatSec)
                for s in 0..<16 {
                    place(hat, atSeconds: barStart + Double(s) * sixteenth, gain: s % 2 == 0 ? 0.55 : 0.28)
                }
            case .discoHats:
                place(kick, atSeconds: barStart + 0 * beatSec, gain: 0.75)
                place(kick, atSeconds: barStart + 2 * beatSec, gain: 0.75)
                place(snare, atSeconds: barStart + 1 * beatSec, gain: 0.5)
                place(snare, atSeconds: barStart + 3 * beatSec, gain: 0.5)
                for s in 0..<16 {
                    place(openHat, atSeconds: barStart + Double(s) * sixteenth, gain: 0.45)
                }
            case .fourFloor:
                for b in 0..<4 {
                    place(kick, atSeconds: barStart + Double(b) * beatSec)
                }
                place(snare, atSeconds: barStart + 1 * beatSec, gain: 0.65)
                place(snare, atSeconds: barStart + 3 * beatSec, gain: 0.65)
                for s in stride(from: 0, to: 16, by: 2) {
                    place(hat, atSeconds: barStart + Double(s) * sixteenth, gain: 0.4)
                }
            }
        }

        // Soft peak normalize.
        var peak: Float = 0
        for s in out { peak = max(peak, abs(s)) }
        if peak > 0.95 {
            let scale = 0.95 / peak
            for i in out.indices { out[i] *= scale }
        }
        return out
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
