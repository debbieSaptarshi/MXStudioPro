import Foundation

/// Bridges Discover cards → starter `MXProject` for Open in Studio / Remix (Week 19).
enum MXDiscoverStudioBridge {
    enum BridgeMode: Sendable {
        case openInStudio
        case remix
    }

    enum BridgeError: Error, LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let detail):
                return "Could not create project from Discover: \(detail)"
            }
        }
    }

    /// Creates a starter project from a Discover card's metadata + stub reference audio.
    static func createProject(from item: DiscoverItem, mode: BridgeMode) throws -> UUID {
        let store = MXProjectStore.shared
        let bpm = inferredBPM(for: item)
        let preset = inferredPreset(for: item)
        let projectName = projectName(for: item, mode: mode)

        var project = MXProject(
            name: projectName,
            bpm: bpm,
            tracks: [],
            preset: preset
        )

        let audioDir = store.audioDirectory(for: project.id)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let refTrack = MXSessionTrack(
            name: "Reference",
            kind: .audio,
            category: .imported,
            isArmed: false
        )

        let stubDuration = 6.0
        let fileName = "disc_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"
        let wavURL = audioDir.appendingPathComponent(fileName)
        let freqs = stubFrequencies(for: item)
        do {
            try MXAIAudioStub.writeStubWAV(
                to: wavURL,
                durationSeconds: stubDuration,
                freqA: freqs.a,
                freqB: freqs.b
            )
        } catch {
            throw BridgeError.writeFailed(error.localizedDescription)
        }

        let lengthBeats = max(0.25, stubDuration * bpm / 60.0)
        var mutableRef = refTrack
        mutableRef.clips.append(
            MXClip(
                trackID: refTrack.id,
                name: item.title,
                startBeat: 0,
                lengthBeats: lengthBeats,
                audioFileName: fileName,
                sourceOffsetSeconds: 0,
                sourceDurationSeconds: stubDuration
            )
        )
        project.tracks.append(mutableRef)

        if mode == .remix {
            let remixTrack = MXSessionTrack(
                name: remixTrackName(for: item),
                kind: .audio,
                category: remixCategory(for: item),
                isArmed: true
            )
            project.tracks.append(remixTrack)
        } else {
            let recordTrack = MXSessionTrack(
                name: "Your Track",
                kind: .audio,
                category: .vocal,
                isArmed: true
            )
            project.tracks.append(recordTrack)
        }

        try store.save(project)
        return project.id
    }

    private static func projectName(for item: DiscoverItem, mode: BridgeMode) -> String {
        let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .openInStudio:
            return String(trimmed.prefix(40))
        case .remix:
            return "Remix — \(String(trimmed.prefix(32)))"
        }
    }

    private static func remixTrackName(for item: DiscoverItem) -> String {
        "Remix Layer"
    }

    private static func inferredBPM(for item: DiscoverItem) -> Double {
        if let genre = item.genre?.lowercased() {
            if genre.contains("lo-fi") || genre.contains("lofi") { return 82 }
            if genre.contains("hip") || genre.contains("trap") { return 140 }
            if genre.contains("rock") || genre.contains("indie") { return 110 }
            if genre.contains("pop") { return 120 }
            if genre.contains("electronic") || genre.contains("dance") { return 128 }
        }
        return 100
    }

    private static func inferredPreset(for item: DiscoverItem) -> StudioPreset {
        if let genre = item.genre?.lowercased() {
            if genre.contains("guitar") || genre.contains("rock") { return .guitar }
            if genre.contains("keys") || genre.contains("piano") { return .midi }
        }
        return .template
    }

    private static func remixCategory(for item: DiscoverItem) -> MXSessionTrack.Category {
        switch inferredPreset(for: item) {
        case .guitar: return .guitar
        case .midi: return .keys
        default: return .vocal
        }
    }

    private static func stubFrequencies(for item: DiscoverItem) -> (a: Double, b: Double) {
        let seed = abs(item.title.hashValue)
        let base = 180.0 + Double(seed % 80)
        return (base, base * 1.5)
    }
}
