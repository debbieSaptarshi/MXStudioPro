import Foundation

/// Every failure path in the engine surfaces one of these rather than silently
/// producing empty audio. Section 11.16 of the plan makes that a shipping
/// requirement: a test that hears silence must be able to tell *why*.
public enum MXAudioError: Error, Equatable, Sendable {
    case resourceNotFound(path: String)
    case unsupportedResource(String)
    case soundBankLoadFailed(path: String, underlying: String)
    case sfzParseFailed(reason: String, line: Int)
    case sampleDecodeFailed(path: String, underlying: String)
    case engineStartFailed(String)
    case graphMutationFailed(String)
    case invalidState(String)
    case stateDecodeFailed(String)
    case unknownPackEngine(String)
    case manifestInvalid(reason: String)
    case checksumMismatch(expected: String, actual: String)
    case licenseMissing(packID: String)
    case componentNotFound(String)
    case instantiationFailed(String)
    case exportFailed(String)
    case notSupportedOnPlatform(String)
}

extension MXAudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let path):
            return "Audio resource not found at \(path)"
        case .unsupportedResource(let what):
            return "Unsupported resource: \(what)"
        case .soundBankLoadFailed(let path, let underlying):
            return "Failed to load sound bank \(path): \(underlying)"
        case .sfzParseFailed(let reason, let line):
            return "SFZ parse failed at line \(line): \(reason)"
        case .sampleDecodeFailed(let path, let underlying):
            return "Failed to decode sample \(path): \(underlying)"
        case .engineStartFailed(let why):
            return "Audio engine failed to start: \(why)"
        case .graphMutationFailed(let why):
            return "Graph mutation failed: \(why)"
        case .invalidState(let why):
            return "Invalid engine state: \(why)"
        case .stateDecodeFailed(let why):
            return "Could not decode saved state: \(why)"
        case .unknownPackEngine(let engine):
            return "Unknown pack engine '\(engine)'"
        case .manifestInvalid(let reason):
            return "Pack manifest invalid: \(reason)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch (expected \(expected), got \(actual))"
        case .licenseMissing(let packID):
            return "Pack '\(packID)' has no SPDX license"
        case .componentNotFound(let desc):
            return "Audio component not found: \(desc)"
        case .instantiationFailed(let why):
            return "Audio unit instantiation failed: \(why)"
        case .exportFailed(let why):
            return "Export failed: \(why)"
        case .notSupportedOnPlatform(let what):
            return "\(what) is not supported on this platform"
        }
    }
}
