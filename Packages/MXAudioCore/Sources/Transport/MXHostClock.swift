import AVFoundation
import Foundation

/// `mach_absolute_time` conversions.
///
/// The plan makes hostTime the canonical clock rather than `sampleTime`,
/// because the input and output nodes report sample times from different
/// origins — anchoring on either one makes recorded takes drift.
public enum MXHostClock {

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    @inline(__always)
    public static var now: UInt64 {
        mach_absolute_time()
    }

    @inline(__always)
    public static func seconds(fromHostTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    @inline(__always)
    public static func hostTicks(fromSeconds seconds: Double) -> UInt64 {
        let nanos = seconds * 1_000_000_000.0
        return UInt64((nanos * Double(timebase.denom) / Double(timebase.numer)).rounded())
    }

    /// Signed elapsed time, so a caller can detect a host time in the past
    /// rather than wrapping into a huge unsigned value.
    @inline(__always)
    public static func elapsedSeconds(since anchor: UInt64, to now: UInt64 = MXHostClock.now) -> Double {
        if now >= anchor {
            return seconds(fromHostTicks: now - anchor)
        } else {
            return -seconds(fromHostTicks: anchor - now)
        }
    }

    /// Builds the `AVAudioTime` used to schedule a buffer at an absolute
    /// position, which is the sample-accurate scheduling path.
    public static func audioTime(hostTime: UInt64,
                                 sampleTime: AVAudioFramePosition,
                                 sampleRate: Double) -> AVAudioTime {
        AVAudioTime(hostTime: hostTime, sampleTime: sampleTime, atRate: sampleRate)
    }
}
