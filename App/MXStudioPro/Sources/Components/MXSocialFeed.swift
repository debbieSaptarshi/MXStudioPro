import SwiftUI
import UIKit

/// Figma Social Feed post (`25:24603`) — Video / Words / Song / Photo.
public struct MXSocialFeedPost: View {
    public enum Kind {
        case video
        case words
        case song
        case photo
    }

    public struct Model: Identifiable {
        public let id: String
        public var kind: Kind
        public var name: String
        public var handle: String
        public var timeAgo: String
        public var caption: String
        public var avatarAsset: String
        public var likes: String
        public var comments: String
        public var mediaTitle: String?
        public var plays: String?
        public var duration: String?
        public var tags: String?
        public var mediaAsset: String?
        public var songCoverAsset: String?

        public init(
            id: String = UUID().uuidString,
            kind: Kind,
            name: String,
            handle: String,
            timeAgo: String,
            caption: String,
            avatarAsset: String,
            likes: String,
            comments: String,
            mediaTitle: String? = nil,
            plays: String? = nil,
            duration: String? = nil,
            tags: String? = nil,
            mediaAsset: String? = nil,
            songCoverAsset: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.name = name
            self.handle = handle
            self.timeAgo = timeAgo
            self.caption = caption
            self.avatarAsset = avatarAsset
            self.likes = likes
            self.comments = comments
            self.mediaTitle = mediaTitle
            self.plays = plays
            self.duration = duration
            self.tags = tags
            self.mediaAsset = mediaAsset
            self.songCoverAsset = songCoverAsset
        }
    }

    public var model: Model
    public var onLike: () -> Void = {}
    public var onComment: () -> Void = {}
    public var onShare: () -> Void = {}
    public var onOpenStudio: () -> Void = {}
    public var onPlay: () -> Void = {}

    public init(
        model: Model,
        onLike: @escaping () -> Void = {},
        onComment: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {},
        onOpenStudio: @escaping () -> Void = {},
        onPlay: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onLike = onLike
        self.onComment = onComment
        self.onShare = onShare
        self.onOpenStudio = onOpenStudio
        self.onPlay = onPlay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(model.caption)
                .font(MXFont.body2())
                .foregroundStyle(MXColor.lightGrey)
                .fixedSize(horizontal: false, vertical: true)

            switch model.kind {
            case .video: videoCard
            case .song: songCard
            case .photo: photoCard
            case .words: EmptyView()
            }

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MXColor.surfaceRaised)
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.lightGrey)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MXColor.accent)
                }
                HStack(spacing: 0) {
                    Text(model.handle)
                    Text(" · \(model.timeAgo)")
                }
                .font(MXFont.body3())
                .foregroundStyle(MXColor.grey)
            }
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MXColor.grey)
                .frame(width: 20, height: 20)
        }
    }

    private var avatar: some View {
        Group {
            if UIImage(named: model.avatarAsset) != nil {
                Image(model.avatarAsset)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.layer2)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var videoCard: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let media = model.mediaAsset, UIImage(named: media) != nil {
                    Image(media)
                        .resizable()
                        .scaledToFill()
                } else {
                    MXColor.surfaceRaised
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.mediaTitle ?? "")
                        .font(MXFont.header3())
                        .foregroundStyle(MXColor.white)
                    HStack(spacing: 0) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text(" \(model.plays ?? "")")
                        Text(" · \(model.duration ?? "")")
                    }
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.lightGrey)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(MXColor.white)
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    if let tags = model.tags {
                        Text(tags)
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.accent)
                    }
                }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var songCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.mediaTitle ?? "")
                        .font(MXFont.header3())
                        .foregroundStyle(MXColor.white)
                    HStack {
                        HStack(spacing: 2) {
                            Image(systemName: "play.fill").font(.system(size: 10))
                            Text(model.plays ?? "")
                            Text(" · \(model.duration ?? "")")
                        }
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                        Spacer()
                        if let tags = model.tags {
                            Text(tags)
                                .font(MXFont.body3())
                                .foregroundStyle(MXColor.accent)
                        }
                    }
                }
                Button(action: onPlay) {
                    ZStack {
                        Group {
                            let cover = model.songCoverAsset ?? model.avatarAsset
                            if UIImage(named: cover) != nil {
                                Image(cover).resizable().scaledToFill()
                            } else {
                                MXColor.layer2
                            }
                        }
                        .frame(width: 44, height: 44)
                        .opacity(0.5)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MXColor.white)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(MXColor.grey)
                Text("Sampling the project")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
                Spacer()
                MXButton("Open on studio", systemImage: nil, kind: .secondary, size: .small, icon: .none, action: onOpenStudio)
            }
            .padding(.leading, 12)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.surfaceRaised)
        )
    }

    private var photoCard: some View {
        Group {
            if let media = model.mediaAsset, UIImage(named: media) != nil {
                Image(media)
                    .resizable()
                    .scaledToFill()
            } else {
                MXColor.surfaceRaised
            }
        }
        .frame(height: 132)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 32) {
            HStack(spacing: 24) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                        Text(model.likes)
                    }
                }
                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text(model.comments)
                    }
                }
            }
            .font(MXFont.body2())
            .foregroundStyle(MXColor.grey)
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MXColor.grey)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Figma Box Bottom Pop-up Type=Login (`113:92490`).
public struct MXLoginBanner: View {
    public var onLogin: () -> Void

