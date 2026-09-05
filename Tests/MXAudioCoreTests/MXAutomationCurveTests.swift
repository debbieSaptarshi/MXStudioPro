import XCTest
@testable import MXAudioCore

final class MXAutomationCurveTests: XCTestCase {
    func testEaseInOutEndpoints() {
        XCTAssertEqual(MXAutomationCurveMath.easeInOut(0), 0, accuracy: 1e-6)
        XCTAssertEqual(MXAutomationCurveMath.easeInOut(1), 1, accuracy: 1e-6)
        XCTAssertGreaterThan(MXAutomationCurveMath.easeInOut(0.5), 0.4)
        XCTAssertLessThan(MXAutomationCurveMath.easeInOut(0.5), 0.6)
    }

    func testBezierVolumeMidpointDiffersFromLinear() {
        let linear = [
            MXAutomationPoint(beat: 0, value: 0, curve: .linear),
            MXAutomationPoint(beat: 4, value: 2, curve: .linear),
        ]
        let bezier = [
            MXAutomationPoint(beat: 0, value: 0, curve: .bezier),
            MXAutomationPoint(beat: 4, value: 2, curve: .linear),
        ]
        let linearMid = MXVolumeAutomation.value(atBeat: 2, points: linear)
        let bezierMid = MXVolumeAutomation.value(atBeat: 2, points: bezier)
        XCTAssertEqual(linearMid, 1, accuracy: 1e-6)
        XCTAssertNotEqual(bezierMid, linearMid, accuracy: 0.05)
    }

    func testTrackPanAutomationOverridesStatic() {
        let pan = MXPanAutomation.trackPan(
            atBeat: 2,
            staticPan: 0,
            automation: [
                MXAutomationPoint(beat: 0, value: -1),
                MXAutomationPoint(beat: 4, value: 1),
            ]
        )
        XCTAssertEqual(pan, 0, accuracy: 1e-6)
    }

    func testToggleCurve() {
        let id = UUID()
        let points = [MXAutomationPoint(id: id, beat: 0, value: 1, curve: .linear)]
        let toggled = MXAutomationCurveMath.togglingCurve(points, id: id)
        XCTAssertEqual(toggled[0].curve, .bezier)
    }
}
