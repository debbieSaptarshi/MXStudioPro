import Foundation

/// Fixed-capacity fractional delay line with linear interpolation.
///
/// Capacity is allocated once at init; `process` never allocates, which is what
/// lets it run inside a render block.
public final class MXDelayLine: @unchecked Sendable {
    private var buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex: Int = 0
    private var sampleRate: Double

    /// Smoothed so moving the delay-time control does not produce a pitch jump.
    private var smoothedDelay: MXSmoothedParameter
    private var targetDelaySamples: Float

    public var feedback: Float = 0
    public var mix: Float = 0.5

    public init(maxDelaySeconds: Float = 2.0, sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        capacity = max(1, Int(Float(sampleRate) * maxDelaySeconds) + 4)
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        targetDelaySamples = Float(sampleRate) * 0.25
        smoothedDelay = MXSmoothedParameter(initial: targetDelaySamples,
                                            smoothingMs: 50,
                                            sampleRate: sampleRate)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    public func setDelay(milliseconds: Float) {
        let samples = Float(sampleRate) * milliseconds / 1000
        targetDelaySamples = min(max(samples, 1), Float(capacity - 2))
    }

    public func clear() {
        buffer.update(repeating: 0, count: capacity)
        writeIndex = 0
        smoothedDelay.reset(to: targetDelaySamples)
    }

    @inline(__always)
    public func process(_ input: Float) -> Float {
        let delay = smoothedDelay.next(target: targetDelaySamples)

        var readPos = Float(writeIndex) - delay
        while readPos < 0 { readPos += Float(capacity) }

        let i0 = Int(readPos) % capacity
        let i1 = (i0 + 1) % capacity
        let frac = readPos - Float(Int(readPos))
        let delayed = buffer[i0] * (1 - frac) + buffer[i1] * frac

        buffer[writeIndex] = input + delayed * feedback
        writeIndex = (writeIndex + 1) % capacity

        return input * (1 - mix) + delayed * mix
    }
}
