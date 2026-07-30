import Foundation
import Observation

/// BandLab-style **cloud auth sync spine** (Week 72) — local stub only.
///
/// Marks whether the signed-in account is cloud-linked and runs a no-network
/// sync that flips status → idle with a timestamp. No URLSession, API keys, or
/// secrets. Real backend remains operator-configured later.
@MainActor
@Observable
public final class MXCloudSyncSpine {
    public enum SyncStatus: String, Codable, Sendable, CaseIterable {
        case idle
        case syncing
        case offline
        case error

        public var displayName: String {
            switch self {
            case .idle: return "Up to date"
            case .syncing: return "Syncing…"
            case .offline: return "Offline"
            case .error: return "Sync error"
            }
        }
    }

    public private(set) var status: SyncStatus = .idle
    public private(set) var lastSyncedAt: Date?
    public private(set) var lastErrorMessage: String?

    public static let shared = MXCloudSyncSpine()

    private let defaults = UserDefaults.standard
    private var syncTask: Task<Void, Never>?

    private enum Keys {
        static let status = "mxstudio.cloud.status"
        static let lastSynced = "mxstudio.cloud.lastSyncedAt"
        static let lastError = "mxstudio.cloud.lastError"
    }

    private init() {
        load()
    }

    public func load() {
        if let raw = defaults.string(forKey: Keys.status),
           let s = SyncStatus(rawValue: raw) {
            // Never restore mid-flight syncing across launches.
            status = s == .syncing ? .idle : s
        } else {
            status = .idle
        }
        if let ts = defaults.object(forKey: Keys.lastSynced) as? Date {
            lastSyncedAt = ts
        }
        lastErrorMessage = defaults.string(forKey: Keys.lastError)
    }

    /// Human-readable status line for Profile (BandLab “last synced” lite).
    public func statusLine(cloudLinked: Bool) -> String {
        guard cloudLinked else { return "Local only — sign in to enable cloud sync" }
        switch status {
        case .syncing:
            return SyncStatus.syncing.displayName
        case .offline:
            return SyncStatus.offline.displayName
        case .error:
            return lastErrorMessage ?? SyncStatus.error.displayName
        case .idle:
            if let lastSyncedAt {
                return "Last synced \(Self.relativeTimestamp(lastSyncedAt))"
            }
            return "Cloud ready — tap Sync now"
        }
    }

    /// Stub sync: short delay then success. No network. Guests / unlinked → no-op.
    @discardableResult
    public func syncNow(cloudLinked: Bool) -> Bool {
        guard cloudLinked else { return false }
        guard status != .syncing else { return false }

        syncTask?.cancel()
        status = .syncing
        lastErrorMessage = nil
        persist()

        syncTask = Task { [weak self] in
            // Simulate a round-trip without contacting a server.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.status = .idle
            self.lastSyncedAt = Date()
            self.lastErrorMessage = nil
            self.persist()
        }
        return true
    }

    public func markOffline() {
        guard status != .syncing else { return }
        status = .offline
        persist()
    }

    public func clearForGuest() {
        syncTask?.cancel()
        syncTask = nil
        status = .idle
        // Keep lastSyncedAt as historical breadcrumb; clear error.
        lastErrorMessage = nil
        persist()
    }

    public static func relativeTimestamp(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    private func persist() {
        defaults.set(status.rawValue, forKey: Keys.status)
        if let lastSyncedAt {
            defaults.set(lastSyncedAt, forKey: Keys.lastSynced)
        }
        if let lastErrorMessage {
            defaults.set(lastErrorMessage, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
        }
    }
}
