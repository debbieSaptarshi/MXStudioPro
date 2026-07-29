import Foundation

public struct MXTimeSignature: Equatable, Codable, Sendable {
    public var numerator: Int
    public var denominator: Int

    public init(_ numerator: Int = 4, _ denominator: Int = 4) {
        self.numerator = max(1, numerator)
        self.denominator = max(1, denominator)
    }

    /// Length of one bar measured in quarter notes, which is the unit the whole
    /// tempo map works in.
    public var beatsPerBar: Double {
        Double(numerator) * (4.0 / Double(denominator))
    }

    public static let fourFour = MXTimeSignature(4, 4)
}

public struct MXTempoEvent: Equatable, Codable, Sendable {
    /// Position in quarter notes from the project start.
    public var beat: Double
    public var bpm: Double

    public init(beat: Double, bpm: Double) {
        self.beat = max(0, beat)
        self.bpm = min(max(bpm, 20), 400)
    }
}

/// Bar and beat are 1-based to match the `001 Bar / 1 Beat` readout in the
/// Figma transport bar.
public struct MXMusicalPosition: Equatable, Codable, Sendable, CustomStringConvertible {
    public static let ticksPerBeat = 960

    public var bar: Int
    public var beat: Int
    public var tick: Int

    public init(bar: Int, beat: Int, tick: Int = 0) {
        self.bar = bar
        self.beat = beat
        self.tick = tick
    }

    public var description: String {
        String(format: "%03d Bar / %d Beat", bar, beat)
    }
}

/// Converts between musical time, seconds and samples.
///
/// Tempo is piecewise constant: a tempo event applies from its beat until the
/// next one. Because every conversion is derived from this map rather than
/// stored per view, a tempo edit at bar 4 leaves everything before bar 4
/// untouched and remaps everything after it (plan scenario T-05).
public final class MXTempoMap: @unchecked Sendable {

    private var tempoEvents: [MXTempoEvent]
    private var signatureEvents: [(bar: Int, signature: MXTimeSignature)]
    private let lock = NSLock()

    public init(bpm: Double = 145, timeSignature: MXTimeSignature = .fourFour) {
        tempoEvents = [MXTempoEvent(beat: 0, bpm: bpm)]
        signatureEvents = [(bar: 1, signature: timeSignature)]
    }

    // MARK: - Editing

    public var initialTempo: Double {
        lock.lock(); defer { lock.unlock() }
        return tempoEvents[0].bpm
    }

    public func setTempo(_ bpm: Double) {
        lock.lock()
        tempoEvents = [MXTempoEvent(beat: 0, bpm: min(max(bpm, 20), 400))]
        lock.unlock()
    }

    /// Inserts or replaces a tempo change. Everything before `beat` keeps its
    /// existing timing.
    public func setTempo(_ bpm: Double, atBeat beat: Double) {
        lock.lock()
        defer { lock.unlock() }
        let event = MXTempoEvent(beat: beat, bpm: bpm)
        if let index = tempoEvents.firstIndex(where: { abs($0.beat - event.beat) < 1e-9 }) {
            tempoEvents[index] = event
        } else {
            tempoEvents.append(event)
            tempoEvents.sort { $0.beat < $1.beat }
        }
    }

    public func removeTempoChange(atBeat beat: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard beat > 0 else { return }
        tempoEvents.removeAll { abs($0.beat - beat) < 1e-9 }
    }

    public var tempoChanges: [MXTempoEvent] {
        lock.lock(); defer { lock.unlock() }
        return tempoEvents
    }

    public func setTimeSignature(_ signature: MXTimeSignature, atBar bar: Int = 1) {
        lock.lock()
        defer { lock.unlock() }
        let clamped = max(1, bar)
        if let index = signatureEvents.firstIndex(where: { $0.bar == clamped }) {
            signatureEvents[index].signature = signature
        } else {
            signatureEvents.append((bar: clamped, signature: signature))
            signatureEvents.sort { $0.bar < $1.bar }
        }
    }

    public func timeSignature(atBar bar: Int) -> MXTimeSignature {
        lock.lock(); defer { lock.unlock() }
        var result = signatureEvents[0].signature
        for event in signatureEvents where event.bar <= bar {
            result = event.signature
        }
        return result
    }

