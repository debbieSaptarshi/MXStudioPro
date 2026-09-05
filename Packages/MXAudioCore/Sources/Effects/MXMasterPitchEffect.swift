import AVFoundation
import MXAudioDSP

/// Live master pitch shift for playback (GarageBand / BandLab transpose lite).
///
/// Uses `AVAudioUnitTimePitch` with rate locked at 1.0 so BPM is unchanged.
/// Pitch is expressed in semitones (−12…+12); the unit expects cents.
public final class MXMasterPitchEffect: MXEffect, @unchecked Sendable {

    private let timePitch: AVAudioUnitTimePitch
    private var bypassed = false
    private var semitones: Float = 0

    public init() {
        timePitch = AVAudioUnitTimePitch()
        timePitch.rate = 1.0
        timePitch.pitch = 0
    }

    public var node: AVAudioNode { timePitch }

    public var displayName: String { "Master Pitch" }

    /// Whole-semitone transposition applied to the master bus (−12…+12).
    public var pitchSemitones: Float {
        get { semitones }
        set {
            semitones = min(max(newValue, -12), 12)
            applyPitch()
        }
    }

    public var isBypassed: Bool {
        get { bypassed }
        set {
            bypassed = newValue
            applyPitch()
        }
    }

    public func setParameter(_ id: MXParamID, value: Float) {
        if id == .masterPitch {
            pitchSemitones = value
        }
    }

    public func parameter(_ id: MXParamID) -> Float {
        id == .masterPitch ? pitchSemitones : 0
    }

    public func captureState() -> Data {
        var bytes = Data()
        bytes.append(bypassed ? UInt8(1) : UInt8(0))
        var pitch = semitones
        withUnsafeBytes(of: &pitch) { bytes.append(contentsOf: $0) }
        return bytes
    }

    public func restoreState(_ data: Data) throws {
        guard data.count >= MemoryLayout<Float>.size + 1 else { return }
        bypassed = data[0] != 0
        semitones = data.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 1, as: Float.self)
        }
        applyPitch()
    }

    private func applyPitch() {
        timePitch.rate = 1.0
        timePitch.pitch = bypassed ? 0 : semitones * 100
    }
}
