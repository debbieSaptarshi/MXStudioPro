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

    /// Creates a new AI preset project, copies staged MP3 into `Audio/`, adds track + clip, persists.
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
        let copied: (fileName: String, durationSeconds: Double)
        do {
            copied = try MXAIAudioFileWriter.copyStagedFile(result.stagedFileName, to: audioDir)
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
            audioDurationSeconds: copied.durationSeconds,
            bpm: project.bpm
        )
        let clip = MXClip(
            trackID: track.id,
            name: trackName,
            startBeat: 0,
            lengthBeats: lengthBeats,
            audioFileName: copied.fileName,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: copied.durationSeconds
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
        let copied: (fileName: String, durationSeconds: Double)
        do {
            copied = try MXAIAudioFileWriter.copyStagedFile(result.stagedFileName, to: audioDir)
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }

        guard let track = session.addAudioTrack(named: trackName) else {
            throw ImportError.trackLimitReached
        }
        session.setTrackCategory(.imported, trackID: track.id)

        let lengthBeats = timelineLengthBeats(
            resultDurationSeconds: result.durationSeconds,
            audioDurationSeconds: copied.durationSeconds,
            bpm: session.bpm
        )

        let clip = MXClip(
            trackID: track.id,
            name: trackName,
            startBeat: 0,
            lengthBeats: lengthBeats,
            audioFileName: copied.fileName,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: copied.durationSeconds
        )
        try session.addImportedClip(clip, toTrackID: track.id)
        return track
    }

    private static func sanitizedTrackName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "AI Track" : trimmed
        return String(base.prefix(28))
    }

    private static func timelineLengthBeats(
        resultDurationSeconds: Int,
        audioDurationSeconds: Double,
        bpm: Double
    ) -> Double {
        let beatsFromResult = Double(resultDurationSeconds) * bpm / 60.0
        let beatsFromAudio = audioDurationSeconds * bpm / 60.0
        return max(0.25, beatsFromResult, beatsFromAudio)
    }
}
