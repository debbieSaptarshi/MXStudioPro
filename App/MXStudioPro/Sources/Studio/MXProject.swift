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

/// Collab role — display-only for Week 22 MVP (no permission enforcement yet).
public enum MXCollaboratorRole: String, Codable, Sendable, CaseIterable {
    case viewer
    case editor

    public var title: String {
        switch self {
        case .viewer: return "Viewer"
        case .editor: return "Editor"
        }
    }
}

public struct MXCollaborator: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var email: String
    public var role: MXCollaboratorRole
    public var invitedAt: Date

    public init(
        id: UUID = UUID(),
        email: String,
        role: MXCollaboratorRole = .viewer,
        invitedAt: Date = .now
    ) {
        self.id = id
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.role = role
        self.invitedAt = invitedAt
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
    /// Local collab invites (Week 22) — no sync backend yet.
    public var collaborators: [MXCollaborator]

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
        preset: StudioPreset = .vocal,
        collaborators: [MXCollaborator] = []
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
        self.collaborators = collaborators
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        bpm = try c.decode(Double.self, forKey: .bpm)
        timeSignatureNumerator = try c.decode(Int.self, forKey: .timeSignatureNumerator)
        timeSignatureDenominator = try c.decode(Int.self, forKey: .timeSignatureDenominator)
        sampleRate = try c.decode(Double.self, forKey: .sampleRate)
        tracks = try c.decode([MXSessionTrack].self, forKey: .tracks)
        presetRaw = try c.decode(String.self, forKey: .presetRaw)
        collaborators = try c.decodeIfPresent([MXCollaborator].self, forKey: .collaborators) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, bpm
        case timeSignatureNumerator, timeSignatureDenominator, sampleRate
        case tracks, presetRaw, collaborators
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
            category: .vocal,
            isArmed: true
        )
        return MXProject(
            name: "Untitled Vocals",
            bpm: bpm,
            tracks: [track],
            preset: .vocal
        )
    }

    /// Guitar path: armed audio track with a light pedalboard seed (Dist / Delay / Rev).
    public static func untitledGuitar(bpm: Double = 120) -> MXProject {
        let track = MXSessionTrack(
            name: "Guitar",
            kind: .audio,
            category: .guitar,
            isArmed: true,
            reverbMix: 18,
            eqMidGain: 1.5,
            delayMix: 20,
            delayTime: 0.32,
            distortionMix: 35
        )
        return MXProject(
            name: "Untitled Guitar",
            bpm: bpm,
            tracks: [track],
            preset: .guitar
        )
    }

    /// MIDI / Virtual Instrument path: one armed MIDI piano track.
    public static func untitledMIDI(bpm: Double = 120) -> MXProject {
        let track = MXSessionTrack(
            name: "Piano",
            kind: .midi,
            category: .keys,
            isArmed: true
        )
        return MXProject(
            name: "Untitled MIDI",
            bpm: bpm,
            tracks: [track],
            preset: .midi
        )
    }
}

