import Foundation
import Observation

public struct AIComposeResult: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let durationSeconds: Int
    public let genres: [String]
    public let instrumental: Bool
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

    var prompt: String = ""
    var selectedGenres: Set<String> = []
    var instrumental: Bool = false
    var phase: AIComposePhase = .idle
    var result: AIComposeResult?
    var errorMessage: String?

    var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canGenerate: Bool {
        !trimmedPrompt.isEmpty && phase != .generating
    }

    func toggleGenre(_ genre: String) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else {
            selectedGenres.insert(genre)
        }
    }

    func generate() async {
        guard canGenerate else { return }

        phase = .generating
        errorMessage = nil
        result = nil

        do {
            try await Task.sleep(for: .seconds(2.5))
            try Task.checkCancellation()

            let snippet = String(trimmedPrompt.prefix(32))
            let genreLabel = selectedGenres.sorted().first ?? "Original"
            let title = snippet.isEmpty ? "Untitled \(genreLabel)" : "\(snippet) — \(genreLabel)"

            result = AIComposeResult(
                id: UUID(),
                title: title,
                durationSeconds: 32,
                genres: selectedGenres.sorted(),
                instrumental: instrumental
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
        phase = .idle
        result = nil
        errorMessage = nil
    }
}
