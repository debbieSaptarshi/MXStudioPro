import Foundation

/// ElevenLabs API key storage for AI music generation.
enum MXAIComposeCredentials {
    static let userDefaultsKey = "mxstudio.elevenlabs.apiKey"

    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let stored = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    static var hasAPIKey: Bool { apiKey != nil }

    static func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
    }
}
