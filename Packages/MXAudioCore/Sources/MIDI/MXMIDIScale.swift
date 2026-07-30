import Foundation

/// Musical scale lock for piano-roll pitch snap (Week 62 — Cubasis / Logic lite).
///
/// Pitch-class relative to `rootPitchClass` (0 = C … 11 = B). Major and natural
/// minor only — enough for “stay in key while dragging.”
public enum MXMIDIScaleMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case major
    case naturalMinor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .major: return "Major"
        case .naturalMinor: return "Minor"
        }
    }

    /// Semitone offsets from the root (0…11) that belong to the scale.
    public var intervals: [UInt8] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }
}

/// Root + mode defining which MIDI pitches are “in key.”
public struct MXMIDIScale: Codable, Equatable, Sendable {
    /// Pitch class of the tonic (0 = C … 11 = B).
    public var rootPitchClass: UInt8
    public var mode: MXMIDIScaleMode

    public init(rootPitchClass: UInt8 = 0, mode: MXMIDIScaleMode = .major) {
        self.rootPitchClass = rootPitchClass % 12
        self.mode = mode
    }

    public static let cMajor = MXMIDIScale(rootPitchClass: 0, mode: .major)

    /// Chromatic root names for UI pickers.
    public static let rootNames: [String] = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
    ]

    public var rootDisplayName: String {
        Self.rootNames[Int(rootPitchClass % 12)]
    }

    public var displayName: String {
        "\(rootDisplayName) \(mode.displayName)"
    }

    /// Pitch classes (0…11) in this scale.
    public var pitchClasses: Set<UInt8> {
        Set(mode.intervals.map { (rootPitchClass + $0) % 12 })
    }

    public func contains(_ pitch: UInt8) -> Bool {
        pitchClasses.contains(pitch % 12)
    }

    /// Nearest in-scale pitch (ties prefer lower). Clamped to 0…127.
    public func snapPitch(_ pitch: UInt8) -> UInt8 {
        let clamped = MXMIDINoteEdit.clampPitch(pitch)
        if contains(clamped) { return clamped }
        let midi = Int(clamped)
        for delta in 1...6 {
            let down = midi - delta
            if down >= 0, contains(UInt8(down)) { return UInt8(down) }
            let up = midi + delta
            if up <= 127, contains(UInt8(up)) { return UInt8(up) }
        }
        return clamped
    }
}
