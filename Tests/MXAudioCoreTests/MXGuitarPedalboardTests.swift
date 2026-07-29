import XCTest
@testable import MXAudioCore

final class MXGuitarPedalboardTests: XCTestCase {
    func testPresetsCoverDistDelayRevRanges() {
        for preset in MXGuitarPedalPreset.allCases {
            XCTAssertGreaterThanOrEqual(preset.distortionMix, 0)
            XCTAssertLessThanOrEqual(preset.distortionMix, 100)
            XCTAssertGreaterThanOrEqual(preset.delayMix, 0)
            XCTAssertLessThanOrEqual(preset.delayMix, 100)
            XCTAssertGreaterThan(preset.delayTime, 0.05)
            XCTAssertLessThan(preset.delayTime, 0.8)
            XCTAssertGreaterThanOrEqual(preset.reverbMix, 0)
            XCTAssertLessThanOrEqual(preset.reverbMix, 100)
            XCTAssertFalse(preset.title.isEmpty)
        }
    }

    func testCrunchIsTrackSeedAndDistinctFromClean() {
        XCTAssertEqual(MXGuitarPedalPreset.trackSeed, .crunch)
        XCTAssertFalse(
            MXGuitarPedalPreset.clean.matches(
                distortionMix: MXGuitarPedalPreset.crunch.distortionMix,
                delayMix: MXGuitarPedalPreset.crunch.delayMix,
                delayTime: MXGuitarPedalPreset.crunch.delayTime,
                reverbMix: MXGuitarPedalPreset.crunch.reverbMix
            )
        )
        XCTAssertTrue(
            MXGuitarPedalPreset.crunch.matches(
                distortionMix: 42,
                delayMix: 22,
                delayTime: 0.32,
                reverbMix: 18
            )
        )
    }

    func testBounceDistortionPassthroughWhenDry() {
        XCTAssertEqual(MXGuitarPedalPreset.bounceDistortion(sample: 0.5, amount: 0), 0.5, accuracy: 1e-5)
    }

    func testBounceDistortionSoftClipsHotPeaks() {
        let hot: Float = 0.95
        let wet = MXGuitarPedalPreset.bounceDistortion(sample: hot, amount: 80)
        XCTAssertLessThan(abs(wet), abs(hot) * 1.05)
        XCTAssertGreaterThan(abs(wet), 0.2)
        // Polarity preserved for positive peaks.
        XCTAssertGreaterThan(wet, 0)
    }

    func testLeadIsHottestDistortion() {
        let dist = MXGuitarPedalPreset.allCases.map(\.distortionMix)
        XCTAssertEqual(dist.max(), MXGuitarPedalPreset.lead.distortionMix)
        XCTAssertEqual(MXGuitarPedalPreset.allCases.map(\.reverbMix).max(), MXGuitarPedalPreset.ambient.reverbMix)
    }
}
