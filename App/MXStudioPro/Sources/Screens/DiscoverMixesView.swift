import SwiftUI

/// Demo content mirroring the Discover Mixes Figma screen.
struct DiscoverItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let imageName: String
    let verified: Bool
}

enum DiscoverData {
    static let popular: [DiscoverItem] = [
        .init(title: "EVRYTHNG IN BETWEEN", subtitle: "Ingwiyhana", imageName: "album_evrythng", verified: true),
        .init(title: "Frag's Favs", subtitle: "Frags", imageName: "discover_card_1", verified: true),
        .init(title: "Night Drive", subtitle: "MX Collective", imageName: "discover_card_2", verified: false),
    ]

    static let playlists: [DiscoverItem] = [
        .init(title: "Studio Warmups", subtitle: "12 tracks", imageName: "discover_card_1", verified: false),
        .init(title: "Indie Pulse", subtitle: "28 tracks", imageName: "discover_card_2", verified: false),
        .init(title: "Green Room", subtitle: "9 tracks", imageName: "album_evrythng", verified: true),
    ]

    static let filters = ["All", "Mixes", "Artists", "Playlists", "Live"]
}

/// Figma node `95:81569` — Discover Mixes.
public struct DiscoverMixesView: View {
    @State private var selectedFilter = "All"
    @State private var query = ""
    public var onOpenNowPlaying: () -> Void = {}

    public init(onOpenNowPlaying: @escaping () -> Void = {}) {
        self.onOpenNowPlaying = onOpenNowPlaying
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchField
                    filterRow
                    section(title: "Popular Mixes", items: DiscoverData.popular, cardWidth: 200, cardHeight: 184)
                    section(title: "Playlists For You", items: DiscoverData.playlists, cardWidth: 140, cardHeight: 124)
                    listSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(MXColor.surface.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover")
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text("Mixes, artists & playlists")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MXColor.white)
                    .frame(width: 20, height: 20)
            }
            .mxMetalButton(.icon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MXColor.grey)
            TextField("Search mixes", text: $query)
                .font(MXFont.body2())
                .foregroundStyle(MXColor.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(MXColor.layer2)
        )
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MXColor.black)
        )
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoverData.filters, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        MXFilterChip(title: filter, isSelected: selectedFilter == filter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func section(title: String, items: [DiscoverItem], cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(MXFont.header3())
                .foregroundStyle(MXColor.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button(action: onOpenNowPlaying) {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(item.imageName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: cardWidth, height: cardHeight - 48)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(MXFont.mediumButton())
                                        .foregroundStyle(MXColor.white)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(item.subtitle)
                                            .font(MXFont.caption())
                                            .foregroundStyle(MXColor.grey)
                                        if item.verified {
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(MXColor.accent)
                                        }
                                    }
                                }
                            }
                            .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending Tracks")
                .font(MXFont.header3())
                .foregroundStyle(MXColor.white)

            ForEach(DiscoverData.popular) { item in
                Button(action: onOpenNowPlaying) {
                    HStack(spacing: 12) {
                        Image(item.imageName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(MXFont.mediumButton())
                                .foregroundStyle(MXColor.white)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                        }
                        Spacer()
                        Image(systemName: "heart")
                            .foregroundStyle(MXColor.grey)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Discover") {
    DiscoverMixesView()
}
