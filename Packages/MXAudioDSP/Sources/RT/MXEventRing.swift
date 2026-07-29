import Foundation
import Synchronization

/// A MIDI-ish event crossing into the render thread. Deliberately a trivial
/// value type so it can live in preallocated storage.
public struct MXVoiceEvent: Sendable {
    public enum Kind: UInt8, Sendable {
        case noteOn
        case noteOff
        case allNotesOff
        case choke
    }

    public var kind: Kind
    public var note: UInt8
    public var velocity: UInt8
    public var channel: UInt8
    /// Offset in frames from the start of the block, for sample-accurate timing.
    public var frameOffset: Int32
    /// Choke group for drum lanes; -1 when unused.
    public var chokeGroup: Int32

    public init(kind: Kind,
                note: UInt8 = 0,
                velocity: UInt8 = 0,
                channel: UInt8 = 0,
                frameOffset: Int32 = 0,
                chokeGroup: Int32 = -1) {
        self.kind = kind
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.frameOffset = frameOffset
        self.chokeGroup = chokeGroup
    }
}

/// Single-producer / single-consumer lock-free ring.
///
/// The control thread pushes; the render thread pops. Indices are atomic with
/// acquire/release ordering so the consumer never observes a slot before its
/// payload is visible. Storage is allocated once — `push` and `pop` never
/// allocate, lock, or call into the Swift runtime.
public final class MXEventRing: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<MXVoiceEvent>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    /// Incremented when a push is dropped because the ring is full. Surfaced in
    /// diagnostics so a silent note is always explainable.
    private let dropCount = Atomic<Int>(0)

    /// - Parameter capacity: rounded up to a power of two so the wrap is a mask.
    public init(capacity: Int = 1024) {
        var c = 1
        while c < capacity { c <<= 1 }
        self.capacity = c
        self.mask = c - 1
        storage = .allocate(capacity: c)
        storage.initialize(repeating: MXVoiceEvent(kind: .noteOff), count: c)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    public var droppedEvents: Int { dropCount.load(ordering: .relaxed) }

    /// Producer side. Returns false when the ring is full rather than blocking.
    @discardableResult
    public func push(_ event: MXVoiceEvent) -> Bool {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        if w - r >= capacity {
            dropCount.add(1, ordering: .relaxed)
            return false
        }
        storage[w & mask] = event
        writeIndex.store(w + 1, ordering: .releasing)
        return true
    }

    /// Consumer side. Safe on the render thread.
    @inline(__always)
    public func pop() -> MXVoiceEvent? {
        let r = readIndex.load(ordering: .relaxed)
        let w = writeIndex.load(ordering: .acquiring)
        if r == w { return nil }
        let event = storage[r & mask]
        readIndex.store(r + 1, ordering: .releasing)
        return event
    }

    public func drain() {
        readIndex.store(writeIndex.load(ordering: .acquiring), ordering: .releasing)
    }
}
