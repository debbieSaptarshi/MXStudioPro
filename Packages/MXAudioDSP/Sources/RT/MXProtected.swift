import Foundation
import os

/// Mutex-protected value for control-thread state.
///
/// Uses `OSAllocatedUnfairLock` rather than `NSLock` because backends mutate
/// this state from `async` loading code, where `NSLock.lock()` is diagnosed as
/// unsafe (it can block a cooperative thread pool worker).
///
/// Never use this on the render thread — that state belongs in
/// `MXParameterStore` or `MXEventRing`.
public struct MXProtected<Value: Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<Value>

    public init(_ initialValue: Value) {
        storage = OSAllocatedUnfairLock(initialState: initialValue)
    }

    public var value: Value {
        get { storage.withLock { $0 } }
        nonmutating set { storage.withLock { $0 = newValue } }
    }

    public func withLock<T: Sendable>(_ body: @Sendable (inout Value) throws -> T) rethrows -> T {
        try storage.withLock(body)
    }
}