public struct MXSessionTrack: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case audio
        case midi
        case bus
    }

    public enum Category: String, Codable, Sendable {
        case vocal
        case guitar
        case keys
        case imported
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var category: Category
    public var isArmed: Bool
    public var isMuted: Bool
    public var isSolo: Bool
    public var volume: Float
    public var pan: Float
    public var clips: [MXClip]
    /// Wet/dry for track reverb insert (0…100). 0 = bypassed.
    public var reverbMix: Float
    /// Aux reverb send level (0…100). 0 = dry.
    public var reverbSend: Float
    /// One-tap Reels Vocal chain (HPF + light comp + short reverb).
    public var reelsVocalEnabled: Bool
    /// Parametric mid gain in dB (−12…12).
    public var eqMidGain: Float
    /// Delay wet mix 0…100.
    public var delayMix: Float
    /// Delay time in seconds (0.01…1).
    public var delayTime: Float
    /// Distortion wet mix 0…100.
    public var distortionMix: Float

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .audio,
        category: Category? = nil,
        isArmed: Bool = false,
        isMuted: Bool = false,
        isSolo: Bool = false,
        volume: Float = 0.8,
        pan: Float = 0,
        clips: [MXClip] = [],
        reverbMix: Float = 0,
        reverbSend: Float = 0,
        reelsVocalEnabled: Bool = false,
        eqMidGain: Float = 0,
        delayMix: Float = 0,
        delayTime: Float = 0.25,
        distortionMix: Float = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category ?? (kind == .midi ? .keys : .vocal)
        self.isArmed = isArmed
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.volume = volume
        self.pan = pan
        self.clips = clips
        self.reverbMix = min(max(reverbMix, 0), 100)
        self.reverbSend = min(max(reverbSend, 0), 100)
        self.reelsVocalEnabled = reelsVocalEnabled
        self.eqMidGain = min(max(eqMidGain, -12), 12)
        self.delayMix = min(max(delayMix, 0), 100)
        self.delayTime = min(max(delayTime, 0.01), 1)
        self.distortionMix = min(max(distortionMix, 0), 100)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        category = try c.decodeIfPresent(Category.self, forKey: .category)
            ?? (kind == .midi ? .keys : .vocal)
        isArmed = try c.decode(Bool.self, forKey: .isArmed)
        isMuted = try c.decode(Bool.self, forKey: .isMuted)
        isSolo = try c.decode(Bool.self, forKey: .isSolo)
        volume = try c.decode(Float.self, forKey: .volume)
        pan = try c.decode(Float.self, forKey: .pan)
        clips = try c.decode([MXClip].self, forKey: .clips)
        reverbMix = min(max(try c.decodeIfPresent(Float.self, forKey: .reverbMix) ?? 0, 0), 100)
        reverbSend = min(max(try c.decodeIfPresent(Float.self, forKey: .reverbSend) ?? 0, 0), 100)
        reelsVocalEnabled = try c.decodeIfPresent(Bool.self, forKey: .reelsVocalEnabled) ?? false
        eqMidGain = min(max(try c.decodeIfPresent(Float.self, forKey: .eqMidGain) ?? 0, -12), 12)
        delayMix = min(max(try c.decodeIfPresent(Float.self, forKey: .delayMix) ?? 0, 0), 100)
        delayTime = min(max(try c.decodeIfPresent(Float.self, forKey: .delayTime) ?? 0.25, 0.01), 1)
        distortionMix = min(max(try c.decodeIfPresent(Float.self, forKey: .distortionMix) ?? 0, 0), 100)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, category, isArmed, isMuted, isSolo, volume, pan, clips
        case reverbMix, reverbSend, reelsVocalEnabled, eqMidGain, delayMix, delayTime, distortionMix
    }
}

public struct MXClip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var name: String
    /// Start position in quarter-note beats from project start.
    public var startBeat: Double
    /// Audible length on the timeline (after trim).
    public var lengthBeats: Double
    /// Relative filename under the project `Audio/` folder.
    public var audioFileName: String?
    /// Seconds into the audio file where playback begins (left trim).
    public var sourceOffsetSeconds: Double
    /// Seconds of audio used from the file (right trim). `nil` = remainder of file.
    public var sourceDurationSeconds: Double?

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        name: String,
        startBeat: Double,
        lengthBeats: Double,
        audioFileName: String? = nil,
        sourceOffsetSeconds: Double = 0,
        sourceDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.name = name
        self.startBeat = startBeat
        self.lengthBeats = lengthBeats
        self.audioFileName = audioFileName
        self.sourceOffsetSeconds = max(0, sourceOffsetSeconds)
        self.sourceDurationSeconds = sourceDurationSeconds.map { max(0.05, $0) }
    }

    /// Back-compat with Week 4 projects that omit trim fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trackID = try c.decode(UUID.self, forKey: .trackID)
        name = try c.decode(String.self, forKey: .name)
        startBeat = try c.decode(Double.self, forKey: .startBeat)
        lengthBeats = try c.decode(Double.self, forKey: .lengthBeats)
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        sourceOffsetSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .sourceOffsetSeconds) ?? 0)
        sourceDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds).map { max(0.05, $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, trackID, name, startBeat, lengthBeats, audioFileName
        case sourceOffsetSeconds, sourceDurationSeconds
    }
}
