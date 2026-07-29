import SwiftUI

/// Figma node `95:81443` — Splash.
public struct SplashView: View {
    public var onFinished: () -> Void = {}

    public init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            MXSteelBackground()

            VStack {
                Spacer()
                MXBrandMark()
                Spacer()
                Text("The Power of a Studio. The Size of Your Pocket.")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.lightGrey)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            onFinished()
        }
    }
}

#Preview("Splash") {
    SplashView()
}
