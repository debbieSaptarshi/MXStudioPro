import Foundation

public enum StudioPreset: String, Equatable, Sendable {
    case vocal
    case importFile
    case guitar
    case bass
    case midi
    case looper
    case sampler
    case ai
    case live
    case template

    public var title: String {
        switch self {
        case .vocal: return "Vocals / Audio"
        case .importFile: return "Import File"
        case .guitar: return "Guitar"
        case .bass: return "Bass"
        case .midi: return "Virtual Instrument"
        case .looper: return "Looper"
        case .sampler: return "Sampler"
        case .ai: return "Create Music With AI"
        case .live: return "Live Performance"
        case .template: return "Template"
        }
    }
}

/// In-memory / on-disk project document for the Studio session layer (Week 3).
/// Clips stay empty until Week 4 recording lands audio files.
public struct MXProject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var bpm: Double
    public var timeSignatureNumerator: Int
    public var timeSignatureDenominator: Int
    public var sampleRate: Double
    public var tracks: [MXSessionTrack]
    public var presetRaw: String

    public init(
        id: UUID = UUID(),
        name: String = "Untitled",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        bpm: Double = 120,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4,
        sampleRate: Double = 48_000,
        tracks: [MXSessionTrack] = [],
        preset: StudioPreset = .vocal
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.bpm = bpm
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.sampleRate = sampleRate
        self.tracks = tracks
        self.presetRaw = preset.rawValue
    }

    public var preset: StudioPreset {
        StudioPreset(rawValue: presetRaw) ?? .vocal
    }

    public var armedTrack: MXSessionTrack? {
        tracks.first(where: \.isArmed) ?? tracks.first
    }

    /// Vocals path: one armed audio track ready for Week 4 record.
    public static func untitledVocal(bpm: Double = 120) -> MXProject {
        let track = MXSessionTrack(
            name: "Vocals/Audio",
            kind: .audio,
            isArmed: true
        )
        return MXProject(
            name: "Untitled Vocals",
            bpm: bpm,
            tracks: [track],
            preset: .vocal
        )
    }
}

public struct MXSessionTrack: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case audio
        case midi
        case bus
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var isArmed: Bool
    public var isMuted: Bool
    public var isSolo: Bool
    public var volume: Float
    public var pan: Float
    public var clips: [MXClip]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .audio,
        isArmed: Bool = false,
        isMuted: Bool = false,
        isSolo: Bool = false,
        volume: Float = 0.8,
        pan: Float = 0,
        clips: [MXClip] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isArmed = isArmed
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.volume = volume
        self.pan = pan
        self.clips = clips
    }
}

public struct MXClip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var name: String
    /// Start position in quarter-note beats from project start.
    public var startBeat: Double
    public var lengthBeats: Double
    /// Relative filename under the project `Audio/` folder.
    public var audioFileName: String?

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        name: String,
        startBeat: Double,
        lengthBeats: Double,
        audioFileName: String? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.name = name
        self.startBeat = startBeat
        self.lengthBeats = lengthBeats
        self.audioFileName = audioFileName
    }
}
