import XCTest
@testable import MXAudioDSP

final class MXReelsWaveformTests: XCTestCase {
    func testPeaksBurstRegion() {
        var mono = [Float](repeating: 0, count: 1000)
        for i in 400..<600 { mono[i] = 0.8 }
        let peaks = MXReelsWaveform.peaks(mono: mono, barCount: 32)
        XCTAssertEqual(peaks.count, 32)
        let mid = peaks[16]
        XCTAssertGreaterThan(mid, 0.5)
        XCTAssertLessThan(peaks[0], 0.1)
        XCTAssertLessThan(peaks[31], 0.1)
    }

    func testPlayheadProgress() {
        XCTAssertEqual(MXReelsWaveform.playheadProgress(presentationSeconds: 0.5, durationSeconds: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MXReelsWaveform.playheadProgress(presentationSeconds: 2, durationSeconds: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(MXReelsWaveform.playheadProgress(presentationSeconds: -1, durationSeconds: 1), 0, accuracy: 1e-9)
    }

    func testCenterBarEdges() {
        XCTAssertEqual(MXReelsWaveform.centerBar(progress: 0, totalBars: 64), 0)
        XCTAssertEqual(MXReelsWaveform.centerBar(progress: 1, totalBars: 64), 63)
        XCTAssertEqual(MXReelsWaveform.centerBar(progress: 0.5, totalBars: 64), 32)
    }

    func testVisibleBarRangeBounds() {
        let range = MXReelsWaveform.visibleBarRange(totalBars: 64, visibleBars: 16, centerBar: 0)
        XCTAssertEqual(range.lowerBound, 0)
        XCTAssertEqual(range.count, 16)
        let end = MXReelsWaveform.visibleBarRange(totalBars: 64, visibleBars: 16, centerBar: 63)
        XCTAssertEqual(end.upperBound, 64)
    }

    func testNormalizedPeaksFloor() {
        let raw: [Float] = [0, 0.001, 1]
        let norm = MXReelsWaveform.normalizedPeaks(raw, floorDB: -48)
        XCTAssertEqual(norm[0], 0, accuracy: 1e-6)
        XCTAssertGreaterThan(norm[2], 0.9)
    }

    func testBarLayoutCount() {
        let peaks: [Float] = [0.2, 0.8, 0.5, 0.9]
        let layout = MXReelsWaveform.barLayout(peaks: peaks, visibleRange: 0..<4)
        XCTAssertEqual(layout.count, 4)
        XCTAssertGreaterThan(layout[1].height, layout[0].height)
    }
}
