import Foundation
import MXAudioDSP

/// One MIDI note on the arrange grid (piano-roll lite).
public struct MXMIDINote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var note: UInt8
    public var velocity: UInt8
    public var startBeat: Double
    public var lengthBeats: Double

    public init(
        id: UUID = UUID(),
        note: UInt8,
        velocity: UInt8 = 100,
        startBeat: Double,
        lengthBeats: Double
    ) {
        self.id = id
        self.note = note
        self.velocity = max(1, velocity)
        self.startBeat = max(0, startBeat)
        self.lengthBeats = max(0.0625, lengthBeats)
    }

    public var endBeat: Double { startBeat + lengthBeats }
}

/// Offline render of MIDI notes through `MXSynthEngine` → PCM WAV (Piano Studio bounce bed).
///
/// `MXSynthEngine` applies queued events at the start of each render block (frameOffset
/// is unused), so we quantize note edges to the render block size.
public enum MXMIDIClipRenderer {
    public static func writeWAV(
        notes: [MXMIDINote],
        to url: URL,
        preset: MXSynthPreset = MXSynthBankPreset.trackSeed.preset,
        bpm: Double = 120,
        sampleRate: Double = 48_000,
        tailSeconds: Double = 0.6
    ) throws {
        guard !notes.isEmpty else {
            throw MXMIDIRenderError.noNotes
        }
        let beatsPerSecond = max(bpm, 1) / 60.0
        let endBeat = notes.map(\.endBeat).max() ?? 0
        let duration = endBeat / beatsPerSecond + max(0.15, tailSeconds)
        let frameCount = max(1, Int((duration * sampleRate).rounded(.up)))

        struct Edge {
            let frame: Int
            let isOn: Bool
            let note: UInt8
            let velocity: UInt8
        }

        var edges: [Edge] = []
        edges.reserveCapacity(notes.count * 2)
        for note in notes {
            let onFrame = max(0, Int((note.startBeat / beatsPerSecond * sampleRate).rounded()))
            let offFrame = max(onFrame + 1, Int((note.endBeat / beatsPerSecond * sampleRate).rounded()))
            edges.append(Edge(frame: onFrame, isOn: true, note: note.note, velocity: note.velocity))
            edges.append(Edge(frame: offFrame, isOn: false, note: note.note, velocity: 0))
        }
        edges.sort { a, b in
            if a.frame != b.frame { return a.frame < b.frame }
            // Note-offs before note-ons at the same frame.
            return !a.isOn && b.isOn
        }

        let engine = MXSynthEngine(sampleRate: sampleRate, polyphony: 16)
        engine.apply(preset: preset)

        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        let block = 256
        var cursor = 0
        var edgeIndex = 0
        while cursor < frameCount {
            let end = min(cursor + block, frameCount)
            while edgeIndex < edges.count, edges[edgeIndex].frame < end {
                let edge = edges[edgeIndex]
                if edge.isOn {
                    engine.noteOn(edge.note, velocity: edge.velocity)
                } else {
                    engine.noteOff(edge.note)
                }
                edgeIndex += 1
            }
            let n = end - cursor
            left.withUnsafeMutableBufferPointer { lBuf in
                right.withUnsafeMutableBufferPointer { rBuf in
                    engine.render(
                        left: lBuf.baseAddress!.advanced(by: cursor),
                        right: rBuf.baseAddress!.advanced(by: cursor),
                        frameCount: n
                    )
                }
            }
            cursor = end
        }

        try writeStereoWAV(left: left, right: right, sampleRate: sampleRate, to: url)
    }

    private static func writeStereoWAV(
        left: [Float],
        right: [Float],
        sampleRate: Double,
        to url: URL
    ) throws {
        let frames = min(left.count, right.count)
        let rate = Int(sampleRate.rounded())
        var samples = [Int16](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            let l = max(-1, min(1, left[i]))
            let r = max(-1, min(1, right[i]))
            samples[i * 2] = Int16((l * Float(Int16.max) * 0.85).rounded())
            samples[i * 2 + 1] = Int16((r * Float(Int16.max) * 0.85).rounded())
        }

        let byteRate = rate * 4
        let dataSize = samples.count * MemoryLayout<Int16>.size
        let riffSize = 36 + dataSize
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: u32(UInt32(riffSize)))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: u32(16))
        data.append(contentsOf: u16(1))
        data.append(contentsOf: u16(2))
        data.append(contentsOf: u32(UInt32(rate)))
        data.append(contentsOf: u32(UInt32(byteRate)))
        data.append(contentsOf: u16(4))
        data.append(contentsOf: u16(16))
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: u32(UInt32(dataSize)))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: [.atomic])
    }

    private static func u16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8)]
    }

    private static func u32(_ v: UInt32) -> [UInt8] {
        [
            UInt8(v & 0xFF),
            UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF),
            UInt8(v >> 24),
        ]
    }
}

public enum MXMIDIRenderError: Error, LocalizedError {
    case noNotes

    public var errorDescription: String? {
        switch self {
        case .noNotes: return "No MIDI notes to render"
        }
    }
}
