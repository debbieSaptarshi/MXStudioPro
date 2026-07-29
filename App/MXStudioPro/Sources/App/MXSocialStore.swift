import AVFoundation
import Foundation
import Observation

/// Local social spine (Weeks 10–12) — users/posts/audio on device until a cloud backend lands.
@MainActor
@Observable
public final class MXSocialStore {
    public struct Post: Codable, Identifiable, Equatable, Sendable {
        public var id: UUID
        public var authorID: String
        public var authorName: String
        public var authorHandle: String
        public var caption: String
        public var createdAt: Date
        public var projectID: UUID?
        public var audioFileName: String?
        public var title: String
        public var durationLabel: String
        public var remixOfPostID: UUID?
        public var likes: Int
        public var comments: Int

        public init(
            id: UUID = UUID(),
            authorID: String,
            authorName: String,
            authorHandle: String,
            caption: String,
            createdAt: Date = .now,
            projectID: UUID? = nil,
            audioFileName: String? = nil,
            title: String,
            durationLabel: String = "00:00",
            remixOfPostID: UUID? = nil,
            likes: Int = 0,
            comments: Int = 0
        ) {
            self.id = id
            self.authorID = authorID
            self.authorName = authorName
            self.authorHandle = authorHandle
            self.caption = caption
            self.createdAt = createdAt
            self.projectID = projectID
            self.audioFileName = audioFileName
            self.title = title
            self.durationLabel = durationLabel
            self.remixOfPostID = remixOfPostID
            self.likes = likes
            self.comments = comments
        }
    }

    public struct NotificationItem: Codable, Identifiable, Equatable, Sendable {
        public var id: UUID
        public var message: String
        public var createdAt: Date
        public var relatedPostID: UUID?
        public var isRead: Bool

        public init(
            id: UUID = UUID(),
            message: String,
            createdAt: Date = .now,
            relatedPostID: UUID? = nil,
            isRead: Bool = false
        ) {
            self.id = id
            self.message = message
            self.createdAt = createdAt
            self.relatedPostID = relatedPostID
            self.isRead = isRead
        }
    }

    public static let shared = MXSocialStore()

    public private(set) var posts: [Post] = []

    public var notifications: [NotificationItem] {
        MXNotificationStore.shared.items.map {
            NotificationItem(
                id: $0.id,
                message: $0.message,
                createdAt: $0.createdAt,
                relatedPostID: $0.relatedPostID,
                isRead: $0.isRead
            )
        }
    }

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
        return docs.appendingPathComponent("Social", isDirectory: true)
    }

    private var postsURL: URL { rootURL.appendingPathComponent("posts.json") }
    public var audioDirectory: URL { rootURL.appendingPathComponent("Audio", isDirectory: true) }

    private init() {
        load()
    }

    public func load() {
        try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: postsURL),
           let decoded = try? decoder.decode([Post].self, from: data) {
            posts = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            posts = []
        }
    }

    public func audioURL(for post: Post) -> URL? {
        guard let name = post.audioFileName else { return nil }
        let url = audioDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Public file URL for an exported mix (local “CDN” for Week 10).
    public func publicURL(for post: Post) -> URL? {
        audioURL(for: post)
    }

    public func post(forProjectID id: UUID) -> Post? {
        posts.first { $0.projectID == id }
    }

    public func posts(forAuthorID authorID: String) -> [Post] {
        posts.filter { $0.authorID == authorID }
    }

    @discardableResult
    public func publish(
        project: MXProject,
        audioSourceURL: URL,
        caption: String,
        auth: MXAuthSession,
        remixOfPostID: UUID? = nil
    ) throws -> Post {
        guard auth.isSignedIn else {
            throw SocialError.notSignedIn
        }
        try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let ext = audioSourceURL.pathExtension.isEmpty ? "m4a" : audioSourceURL.pathExtension
        let fileName = "post_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext)"
        let dest = audioDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: audioSourceURL, to: dest)

        let handleBase = (auth.displayName ?? "creator")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let post = Post(
            authorID: auth.userID ?? "local",
            authorName: auth.displayName ?? "Creator",
            authorHandle: "@\(handleBase)",
            caption: caption,
            projectID: project.id,
            audioFileName: fileName,
            title: project.name,
            durationLabel: approximateDurationLabel(url: dest),
            remixOfPostID: remixOfPostID
        )
        posts.insert(post, at: 0)
        persistPosts()

        if let remixOf = remixOfPostID, let original = posts.first(where: { $0.id == remixOf }) {
            MXNotificationStore.shared.add(
                message: "\(post.authorName) remixed “\(original.title)”",
                kind: .remix,
                relatedPostID: post.id
            )
        }
        return post
    }

    public func notify(message: String, relatedPostID: UUID? = nil) {
        MXNotificationStore.shared.add(
            message: message,
            kind: .general,
            relatedPostID: relatedPostID
        )
    }

    public func markNotificationsRead() {
        MXNotificationStore.shared.markAllRead()
    }

    public var unreadNotificationCount: Int {
        MXNotificationStore.shared.unreadCount
    }

    public func feedModels(includingMock: Bool) -> [MXSocialFeedPost.Model] {
        let local: [MXSocialFeedPost.Model] = posts.map { post in
            .init(
                id: post.id.uuidString,
                kind: .song,
                name: post.authorName,
                handle: post.authorHandle,
                timeAgo: relativeTime(post.createdAt),
                caption: post.caption,
                avatarAsset: "avatar_kings",
                likes: "\(post.likes)",
                comments: "\(post.comments)",
                mediaTitle: post.title,
                plays: "—",
                duration: post.durationLabel,
                tags: post.remixOfPostID == nil ? "#mxstudio" : "#remix #mxstudio",
                songCoverAsset: "avatar_kings"
            )
        }
        if includingMock {
            return local + MXSocialFeedData.fullFeed
        }
        return local
    }

    private func persistPosts() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if let data = try? encoder.encode(posts) {
            try? data.write(to: postsURL, options: [.atomic])
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    private func approximateDurationLabel(url: URL) -> String {
        guard let file = try? AVAudioFile(forReading: url) else { return "00:00" }
        let seconds = Int(Double(file.length) / max(file.fileFormat.sampleRate, 1))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public enum SocialError: Error, LocalizedError {
        case notSignedIn
        case missingAudio

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to publish."
            case .missingAudio: return "Export a mix before publishing."
            }
        }
    }
}
