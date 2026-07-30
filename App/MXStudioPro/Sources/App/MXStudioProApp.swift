import AuthenticationServices
import SwiftUI

@main
struct MXStudioProApp: App {
    @UIApplicationDelegateAdaptor(MXAppDelegate.self) private var appDelegate

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
    case aiCompose
    case studio(StudioPreset)
    case studioProject(UUID)
}

struct RootView: View {
    @State private var auth = MXAuthSession.shared
    @State private var route: AppRoute
    @State private var tab: MXTab = .socials
    @State private var showMiniPlayer = false
    @State private var isPlaying = true
    @State private var showEmailSignIn = false
    @State private var appleAlert: String?
    @State private var appleCoordinator = AppleSignInCoordinator()
    @State private var openTunerOnLearnTab = false

    private var isLoggedIn: Bool { auth.isSignedIn }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let session = MXAuthSession.shared

        if args.contains("-startMIDI") {
            _route = State(initialValue: .studio(.midi))
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startGuitar") {
            _route = State(initialValue: .studio(.guitar))
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startStudio") {
            _route = State(initialValue: .studio(.vocal))
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if args.contains("-loggedIn") || !args.contains("-guest") {
                if !session.isSignedIn {
                    session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
                }
            } else {
                session.enterGuest()
            }
        } else if args.contains("-startSocials") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .socials)
            _showMiniPlayer = State(initialValue: args.contains("-playing"))
            _isPlaying = State(initialValue: true)
            if args.contains("-loggedIn") || args.contains("-playing") {
                if !session.isSignedIn {
                    session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
                }
            } else if args.contains("-guest") {
                session.enterGuest()
            }
        } else if args.contains("-startCreate") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if args.contains("-guest") {
                session.enterGuest()
            } else if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startAI") {
            _route = State(initialValue: .aiCompose)
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startDiscover") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .discover)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startTuner") {
            _route = State(initialValue: .main)
            _tab = State(initialValue: .studio)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            _openTunerOnLearnTab = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startTemplate") {
            let projectID: UUID
            if let first = MXDemoTemplates.all.first,
               let id = try? MXDemoTemplates.createProject(from: first) {
                projectID = id
            } else {
                projectID = UUID()
            }
            _route = State(initialValue: .studioProject(projectID))
            _tab = State(initialValue: .create)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startNowPlaying") {
            _route = State(initialValue: .nowPlaying)
            _tab = State(initialValue: .discover)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            if !session.isSignedIn {
                session.signIn(email: "demo@mxstudio.pro", displayName: "Demo")
            }
        } else if args.contains("-startWelcome") {
            _route = State(initialValue: .welcome)
            _tab = State(initialValue: .socials)
            _showMiniPlayer = State(initialValue: false)
            _isPlaying = State(initialValue: true)
            session.enterGuest()
        } else {
            // Cold start: splash → welcome or main based on persisted session
            _route = State(initialValue: .splash)
            _tab = State(initialValue: .socials)
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
                        route = auth.isSignedIn ? .main : .welcome
                    }
                }

            case .welcome:
                WelcomeView(
                    onSkip: {
                        auth.enterGuest()
                        tab = .socials
                        route = .main
                    },
                    onContinueEmail: {
                        showEmailSignIn = true
                    },
                    onApple: {
                        beginAppleSignIn()
                    }
                )
                .sheet(isPresented: $showEmailSignIn) {
                    EmailSignInView(
                        onCancel: { showEmailSignIn = false },
                        onContinue: { email in
                            auth.signIn(email: email)
                            showEmailSignIn = false
                            finishSignIn()
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
                }

            case .main:
                mainShell

            case .nowPlaying:
                NowPlayingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        route = .main
                    }
                }

            case .aiCompose:
                AIComposeView(
                    onOpenInStudio: { projectID in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tab = .create
                            route = .studioProject(projectID)
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tab = .create
                            route = .main
                        }
                    }
                )

            case .studio(let preset):
                StudioHostView(
                    preset: preset,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tab = .create
                            route = .main
                        }
                    },
                    onViewSocials: openSocialsTab
                )

            case .studioProject(let id):
                StudioHostView(
                    projectID: id,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tab = .profile
                            route = .main
                        }
                    },
                    onViewSocials: openSocialsTab
                )
            }
        }
        .alert("Sign in with Apple", isPresented: Binding(
            get: { appleAlert != nil },
            set: { if !$0 { appleAlert = nil } }
        )) {
            Button("Continue with Email") { showEmailSignIn = true; appleAlert = nil }
            Button("OK", role: .cancel) { appleAlert = nil }
        } message: {
            Text(appleAlert ?? "")
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
                        onLogin: { presentLogin(from: .socials) },
                        onCompose: {},
                        onTogglePlay: { isPlaying.toggle() },
                        onOpenPlayer: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .nowPlaying
                            }
                        },
                        onStartPlaying: {
                            showMiniPlayer = true
                            isPlaying = true
                        },
                        onRemixPost: { post in
                            UserDefaults.standard.set(
                                post.id.uuidString,
                                forKey: "mxstudio.pendingRemixOfPostID"
                            )
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if let projectID = post.projectID {
                                    route = .studioProject(projectID)
                                } else {
                                    route = .studio(.vocal)
                                }
                            }
                        },
                        onOpenProject: { projectID in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                tab = .create
                                route = .studioProject(projectID)
                            }
                        }
                    )
                case .discover:
                    DiscoverMixesView(
                        onOpenNowPlaying: {
                            withAnimation { route = .nowPlaying }
                        },
                        onOpenStudioProject: openStudioProject
                    )
                case .create:
                    CreateMixView(
                        isLoggedIn: isLoggedIn,
                        onOpenStudio: { preset in
                            if !auth.isSignedIn {
                                auth.stashResume(preset: preset, resumeStudio: true)
                            }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .studio(preset)
                            }
                        },
                        onOpenStudioProject: openStudioProject,
                        onOpenAI: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .aiCompose
                            }
                        },
                        onLogin: { presentLogin(from: .create) }
                    )
                case .studio:
                    LearnView(
                        onOpenStudio: { preset in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .studio(preset)
                            }
                        },
                        openTunerOnAppear: $openTunerOnLearnTab
                    )
                case .profile:
                    MyMixView(
                        onOpenProject: { project in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                route = .studioProject(project.id)
                            }
                        },
                        onLogin: { presentLogin(from: .profile) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MXTabBar(selection: $tab)
        }
        .background(MXColor.surface.ignoresSafeArea())
    }

    private func openStudioProject(_ projectID: UUID) {
        withAnimation(.easeInOut(duration: 0.25)) {
            tab = .create
            route = .studioProject(projectID)
        }
    }

    private func openSocialsTab() {
        withAnimation(.easeInOut(duration: 0.25)) {
            tab = .socials
            route = .main
        }
    }

    private func presentLogin(from tabHint: MXTab) {
        tab = tabHint
        if case .studio = route {
            auth.stashResume(preset: .vocal, resumeStudio: true)
        } else if tabHint == .create, auth.pendingCreatePreset == nil {
            auth.stashResume(preset: .vocal, resumeStudio: false)
        }
        route = .welcome
        showEmailSignIn = false
    }

    private func finishSignIn() {
        let resumeStudio = auth.pendingResumeStudio
        let preset = auth.pendingCreatePreset
        let projectID = MXProjectStore.shared.lastOpenedProjectID
        auth.clearPendingResume()

        tab = .create
        if resumeStudio {
            if let projectID {
                route = .studioProject(projectID)
            } else if let preset {
                route = .studio(preset)
            } else {
                route = .main
            }
        } else {
            route = .main
        }
    }

    private func beginAppleSignIn() {
        appleCoordinator.onSuccess = { userID, email, name in
            auth.signInWithApple(userID: userID, email: email, fullName: name)
            finishSignIn()
        }
        appleCoordinator.onFailure = { message in
            appleAlert = message
        }
        appleCoordinator.start()
    }
}

