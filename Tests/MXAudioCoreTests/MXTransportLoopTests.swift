import XCTest
@testable import MXAudioCore

final class MXTransportLoopTests: XCTestCase {

    func testEnabledLoopWrapsCurrentBeatNearStart() {
        let tempo = MXTempoMap(bpm: 120)
        let sampleRate = 48_000.0
        let transport = MXTransport(tempoMap: tempo,
                                    sampleRate: sampleRate,
                                    clockSource: .offline)

        transport.loop = MXTransport.LoopRegion(startBeat: 0, endBeat: 4, isEnabled: true)
        transport.play(fromSample: 0)

        let endSample = tempo.sample(forBeat: 4, sampleRate: sampleRate)
        // Advance just past the loop end (about 0.25 beats ≈ 0.125 s at 120 BPM).
        let pastEnd = Int(endSample) + Int(0.125 * sampleRate)
        transport.advance(frames: pastEnd)

        // Wrapped position: (pastEnd - start) % length → near beat 0.25.
        XCTAssertLessThan(transport.currentBeat, 1.0,
                          "expected wrap near loop start, got beat \(transport.currentBeat)")
        XCTAssertGreaterThan(transport.currentBeat, 0.1,
                             "expected residual past wrap, got beat \(transport.currentBeat)")
        XCTAssertEqual(transport.currentBeat, 0.25, accuracy: 0.05)
    }

    func testDisabledLoopDoesNotWrap() {
        let tempo = MXTempoMap(bpm: 120)
        let sampleRate = 48_000.0
        let transport = MXTransport(tempoMap: tempo,
                                    sampleRate: sampleRate,
                                    clockSource: .offline)

        transport.loop = MXTransport.LoopRegion(startBeat: 0, endBeat: 4, isEnabled: false)
        transport.play(fromSample: 0)

        let endSample = tempo.sample(forBeat: 4, sampleRate: sampleRate)
        let pastEnd = Int(endSample) + Int(0.125 * sampleRate)
        transport.advance(frames: pastEnd)

        XCTAssertGreaterThan(transport.currentBeat, 4.0,
                             "disabled loop must not wrap; beat=\(transport.currentBeat)")
    }

    func testNilLoopDoesNotWrap() {
        let tempo = MXTempoMap(bpm: 120)
        let sampleRate = 48_000.0
        let transport = MXTransport(tempoMap: tempo,
                                    sampleRate: sampleRate,
                                    clockSource: .offline)

        transport.loop = nil
        transport.play(fromSample: 0)

        let endSample = tempo.sample(forBeat: 4, sampleRate: sampleRate)
        transport.advance(frames: Int(endSample) + 4_800)

        XCTAssertGreaterThan(transport.currentBeat, 4.0)
    }

    // MARK: - Loop schedule clamp (Week 29)

    func testClampCapsFramesAtLoopEnd() {
        let capped = MXLoopScheduleClamp.clampFrameCount(
            requestedFrames: 10_000,
            audibleStartSample: 8_000,
            loopEndSample: 12_000,
            loopEnabled: true
        )
        XCTAssertEqual(capped, 4_000)
    }

    func testClampReturnsZeroWhenStartAtOrPastLoopEnd() {
        XCTAssertEqual(
            MXLoopScheduleClamp.clampFrameCount(
                requestedFrames: 1_000,
                audibleStartSample: 12_000,
                loopEndSample: 12_000,
                loopEnabled: true
            ),
            0
        )
        XCTAssertEqual(
            MXLoopScheduleClamp.clampFrameCount(
                requestedFrames: 1_000,
                audibleStartSample: 12_500,
                loopEndSample: 12_000,
                loopEnabled: true
            ),
            0
        )
    }

    func testClampPassthroughWhenLoopDisabled() {
        XCTAssertEqual(
            MXLoopScheduleClamp.clampFrameCount(
                requestedFrames: 10_000,
                audibleStartSample: 8_000,
                loopEndSample: 12_000,
                loopEnabled: false
            ),
            10_000
        )
    }

    func testClampDoesNotExtendShortRequest() {
        XCTAssertEqual(
            MXLoopScheduleClamp.clampFrameCount(
                requestedFrames: 500,
                audibleStartSample: 8_000,
                loopEndSample: 12_000,
                loopEnabled: true
            ),
            500
        )
    }
}
