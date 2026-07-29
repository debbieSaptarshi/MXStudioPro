import AVFoundation
import XCTest
@testable import MXAudioDSP
@testable import MXInstruments
import MXAudioTestHarness

/// Plan section 11.6, SFZ-01 … SFZ-04.
///
/// These are written against `MXSFZEngine` rather than the native
/// implementation, so they double as the acceptance gate if vendored sfizz is
/// swapped in behind the same protocol.
final class MXSFZBackendTests: XCTestCase {

    private var engine: MXHeadlessEngine!
    private var fixtures: URL!

    override func setUpWithError() throws {
        engine = try MXHeadlessEngine()
        fixtures = engine.workingDirectory
    }

    override func tearDown() {
        engine?.tearDown()
        engine = nil
        super.tearDown()
    }

    // MARK: - SFZ-01

    func testVelocityLayersSelectDifferentSamples() throws {
        let sfz = try MXFixtureFactory.velocityLayeredSFZ(in: fixtures)
        let backend = MXSFZBackend(displayName: "Velocity", sampleRate: engine.sampleRate)
        try backend.engine.loadSFZ(url: sfz)

        engine.addTrack(instrument: backend)
        try engine.start()

        let soft = try engine.renderNote(60, velocity: 30, on: backend,
                                         holdSeconds: 0.5, totalSeconds: 0.8)
        let hard = try engine.renderNote(60, velocity: 120, on: backend,
                                         holdSeconds: 0.5, totalSeconds: 0.8)

        XCTAssertFalse(MXAudioAnalysis.isSilent(soft.mono), "soft layer produced no audio")
        XCTAssertFalse(MXAudioAnalysis.isSilent(hard.mono), "hard layer produced no audio")

        // Different samples, not merely a gain difference: the noise-based hard
        // layer is far brighter than the tonal soft layer.
        let softCentroid = MXAudioAnalysis.spectralCentroid(soft.mono, sampleRate: engine.sampleRate)
        let hardCentroid = MXAudioAnalysis.spectralCentroid(hard.mono, sampleRate: engine.sampleRate)
        XCTAssertGreaterThan(hardCentroid, softCentroid * 2,
                             "velocity did not select a different sample "
                             + "(soft centroid \(softCentroid) Hz, hard \(hardCentroid) Hz)")

        XCTAssertNotEqual(MXAudioAnalysis.fingerprint(soft.mono),
                          MXAudioAnalysis.fingerprint(hard.mono))
    }

    // MARK: - SFZ-02

    func testRoundRobinCyclesThroughFourDistinctSamples() throws {
        let sfz = try MXFixtureFactory.roundRobinSFZ(in: fixtures, variations: 4)
        let backend = MXSFZBackend(displayName: "RoundRobin", sampleRate: engine.sampleRate)
        try backend.engine.loadSFZ(url: sfz)

        engine.addTrack(instrument: backend)
        try engine.start()

        var fingerprints: [UInt64] = []
        for _ in 0..<4 {
            let result = try engine.renderNote(60, velocity: 100, on: backend,
                                               holdSeconds: 0.2, totalSeconds: 0.35)
            XCTAssertFalse(MXAudioAnalysis.isSilent(result.mono), "round-robin hit was silent")
            fingerprints.append(MXAudioAnalysis.fingerprint(result.mono))
        }

        XCTAssertEqual(Set(fingerprints).count, 4,
                       "expected 4 distinct round-robin samples, got \(Set(fingerprints).count)")

        // The fifth hit must wrap back to the first variation.
        let fifth = try engine.renderNote(60, velocity: 100, on: backend,
                                          holdSeconds: 0.2, totalSeconds: 0.35)
        XCTAssertEqual(MXAudioAnalysis.fingerprint(fifth.mono), fingerprints[0],
                       "round robin did not wrap after seq_length hits")
    }

    // MARK: - SFZ-03

    func testLargeKitStreamsWithinMemoryBudget() throws {
        // Budget deliberately smaller than the kit so streaming has to engage.
        let budget = 4 * 1024 * 1024
        let store = MXSampleStore(budgetBytes: budget,
                                  preloadFrames: 4_096,
                                  fullLoadThresholdBytes: 64 * 1024)
        let sfz = try MXFixtureFactory.drumKitSFZ(in: fixtures)

        let backend = MXSFZBackend(displayName: "Kit",
                                   sampleRate: engine.sampleRate,
                                   store: store)
        try backend.engine.loadSFZ(url: sfz)

        engine.addTrack(instrument: backend)
        try engine.start()

        XCTAssertEqual(backend.regionCount, MXDrumLaneFixture.allLanes.count)

        for lane in MXDrumLaneFixture.allLanes {
            let result = try engine.renderNote(lane.midiNote, velocity: 110, on: backend,
                                               holdSeconds: 0.05, totalSeconds: 0.25)
            XCTAssertFalse(MXAudioAnalysis.isSilent(result.mono),
                           "lane \(lane.id) produced no audio")
        }

        let stats = store.statistics()
        XCTAssertLessThanOrEqual(stats.residentBytes, budget,
                                 "sample store exceeded its memory budget "
                                 + "(\(stats.residentBytes) > \(budget))")
    }

