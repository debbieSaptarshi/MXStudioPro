import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Studio shell matching Figma `Studio - After Record Audio or Vocal` (95:85026).
public struct StudioView: View {
    @Bindable var session: StudioSessionController
    public var onClose: () -> Void
    public var onViewSocials: () -> Void

    @State private var showBPMSheet = false
    @State private var showMetronomeSheet = false
    @State private var showAddTrackSheet = false
    @State private var showAIComposeSheet = false
    @State private var showMixerSheet = false
    @State private var showFXSheet = false
    @State private var showSettingsSheet = false
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var selectedTrackID: UUID?
    @State private var showExportSheet = false
    @State private var showTunerSheet = false
    @State private var showCollabSheet = false
    @State private var showClipInspector = false

    private let trackColumnWidth: CGFloat = 135
    private let beatsVisible: Double = 8
    /// Figma Studio – Guitar (`95:85203`): track lanes / headers are 60pt.
    private let trackLaneHeight: CGFloat = 60
    /// Figma Bottom Actions “Studio Details” row is 70pt.
    private let detailsStripHeight: CGFloat = 70
    private let rulerHeight: CGFloat = 24

    public init(
        session: StudioSessionController,
        onClose: @escaping () -> Void,
        onViewSocials: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onClose = onClose
        self.onViewSocials = onViewSocials
    }

