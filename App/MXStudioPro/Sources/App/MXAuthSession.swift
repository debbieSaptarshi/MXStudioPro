import Foundation
import Observation

/// Local auth session for Week 9 — persists guest vs signed-in without a backend.
@MainActor
@Observable
public final class MXAuthSession {
    public enum Mode: String, Codable, Sendable {
        case guest
        case signedIn
    }

    public private(set) var mode: Mode = .guest
    public private(set) var email: String?
    public private(set) var displayName: String?
    public private(set) var userID: String?

    /// After login, reopen Create / Studio for this preset if set.
    public var pendingCreatePreset: StudioPreset?
    /// Prefer reopening last project when true.
    public var pendingResumeStudio: Bool = false

    public var isSignedIn: Bool { mode == .signedIn }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let mode = "mxstudio.auth.mode"
        static let email = "mxstudio.auth.email"
        static let displayName = "mxstudio.auth.displayName"
        static let userID = "mxstudio.auth.userID"
        static let pendingPreset = "mxstudio.auth.pendingPreset"
        static let pendingResume = "mxstudio.auth.pendingResume"
    }

    public static let shared = MXAuthSession()

    private init() {
        load()
    }

    public func load() {
        if let raw = defaults.string(forKey: Keys.mode), let m = Mode(rawValue: raw) {
            mode = m
        } else {
            mode = .guest
        }
        email = defaults.string(forKey: Keys.email)
        displayName = defaults.string(forKey: Keys.displayName)
        userID = defaults.string(forKey: Keys.userID)
        if let presetRaw = defaults.string(forKey: Keys.pendingPreset) {
            pendingCreatePreset = StudioPreset(rawValue: presetRaw)
        }
        pendingResumeStudio = defaults.bool(forKey: Keys.pendingResume)
    }

    public func enterGuest() {
        mode = .guest
        // Keep email cleared for guest; identity reserved for signed-in.
        persist()
    }

    public func signIn(email rawEmail: String, displayName: String? = nil, userID: String? = nil) {
        let trimmed = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.contains("@") else { return }
        mode = .signedIn
        email = trimmed
        self.displayName = displayName ?? trimmed.split(separator: "@").first.map(String.init) ?? "Creator"
        if let userID {
            self.userID = userID
        } else if let existing = defaults.string(forKey: Keys.userID),
                  defaults.string(forKey: Keys.email) == trimmed {
            self.userID = existing
        } else {
            self.userID = "local_\(UUID().uuidString.prefix(8))"
        }
        persist()
    }

    public func signInWithApple(userID: String, email: String?, fullName: String?) {
        mode = .signedIn
        self.userID = userID
        if let email, !email.isEmpty {
            self.email = email.lowercased()
        } else if self.email == nil {
            self.email = "apple.\(userID.prefix(8))@privaterelay.appleid.com"
        }
        if let fullName, !fullName.isEmpty {
            displayName = fullName
        } else if displayName == nil {
            displayName = "Apple User"
        }
        persist()
    }

    public func signOut() {
        mode = .guest
        email = nil
        displayName = nil
        userID = nil
        clearPendingResume()
        persist()
    }

    public func stashResume(preset: StudioPreset?, resumeStudio: Bool) {
        pendingCreatePreset = preset
        pendingResumeStudio = resumeStudio
        if let preset {
            defaults.set(preset.rawValue, forKey: Keys.pendingPreset)
        } else {
            defaults.removeObject(forKey: Keys.pendingPreset)
        }
        defaults.set(resumeStudio, forKey: Keys.pendingResume)
    }

    public func clearPendingResume() {
        pendingCreatePreset = nil
        pendingResumeStudio = false
        defaults.removeObject(forKey: Keys.pendingPreset)
        defaults.set(false, forKey: Keys.pendingResume)
    }

    private func persist() {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(email, forKey: Keys.email)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(userID, forKey: Keys.userID)
    }
}
