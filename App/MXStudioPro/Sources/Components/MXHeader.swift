import SwiftUI

/// Figma Header family (`26:26321`) — 375×64, Layer 1 bg + Layer 2 bottom border.
public struct MXHeader: View {
    public enum Kind: String, CaseIterable, Identifiable {
        case home
        case notLogin
        case titleProfile
        case titleBack
        case customAI
        case player
        case studio
        public var id: String { rawValue }
    }

    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var onClose: () -> Void
    public var onBell: () -> Void
    public var onProfile: () -> Void

    public init(
        kind: Kind = .home,
        title: String = "Notifications",
        subtitle: String = "Pop-Rock Indonesia",
        onClose: @escaping () -> Void = {},
        onBell: @escaping () -> Void = {},
        onProfile: @escaping () -> Void = {}
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.onBell = onBell
        self.onProfile = onProfile
    }

    public var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            trailing
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

    @ViewBuilder
    private var leading: some View {
        switch kind {
        case .home, .notLogin:
            brandMark
        case .titleProfile, .titleBack:
            Text(title.uppercased())
                .font(.system(size: 24, weight: .regular, design: .default).width(.condensed))
                .foregroundStyle(MXColor.lightGrey)
                .lineLimit(1)
        case .customAI:
            HStack(spacing: 2) {
                iconFace(systemImage: "textformat", tint: MXColor.accent)
                iconFace(systemImage: "mic")
                MXButton("Custom", systemImage: "sparkles", kind: .secondary, size: .medium, icon: .leading, action: {})
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        case .player:
            VStack(alignment: .leading, spacing: 0) {
                Text("Now Playing from")
                    .font(.system(size: 16, weight: .regular, design: .default).width(.condensed))
                    .foregroundStyle(MXColor.lightGrey)
                Text(subtitle)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
        case .studio:
            HStack(spacing: 2) {
                iconChip(systemImage: "arrow.left.to.line", action: onClose)
                iconChip(systemImage: "dial.low", action: {})
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case .home, .titleProfile:
            HStack(spacing: 4) {
                iconChip(systemImage: "bell", action: onBell)
                profileTile
            }
        case .notLogin:
            iconChip(systemImage: "person.crop.circle", action: onProfile)
        case .titleBack, .player:
            iconChip(systemImage: "xmark", action: onClose)
        case .customAI:
            iconChip(systemImage: "xmark", action: onClose)
        case .studio:
            HStack(spacing: 2) {
                MXButton("Collab", systemImage: "plus", kind: .secondary, size: .medium, icon: .leading, action: {})
                iconFace(systemImage: "wand.and.stars")
                iconFace(systemImage: "gearshape")
                iconFace(systemImage: "square.and.arrow.up")
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        }
    }

    private var brandMark: some View {
        HStack(spacing: 8) {
            Image("knob_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            Text("MXSTUDIO PRO")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MXColor.white)
                .lineLimit(1)
        }
    }

    private var profileTile: some View {
        Button(action: onProfile) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.white)
                Text("W")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MXColor.black)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MXColor.black)
        )
    }

    private func iconChip(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            iconFace(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MXColor.black)
        )
    }

    private func iconFace(systemImage: String, tint: Color = MXColor.white) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.layer2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}
