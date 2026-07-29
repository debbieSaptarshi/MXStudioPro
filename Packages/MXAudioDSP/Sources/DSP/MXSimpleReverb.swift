import Foundation

/// Lightweight Schroeder-style offline reverb for bounce / export.
///
/// Uses a handful of comb + allpass delay buffers (no `AVAudioUnit`). Capacity is
/// allocated once at init; `process` never allocates so it is safe in tight
/// sample loops.
public final class MXSimpleReverb: @unchecked Sendable {
    /// Wet/dry mix in percent (0…100). 0 = fully dry.
    public var wetDryMix: Float = 0 {
        didSet { wetDryMix = min(max(wetDryMix, 0), 100) }
    }

    private let combBuffers: [UnsafeMutablePointer<Float>]
    private let combSizes: [Int]
    private var combWrite: [Int]
    private let combFeedback: [Float]

    private let allpassBuffers: [UnsafeMutablePointer<Float>]
    private let allpassSizes: [Int]
    private var allpassWrite: [Int]
    private let allpassGain: Float = 0.5

    /// - Parameters:
    ///   - sampleRate: Output sample rate for the bounce buffer.
    ///   - smallRoom: Shorter taps + faster decay (Reels Vocal preset).
    public init(sampleRate: Double = 48_000, smallRoom: Bool = false) {
        let srScale = Float(max(sampleRate, 1) / 44_100)
        // Freeverb-inspired comb lengths; scaled for sample rate.
        let baseCombs: [Float] = smallRoom
            ? [557, 641, 709, 773]
            : [1116, 1188, 1277, 1356]
        let baseAllpass: [Float] = smallRoom
            ? [225, 341]
            : [556, 441]
        // Higher feedback → longer tail; small room decays quicker.
        let feedbackBase: Float = smallRoom ? 0.62 : 0.82

        var cBufs: [UnsafeMutablePointer<Float>] = []
        var cSizes: [Int] = []
        var cWrite: [Int] = []
        var cFeedback: [Float] = []
        for (i, base) in baseCombs.enumerated() {
            let size = max(4, Int((base * srScale).rounded()))
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: size)
            ptr.initialize(repeating: 0, count: size)
            cBufs.append(ptr)
            cSizes.append(size)
            cWrite.append(0)
            // Slight stagger so combs don't ring in unison.
            cFeedback.append(feedbackBase - Float(i) * 0.02)
        }
        combBuffers = cBufs
        combSizes = cSizes
        combWrite = cWrite
        combFeedback = cFeedback

        var aBufs: [UnsafeMutablePointer<Float>] = []
        var aSizes: [Int] = []
        var aWrite: [Int] = []
        for base in baseAllpass {
            let size = max(4, Int((base * srScale).rounded()))
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: size)
            ptr.initialize(repeating: 0, count: size)
            aBufs.append(ptr)
            aSizes.append(size)
            aWrite.append(0)
        }
        allpassBuffers = aBufs
        allpassSizes = aSizes
        allpassWrite = aWrite
    }

    deinit {
        for (i, buf) in combBuffers.enumerated() {
            buf.deinitialize(count: combSizes[i])
            buf.deallocate()
        }
        for (i, buf) in allpassBuffers.enumerated() {
            buf.deinitialize(count: allpassSizes[i])
            buf.deallocate()
        }
    }

    public func clear() {
        for (i, buf) in combBuffers.enumerated() {
            buf.update(repeating: 0, count: combSizes[i])
            combWrite[i] = 0
        }
        for (i, buf) in allpassBuffers.enumerated() {
            buf.update(repeating: 0, count: allpassSizes[i])
            allpassWrite[i] = 0
        }
    }

    @inline(__always)
    public func process(_ input: Float) -> Float {
        // Parallel combs → sum, then series allpass diffusion.
        var combSum: Float = 0
        let invN = 1 / Float(combBuffers.count)
        for i in 0..<combBuffers.count {
            let size = combSizes[i]
            let wi = combWrite[i]
            let delayed = combBuffers[i][wi]
            combBuffers[i][wi] = input + delayed * combFeedback[i]
            combWrite[i] = (wi + 1) % size
            combSum += delayed
        }
        var wet = combSum * invN

        for i in 0..<allpassBuffers.count {
            let size = allpassSizes[i]
            let wi = allpassWrite[i]
            let bufOut = allpassBuffers[i][wi]
            let g = allpassGain
            let newVal = wet + bufOut * g
            allpassBuffers[i][wi] = newVal
            allpassWrite[i] = (wi + 1) % size
            wet = bufOut - newVal * g
        }

        let wetAmt = wetDryMix / 100
        return input * (1 - wetAmt) + wet * wetAmt
    }
}
