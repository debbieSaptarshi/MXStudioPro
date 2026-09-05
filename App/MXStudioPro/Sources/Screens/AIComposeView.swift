import SwiftUI

public struct AIComposeView: View {
    public var sessionToImportInto: StudioSessionController?
    public var onOpenInStudio: ((UUID) -> Void)?
    public var onClose: () -> Void

    @State private var service = MXAIComposeService()
    @State private var importError: String?
    @FocusState private var promptFocused: Bool

    public init(
        sessionToImportInto: StudioSessionController? = nil,
        onOpenInStudio: ((UUID) -> Void)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.sessionToImportInto = sessionToImportInto
        self.onOpenInStudio = onOpenInStudio
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            MXColor.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if service.phase == .completed, let result = service.result {
                            resultCard(result)
                        } else {
                            composeForm
                        }
                    }
                    .padding(16)
                }
            }

            if service.phase == .generating {
                loadingOverlay
            }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("CREATE MUSIC WITH AI")
                .font(.system(size: 20, weight: .regular, design: .default).width(.condensed))
                .foregroundStyle(MXColor.lightGrey)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXColor.white)
                    .frame(width: 20, height: 20)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
                            .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MXColor.layer2)
                .frame(height: 1)
        }
    }

    // MARK: - Compose form

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            apiKeySection
            promptSection
            genreSection
            durationSection
            instrumentalRow

            if service.phase == .failed, let message = service.errorMessage {
                Text(message)
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.red)
            }

            MXButton(
                "Generate",
                systemImage: "sparkles",
                kind: service.canGenerate ? .prime : .notAvailable,
                size: .big,
                icon: .leading,
                expands: true
            ) {
                Task { await service.generate() }
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ELEVENLABS API KEY")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.grey)

            SecureField("sk_…", text: $service.apiKeyDraft)
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MXColor.black)
                )

            Text("Get a key at elevenlabs.io. Stored on device only.")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LENGTH")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.grey)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MXAIComposeService.durationOptions, id: \.self) { seconds in
                        Button {
                            service.targetDurationSeconds = seconds
                        } label: {
                            MXFilterChip(
                                title: formatDuration(seconds),
                                isSelected: service.targetDurationSeconds == seconds
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIBE YOUR VIBE")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.grey)

            ZStack(alignment: .topLeading) {
                if service.prompt.isEmpty {
                    Text("Chill lo-fi beat for a rainy night…")
                        .font(MXFont.body2())
                        .foregroundStyle(MXColor.grey)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $service.prompt)
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.white)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .focused($promptFocused)
            }
            .frame(minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(promptFocused ? MXColor.accent : Color.clear, lineWidth: 1)
                    )
            )
        }
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENRE")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.grey)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MXAIComposeService.genres, id: \.self) { genre in
                        Button {
                            service.toggleGenre(genre)
                        } label: {
                            MXFilterChip(
                                title: genre,
                                isSelected: service.selectedGenres.contains(genre)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var instrumentalRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Instrumental")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.white)
                Text("No vocals — beat only")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
            }

            Spacer(minLength: 8)

            MXToggleSwitch(isOn: $service.instrumental)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MXColor.surfaceRaised)
                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
                .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
        )
    }

    // MARK: - Result

    private func resultCard(_ result: AIComposeResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MXColor.accent)
                    Text("YOUR TRACK")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.grey)
                }

                Text(result.title)
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formatDuration(result.durationSeconds))
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.lightGrey)

                if !result.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(result.genres, id: \.self) { genre in
                                MXBadge(genre, icon: .none)
                            }
                            if result.instrumental {
                                MXBadge("Instrumental", icon: .none, tint: MXColor.teal)
                            }
                        }
                    }
                } else if result.instrumental {
                    MXBadge("Instrumental", icon: .none, tint: MXColor.teal)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(metalCard)

            Button("Open in Studio") {
                openInStudio(result)
            }
            .mxMetalButton(.big, accent: false)

            HStack(spacing: 12) {
                MXButton("Regenerate", kind: .secondary, size: .big, expands: true) {
                    Task { await service.regenerate() }
                }

                MXButton("Done", kind: .prime, size: .big, expands: true, action: close)
            }
        }
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(MXColor.accent)
                    .scaleEffect(1.2)

                Text("Generating with ElevenLabs…")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.surfaceRaised)
            )
            .padding(32)
        }
    }

    // MARK: - Helpers

    private var metalCard: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(MXColor.surfaceRaised)
            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
            .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func openInStudio(_ result: AIComposeResult) {
        if let session = sessionToImportInto {
            do {
                try MXAIStudioImporter.importIntoSession(session, result: result)
                close()
            } catch {
                importError = error.localizedDescription
            }
            return
        }

        do {
            let projectID = try MXAIStudioImporter.importIntoNewProject(result: result)
            onOpenInStudio?(projectID)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func close() {
        service.reset()
        onClose()
    }
}

#Preview("AI Compose") {
    AIComposeView()
}