    public var body: some View {
        Group {
            if case .failed(let message) = session.phase {
                studioStartFailureView(message: message)
            } else if session.isRecordMode {
                // Figma 95:83675 — Record Vocal or Audio with Mic
                RecordVocalView(
                    session: session,
                    onClose: { session.exitRecordMode() },
                    onOpenFX: {
                        selectedTrackID = session.project.armedTrack?.id ?? selectedTrackID
                        showFXSheet = true
                    }
                )
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
        .sheet(isPresented: $showAddTrackSheet) {
            addTrackSheet
                .presentationDetents([.height(460)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAIComposeSheet) {
            AIComposeView(
                sessionToImportInto: session,
                onClose: {
                    showAIComposeSheet = false
                    selectedTrackID = session.project.armedTrack?.id ?? session.project.tracks.last?.id
                }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showMixerSheet) {
            mixerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showFXSheet) {
            fxSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettingsSheet) {
            ScrollView {
                studioSettingsSheet
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.importAudioTypes,
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let track = try session.importAudioFile(from: url)
                        selectedTrackID = track.id
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showExportSheet) {
            StudioExportSheet(
                session: session,
                isSignedIn: MXAuthSession.shared.isSignedIn,
                onDismiss: { showExportSheet = false },
                onViewSocials: onViewSocials
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTunerSheet) {
            TunerView(onClose: { showTunerSheet = false })
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCollabSheet) {
            StudioCollabSheet(
                session: session,
                ownerName: MXAuthSession.shared.displayName ?? MXAuthSession.shared.email ?? "You",
                onDismiss: { showCollabSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showClipInspector) {
            clipInspectorSheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .onChange(of: session.selectedClipID) { _, id in
            if id == nil { showClipInspector = false }
        }
    }

    private static let importAudioTypes: [UTType] = {
        var types: [UTType] = [.audio, .wav, .mp3, .mpeg4Audio]
        if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
        if let aac = UTType(filenameExtension: "aac") { types.append(aac) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        return types
    }()

    /// Arrangement + transport chrome for Figma `Studio - Guitar` (`95:85203`) / After Record.
    private var afterRecordStudio: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                studioHeader
                arrangement
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                studioDetailsStrip
                    .frame(height: detailsStripHeight)
                    .fixedSize(horizontal: false, vertical: true)
                if session.showsPianoKeyboard {
                    PianoKeyboardView(
                        onNoteOn: { session.noteOn($0) },
                        onNoteOff: { session.noteOff($0) }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                actionBoard
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let message = session.trackLimitMessage {
                trackLimitBanner(message)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let clipWarning = session.clipLoadWarnings.last {
                clipWarningBanner(clipWarning)
                    .padding(.top, session.trackLimitMessage == nil ? 56 : 96)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if session.isExporting {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    ProgressView("Exporting…")
                        .progressViewStyle(.circular)
                        .tint(MXColor.accent)
                        .foregroundStyle(MXColor.white)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(MXColor.surfaceRaised)
                        )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.trackLimitMessage)
        .animation(.easeInOut(duration: 0.2), value: session.clipLoadWarnings.count)
        .animation(.easeInOut(duration: 0.2), value: session.isExporting)
    }

    // MARK: - Header (95:85029)

    private var studioHeader: some View {
        HStack {
            HStack(spacing: 2) {
                // Asset `studio_back` is a share glyph — use SF Symbol to match Figma back chevron.
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MXColor.white)
                        .frame(width: 20, height: 20)
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
                .accessibilityLabel("Close studio")
                studioIconButton(asset: "studio_tuner_a", systemFallback: "tuningfork") {
                    showTunerSheet = true
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button { showCollabSheet = true } label: {
                    HStack(spacing: 6) {
                        Text("+ Collab")
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
                    .overlay(alignment: .topTrailing) {
                        if session.collaboratorCount > 0 {
                            Text("\(session.collaboratorCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MXColor.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(MXColor.accent))
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)

                studioIconButton(asset: "studio_fx", systemFallback: "wand.and.stars") {
                    showFXSheet = true
                }
                studioIconButton(asset: "studio_settings", systemFallback: "gearshape") {
                    showSettingsSheet = true
                }
                studioIconButton(asset: "studio_export", systemFallback: "square.and.arrow.up") {
                    showExportSheet = true
                }
                .disabled(session.isExporting)
                .opacity(session.isExporting ? 0.4 : 1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MXColor.surface)
    }

    private var trackListColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.playheadTimeLabel)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.grey)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: rulerHeight)

            ForEach(session.project.tracks) { track in
                StudioTrackHeader(
                    track: track,
                    isSelected: selectedTrackID == track.id,
                    isArmed: track.isArmed,
                    onSelect: {
                        selectedTrackID = track.id
                        session.armTrack(id: track.id)
                    },
                    onMute: { session.toggleMute(trackID: track.id) },
                    onSolo: { session.toggleSolo(trackID: track.id) },
                    onSetActiveTake: { session.setActiveTake(clipID: $0) }
                )
                .frame(height: trackLaneHeight)
                .clipped()
            }

            Button {
                showAddTrackSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("ADD TRACK")
                        .font(MXFont.caption())
                        .fontWeight(.semibold)
                }
                .foregroundStyle(session.canAddTrack ? MXColor.lightGrey : MXColor.grey.opacity(0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            session.canAddTrack ? MXColor.layer2 : MXColor.layer2.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!session.canAddTrack)
            .opacity(session.canAddTrack ? 1 : 0.45)
            .padding(.horizontal, 4)
            .accessibilityLabel("Add track")

            Spacer(minLength: 0)
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MXColor.surface)
    }

    private func trackLimitBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Text(message)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Got it") {
                session.dismissTrackLimitMessage()
            }
            .font(MXFont.caption())
            .fontWeight(.semibold)
            .foregroundStyle(MXColor.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.black.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MXColor.layer2, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                session.dismissTrackLimitMessage()
            }
        }
    }

    private func clipWarningBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MXColor.accent)
            Text(message)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("OK") {
                session.dismissClipLoadWarnings()
            }
            .font(MXFont.caption())
            .fontWeight(.semibold)
            .foregroundStyle(MXColor.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.black.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MXColor.layer2, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                session.dismissClipLoadWarnings()
            }
        }
    }

    private func studioStartFailureView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.slash")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(MXColor.accent)

            Text("Studio couldn't start")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)

            Text(message)
                .font(MXFont.body2())
                .foregroundStyle(MXColor.grey)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            MXButton("Retry", systemImage: "arrow.clockwise", kind: .prime, size: .big, icon: .leading) {
                session.retryStart()
            }
            .padding(.horizontal, 32)

            Button("Close Studio", action: onClose)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.grey)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MXColor.surface.ignoresSafeArea())
    }

    private var beatNet: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let pixelsPerBeat = width / beatsVisible

            ZStack(alignment: .topLeading) {
                MXColor.surface

                // Ruler (fixed band — do not let Spacers stretch the beat column)
                HStack(spacing: 0) {
                    ForEach(0..<Int(beatsVisible), id: \.self) { beat in
                        let isBar = beat % session.project.timeSignatureNumerator == 0
                        Text(isBar ? "\(beat / session.project.timeSignatureNumerator + 1)" : "1")
                            .font(isBar ? MXFont.body3() : MXFont.caption())
                            .foregroundStyle(isBar ? MXColor.lightGrey : MXColor.grey)
                            .frame(width: pixelsPerBeat, height: rulerHeight, alignment: .bottomLeading)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(isBar ? MXColor.layer2 : MXColor.layer2.opacity(0.45))
                                    .frame(width: 1)
                            }
                    }
                }
                .frame(height: rulerHeight)

                // Vertical grid lines through lanes
                ForEach(0..<Int(beatsVisible), id: \.self) { beat in
                    Rectangle()
                        .fill(beat % session.project.timeSignatureNumerator == 0
                              ? MXColor.layer2
                              : MXColor.layer2.opacity(0.35))
                        .frame(width: 1, height: max(0, geo.size.height - rulerHeight))
                        .offset(x: CGFloat(beat) * pixelsPerBeat, y: rulerHeight)
                }

                // Track lanes + clips / placeholder waveform
                VStack(spacing: 4) {
                    Color.clear.frame(height: rulerHeight)
                    ForEach(Array(session.project.tracks.enumerated()), id: \.element.id) { index, track in
                        trackLane(track: track, width: width, pixelsPerBeat: pixelsPerBeat, isPrimary: index == 0)
                            .frame(height: trackLaneHeight)
                    }
                    Spacer(minLength: 0)
                }

                // Loop region highlight (GarageBand / BandLab style)
                if session.project.loopEnabled {
                    let loopX = CGFloat(session.project.loopStartBeat) * pixelsPerBeat
                    let loopW = CGFloat(max(0.25, session.project.loopEndBeat - session.project.loopStartBeat)) * pixelsPerBeat
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MXColor.accent.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(MXColor.accent.opacity(0.7)).frame(width: 2)
                        }
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(MXColor.accent.opacity(0.7)).frame(width: 2)
                        }
                        .frame(width: loopW, height: max(0, geo.size.height - rulerHeight))
                        .offset(x: loopX, y: rulerHeight)
                        .allowsHitTesting(false)
                }

                // Playhead (non-interactive so it never steals clip/lane hits)
                Rectangle()
                    .fill(MXColor.white)
                    .frame(width: 1.5, height: max(0, geo.size.height - 8))
                    .offset(x: playheadX(pixelsPerBeat: pixelsPerBeat), y: 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private func trackLane(track: MXSessionTrack, width: CGFloat, pixelsPerBeat: CGFloat, isPrimary: Bool) -> some View {
        let takeLaneCount = Set(track.clips.map(\.takeIndex)).count
        let showGhostLanes = takeLaneCount >= 2
        let activeClips = track.clips.filter(\.isActive)
        let ghostClips = showGhostLanes ? track.clips.filter { !$0.isActive } : []

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.surfaceRaised.opacity(0.35))
                .contentShape(Rectangle())
                .modifier(LaneBackgroundPointerModifier(
                    pixelsPerBeat: pixelsPerBeat,
                    hasSelection: session.selectedClipID != nil,
                    onSeek: { session.seek(toBeat: max(0, $0)) },
                    onClearSelection: { session.selectClip(nil) }
                ))

            // Ghost playlist lanes under actives (BandLab / Logic take comps lite).
            ForEach(ghostClips) { clip in
                GhostStudioClip(
                    clip: clip,
                    pixelsPerBeat: pixelsPerBeat,
                    onActivate: { session.setActiveTake(clipID: clip.id) }
                )
            }

            if activeClips.isEmpty {
                if isPrimary {
                    Text(track.kind == .midi ? "Play the keys below" : "Tap ● to record")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            } else {
                ForEach(activeClips) { clip in
                    InteractiveStudioClip(
                        clip: clip,
                        pixelsPerBeat: pixelsPerBeat,
                        isSelected: session.selectedClipID == clip.id,
                        onSelect: { session.selectClip(clip.id) },
                        onMove: { session.moveClip(id: clip.id, toStartBeat: $0) },
                        onTrimStart: { session.trimClipStart(id: clip.id, toStartBeat: $0) },
                        onTrimEnd: { session.trimClipEnd(id: clip.id, toEndBeat: $0) }
                    )
                }
            }
        }
    }

    private func playheadX(pixelsPerBeat: CGFloat) -> CGFloat {
        CGFloat(session.playheadBeat.truncatingRemainder(dividingBy: beatsVisible)) * pixelsPerBeat
    }

    // MARK: - Details strip (Figma Bottom Actions / Studio Details — 70pt)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailDivider
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
            .frame(width: 125)
            .frame(maxHeight: .infinity)
        }
        .frame(height: detailsStripHeight)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(MXColor.layer2)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    // MARK: - Action board (95:85072)

    private var actionBoard: some View {
        // Figma Action Board Studio: Undo / Redo / To-start · Record · Play / Metro / Mixer
        HStack {
            HStack(spacing: 2) {
                studioIconButton(asset: "studio_undo", systemFallback: "arrow.uturn.backward") {
                    session.undo()
                }
                .disabled(!session.canUndo)
                .opacity(session.canUndo ? 1 : 0.35)

                if session.selectedClipID != nil {
                    studioIconButton(asset: "studio_trash", systemFallback: "trash") {
                        session.deleteSelectedClip()
                    }
                }

                studioIconButton(asset: "studio_redo", systemFallback: "arrow.uturn.forward") {
                    session.redo()
                }
                .disabled(!session.canRedo)
                .opacity(session.canRedo ? 1 : 0.35)

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
                guard session.canRecordAudio else { return }
                session.enterRecordMode()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(width: 52, height: 52)
                    Circle()
                        .fill(session.canRecordAudio ? MXColor.red : MXColor.grey)
                        .frame(width: 28, height: 28)
                }
                .padding(4)
                .background(
                    Capsule(style: .continuous)
                        .fill(MXColor.black)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.phase != .ready || session.isInterrupted || !session.canRecordAudio)
            .opacity(session.canRecordAudio ? 1 : 0.4)

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

                studioIconButton(asset: "studio_mixer", systemFallback: "slider.horizontal.3") {
                    showMixerSheet = true
                }
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

    private var addTrackSheet: some View {
        VStack(spacing: 10) {
            Text("Add Track")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 4)

            addTrackOption(
                title: "Vocals/Audio",
                subtitle: "Mic take on a new track",
                systemImage: "mic.fill",
                tint: MXColor.accent
            ) {
                if let track = session.addAudioTrack() {
                    selectedTrackID = track.id
                }
                showAddTrackSheet = false
            }

            addTrackOption(
                title: "Guitar",
                subtitle: "Amp-ready track with pedalboard",
                systemImage: "guitars.fill",
                tint: MXColor.teal
            ) {
                if let track = session.addGuitarTrack() {
                    selectedTrackID = track.id
                }
                showAddTrackSheet = false
            }

            addTrackOption(
                title: "Virtual Instrument",
                subtitle: "Keys with built-in synth",
                systemImage: "pianokeys",
                tint: MXColor.orange
            ) {
                if let track = session.addMIDITrack() {
                    selectedTrackID = track.id
                }
                showAddTrackSheet = false
            }

            addTrackOption(
                title: "Import File",
                subtitle: "WAV, M4A, MP3…",
                systemImage: "square.and.arrow.down",
                tint: MXColor.red
            ) {
                showAddTrackSheet = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    showFileImporter = true
                }
            }

            addTrackOption(
                title: "Generate with AI",
                subtitle: "Describe a vibe, add a clip",
                systemImage: "sparkles",
                tint: MXColor.accent
            ) {
                showAddTrackSheet = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    showAIComposeSheet = true
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(MXColor.surface)
    }

    private func addTrackOption(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.layer2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!session.canAddTrack)
        .opacity(session.canAddTrack ? 1 : 0.45)
    }

    /// Clip gain + fades inspector (Ableton / Logic / BandLab pattern).
    private var clipInspectorSheet: some View {
        let selected = session.selectedClipID.flatMap { id in
            session.project.tracks.flatMap(\.clips).first(where: { $0.id == id })
        }
        return VStack(alignment: .leading, spacing: 18) {
            Text(selected?.name ?? "Clip")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            if let clip = selected {
                if let track = session.project.tracks.first(where: { $0.id == clip.trackID }),
                   Set(track.clips.map(\.takeIndex)).count > 1 {
                    // One row per takeIndex — punch comps may split a take into pieces.
                    let takeRows: [MXClip] = Dictionary(grouping: track.clips, by: \.takeIndex)
                        .values
                        .compactMap { pieces in
                            pieces.min(by: { $0.startBeat < $1.startBeat })
                        }
                        .sorted { $0.takeIndex < $1.takeIndex }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Takes")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        ForEach(takeRows) { take in
                            let laneActive = track.clips.contains { $0.takeIndex == take.takeIndex && $0.isActive }
                            Button {
                                session.setActiveTake(clipID: take.id)
                            } label: {
                                HStack {
                                    Text(take.name)
                                        .font(MXFont.body3())
                                        .foregroundStyle(MXColor.white)
                                    Spacer()
                                    if laneActive {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(MXColor.accent)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(laneActive ? MXColor.layer2 : MXColor.black.opacity(0.35))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gain")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        Spacer()
                        Text(String(format: "%.0f%%", clip.gain * 100))
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.lightGrey)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(clip.gain) },
                            set: { session.setClipGain(Float($0), clipID: clip.id) }
                        ),
                        in: 0.1...2.0,
                        step: 0.05
                    )
                    .tint(MXColor.accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fade in")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        Spacer()
                        Text(String(format: "%.2fs", clip.fadeInSeconds))
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.lightGrey)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { clip.fadeInSeconds },
                            set: { session.setClipFades(fadeInSeconds: $0, fadeOutSeconds: nil, clipID: clip.id) }
                        ),
                        in: 0...2,
                        step: 0.05
                    )
                    .tint(MXColor.accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fade out")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                        Spacer()
                        Text(String(format: "%.2fs", clip.fadeOutSeconds))
                            .font(MXFont.body3())
                            .foregroundStyle(MXColor.lightGrey)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { clip.fadeOutSeconds },
                            set: { session.setClipFades(fadeInSeconds: nil, fadeOutSeconds: $0, clipID: clip.id) }
                        ),
                        in: 0...2,
                        step: 0.05
                    )
                    .tint(MXColor.accent)
                }

                Button {
                    session.setLoopRegion(startBeat: clip.startBeat, endBeat: clip.startBeat + clip.lengthBeats)
                    session.setLoopEnabled(true)
                    showClipInspector = false
                } label: {
                    Label("Loop this clip", systemImage: "repeat")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Text("Select a clip on the timeline.")
                    .font(MXFont.body2())
                    .foregroundStyle(MXColor.grey)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(MXColor.surface.ignoresSafeArea())
    }

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

    /// Studio settings — arrangement toggles + latency calibration.
    private var studioSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Studio Settings")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            VStack(spacing: 0) {
                settingsToggleRow(
                    title: "Snap to grid",
                    subtitle: "Move & trim to 16th notes",
                    isOn: session.isSnapEnabled
                ) {
                    session.isSnapEnabled.toggle()
                }
                Divider().overlay(MXColor.layer2)
                settingsToggleRow(
                    title: "Loop region",
                    subtitle: session.project.loopEnabled
                        ? "Looping current region"
                        : "Long-press sets region to selection / bar",
                    isOn: session.project.loopEnabled
                ) {
                    if session.project.loopEnabled {
                        session.setLoopEnabled(false)
                    } else {
                        session.setLoopToSelectionOrBar()
                    }
                }
                if session.selectedClipID != nil {
                    Divider().overlay(MXColor.layer2)
                    Button {
                        showSettingsSheet = false
                        showClipInspector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clip fade & gain")
                                    .font(MXFont.mediumButton())
                                    .foregroundStyle(MXColor.white)
                                Text("Edit selected clip")
                                    .font(MXFont.caption())
                                    .foregroundStyle(MXColor.grey)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MXColor.grey)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.layer2)
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Input latency")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)
                Text("Play a click into the mic with headphones on")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Applied")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                Spacer(minLength: 8)
                if session.hasLatencyCompensation {
                    Text(String(format: "%.1f ms", session.latencyCompensationMilliseconds))
                        .font(MXFont.studioReadout())
                        .foregroundStyle(MXColor.lightGrey)
                        .monospacedDigit()
                } else {
                    Text("Not calibrated")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.grey)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MXColor.layer2)
            )

