import Foundation

/// Fixed drum part lanes for arrange (BandLab / GarageBand kit columns).
///
/// Maps GM-ish pad notes onto Kick / Snare / Hats / Toms / Perc / Ride so a
/// single performance clip can be shown as per-part timeline rows without
/// splitting the WAV bed. Orthogonal to `MXClip.takeIndex` (playlist comps).
public enum MXDrumPart: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case kick
    case snare
    case hats
    case toms
    case perc
    case ride

    public var id: String { rawValue }

    /// Short header label (Figma Drum Midi part columns).
    public var shortLabel: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hats: return "Hats"
        case .toms: return "Toms"
        case .perc: return "Perc"
        case .ride: return "Ride"
        }
    }

    /// Sort order matches BandLab-style kit columns (kick → cymbals).
    public static func < (lhs: MXDrumPart, rhs: MXDrumPart) -> Bool {
        (lhs.laneIndex, lhs.rawValue) < (rhs.laneIndex, rhs.rawValue)
    }

    public var laneIndex: Int {
        switch self {
        case .kick: return 0
        case .snare: return 1
        case .hats: return 2
        case .toms: return 3
        case .perc: return 4
        case .ride: return 5
        }
    }

    /// Primary + aliased MIDI notes for this part (DrumPadView + common GM / fixture).
    public var midiNotes: Set<UInt8> {
        switch self {
        case .kick:
            return [36]
        case .snare:
            // 38 snare, 39 clap, 40 snare mid (fixture)
            return [38, 39, 40]
        case .hats:
            // 42 closed, 44 foot, 46 open
            return [42, 44, 46]
        case .toms:
            // 41 low, 45 mid, 48 high
            return [41, 45, 48]
        case .perc:
            // 37 side stick / perc
            return [37]
        case .ride:
            // 49 crash, 51 ride, 55/57 cymbals
            return [49, 51, 55, 57]
        }
    }

    /// Resolve a MIDI note to a drum part lane, if it belongs to the kit map.
    public static func part(forNote note: UInt8) -> MXDrumPart? {
        for part in MXDrumPart.allCases where part.midiNotes.contains(note) {
            return part
        }
        return nil
    }

    /// Notes that belong to `part` (clip-local or absolute — filter only).
    public static func filter(_ notes: [MXMIDINote], part: MXDrumPart) -> [MXMIDINote] {
        notes.filter { part.midiNotes.contains($0.note) }
    }

    /// Notes that belong to any drum part (excludes unmapped pitches).
    public static func filterDrumKitNotes(_ notes: [MXMIDINote]) -> [MXMIDINote] {
        notes.filter { part(forNote: $0.note) != nil }
    }

    /// Drop notes whose mapped kit part is muted. Unmapped pitches are kept
    /// (they are not part of the Kick→Ride mute columns).
    public static func excludingMuted(
        _ notes: [MXMIDINote],
        muted: Set<MXDrumPart>
    ) -> [MXMIDINote] {
        guard !muted.isEmpty else { return notes }
        return notes.filter { note in
            guard let part = part(forNote: note.note) else { return true }
            return !muted.contains(part)
        }
    }

    /// Decode persisted rawValues into a typed mute set (unknown strings ignored).
    public static func mutedParts(fromRawValues values: Set<String>) -> Set<MXDrumPart> {
        Set(values.compactMap { MXDrumPart(rawValue: $0) })
    }

    /// True when `notes` includes at least one mapped drum hit.
    public static func hasDrumParts(_ notes: [MXMIDINote]) -> Bool {
        notes.contains { part(forNote: $0.note) != nil }
    }

    // MARK: - Shared pad grid (DrumPadView)

    /// One pad in the 2×4 Drum Studio grid.
    public struct Pad: Sendable, Equatable, Identifiable {
        public let note: UInt8
        public let label: String
        public let part: MXDrumPart

        public var id: UInt8 { note }

        public init(note: UInt8, label: String, part: MXDrumPart) {
            self.note = note
            self.label = label
            self.part = part
        }
    }

    /// Week 34 pad layout — row-major 2×4 matching `DrumPadView`.
    public static let padGrid: [[Pad]] = [
        [
            Pad(note: 36, label: "Kick", part: .kick),
            Pad(note: 38, label: "Snare", part: .snare),
            Pad(note: 39, label: "Clap", part: .snare),
            Pad(note: 42, label: "Closed HH", part: .hats),
        ],
        [
            Pad(note: 46, label: "Open HH", part: .hats),
            Pad(note: 45, label: "Tom", part: .toms),
            Pad(note: 37, label: "Perc", part: .perc),
            Pad(note: 51, label: "Ride", part: .ride),
        ],
    ]

    public static var allPads: [Pad] { padGrid.flatMap { $0 } }
}

extension Array where Element == MXMIDINote {
    public func filtered(to part: MXDrumPart) -> [MXMIDINote] {
        MXDrumPart.filter(self, part: part)
    }

    public func excludingMuted(_ muted: Set<MXDrumPart>) -> [MXMIDINote] {
        MXDrumPart.excludingMuted(self, muted: muted)
    }
}
