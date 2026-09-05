import SwiftUI
import MXStudioEngine

/// Record Vocal / Audio screen — Figma `95:83675` / track focus `95:91592` / landscape `95:81418`.
struct RecordVocalView: View {
    @Bindable var session: StudioSessionController
    var onClose: () -> Void
    /// Opens the Studio Track FX / Pedalboard sheet (wired from `StudioView`).
    var onOpenFX: (() -> Void)? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Figma Box Bottom Pop-up: 8pt pad + 70pt track card.
    private let mixerStripHeight: CGFloat = 86
    /// Figma Studio Details row.
    private let detailsStripHeight: CGFloat = 70

    /// Compact landscape record chrome (Figma Recording landscape `95:81418`).
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var armedTrack: MXSessionTrack? {
        session.project.armedTrack ?? session.project.tracks.first
    }

    var body: some View {
        ZStack {
            // Figma `95:91592` stack: Header → Net → Mixer 86 → Details 70 → Transport 76.
            VStack(spacing: 0) {
                recordHeader
                    .frame(height: isLandscape ? 56 : 68)
                if session.showClipWarning {
                    clipWarningBanner
                }

                ZStack(alignment: .top) {
                    liveWaveform
                    if !isLandscape {
                        captureQualityStrip
                            .padding(.top, 8)
                    } else {
                        captureQualityStrip
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                // Landscape: hide mixer strip — meter + Monitor cover levels (GarageBand densify).
                if !isLandscape, let track = armedTrack {
                    mixerStrip(track: track)
                        .frame(height: mixerStripHeight)
                        .clipped()
                }
                if !isLandscape {
                    instrumentsStrip
                        .frame(height: 72)
                        .clipped()
                }
                detailsStrip
                    .frame(height: isLandscape ? 58 : detailsStripHeight)
                    .clipped()
                actionBoard
                    .frame(height: isLandscape ? 64 : 76)
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

    private var isGuitarCapture: Bool {
        armedTrack?.category == .guitar || session.preset == .guitar
    }

    private var recordHeader: some View {
        HStack(spacing: isLandscape ? 10 : 16) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGuitarCapture ? "Pedalboard" : "No Fx")
                        .font(MXFont.smallButton())
                        .foregroundStyle(MXColor.white)
                    if !isLandscape {
                        Text(armedTrack?.name ?? (isGuitarCapture ? "Guitar" : "Vocal/Audio"))
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                    }
                }
                if !isLandscape {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MXColor.grey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Button {
                    onOpenFX?()
                } label: {
                    Text(isGuitarCapture ? "Pedals" : "EQ")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                        .padding(isLandscape ? 8 : 10)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGuitarCapture ? "Pedalboard" : "Track FX")

                if !isLandscape {
                    metalIcon("square.and.arrow.up")
                    metalIcon("ellipsis")
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(isLandscape ? 8 : 10)
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
        .padding(.horizontal, isLandscape ? 12 : 16)
        .padding(.vertical, isLandscape ? 6 : 12)
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
            let signalHeight = min(isLandscape ? 140 : 180, max(100, geo.size.height * (isLandscape ? 0.72 : 0.42)))
            ZStack {
                LinearGradient(
                    colors: [MXColor.surface, Color(hex: 0x14181C), MXColor.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { beat in
                        Rectangle()
                            .fill(beat % 4 == 0 ? MXColor.layer2.opacity(0.8) : MXColor.layer2.opacity(0.35))
                            .frame(width: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

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
                .frame(height: signalHeight)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    Spacer().frame(width: playheadOffset(width: max(geo.size.width, 1)))
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

    // MARK: - Capture quality

    private var captureQualityStrip: some View {
        VStack(alignment: .leading, spacing: isLandscape ? 0 : 2) {
            HStack(spacing: 12) {
                Toggle(isOn: $session.isHighPassEnabled) {
                    Text(isGuitarCapture ? "Cut rumble (DI)" : "Cut rumble")
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

            // Landscape: hide tip copy — toggles only (Figma densify).
            if !isLandscape {
                if let tip = session.headphoneTip {
                    Text(tip)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isGuitarCapture {
                    Text("Input: phone mic or Lightning/USB DI — same record path.")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, isLandscape ? 12 : 16)
        .padding(.vertical, isLandscape ? 6 : 10)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
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
                Text(isGuitarCapture ? "Arming input…" : "Arming mic…")
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
        let guitar = track.category == .guitar || session.preset == .guitar
        let tint = guitar ? MXColor.teal : MXColor.accent
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: guitar ? "guitars.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(track.name.uppercased())
                        .font(MXFont.studioTrackName())
                        .foregroundStyle(MXColor.white)
                        .lineLimit(1)
                    if guitar {
                        Text("PEDALS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MXColor.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(MXColor.teal)
                            )
                    }
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
                    .tint(tint)

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

    // MARK: - Instruments

    private var instrumentChoices: [MXSynthBankPreset] {
        MXSynthBankPreset.pianoBank + [.drumKit]
    }

    private var instrumentsStrip: some View {
        let active = session.activeInstrumentPreset()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Add Instrument")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(instrumentChoices) { bank in
                        let isOn = active == bank
                        Button {
                            _ = session.addOrSwitchInstrument(bank)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bank.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(isOn ? MXColor.black : MXColor.white)
                                Text(bank.subtitle)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(isOn ? MXColor.black.opacity(0.7) : MXColor.grey)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isOn ? MXColor.orange : MXColor.layer2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(bank.title) instrument")
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
    }

    // MARK: - Details + transport (shared look)

    private var detailsStrip: some View {
        let vPad: CGFloat = isLandscape ? 8 : 16
        return HStack(spacing: 0) {
            detail(String(format: "%03d", session.playheadBar), "Bar", verticalPadding: vPad)
            divider
            detail("\(session.playheadBeatInBar)", "Beat", verticalPadding: vPad)
            divider
            VStack(spacing: isLandscape ? 2 : 4) {
                Text("\(session.project.timeSignatureNumerator)/\(session.project.timeSignatureDenominator)")
                    .font(MXFont.studioReadout())
                    .foregroundStyle(MXColor.lightGrey)
                Text(session.musicalKey)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, vPad)
            divider
            VStack(spacing: isLandscape ? 2 : 4) {
                HStack {
                    Button { session.nudgeMasterPitch(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MXColor.lightGrey)
                            .frame(width: 20, height: 20)
                            .background(MXColor.layer2)
                    }
                    .buttonStyle(.plain)
                    Text(masterPitchLabel)
                        .font(MXFont.studioReadout())
                        .foregroundStyle(MXColor.lightGrey)
                        .frame(minWidth: 36)
                    Button { session.nudgeMasterPitch(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MXColor.lightGrey)
                            .frame(width: 20, height: 20)
                            .background(MXColor.layer2)
                    }
                    .buttonStyle(.plain)
                }
                Text("Pitch")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            .frame(width: isLandscape ? 110 : 125)
            .padding(.vertical, vPad)
            divider
            VStack(spacing: isLandscape ? 2 : 4) {
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
            .frame(width: isLandscape ? 110 : 125)
            .padding(.vertical, vPad)
        }
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(MXColor.layer2).frame(height: 1) }
    }

    private var masterPitchLabel: String {
        let semitones = Int(session.masterPitchSemitones.rounded())
        if semitones == 0 { return "0" }
        return semitones > 0 ? "+\(semitones)" : "\(semitones)"
    }

    private func detail(_ value: String, _ label: String, verticalPadding: CGFloat = 16) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(MXFont.studioReadout())
                .foregroundStyle(MXColor.lightGrey)
            Text(label)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
    }

    private var divider: some View {
        Rectangle().fill(MXColor.layer2).frame(width: 1)
    }

    private var actionBoard: some View {
        let recOuter: CGFloat = isLandscape ? 40 : 52
        let recInner: CGFloat = isLandscape ? 22 : 28
        let stopInner: CGFloat = isLandscape ? 16 : 22
        let pad: CGFloat = isLandscape ? 7 : 10
        return HStack {
            HStack(spacing: 2) {
                if !isLandscape {
                    transportIcon("arrow.uturn.backward") {}
                    transportIcon("arrow.uturn.forward") {}
                }
                transportIcon("chevron.backward.2", pad: pad) { session.stop() }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MXColor.black))

            Spacer()

            Button {
                session.toggleRecord()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: isLandscape ? 12 : 16, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(width: recOuter, height: recOuter)
                    if session.isRecording {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.red)
                            .frame(width: stopInner, height: stopInner)
                    } else {
                        Circle()
                            .fill(MXColor.red)
                            .frame(width: recInner, height: recInner)
                    }
                }
                .padding(4)
                .background(Capsule(style: .continuous).fill(MXColor.black))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isRecording ? "Stop recording" : "Record")

            Spacer()

            HStack(spacing: 2) {
                Button(action: session.togglePlayback) {
                    Image(systemName: session.isPlaying && !session.isRecording ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(pad)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
                }
                .buttonStyle(.plain)
                .disabled(session.isRecording)

                Button { session.isMetronomeEnabled.toggle() } label: {
                    Image(systemName: "metronome.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(session.isMetronomeEnabled ? MXColor.accent : MXColor.white)
                        .frame(width: 20, height: 20)
                        .padding(pad)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
                        .overlay {
                            if session.isMetronomeEnabled {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(MXColor.accent.opacity(0.7), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)

                if !isLandscape {
                    Button { session.setMasterPitch(0) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                abs(session.masterPitchSemitones) > 0.01 ? MXColor.orange : MXColor.white
                            )
                            .frame(width: 20, height: 20)
                            .padding(pad)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(MXColor.layer2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset master pitch")
                    .disabled(abs(session.masterPitchSemitones) < 0.01)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MXColor.black))
        }
        .padding(.horizontal, isLandscape ? 12 : 16)
        .padding(.vertical, isLandscape ? 4 : 8)
        .background(MXColor.surfaceRaised)
    }

    private func transportIcon(_ systemName: String, pad: CGFloat = 10, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MXColor.white)
                .frame(width: 20, height: 20)
                .padding(pad)
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
