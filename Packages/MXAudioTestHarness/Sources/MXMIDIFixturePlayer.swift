import Foundation
import MXAudioCore
import MXAudioDSP

/// A note in a MIDI fixture, positioned in musical time so the same fixture
/// works at any tempo.
public struct MXMIDIFixtureNote: Codable, Equatable, Sendable {
    public var beat: Double
    public var note: UInt8
    public var velocity: UInt8
    public var durationBeats: Double
    public var channel: UInt8

    public init(beat: Double,
                note: UInt8,
                velocity: UInt8 = 100,
                durationBeats: Double = 1,
                channel: UInt8 = 0) {
        self.beat = beat
        self.note = note
        self.velocity = velocity
        self.durationBeats = durationBeats
        self.channel = channel
    }
}

public struct MXMIDIFixture: Codable, Equatable, Sendable {
    public var name: String
    public var bpm: Double
    public var notes: [MXMIDIFixtureNote]

    public init(name: String, bpm: Double = 145, notes: [MXMIDIFixtureNote]) {
        self.name = name
        self.bpm = bpm
        self.notes = notes
    }

    public static func load(from url: URL) throws -> MXMIDIFixture {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MXMIDIFixture.self, from: data)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    // MARK: - Common patterns

    public static func singleNote(_ note: UInt8 = 60,
                                  velocity: UInt8 = 100,
                                  durationBeats: Double = 1,
                                  bpm: Double = 145) -> MXMIDIFixture {
        MXMIDIFixture(name: "single-note", bpm: bpm,
                      notes: [MXMIDIFixtureNote(beat: 0, note: note,
                                                velocity: velocity,
                                                durationBeats: durationBeats)])
    }

    /// Sixteenth-note hi-hats for a whole bar, which is what D-05 quantises.
    public static func sixteenthNotes(_ note: UInt8,
                                      bars: Int = 1,
                                      bpm: Double = 145,
                                      beatsPerBar: Int = 4) -> MXMIDIFixture {
        var notes: [MXMIDIFixtureNote] = []
        let steps = bars * beatsPerBar * 4
        for step in 0..<steps {
            notes.append(MXMIDIFixtureNote(beat: Double(step) * 0.25,
                                           note: note,
                                           velocity: 100,
                                           durationBeats: 0.125))
        }
        return MXMIDIFixture(name: "sixteenths", bpm: bpm, notes: notes)
    }

    public static func chord(_ notes: [UInt8],
                             velocity: UInt8 = 100,
                             durationBeats: Double = 2,
                             bpm: Double = 145) -> MXMIDIFixture {
        MXMIDIFixture(name: "chord", bpm: bpm,
                      notes: notes.map {
                          MXMIDIFixtureNote(beat: 0, note: $0,
                                            velocity: velocity,
                                            durationBeats: durationBeats)
                      })
    }
}

/// Turns a fixture into scheduled actions the offline renderer can execute at
/// exact frame positions.
public enum MXMIDIFixturePlayer {

    public static func actions(for fixture: MXMIDIFixture,
                               on instrument: MXInstrument,
                               tempoMap: MXTempoMap? = nil) -> [MXScheduledAction] {
        let map = tempoMap ?? MXTempoMap(bpm: fixture.bpm)
        var actions: [MXScheduledAction] = []

        for note in fixture.notes {
            let onSeconds = map.seconds(forBeat: note.beat)
            let offSeconds = map.seconds(forBeat: note.beat + note.durationBeats)

            actions.append(MXScheduledAction(at: onSeconds) {
                instrument.noteOn(note.note, velocity: note.velocity, channel: note.channel)
            })
            actions.append(MXScheduledAction(at: offSeconds) {
                instrument.noteOff(note.note, channel: note.channel)
            })
        }
        return actions.sorted { $0.atSeconds < $1.atSeconds }
    }

    /// Expected onset positions in samples, for comparing against detected
    /// onsets.
    public static func expectedOnsetSamples(for fixture: MXMIDIFixture,
                                            sampleRate: Double,
                                            tempoMap: MXTempoMap? = nil) -> [Int] {
        let map = tempoMap ?? MXTempoMap(bpm: fixture.bpm)
        return fixture.notes
            .map { Int((map.seconds(forBeat: $0.beat) * sampleRate).rounded()) }
            .sorted()
    }
}