// MARK: - Apple Sign In (optional; falls back when team/capability missing)

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onSuccess: ((String, String?, String?) -> Void)?
    var onFailure: ((String) -> Void)?

    private var controller: ASAuthorizationController?

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onFailure?("Apple Sign In returned an unexpected credential.")
            return
        }
        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
        let fullName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
        onSuccess?(credential.user, credential.email, fullName)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return
        }
        onFailure?("Sign in with Apple needs an Apple Developer team & capability. Use Continue with Email for now.")
    }
}

/// Owns one `StudioSessionController` for the lifetime of the Studio screen.
private struct StudioHostView: View {
    @State private var session: StudioSessionController
    var onClose: () -> Void
    var onViewSocials: () -> Void

    init(preset: StudioPreset, onClose: @escaping () -> Void, onViewSocials: @escaping () -> Void = {}) {
        _session = State(initialValue: StudioSessionController(preset: preset))
        self.onClose = onClose
        self.onViewSocials = onViewSocials
    }

    init(projectID: UUID, onClose: @escaping () -> Void, onViewSocials: @escaping () -> Void = {}) {
        let project = (try? MXProjectStore.shared.load(id: projectID))
            ?? MXProject.untitledVocal()
        _session = State(initialValue: StudioSessionController(project: project))
        self.onClose = onClose
        self.onViewSocials = onViewSocials
    }

    var body: some View {
        StudioView(session: session, onClose: onClose, onViewSocials: onViewSocials)
            .task {
                if ProcessInfo.processInfo.arguments.contains("-startRecord") {
                    session.enterRecordMode()
                }
                if ProcessInfo.processInfo.arguments.contains("-bounceOnLaunch") {
                    do {
                        let result = try await session.bounceMix(normalize: true)
                        print("MX_BOUNCE_OK wav=\(result.wavURL.path) m4a=\(result.m4aURL.path)")
                    } catch {
                        print("MX_BOUNCE_FAIL \(error.localizedDescription)")
                    }
                }
            }
    }
}

#Preview("Root") {
    RootView()
}
