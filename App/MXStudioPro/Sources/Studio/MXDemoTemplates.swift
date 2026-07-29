import Foundation

/// BandLab-style starter projects with stub audio clips (Week 19).
struct MXDemoTemplate: Identifiable, Sendable {
    struct TrackSpec: Sendable {
        let name: String
        let kind: MXSessionTrack.Kind
        let category: MXSessionTrack.Category
        let clipDurationSeconds: Double
        let startBeat: Double
        let isArmed: Bool
        let freqA: Double
        let freqB: Double
        var reverbMix: Float?
        var delayMix: Float?
        var delayTime: Float?
        var distortionMix: Float?
    }

    let id: String
    let title: String
    let subtitle: String
    let bpm: Double
    let preset: StudioPreset
    let systemImage: String
    let tracks: [TrackSpec]
}

enum MXDemoTemplates {
    enum TemplateError: Error, LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let detail):
                return "Could not write template audio: \(detail)"
            }
        }
    }

    static let all: [MXDemoTemplate] = [
        .init(
            id: "lofi_beat",
            title: "Lo-Fi Beat",
            subtitle: "Chill drums + keys bed",
            bpm: 82,
            preset: .template,
            systemImage: "waveform.path",
            tracks: [
                .init(
                    name: "Drums",
                    kind: .audio,
                    category: .imported,
                    clipDurationSeconds: 8,
                    startBeat: 0,
                    isArmed: false,
                    freqA: 90,
                    freqB: 135
                ),
                .init(
                    name: "Keys Bed",
                    kind: .audio,
                    category: .imported,
                    clipDurationSeconds: 8,
                    startBeat: 0,
                    isArmed: true,
                    freqA: 220,
                    freqB: 330
                ),
            ]
        ),
        .init(
            id: "vocal_idea",
            title: "Vocal Idea",
            subtitle: "Empty vocal + guide beat",
            bpm: 90,
            preset: .vocal,
            systemImage: "mic.fill",
            tracks: [
                .init(
                    name: "Guide Beat",
                    kind: .audio,
                    category: .imported,
                    clipDurationSeconds: 6,
                    startBeat: 0,
                    isArmed: false,
                    freqA: 110,
                    freqB: 165
                ),
                .init(
                    name: "Vocals/Audio",
                    kind: .audio,
                    category: .vocal,
                    clipDurationSeconds: 0,
                    startBeat: 0,
                    isArmed: true,
                    freqA: 0,
                    freqB: 0
                ),
            ]
        ),
        .init(
            id: "guitar_loop",
            title: "Guitar Loop",
            subtitle: "Rhythm loop ready to jam",
            bpm: 110,
            preset: .guitar,
            systemImage: "guitars.fill",
            tracks: [
                .init(
                    name: "Guitar Loop",
                    kind: .audio,
                    category: .guitar,
                    clipDurationSeconds: 4,
                    startBeat: 0,
                    isArmed: true,
                    freqA: 196,
                    freqB: 294,
                    reverbMix: 12,
                    delayMix: 18,
                    delayTime: 0.28,
                    distortionMix: 22
                ),
            ]
        ),
        .init(
            id: "keys_sketch",
            title: "Keys Sketch",
            subtitle: "Piano + pad starter",
            bpm: 120,
            preset: .midi,
            systemImage: "pianokeys",
            tracks: [
                .init(
                    name: "Pad",
                    kind: .audio,
                    category: .imported,
                    clipDurationSeconds: 6,
                    startBeat: 0,
                    isArmed: false,
                    freqA: 130,
                    freqB: 195
                ),
                .init(
                    name: "Piano",
                    kind: .midi,
                    category: .keys,
                    clipDurationSeconds: 0,
                    startBeat: 0,
                    isArmed: true,
                    freqA: 0,
                    freqB: 0
                ),
            ]
        ),
    ]

    static func template(id: String) -> MXDemoTemplate? {
        all.first { $0.id == id }
    }

    /// Creates a persisted starter project from a demo template.
    static func createProject(from template: MXDemoTemplate) throws -> UUID {
        let store = MXProjectStore.shared
        var project = MXProject(
            name: template.title,
            bpm: template.bpm,
            tracks: [],
            preset: template.preset
        )

        let audioDir = store.audioDirectory(for: project.id)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        for spec in template.tracks {
            var track = MXSessionTrack(
                name: spec.name,
                kind: spec.kind,
                category: spec.category,
                isArmed: spec.isArmed
            )
            if let reverb = spec.reverbMix { track.reverbMix = reverb }
            if let delay = spec.delayMix { track.delayMix = delay }
            if let delayTime = spec.delayTime { track.delayTime = delayTime }
            if let distortion = spec.distortionMix { track.distortionMix = distortion }

            if spec.clipDurationSeconds > 0, spec.kind == .audio {
                let fileName = "tpl_\(template.id)_\(track.id.uuidString.prefix(6)).wav"
                let wavURL = audioDir.appendingPathComponent(fileName)
                do {
                    try MXAIAudioStub.writeStubWAV(
                        to: wavURL,
                        durationSeconds: spec.clipDurationSeconds,
                        freqA: spec.freqA > 0 ? spec.freqA : 220,
                        freqB: spec.freqB > 0 ? spec.freqB : 330
                    )
                } catch {
                    throw TemplateError.writeFailed(error.localizedDescription)
                }

                let lengthBeats = max(0.25, spec.clipDurationSeconds * template.bpm / 60.0)
                let clip = MXClip(
                    trackID: track.id,
                    name: spec.name,
                    startBeat: spec.startBeat,
                    lengthBeats: lengthBeats,
                    audioFileName: fileName,
                    sourceOffsetSeconds: 0,
                    sourceDurationSeconds: spec.clipDurationSeconds
                )
                track.clips.append(clip)
            }

            project.tracks.append(track)
        }

        try store.save(project)
        return project.id
    }
}
