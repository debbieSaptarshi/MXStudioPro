import XCTest
@testable import MXAudioDSP

final class MXReelsWaveformTests: XCTestCase {
    func testPeaksEmpty() {
        let peaks = MXReelsWaveform.peaks(mono: [])
        XCTAssertEqual(peaks.barCount, MXReelsWaveform.defaultBarCount)
        XCTAssertTrue(peaks.bars.allSatisfy { $0 == 0 })
    }

    func testPeaksNormalized() {
        var mono = [Float](repeating: 0, count: 640)
        for i in 0..<320 { mono[i] = 0.8 }
        let peaks = MXReelsWaveform.peaks(mono: mono, barCount: 16)
        XCTAssertEqual(peaks.barCount, 16)
        XCTAssertGreaterThan(peaks.bars[0], 0.5)
        XCTAssertLessThanOrEqual(peaks.bars.max() ?? 0, 1.01)
    }

    func testPlayheadFraction() {
        XCTAssertEqual(MXReelsWaveform.playheadFraction(frameIndex: 0, frameCount: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(MXReelsWaveform.playheadFraction(frameIndex: 9, frameCount: 10), 1, accuracy: 1e-9)
    }

    func testPlayheadBarIndex() {
        XCTAssertEqual(MXReelsWaveform.playheadBarIndex(fraction: 0, barCount: 64), 0)
        XCTAssertEqual(MXReelsWaveform.playheadBarIndex(fraction: 1, barCount: 64), 63)
    }
}
