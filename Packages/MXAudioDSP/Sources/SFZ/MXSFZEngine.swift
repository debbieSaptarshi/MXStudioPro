import Foundation

/// The seam sfizz would slot into.
///
/// Deliberately POD-in / POD-out: no Swift objects cross it at render time, so
/// a C++ implementation can satisfy it through a thin ObjC++ bridge without
/// touching the Swift runtime on the audio thread. See
/// `Vendor/sfizz/README.md` for the swap procedure.
public protocol MXSFZEngine: AnyObject {
    func loadSFZ(url: URL) throws

    /// Control-thread entry points. `frameOffset` positions the event inside the
    /// next render block for sample-accurate sequencing.
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, frameOffset: Int)
    func noteOff(note: UInt8, channel: UInt8, frameOffset: Int)
    func allNotesOff()

    func setPolyphony(_ voices: Int)
    func setSampleRate(_ rate: Double)

    /// Render-thread entry point.
    func render(left: UnsafeMutablePointer<Float>,
                right: UnsafeMutablePointer<Float>,
                frameCount: Int)

    var activeVoiceCount: Int { get }
    var loadedRegionCount: Int { get }
    var residentBytes: Int { get }
}

public enum MXSFZEngineKind: String, Sendable {
    case native
    case sfizz
}

/// Single place that decides which SFZ implementation is live.
public enum MXSFZEngineFactory {
    /// Flip to `.sfizz` once the vendored engine is wired up.
    public static var preferred: MXSFZEngineKind = .native

    public static func make(sampleRate: Double = 48_000,
                            store: MXSampleStore? = nil) -> MXSFZEngine {
        switch preferred {
        case .native, .sfizz:
            // `.sfizz` intentionally falls back until the bridge target exists,
            // so flipping the flag early degrades rather than crashing.
            return MXSFZSampler(sampleRate: sampleRate, store: store)
        }
    }
}
