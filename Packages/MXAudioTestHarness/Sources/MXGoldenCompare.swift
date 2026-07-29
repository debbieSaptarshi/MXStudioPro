import AVFoundation
import Foundation
import MXAudioDSP

/// Compares a render against a committed golden file.
///
/// Tolerances default to the plan's numbers: ±1.5 dB RMS and ±2 samples of
/// onset. A golden file changes only with a PR note explaining the sonic
/// difference, so the comparison is deliberately strict enough to notice.
public enum MXGoldenCompare {

    public struct Tolerance: Sendable {
        public var rmsDB: Float
        public var peakDB: Float
        public var onsetSamples: Int

        public init(rmsDB: Float = 1.5, peakDB: Float = 2.0, onsetSamples: Int = 2) {
            self.rmsDB = rmsDB
            self.peakDB = peakDB
            self.onsetSamples = onsetSamples
        }

        public static let `default` = Tolerance()
    }

    public struct Result: Sendable {
        public var passed: Bool
        public var rmsDeltaDB: Float
        public var peakDeltaDB: Float
        public var onsetDeltaSamples: Int
        public var message: String
    }

    /// Set `MX_REGENERATE_GOLDENS=1` to rewrite goldens instead of asserting.
    /// The rewritten files must be reviewed in the PR diff.
    public static var isRegenerating: Bool {
        ProcessInfo.processInfo.environment["MX_REGENERATE_GOLDENS"] == "1"
    }

    public static func compare(_ rendered: [Float],
                               againstGoldenAt url: URL,
                               tolerance: Tolerance = .default,
                               sampleRate: Double = 48_000) throws -> Result {
        if isRegenerating || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try MXFixtureFactory.writeWAV(rendered, to: url, sampleRate: sampleRate)
            return Result(passed: true, rmsDeltaDB: 0, peakDeltaDB: 0, onsetDeltaSamples: 0,
                          message: "golden written to \(url.lastPathComponent)")
        }

        let golden = try MXFixtureFactory.readWAV(url)
        return compare(rendered, against: golden, tolerance: tolerance, label: url.lastPathComponent)
    }

    public static func compare(_ rendered: [Float],
                               against golden: [Float],
                               tolerance: Tolerance = .default,
                               label: String = "golden") -> Result {
        guard !rendered.isEmpty, !golden.isEmpty else {
            return Result(passed: false, rmsDeltaDB: .infinity, peakDeltaDB: .infinity,
                          onsetDeltaSamples: .max,
                          message: "\(label): one side is empty (rendered=\(rendered.count), golden=\(golden.count))")
        }

        let rmsDelta = abs(MXAudioAnalysis.rmsDB(rendered) - MXAudioAnalysis.rmsDB(golden))
        let peakDelta = abs(MXAudioAnalysis.peakDB(rendered) - MXAudioAnalysis.peakDB(golden))

        let renderedOnset = MXAudioAnalysis.detectOnsets(rendered).first ?? 0
        let goldenOnset = MXAudioAnalysis.detectOnsets(golden).first ?? 0
        let onsetDelta = abs(renderedOnset - goldenOnset)

        let passed = rmsDelta <= tolerance.rmsDB
            && peakDelta <= tolerance.peakDB
            && onsetDelta <= tolerance.onsetSamples

        let message = passed
            ? "\(label): match"
            : """
              \(label): mismatch \
              (RMS Δ \(String(format: "%.2f", rmsDelta)) dB > \(tolerance.rmsDB), \
              peak Δ \(String(format: "%.2f", peakDelta)) dB > \(tolerance.peakDB), \
              onset Δ \(onsetDelta) samples > \(tolerance.onsetSamples))
              """

        return Result(passed: passed,
                      rmsDeltaDB: rmsDelta,
                      peakDeltaDB: peakDelta,
                      onsetDeltaSamples: onsetDelta,
                      message: message)
    }
}