    // MARK: - Beat <-> seconds

    public func tempo(atBeat beat: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        return tempoUnlocked(atBeat: beat)
    }

    private func tempoUnlocked(atBeat beat: Double) -> Double {
        var bpm = tempoEvents[0].bpm
        for event in tempoEvents where event.beat <= beat + 1e-9 {
            bpm = event.bpm
        }
        return bpm
    }

    public func seconds(forBeat beat: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        return secondsUnlocked(forBeat: beat)
    }

    private func secondsUnlocked(forBeat beat: Double) -> Double {
        guard beat > 0 else { return 0 }
        var seconds = 0.0
        var cursor = 0.0
        var bpm = tempoEvents[0].bpm

        for event in tempoEvents.dropFirst() {
            guard event.beat < beat else { break }
            seconds += (event.beat - cursor) * 60.0 / bpm
            cursor = event.beat
            bpm = event.bpm
        }
        seconds += (beat - cursor) * 60.0 / bpm
        return seconds
    }

    public func beat(forSeconds seconds: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard seconds > 0 else { return 0 }

        var remaining = seconds
        var cursorBeat = 0.0
        var bpm = tempoEvents[0].bpm

        for event in tempoEvents.dropFirst() {
            let segmentSeconds = (event.beat - cursorBeat) * 60.0 / bpm
            if remaining < segmentSeconds { break }
            remaining -= segmentSeconds
            cursorBeat = event.beat
            bpm = event.bpm
        }
        return cursorBeat + remaining * bpm / 60.0
    }

    // MARK: - Beat <-> samples

    public func samplesPerBeat(atBeat beat: Double = 0, sampleRate: Double) -> Double {
        sampleRate * 60.0 / tempo(atBeat: beat)
    }

    public func sample(forBeat beat: Double, sampleRate: Double) -> Int64 {
        Int64((seconds(forBeat: beat) * sampleRate).rounded())
    }

    public func beat(forSample sample: Int64, sampleRate: Double) -> Double {
        beat(forSeconds: Double(sample) / sampleRate)
    }

    // MARK: - Beat <-> bar/beat/tick

    /// Bar boundaries respect time-signature changes, so this walks bars rather
    /// than assuming a constant bar length.
    public func position(forBeat beat: Double) -> MXMusicalPosition {
        let clamped = max(0, beat)
        var bar = 1
        var accumulated = 0.0

        while true {
            let barLength = timeSignature(atBar: bar).beatsPerBar
            if accumulated + barLength > clamped + 1e-9 { break }
            accumulated += barLength
            bar += 1
            if bar > 1_000_000 { break }
        }

        let intoBar = clamped - accumulated
        let beatIndex = Int(floor(intoBar + 1e-9))
        let fraction = intoBar - Double(beatIndex)
        let tick = Int((fraction * Double(MXMusicalPosition.ticksPerBeat)).rounded())

        return MXMusicalPosition(bar: bar, beat: beatIndex + 1, tick: tick)
    }

    public func beat(forPosition position: MXMusicalPosition) -> Double {
        var accumulated = 0.0
        var bar = 1
        while bar < position.bar {
            accumulated += timeSignature(atBar: bar).beatsPerBar
            bar += 1
        }
        accumulated += Double(position.beat - 1)
        accumulated += Double(position.tick) / Double(MXMusicalPosition.ticksPerBeat)
        return accumulated
    }

    public func position(forSample sample: Int64, sampleRate: Double) -> MXMusicalPosition {
        position(forBeat: beat(forSample: sample, sampleRate: sampleRate))
    }

    public func sample(forBar bar: Int, sampleRate: Double) -> Int64 {
        sample(forBeat: beat(forPosition: MXMusicalPosition(bar: bar, beat: 1)),
               sampleRate: sampleRate)
    }

    /// Beat positions of every beat line in `range`, used by the metronome and
    /// by grid rendering.
    public func beatGrid(fromBeat start: Double, toBeat end: Double) -> [Double] {
        guard end > start else { return [] }
        var result: [Double] = []
        var beat = floor(start)
        if beat < start { beat += 1 }
        while beat <= end {
            result.append(beat)
            beat += 1
        }
        return result
    }
}
