import SwiftUI

@main
struct MXStudioProApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum AppRoute: Equatable {
    case splash
    case welcome
    case main
    case nowPlaying
    case studio(StudioPreset)
}

struct RootView: View {
    @State private var route: AppRoute
    @State private var tab: MXTab = .socials
    @State private var isLoggedIn = false
    @State private var showMiniPlayer = false
    @State private var isPlaying = true

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startStudio") {
            _route = State(initialValue: .studio(.vocal))
            _tab = State(initialValue: .create)
            _isLoggedIn = State(initialValue: true)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        } else if args.contains("-startSocials") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .socials)
            _isLoggedIn = State(initialValue: args.contains("-loggedIn") || args.contains("-playing"))
            _showMiniPlayer = State(initialValue: args.contains("-playing"))
            _isPlaying = State(initialValue: true)
        } else if args.contains("-startCreate") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .create)
            _isLoggedIn = State(initialValue: !args.contains("-guest"))
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        } else if args.contains("-startDiscover") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .discover)
            _isLoggedIn = State(initialValue: true)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        } else if args.contains("-startNowPlaying") {
            _route = State(initialValue: .nowPlaying)
            _tab = State(initialValue: .discover)
            _isLoggedIn = State(initialValue: true)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        } else if args.contains("-startWelcome") {
            _route = State(initialValue: .welcome)
            _tab = State(initialValue: .socials)
            _isLoggedIn = State(initialValue: false)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        } else {
            _route = State(initialValue: .splash)
            _tab = State(initialValue: .socials)
            _isLoggedIn = State(initialValue: false)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
        }
    }

    var body: some View {
        ZStack {
            switch route {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        route = .welcome
                    }
                }

            case .welcome:
                WelcomeView(
                    onSkip: {
                        isLoggedIn = false
                        tab = .socials
                        route = .main
                    },
                    onContinueEmail: {
                        isLoggedIn = true
                        tab = .socials
                        route = .main
                    }
                )

            case .main:
                mainShell

            case .nowPlaying:
                NowPlayingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        route = .main
                    }
                }

            case .studio(let preset):
                StudioHostView(preset: preset) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        tab = .create
                        route = .main
                    }
                }
            }
        }
    }

    private var mainShell: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .socials:
                    SocialsView(
                        isLoggedIn: isLoggedIn,
                        showFullFeed: isLoggedIn,
                        showMiniPlayer: showMiniPlayer,
                        isPlaying: isPlaying,
                        onLogin: {
                            route = .welcome
                        },
                        onCompose: {},
                        onTogglePlay: {
                            isPlaying.toggle()
                        },
                        onOpenPlayer: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .nowPlaying
                            }
                        },
                        onStartPlaying: {
                            showMiniPlayer = true
                            isPlaying = true
                        }
                    )
                case .discover:
                    DiscoverMixesView {
                        withAnimation { route = .nowPlaying }
                    }
                case .create:
                    CreateMixView(
                        isLoggedIn: isLoggedIn,
                        onOpenStudio: { preset in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .studio(preset)
                            }
                        },
                        onLogin: {
                            route = .welcome
                        }
                    )
                case .studio:
                    StudioHubView()
                case .profile:
                    placeholder("My Mix", icon: "play.square")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MXTabBar(selection: $tab)
        }
        .background(MXColor.surface.ignoresSafeArea())
    }

    private func placeholder(_ title: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(MXColor.accent)
            Text(title)
                .font(MXFont.displayTitle())
                .foregroundStyle(MXColor.white)
            Text("Coming next from the Figma set")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MXColor.surface)
    }
}

/// Owns one `StudioSessionController` for the lifetime of the Studio screen.
private struct StudioHostView: View {
    @State private var session: StudioSessionController
    var onClose: () -> Void

    init(preset: StudioPreset, onClose: @escaping () -> Void) {
        _session = State(initialValue: StudioSessionController(preset: preset))
        self.onClose = onClose
    }

    var body: some View {
        StudioView(session: session, onClose: onClose)
    }
}

#Preview("Root") {
    RootView()
}
