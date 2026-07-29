import SwiftUI

/// Figma Component Box → Buttons (`19:22500`).
public struct MXButton: View {
    public enum Kind: String, CaseIterable, Identifiable {
        case prime, secondary, tertiary, notAvailable
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .prime: return "Prime"
            case .secondary: return "Secondary"
            case .tertiary: return "Tertiary"
            case .notAvailable: return "Not Available"
            }
        }
    }

    public enum Size: String, CaseIterable, Identifiable {
        case big, medium, small
        public var id: String { rawValue }
    }

    public enum IconPlacement: String, CaseIterable, Identifiable {
        case none, leading, trailing, iconOnly
        public var id: String { rawValue }
    }

    public var title: String
    public var systemImage: String?
    public var kind: Kind
    public var size: Size
    public var icon: IconPlacement
    public var expands: Bool
    public var action: () -> Void

    public init(
        _ title: String = "Sign up with Email",
        systemImage: String? = "envelope",
        kind: Kind = .prime,
        size: Size = .big,
        icon: IconPlacement = .leading,
        expands: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.icon = icon
        self.expands = expands
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            labelContent
                .padding(metrics.padding)
                .frame(maxWidth: expands ? .infinity : nil)
                .background(chrome)
        }
        .buttonStyle(MXPressScaleStyle(enabled: kind != .notAvailable))
        .disabled(kind == .notAvailable)
        .accessibilityLabel(icon == .iconOnly ? (systemImage ?? title) : title)
    }

    @ViewBuilder
    private var labelContent: some View {
        switch icon {
        case .none:
            titleText
        case .leading:
            HStack(spacing: metrics.gap) {
                iconImage
                titleText
            }
        case .trailing:
            HStack(spacing: metrics.gap) {
                titleText
                iconImage
            }
        case .iconOnly:
            iconImage
        }
    }

    private var titleText: some View {
        Text(title)
            .font(metrics.font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: !expands, vertical: true)
    }

    @ViewBuilder
    private var iconImage: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: metrics.iconPointSize, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: metrics.iconFrame, height: metrics.iconFrame)
        }
    }

    private var foreground: Color {
        switch kind {
        case .prime: return MXColor.black
        case .secondary: return MXColor.white
        case .tertiary: return MXColor.accent
        case .notAvailable: return MXColor.layer2
        }
    }

    @ViewBuilder
    private var chrome: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        switch kind {
        case .tertiary:
            shape.fill(Color.clear)
        case .prime:
            shape
                .fill(MXColor.accent)
                .overlay(insetRing(dark: MXColor.primeInset, light: Color.white.opacity(0.56)))
                .shadow(color: MXColor.primeInset.opacity(0.55), radius: 0.8, x: 1.2, y: -1.2)
                .shadow(color: Color.white.opacity(0.35), radius: 0.8, x: -1.2, y: 1.2)
        case .secondary:
            shape
                .fill(MXColor.layer2)
                .overlay(insetRing(dark: Color.black.opacity(0.5), light: Color.white.opacity(0.1)))
                .shadow(color: Color.black.opacity(0.45), radius: 0.8, x: 1.2, y: -1.2)
                .shadow(color: Color.white.opacity(0.08), radius: 0.8, x: -1.2, y: 1.2)
        case .notAvailable:
            shape
                .fill(MXColor.surfaceRaised)
                .overlay(insetRing(dark: Color.black.opacity(0.5), light: Color.white.opacity(0.1)))
        }
    }

    private func insetRing(dark: Color, light: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [light, dark.opacity(0.01), dark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }

    private var metrics: Metrics { Metrics(size: size, iconOnly: icon == .iconOnly) }

    private struct Metrics {
        let padding: EdgeInsets
        let gap: CGFloat
        let font: Font
        let iconFrame: CGFloat
        let iconPointSize: CGFloat

        init(size: Size, iconOnly: Bool) {
            switch size {
            case .big:
                gap = 8; font = MXFont.bigButton(); iconFrame = 24; iconPointSize = 18
                padding = iconOnly
                    ? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                    : EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            case .medium:
                gap = 6; font = MXFont.mediumButton(); iconFrame = 20; iconPointSize = 15
                padding = iconOnly
                    ? EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                    : EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            case .small:
                gap = 4; font = MXFont.smallButton(); iconFrame = 16; iconPointSize = 12
                padding = iconOnly
                    ? EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
                    : EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            }
        }
    }
}

struct MXPressScaleStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && enabled ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && enabled ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
