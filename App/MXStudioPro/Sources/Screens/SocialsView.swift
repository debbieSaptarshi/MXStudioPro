import SwiftUI

/// Figma Social home screens:
/// - `95:83619` Socials Not login
/// - `95:81469` Socials (logged in)
/// - `95:81539` Socials - Play Music
/// - `95:82872` Socials Full Feed
public struct SocialsView: View {
    public var isLoggedIn: Bool
    public var showFullFeed: Bool
    public var showMiniPlayer: Bool
    public var isPlaying: Bool
    public var onLogin: () -> Void
    public var onCompose: () -> Void
    public var onTogglePlay: () -> Void
    public var onOpenPlayer: () -> Void
    public var onStartPlaying: () -> Void

    public init(
        isLoggedIn: Bool = false,
        showFullFeed: Bool = true,
        showMiniPlayer: Bool = false,
        isPlaying: Bool = true,
        onLogin: @escaping () -> Void = {},
        onCompose: @escaping () -> Void = {},
        onTogglePlay: @escaping () -> Void = {},
        onOpenPlayer: @escaping () -> Void = {},
        onStartPlaying: @escaping () -> Void = {}
    ) {
        self.isLoggedIn = isLoggedIn
        self.showFullFeed = showFullFeed
        self.showMiniPlayer = showMiniPlayer
        self.isPlaying = isPlaying
        self.onLogin = onLogin
        self.onCompose = onCompose
        self.onTogglePlay = onTogglePlay
        self.onOpenPlayer = onOpenPlayer
        self.onStartPlaying = onStartPlaying
    }

    private var posts: [MXSocialFeedPost.Model] {
        if !isLoggedIn {
            return MXSocialFeedData.notLoginFeed
        }
        return showFullFeed ? MXSocialFeedData.fullFeed : MXSocialFeedData.notLoginFeed
    }

    public var body: some View {
        VStack(spacing: 0) {
            MXHeader(kind: isLoggedIn ? .home : .notLogin, onProfile: onLogin)

            sectionTitle

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        MXSocialFeedPost(model: post, onPlay: onStartPlaying)
                    }
                    Color.clear.frame(height: bottomClearance)
                }
            }
        }
        .background(MXColor.surface)
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if showMiniPlayer && isLoggedIn {
                    MXMiniPlayer(
                        isPlaying: isPlaying,
                        onTogglePlay: onTogglePlay,
                        onOpen: onOpenPlayer
                    )
                }
                if !isLoggedIn {
                    MXLoginBanner(onLogin: onLogin)
                }
            }
        }
    }

    private var bottomClearance: CGFloat {
        if !isLoggedIn { return 120 }
        if showMiniPlayer { return 72 }
        return 24
    }

    private var sectionTitle: some View {
        HStack(spacing: 8) {
            Text("SOCIALS")
                .font(.system(size: 24, weight: .regular, design: .default).width(.condensed))
                .foregroundStyle(MXColor.white)

            Spacer(minLength: 0)

            if isLoggedIn {
                Button(action: onCompose) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MXColor.black)
                )
            } else {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Text("For you")
                            .font(MXFont.smallButton())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(MXColor.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MXColor.black)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surface)
    }
}

#Preview("Socials Not Login") {
    SocialsView(isLoggedIn: false)
}

#Preview("Socials Logged In") {
    SocialsView(isLoggedIn: true, showFullFeed: false)
}

#Preview("Socials Play Music") {
    SocialsView(isLoggedIn: true, showMiniPlayer: true)
}

#Preview("Socials Full Feed") {
    SocialsView(isLoggedIn: true, showFullFeed: true)
}
