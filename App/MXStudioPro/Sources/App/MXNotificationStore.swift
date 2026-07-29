import Foundation
import Observation

/// Local notification store (Week 22) — collab invites, remix alerts, etc.
@MainActor
@Observable
public final class MXNotificationStore {
    public struct Item: Codable, Identifiable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case collabInvite
            case remix
            case general
        }

        public var id: UUID
        public var message: String
        public var createdAt: Date
        public var relatedProjectID: UUID?
        public var relatedPostID: UUID?
        public var kind: Kind
        public var isRead: Bool

        public init(
            id: UUID = UUID(),
            message: String,
            createdAt: Date = .now,
            relatedProjectID: UUID? = nil,
            relatedPostID: UUID? = nil,
            kind: Kind = .general,
            isRead: Bool = false
        ) {
            self.id = id
            self.message = message
            self.createdAt = createdAt
            self.relatedProjectID = relatedProjectID
            self.relatedPostID = relatedPostID
            self.kind = kind
            self.isRead = isRead
        }
    }

    public static let shared = MXNotificationStore()

    public private(set) var items: [Item] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var rootURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Notifications", isDirectory: true)
    }

    private var itemsURL: URL { rootURL.appendingPathComponent("notifications.json") }

    private init() {
        load()
    }

    public func load() {
        if let data = try? Data(contentsOf: itemsURL),
           let decoded = try? decoder.decode([Item].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            items = []
            migrateLegacySocialNotificationsIfNeeded()
        }
    }

    public func add(
        message: String,
        kind: Item.Kind = .general,
        relatedProjectID: UUID? = nil,
        relatedPostID: UUID? = nil
    ) {
        let item = Item(
            message: message,
            relatedProjectID: relatedProjectID,
            relatedPostID: relatedPostID,
            kind: kind
        )
        items.insert(item, at: 0)
        persist()
    }

    public func notifyCollabInvite(inviterName: String, projectName: String, projectID: UUID) {
        add(
            message: "\(inviterName) invited you to collaborate on “\(projectName)”",
            kind: .collabInvite,
            relatedProjectID: projectID
        )
    }

    public func markAllRead() {
        guard items.contains(where: { !$0.isRead }) else { return }
        for i in items.indices {
            items[i].isRead = true
        }
        persist()
    }

    public func markRead(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              !items[index].isRead else { return }
        items[index].isRead = true
        persist()
    }

    public var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private func persist() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if let data = try? encoder.encode(items) {
            try? data.write(to: itemsURL, options: [.atomic])
        }
    }

    /// Pull Week 10–12 notifications from Social/ if present (one-time).
    private func migrateLegacySocialNotificationsIfNeeded() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyURL = docs
            .appendingPathComponent("Social", isDirectory: true)
            .appendingPathComponent("notifications.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let legacy = try? decoder.decode([LegacyNotification].self, from: data),
              !legacy.isEmpty else { return }

        items = legacy.map {
            Item(
                id: $0.id,
                message: $0.message,
                createdAt: $0.createdAt,
                relatedPostID: $0.relatedPostID,
                kind: .general,
                isRead: $0.isRead
            )
        }.sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    private struct LegacyNotification: Codable {
        var id: UUID
        var message: String
        var createdAt: Date
        var relatedPostID: UUID?
        var isRead: Bool
    }
}
