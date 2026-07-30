import XCTest
@testable import MXAudioCore
import MXAudioDSP

final class MXMIDIClipRendererTests: XCTestCase {
    func testWriteWAVProducesRIFFFile() throws {
        let notes = [
            MXMIDINote(note: 60, velocity: 100, startBeat: 0, lengthBeats: 1),
            MXMIDINote(note: 64, velocity: 90, startBeat: 1, lengthBeats: 1),
            MXMIDINote(note: 67, velocity: 80, startBeat: 2, lengthBeats: 2),
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mxmidi_test_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try MXMIDIClipRenderer.writeWAV(
            notes: notes,
            to: url,
            preset: MXSynthBankPreset.softKeys.preset,
            bpm: 120,
            sampleRate: 48_000,
            tailSeconds: 0.25
        )

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }

    func testEmptyNotesThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty.wav")
        XCTAssertThrowsError(
            try MXMIDIClipRenderer.writeWAV(notes: [], to: url)
        )
    }

    func testSynthBankPresetsAreDistinct() {
        let names = Set(MXSynthBankPreset.allCases.map(\.preset.name))
        XCTAssertEqual(names.count, MXSynthBankPreset.allCases.count)
        XCTAssertEqual(MXSynthBankPreset.trackSeed, .softKeys)
    }
}
