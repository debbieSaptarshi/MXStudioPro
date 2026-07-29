import AVFoundation
import Foundation
import MXAudioDSP

/// Base class for instruments whose DSP we own, wrapping the `AVAudioSourceNode`
/// plumbing so each backend only has to fill a stereo pair.
///
/// Lifetime contract: the render block captures `self` as `unowned(unsafe)` to
/// keep ARC off the audio thread. That is safe because the node is owned by the
/// instrument and `MXGraph` always detaches a node before releasing the
/// instrument that vends it. Breaking that ordering is a use-after-free, which
/// is why nothing outside `MXGraph` is allowed to call `detach`.
open class MXSourceInstrument: MXInstrument, @unchecked Sendable {

    public private(set) var sourceNode: AVAudioSourceNode!
    public var node: AVAudioNode { sourceNode }

    public var displayName: String
    public private(set) var sampleRate: Double

    /// Scratch buffers so `render` always gets contiguous, deinterleaved
    /// channels regardless of what the engine hands us.
    private var scratchLeft: UnsafeMutablePointer<Float>
    private var scratchRight: UnsafeMutablePointer<Float>
    private let scratchCapacity: Int

    open var polyphony: Int {
        get { 16 }
        set { _ = newValue }
    }

    public init(displayName: String,
                sampleRate: Double = 48_000,
                maximumFrameCount: Int = 4_096) {
        self.displayName = displayName
        self.sampleRate = sampleRate
        scratchCapacity = maximumFrameCount
        scratchLeft = .allocate(capacity: maximumFrameCount)
        scratchRight = .allocate(capacity: maximumFrameCount)
        scratchLeft.initialize(repeating: 0, count: maximumFrameCount)
        scratchRight.initialize(repeating: 0, count: maximumFrameCount)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        sourceNode = AVAudioSourceNode(format: format) { [unowned(unsafe) self] _, _, frameCount, audioBufferList in
            self.fill(frameCount: Int(frameCount), audioBufferList: audioBufferList)
        }
    }

    deinit {
        scratchLeft.deinitialize(count: scratchCapacity)
        scratchLeft.deallocate()
        scratchRight.deinitialize(count: scratchCapacity)
        scratchRight.deallocate()
    }

    /// Subclass hook. Called on the render thread — no allocation, no locks.
    open func render(left: UnsafeMutablePointer<Float>,
                     right: UnsafeMutablePointer<Float>,
                     frameCount: Int) {
        for i in 0..<frameCount {
            left[i] = 0
            right[i] = 0
        }
    }

    private func fill(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let frames = min(frameCount, scratchCapacity)
        render(left: scratchLeft, right: scratchRight, frameCount: frames)

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for (index, buffer) in buffers.enumerated() {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let source = index == 0 ? scratchLeft : scratchRight
            data.update(from: source, count: frames)
            // Zero any frames the engine asked for beyond our scratch capacity
            // rather than leaving stale audio behind.
            if frameCount > frames {
                (data + frames).update(repeating: 0, count: frameCount - frames)
            }
        }
        return noErr
    }

    open func setSampleRate(_ rate: Double) {
        sampleRate = rate
    }

    // MARK: - MXInstrument (subclasses override what they support)

    open func load(_ resource: MXInstrumentResource) async throws {
        throw MXAudioError.unsupportedResource(resource.displayName)
    }

    open func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {}
    open func noteOff(_ note: UInt8, channel: UInt8) {}
    open func allNotesOff() {}
    open func setParameter(_ id: MXParamID, value: Float) {}
    open func parameter(_ id: MXParamID) -> Float { 0 }
    open func captureState() -> Data { Data() }
    open func restoreState(_ data: Data) throws {}
}
