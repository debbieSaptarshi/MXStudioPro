import AVFoundation
import MXAudioDSP

/// Thin wrapper around `AVAudioUnitReverb` for aux send buses.
/// The unit stays fully wet — send level is controlled on the track mixer.
public final class MXAUReverbEffect: MXEffect, @unchecked Sendable {

    private let reverb = AVAudioUnitReverb()
    private var bypassed = false

    public init() {
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 100
    }

    public var node: AVAudioNode { reverb }

    public var displayName: String { "Reverb" }

    public var isBypassed: Bool {
        get { bypassed }
        set {
            bypassed = newValue
            reverb.wetDryMix = newValue ? 0 : 100
        }
    }

    public func setParameter(_ id: MXParamID, value: Float) {
        switch id {
        case .fxMix:
            reverb.wetDryMix = bypassed ? 0 : min(max(value, 0), 100)
        default:
            break
        }
    }

    public func parameter(_ id: MXParamID) -> Float {
        switch id {
        case .fxMix:
            return reverb.wetDryMix
        default:
            return 0
        }
    }

    public func captureState() -> Data {
        Data([bypassed ? UInt8(1) : UInt8(0)])
    }

    public func restoreState(_ data: Data) throws {
        guard let byte = data.first else { return }
        isBypassed = byte != 0
    }
}
