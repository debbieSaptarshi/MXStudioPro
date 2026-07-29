import Foundation
import Synchronization

/// Parameter transport between the control thread and the render thread.
///
/// Backing storage is a single aligned `Float` allocation made once at init.
/// Aligned 32-bit loads and stores are indivisible on every architecture we
/// ship to, so a reader can never observe a torn value, and each parameter is
/// independent so cross-parameter ordering is not a correctness concern.
///
/// Values are additionally smoothed by `MXSmoothedParameter` before they reach
/// the DSP, which is what keeps parameter sweeps free of zipper noise (plan
/// scenario FX-06).
public final class MXParameterStore: @unchecked Sendable {
    private static let slotIndex: [UInt64: Int] = {
        var map: [UInt64: Int] = [:]
        for (i, id) in MXParamID.allCases.enumerated() {
            map[id.rawValue] = i
        }
        return map
    }()

    private let storage: UnsafeMutablePointer<Float>
    private let count: Int

    public init() {
        count = MXParamID.allCases.count
        storage = .allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
        for id in MXParamID.allCases {
            if let i = Self.slotIndex[id.rawValue] {
                storage[i] = Self.defaultValue(for: id)
            }
        }
    }

    deinit {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    /// Safe to call from the render thread: no locks, no allocation.
    @inline(__always)
    public func value(_ id: MXParamID) -> Float {
        guard let i = Self.slotIndex[id.rawValue] else { return 0 }
        return storage[i]
    }

    /// Called from the control thread. Clamped so out-of-range UI values can
    /// never reach the DSP.
    public func set(_ id: MXParamID, _ value: Float) {
        guard let i = Self.slotIndex[id.rawValue] else { return }
        storage[i] = id.clamp(value)
    }

    public func snapshot() -> [UInt64: Float] {
        var out: [UInt64: Float] = [:]
        for id in MXParamID.allCases {
            out[id.rawValue] = value(id)
        }
        return out
    }

    public func restore(_ values: [UInt64: Float]) {
        for (raw, v) in values {
            guard let id = MXParamID(rawValue: raw) else { continue }
            set(id, v)
        }
    }

    private static func defaultValue(for id: MXParamID) -> Float {
        switch id {
        case .volume, .ampMaster, .osc1Level:
            return 1.0
        case .filterCutoff:
            return 20_000
        case .ampSustain:
            return 1.0
        case .ampRelease:
            return 0.1
        case .subOctave:
            return 1
        default:
            return 0
        }
    }
}

/// One-pole smoother applied per render block. Without this, a parameter jump
/// produces a discontinuity that reads as a click.
public struct MXSmoothedParameter {
    public private(set) var current: Float
    private var coefficient: Float

    public init(initial: Float = 0, smoothingMs: Float = 12, sampleRate: Double = 48_000) {
        current = initial
        let samples = max(1, Float(sampleRate) * smoothingMs / 1000)
        coefficient = 1 - exp(-1 / samples)
    }

    public mutating func setSmoothingTime(_ ms: Float, sampleRate: Double) {
        let samples = max(1, Float(sampleRate) * ms / 1000)
        coefficient = 1 - exp(-1 / samples)
    }

    /// Jump without ramping. Only valid when no voice is sounding.
    public mutating func reset(to value: Float) {
        current = value
    }

    @inline(__always)
    public mutating func next(target: Float) -> Float {
        current += (target - current) * coefficient
        return current
    }
}
