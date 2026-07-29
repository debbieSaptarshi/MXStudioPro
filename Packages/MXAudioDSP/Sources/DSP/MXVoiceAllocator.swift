import Foundation

/// Tracks which voice slots are in use, steals the oldest when the polyphony
/// cap is hit, and resolves choke groups.
///
/// Shared by the synth and the SFZ sampler so voice-stealing behaviour (plan
/// scenario I-04) and choke behaviour (D-02) are implemented once.
///
/// All operations run on the render thread: fixed-size storage, no allocation,
/// no locks.
public final class MXVoiceAllocator: @unchecked Sendable {
    public struct Slot {
        public var note: UInt8 = 0
        public var channel: UInt8 = 0
        public var chokeGroup: Int32 = -1
        public var age: UInt64 = 0
        public var isActive: Bool = false
        /// Set on note-off; the voice keeps rendering its release tail but is
        /// preferred for stealing over a held voice.
        public var isReleasing: Bool = false
    }

    private var slots: [Slot]
    private var counter: UInt64 = 0
    public private(set) var capacity: Int

    /// Highest capacity the allocator can be raised to without reallocating.
    public let maxCapacity: Int

    public init(capacity: Int = 16, maxCapacity: Int = 128) {
        self.maxCapacity = max(capacity, maxCapacity)
        self.capacity = min(capacity, self.maxCapacity)
        slots = Array(repeating: Slot(), count: self.maxCapacity)
    }

    /// Changing polyphony from the control thread. Voices above the new cap are
    /// reported so the caller can silence them.
    public func setCapacity(_ newValue: Int, onEvict: (Int) -> Void) {
        let clamped = min(max(1, newValue), maxCapacity)
        if clamped < capacity {
            for i in clamped..<capacity where slots[i].isActive {
                slots[i] = Slot()
                onEvict(i)
            }
        }
        capacity = clamped
    }

    public var activeVoiceCount: Int {
        var n = 0
        for i in 0..<capacity where slots[i].isActive { n += 1 }
        return n
    }

    public func slot(at index: Int) -> Slot {
        slots[index]
    }

    /// Returns the voice index to use, stealing if necessary.
    ///
    /// Preference order for stealing: a free slot, then the oldest releasing
    /// voice, then the oldest voice overall.
    public func allocate(note: UInt8, channel: UInt8, chokeGroup: Int32 = -1) -> Int {
        counter &+= 1

        var chosen = -1
        for i in 0..<capacity where !slots[i].isActive {
            chosen = i
            break
        }

        if chosen < 0 {
            var oldestReleasing = -1
            var oldestReleasingAge = UInt64.max
            var oldest = -1
            var oldestAge = UInt64.max

            for i in 0..<capacity {
                let s = slots[i]
                if s.isReleasing, s.age < oldestReleasingAge {
                    oldestReleasingAge = s.age
                    oldestReleasing = i
                }
                if s.age < oldestAge {
                    oldestAge = s.age
                    oldest = i
                }
            }
            chosen = oldestReleasing >= 0 ? oldestReleasing : oldest
        }

        slots[chosen] = Slot(note: note,
                             channel: channel,
                             chokeGroup: chokeGroup,
                             age: counter,
                             isActive: true,
                             isReleasing: false)
        return chosen
    }

    /// Marks matching voices as releasing and reports them. A note can be
    /// sounding on more than one voice after a re-trigger, so all matches fire.
    public func release(note: UInt8, channel: UInt8, _ body: (Int) -> Void) {
        for i in 0..<capacity {
            guard slots[i].isActive,
                  !slots[i].isReleasing,
                  slots[i].note == note,
                  slots[i].channel == channel else { continue }
            slots[i].isReleasing = true
            body(i)
        }
    }

    /// Reports every voice in `group` other than `excluding`, so a closed hi-hat
    /// can cut a ringing open hi-hat.
    public func chokeGroup(_ group: Int32, excluding: Int, _ body: (Int) -> Void) {
        guard group >= 0 else { return }
        for i in 0..<capacity {
            guard i != excluding,
                  slots[i].isActive,
                  slots[i].chokeGroup == group else { continue }
            slots[i].isReleasing = true
            body(i)
        }
    }

    public func releaseAll(_ body: (Int) -> Void) {
        for i in 0..<capacity where slots[i].isActive && !slots[i].isReleasing {
            slots[i].isReleasing = true
            body(i)
        }
    }

    /// Called once a voice's envelope has fully decayed.
    public func recycle(_ index: Int) {
        slots[index] = Slot()
    }

    public func reset() {
        for i in 0..<maxCapacity { slots[i] = Slot() }
        counter = 0
    }
}
