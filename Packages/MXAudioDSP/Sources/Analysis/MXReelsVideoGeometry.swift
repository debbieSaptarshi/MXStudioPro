import Foundation

/// Pure helpers for CapCut / Instagram Reels 9:16 video export (Week 78).
///
/// Kept free of AVFoundation so Linux CI can unit-test frame math.
public enum MXReelsVideoGeometry: Sendable {
    public struct Size: Sendable, Equatable, Hashable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        /// Default Reels lite (keeps frame count bounded).
        public static let reels720 = Size(width: 720, height: 1280)
        /// Full HD Reels.
        public static let reels1080 = Size(width: 1080, height: 1920)

        public var aspectRatio: Double {
            guard height > 0 else { return 0 }
            return Double(width) / Double(height)
        }
    }

    public static let defaultFPS: Double = 24
    public static let maxDurationSeconds: Double = 90

    /// Even dimensions required for H.264.
    public static func isValidEvenSize(_ size: Size) -> Bool {
        size.width > 0 && size.height > 0
            && size.width % 2 == 0
            && size.height % 2 == 0
    }

    /// Clamp mix length for phone Reels (Instagram/TikTok lite).
    public static func clampedDuration(_ seconds: Double, maxSeconds: Double = maxDurationSeconds) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(max(seconds, 0), max(0, maxSeconds))
    }

    /// Frame count for a duration at `fps` (at least 1 when duration > 0).
    public static func frameCount(durationSeconds: Double, fps: Double = defaultFPS) -> Int {
        let duration = clampedDuration(durationSeconds)
        let rate = max(1, fps)
        guard duration > 0 else { return 0 }
        return max(1, Int((duration * rate).rounded(.up)))
    }

    /// Presentation time in seconds for a zero-based frame index.
    public static func presentationTime(frame: Int, fps: Double = defaultFPS) -> Double {
        let rate = max(1, fps)
        return Double(max(0, frame)) / rate
    }

    /// True when size is roughly 9:16 (portrait Reels).
    public static func isPortraitReelsAspect(_ size: Size, tolerance: Double = 0.02) -> Bool {
        guard size.height > 0 else { return false }
        let target = 9.0 / 16.0
        return abs(size.aspectRatio - target) <= tolerance
    }
}
