import XCTest
@testable import MXAudioCore

final class MXMIDIScaleTests: XCTestCase {
    // MARK: - Mode intervals

    func testMajorIntervals() {
        XCTAssertEqual(MXMIDIScaleMode.major.intervals, [0, 2, 4, 5, 7, 9, 11])
    }

    func testNaturalMinorIntervals() {
        XCTAssertEqual(MXMIDIScaleMode.naturalMinor.intervals, [0, 2, 3, 5, 7, 8, 10])
    }

    func testDisplayNames() {
        XCTAssertEqual(MXMIDIScaleMode.major.displayName, "Major")
        XCTAssertEqual(MXMIDIScaleMode.naturalMinor.displayName, "Minor")
        XCTAssertEqual(MXMIDIScale.cMajor.displayName, "C Major")
        XCTAssertEqual(
            MXMIDIScale(rootPitchClass: 9, mode: .naturalMinor).displayName,
            "A Minor"
        )
    }

    // MARK: - contains

    func testCMajorContainsWhiteKeys() {
        let scale = MXMIDIScale.cMajor
        // C D E F G A B across octaves.
        XCTAssertTrue(scale.contains(60)) // C4
        XCTAssertTrue(scale.contains(62)) // D4
        XCTAssertTrue(scale.contains(64)) // E4
        XCTAssertTrue(scale.contains(65)) // F4
        XCTAssertTrue(scale.contains(67)) // G4
        XCTAssertTrue(scale.contains(69)) // A4
        XCTAssertTrue(scale.contains(71)) // B4
        XCTAssertTrue(scale.contains(72)) // C5
    }

    func testCMajorExcludesBlackKeys() {
        let scale = MXMIDIScale.cMajor
        XCTAssertFalse(scale.contains(61)) // C#
        XCTAssertFalse(scale.contains(63)) // D#
        XCTAssertFalse(scale.contains(66)) // F#
        XCTAssertFalse(scale.contains(68)) // G#
        XCTAssertFalse(scale.contains(70)) // A#
    }

    func testAMinorContainsExpectedPitchClasses() {
        let scale = MXMIDIScale(rootPitchClass: 9, mode: .naturalMinor)
        // A natural minor uses the same white keys as C major.
        XCTAssertEqual(scale.pitchClasses, MXMIDIScale.cMajor.pitchClasses)
        XCTAssertTrue(scale.contains(69))  // A
        XCTAssertTrue(scale.contains(71))  // B
        XCTAssertTrue(scale.contains(72))  // C
        XCTAssertFalse(scale.contains(70)) // A#
    }

    // MARK: - snapPitch

    func testSnapPitchLeavesInScalePitches() {
        let scale = MXMIDIScale.cMajor
        XCTAssertEqual(scale.snapPitch(60), 60)
        XCTAssertEqual(scale.snapPitch(67), 67)
    }

    func testSnapPitchMovesToNearestInScale() {
        let scale = MXMIDIScale.cMajor
        // C# (61) → nearest is C (60) or D (62); ties prefer lower → C.
        XCTAssertEqual(scale.snapPitch(61), 60)
        // F# (66) → F (65) or G (67); ties prefer lower → F.
        XCTAssertEqual(scale.snapPitch(66), 65)
        // A# (70) → A (69) or B (71); ties prefer lower → A.
        XCTAssertEqual(scale.snapPitch(70), 69)
    }

    func testSnapPitchGMajorAsymmetric() {
        // G major = G A B C D E F# → F natural (5) is out of scale.
        let scale = MXMIDIScale(rootPitchClass: 7, mode: .major)
        XCTAssertFalse(scale.contains(65)) // F natural
        // F (65): down to E(64, out), up to F#(66, in) → nearest in-scale is F#.
        XCTAssertEqual(scale.snapPitch(65), 66)
    }

    func testSnapPitchStaysInBounds() {
        let scale = MXMIDIScale.cMajor
        let low = scale.snapPitch(0)
        XCTAssertTrue(scale.contains(low))
        let high = scale.snapPitch(127)
        XCTAssertTrue(scale.contains(high))
        XCTAssertLessThanOrEqual(high, 127)
    }

    // MARK: - Root normalization

    func testRootPitchClassWrapsModulo12() {
        let scale = MXMIDIScale(rootPitchClass: 14, mode: .major) // 14 % 12 = 2 (D)
        XCTAssertEqual(scale.rootPitchClass, 2)
        XCTAssertEqual(scale.rootDisplayName, "D")
    }
}
