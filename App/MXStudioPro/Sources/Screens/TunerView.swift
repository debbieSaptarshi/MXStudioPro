import SwiftUI

/// Chromatic tuner — GarageBand-style pitch readout with cents needle.
struct TunerView: View {
    var onClose: () -> Void

    @State private var engine = MXTunerEngine()

    var body: some View {
        ZStack {
            MXColor.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if engine.permissionState == .denied {
                    permissionDenied
                } else {
                    tunerBody
                }
            }
        }
        .task {
            await engine.requestPermissionAndStart()
        }
        .onDisappear {
            engine.stopListening()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tuningfork")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(MXColor.accent)

            Text("CHROMATIC TUNER")
                .font(MXFont.studioReadout())
                .foregroundStyle(MXColor.lightGrey)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    // MARK: - Body

    private var tunerBody: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text(engine.displayNote)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(engine.isInTune ? MXColor.accent : MXColor.white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: engine.displayNote)

                if engine.signalPresent {
                    Text(String(format: "%.1f Hz", engine.frequencyHz))
                        .font(MXFont.body2())
                        .foregroundStyle(MXColor.grey)
                } else {
                    Text("Play a note near the mic")
                        .font(MXFont.body2())
                        .foregroundStyle(MXColor.grey)
                }
            }

            centsNeedle

            statusBadge

            Spacer()

            Text("Reference A4 = 440 Hz")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var centsNeedle: some View {
        VStack(spacing: 12) {
            HStack {
                Text("♭")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
                Spacer()
                Text("♯")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let clampedCents = max(-50, min(50, engine.cents))
                let normalized = (clampedCents + 50) / 100
                let needleX = width * normalized

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(height: 12)

                    Rectangle()
                        .fill(MXColor.grey.opacity(0.35))
                        .frame(width: 2, height: 20)
                        .offset(x: width / 2 - 1)

                    Circle()
                        .fill(engine.isInTune ? MXColor.accent : MXColor.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: engine.isInTune ? MXColor.accent.opacity(0.5) : .clear, radius: 8)
                        .offset(x: needleX - 9)
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.75), value: engine.cents)
                }
            }
            .frame(height: 20)

            if engine.signalPresent {
                Text(centsLabel)
                    .font(MXFont.mediumButton())
                    .foregroundStyle(engine.isInTune ? MXColor.accent : MXColor.lightGrey)
                    .monospacedDigit()
            } else {
                Text("— cents")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.grey)
            }
        }
    }

    private var centsLabel: String {
        let rounded = Int(engine.cents.rounded())
        if rounded == 0 { return "0 cents" }
        return rounded > 0 ? "+\(rounded) cents" : "\(rounded) cents"
    }

    private var statusBadge: some View {
        Text(engine.isInTune ? "IN TUNE" : (engine.signalPresent ? "ADJUST" : "LISTENING…"))
            .font(MXFont.smallButton())
            .foregroundStyle(engine.isInTune ? MXColor.black : MXColor.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(engine.isInTune ? MXColor.accent : MXColor.layer2)
            )
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(MXColor.grey)
            Text("Microphone access is required to tune.")
                .font(MXFont.body2())
                .foregroundStyle(MXColor.lightGrey)
                .multilineTextAlignment(.center)
            Text("Enable the mic for MXStudio Pro in Settings → Privacy → Microphone.")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

#Preview("Tuner") {
    TunerView(onClose: {})
}
