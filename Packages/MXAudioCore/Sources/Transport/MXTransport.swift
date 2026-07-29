import AVFoundation
import Foundation
import Synchronization

/// Project playhead and play/record state.
///
/// The playhead is an `Atomic<Int64>` sample position. The audio thread writes
/// it and the UI polls it from a display link; the audio thread never calls
/// into SwiftUI and the UI never takes a lock the audio thread could contend on.
///
/// Two clock sources share one interface:
/// - **realtime** extrapolates from a hostTime anchor, so a late or coalesced
///   render callback does not make the playhead stutter.
/// - **offline** advances only when the render callback says frames were
///   produced, which is what makes bounce and the golden-audio suite
///   deterministic.
public final class MXTransport: @unchecked Sendable {

    public enum State: Int, Sendable {
        case stopped = 0
        case playing = 1
        case recording = 2
    }

    public enum ClockSource: Sendable {
        case realtime
        case offline
    }

    public struct LoopRegion: Equatable, Sendable {
        public var startBeat: Double
        public var endBeat: Double
        public var isEnabled: Bool

        public init(startBeat: Double, endBeat: Double, isEnabled: Bool = true) {
            self.startBeat = startBeat
            self.endBeat = max(endBeat, startBeat)
            self.isEnabled = isEnabled
        }
    }

    public let tempoMap: MXTempoMap
    public private(set) var sampleRate: Double
    public var clockSource: ClockSource

    /// Written by the audio thread, read by the UI.
    private let playhead = Atomic<Int64>(0)
    private let rawState = Atomic<Int>(State.stopped.rawValue)

    /// hostTime anchor captured at the moment playback started.
    private let anchorHostTime = Atomic<UInt64>(0)
    private let anchorSample = Atomic<Int64>(0)

    private var loopRegion: LoopRegion?
    private let controlLock = NSLock()

    /// Fired on transport state changes so UI can react without polling.
    public var onStateChange: (@Sendable (State) -> Void)?

    public init(tempoMap: MXTempoMap = MXTempoMap(),
                sampleRate: Double = 48_000,
                clockSource: ClockSource = .realtime) {
        self.tempoMap = tempoMap
        self.sampleRate = sampleRate
        self.clockSource = clockSource
    }

    public func setSampleRate(_ rate: Double) {
        controlLock.lock()
        sampleRate = rate
        controlLock.unlock()
    }

    // MARK: - State

    public var state: State {
        State(rawValue: rawState.load(ordering: .acquiring)) ?? .stopped
    }

    public var isPlaying: Bool {
        let s = state
        return s == .playing || s == .recording
    }

    public var isRecording: Bool { state == .recording }

    // MARK: - Playhead

    /// Safe from any thread. In realtime the value is extrapolated from the
    /// hostTime anchor, so it advances smoothly between render callbacks.
    public var currentSample: Int64 {
        guard isPlaying else { return playhead.load(ordering: .acquiring) }
        switch clockSource {
        case .offline:
            return playhead.load(ordering: .acquiring)
        case .realtime:
            let anchor = anchorHostTime.load(ordering: .acquiring)
            guard anchor != 0 else { return playhead.load(ordering: .acquiring) }
            let elapsed = MXHostClock.elapsedSeconds(since: anchor)
            let base = anchorSample.load(ordering: .acquiring)
            let projected = base + Int64((elapsed * sampleRate).rounded())
            return wrapForLoop(projected)
        }
    }

    public var currentSeconds: Double {
        Double(currentSample) / sampleRate
    }

    public var currentBeat: Double {
        tempoMap.beat(forSample: currentSample, sampleRate: sampleRate)
    }

    public var currentPosition: MXMusicalPosition {
        tempoMap.position(forBeat: currentBeat)
    }

    // MARK: - Commands

    public func play(fromSample sample: Int64? = nil) {
        let start = sample ?? playhead.load(ordering: .acquiring)
        beginPlayback(at: start, state: .playing)
    }

    public func record(fromSample sample: Int64? = nil) {
        let start = sample ?? playhead.load(ordering: .acquiring)
        beginPlayback(at: start, state: .recording)
    }

