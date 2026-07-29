import AVFoundation
import Foundation
import MXAudioCore
import MXAudioDSP

public struct MXRenderResult: Sendable {
    public var left: [Float]
    public var right: [Float]
    public var sampleRate: Double

    public var frameCount: Int { left.count }

    /// Channel sum, which is what most level assertions want.
    public var mono: [Float] {
        guard right.count == left.count else { return left }
        return zip(left, right).map { ($0 + $1) * 0.5 }
    }

    public func slice(fromSeconds start: Double, toSeconds end: Double) -> MXRenderResult {
        let from = max(0, Int(start * sampleRate))
        let to = min(left.count, Int(end * sampleRate))
        guard from < to else {
            return MXRenderResult(left: [], right: [], sampleRate: sampleRate)
        }
        return MXRenderResult(left: Array(left[from..<to]),
                              right: Array(right[from..<to]),
                              sampleRate: sampleRate)
    }
}

/// An action to run at an exact point during an offline render.
///
/// The renderer stops at the requested frame, runs the action, then continues,
/// which is what makes "insert an effect 200 ms in" reproducible rather than
/// dependent on wall-clock timing.
public struct MXScheduledAction {
    public var atSeconds: Double
    public var action: () -> Void

    public init(at seconds: Double, _ action: @escaping () -> Void) {
        self.atSeconds = seconds
        self.action = action
    }
}

/// Deterministic offline renderer.
///
/// Everything in the golden-audio layer runs through here so a rendered result
/// depends only on the graph, never on scheduling luck.
public final class MXOfflineRenderer {

    public let graph: MXGraph
    public private(set) var sampleRate: Double
    private let blockFrames: AVAudioFrameCount

    public init(graph: MXGraph,
                sampleRate: Double = 48_000,
                blockFrames: AVAudioFrameCount = 512) {
        self.graph = graph
        self.sampleRate = sampleRate
        self.blockFrames = blockFrames
    }

    public func prepare() throws {
        try graph.prepare(mode: .offline(sampleRate: sampleRate, maximumFrameCount: blockFrames))
        try graph.start()
    }

    @discardableResult
    public func render(seconds: Double,
                       actions: [MXScheduledAction] = []) throws -> MXRenderResult {
        guard graph.engine.isRunning else {
            throw MXAudioError.invalidState("offline renderer used before start()")
        }

        let totalFrames = Int(seconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat,
                                            frameCapacity: blockFrames) else {
            throw MXAudioError.invalidState("could not allocate render buffer")
        }

        var left = [Float]()
        var right = [Float]()
        left.reserveCapacity(totalFrames)
        right.reserveCapacity(totalFrames)

        let pending = actions
            .map { (frame: Int($0.atSeconds * sampleRate), action: $0.action) }
            .sorted { $0.frame < $1.frame }
        var actionIndex = 0
        var rendered = 0

        while rendered < totalFrames {
            while actionIndex < pending.count, pending[actionIndex].frame <= rendered {
                pending[actionIndex].action()
                actionIndex += 1
            }

            // Never render past the next action, so it lands on the frame it
            // was scheduled for rather than at the next block boundary.
            var want = min(Int(blockFrames), totalFrames - rendered)
            if actionIndex < pending.count {
                want = min(want, max(1, pending[actionIndex].frame - rendered))
            }

            let status = try graph.engine.renderOffline(AVAudioFrameCount(want), to: buffer)
            guard status == .success, buffer.frameLength > 0 else { break }

            let frames = Int(buffer.frameLength)
            if let channels = buffer.floatChannelData {
                left.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: frames))
                if buffer.format.channelCount > 1 {
                    right.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: frames))
                }
            }
            rendered += frames
        }

        // Run any actions scheduled past the render window so a test can assert
        // on their side effects.
        while actionIndex < pending.count {
            pending[actionIndex].action()
            actionIndex += 1
        }

        if right.isEmpty { right = left }
        return MXRenderResult(left: left, right: right, sampleRate: sampleRate)
    }

    public func stop() {
        graph.stop()
    }
}
