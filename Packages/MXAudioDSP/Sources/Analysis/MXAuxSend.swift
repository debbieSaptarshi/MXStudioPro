import Foundation

/// Shared reverb-aux routing math (Week 81 — BandLab / Logic send bus lite).
///
/// Tracks keep a dry (or insert-wet) path to the master bus. A parallel **send**
/// taps post-fader audio at `reverbSend` (0…100), feeds one shared reverb aux
/// that stays fully wet, then returns at `auxReverbReturn` (0…100).
///
/// Pure + `Sendable` so bounce / unit tests share the same gain law as live mix
/// without touching `AVAudioEngine`.
public enum MXAuxSend: Sendable {

    /// Default aux return percent — matches the historical live `returnLevel` of 0.7.
    public static let defaultReturnPercent: Float = 70

    /// Clamp a mixer send / return control to 0…100.
    public static func clampPercent(_ value: Float) -> Float {
        min(max(value, 0), 100)
    }

    /// Linear send gain 0…1 from a 0…100 mixer Send control.
    public static func linearGain(percent: Float) -> Float {
        clampPercent(percent) / 100
    }

    /// Linear aux return gain 0…1 from a 0…100 Aux Return control.
    public static func returnGain(percent: Float) -> Float {
        clampPercent(percent) / 100
    }

    /// Post-fader send tap: dry sample already scaled by track/clip/automation gain.
    public static func sendTap(postFaderSample: Float, sendPercent: Float) -> Float {
        postFaderSample * linearGain(percent: sendPercent)
    }

    /// Aux return contribution into one master channel after a fully-wet reverb.
    public static func masterContribution(wetSample: Float, returnPercent: Float) -> Float {
        wetSample * returnGain(percent: returnPercent)
    }

    /// Whether a send should open an aux route (above ~0.5% → audible).
    public static func isActive(sendPercent: Float) -> Bool {
        clampPercent(sendPercent) > 0.5
    }

    /// Extra bounce seconds so shared-aux tails are not chopped.
    public static func auxTailSeconds(sendPercent: Float, smallRoom: Bool = false) -> Double {
        guard isActive(sendPercent: sendPercent) else { return 0 }
        return smallRoom ? 0.85 : 1.35
    }
}
