import SwiftUI

private struct CreateCategory: Identifiable {
    enum Style {
        case hero
        case compact
        case medium
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let style: Style
    let preset: StudioPreset?
    /// Week 1: only Vocals opens Studio. Other tiles stay visible.
    let isEnabled: Bool
}

private struct CreateMoreItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

/// Figma:
/// - `96:53711` Create New Mix Not login
/// - `96:72447` Create Mix with AI v2 (logged in)
public struct CreateMixView: View {
    public var isLoggedIn: Bool
    public var onOpenStudio: (StudioPreset) -> Void
    public var onOpenStudioProject: (UUID) -> Void
    public var onOpenAI: () -> Void
    public var onLogin: () -> Void
    public var onTutorials: () -> Void

    @State private var showTemplates = false
    @State private var templateError: String?

    public init(
        isLoggedIn: Bool = false,
        onOpenStudio: @escaping (StudioPreset) -> Void = { _ in },
        onOpenStudioProject: @escaping (UUID) -> Void = { _ in },
        onOpenAI: @escaping () -> Void = {},
        onLogin: @escaping () -> Void = {},
        onTutorials: @escaping () -> Void = {}
    ) {
        self.isLoggedIn = isLoggedIn
        self.onOpenStudio = onOpenStudio
        self.onOpenStudioProject = onOpenStudioProject
        self.onOpenAI = onOpenAI
        self.onLogin = onLogin
        self.onTutorials = onTutorials
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoggedIn {
                            loggedInGrid
                        } else {
                            guestGrid
                        }
                        moreProject
                        Color.clear.frame(height: isLoggedIn ? 16 : 108)
                    }
                    .padding(16)
                }
            }
            .background(MXColor.surface)

            if !isLoggedIn {
                MXLoginBanner(onLogin: onLogin)
                    .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showTemplates) {
            DemoTemplatesView(
                onSelectTemplate: { template in
                    showTemplates = false
                    openTemplate(template)
                },
                onClose: { showTemplates = false }
            )
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .alert("Template", isPresented: Binding(
            get: { templateError != nil },
            set: { if !$0 { templateError = nil } }
        )) {
            Button("OK", role: .cancel) { templateError = nil }
        } message: {
            Text(templateError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if isLoggedIn {
                MXHeader(kind: .titleProfile, title: "Create Mix", onProfile: onLogin)
            } else {
                guestHeader
            }
        }
    }

    private var guestHeader: some View {
        HStack(spacing: 8) {
            Text("CREATE NEW MIX")
                .font(.system(size: 24, weight: .regular, design: .default).width(.condensed))
                .foregroundStyle(MXColor.lightGrey)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onLogin) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 14, weight: .medium))
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MXColor.layer2)
                .frame(height: 1)
        }
    }

    // MARK: - Logged-in grid (`96:72447`)

    private var loggedInCategories: [CreateCategory] {
        let pocket = "Record live with microphones in your pocket."
        return [
            .init(title: "Create Music With AI", subtitle: "Describe a vibe — get a track", systemImage: "sparkles", tint: MXColor.accent, style: .hero, preset: .ai, isEnabled: true),
            .init(title: "Vocals/Audio", subtitle: pocket, systemImage: "mic.fill", tint: MXColor.accent, style: .medium, preset: .vocal, isEnabled: true),
            .init(title: "Guitar", subtitle: "Record electric or acoustic with pedals", systemImage: "guitars.fill", tint: MXColor.teal, style: .medium, preset: .guitar, isEnabled: true),
            .init(title: "Drums", subtitle: "Pad machine — lay a beat on the timeline", systemImage: "circle.grid.2x2.fill", tint: MXColor.orange, style: .medium, preset: .drums, isEnabled: true),
            .init(title: "Quick Recording", subtitle: "One-take capture — minimal chrome", systemImage: "record.circle", tint: MXColor.red, style: .medium, preset: .quickRecord, isEnabled: true),
            .init(title: "Bass", subtitle: "Others — coming soon", systemImage: "music.note", tint: MXColor.purple, style: .medium, preset: .bass, isEnabled: false),
            .init(title: "Looper", subtitle: "Others — coming soon", systemImage: "arrow.triangle.2.circlepath", tint: MXColor.lightPurple, style: .medium, preset: .looper, isEnabled: false),
            .init(title: "Sampler", subtitle: "Others — coming soon", systemImage: "guitars", tint: MXColor.pink, style: .medium, preset: .sampler, isEnabled: false),
            .init(title: "Import File", subtitle: pocket, systemImage: "square.and.arrow.up", tint: MXColor.red, style: .medium, preset: .importFile, isEnabled: false),
            .init(title: "Virtual Instrument", subtitle: "Play keys with a built-in piano/synth", systemImage: "pianokeys", tint: MXColor.orange, style: .medium, preset: .midi, isEnabled: true),
            .init(title: "Live Performance", subtitle: pocket, systemImage: "music.quarternote.3", tint: MXColor.white, style: .medium, preset: .live, isEnabled: false),
        ]
    }

    private var loggedInGrid: some View {
        let items = loggedInCategories
        let medium = Array(items.dropFirst())
        return VStack(spacing: 8) {
            if let hero = items.first {
                heroTile(hero)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4),
                ],
                spacing: 4
            ) {
                ForEach(medium) { category in
                    mediumTile(category)
                }
            }
        }
    }

    private func heroTile(_ category: CreateCategory) -> some View {
        Button {
            open(category)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(category.isEnabled ? category.tint : category.tint.opacity(0.35))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text(category.title.uppercased())
                        .font(.system(size: 16, weight: .regular, design: .default).width(.condensed))
                        .foregroundStyle(category.isEnabled ? MXColor.white : MXColor.grey)
                    Text(category.subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(metalCard)
            .opacity(category.isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func mediumTile(_ category: CreateCategory) -> some View {
        Button {
            open(category)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(category.isEnabled ? category.tint : category.tint.opacity(0.35))
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 0) {
                    Text(category.title.uppercased())
                        .font(.system(size: 14, weight: .regular, design: .default).width(.condensed))
                        .foregroundStyle(category.isEnabled ? MXColor.white : MXColor.grey)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(category.subtitle)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(MXColor.grey)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(metalCard)
            .opacity(category.isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Guest grid (`96:53711`)

    private var guestCategories: [CreateCategory] {
        [
            .init(title: "Create Music With AI", subtitle: "Describe a vibe — get a track", systemImage: "sparkles", tint: MXColor.accent, style: .hero, preset: .ai, isEnabled: true),
            .init(title: "Vocals/Audio", subtitle: "Record live with microphones.", systemImage: "mic.fill", tint: MXColor.accent, style: .compact, preset: .vocal, isEnabled: true),
            .init(title: "Guitar", subtitle: "Record electric or acoustic with pedals", systemImage: "guitars.fill", tint: MXColor.teal, style: .compact, preset: .guitar, isEnabled: true),
            .init(title: "Drums", subtitle: "Pad machine — lay a beat on the timeline", systemImage: "circle.grid.2x2.fill", tint: MXColor.orange, style: .compact, preset: .drums, isEnabled: true),
            .init(title: "Quick Recording", subtitle: "One-take capture — minimal chrome", systemImage: "record.circle", tint: MXColor.red, style: .compact, preset: .quickRecord, isEnabled: true),
            .init(title: "Bass", subtitle: "Others — coming soon", systemImage: "music.note", tint: MXColor.purple, style: .compact, preset: .bass, isEnabled: false),
            .init(title: "Looper", subtitle: "Others — coming soon", systemImage: "arrow.triangle.2.circlepath", tint: MXColor.lightPurple, style: .compact, preset: .looper, isEnabled: false),
            .init(title: "Sampler", subtitle: "Others — coming soon", systemImage: "guitars", tint: MXColor.pink, style: .compact, preset: .sampler, isEnabled: false),
            .init(title: "Import File", subtitle: "Import your mixed file or mp3 file", systemImage: "square.and.arrow.up", tint: MXColor.red, style: .compact, preset: .importFile, isEnabled: false),
            .init(title: "Virtual Instrument", subtitle: "Play keys with a built-in piano/synth", systemImage: "pianokeys", tint: MXColor.orange, style: .compact, preset: .midi, isEnabled: true),
            .init(title: "Live Performance", subtitle: "Set up for the live performance on virtual stage.", systemImage: "music.quarternote.3", tint: MXColor.white, style: .compact, preset: .live, isEnabled: false),
        ]
    }

    private var guestGrid: some View {
        let items = guestCategories
        return VStack(spacing: 8) {
            heroTile(items[0])
            HStack(spacing: 8) {
                compactTile(items[1])
                compactTile(items[2])
                compactTile(items[3])
            }
            HStack(spacing: 8) {
                compactTile(items[4])
                compactTile(items[5])
                compactTile(items[6])
            }
            HStack(spacing: 8) {
                compactTile(items[7])
                compactTile(items[8])
            }
        }
    }

    private func compactTile(_ category: CreateCategory) -> some View {
        Button {
            open(category)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.isEnabled ? category.tint : category.tint.opacity(0.35))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 0) {
                    Text(category.title.uppercased())
                        .font(.system(size: 16, weight: .regular, design: .default).width(.condensed))
                        .foregroundStyle(category.isEnabled ? MXColor.white : MXColor.grey)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(category.subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(metalCard)
            .opacity(category.isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func open(_ category: CreateCategory) {
        guard category.isEnabled, let preset = category.preset else { return }
        if preset == .ai {
            onOpenAI()
            return
        }
        onOpenStudio(preset)
    }

    private func openMoreItem(_ item: CreateMoreItem) {
        switch item.title {
        case "Demo Templates":
            showTemplates = true
        case "Tutorials":
            onTutorials()
        default:
            break
        }
    }

    private func openTemplate(_ template: MXDemoTemplate) {
        do {
            let projectID = try MXDemoTemplates.createProject(from: template)
            onOpenStudioProject(projectID)
        } catch {
            templateError = error.localizedDescription
        }
    }

    // MARK: - More Project

    private var moreItems: [CreateMoreItem] {
        let templateCount = MXDemoTemplates.all.count
        if isLoggedIn {
            return [
                .init(title: "Demo Templates", subtitle: "\(templateCount) starter templates", systemImage: "folder"),
                .init(title: "My Templates", subtitle: "0 saved templates", systemImage: "folder"),
                .init(title: "Tutorials", subtitle: "Start your music study", systemImage: "lifepreserver"),
            ]
        }
        return [
            .init(title: "Demo Templates", subtitle: "\(templateCount) starter templates", systemImage: "folder"),
            .init(title: "Tutorials", subtitle: "Start your music study", systemImage: "lifepreserver"),
        ]
    }

    private var moreProject: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MORE PROJECT")
                .font(.system(size: 20, weight: .regular, design: .default).width(.condensed))
                .foregroundStyle(MXColor.grey)

            VStack(spacing: 8) {
                ForEach(moreItems) { item in
                    Button(action: { openMoreItem(item) }) {
                        HStack(spacing: 16) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(MXColor.white)
                                .frame(width: 24, height: 24)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(MXColor.layer2)
                                        .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
                                        .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(MXFont.mediumButton())
                                    .foregroundStyle(MXColor.lightGrey)
                                Text(item.subtitle)
                                    .font(item.title == "Tutorials" ? MXFont.caption() : MXFont.body3())
                                    .foregroundStyle(MXColor.grey)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MXColor.grey)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var metalCard: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(MXColor.surfaceRaised)
            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
            .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
    }
}

/// Lightweight studio landing matching Mix into the Studio entry.
public struct StudioHubView: View {
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Studio")
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Spacer()
            }
            .padding(16)
            .background(MXColor.surfaceRaised)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image("mix_studio")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text("Open a session, load instruments, and mix.")
                        .font(MXFont.body2())
                        .foregroundStyle(MXColor.lightGrey)

                    Button("New Session") {}
                        .mxMetalButton(.big, accent: true)
                }
                .padding(16)
            }
        }
        .background(MXColor.surface.ignoresSafeArea())
    }
}

#Preview("Create Not Login") {
    CreateMixView(isLoggedIn: false)
}

#Preview("Create Mix AI v2") {
    CreateMixView(isLoggedIn: true)
}
