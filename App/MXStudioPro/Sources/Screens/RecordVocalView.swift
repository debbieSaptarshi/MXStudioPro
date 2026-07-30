import SwiftUI

/// Record Vocal / Audio screen — Figma `95:83675` / track focus `95:91592`.
struct RecordVocalView: View {
    @Bindable var session: StudioSessionController
    var onClose: () -> Void
    /// Opens the Studio Track FX / Pedalboard sheet (wired from `StudioView`).
    var onOpenFX: (() -> Void)? = nil

    /// Figma Box Bottom Pop-up: 8pt pad + 70pt track card.
    private let mixerStripHeight: CGFloat = 86
    /// Figma Studio Details row.
    private let detailsStripHeight: CGFloat = 70

    private var armedTrack: MXSessionTrack? {
        session.project.armedTrack ?? session.project.tracks.first
    }

    var body: some View {
        ZStack {
            // Figma `95:91592` Bottom Actions stack:
            // Header 68 → Net ~420 → Box Bottom Pop-up 86 → Details 70 → Transport 76.
            VStack(spacing: 0) {
                recordHeader
                    .frame(height: 68)

                if session.showClipWarning {
                    clipWarningBanner
                }

                // Net fills leftover height; toggles overlay top so mixer stays flush under Net.
                ZStack(alignment: .top) {
                    liveWaveform
                    captureQualityOverlay
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                if let track = armedTrack {
                    mixerStrip(track: track)
                        .frame(height: mixerStripHeight)
                        .clipped()
                }

                detailsStrip
                    .frame(height: detailsStripHeight)
                    .clipped()

                actionBoard
                    .frame(height: 76)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MXColor.surface.ignoresSafeArea())

            if session.showQuietRoomTip {
                quietRoomTipOverlay
            }
        }
        .task {
            // Hold auto-Rec while the first-record checklist is up so the
            // user can prep the room (GarageBand / BandLab first-capture UX).
            if !session.isRecording && !session.showQuietRoomTip {
                await session.startRecording()
            }
        }
        .onChange(of: session.showQuietRoomTip) { _, showing in
            if !showing && !session.isRecording {
                Task { await session.startRecording() }
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
                    Text(armedTrack?.name ?? (session.preset == .guitar ? "Guitar" : "Vocal/Audio"))
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Button {
                    onOpenFX?()
                } label: {
                    Text("EQ")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Track FX")

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Clip warning

    private var clipWarningBanner: some View {
        Text("Too loud — back off the mic")
            .font(MXFont.body3())
            .foregroundStyle(MXColor.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(MXColor.red)
    }

    // MARK: - Quiet room checklist

    private var quietRoomTipOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Quiet room checklist")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)

                Text(
                    session.preset == .guitar
                        ? "Quick prep before you play — headphones make Monitor safe."
                        : "Quick prep before your first take — Reels-ready vocals start here."
                )
                .font(MXFont.body3())
                .foregroundStyle(MXColor.lightGrey)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(QuietRoomChecklistItem.allCases) { item in
                        quietRoomChecklistRow(item)
                    }
                }

                // Live mic cue while checklist is up (input is armed).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MXColor.layer2)
                        Capsule()
                            .fill(session.isInputClipping ? MXColor.red : MXColor.accent)
                            .frame(width: max(4, geo.size.width * CGFloat(min(session.inputLevel, 1))))
                    }
                }
                .frame(height: 6)
                .padding(.top, 2)

                Button {
                    session.dismissQuietRoomTip()
                } label: {
                    Text(session.isQuietRoomChecklistComplete ? "Start recording" : "Skip & record")
                        .font(MXFont.smallButton())
                        .foregroundStyle(MXColor.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(MXColor.accent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MXColor.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(MXColor.layer2, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }

    private func quietRoomChecklistRow(_ item: QuietRoomChecklistItem) -> some View {
        let done = session.quietRoomChecklistDone.contains(item.rawValue)
        return Button {
            session.toggleQuietRoomChecklistItem(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(done ? MXColor.accent : MXColor.grey)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MXColor.grey)
                        Text(item.title)
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.white)
                    }
                    Text(item.detail)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.lightGrey)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(done ? MXColor.layer2.opacity(0.55) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live waveform

    private var liveWaveform: some View {
        GeometryReader { geo in
            // Figma Track Signal ≈ 157pt tall, vertically centered in Net.
            let signalHeight = min(157, max(120, geo.size.height * 0.38))
            ZStack {
                // Soft depth behind the Metal wave
                LinearGradient(
                    colors: [
                        MXColor.surface,
                        Color(hex: 0x14181C),
                        MXColor.surface
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Beat grid backdrop
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { beat in
                        Rectangle()
                            .fill(beat % 4 == 0 ? MXColor.layer2.opacity(0.8) : MXColor.layer2.opacity(0.35))
                            .frame(width: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Ambient glow plate under the signal
                Capsule(style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                (session.isInputClipping ? MXColor.red : MXColor.accent).opacity(0.18),
                                MXColor.teal.opacity(0.06),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: max(geo.size.width * 0.55, 80)
                        )
                    )
                    .frame(height: signalHeight * 1.35)
                    .blur(radius: 18)

                MetalLiveWaveformView(
                    level: session.inputLevel,
                    isActive: session.isRecording || session.isCountingIn || session.isRecordMode,
                    isClipping: session.isInputClipping,
                    beatPulse: session.isCountingIn || session.isMetronomeEnabled
                        ? Float(max(0, 1.0 - (session.playheadBeat.truncatingRemainder(dividingBy: 1.0)) * 2.2))
                        : 0
                )
                .frame(height: max(signalHeight, geo.size.height * 0.42))
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

                // Playhead
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: playheadOffset(width: max(geo.size.width, 1)))
                    Rectangle()
                        .fill(MXColor.white)
                        .frame(width: 1.5)
                    Spacer(minLength: 0)
                }

                VStack {
                    Spacer()
                    statusCaption
                        .padding(.bottom, 10)
                }

                // Peak meter — practical for record; sits at Net trailing edge.
                HStack {
                    Spacer()
                    InputPeakMeter(
                        level: session.inputLevel,
                        peakHold: session.peakHoldLevel,
                        isClipping: session.isInputClipping
                    )
                    .frame(width: 8)
                    .padding(.vertical, 20)
                    .padding(.trailing, 6)
                }
            }
        }
    }

    // MARK: - Capture quality (overlay on waveform so Figma stack stays Net → Mixer → Details)

    private var captureQualityOverlay: some View {
        // Kept as product affordance; pinned to Net top so Figma Net→Mixer stack stays flush.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Toggle(isOn: $session.isHighPassEnabled) {
                    Text("Cut rumble")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.lightGrey)
                }
                .toggleStyle(CaptureQualityToggleStyle())

                Toggle(isOn: $session.isMonitoringEnabled) {
                    Text("Monitor")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.lightGrey)
                }
                .toggleStyle(CaptureQualityToggleStyle())

                Spacer(minLength: 0)
            }

            if let tip = session.headphoneTip {
                Text(tip)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MXColor.surface.opacity(0.9), MXColor.surface.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
        // Figma Box Bottom Pop-up (`158:109232`): 70pt track card in 8pt pad.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: session.preset == .guitar ? "guitars.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.accent)
                        .frame(width: 16, height: 16)
                    Text(track.name)
                        .font(MXFont.studioTrackName())
                        .foregroundStyle(MXColor.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .textCase(.uppercase)
                }

                HStack(spacing: 0) {
                    Text("Vol")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .textCase(.uppercase)
                        .frame(width: 24, alignment: .leading)

                    CompactVolumeBar(
                        value: Binding(
                            get: { Double(track.volume) },
                            set: { session.setTrackVolume(Float($0), trackID: track.id) }
                        )
                    )
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)

                    Text("\(Int(((track.volume - 1) * 24).rounded()))")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .frame(width: 16, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(MXColor.layer2)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(spacing: 4) {
                muteSolo("M", active: track.isMuted) {
                    session.toggleMute(trackID: track.id)
                }
                muteSolo("S", active: track.isSolo) {
                    session.toggleSolo(trackID: track.id)
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(MXColor.layer2)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(spacing: 0) {
                PanKnob(
                    value: Binding(
                        get: { track.pan },
                        set: { session.setTrackPan($0, trackID: track.id) }
                    ),
                    size: 32
                )
                HStack {
                    Text("L").font(MXFont.caption()).foregroundStyle(MXColor.grey)
                    Spacer(minLength: 0)
                    Text("R").font(MXFont.caption()).foregroundStyle(MXColor.grey)
                }
                .frame(width: 32)
            }
            .padding(12)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MXColor.layer2, lineWidth: 1)
                )
        )
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                HStack(spacing: 2) {
                    Text(session.musicalKey)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MXColor.grey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            divider
            VStack(spacing: 4) {
                HStack(spacing: 8) {
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
                Text(session.countInBars > 0 ? "Count \(session.countInBars)" : "Keep")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            .frame(width: 125)
            .frame(maxHeight: .infinity)
        }
        .frame(height: detailsStripHeight)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(MXColor.layer2)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Peak meter

private struct InputPeakMeter: View {
    var level: Float
    var peakHold: Float
    var isClipping: Bool

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(max(level, 0), 1))
            let hold = CGFloat(min(max(peakHold, 0), 1))
            let fillHeight = max(2, geo.size.height * clamped)
            let holdY = geo.size.height * (1 - hold)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.layer2)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isClipping ? MXColor.red : MXColor.accent)
                    .frame(height: fillHeight)

                // Peak hold marker
                Rectangle()
                    .fill(isClipping ? MXColor.red : MXColor.white)
                    .frame(width: geo.size.width, height: 2)
                    .position(x: geo.size.width / 2, y: max(1, min(geo.size.height - 1, holdY)))
            }
        }
    }
}

// MARK: - Compact volume (Figma Box Bottom Pop-up 8pt track)

private struct CompactVolumeBar: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(value, 0), 1)
            let fillW = max(4, geo.size.width * clamped)
            let thumbX = fillW

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.black)
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.accent)
                    .frame(width: fillW, height: 8)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.surface)
                    .frame(width: 6, height: 6)
                    .position(x: min(max(3, thumbX - 3), geo.size.width - 3), y: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = min(max(Double(drag.location.x / max(geo.size.width, 1)), 0), 1)
                    }
            )
        }
        .frame(height: 8)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

// MARK: - Capture toggle style

private struct CaptureQualityToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(configuration.isOn ? MXColor.accent : MXColor.layer2)
                    .frame(width: 28, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(MXColor.white)
                            .frame(width: 12, height: 12)
                            .padding(2)
                    }
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pan knob (shared with Studio mixer channel strips)

struct PanKnob: View {
    @Binding var value: Float
    var size: CGFloat = 32

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
                .frame(width: 2, height: size * 0.31)
                .offset(y: -size * 0.25)
                .rotationEffect(.degrees(Double(value) * 120))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let delta = Float(gesture.translation.width / 80)
                    value = min(max(value + delta * 0.08, -1), 1)
                }
        )
        .accessibilityLabel("Pan")
        .accessibilityValue(panAccessibilityLabel)
    }

    private var panAccessibilityLabel: String {
        if abs(value) < 0.02 { return "Center" }
        return value < 0
            ? String(format: "Left %.0f", abs(value) * 100)
            : String(format: "Right %.0f", value * 100)
    }
}
