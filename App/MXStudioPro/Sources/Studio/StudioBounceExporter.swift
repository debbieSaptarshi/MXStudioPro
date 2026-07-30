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

    /// One per-track stem from `bounceStems` (Ableton / BandLab stem export lite).
    public struct StemResult: Sendable {
        public var trackID: UUID
        public var trackName: String
        public var wavURL: URL
        public var m4aURL: URL
        public var durationSeconds: Double
        public var loudnessMode: LoudnessMode
    }

    public struct StemsResult: Sendable {
        public var stems: [StemResult]
        public var loudnessMode: LoudnessMode

        public var allURLs: [URL] {
            stems.flatMap { [$0.wavURL, $0.m4aURL] }
        }
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
        loudnessMode: LoudnessMode = .peakNormalize,
        highPassEnabled: Bool = true
    ) throws -> Result {
        let sampleRate = project.sampleRate > 0 ? project.sampleRate : 48_000
        let bpm = max(project.bpm, 1)
        let anySolo = project.tracks.contains(where: \.isSolo)

        var endBeat: Double = 0
        var jobs: [(clip: MXClip, track: MXSessionTrack, url: URL)] = []
        var skippedMissing = 0
        var fxTailSeconds: Double = 0.25
        for track in project.tracks {
            if track.isMuted { continue }
            if anySolo && !track.isSolo { continue }
            for clip in track.clips {
                guard clip.isActive else { continue }
                guard let name = clip.audioFileName else { continue }
                let url = audioDirectory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    skippedMissing += 1
                    continue
                }
                jobs.append((clip, track, url))
                endBeat = max(endBeat, clip.startBeat + clip.lengthBeats)
                fxTailSeconds = max(fxTailSeconds, mixClipFXTailSeconds(track: track))
            }
        }
        guard !jobs.isEmpty, endBeat > 0 else {
            if skippedMissing > 0 {
                throw BounceError.writeFailed("Audio files missing for \(skippedMissing) clip(s). Re-record or re-import.")
            }
            throw BounceError.noAudio
        }

        let totalSeconds = endBeat * 60.0 / bpm + fxTailSeconds
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
                highPassEnabled: highPassEnabled,
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
                // LUFS path applies the shared master limiter internally via maxPeak.
                MXLoudness.normalizeToLUFS(left: &left, right: &right, targetLUFS: -14, maxPeak: 0.99)
                appliedMode = .reelsLUFS
            }
            // Peak path: safety brickwall after −1 dBFS normalize. LUFS already
            // limited; second pass is a no-op when peak ≤ ceiling.
            applyMasterLimiter(left: &left, right: &right, ceiling: 0.99)
        } else {
            // Still protect overs when normalize is off.
            applyMasterLimiter(left: &left, right: &right, ceiling: 0.99)
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

    /// Bounce each track with audible clips to its own WAV + M4A (stem export).
    ///
    /// Ignores mute/solo so every track with audio becomes a stem (BandLab / Ableton style).
    /// Tracks with no active audio files are skipped.
    public static func bounceStems(
        project: MXProject,
        audioDirectory: URL,
        outputDirectory: URL,
        normalize: Bool = true,
        loudnessMode: LoudnessMode = .peakNormalize,
        highPassEnabled: Bool = true
    ) throws -> StemsResult {
        let sampleRate = project.sampleRate > 0 ? project.sampleRate : 48_000
        let bpm = max(project.bpm, 1)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)

        var stems: [StemResult] = []
        var skippedMissing = 0
        var appliedMode = loudnessMode

        for track in project.tracks {
            var endBeat: Double = 0
            var jobs: [(clip: MXClip, url: URL)] = []
            var fxTailSeconds: Double = 0.25
            for clip in track.clips {
                guard clip.isActive else { continue }
                guard let name = clip.audioFileName else { continue }
                let url = audioDirectory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    skippedMissing += 1
                    continue
                }
                jobs.append((clip, url))
                endBeat = max(endBeat, clip.startBeat + clip.lengthBeats)
                fxTailSeconds = max(fxTailSeconds, mixClipFXTailSeconds(track: track))
            }
            guard !jobs.isEmpty, endBeat > 0 else { continue }

            let totalSeconds = endBeat * 60.0 / bpm + fxTailSeconds
            let frameCount = max(1, Int((totalSeconds * sampleRate).rounded(.up)))
            var left = [Float](repeating: 0, count: frameCount)
            var right = [Float](repeating: 0, count: frameCount)

            for job in jobs {
                try mixClip(
                    url: job.url,
                    clip: job.clip,
                    track: track,
                    bpm: bpm,
                    sampleRate: sampleRate,
                    highPassEnabled: highPassEnabled,
                    intoLeft: &left,
                    intoRight: &right
                )
            }

            if normalize {
                switch loudnessMode {
                case .peakNormalize:
                    peakNormalize(left: &left, right: &right, targetPeak: 0.89)
                    appliedMode = .peakNormalize
                case .reelsLUFS:
                    MXLoudness.normalizeToLUFS(left: &left, right: &right, targetLUFS: -14, maxPeak: 0.99)
                    appliedMode = .reelsLUFS
                }
                applyMasterLimiter(left: &left, right: &right, ceiling: 0.99)
            } else {
                applyMasterLimiter(left: &left, right: &right, ceiling: 0.99)
                appliedMode = loudnessMode
            }

            let base = "Stem_\(sanitize(track.name))_\(stamp)"
            let wavURL = outputDirectory.appendingPathComponent("\(base).wav")
            let m4aURL = outputDirectory.appendingPathComponent("\(base).m4a")
            try writeWAV(left: left, right: right, sampleRate: sampleRate, to: wavURL)
            try writeM4A(left: left, right: right, sampleRate: sampleRate, to: m4aURL)

            stems.append(
                StemResult(
                    trackID: track.id,
                    trackName: track.name,
                    wavURL: wavURL,
                    m4aURL: m4aURL,
                    durationSeconds: totalSeconds,
                    loudnessMode: appliedMode
                )
            )
        }

        guard !stems.isEmpty else {
            if skippedMissing > 0 {
                throw BounceError.writeFailed("Audio files missing for \(skippedMissing) clip(s). Re-record or re-import.")
            }
            throw BounceError.noAudio
        }

        return StemsResult(stems: stems, loudnessMode: appliedMode)
    }

    // MARK: - Mix

    private static func mixClip(
        url: URL,
        clip: MXClip,
        track: MXSessionTrack,
        bpm: Double,
        sampleRate: Double,
        highPassEnabled: Bool,
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
        let baseGain = track.volume * clip.gain
        let trackPan = track.pan
        let hasTrackAutomation = !track.volumeAutomation.isEmpty
        let hasClipVolAutomation = !clip.volumeAutomation.isEmpty
        let hasClipPanAutomation = !clip.panAutomation.isEmpty
        let ratio = sampleRate / max(fileSR, 1)
        let outFrames = Int((Double(framesToRead) * ratio).rounded())
        let audibleDuration = Double(outFrames) / max(sampleRate, 1)

        // Live insert order: vocal HPF → EQ → De-ess → Gate → Delay → Dist → Dyn → Rev;
        // guitar HPF → EQ/Tone → Dist → Delay → Rev (soft-clip Dist approx).
        // Gate sits after de-ess (before delay) — closer to live Dynamics placement than pre-EQ.
        let hpfOn = highPassEnabled || track.reelsVocalEnabled
        var hpf = MXBiquad()
        if hpfOn {
            hpf.configure(kind: .highpass, frequency: 100, q: 0.707, sampleRate: sampleRate)
        }

        let eqGain = track.eqMidGain
        let eqOn = abs(eqGain) >= 0.05
        var eqMid = MXBiquad()
        if eqOn {
            eqMid.configure(
                kind: .peaking,
                frequency: 1_200,
                q: 1.0,
                gainDB: eqGain,
                sampleRate: sampleRate
            )
        }

        let deEssOn = track.deEsserEnabled && track.deEsserAmount > 0.5
        var deEssFilter = MXBiquad()
        if deEssOn {
            deEssFilter.configure(
                kind: .peaking,
                frequency: 6_500,
                q: 1.4,
                gainDB: -(track.deEsserAmount / 100) * 12,
                sampleRate: sampleRate
            )
        }

        let gateOn = track.noiseGateEnabled
        let gateThreshold = min(max(track.noiseGateThreshold, 0), 0.2)

        let delayOn = track.delayMix >= 0.5
        let delayLine: MXDelayLine? = delayOn ? MXDelayLine(maxDelaySeconds: 2.0, sampleRate: sampleRate) : nil
        if let delayLine {
            delayLine.setDelay(milliseconds: track.delayTime * 1_000)
            delayLine.feedback = 0.35
            delayLine.mix = track.delayMix / 100
        }

        let isGuitar = track.category == .guitar
        let distOn = track.distortionMix >= 0.5
        let distAmount = track.distortionMix

        let reelsCompOn = track.reelsVocalEnabled && !isGuitar

        let reverbOn = track.reverbMix > 0.5
        let reverb: MXSimpleReverb? = reverbOn
            ? MXSimpleReverb(sampleRate: sampleRate, smallRoom: track.reelsVocalEnabled)
            : nil
        reverb?.wetDryMix = track.reverbMix

        // Run silence through delay/reverb after the dry clip so wet tails are not chopped.
        let tailFrames = Int((mixClipFXTailSeconds(track: track) * sampleRate).rounded())
        let processFrames = outFrames + (delayOn || reverbOn ? tailFrames : 0)

        for i in 0..<processFrames {
            var mono: Float
            if i < outFrames {
                let srcIndex = min(Int(framesToRead) - 1, Int((Double(i) / ratio).rounded(.down)))
                if channels >= 2 {
                    mono = 0.5 * (data[0][srcIndex] + data[1][srcIndex])
                } else {
                    mono = data[0][srcIndex]
                }
                // Fade the dry input so insert FX (esp. reverb/delay) can ring out naturally.
                let t = Double(i) / max(sampleRate, 1)
                mono *= clip.fadeEnvelope(atSeconds: t, durationSeconds: audibleDuration)
            } else {
                mono = 0
            }
            if hpfOn {
                mono = hpf.process(mono)
            }
            if eqOn {
                mono = eqMid.process(mono)
            }
            if deEssOn && !isGuitar {
                mono = deEssFilter.process(mono)
            }
            if gateOn && !isGuitar {
                mono = applyNoiseGate(mono, threshold: gateThreshold)
            }
            // Guitar pedalboard: Dist before Delay (matches live insert order).
            // Other tracks keep Delay → Dist approximation after the delay stage.
            if isGuitar, distOn {
                mono = MXGuitarPedalPreset.bounceDistortion(sample: mono, amount: distAmount)
            }
            if let delayLine {
                mono = delayLine.process(mono)
            }
            if !isGuitar, distOn {
                mono = MXGuitarPedalPreset.bounceDistortion(sample: mono, amount: distAmount)
            }
            if reelsCompOn {
                mono = applySoftCompressor(mono)
            }
            if let reverb {
                mono = reverb.process(mono)
            }
            let di = destStart + i
            guard di >= 0, di < left.count else { continue }
            let beat = Double(di) / max(sampleRate, 1) * bpm / 60.0
            let trackAuto = hasTrackAutomation
                ? MXVolumeAutomation.value(atBeat: beat, points: track.volumeAutomation)
                : MXVolumeAutomation.unity
            let clipAuto = hasClipVolAutomation
                ? clip.volumeAutomationGain(atProjectBeat: beat)
                : MXVolumeAutomation.unity
            let panOffset = hasClipPanAutomation
                ? clip.panAutomationOffset(atProjectBeat: beat)
                : MXPanAutomation.center
            let pan = MXPanAutomation.combined(trackPan: trackPan, clipOffset: panOffset)
            let gain = baseGain * trackAuto * clipAuto
            let leftGain = gain * min(1, max(0, 1 - pan))
            let rightGain = gain * min(1, max(0, 1 + pan))
            left[di] += mono * leftGain
            right[di] += mono * rightGain
        }
    }

    /// Extra seconds of silence to render through delay/reverb after clip audio ends.
    static func mixClipFXTailSeconds(track: MXSessionTrack) -> Double {
        var tail: Double = 0.25
        if track.delayMix >= 0.5 {
            // Primary echo + a couple of feedback repeats.
            tail = max(tail, Double(track.delayTime) * 3 + 0.15)
        }
        if track.reverbMix > 0.5 {
            // Schroeder combs ~1s RT60 (medium) / shorter for Reels small room.
            tail = max(tail, track.reelsVocalEnabled ? 0.85 : 1.35)
        }
        return tail
    }

    /// Soft-knee downward expander: below `threshold`, gain falls as (abs/threshold)².
    /// At/above threshold the sample passes unchanged. Bounce-only MVP (no live AVAudioUnit).
    static func applyNoiseGate(_ sample: Float, threshold: Float) -> Float {
        let thresh = max(threshold, 1e-6)
        let magnitude = abs(sample)
        guard magnitude < thresh else { return sample }
        let ratio = magnitude / thresh
        // Soft knee: quadratic taper toward silence (strong attenuation, not hard mute).
        return sample * ratio * ratio
    }

    /// Soft-knee compressor for Reels Vocal bounce path (mirrors live Dynamics ~−18 dB / +2 dB).
    static func applySoftCompressor(
        _ sample: Float,
        thresholdLinear: Float = 0.12589254, // −18 dBFS
        ratio: Float = 3,
        makeup: Float = 1.2589254, // +2 dB
        kneeWidth: Float = 0.06
    ) -> Float {
        let x = abs(sample)
        guard x > 1e-9 else { return 0 }
        let halfKnee = kneeWidth * 0.5
        let lower = max(thresholdLinear - halfKnee, 1e-6)
        let upper = thresholdLinear + halfKnee
        let gain: Float
        if x <= lower {
            gain = 1
        } else {
            let over = max(0, x - thresholdLinear)
            // Compressors only attenuate — clamp so the soft knee never boosts below threshold.
            let hardGain = min(1, (thresholdLinear + over / max(ratio, 1)) / x)
            if x >= upper {
                gain = hardGain
            } else {
                let t = (x - lower) / max(kneeWidth, 1e-6)
                let soft = t * t
                gain = 1 + soft * (hardGain - 1)
            }
        }
        return sample * gain * makeup
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

    /// Soft master limiter / brickwall so true peak stays ≤ ~0.99 (−0.1 dBTP-ish).
    /// Shared helper used after peak normalize and by the LUFS path (`MXLoudness`).
    public static func applyMasterLimiter(left: inout [Float],
                                          right: inout [Float],
                                          ceiling: Float = 0.99) {
        MXLoudness.applyMasterLimiter(left: &left, right: &right, ceiling: ceiling)
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
