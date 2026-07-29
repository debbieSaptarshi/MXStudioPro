import SwiftUI

/// Figma node `95:83311` — Now Playing.
public struct NowPlayingView: View {
    @State private var progress: Double = 0.4
    @State private var volume: Double = 0.75
    @State private var isPlaying = true
    public var onClose: () -> Void = {}

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            artwork
            timestamps
            trackInfo
            controls
            tags
            volumeRow
            continuePlaying
            Spacer(minLength: 0)
        }
        .background(MXColor.surface.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing from")
                    .font(MXFont.nowPlayingSource())
                    .foregroundStyle(MXColor.lightGrey)
                    .textCase(.uppercase)
                Text("EVRYTHNG IN BETWEEN")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
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

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            Image("album_evrythng")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 375)
                .clipped()

            // Progress flush with art bottom edge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(MXColor.surfaceRaised)
                    Rectangle()
                        .fill(MXColor.accent)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            Button(action: {}) {
                Image(systemName: "mic")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MXColor.white)
                    .frame(width: 20, height: 20)
            }
            .mxMetalButton(.icon)
            .padding(16)
            .padding(.bottom, 8)
        }
    }

    private var timestamps: some View {
        HStack {
            Text("01:56")
            Spacer()
            Text("04:56")
        }
        .font(MXFont.caption())
        .foregroundStyle(MXColor.grey)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var trackInfo: some View {
        VStack(spacing: 4) {
            Text("The people I know just telling me t...")
                .font(MXFont.trackTitle())
                .foregroundStyle(MXColor.white)
                .lineLimit(1)
            Text("Ingwiyhana")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.lightGrey)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            controlButton("shuffle")
            controlButton("repeat")
            controlButton("backward.end.fill")
            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MXColor.black)
                    .frame(width: 24, height: 24)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.accent)
                    )
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(MXColor.black)
                    )
            }
            .buttonStyle(.plain)
            controlButton("forward.end.fill")
            controlButton("heart")
            controlButton("ellipsis")
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }

    private func controlButton(_ systemName: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MXColor.lightGrey)
                .frame(width: 18, height: 18)
        }
        .mxMetalButton(.icon)
    }

    private var tags: some View {
        HStack(spacing: 12) {
            ForEach(["#pop", "#rock", "#alternativerock"], id: \.self) { tag in
                Text(tag)
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.accent)
            }
        }
        .padding(.top, 14)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2")
                .foregroundStyle(MXColor.grey)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MXColor.layer2).frame(height: 4)
                    Capsule()
                        .fill(MXColor.accent)
                        .frame(width: geo.size.width * volume, height: 4)
                    Circle()
                        .fill(MXColor.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: geo.size.width * volume - 7)
                }
                .frame(maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            volume = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                )
            }
            .frame(height: 24)
            Text("\(Int(volume * 100))")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var continuePlaying: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Playing")
                .font(MXFont.header3())
                .foregroundStyle(MXColor.lightGrey)

            HStack(spacing: 12) {
                Image("photo_continue")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Frag's Favs")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    HStack(spacing: 4) {
                        Text("Frags")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MXColor.accent)
                        Text("02:16")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                    }
                }
                Spacer()
                Image(systemName: "heart")
                    .foregroundStyle(MXColor.grey)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }
}

#Preview("Now Playing") {
    NowPlayingView()
}