    // MARK: - SFZ-04

    func testMalformedSFZThrowsTypedErrorWithoutCrashing() throws {
        let bad = fixtures.appendingPathComponent("broken.sfz")
        try "<region> lokey=90 hikey=20 sample=missing.wav".write(to: bad,
                                                                  atomically: true,
                                                                  encoding: .utf8)
        let backend = MXSFZBackend(displayName: "Broken", sampleRate: engine.sampleRate)

        XCTAssertThrowsError(try backend.engine.loadSFZ(url: bad)) { error in
            guard case MXAudioError.sfzParseFailed = error else {
                return XCTFail("expected .sfzParseFailed, got \(error)")
            }
        }

        // The engine must survive and still be usable.
        engine.addTrack(instrument: backend)
        try engine.start()
        XCTAssertTrue(engine.graph.isRunning)
    }

    func testMissingSFZFileThrowsResourceNotFound() throws {
        let backend = MXSFZBackend(displayName: "Missing", sampleRate: engine.sampleRate)
        let missing = fixtures.appendingPathComponent("nope.sfz")
        XCTAssertThrowsError(try backend.engine.loadSFZ(url: missing)) { error in
            guard case MXAudioError.resourceNotFound = error else {
                return XCTFail("expected .resourceNotFound, got \(error)")
            }
        }
    }

    func testSFZWithNoRegionsIsRejected() throws {
        let empty = fixtures.appendingPathComponent("empty.sfz")
        try "// nothing here\n<group> key=60".write(to: empty, atomically: true, encoding: .utf8)
        let backend = MXSFZBackend(displayName: "Empty", sampleRate: engine.sampleRate)
        XCTAssertThrowsError(try backend.engine.loadSFZ(url: empty))
    }
}

/// Parser-level coverage. Fast, no audio hardware, catches opcode regressions
/// long before they show up as a silent region.
final class MXSFZParserTests: XCTestCase {

    func testParsesInheritanceFromGlobalMasterGroupRegion() throws {
        let text = """
        <global> ampeg_release=0.5
        <master> volume=-3
        <group> key=60 pitch_keycenter=60
        <region> sample=a.wav lovel=0 hivel=63
        <region> sample=b.wav lovel=64 hivel=127 volume=-6
        """
        let result = try MXSFZParser().parse(text: text)

        XCTAssertEqual(result.regions.count, 2)
        XCTAssertEqual(result.regions[0].ampegRelease, 0.5, accuracy: 1e-6)
        XCTAssertEqual(result.regions[0].volumeDB, -3, accuracy: 1e-6)
        XCTAssertEqual(result.regions[0].loKey, 60)
        XCTAssertEqual(result.regions[1].volumeDB, -6, accuracy: 1e-6,
                       "region opcode must win over the inherited master value")
    }

    func testParsesNoteNamesAndMidiNumbers() {
        XCTAssertEqual(MXSFZParser.midiNote(fromName: "c4"), 60)
        XCTAssertEqual(MXSFZParser.midiNote(fromName: "C-1"), 0)
        XCTAssertEqual(MXSFZParser.midiNote(fromName: "a4"), 69)
        XCTAssertEqual(MXSFZParser.midiNote(fromName: "f#3"), 54)
        XCTAssertEqual(MXSFZParser.midiNote(fromName: "bb3"), 58)
        XCTAssertNil(MXSFZParser.midiNote(fromName: "notanote"))
    }

    func testSampleValueMayContainSpaces() throws {
        let text = "<region> sample=Grand Piano C4.wav key=60"
        let result = try MXSFZParser().parse(text: text)
        XCTAssertEqual(result.regions.first?.samplePath, "Grand Piano C4.wav")
        XCTAssertEqual(result.regions.first?.loKey, 60)
    }

    func testCommentsAreStripped() throws {
        let text = """
        // leading comment
        <region> sample=a.wav key=60 // trailing comment
        """
        let result = try MXSFZParser().parse(text: text)
        XCTAssertEqual(result.regions.count, 1)
        XCTAssertEqual(result.regions[0].samplePath, "a.wav")
    }

    func testRoundRobinSequenceMatching() {
        var region = MXSFZRegion(samplePath: "a.wav")
        region.seqLength = 4
        region.seqPosition = 3
        XCTAssertFalse(region.matchesSequence(counter: 0))
        XCTAssertTrue(region.matchesSequence(counter: 2))
        XCTAssertTrue(region.matchesSequence(counter: 6))
    }

    func testUnknownOpcodesAreCollectedNotFatal() throws {
        let text = "<region> sample=a.wav key=60 some_future_opcode=42"
        let result = try MXSFZParser().parse(text: text)
        XCTAssertEqual(result.regions.count, 1)
        XCTAssertTrue(result.unknownOpcodes.contains("some_future_opcode"))
    }
}
