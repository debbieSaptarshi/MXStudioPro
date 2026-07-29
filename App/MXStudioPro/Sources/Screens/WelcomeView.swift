import SwiftUI
import UIKit

/// Figma node `95:81450` — Welcome / login screen.
public struct WelcomeView: View {
    public var onSkip: () -> Void = {}
    public var onContinueEmail: () -> Void = {}
    public var onGoogle: () -> Void = {}
    public var onApple: () -> Void = {}
    public var onFacebook: () -> Void = {}

    public init(
        onSkip: @escaping () -> Void = {},
        onContinueEmail: @escaping () -> Void = {},
        onGoogle: @escaping () -> Void = {},
        onApple: @escaping () -> Void = {},
        onFacebook: @escaping () -> Void = {}
    ) {
        self.onSkip = onSkip
        self.onContinueEmail = onContinueEmail
        self.onGoogle = onGoogle
        self.onApple = onApple
        self.onFacebook = onFacebook
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                MXSteelBackground()

                // Logo — Figma: centered, top = 50% − 105pt, size 211×162
                MXBrandMark()
                    .position(
                        x: geo.size.width / 2,
                        y: geo.size.height * 0.5 - 105 + 81
                    )

                // Bottom actions — Figma `95:81457`
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    bottomActions
                }

                // Skip — Figma absolute left:287 top:50 on 375pt frame
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        skipButton
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 50)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip")
                .font(MXFont.mediumButton())
                .foregroundStyle(MXColor.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(metalFace)
        }
        .buttonStyle(MXPressScaleStyle())
        .padding(4)
        .background(metalShell)
    }

    private var bottomActions: some View {
        VStack(spacing: 16) {
            emailButton
            socialRow
            legalCopy
        }
        .padding(24)
        .padding(.bottom, 8)
    }

    private var emailButton: some View {
        Button(action: onContinueEmail) {
            HStack(spacing: 8) {
                Image("icon_mail")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Continue with Email")
                    .font(MXFont.bigButton())
            }
            .foregroundStyle(MXColor.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(metalFace)
        }
        .buttonStyle(MXPressScaleStyle())
        .padding(4)
        .background(metalShell)
    }

    private var socialRow: some View {
        HStack(spacing: 4) {
            socialButton(asset: "icon_google", fallback: "G", action: onGoogle)
            socialButton(asset: "icon_apple", fallbackSystem: "apple.logo", action: onApple)
            socialButton(asset: "icon_facebook", fallback: "f", action: onFacebook)
        }
        .padding(4)
        .background(metalShell)
    }

    private func socialButton(
        asset: String,
        fallback: String? = nil,
        fallbackSystem: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else if let fallbackSystem {
                    Image(systemName: fallbackSystem)
                        .font(.system(size: 20, weight: .medium))
                } else if let fallback {
                    Text(fallback)
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .foregroundStyle(MXColor.white)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(metalFace)
        }
        .buttonStyle(MXPressScaleStyle())
        .frame(maxWidth: .infinity)
    }

    private var metalFace: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(MXColor.layer2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.black.opacity(0.01), Color.black.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 1, x: 1.5, y: -1.5)
            .shadow(color: Color.white.opacity(0.1), radius: 1, x: -1.5, y: 1.5)
    }

    private var metalShell: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(MXColor.black)
    }

    private var legalCopy: some View {
        (Text("By continuing, you agree to our ")
            .foregroundStyle(MXColor.lightGrey)
         + Text("Terms of Use")
            .foregroundStyle(MXColor.accent)
            .underline()
         + Text(" and ")
            .foregroundStyle(MXColor.lightGrey)
         + Text("Privacy Policy")
            .foregroundStyle(MXColor.accent)
            .underline())
        .font(MXFont.body2())
        .multilineTextAlignment(.center)
        .frame(maxWidth: 299)
    }
}

#Preview("Login") {
    WelcomeView()
}
