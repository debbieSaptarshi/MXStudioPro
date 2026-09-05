import Foundation
import MXStudioEngine

public enum StudioPreset: String, Equatable, Sendable {
    case vocal
    case importFile
    case guitar
    case bass
    case midi
    case drums
    case looper
    case sampler
    case ai
    case live
    case template
    /// Minimal capture entry (Week 35 Quick Recording) — vocal project auto-opens Record.
    case quickRecord

    public var title: String {
        switch self {
        case .vocal: return "Vocals / Audio"
        case .importFile: return "Import File"
        case .guitar: return "Guitar"
        case .bass: return "Bass"
        case .midi: return "Virtual Instrument"
        case .drums: return "Drums"
        case .looper: return "Looper"
        case .sampler: return "Sampler"
        case .ai: return "Create Music With AI"
        case .live: return "Live Performance"
        case .template: return "Template"
        case .quickRecord: return "Quick Recording"
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
    /// Arrangement loop region (GarageBand / BandLab style).
    public var loopEnabled: Bool
    public var loopStartBeat: Double
    public var loopEndBeat: Double
    /// Shared reverb aux return level (0…100). Week 81 — BandLab / Logic return.
    public var auxReverbReturn: Float
    /// Punch comp crossfade length in seconds (Week 83). Applied on new punches only.
    public var compCrossfadeSeconds: Double
    /// Master bus pitch shift in semitones (−12…+12). Week MVP transpose.
    public var masterPitchSemitones: Float

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
        collaborators: [MXCollaborator] = [],
        loopEnabled: Bool = false,
        loopStartBeat: Double = 0,
        loopEndBeat: Double = 8,
        auxReverbReturn: Float = MXAuxSend.defaultReturnPercent,
        compCrossfadeSeconds: Double = MXCompRegionSplit.crossfadeSeconds,
        masterPitchSemitones: Float = 0
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
        self.loopEnabled = loopEnabled
        self.loopStartBeat = max(0, loopStartBeat)
        self.loopEndBeat = max(self.loopStartBeat + 0.25, loopEndBeat)
        self.auxReverbReturn = MXAuxSend.clampPercent(auxReverbReturn)
        self.compCrossfadeSeconds = Self.clampCompCrossfade(compCrossfadeSeconds)
        self.masterPitchSemitones = Self.clampMasterPitch(masterPitchSemitones)
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
        loopEnabled = try c.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        loopStartBeat = max(0, try c.decodeIfPresent(Double.self, forKey: .loopStartBeat) ?? 0)
        let end = try c.decodeIfPresent(Double.self, forKey: .loopEndBeat) ?? 8
        loopEndBeat = max(loopStartBeat + 0.25, end)
        auxReverbReturn = MXAuxSend.clampPercent(
            try c.decodeIfPresent(Float.self, forKey: .auxReverbReturn) ?? MXAuxSend.defaultReturnPercent
        )
        compCrossfadeSeconds = Self.clampCompCrossfade(
            try c.decodeIfPresent(Double.self, forKey: .compCrossfadeSeconds)
                ?? MXCompRegionSplit.crossfadeSeconds
        )
        masterPitchSemitones = Self.clampMasterPitch(
            try c.decodeIfPresent(Float.self, forKey: .masterPitchSemitones) ?? 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, bpm
        case timeSignatureNumerator, timeSignatureDenominator, sampleRate
        case tracks, presetRaw, collaborators
        case loopEnabled, loopStartBeat, loopEndBeat
        case auxReverbReturn, compCrossfadeSeconds, masterPitchSemitones
    }

    /// Clamp comp crossfade dial to 0…200 ms (Week 83).
    public static func clampCompCrossfade(_ seconds: Double) -> Double {
        min(max(seconds, 0), 0.2)
    }

    public static func clampMasterPitch(_ value: Float) -> Float {
        min(max(value, -12), 12)
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
        let seed = MXGuitarPedalPreset.trackSeed
        let track = MXSessionTrack(
            name: "Guitar",
            kind: .audio,
            category: .guitar,
            isArmed: true,
            reverbMix: seed.reverbMix,
            eqMidGain: seed.eqMidGain,
            delayMix: seed.delayMix,
            delayTime: seed.delayTime,
            distortionMix: seed.distortionMix
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
            isArmed: true,
            reverbMix: 14,
            reverbSend: 20,
            synthBankPresetID: MXSynthBankPreset.trackSeed.rawValue
        )
        return MXProject(
            name: "Untitled MIDI",
            bpm: bpm,
            tracks: [track],
            preset: .midi
        )
    }

    /// Drum Machine path: armed MIDI drums track with short kit patch.
    public static func untitledDrums(bpm: Double = 120) -> MXProject {
        let track = MXSessionTrack(
            name: "Drums",
            kind: .midi,
            category: .drums,
            isArmed: true,
            reverbMix: 8,
            reverbSend: 12,
            synthBankPresetID: MXSynthBankPreset.drumKit.rawValue
        )
        return MXProject(
            name: "Untitled Drums",
            bpm: bpm,
            tracks: [track],
            preset: .drums
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
        case drums
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
    /// Bounce-path noise gate (vocal). Live/monitor path is wired separately (Week 28).
    public var noiseGateEnabled: Bool
    /// Linear amplitude threshold (0…0.2). Samples below are attenuated with a soft knee.
    public var noiseGateThreshold: Float
    /// Vocal de-esser — cuts harsh sibilance around ~6.5 kHz (live EQ + bounce).
    public var deEsserEnabled: Bool
    /// De-esser amount 0…100 (maps to ~0…−12 dB peaking cut).
    public var deEsserAmount: Float
    /// Keys / VI synth bank preset id (`MXSynthBankPreset.rawValue`). Nil for non-MIDI.
    public var synthBankPresetID: String?
    /// Muted drum kit parts (`MXDrumPart.rawValue`). Empty = all parts audible.
    /// Orthogonal to track `isMuted` and clip `takeIndex` (Week 42).
    public var mutedDrumParts: Set<String>
    /// Soloed drum kit parts (`MXDrumPart.rawValue`). Empty = no part solo.
    /// When non-empty, only soloed (and not muted) parts are audible (Week 44).
    public var soloedDrumParts: Set<String>
    /// Track volume automation breakpoints (Week 52). Empty = constant `volume`.
    public var volumeAutomation: [MXAutomationPoint]
    /// Track pan automation breakpoints (Week 82). Empty = constant `pan`.
    public var panAutomation: [MXAutomationPoint]
    /// Bounce-in-place freeze (Week 83). When true, `clips` is a single rendered bed.
    public var isFrozen: Bool
    /// Pre-freeze clip array for unfreeze restore.
    public var frozenClipsBackup: [MXClip]?
    /// Sidechain "lite" ducking to the kick (Week 63). When on, this track's
    /// playback volume dips on each kick hit (envelope duck, not a real key input).
    public var sidechainEnabled: Bool
    /// Sidechain duck depth 0…100 (0 = none, 100 = full duck at the hit).
    public var sidechainAmount: Float

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
        distortionMix: Float = 0,
        noiseGateEnabled: Bool = false,
        noiseGateThreshold: Float = 0.02,
        deEsserEnabled: Bool = false,
        deEsserAmount: Float = 50,
        synthBankPresetID: String? = nil,
        mutedDrumParts: Set<String> = [],
        soloedDrumParts: Set<String> = [],
        volumeAutomation: [MXAutomationPoint] = [],
        panAutomation: [MXAutomationPoint] = [],
        isFrozen: Bool = false,
        frozenClipsBackup: [MXClip]? = nil,
        sidechainEnabled: Bool = false,
        sidechainAmount: Float = 50
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category ?? (kind == .midi ? .keys : .vocal)
        // Note: callers should pass `.drums` explicitly for drum tracks.
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
        self.noiseGateEnabled = noiseGateEnabled
        self.noiseGateThreshold = min(max(noiseGateThreshold, 0), 0.2)
        self.deEsserEnabled = deEsserEnabled
        self.deEsserAmount = min(max(deEsserAmount, 0), 100)
        self.synthBankPresetID = synthBankPresetID
            ?? (kind == .midi ? MXSynthBankPreset.trackSeed.rawValue : nil)
        self.mutedDrumParts = mutedDrumParts
        self.soloedDrumParts = soloedDrumParts
        self.volumeAutomation = volumeAutomation.sorted { $0.beat < $1.beat }
        self.panAutomation = panAutomation.sorted { $0.beat < $1.beat }
        self.isFrozen = isFrozen
        self.frozenClipsBackup = frozenClipsBackup
        self.sidechainEnabled = sidechainEnabled
        self.sidechainAmount = min(max(sidechainAmount, 0), 100)
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
        noiseGateEnabled = try c.decodeIfPresent(Bool.self, forKey: .noiseGateEnabled) ?? false
        noiseGateThreshold = min(max(try c.decodeIfPresent(Float.self, forKey: .noiseGateThreshold) ?? 0.02, 0), 0.2)
        deEsserEnabled = try c.decodeIfPresent(Bool.self, forKey: .deEsserEnabled) ?? false
        deEsserAmount = min(max(try c.decodeIfPresent(Float.self, forKey: .deEsserAmount) ?? 50, 0), 100)
        synthBankPresetID = try c.decodeIfPresent(String.self, forKey: .synthBankPresetID)
            ?? (kind == .midi ? MXSynthBankPreset.trackSeed.rawValue : nil)
        mutedDrumParts = try c.decodeIfPresent(Set<String>.self, forKey: .mutedDrumParts) ?? []
        soloedDrumParts = try c.decodeIfPresent(Set<String>.self, forKey: .soloedDrumParts) ?? []
        volumeAutomation = (try c.decodeIfPresent([MXAutomationPoint].self, forKey: .volumeAutomation) ?? [])
            .sorted { $0.beat < $1.beat }
        panAutomation = (try c.decodeIfPresent([MXAutomationPoint].self, forKey: .panAutomation) ?? [])
            .sorted { $0.beat < $1.beat }
        isFrozen = try c.decodeIfPresent(Bool.self, forKey: .isFrozen) ?? false
        frozenClipsBackup = try c.decodeIfPresent([MXClip].self, forKey: .frozenClipsBackup)
        sidechainEnabled = try c.decodeIfPresent(Bool.self, forKey: .sidechainEnabled) ?? false
        sidechainAmount = min(max(try c.decodeIfPresent(Float.self, forKey: .sidechainAmount) ?? 50, 0), 100)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, category, isArmed, isMuted, isSolo, volume, pan, clips
        case reverbMix, reverbSend, reelsVocalEnabled, eqMidGain, delayMix, delayTime, distortionMix
        case noiseGateEnabled, noiseGateThreshold, deEsserEnabled, deEsserAmount
        case synthBankPresetID, mutedDrumParts, soloedDrumParts, volumeAutomation, panAutomation
        case isFrozen, frozenClipsBackup
        case sidechainEnabled, sidechainAmount
    }

    /// Effective pan at project beat — automation overrides static fader when non-empty (Week 82).
    public func panAtBeat(_ beat: Double) -> Float {
        guard !panAutomation.isEmpty else { return pan }
        return MXPanAutomation.value(atBeat: beat, points: panAutomation)
    }

    /// Typed mute set for drum part lanes (empty for non-drums / none muted).
    public var mutedDrumPartSet: Set<MXDrumPart> {
        MXDrumPart.mutedParts(fromRawValues: mutedDrumParts)
    }

    public var soloedDrumPartSet: Set<MXDrumPart> {
        MXDrumPart.mutedParts(fromRawValues: soloedDrumParts)
    }

    public func isDrumPartMuted(_ part: MXDrumPart) -> Bool {
        mutedDrumParts.contains(part.rawValue)
    }

    public func isDrumPartSoloed(_ part: MXDrumPart) -> Bool {
        soloedDrumParts.contains(part.rawValue)
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
    /// Linear clip gain (0.1…2). 1 = unity. Multiplies track volume (relative mode).
    public var gain: Float
    /// Fade-in length in seconds from the audible clip start.
    public var fadeInSeconds: Double
    /// Fade-out length in seconds ending at the audible clip end.
    public var fadeOutSeconds: Double
    /// Take lane index within the track (0-based). Older projects decode as 0.
    public var takeIndex: Int
    /// When false, clip is kept as an alternate take but skipped in playback/bounce.
    public var isActive: Bool
    /// Piano-roll lite notes (MIDI tracks). Empty for audio clips.
    public var midiNotes: [MXMIDINote]
    /// Clip-local volume / gain automation (beats from clip start). Empty = constant `gain`.
    public var volumeAutomation: [MXAutomationPoint]
    /// Clip-local pan offset automation (−1…1). Empty = no offset (use track pan).
    public var panAutomation: [MXAutomationPoint]
    /// Relative (× `gain`) vs absolute (lane replaces `gain` when non-empty). Week 77.
    public var gainAutomationMode: MXClipGainAutomationMode

    public init(
        id: UUID = UUID(),
        trackID: UUID,
        name: String,
        startBeat: Double,
        lengthBeats: Double,
        audioFileName: String? = nil,
        sourceOffsetSeconds: Double = 0,
        sourceDurationSeconds: Double? = nil,
        gain: Float = 1,
        fadeInSeconds: Double = 0,
        fadeOutSeconds: Double = 0,
        takeIndex: Int = 0,
        isActive: Bool = true,
        midiNotes: [MXMIDINote] = [],
        volumeAutomation: [MXAutomationPoint] = [],
        panAutomation: [MXAutomationPoint] = [],
        gainAutomationMode: MXClipGainAutomationMode = .relative
    ) {
        self.id = id
        self.trackID = trackID
        self.name = name
        self.startBeat = startBeat
        self.lengthBeats = lengthBeats
        self.audioFileName = audioFileName
        self.sourceOffsetSeconds = max(0, sourceOffsetSeconds)
        self.sourceDurationSeconds = sourceDurationSeconds.map { max(0.05, $0) }
        self.gain = min(max(gain, MXClipGainAutomation.minGain), MXClipGainAutomation.maxGain)
        let audibleHint = sourceDurationSeconds.map { max(0.05, $0) }
            ?? max(0.05, lengthBeats * 60.0 / 120.0)
        let fades = MXClipFadeGeometry.meetInMiddle(
            fadeIn: fadeInSeconds,
            fadeOut: fadeOutSeconds,
            duration: audibleHint
        )
        self.fadeInSeconds = fades.fadeIn
        self.fadeOutSeconds = fades.fadeOut
        self.takeIndex = max(0, takeIndex)
        self.isActive = isActive
        self.midiNotes = midiNotes
        self.volumeAutomation = MXVolumeAutomation.clampingBeats(volumeAutomation, lengthBeats: lengthBeats)
        self.panAutomation = MXPanAutomation.clampingBeats(panAutomation, lengthBeats: lengthBeats)
        self.gainAutomationMode = gainAutomationMode
    }

    /// Back-compat with Week 4 projects that omit trim / fade / take fields.
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
        gain = min(
            max(try c.decodeIfPresent(Float.self, forKey: .gain) ?? 1, MXClipGainAutomation.minGain),
            MXClipGainAutomation.maxGain
        )
        let rawIn = max(0, try c.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 0)
        let rawOut = max(0, try c.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 0)
        let audibleHint = sourceDurationSeconds
            ?? max(0.05, lengthBeats * 60.0 / 120.0)
        let fades = MXClipFadeGeometry.meetInMiddle(fadeIn: rawIn, fadeOut: rawOut, duration: audibleHint)
        fadeInSeconds = fades.fadeIn
        fadeOutSeconds = fades.fadeOut
        takeIndex = max(0, try c.decodeIfPresent(Int.self, forKey: .takeIndex) ?? 0)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        midiNotes = try c.decodeIfPresent([MXMIDINote].self, forKey: .midiNotes) ?? []
        volumeAutomation = MXVolumeAutomation.clampingBeats(
            try c.decodeIfPresent([MXAutomationPoint].self, forKey: .volumeAutomation) ?? [],
            lengthBeats: lengthBeats
        )
        panAutomation = MXPanAutomation.clampingBeats(
            try c.decodeIfPresent([MXAutomationPoint].self, forKey: .panAutomation) ?? [],
            lengthBeats: lengthBeats
        )
        gainAutomationMode = try c.decodeIfPresent(MXClipGainAutomationMode.self, forKey: .gainAutomationMode)
            ?? .relative
    }

    private enum CodingKeys: String, CodingKey {
        case id, trackID, name, startBeat, lengthBeats, audioFileName
        case sourceOffsetSeconds, sourceDurationSeconds
        case gain, fadeInSeconds, fadeOutSeconds
        case takeIndex, isActive, midiNotes
        case volumeAutomation, panAutomation, gainAutomationMode
    }

    /// True when this clip’s beat range overlaps `other` (exclusive ends).
    public func overlaps(with other: MXClip) -> Bool {
        let a0 = startBeat
        let a1 = startBeat + lengthBeats
        let b0 = other.startBeat
        let b1 = other.startBeat + other.lengthBeats
        return a0 < b1 && b0 < a1
    }

    /// Equal-power envelope at `t` seconds into the audible clip (`duration` = audible length).
    /// Uses `MXCrossfade.equalPowerIn` / `equalPowerOut` so overlapping seams keep constant power.
    /// Fades are meet-in-middle clamped so they never exceed `duration` combined.
    public func fadeEnvelope(atSeconds t: Double, durationSeconds duration: Double) -> Float {
        guard duration > 1e-6 else { return 1 }
        let fades = MXClipFadeGeometry.meetInMiddle(
            fadeIn: fadeInSeconds,
            fadeOut: fadeOutSeconds,
            duration: duration
        )
        let fadeIn = fades.fadeIn
        let fadeOut = fades.fadeOut
        var env: Float = 1
        if fadeIn > 1e-6, t < fadeIn {
            env = MXCrossfade.equalPowerIn(t / fadeIn)
        }
        if fadeOut > 1e-6 {
            let outStart = duration - fadeOut
            if t >= outStart {
                env = min(env, MXCrossfade.equalPowerOut((t - outStart) / fadeOut))
            }
        }
        return env
    }

    /// Clip-local beat for a project playhead (0 when before clip).
    public func localBeat(atProjectBeat projectBeat: Double) -> Double {
        max(0, projectBeat - startBeat)
    }

    /// Volume automation gain at a project beat (unity when empty / outside).
    public func volumeAutomationGain(atProjectBeat projectBeat: Double) -> Float {
        guard !volumeAutomation.isEmpty else { return MXVolumeAutomation.unity }
        let local = localBeat(atProjectBeat: projectBeat)
        guard local <= lengthBeats + 1e-6 else { return MXVolumeAutomation.unity }
        return MXVolumeAutomation.value(atBeat: local, points: volumeAutomation)
    }

    /// Clip contribution after applying relative/absolute gain automation mode (Week 77).
    public func effectiveGain(atProjectBeat projectBeat: Double) -> Float {
        MXClipGainAutomation.effectiveGain(
            clipGain: gain,
            mode: gainAutomationMode,
            automationValue: volumeAutomationGain(atProjectBeat: projectBeat),
            hasAutomation: !volumeAutomation.isEmpty
        )
    }

    /// Pan offset at a project beat (0 when empty).
    public func panAutomationOffset(atProjectBeat projectBeat: Double) -> Float {
        guard !panAutomation.isEmpty else { return MXPanAutomation.center }
        let local = localBeat(atProjectBeat: projectBeat)
        guard local <= lengthBeats + 1e-6 else { return MXPanAutomation.center }
        return MXPanAutomation.value(atBeat: local, points: panAutomation)
    }
}
