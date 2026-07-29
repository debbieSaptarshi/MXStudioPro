import Foundation
import QuartzCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Display-link polling of the transport playhead.
///
/// This is the only sanctioned way for UI to learn the play position. The audio
/// thread publishes an atomic and never calls back into the UI, which keeps the
/// render thread free of Swift runtime work and keeps the UI free of audio
/// priority inversions.
@MainActor
public final class MXPlayheadObserver {

    public struct Readout: Equatable, Sendable {
        public var sample: Int64
        public var seconds: Double
        public var beat: Double
        public var position: MXMusicalPosition
        public var state: MXTransport.State
    }

    private let transport: MXTransport
    private var displayLink: CADisplayLink?
    private var handler: ((Readout) -> Void)?
    private var fallbackTimer: Timer?

    public private(set) var latest: Readout

    public init(transport: MXTransport) {
        self.transport = transport
        latest = Readout(sample: 0, seconds: 0, beat: 0,
                         position: MXMusicalPosition(bar: 1, beat: 1),
                         state: .stopped)
    }

    deinit {
        displayLink?.invalidate()
        fallbackTimer?.invalidate()
    }

    /// - Parameter preferredFPS: the transport readout does not need 120 Hz;
    ///   30 is smooth and leaves headroom for the audio thread.
    public func start(preferredFPS: Int = 30, _ handler: @escaping (Readout) -> Void) {
        stop()
        self.handler = handler

        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15,
                                                        maximum: Float(preferredFPS),
                                                        preferred: Float(preferredFPS))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #elseif canImport(AppKit)
        if let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            // Headless (CI, unit tests): no screen to drive a display link.
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(preferredFPS),
                                                 repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        #endif
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        handler = nil
    }

    /// Exposed so tests can pump a readout without a display server.
    @objc public func tick() {
        let sample = transport.currentSample
        let beat = transport.tempoMap.beat(forSample: sample, sampleRate: transport.sampleRate)
        let readout = Readout(sample: sample,
                              seconds: Double(sample) / transport.sampleRate,
                              beat: beat,
                              position: transport.tempoMap.position(forBeat: beat),
                              state: transport.state)
        latest = readout
        handler?(readout)
    }
}
