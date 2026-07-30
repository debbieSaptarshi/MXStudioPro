import AVFoundation
import MXAudioDSP
import AudioToolbox

/// GarageBand-style master brickwall lite for live playback (Week 59).
///
/// Wraps `AVAudioUnitEffect` DynamicsProcessor with near-ceiling threshold so
/// overs are soft-limited before `mainMixerNode`. Bounce still uses
/// `MXLoudness.applyMasterLimiter` offline.
public final class MXMasterLimiterEffect: MXEffect, @unchecked Sendable {

    private let dynamics: AVAudioUnitEffect
    private var bypassed = false

    public init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        dynamics = AVAudioUnitEffect(audioComponentDescription: description)
        Self.configureBrickwall(dynamics)
    }

    public var node: AVAudioNode { dynamics }

    public var displayName: String { "Master Limiter" }

    public var isBypassed: Bool {
        get { bypassed }
        set {
            bypassed = newValue
            // Bypass by opening the dynamics wide so it passes audio unchanged.
            if let au = dynamics.audioUnit {
                if newValue {
                    AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, 0, 0)
                    AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 40, 0)
                    AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
                    AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
                } else {
                    Self.configureBrickwall(dynamics)
                }
            }
        }
    }

    public func setParameter(_ id: MXParamID, value: Float) {}
    public func parameter(_ id: MXParamID) -> Float { 0 }

    public func captureState() -> Data {
        Data([bypassed ? UInt8(1) : UInt8(0)])
    }

    public func restoreState(_ data: Data) throws {
        guard let byte = data.first else { return }
        isBypassed = byte != 0
    }

    private static func configureBrickwall(_ unit: AVAudioUnitEffect) {
        guard let au = unit.audioUnit else { return }
        // Near-ceiling threshold + tiny headroom ≈ soft brickwall.
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -1.5, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 0.5, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -40, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
    }
}
