import XCTest
@testable import MXAudioCore

final class MXVolumeAutomationTests: XCTestCase {
    func testEmptyIsUnity() {
        XCTAssertEqual(MXVolumeAutomation.value(atBeat: 1, points: []), 1, accuracy: 1e-6)
    }

    func testEndpointHold() {
        let points = [
            MXAutomationPoint(beat: 1, value: 0.5),
            MXAutomationPoint(beat: 3, value: 1.5),
        ]
        XCTAssertEqual(MXVolumeAutomation.value(atBeat: 0, points: points), 0.5, accuracy: 1e-6)
        XCTAssertEqual(MXVolumeAutomation.value(atBeat: 4, points: points), 1.5, accuracy: 1e-6)
    }

    func testLinearInterpolation() {
        let points = [
            MXAutomationPoint(beat: 0, value: 0),
            MXAutomationPoint(beat: 2, value: 2),
        ]
        XCTAssertEqual(MXVolumeAutomation.value(atBeat: 1, points: points), 1, accuracy: 1e-5)
        XCTAssertEqual(MXVolumeAutomation.value(atBeat: 0.5, points: points), 0.5, accuracy: 1e-5)
    }

    func testUpsertNearExisting() {
        var points = [MXAutomationPoint(beat: 1, value: 1)]
        points = MXVolumeAutomation.upserting(points, beat: 1.02, value: 0.25, toleranceBeats: 0.08)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, 0.25, accuracy: 1e-6)
    }

    func testMoveAndRemove() {
        let a = MXAutomationPoint(beat: 0, value: 1)
        let b = MXAutomationPoint(beat: 2, value: 0.5)
        var points = [a, b]
        points = MXVolumeAutomation.moving(points, id: b.id, beat: 3, value: 1.5)
        XCTAssertEqual(points.last?.beat, 3, accuracy: 1e-9)
        XCTAssertEqual(points.last?.value, 1.5, accuracy: 1e-6)
        points = MXVolumeAutomation.removing(points, id: a.id)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].id, b.id)
    }

    func testClampBeatsToClipLength() {
        let points = [
            MXAutomationPoint(beat: -1, value: 0.5),
            MXAutomationPoint(beat: 5, value: 1.5),
        ]
        let clamped = MXVolumeAutomation.clampingBeats(points, lengthBeats: 4)
        XCTAssertEqual(clamped[0].beat, 0, accuracy: 1e-9)
        XCTAssertEqual(clamped[1].beat, 4, accuracy: 1e-9)
    }

    func testPanAutomationInterpAndCombine() {
        let points = [
            MXAutomationPoint(beat: 0, value: -1),
            MXAutomationPoint(beat: 2, value: 1),
        ]
        XCTAssertEqual(MXPanAutomation.value(atBeat: 1, points: points), 0, accuracy: 1e-5)
        XCTAssertEqual(MXPanAutomation.value(atBeat: 3, points: []), 0, accuracy: 1e-6)
        XCTAssertEqual(MXPanAutomation.combined(trackPan: 0.5, clipOffset: 0.8), 1, accuracy: 1e-6)
        XCTAssertEqual(MXPanAutomation.combined(trackPan: -0.5, clipOffset: -0.8), -1, accuracy: 1e-6)
    }

    func testPanUpsertClamp() {
        var points: [MXAutomationPoint] = []
        points = MXPanAutomation.upserting(points, beat: 1, value: 2)
        XCTAssertEqual(points[0].value, 1, accuracy: 1e-6)
        points = MXPanAutomation.upserting(points, beat: 1.01, value: -2)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, -1, accuracy: 1e-6)
    }

    func testClipGainRelativeMultiplies() {
        let relative = MXClipGainAutomation.effectiveGain(
            clipGain: 0.5,
            mode: .relative,
            automationValue: 1.5,
            hasAutomation: true
        )
        XCTAssertEqual(relative, 0.75, accuracy: 1e-5)
        let empty = MXClipGainAutomation.effectiveGain(
            clipGain: 0.5,
            mode: .relative,
            automationValue: 1.5,
            hasAutomation: false
        )
        XCTAssertEqual(empty, 0.5, accuracy: 1e-5)
    }

    func testClipGainAbsoluteReplaces() {
        let absolute = MXClipGainAutomation.effectiveGain(
            clipGain: 0.5,
            mode: .absolute,
            automationValue: 1.25,
            hasAutomation: true
        )
        XCTAssertEqual(absolute, 1.25, accuracy: 1e-5)
        let empty = MXClipGainAutomation.effectiveGain(
            clipGain: 0.8,
            mode: .absolute,
            automationValue: 1.25,
            hasAutomation: false
        )
        XCTAssertEqual(empty, 0.8, accuracy: 1e-5)
    }

    func testClipGainClampsStatic() {
        let high = MXClipGainAutomation.effectiveGain(
            clipGain: 9,
            mode: .relative,
            automationValue: 1,
            hasAutomation: false
        )
        XCTAssertEqual(high, MXClipGainAutomation.maxGain, accuracy: 1e-5)
    }
}
