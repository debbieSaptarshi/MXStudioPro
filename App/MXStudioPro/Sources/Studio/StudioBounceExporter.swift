import AVFoundation
import Foundation
import MXStudioEngine

/// Offline mix bounce for Week 8+ — mixes project clips to stereo WAV + M4A.
public enum StudioBounceExporter {
    public enum LoudnessMode: String, Sendable, CaseIterable {
        /// Peak normalize to ~−1 dBFS (original Week 8 behavior).
        case peakNormalize
        /// Target ~−14 LUFS for Reels / TikTok, then peak-cap.
        case reelsLUFS
    }

    public struct Result: Sendable {
        public var wavURL: URL
        public var m4aURL: URL
        public var durationSeconds: Double
        public var loudnessMode: LoudnessMode
    }

    public enum BounceError: Error, LocalizedError {
        case noAudio
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAudio: return "Nothing to export — add a take or import first."
            case .writeFailed(let detail): return "Export failed: \(detail)"
            }
        }
    }

    public static func bounce(
        project: MXProject,
        audioDirectory: URL,
        outputDirectory: URL,
        normalize: Bool = true,
        loudnessMode: LoudnessMode = .peakNormalize
    ) throws -> Result {
        let sampleRate = project.sampleRate > 0 ? project.sampleRate : 48_000
        let bpm = max(project.bpm, 1)
        let anySolo = project.tracks.contains(where: \.isSolo)

        var endBeat: Double = 0
        var jobs: [(clip: MXClip, track: MXSessionTrack, url: URL)] = []
        var skippedMissing = 0
        for track in project.tracks {
            if track.isMuted { continue }
            if anySolo && !track.isSolo { continue }
            for clip in track.clips {
                guard let name = clip.audioFileName else { continue }
                let url = audioDirectory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    skippedMissing += 1
                    continue
                }
                jobs.append((clip, track, url))
                endBeat = max(endBeat, clip.startBeat + clip.lengthBeats)
            }
        }
        guard !jobs.isEmpty, endBeat > 0 else {
            if skippedMissing > 0 {
                throw BounceError.writeFailed("Audio files missing for \(skippedMissing) clip(s). Re-record or re-import.")
            }
            throw BounceError.noAudio
        }

        let totalSeconds = endBeat * 60.0 / bpm + 0.25
        let frameCount = max(1, Int((totalSeconds * sampleRate).rounded(.up)))
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)

        for job in jobs {
            try mixClip(
                url: job.url,
                clip: job.clip,
                track: job.track,
                bpm: bpm,
                sampleRate: sampleRate,
                intoLeft: &left,
                intoRight: &right
            )
        }

        let appliedMode: LoudnessMode
        if normalize {
            switch loudnessMode {
            case .peakNormalize:
                peakNormalize(left: &left, right: &right, targetPeak: 0.89)
                appliedMode = .peakNormalize
            case .reelsLUFS:
                MXLoudness.normalizeToLUFS(left: &left, right: &right, targetLUFS: -14, maxPeak: 0.99)
                appliedMode = .reelsLUFS
            }
        } else {
            appliedMode = loudnessMode
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let base = "Mix_\(sanitize(project.name))_\(stamp)"
        let wavURL = outputDirectory.appendingPathComponent("\(base).wav")
        let m4aURL = outputDirectory.appendingPathComponent("\(base).m4a")

        try writeWAV(left: left, right: right, sampleRate: sampleRate, to: wavURL)
        try writeM4A(left: left, right: right, sampleRate: sampleRate, to: m4aURL)

        return Result(
            wavURL: wavURL,
            m4aURL: m4aURL,
            durationSeconds: totalSeconds,
            loudnessMode: appliedMode
        )
    }

    // MARK: - Mix

    private static func mixClip(
        url: URL,
        clip: MXClip,
        track: MXSessionTrack,
        bpm: Double,
        sampleRate: Double,
        intoLeft left: inout [Float],
        intoRight right: inout [Float]
    ) throws {
        let file = try AVAudioFile(forReading: url)
        let fileSR = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)
        let startFrame = AVAudioFramePosition((clip.sourceOffsetSeconds * fileSR).rounded())
        let maxFrames = AVAudioFrameCount(max(0, file.length - startFrame))
        let durationSeconds = clip.sourceDurationSeconds
            ?? (Double(maxFrames) / max(fileSR, 1))
        var framesToRead = AVAudioFrameCount(min(Double(maxFrames), (durationSeconds * fileSR).rounded()))
        guard framesToRead > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: framesToRead)
        else { return }

        file.framePosition = startFrame
        try file.read(into: buffer, frameCount: framesToRead)
        framesToRead = buffer.frameLength
        guard framesToRead > 0, let data = buffer.floatChannelData else { return }

        let destStart = Int((clip.startBeat * 60.0 / bpm * sampleRate).rounded())
        let gain = track.volume * clip.gain
        let pan = track.pan
        let leftGain = gain * min(1, max(0, 1 - pan))
        let rightGain = gain * min(1, max(0, 1 + pan))
        let ratio = sampleRate / max(fileSR, 1)
        let outFrames = Int((Double(framesToRead) * ratio).rounded())
        let audibleDuration = Double(outFrames) / max(sampleRate, 1)

        for i in 0..<outFrames {
            let srcIndex = min(Int(framesToRead) - 1, Int((Double(i) / ratio).rounded(.down)))
            let mono: Float
            if channels >= 2 {
                mono = 0.5 * (data[0][srcIndex] + data[1][srcIndex])
            } else {
                mono = data[0][srcIndex]
            }
            let t = Double(i) / max(sampleRate, 1)
            let envelope = clip.fadeEnvelope(atSeconds: t, durationSeconds: audibleDuration)
            let di = destStart + i
            guard di >= 0, di < left.count else { continue }
            left[di] += mono * leftGain * envelope
            right[di] += mono * rightGain * envelope
        }
    }

    static func peakNormalize(left: inout [Float], right: inout [Float], targetPeak: Float = 0.89) {
        var peak: Float = 0
        for i in 0..<left.count {
            peak = max(peak, abs(left[i]), abs(right[i]))
        }
        guard peak > 1e-6 else { return }
        // Scale so peak lands at target (~−1 dBFS). Boosts quiet mixes and tames overs.
        let scale = min(8, targetPeak / peak)
        for i in 0..<left.count {
            left[i] *= scale
            right[i] *= scale
        }
    }

    // MARK: - Writers

    static func writeWAV(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
        guard left.count == right.count, !left.isEmpty else { throw BounceError.noAudio }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw BounceError.writeFailed("Invalid WAV format")
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))
        else { throw BounceError.writeFailed("Buffer alloc") }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: left.count)
        }
        right.withUnsafeBufferPointer { src in
            buffer.floatChannelData![1].update(from: src.baseAddress!, count: right.count)
        }
        try file.write(from: buffer)
    }

    static func writeM4A(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
        guard left.count == right.count, !left.isEmpty else { throw BounceError.noAudio }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw BounceError.writeFailed(error.localizedDescription)
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count))
        else { throw BounceError.writeFailed("M4A buffer") }

        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: left.count)
        }
        right.withUnsafeBufferPointer { src in
            buffer.floatChannelData![1].update(from: src.baseAddress!, count: right.count)
        }
        do {
            try file.write(from: buffer)
        } catch {
            // Some simulators reject float → AAC; fall back to Int16 PCM buffer convert via WAV re-read path
            throw BounceError.writeFailed(error.localizedDescription)
        }
    }

    private static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "Untitled" : trimmed
        return safe
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(24)
            .description
    }
}