    public init(onLogin: @escaping () -> Void = {}) {
        self.onLogin = onLogin
    }

    public var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(MXColor.lightGrey)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text("Login")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.lightGrey)
                Text("Login to your account")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
            }

            Spacer(minLength: 0)

            MXButton("Login", systemImage: nil, kind: .prime, size: .small, icon: .none, action: onLogin)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MXColor.black)
                )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MXColor.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(MXColor.layer2, lineWidth: 1)
                )
        )
        .padding(8)
    }
}

/// Mini player above the tab bar — Figma `95:81539` Socials - Play Music.
public struct MXMiniPlayer: View {
    public var title: String
    public var artist: String
    public var coverAsset: String
    public var isPlaying: Bool
    public var onTogglePlay: () -> Void
    public var onOpen: () -> Void

    public init(
        title: String = "I don’t miss you at all",
        artist: String = "Shawn Mendes",
        coverAsset: String = "social_video",
        isPlaying: Bool = true,
        onTogglePlay: @escaping () -> Void = {},
        onOpen: @escaping () -> Void = {}
    ) {
        self.title = title
        self.artist = artist
        self.coverAsset = coverAsset
        self.isPlaying = isPlaying
        self.onTogglePlay = onTogglePlay
        self.onOpen = onOpen
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Group {
                        if UIImage(named: coverAsset) != nil {
                            Image(coverAsset)
                                .resizable()
                                .scaledToFill()
                        } else {
                            MXColor.layer2
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(MXFont.mediumButton())
                            .foregroundStyle(MXColor.lightGrey)
                            .lineLimit(1)
                        Text(artist)
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.grey)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXColor.white)
                    .frame(width: 20, height: 20)
                    .padding(10)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MXColor.layer2)
                .frame(height: 1)
        }
    }
}

public enum MXSocialFeedData {
    public static let notLoginFeed: [MXSocialFeedPost.Model] = [
        .init(
            kind: .video,
            name: "Shawn Mendez",
            handle: "@shawnmendez",
            timeAgo: "4m ago",
            caption: "Just uploaded a new sound I’ve been experimenting with. Thoughts?",
            avatarAsset: "avatar_shawn",
            likes: "256k",
            comments: "27",
            mediaTitle: "I don’t miss you at all",
            plays: "67k",
            duration: "03:14",
            tags: "#pop #rock #jpop",
            mediaAsset: "social_video"
        ),
        .init(
            kind: .words,
            name: "Mehra Nehru",
            handle: "@mehranehru",
            timeAgo: "2m ago",
            caption: "Been working on this one for a while finally ready to share. Tried a different style with this one. Curious",
            avatarAsset: "avatar_mehra",
            likes: "54.4k",
            comments: "1.6k"
        ),
        .init(
            kind: .photo,
            name: "Pamungkas",
            handle: "@pamunqkas",
            timeAgo: "1h ago",
            caption: "Just finished this track and wanted to share it here. Let me know your favorite part.",
            avatarAsset: "avatar_mehra",
            likes: "84",
            comments: "7",
            mediaAsset: "social_photo"
        ),
    ]

    /// Figma `95:82872` Socials Full Feed — song + video + words + photo.
    public static let fullFeed: [MXSocialFeedPost.Model] = [
        .init(
            kind: .song,
            name: "Kings",
            handle: "@kingofficials",
            timeAgo: "2m ago",
            caption: "Made this during a random burst of inspiration. Hope it finds the right ears.",
            avatarAsset: "avatar_kings",
            likes: "4.2k",
            comments: "143",
            mediaTitle: "I love about you",
            plays: "4.2k",
            duration: "05:41",
            tags: "#pop #rock #jpop",
            songCoverAsset: "avatar_kings"
        ),
    ] + notLoginFeed
}
