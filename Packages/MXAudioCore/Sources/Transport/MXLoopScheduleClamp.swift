import Foundation

/// Caps clip-player schedules so wall-clock audio stops at the transport loop end.
///
/// `MXTransport.wrapForLoop` only wraps the playhead. Scheduled `AVAudioPlayerNode`
/// segments keep playing on host time past the loop boundary unless frame counts
/// are clamped here (GarageBand / Logic loop region behaviour).
public enum MXLoopScheduleClamp: Sendable {

    /// Returns frames to schedule from `audibleStartSample`, capped at `loopEndSample`.
    ///
    /// - Parameters:
    ///   - requestedFrames: Frames about to be scheduled from `audibleStartSample`.
    ///   - audibleStartSample: First sample that will sound (`max(playhead, clipStart)`).
    ///   - loopEndSample: Absolute sample of the loop end (exclusive).
    ///   - loopEnabled: When false, returns `max(0, requestedFrames)` unchanged.
    public static func clampFrameCount(
        requestedFrames: Int64,
        audibleStartSample: Int64,
        loopEndSample: Int64,
        loopEnabled: Bool
    ) -> Int64 {
        let requested = max(Int64(0), requestedFrames)
        guard loopEnabled else { return requested }
        if audibleStartSample >= loopEndSample { return 0 }
        let maxToLoop = loopEndSample - audibleStartSample
        return min(requested, max(Int64(0), maxToLoop))
    }
}
