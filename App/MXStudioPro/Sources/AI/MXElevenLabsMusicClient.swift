import Foundation

/// ElevenLabs Music API — POST https://api.elevenlabs.io/v1/music
enum MXElevenLabsMusicClient {
    enum ClientError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse
        case emptyAudio
        case httpError(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your ElevenLabs API key to generate music."
            case .invalidResponse:
                return "ElevenLabs returned an unexpected response."
            case .emptyAudio:
                return "ElevenLabs returned an empty audio file."
            case .httpError(let status, let message):
                let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return "ElevenLabs request failed (HTTP \(status))."
                }
                return "ElevenLabs request failed (HTTP \(status)): \(detail)"
            }
        }
    }

    struct ComposeRequest: Sendable {
        var prompt: String
        var musicLengthMs: Int
        var forceInstrumental: Bool
        var modelID: String = "music_v2"
    }

    private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/music")!

    static func compose(_ request: ComposeRequest, apiKey: String? = MXAIComposeCredentials.apiKey) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty else {
            throw ClientError.missingAPIKey
        }

        var urlComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_44100_128"),
        ]

        var urlRequest = URLRequest(url: urlComponents.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.timeoutInterval = 300

        let body: [String: Any] = [
            "prompt": request.prompt,
            "music_length_ms": request.musicLengthMs,
            "model_id": request.modelID,
            "force_instrumental": request.forceInstrumental,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(status: http.statusCode, message: message)
        }
        guard !data.isEmpty else {
            throw ClientError.emptyAudio
        }
        return data
    }
}
