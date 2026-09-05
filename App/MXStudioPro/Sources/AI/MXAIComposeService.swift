import Foundation
import Observation

public struct AIComposeResult: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let durationSeconds: Int
    public let genres: [String]
    public let instrumental: Bool
    /// Staged MP3 in `Documents/AICompose/` until imported into a project.
    public let stagedFileName: String
}

enum AIComposePhase: Equatable {
    case idle
    case generating
    case completed
    case failed
}

@MainActor
@Observable
final class MXAIComposeService {
    static let genres = ["Pop", "Hip-Hop", "R&B", "Rock", "Electronic", "Lo-Fi", "Acoustic", "Cinematic"]
    static let durationOptions = [15, 30, 60, 90, 120]

    var prompt: String = ""
    var selectedGenres: Set<String> = []
    var instrumental: Bool = false
    var targetDurationSeconds: Int = 30
    var apiKeyDraft: String = MXAIComposeCredentials.apiKey ?? ""
    var phase: AIComposePhase = .idle
    var result: AIComposeResult?
    var errorMessage: String?

    var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAPIKey: Bool {
        !trimmedAPIKey.isEmpty || MXAIComposeCredentials.hasAPIKey
    }

    var canGenerate: Bool {
        hasAPIKey && !trimmedPrompt.isEmpty && phase != .generating
    }

    func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
    }

    func saveAPIKey() {
        guard !trimmedAPIKey.isEmpty else { return }
        MXAIComposeCredentials.setAPIKey(trimmedAPIKey)
    }

    func generate() async {
        guard canGenerate else {
            if !hasAPIKey {
                errorMessage = MXElevenLabsMusicClient.ClientError.missingAPIKey.localizedDescription
                phase = .failed
            }
            return
        }

        phase = .generating
        errorMessage = nil
        result = nil
        saveAPIKey()

        do {
            try Task.checkCancellation()

            let composedPrompt = buildPrompt()
            let lengthMs = clampedMusicLengthMs(targetDurationSeconds)
            let audioData = try await MXElevenLabsMusicClient.compose(
                .init(
                    prompt: composedPrompt,
                    musicLengthMs: lengthMs,
                    forceInstrumental: instrumental
                ),
                apiKey: trimmedAPIKey.isEmpty ? MXAIComposeCredentials.apiKey : trimmedAPIKey
            )
            try Task.checkCancellation()

            let composeID = UUID()
            let staged = try MXAIAudioFileWriter.writeStagedMP3(data: audioData, id: composeID)
            let title = buildTitle(from: composedPrompt)
            let duration = max(1, Int(staged.durationSeconds.rounded()))

            result = AIComposeResult(
                id: composeID,
                title: title,
                durationSeconds: duration,
                genres: selectedGenres.sorted(),
                instrumental: instrumental,
                stagedFileName: staged.fileName
            )
            phase = .completed
        } catch is CancellationError {
            phase = .idle
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    func regenerate() async {
        await generate()
    }

    func reset() {
        prompt = ""
        selectedGenres = []
        instrumental = false
        targetDurationSeconds = 30
        phase = .idle
        result = nil
        errorMessage = nil
    }

    private func buildPrompt() -> String {
        var parts: [String] = [trimmedPrompt]
        if !selectedGenres.isEmpty {
            parts.append("Genre: \(selectedGenres.sorted().joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }

    private func buildTitle(from composedPrompt: String) -> String {
        let snippet = String(composedPrompt.prefix(32))
        let genreLabel = selectedGenres.sorted().first ?? "Original"
        return snippet.isEmpty ? "Untitled \(genreLabel)" : "\(snippet) — \(genreLabel)"
    }

    private func clampedMusicLengthMs(_ seconds: Int) -> Int {
        min(max(seconds, 3), 600) * 1_000
    }
}
