import AVFoundation
import Foundation
import MXAudioDSP

#if canImport(UIKit)
import UIKit
#endif

/// Wraps `AVAudioSession` on iOS and degrades to a no-op on macOS, so the rest
/// of the engine never needs `#if os(...)`.
///
/// Also owns interruption and route-change handling, which scenario G-08
/// depends on: an interruption must not lose transport state.
public final class MXAudioSession: @unchecked Sendable {

    public struct Configuration: Sendable {
        public var sampleRate: Double
        /// Small buffers cut latency but raise the dropout risk. 256 frames at
        /// 48 kHz is ~5.3 ms, which is the usual sweet spot for a mobile DAW.
        public var preferredIOBufferFrames: Int
        public var enablesInput: Bool
        public var allowsBluetooth: Bool
        /// When set (e.g. `1` for vocal mono), asked of `AVAudioSession` on activate
        /// and before record. Hardware may still deliver stereo; the recorder
        /// downmixes when mono is preferred.
        public var preferredInputChannelCount: Int?

        public init(sampleRate: Double = 48_000,
                    preferredIOBufferFrames: Int = 256,
                    enablesInput: Bool = true,
                    allowsBluetooth: Bool = true,
                    preferredInputChannelCount: Int? = nil) {
            self.sampleRate = sampleRate
            self.preferredIOBufferFrames = preferredIOBufferFrames
            self.enablesInput = enablesInput
            self.allowsBluetooth = allowsBluetooth
            self.preferredInputChannelCount = preferredInputChannelCount
        }

        public static let studio = Configuration()
        /// Playback-only, used by the player screens where no mic is needed.
        public static let playbackOnly = Configuration(enablesInput: false)
    }

    public enum Event: Sendable {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case routeChanged
        case mediaServicesReset
    }

    public private(set) var configuration: Configuration
    public var onEvent: (@Sendable (Event) -> Void)?

    private var observers: [NSObjectProtocol] = []

    public init(configuration: Configuration = .studio) {
        self.configuration = configuration
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Actual sample rate granted by the OS, which can differ from the request.
    public var actualSampleRate: Double {
        #if os(iOS)
        return AVAudioSession.sharedInstance().sampleRate
        #else
        return configuration.sampleRate
        #endif
    }

    public var actualIOBufferDuration: Double {
        #if os(iOS)
        return AVAudioSession.sharedInstance().ioBufferDuration
        #else
        return Double(configuration.preferredIOBufferFrames) / configuration.sampleRate
        #endif
    }

    /// Full input+output latency reported by the OS. The calibrator refines
    /// this, but it is the right starting estimate.
    public var reportedRoundTripLatency: Double {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        return session.inputLatency + session.outputLatency + session.ioBufferDuration
        #else
        return actualIOBufferDuration * 2
        #endif
    }

    public func activate(_ configuration: Configuration? = nil) throws {
        if let configuration { self.configuration = configuration }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
            if self.configuration.allowsBluetooth {
                // HFP for mic-capable BT; A2DP alone is output-only and can
                // zero out the input format on some routes / Simulator.
                if self.configuration.enablesInput {
                    options.insert(.allowBluetooth)
                }
                options.insert(.allowBluetoothA2DP)
            }
            try session.setCategory(self.configuration.enablesInput ? .playAndRecord : .playback,
                                    mode: self.configuration.enablesInput ? .default : .measurement,
                                    options: options)
            try session.setPreferredSampleRate(self.configuration.sampleRate)
            try session.setPreferredIOBufferDuration(
                Double(self.configuration.preferredIOBufferFrames) / self.configuration.sampleRate)
            if let channels = self.configuration.preferredInputChannelCount, channels > 0 {
                // Best-effort: many built-in mics already report 1 channel; stereo
                // interfaces may ignore this. Recorder still downmixes when asked.
                try? session.setPreferredInputNumberOfChannels(channels)
            }
            try session.setActive(true)
        } catch {
            throw MXAudioError.engineStartFailed("audio session: \(error.localizedDescription)")
        }
        installObservers()
        #endif
    }

    /// Best-effort mono/stereo preference before a take. No-op off iOS.
    /// Callers that need a mono file should also pass `preferMono` to the recorder.
    public func preferInputChannelCount(_ count: Int) {
        configuration.preferredInputChannelCount = count
        #if os(iOS)
        guard count > 0 else { return }
        try? AVAudioSession.sharedInstance().setPreferredInputNumberOfChannels(count)
        #endif
    }

    public func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    /// True when recording is actually permitted. Callers should surface a
    /// typed error rather than recording silence.
    public func hasInputPermission() -> Bool {
        #if os(iOS)
        return AVAudioApplication.shared.recordPermission == .granted
        #else
        return true
        #endif
    }

    private func installObservers() {
        #if os(iOS)
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.onEvent?(.interruptionBegan)
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                self.onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
            @unknown default:
                break
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.onEvent?(.routeChanged)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            self?.onEvent?(.mediaServicesReset)
        })
        #endif
    }
}
