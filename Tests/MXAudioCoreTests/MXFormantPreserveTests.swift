import Foundation
import XCTest
@testable import MXAudioDSP

final class MXFormantPreserveTests: XCTestCase {
    func testAmountZeroReturnsShifted() {
        let shifted: [Float] = [0.1, 0.2, 0.3, 0.4]
        let original: [Float] = [0.5, 0.4, 0.3, 0.2]
        let out = MXFormantPreserve.compensate(
            shifted: shifted,
            original: original,
            pitchRatio: 1.2,
            amount: 0
        )
        XCTAssertEqual(out, shifted)
    }

    func testIdentityRatioReturnsShifted() {
        let shifted: [Float] = [0.1, 0.2, 0.3]
        let out = MXFormantPreserve.compensate(
            shifted: shifted,
            original: shifted,
            pitchRatio: 1,
            amount: 1
        )
        XCTAssertEqual(out, shifted)
    }

    func testCompensatePreservesLength() {
        let shifted = (0..<256).map { Float(sin(Double($0) * 0.1)) }
        let original = shifted
        let out = MXFormantPreserve.compensate(
            shifted: shifted,
            original: original,
            pitchRatio: 1.15,
            amount: 0.7
        )
        XCTAssertEqual(out.count, shifted.count)
    }
}
