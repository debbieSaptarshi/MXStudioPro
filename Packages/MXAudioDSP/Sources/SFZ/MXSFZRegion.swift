import Foundation

/// One `<region>` from an SFZ file, already flattened with its inherited
/// `<global>` / `<master>` / `<group>` opcodes applied.
public struct MXSFZRegion: Equatable, Sendable {
    public enum LoopMode: String, Equatable, Sendable {
        case noLoop = "no_loop"
        case oneShot = "one_shot"
        case loopContinuous = "loop_continuous"
        case loopSustain = "loop_sustain"
    }

    public var samplePath: String

    // Key range
    public var loKey: UInt8 = 0
    public var hiKey: UInt8 = 127
    public var pitchKeyCenter: UInt8 = 60

    // Velocity range
    public var loVel: UInt8 = 0
    public var hiVel: UInt8 = 127

    // Round robin
    public var seqLength: Int = 1
    public var seqPosition: Int = 1

    // Choke groups: a region in `group` is silenced by a region whose
    // `offBy` matches. This is how a closed hi-hat cuts an open one.
    public var group: Int32 = -1
    public var offBy: Int32 = -1

    // Playback
    public var loopMode: LoopMode = .noLoop
    public var loopStart: Int = 0
    public var loopEnd: Int = 0
    public var offset: Int = 0

    // Gain / tuning
    public var volumeDB: Float = 0
    public var pan: Float = 0
    public var tuneCents: Float = 0

    // Per-region amplitude envelope
    public var ampegAttack: Float = 0.001
    public var ampegDecay: Float = 0
    public var ampegSustain: Float = 1
    public var ampegRelease: Float = 0.05

    public init(samplePath: String) {
        self.samplePath = samplePath
    }

    public func matches(note: UInt8, velocity: UInt8) -> Bool {
        note >= loKey && note <= hiKey && velocity >= loVel && velocity <= hiVel
    }

    /// Round-robin regions only sound on their turn in the rotation.
    public func matchesSequence(counter: Int) -> Bool {
        guard seqLength > 1 else { return true }
        return (counter % seqLength) + 1 == seqPosition
    }

    public var linearGain: Float {
        pow(10, volumeDB / 20)
    }
}