    private func beginPlayback(at sample: Int64, state newState: State) {
        playhead.store(sample, ordering: .releasing)
        anchorSample.store(sample, ordering: .releasing)
        anchorHostTime.store(MXHostClock.now, ordering: .releasing)
        rawState.store(newState.rawValue, ordering: .releasing)
        onStateChange?(newState)
    }

    /// Stops and leaves the playhead where it landed.
    public func stop() {
        let final = currentSample
        rawState.store(State.stopped.rawValue, ordering: .releasing)
        playhead.store(final, ordering: .releasing)
        anchorHostTime.store(0, ordering: .releasing)
        onStateChange?(.stopped)
    }

    /// Stops and rewinds to the last start point.
    public func stopAndReturn() {
        let origin = anchorSample.load(ordering: .acquiring)
        rawState.store(State.stopped.rawValue, ordering: .releasing)
        playhead.store(origin, ordering: .releasing)
        anchorHostTime.store(0, ordering: .releasing)
        onStateChange?(.stopped)
    }

    public func seek(toSample sample: Int64) {
        let clamped = max(0, sample)
        playhead.store(clamped, ordering: .releasing)
        anchorSample.store(clamped, ordering: .releasing)
        if isPlaying {
            anchorHostTime.store(MXHostClock.now, ordering: .releasing)
        }
    }

    public func seek(toBeat beat: Double) {
        seek(toSample: tempoMap.sample(forBeat: beat, sampleRate: sampleRate))
    }

    public func seek(toBar bar: Int) {
        seek(toSample: tempoMap.sample(forBar: bar, sampleRate: sampleRate))
    }

    // MARK: - Looping

    public var loop: LoopRegion? {
        get { controlLock.lock(); defer { controlLock.unlock() }; return loopRegion }
        set { controlLock.lock(); loopRegion = newValue; controlLock.unlock() }
    }

    private func wrapForLoop(_ sample: Int64) -> Int64 {
        controlLock.lock()
        let region = loopRegion
        controlLock.unlock()

        guard let region, region.isEnabled, region.endBeat > region.startBeat else {
            return sample
        }
        let start = tempoMap.sample(forBeat: region.startBeat, sampleRate: sampleRate)
        let end = tempoMap.sample(forBeat: region.endBeat, sampleRate: sampleRate)
        let length = end - start
        guard length > 0, sample >= end else { return sample }
        return start + ((sample - start) % length)
    }

    // MARK: - Render thread

    /// Offline clock: called by the render callback once per block.
    ///
    /// Render-thread safe: one atomic load, one atomic store, no allocation.
    @inline(__always)
    public func advance(frames: Int) {
        guard isPlaying, clockSource == .offline else { return }
        let next = playhead.load(ordering: .relaxed) + Int64(frames)
        playhead.store(wrapForLoop(next), ordering: .releasing)
    }

    /// Realtime clock: re-anchors from `outputNode.lastRenderTime` so the
    /// playhead tracks the actual audio clock instead of drifting against it.
    public func synchronize(toRenderTime renderTime: AVAudioTime) {
        guard isPlaying, clockSource == .realtime, renderTime.isHostTimeValid else { return }
        let anchor = anchorHostTime.load(ordering: .acquiring)
        guard anchor != 0 else { return }
        let elapsed = MXHostClock.elapsedSeconds(since: anchor, to: renderTime.hostTime)
        let base = anchorSample.load(ordering: .acquiring)
        playhead.store(wrapForLoop(base + Int64((elapsed * sampleRate).rounded())),
                       ordering: .releasing)
    }

    /// Absolute host time at which a future sample position will be heard.
    /// Used to schedule buffers sample-accurately.
    public func hostTime(forSample sample: Int64) -> UInt64 {
        let anchor = anchorHostTime.load(ordering: .acquiring)
        let base = anchorSample.load(ordering: .acquiring)
        guard anchor != 0 else { return MXHostClock.now }
        let delta = Double(sample - base) / sampleRate
        if delta >= 0 {
            return anchor &+ MXHostClock.hostTicks(fromSeconds: delta)
        } else {
            return anchor &- MXHostClock.hostTicks(fromSeconds: -delta)
        }
    }
}
