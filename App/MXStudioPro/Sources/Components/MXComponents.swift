import SwiftUI

/// Recessed metal button matching Figma's "Secondary Button Shadow" style:
/// outer shell `#17191A`, face `#2F3238`, dual inset shadows.
public struct MXMetalButtonStyle: ButtonStyle {
    public enum Size {
        case big      // 12pt vertical, 24pt horizontal
        case medium   // 10pt vertical, 16pt horizontal
        case icon     // 10pt all sides, square-ish
        case social   // 12pt all sides, flex width

        var padding: EdgeInsets {
            switch self {
            case .big: return EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            case .medium: return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            case .icon: return EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            case .social: return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            }
        }

        var font: Font {
            switch self {
            case .big, .social: return MXFont.bigButton()
            case .medium, .icon: return MXFont.mediumButton()
            }
        }
    }

    public var size: Size = .big
    public var fill: Color = MXColor.layer2
    public var foreground: Color = MXColor.white
    public var isAccent: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .foregroundStyle(isAccent ? MXColor.black : foreground)
            .padding(size.padding)
            .frame(maxWidth: size == .big || size == .social ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isAccent ? MXColor.accent : fill)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
            .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
            .padding(size == .icon ? 2 : 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
    }
}

public extension View {
    func mxMetalButton(_ size: MXMetalButtonStyle.Size = .big,
                       accent: Bool = false) -> some View {
        buttonStyle(MXMetalButtonStyle(size: size, isAccent: accent))
    }
}

/// Full-bleed cinematic steel background used on Splash / Welcome.
/// Texture is constrained + clipped so `scaledToFill` cannot inflate the
/// parent ZStack (which was pushing Skip / side social buttons off-screen).
public struct MXSteelBackground: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(MXColor.cinematicSteel)
            .ignoresSafeArea()
            .overlay {
                Image("bg_texture")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.28)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
            .overlay {
                RadialGradient(
                    colors: [Color.white.opacity(0.18), Color.clear],
                    center: UnitPoint(x: 0.24, y: 0.0),
                    startRadius: 0,
                    endRadius: 420
                )
                .blendMode(.overlay)
                .allowsHitTesting(false)
            }
            .clipped()
            .allowsHitTesting(false)
    }
}

/// Brand mark: knob + wordmark, centered as in Figma.
public struct MXBrandMark: View {
    public var knobSize: CGFloat = 96

    public init(knobSize: CGFloat = 96) {
        self.knobSize = knobSize
    }

    public var body: some View {
        VStack(spacing: 32) {
            Image("knob_logo")
                .resizable()
                .scaledToFit()
                .frame(width: knobSize, height: knobSize)
                .clipShape(Circle())
                .shadow(color: Color(hex: 0x17191A, opacity: 0.4), radius: 16, x: 20, y: 20)
                .shadow(color: Color(hex: 0x0A0C0D, opacity: 0.35), radius: 8, x: 6, y: 6)

            ZStack {
                // Soft extrusion matching Figma wordmark depth.
                Text("MXSTUDIO PRO")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .offset(x: 1.5, y: 2)
                Text("MXSTUDIO PRO")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xE8E8E8), Color(hex: 0xA8A8A8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
        }
    }
}

/// Filter chip matching Discover "Filters" row.
public struct MXFilterChip: View {
    public var title: String
    public var isSelected: Bool = false

    public var body: some View {
        Text(title)
            .font(MXFont.mediumButton())
            .foregroundStyle(isSelected ? MXColor.black : MXColor.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? MXColor.accent : MXColor.layer2)
            )
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
    }
}

/// Bottom tab bar matching Figma Main Menu on Social home:
/// HOME / MIXES / ADD / LEARN / MY MIX
public enum MXTab: String, CaseIterable, Identifiable {
    case socials = "Home"
    case discover = "Mixes"
    case create = "Add"
    case studio = "Learn"
    case profile = "My Mix"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .socials: return "square.grid.2x2.fill"
        case .discover: return "magnifyingglass"
        case .create: return "plus.square"
        case .studio: return "music.note"
        case .profile: return "play.square.fill"
        }
    }
}

public struct MXTabBar: View {
    @Binding public var selection: MXTab

    public init(selection: Binding<MXTab>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(MXTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    if tab == .create {
                        createTab(selected: selection == tab)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 18, weight: .medium))
                            Text(tab.rawValue.uppercased())
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(selection == tab ? MXColor.white : MXColor.grey)
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .padding(.horizontal, 8)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MXColor.layer2)
                .frame(height: 1)
        }
    }

    private func createTab(selected: Bool) -> some View {
        Image(systemName: "plus")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MXColor.white)
            .frame(width: 24, height: 24)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MXColor.layer2)
                    .shadow(color: Color.black.opacity(0.45), radius: 0.8, x: 0.5, y: -0.5)
                    .shadow(color: Color.white.opacity(0.11), radius: 0.8, x: -1.5, y: 1.5)
            )
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? MXColor.accent : Color.clear)
            )
            .frame(maxWidth: .infinity)
    }
}
