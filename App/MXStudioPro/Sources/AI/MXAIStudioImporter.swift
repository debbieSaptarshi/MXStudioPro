import Foundation

enum MXAIStudioImporter {
    enum ImportError: Error, LocalizedError {
        case trackLimitReached
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .trackLimitReached:
                return "Track limit reached (\(StudioSessionController.maxTracks))"
            case .writeFailed(let detail):
                return "Could not write AI audio: \(detail)"
            }
        }
    }

    /// Creates a new AI preset project, writes stub WAV, adds track + clip, persists.
    @MainActor
    static func importIntoNewProject(result: AIComposeResult) throws -> UUID {
        let store = MXProjectStore.shared
        let trackName = sanitizedTrackName(from: result.title)
        var project = MXProject(
            name: String(result.title.prefix(48)),
            bpm: 120,
            tracks: [],
            preset: .ai
        )

        let audioDir = store.audioDirectory(for: project.id)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let stubDuration = stubDurationSeconds(for: result)
        let fileName = "ai_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"
        let wavURL = audioDir.appendingPathComponent(fileName)
        do {
            try MXAIAudioStub.writeStubWAV(to: wavURL, durationSeconds: stubDuration)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        let track = MXSessionTrack(
            name: trackName,
            kind: .audio,
            category: .imported,
            isArmed: true
        )
        let lengthBeats = timelineLengthBeats(
            resultDurationSeconds: result.durationSeconds,
            stubDurationSeconds: stubDuration,
            bpm: project.bpm
        )
        let clip = MXClip(
            trackID: track.id,
            name: trackName,
            startBeat: 0,
            lengthBeats: lengthBeats,
            audioFileName: fileName,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: stubDuration
        )

        var mutableTrack = track
        mutableTrack.clips.append(clip)
        project.tracks.append(mutableTrack)

        try store.save(project)
        return project.id
    }

    /// Adds an AI audio track + clip to the active Studio session.
    @MainActor
    @discardableResult
    static func importIntoSession(_ session: StudioSessionController, result: AIComposeResult) throws -> MXSessionTrack {
        guard session.canAddTrack else {
            throw ImportError.trackLimitReached
        }

        let trackName = sanitizedTrackName(from: result.title)
        let audioDir = MXProjectStore.shared.audioDirectory(for: session.project.id)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let stubDuration = stubDurationSeconds(for: result)
        let fileName = "ai_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"
        let wavURL = audioDir.appendingPathComponent(fileName)
        do {
            try MXAIAudioStub.writeStubWAV(to: wavURL, durationSeconds: stubDuration)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        guard let track = session.addAudioTrack(named: trackName) else {
            try? FileManager.default.removeItem(at: wavURL)
            throw ImportError.trackLimitReached
        }
        session.setTrackCategory(.imported, trackID: track.id)

        let lengthBeats = timelineLengthBeats(
            resultDurationSeconds: result.durationSeconds,
            stubDurationSeconds: stubDuration,
            bpm: session.bpm
        )

        let clip = MXClip(
            trackID: track.id,
            name: trackName,
            startBeat: 0,
            lengthBeats: lengthBeats,
            audioFileName: fileName,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: stubDuration
        )
        try session.addImportedClip(clip, toTrackID: track.id)
        return track
    }

    private static func stubDurationSeconds(for result: AIComposeResult) -> Double {
        min(max(1, Double(result.durationSeconds)), 4)
    }

    private static func sanitizedTrackName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "AI Track" : trimmed
        return String(base.prefix(28))
    }

    private static func timelineLengthBeats(
        resultDurationSeconds: Int,
        stubDurationSeconds: Double,
        bpm: Double
    ) -> Double {
        let beatsFromResult = Double(resultDurationSeconds) * bpm / 60.0
        let beatsFromStub = stubDurationSeconds * bpm / 60.0
        return max(0.25, beatsFromResult, beatsFromStub)
    }
}
