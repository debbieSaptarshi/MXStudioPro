import XCTest
@testable import MXAudioCore

final class MXCrossfadeTests: XCTestCase {

    func testEqualPowerEndpoints() {
        XCTAssertEqual(MXCrossfade.equalPowerIn(0), 0, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerIn(1), 1, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerOut(0), 1, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerOut(1), 0, accuracy: 1e-6)
    }

    func testEqualPowerConstantPower() {
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            let gOut = MXCrossfade.equalPowerOut(t)
            let gIn = MXCrossfade.equalPowerIn(t)
            let power = Double(gOut * gOut + gIn * gIn)
            XCTAssertEqual(power, 1, accuracy: 1e-5, "t=\(t)")
        }
    }

    func testClampsOutsideUnitInterval() {
        XCTAssertEqual(MXCrossfade.equalPowerIn(-0.5), 0, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerIn(1.5), 1, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerOut(-0.5), 1, accuracy: 1e-6)
        XCTAssertEqual(MXCrossfade.equalPowerOut(1.5), 0, accuracy: 1e-6)
    }
}
