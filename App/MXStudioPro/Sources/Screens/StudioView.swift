import SwiftUI

/// Studio shell matching Figma `Studio - After Record Audio or Vocal` (95:85026).
public struct StudioView: View {
    @Bindable var session: StudioSessionController
    public var onClose: () -> Void

    @State private var showBPMSheet = false
    @State private var showMetronomeSheet = false
    @State private var selectedTrackID: UUID?

    private let trackColumnWidth: CGFloat = 135
    private let beatsVisible: Double = 8

    public init(session: StudioSessionController, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if session.isRecordMode {
                // Figma 95:83675 — Record Vocal or Audio with Mic
                RecordVocalView(session: session, onClose: { session.exitRecordMode() })
            } else {
                // Figma 95:85026 — Studio - After Record Audio or Vocal
                afterRecordStudio
            }
        }
        .background(MXColor.surface.ignoresSafeArea())
        .onAppear {
            session.start()
            selectedTrackID = session.project.armedTrack?.id ?? session.project.tracks.first?.id
        }
        .onChange(of: session.isRecordMode) { _, inRecord in
            // Leaving record mode lands on After Record Studio with the armed track selected.
            if !inRecord {
                selectedTrackID = session.project.armedTrack?.id ?? session.project.tracks.first?.id
            }
        }
        .onDisappear { session.shutdown() }
        .sheet(isPresented: $showBPMSheet) {
            bpmSheet
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showMetronomeSheet) {
            metronomeSheet
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    /// Arrangement + transport chrome for Figma `Studio - After Record Audio or Vocal` (95:85026).
    private var afterRecordStudio: some View {
        VStack(spacing: 0) {
            studioHeader
            arrangement
            studioDetailsStrip
            actionBoard
        }
    }

    // MARK: - Header (95:85029)

    private var studioHeader: some View {
        HStack {
            HStack(spacing: 2) {
                studioIconButton(asset: "studio_back", systemFallback: "rectangle.portrait.and.arrow.right") {
                    onClose()
                }
                studioIconButton(asset: "studio_tuner_a", systemFallback: "tuningfork") {
                    // Tuner — Month 5
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button {} label: {
                    HStack(spacing: 6) {
                        studioGlyph("studio_plus", systemFallback: "plus", size: 20)
                        Text("Collab")
                            .font(MXFont.mediumButton())
                            .foregroundStyle(MXColor.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)

                studioIconButton(asset: "studio_fx", systemFallback: "wand.and.stars") {}
                studioIconButton(asset: "studio_settings", systemFallback: "gearshape") {}
                studioIconButton(asset: "studio_export", systemFallback: "square.and.arrow.up") {}
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
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    // MARK: - Arrangement (track list + beat net)

    private var arrangement: some View {
        HStack(alignment: .top, spacing: 0) {
            trackListColumn
                .frame(width: trackColumnWidth)

            beatNet
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MXColor.surface)
    }

    private var trackListColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.playheadTimeLabel)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.grey)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .frame(height: 20)

            ForEach(session.project.tracks) { track in
                StudioTrackHeader(
                    track: track,
                    isSelected: selectedTrackID == track.id,
                    onSelect: { selectedTrackID = track.id },
                    onMute: { session.toggleMute(trackID: track.id) },
                    onSolo: { session.toggleSolo(trackID: track.id) }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, 4)
        .background(MXColor.surface)
    }

    private var beatNet: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let pixelsPerBeat = width / beatsVisible

            ZStack(alignment: .topLeading) {
                MXColor.surface

                // Ruler
                HStack(spacing: 0) {
                    ForEach(0..<Int(beatsVisible), id: \.self) { beat in
                        let isBar = beat % session.project.timeSignatureNumerator == 0
                        VStack(spacing: 0) {
                            Text(isBar ? "\(beat / session.project.timeSignatureNumerator + 1)" : "1")
                                .font(isBar ? MXFont.body3() : MXFont.caption())
                                .foregroundStyle(isBar ? MXColor.lightGrey : MXColor.grey)
                                .frame(height: 24, alignment: .bottom)
                            Spacer(minLength: 0)
                        }
                        .frame(width: pixelsPerBeat, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(isBar ? MXColor.layer2 : MXColor.layer2.opacity(0.45))
                                .frame(width: 1)
                        }
                    }
                }
                .frame(height: geo.size.height)

                // Vertical grid lines through lanes
                ForEach(0..<Int(beatsVisible), id: \.self) { beat in
                    Rectangle()
                        .fill(beat % session.project.timeSignatureNumerator == 0
                              ? MXColor.layer2
                              : MXColor.layer2.opacity(0.35))
                        .frame(width: 1, height: geo.size.height - 24)
                        .offset(x: CGFloat(beat) * pixelsPerBeat, y: 24)
                }

                // Track lanes + clips / placeholder waveform
                VStack(spacing: 4) {
                    Color.clear.frame(height: 24)
                    ForEach(Array(session.project.tracks.enumerated()), id: \.element.id) { index, track in
                        trackLane(track: track, width: width, pixelsPerBeat: pixelsPerBeat, isPrimary: index == 0)
                            .frame(height: 60)
                    }
                    Spacer(minLength: 0)
                }

                // Playhead
                Rectangle()
                    .fill(MXColor.white)
                    .frame(width: 1.5, height: geo.size.height - 8)
                    .offset(x: playheadX(pixelsPerBeat: pixelsPerBeat), y: 16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let beat = Double(value.location.x / pixelsPerBeat)
                        session.seek(toBeat: max(0, beat))
                    }
            )
        }
    }

    private func trackLane(track: MXSessionTrack, width: CGFloat, pixelsPerBeat: CGFloat, isPrimary: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.surfaceRaised.opacity(0.35))

            if track.clips.isEmpty {
                if isPrimary {
                    Text("Tap ● to record")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                        .padding(.leading, 12)
                }
            } else {
                ForEach(track.clips) { clip in
                    StudioWaveformClip()
                        .frame(
                            width: max(24, CGFloat(clip.lengthBeats) * pixelsPerBeat),
                            height: 52
                        )
                        .offset(x: CGFloat(clip.startBeat) * pixelsPerBeat)
                        .accessibilityLabel(clip.name)
                }
            }
        }
    }

    private func playheadX(pixelsPerBeat: CGFloat) -> CGFloat {
        CGFloat(session.playheadBeat.truncatingRemainder(dividingBy: beatsVisible)) * pixelsPerBeat
    }

    // MARK: - Details strip (95:85071)

    private var studioDetailsStrip: some View {
        HStack(spacing: 0) {
            detailCell(value: String(format: "%03d", session.playheadBar), label: "Bar")
            detailDivider
            detailCell(value: "\(session.playheadBeatInBar)", label: "Beat")
            detailDivider
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            detailDivider
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
                .frame(width: 125)

                Button { showBPMSheet = true } label: {
                    HStack(spacing: 2) {
                        Text(session.countInBars > 0 ? "Count \(session.countInBars)" : "Keep")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(MXColor.grey)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 16)
            .frame(width: 125)
        }
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    private func detailCell(value: String, label: String) -> some View {
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

    private var detailDivider: some View {
        Rectangle().fill(MXColor.layer2).frame(width: 1)
    }

    // MARK: - Action board (95:85072)

    private var actionBoard: some View {
        HStack {
            HStack(spacing: 2) {
                studioIconButton(asset: "studio_undo", systemFallback: "arrow.uturn.backward") {}
                studioIconButton(asset: "studio_redo", systemFallback: "arrow.uturn.forward") {}
                studioIconButton(asset: "studio_to_start", systemFallback: "chevron.backward.2") {
                    session.stop()
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )

            Spacer(minLength: 8)

            Button {
                session.enterRecordMode()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(width: 52, height: 52)
                    Circle()
                        .fill(MXColor.red)
                        .frame(width: 28, height: 28)
                }
                .padding(4)
                .background(
                    Capsule(style: .continuous)
                        .fill(MXColor.black)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.phase != .ready || session.isInterrupted)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button(action: session.togglePlayback) {
                    Group {
                        if session.isPlaying {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MXColor.white)
                                .frame(width: 20, height: 20)
                        } else {
                            studioGlyph("studio_play", systemFallback: "play.fill", size: 20)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(session.phase != .ready || session.isInterrupted)

                Button {
                    session.isMetronomeEnabled.toggle()
                } label: {
                    studioGlyph("studio_metro", systemFallback: "metronome.fill", size: 20)
                        .foregroundStyle(session.isMetronomeEnabled ? MXColor.accent : MXColor.white)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                        .overlay {
                            if session.isMetronomeEnabled {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(MXColor.accent.opacity(0.7), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        showMetronomeSheet = true
                    }
                )

                studioIconButton(asset: "studio_mixer", systemFallback: "slider.horizontal.3") {}
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MXColor.surfaceRaised)
    }

    // MARK: - Sheets

    private var bpmSheet: some View {
        VStack(spacing: 20) {
            Text("Tempo")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)

            HStack(spacing: 24) {
                Button { session.nudgeBPM(-1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(MXColor.layer2))
                }
                .buttonStyle(.plain)

                Text(String(format: "%.0f", session.bpm))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(MXColor.accent)
                    .monospacedDigit()
                    .frame(minWidth: 100)

                Button { session.nudgeBPM(1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(MXColor.layer2))
                }
                .buttonStyle(.plain)
            }

            Slider(
                value: Binding(
                    get: { session.bpm },
                    set: { session.setBPM($0) }
                ),
                in: 40...240,
                step: 1
            )
            .tint(MXColor.accent)
            .padding(.horizontal, 24)

            Picker("Count-in", selection: Binding(
                get: { session.countInBars },
                set: { session.countInBars = $0 }
            )) {
                Text("Off").tag(0)
                Text("1 bar").tag(1)
                Text("2 bars").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .background(MXColor.surface)
    }

    private var metronomeSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Metronome")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)

            Toggle(isOn: $session.isMetronomeEnabled) {
                Text("Click enabled")
                    .foregroundStyle(MXColor.white)
            }
            .tint(MXColor.accent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Level")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                Slider(
                    value: Binding(
                        get: { Double(session.metronomeLevel) },
                        set: { session.metronomeLevel = Float($0) }
                    ),
                    in: 0...1
                )
                .tint(MXColor.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(MXColor.surface)
    }

    // MARK: - Helpers

    private func studioIconButton(asset: String, systemFallback: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            studioGlyph(asset, systemFallback: systemFallback, size: 20)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(MXColor.layer2)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func studioGlyph(_ asset: String, systemFallback: String, size: CGFloat) -> some View {
        if UIImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(MXColor.white)
                .frame(width: size, height: size)
        } else {
            Image(systemName: systemFallback)
                .font(.system(size: size * 0.72, weight: .semibold))
                .foregroundStyle(MXColor.white)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Track header (95:85033)

private struct StudioTrackHeader: View {
    let track: MXSessionTrack
    var isSelected: Bool
    var onSelect: () -> Void
    var onMute: () -> Void
    var onSolo: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MXColor.accent)
                        Text(track.name.uppercased())
                            .font(MXFont.studioTrackName())
                            .foregroundStyle(MXColor.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MXColor.grey)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MXColor.black).frame(height: 6)
                            Capsule()
                                .fill(MXColor.accent)
                                .frame(width: geo.size.width * CGFloat(track.volume), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.vertical, 7)
                }

                VStack(spacing: 4) {
                    muteSoloButton("M", active: track.isMuted, action: onMute)
                    muteSoloButton("S", active: track.isSolo, action: onSolo)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.layer2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? MXColor.accent : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private func muteSoloButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MXFont.caption())
                .fontWeight(.medium)
                .foregroundStyle(active ? MXColor.black : MXColor.lightGrey)
                .frame(width: 20, height: 20)
                .background(active ? MXColor.accent : MXColor.layer2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder waveform clip

private struct StudioWaveformClip: View {
    private let samples: [CGFloat] = {
        (0..<64).map { i in
            let t = Double(i) / 64.0
            let envelope = sin(t * .pi)
            let buzz = abs(sin(t * 18)) * 0.55 + abs(sin(t * 41)) * 0.35
            return CGFloat(max(0.12, envelope * buzz))
        }
    }()

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let step = size.width / CGFloat(samples.count)
            for (index, sample) in samples.enumerated() {
                let h = sample * size.height * 0.9
                let x = CGFloat(index) * step
                let rect = CGRect(x: x, y: mid - h / 2, width: max(1, step * 0.7), height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(MXColor.accent))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.layer2.opacity(0.65))
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

#Preview("Studio") {
    StudioView(session: StudioSessionController(preset: .vocal), onClose: {})
}
