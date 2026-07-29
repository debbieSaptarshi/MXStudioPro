import AVFoundation
import Foundation

/// The single seam the whole architecture rests on. Anything that makes sound
/// vends an `AVAudioNode`; the graph never learns which backend it got, so an
/// Apple sampler, an SFZ library, a synth and a hosted AUv3 are interchangeable
/// on any track.
public protocol MXInstrument: AnyObject {
    /// Node handed to the graph. Must be stable for the instrument's lifetime —
    /// the graph caches it across reconnections.
    var node: AVAudioNode { get }

    /// Maximum simultaneous voices. Exceeding it steals the oldest voice rather
    /// than dropping the new note or growing without bound.
    var polyphony: Int { get set }

    /// Human-readable, surfaced in the track header.
    var displayName: String { get }

    func load(_ resource: MXInstrumentResource) async throws
    func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8)
    func noteOff(_ note: UInt8, channel: UInt8)
    func allNotesOff()
    func setParameter(_ id: MXParamID, value: Float)
    func parameter(_ id: MXParamID) -> Float
    func captureState() -> Data
    func restoreState(_ data: Data) throws
}

public extension MXInstrument {
    func noteOn(_ note: UInt8, velocity: UInt8) {
        noteOn(note, velocity: velocity, channel: 0)
    }

    func noteOff(_ note: UInt8) {
        noteOff(note, channel: 0)
    }
}

/// Effects share the same shape so an insert slot can hold a built-in AU, an
/// AudioKit node, a convolution cabinet, or a hosted AUv3 without special cases.
public protocol MXEffect: AnyObject {
    var node: AVAudioNode { get }
    var displayName: String { get }

    /// Bypass must return the dry signal to within ±0.5 dB (plan 11.8), so it is
    /// modelled as explicit state rather than "set mix to zero".
    var isBypassed: Bool { get set }

    func setParameter(_ id: MXParamID, value: Float)
    func parameter(_ id: MXParamID) -> Float
    func captureState() -> Data
    func restoreState(_ data: Data) throws
}

/// Effects that need the graph to physically route around them when bypassed
/// (rather than handling it internally) opt in here.
public protocol MXBypassRoutable: MXEffect {
    var prefersGraphLevelBypass: Bool { get }
}
