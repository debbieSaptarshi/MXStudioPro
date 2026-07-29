import SwiftUI

/// Record Vocal / Audio screen (Figma 95:83675) — working features over pixel-perfect layout.
struct RecordVocalView: View {
    @Bindable var session: StudioSessionController
    var onClose: () -> Void

    private var armedTrack: MXSessionTrack? {
        session.project.armedTrack ?? session.project.tracks.first
    }

    var body: some View {
        VStack(spacing: 0) {
            recordHeader
            liveWaveform
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let track = armedTrack {
                mixerStrip(track: track)
            }
            detailsStrip
            actionBoard
        }
        .background(MXColor.surface.ignoresSafeArea())
        .task {
            if !session.isRecording {
                await session.startRecording()
            }
        }
    }

    // MARK: - Header

    private var recordHeader: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Fx")
                        .font(MXFont.smallButton())
                        .foregroundStyle(MXColor.white)
                    Text(armedTrack?.name ?? "Vocal/Audio")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Text("EQ")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )

                metalIcon("square.and.arrow.up")
                metalIcon("ellipsis")
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
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surfaceRaised)
    }

    private func metalIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MXColor.white)
            .frame(width: 20, height: 20)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.layer2)
            )
    }

    // MARK: - Live waveform

    private var liveWaveform: some View {
        GeometryReader { geo in
            ZStack {
                MXColor.surface

                // Beat grid backdrop
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { beat in
                        Rectangle()
                            .fill(beat % 4 == 0 ? MXColor.layer2.opacity(0.8) : MXColor.layer2.opacity(0.35))
                            .frame(width: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                LiveInputWaveform(level: session.inputLevel, isActive: session.isRecording)
                    .frame(height: min(160, geo.size.height * 0.45))
                    .padding(.horizontal, 8)

                // Playhead
                Rectangle()
                    .fill(MXColor.white)
                    .frame(width: 1.5)
                    .offset(x: playheadOffset(width: geo.size.width) - geo.size.width / 2)

                VStack {
                    Spacer()
                    statusCaption
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var statusCaption: some View {
        Group {
            if let error = session.recordError {
                Text(error)
                    .foregroundStyle(MXColor.red)
            } else if session.isCountingIn {
                Text("Count-in…")
                    .foregroundStyle(MXColor.accent)
            } else if session.isRecording {
                Text("Recording \(session.playheadTimeLabel)")
                    .foregroundStyle(MXColor.red)
            } else {
                Text("Arming mic…")
                    .foregroundStyle(MXColor.grey)
            }
        }
        .font(MXFont.body3())
    }

    private func playheadOffset(width: CGFloat) -> CGFloat {
        let beat = session.playheadBeat.truncatingRemainder(dividingBy: 8)
        return CGFloat(beat / 8.0) * width
    }

    // MARK: - Mixer strip

    private func mixerStrip(track: MXSessionTrack) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MXColor.accent)
                    Text(track.name.uppercased())
                        .font(MXFont.studioTrackName())
                        .foregroundStyle(MXColor.white)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("VOL")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .frame(width: 28, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { Double(track.volume) },
                            set: { session.setTrackVolume(Float($0), trackID: track.id) }
                        ),
                        in: 0...1
                    )
                    .tint(MXColor.accent)

                    Text("\(Int(((track.volume - 1) * 24).rounded()))")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(MXColor.layer2).frame(width: 1)

            VStack(spacing: 4) {
                muteSolo("M", active: track.isMuted) {
                    session.toggleMute(trackID: track.id)
                }
                muteSolo("S", active: track.isSolo) {
                    session.toggleSolo(trackID: track.id)
                }
            }
            .padding(12)

            Rectangle().fill(MXColor.layer2).frame(width: 1)

            VStack(spacing: 4) {
                PanKnob(
                    value: Binding(
                        get: { track.pan },
                        set: { session.setTrackPan($0, trackID: track.id) }
                    )
                )
                HStack {
                    Text("L").font(MXFont.caption()).foregroundStyle(MXColor.grey)
                    Spacer()
                    Text("R").font(MXFont.caption()).foregroundStyle(MXColor.grey)
                }
                .frame(width: 40)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MXColor.layer2, lineWidth: 1)
                )
        )
        .padding(8)
        .background(MXColor.surface)
    }

    private func muteSolo(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MXFont.smallButton())
                .foregroundStyle(active ? MXColor.black : MXColor.lightGrey)
                .frame(width: 24, height: 24)
                .background(active ? MXColor.accent : MXColor.layer2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Details + transport (shared look)

    private var detailsStrip: some View {
        HStack(spacing: 0) {
            detail(String(format: "%03d", session.playheadBar), "Bar")
            divider
            detail("\(session.playheadBeatInBar)", "Beat")
            divider
            VStack(spacing: 4) {
                Text("\(session.project.timeSignatureNumerator)/\(session.project.timeSignatureDenominator)")
                    .font(MXFont.studioReadout())
                    .foregroundStyle(MXColor.lightGrey)
                Text(session.musicalKey)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            divider
            VStack(spacing: 4) {
                HStack {
                    Button { session.nudgeBPM(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MXColor.lightGrey)
                            .frame(width: 20, height: 20)
                            .background(MXColor.layer2)
                    }
                    .buttonStyle(.plain)
                    Text(String(format: "%.0f", session.bpm))
                        .font(MXFont.studioReadout())
                        .foregroundStyle(MXColor.lightGrey)
                        .frame(minWidth: 36)
                    Button { session.nudgeBPM(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MXColor.lightGrey)
                            .frame(width: 20, height: 20)
                            .background(MXColor.layer2)
                    }
                    .buttonStyle(.plain)
                }
                Text("BPM")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            .frame(width: 125)
            .padding(.vertical, 16)
        }
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
    }

    private func detail(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(MXFont.studioReadout())
                .foregroundStyle(MXColor.lightGrey)
            Text(label)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var divider: some View {
        Rectangle().fill(MXColor.layer2).frame(width: 1)
    }

    private var actionBoard: some View {
        HStack {
            HStack(spacing: 2) {
                transportIcon("arrow.uturn.backward") {}
                transportIcon("arrow.uturn.forward") {}
                transportIcon("chevron.backward.2") { session.stop() }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MXColor.black))

            Spacer()

            Button {
                session.toggleRecord()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(width: 52, height: 52)
                    if session.isRecording {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.red)
                            .frame(width: 22, height: 22)
                    } else {
                        Circle()
                            .fill(MXColor.red)
                            .frame(width: 28, height: 28)
                    }
                }
                .padding(4)
                .background(Capsule(style: .continuous).fill(MXColor.black))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 2) {
                Button(action: session.togglePlayback) {
                    Image(systemName: session.isPlaying && !session.isRecording ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
                }
                .buttonStyle(.plain)
                .disabled(session.isRecording)

                Button { session.isMetronomeEnabled.toggle() } label: {
                    Image(systemName: "metronome.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(session.isMetronomeEnabled ? MXColor.accent : MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
                        .overlay {
                            if session.isMetronomeEnabled {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(MXColor.accent.opacity(0.7), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)

                transportIcon("slider.horizontal.3") {}
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MXColor.black))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MXColor.surfaceRaised)
    }

    private func transportIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MXColor.white)
                .frame(width: 20, height: 20)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live waveform

private struct LiveInputWaveform: View {
    var level: Float
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                let mid = size.height / 2
                let bars = 72
                let step = size.width / CGFloat(bars)
                let t = timeline.date.timeIntervalSinceReferenceDate
                let base = CGFloat(max(0.05, level))

                for i in 0..<bars {
                    let phase = Double(i) * 0.35 + t * 8
                    let wobble = abs(sin(phase)) * 0.55 + abs(sin(phase * 1.7)) * 0.45
                    let h = max(4, base * size.height * 0.95 * CGFloat(wobble))
                    let x = CGFloat(i) * step
                    let rect = CGRect(x: x, y: mid - h / 2, width: max(1.5, step * 0.55), height: h)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(MXColor.accent)
                    )
                }
            }
        }
    }
}

// MARK: - Pan knob

private struct PanKnob: View {
    @Binding var value: Float

    var body: some View {
        ZStack {
            Circle()
                .fill(MXColor.layer2)
            Circle()
                .trim(from: 0.15, to: 0.15 + 0.35 * Double((value + 1) / 2))
                .stroke(MXColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Capsule()
                .fill(MXColor.accent)
                .frame(width: 2, height: 10)
                .offset(y: -8)
                .rotationEffect(.degrees(Double(value) * 120))
        }
        .frame(width: 32, height: 32)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let delta = Float(gesture.translation.width / 80)
                    value = min(max(value + delta * 0.08, -1), 1)
                }
        )
    }
}
