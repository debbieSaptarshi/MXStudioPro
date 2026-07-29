import SwiftUI
import UIKit

/// Figma Badge (`117:92915`) — accent chip, 8% fill, Body 3 / 12pt.
public struct MXBadge: View {
    public enum IconPlacement: String, CaseIterable, Identifiable {
        case leading, trailing, none
        public var id: String { rawValue }
    }

    public var title: String
    public var icon: IconPlacement
    public var tint: Color

    public init(
        _ title: String = "Title",
        icon: IconPlacement = .leading,
        tint: Color = MXColor.accent
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if icon == .leading { badgeIcon }
            Text(title)
                .font(MXFont.body3())
                .foregroundStyle(tint)
                .lineLimit(1)
            if icon == .trailing { badgeIcon }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private var badgeIcon: some View {
        Group {
            if UIImage(named: "icon_badge_check") != nil {
                Image("icon_badge_check")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(tint)
        .frame(width: 12, height: 12)
    }
}