            if let summary = session.lastCalibrationSummary {
                Text(summary)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.lightGrey)
            }

            Button {
                session.calibrateLatency()
            } label: {
                HStack(spacing: 8) {
                    if session.isCalibrating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(MXColor.black)
                    }
                    Text(session.isCalibrating ? "Calibrating…" : "Calibrate")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(MXColor.accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.isCalibrating || session.phase != .ready || session.isRecording)
            .opacity(session.isCalibrating || session.phase != .ready || session.isRecording ? 0.5 : 1)

            if let error = session.calibrationError {
                Text(error)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pre-roll buffer")
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)
                Text("Keeps the last moments of mic input so Rec doesn’t clip attacks")
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
                HStack {
                    Text("\(Int(session.preRollMilliseconds)) ms")
                        .font(MXFont.studioReadout())
                        .foregroundStyle(MXColor.lightGrey)
                        .monospacedDigit()
                    Spacer()
                }
                Slider(
                    value: Binding(
                        get: { session.preRollMilliseconds },
                        set: { session.preRollMilliseconds = $0 }
                    ),
                    in: 0...500,
                    step: 50
                )
                .tint(MXColor.accent)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(MXColor.surface)
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? MXColor.accent : MXColor.grey)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var mixerSheet: some View {
        VStack(spacing: 0) {
            Text("Mixer")
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(session.project.tracks) { track in
                        mixerChannelStrip(track)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(MXColor.surface)
    }

    /// Selected / armed track first, then remaining tracks.
    private var fxSheetTracks: [MXSessionTrack] {
        let tracks = session.project.tracks
        let preferredID = selectedTrackID ?? session.project.armedTrack?.id
        guard let preferredID,
              let preferred = tracks.first(where: { $0.id == preferredID })
        else { return tracks }
        return [preferred] + tracks.filter { $0.id != preferredID }
    }

    private var fxSheetTitle: String {
        let track = fxSheetTracks.first
        if track?.category == .guitar || session.preset == .guitar {
            return "Pedalboard"
        }
        return "Track FX"
    }

    private var fxSheet: some View {
        VStack(spacing: 0) {
            Text(fxSheetTitle)
                .font(MXFont.sectionTitle())
                .foregroundStyle(MXColor.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(fxSheetTracks) { track in
                        fxTrackRow(track)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(MXColor.surface)
    }

    private func fxTrackRow(_ track: MXSessionTrack) -> some View {
        let isGuitar = track.category == .guitar || session.preset == .guitar
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(mixerCategoryTint(track.category))
                    .frame(width: 3, height: 16)
                Text(track.name)
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)
                    .lineLimit(1)
            }

            insertChainBar(for: track)

            if !isGuitar {
                mixerSliderRow(
                    label: "EQ Mid",
                    valueLabel: String(format: "%+.0f", track.eqMidGain),
                    value: Binding(
                        get: { Double(track.eqMidGain) },
                        set: { session.setTrackEQMidGain(Float($0), trackID: track.id) }
                    ),
                    range: -12...12,
                    labelWidth: 56
                )
            }

            mixerSliderRow(
                label: "Dly Mix",
                valueLabel: String(format: "%.0f", track.delayMix),
                value: Binding(
                    get: { Double(track.delayMix) },
                    set: {
                        session.setTrackDelay(mix: Float($0), time: track.delayTime, trackID: track.id)
                    }
                ),
                range: 0...100,
                labelWidth: 56
            )

            mixerSliderRow(
                label: "Dly Time",
                valueLabel: String(format: "%.2f", track.delayTime),
                value: Binding(
                    get: { Double(track.delayTime) },
                    set: {
                        session.setTrackDelay(mix: track.delayMix, time: Float($0), trackID: track.id)
                    }
                ),
                range: 0.05...0.8,
                labelWidth: 56
            )

            mixerSliderRow(
                label: "Dist",
                valueLabel: String(format: "%.0f", track.distortionMix),
                value: Binding(
                    get: { Double(track.distortionMix) },
                    set: { session.setTrackDistortionMix(Float($0), trackID: track.id) }
                ),
                range: 0...100,
                labelWidth: 56
            )

            mixerSliderRow(
                label: "Rev",
                valueLabel: String(format: "%.0f", track.reverbMix),
                value: Binding(
                    get: { Double(track.reverbMix) },
                    set: { session.setTrackReverbMix(Float($0), trackID: track.id) }
                ),
                range: 0...100,
                labelWidth: 56
            )

            if track.category == .vocal {
                Toggle(isOn: Binding(
                    get: { track.noiseGateEnabled },
                    set: { session.setNoiseGateEnabled($0, trackID: track.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noise Gate")
                            .font(MXFont.caption())
                            .fontWeight(.semibold)
                            .foregroundStyle(MXColor.white)
                        Text("Live + export — quiets room noise between phrases")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                    }
                }
                .tint(MXColor.accent)

                if track.noiseGateEnabled {
                    mixerSliderRow(
                        label: "Thresh",
                        valueLabel: String(format: "%.3f", track.noiseGateThreshold),
                        value: Binding(
                            get: { Double(track.noiseGateThreshold) },
                            set: { session.setNoiseGateThreshold(Float($0), trackID: track.id) }
                        ),
                        range: 0...0.2,
                        labelWidth: 56
                    )
                }

                Toggle(isOn: Binding(
                    get: { track.deEsserEnabled },
                    set: { session.setDeEsserEnabled($0, trackID: track.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("De-esser")
                            .font(MXFont.caption())
                            .fontWeight(.semibold)
                            .foregroundStyle(MXColor.white)
                        Text("Tames harsh S sounds around 6.5 kHz")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey)
                    }
                }
                .tint(MXColor.accent)

                if track.deEsserEnabled {
                    mixerSliderRow(
                        label: "Amount",
                        valueLabel: String(format: "%.0f", track.deEsserAmount),
                        value: Binding(
                            get: { Double(track.deEsserAmount) },
                            set: { session.setDeEsserAmount(Float($0), trackID: track.id) }
                        ),
                        range: 0...100,
                        labelWidth: 56
                    )
                }
            }

            if !isGuitar {
                Button {
                    session.toggleReelsVocal(trackID: track.id)
                } label: {
                    Text("Reels Vocal")
                        .font(MXFont.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(track.reelsVocalEnabled ? MXColor.black : MXColor.lightGrey)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(track.reelsVocalEnabled ? MXColor.accent : MXColor.layer2)
                        )
                        .overlay {
                            if !track.reelsVocalEnabled {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.layer2)
        )
    }

    /// BandLab / GarageBand-style channel strip for the mixer sheet.
    private func mixerChannelStrip(_ track: MXSessionTrack) -> some View {
        let tint = mixerCategoryTint(track.category)
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 3, height: 28)
                Text(track.name)
                    .font(MXFont.caption())
                    .fontWeight(.semibold)
                    .foregroundStyle(MXColor.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 32, alignment: .top)

            HStack(spacing: 6) {
                mixerMuteSoloButton("M", active: track.isMuted) {
                    session.toggleMute(trackID: track.id)
                }
                mixerMuteSoloButton("S", active: track.isSolo) {
                    session.toggleSolo(trackID: track.id)
                }
            }

            VStack(spacing: 4) {
                Text(String(format: "%.0f", track.volume * 100))
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.lightGrey)
                    .monospacedDigit()
                MixerVerticalFader(
                    value: Binding(
                        get: { Double(track.volume) },
                        set: { session.setTrackVolume(Float($0), trackID: track.id) }
                    ),
                    tint: tint
                )
                Text("Vol")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }

            VStack(spacing: 4) {
                PanKnob(
                    value: Binding(
                        get: { track.pan },
                        set: { session.setTrackPan($0, trackID: track.id) }
                    ),
                    size: 28
                )
                Text(panLabel(track.pan))
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .monospacedDigit()
            }

            // Insert reverb for audio; MIDI keeps a separate aux Send below.
            VStack(spacing: 2) {
                Text("Rev")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                Slider(
                    value: Binding(
                        get: { Double(track.reverbMix) },
                        set: { session.setTrackReverbMix(Float($0), trackID: track.id) }
                    ),
                    in: 0...100
                )
                .tint(MXColor.accent)
                .controlSize(.mini)
                Text(String(format: "%.0f", track.reverbMix))
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.lightGrey)
                    .monospacedDigit()
            }

            if track.kind == .midi {
                VStack(spacing: 2) {
                    Text("Send")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                    Slider(
                        value: Binding(
                            get: { Double(track.reverbSend) },
                            set: { session.setTrackReverbSend(Float($0), trackID: track.id) }
                        ),
                        in: 0...100
                    )
                    .tint(MXColor.teal)
                    .controlSize(.mini)
                    Text(String(format: "%.0f", track.reverbSend))
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.lightGrey)
                        .monospacedDigit()
                }
            }

            if track.category == .vocal {
                Button {
                    session.toggleReelsVocal(trackID: track.id)
                } label: {
                    Text("Reels")
                        .font(MXFont.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(track.reelsVocalEnabled ? MXColor.black : MXColor.lightGrey)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(track.reelsVocalEnabled ? MXColor.accent : MXColor.black)
                        )
                        .overlay {
                            if !track.reelsVocalEnabled {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 96)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.layer2)
        )
    }

    /// Fixed live-order insert chips (visual; no drag-reorder).
    private func insertChainBar(for track: MXSessionTrack) -> some View {
        let stages: [(label: String, active: Bool)] = [
            ("HPF", session.isHighPassEnabled || track.reelsVocalEnabled),
            ("EQ", abs(track.eqMidGain) >= 0.05 || (track.deEsserEnabled && track.deEsserAmount > 0.5)),
            ("Dly", track.delayMix > 0.5),
            ("Dist", track.distortionMix > 0.5),
            ("Dyn", track.reelsVocalEnabled || track.noiseGateEnabled),
            ("Rev", track.reverbMix > 0.5),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(MXColor.grey.opacity(0.7))
                    }
                    Text(stage.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(stage.active ? MXColor.black : MXColor.grey)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(stage.active ? MXColor.accent : MXColor.black)
                        )
                        .overlay {
                            if !stage.active {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                            }
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insert chain")
    }

    private func mixerCategoryTint(_ category: MXSessionTrack.Category) -> Color {
        switch category {
        case .vocal: return MXColor.accent
        case .guitar: return MXColor.teal
        case .keys: return MXColor.orange
        case .imported: return MXColor.red
        }
    }

    private func mixerSliderRow(
        label: String,
        valueLabel: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        labelWidth: CGFloat = 28
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)
            Slider(value: value, in: range)
                .tint(MXColor.accent)
            Text(valueLabel)
                .font(MXFont.caption())
                .foregroundStyle(MXColor.lightGrey)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func mixerMuteSoloButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MXFont.caption())
                .fontWeight(.medium)
                .foregroundStyle(active ? MXColor.black : MXColor.lightGrey)
                .frame(width: 24, height: 24)
                .background(active ? MXColor.accent : MXColor.black)
        }
        .buttonStyle(.plain)
    }

    private func panLabel(_ pan: Float) -> String {
        if abs(pan) < 0.02 { return "C" }
        return pan < 0
            ? String(format: "L%.0f", abs(pan) * 100)
            : String(format: "R%.0f", pan * 100)
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

// MARK: - Mixer vertical fader

/// Tall volume fader for mixer channel strips (drag up/down).
private struct MixerVerticalFader: View {
    @Binding var value: Double
    var tint: Color
    var height: CGFloat = 140

    var body: some View {
        GeometryReader { geo in
            let trackWidth: CGFloat = 4
            let thumbSize: CGFloat = 16
            let travel = max(geo.size.height - thumbSize, 1)
            let y = travel * (1 - value)

            ZStack(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(MXColor.black)
                    .frame(width: trackWidth, height: geo.size.height)
                    .frame(maxWidth: .infinity)

                Capsule(style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(width: trackWidth, height: max(geo.size.height - y - thumbSize / 2, trackWidth))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tint.opacity(0.35))
                    )
                    .frame(width: 22, height: thumbSize)
                    .offset(y: y)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let loc = gesture.location.y - thumbSize / 2
                        let next = 1 - Double(loc / travel)
                        value = min(max(next, 0), 1)
                    }
            )
        }
        .frame(width: 28, height: height)
        .accessibilityLabel("Volume")
        .accessibilityValue(Text(String(format: "%.0f percent", value * 100)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.05, 1)
            case .decrement: value = max(value - 0.05, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - Track header (95:85033)

private struct StudioTrackHeader: View {
    let track: MXSessionTrack
    var isSelected: Bool
    var isArmed: Bool
    var onSelect: () -> Void
    var onMute: () -> Void
    var onSolo: () -> Void
    var onSetActiveTake: (UUID) -> Void

    private var categoryTint: Color {
        switch track.category {
        case .vocal: return MXColor.accent
        case .guitar: return MXColor.teal
        case .keys: return MXColor.orange
        case .imported: return MXColor.red
        }
    }

    private var categoryIcon: String {
        switch track.category {
        case .vocal: return "mic.fill"
        case .guitar: return "guitars.fill"
        case .keys: return "pianokeys"
        case .imported: return "waveform"
        }
    }

    private var takeCount: Int { track.clips.count }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(categoryTint)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isArmed ? MXColor.red : categoryTint)
                        Text(track.name.uppercased())
                            .font(MXFont.studioTrackName())
                            .foregroundStyle(MXColor.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        if isArmed {
                            Text("R")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(MXColor.white)
                                .frame(width: 12, height: 12)
                                .background(Circle().fill(MXColor.red))
                        }
                        if takeCount > 1 {
                            Menu {
                                ForEach(track.clips.sorted(by: { $0.takeIndex < $1.takeIndex })) { take in
                                    Button {
                                        onSetActiveTake(take.id)
                                    } label: {
                                        if take.isActive {
                                            Label(take.name, systemImage: "checkmark")
                                        } else {
                                            Text(take.name)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MXColor.grey)
                            }
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(MXColor.black).frame(height: 5)
                            Capsule()
                                .fill(categoryTint)
                                .frame(width: geo.size.width * CGFloat(track.volume), height: 5)
                        }
                    }
                    .frame(height: 5)
                }

                VStack(spacing: 3) {
                    muteSoloButton("M", active: track.isMuted, action: onMute)
                    muteSoloButton("S", active: track.isSolo, action: onSolo)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.layer2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? categoryTint : Color.clear, lineWidth: 0.5)
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

// MARK: - Lane pointer (seek vs deselect)

/// Seek on empty lane space when idle; tap deselects when a clip is selected.
/// Clips sit above this layer so trim/move/select are not contested.
private struct LaneBackgroundPointerModifier: ViewModifier {
    let pixelsPerBeat: CGFloat
    let hasSelection: Bool
    var onSeek: (Double) -> Void
    var onClearSelection: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if hasSelection {
            content.onTapGesture(perform: onClearSelection)
        } else {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(Double(value.location.x / pixelsPerBeat))
                    }
            )
        }
    }
}

// MARK: - Ghost playlist clip (inactive take)

private struct GhostStudioClip: View {
    let clip: MXClip
    let pixelsPerBeat: CGFloat
    var onActivate: () -> Void

    private var width: CGFloat {
        max(16, CGFloat(clip.lengthBeats) * pixelsPerBeat)
    }

    private var x: CGFloat {
        CGFloat(clip.startBeat) * pixelsPerBeat
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.layer2.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(MXColor.grey.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                )
            Text("T\(clip.takeIndex + 1)")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
                .padding(.leading, 4)
                .padding(.top, 2)
        }
        .frame(width: width, height: 36)
        .offset(x: x, y: 8)
        .opacity(0.45)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .accessibilityLabel("Inactive \(clip.name)")
        .accessibilityHint("Activates this take lane")
    }
}

// MARK: - Interactive clip (select / move / trim)

private struct InteractiveStudioClip: View {
    let clip: MXClip
    let pixelsPerBeat: CGFloat
    let isSelected: Bool
    var onSelect: () -> Void
    var onMove: (_ toStartBeat: Double) -> Void
    var onTrimStart: (_ toStartBeat: Double) -> Void
    var onTrimEnd: (_ toEndBeat: Double) -> Void

    private let handleWidth: CGFloat = 14
    private let clipHeight: CGFloat = 52

    @State private var activeDrag: DragKind?
    @State private var dragDeltaX: CGFloat = 0

    private enum DragKind {
        case move, trimStart, trimEnd
    }

    private var baseWidth: CGFloat {
        max(24, CGFloat(clip.lengthBeats) * pixelsPerBeat)
    }

    private var baseX: CGFloat {
        CGFloat(clip.startBeat) * pixelsPerBeat
    }

    private var displayX: CGFloat {
        switch activeDrag {
        case .move, .trimStart: return baseX + dragDeltaX
        case .trimEnd, .none: return baseX
        }
    }

    private var displayWidth: CGFloat {
        switch activeDrag {
        case .trimStart: return max(24, baseWidth - dragDeltaX)
        case .trimEnd: return max(24, baseWidth + dragDeltaX)
        case .move, .none: return baseWidth
        }
    }

    var body: some View {
        clipChrome
            .accessibilityLabel(clip.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var clipChrome: some View {
        let base = ZStack(alignment: .leading) {
            StudioWaveformClip()
                .frame(width: displayWidth, height: clipHeight)
                .opacity(isSelected ? 1 : 0.92)

            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(MXColor.accent, lineWidth: 1.5)
                    .frame(width: displayWidth, height: clipHeight)
                    .allowsHitTesting(false)

                // Left trim handle
                trimHandle
                    .highPriorityGesture(trimStartGesture)

                // Right trim handle — spacer ignores hits so body drag still works
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                    trimHandle
                        .highPriorityGesture(trimEndGesture)
                }
                .frame(width: displayWidth, height: clipHeight)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.white.opacity(0.06))
                    .frame(width: displayWidth, height: clipHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: displayWidth, height: clipHeight, alignment: .leading)
        .contentShape(Rectangle())
        .offset(x: displayX)
        .onTapGesture(perform: onSelect)

        if isSelected {
            base.gesture(moveGesture)
        } else {
            base
        }
    }

    private var trimHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(MXColor.white.opacity(0.92))
            Capsule()
                .fill(MXColor.black.opacity(0.35))
                .frame(width: 2, height: 18)
        }
        .frame(width: handleWidth, height: clipHeight)
        .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if activeDrag == nil || activeDrag == .move {
                    activeDrag = .move
                    dragDeltaX = value.translation.width
                }
            }
            .onEnded { value in
                let wasMove = activeDrag == .move
                activeDrag = nil
                dragDeltaX = 0
                guard wasMove else { return }
                let newStart = clip.startBeat + Double(value.translation.width / pixelsPerBeat)
                onMove(max(0, newStart))
            }
    }

    private var trimStartGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                activeDrag = .trimStart
                let maxDelta = baseWidth - 24
                dragDeltaX = min(maxDelta, max(-baseX, value.translation.width))
            }
            .onEnded { value in
                let maxDelta = baseWidth - 24
                let dx = min(maxDelta, max(-baseX, value.translation.width))
                let newStart = clip.startBeat + Double(dx / pixelsPerBeat)
                activeDrag = nil
                dragDeltaX = 0
                onTrimStart(newStart)
            }
    }

    private var trimEndGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                activeDrag = .trimEnd
                dragDeltaX = max(24 - baseWidth, value.translation.width)
            }
            .onEnded { value in
                let dx = max(24 - baseWidth, value.translation.width)
                let newEnd = clip.startBeat + clip.lengthBeats + Double(dx / pixelsPerBeat)
                activeDrag = nil
                dragDeltaX = 0
                onTrimEnd(newEnd)
            }
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
