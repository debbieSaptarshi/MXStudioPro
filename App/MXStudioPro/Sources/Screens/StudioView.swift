import SwiftUI
import UIKit
import UniformTypeIdentifiers
import MXStudioEngine

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
    @State private var showPianoRoll = false
    @State private var pianoRollDragUndoArmed = true
    /// Figma Studio – Hide Tracks (`95:85310`): collapse headers to an icon rail.
    @State private var tracksCollapsed = false
    /// Session-local collapse state: tracks in this set are collapsed to one summary lane.
    @State private var collapsedPlaylistTrackIDs: Set<UUID> = []
    /// Session-local collapse for Week 40 drum part columns (Kick/Snare/Hats…).
    @State private var collapsedDrumPartTrackIDs: Set<UUID> = []
    /// Tracks showing volume automation lane (Week 52).
    @State private var automationLaneTrackIDs: Set<UUID> = []
    /// Per-track automation lane target (Week 54 clip-relative).
    @State private var automationLaneModes: [UUID: AutomationLaneMode] = [:]
    /// Pads vs BandLab-style 16-step sequencer (Week 49).
    @State private var drumInputMode: DrumInputMode = .pads
    @State private var drumStepVelocityGrid: [[UInt8]] = MXDrumStepSequencer.emptyVelocityGrid(bars: 1)
    @State private var drumStepBars: Int = 1
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum AutomationLaneMode: String, CaseIterable, Identifiable {
        case trackVolume
        case clipVolume
        case clipPan
        var id: String { rawValue }
        var label: String {
            switch self {
            case .trackVolume: return "Track"
            case .clipVolume: return "Clip Vol"
            case .clipPan: return "Clip Pan"
            }
        }
    }

    private enum DrumInputMode: String, CaseIterable, Identifiable {
        case pads
        case steps
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pads: return "Pads"
            case .steps: return "Steps"
            }
        }
    }

    /// Compact landscape arrange (Figma Studio landscape `97:113250` / 812×375).
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var trackColumnWidth: CGFloat {
        if tracksCollapsed || isLandscape { return 44 }
        return 135
    }
    private let beatsVisible: Double = 8
    /// Figma Studio – Guitar (`95:85203`): track lanes / headers are 60pt.
    private var trackLaneHeight: CGFloat { isLandscape ? 48 : 60 }
    /// Height of one take lane inside an expanded playlist folder.
    private var takeRowHeight: CGFloat { isLandscape ? 40 : 44 }
    /// Height of one Kick/Snare/Hats… column inside an expanded drum folder.
    private var drumPartRowHeight: CGFloat { isLandscape ? 36 : 40 }
    /// Volume automation lane under a track (Logic / Ableton lite).
    private var automationLaneHeight: CGFloat { isLandscape ? 28 : 36 }
    /// Figma Bottom Actions “Studio Details” row is 70pt; compact in landscape.
    private var detailsStripHeight: CGFloat { isLandscape ? 52 : 70 }
    private let rulerHeight: CGFloat = 24

    private func playlistTakeIndices(for track: MXSessionTrack) -> [Int] {
        Array(Set(track.clips.map(\.takeIndex))).sorted()
    }

    private func isPlaylistFolder(_ track: MXSessionTrack) -> Bool {
        playlistTakeIndices(for: track).count >= 2
    }

    private func isPlaylistExpanded(_ track: MXSessionTrack) -> Bool {
        isPlaylistFolder(track) && !collapsedPlaylistTrackIDs.contains(track.id)
    }

    /// Drum tracks always expose BandLab-style part columns (orthogonal to takes).
    private func isDrumPartFolder(_ track: MXSessionTrack) -> Bool {
        track.category == .drums
    }

    /// Part columns for single-take drum tracks (playlist folder wins when ≥2 takes).
    private func isDrumPartsExpanded(_ track: MXSessionTrack) -> Bool {
        isDrumPartFolder(track)
            && !isPlaylistFolder(track)
            && !collapsedDrumPartTrackIDs.contains(track.id)
    }

    private func trackArrangementHeight(for track: MXSessionTrack) -> CGFloat {
        var height: CGFloat
        if isPlaylistExpanded(track) {
            height = CGFloat(playlistTakeIndices(for: track).count) * takeRowHeight
        } else if isDrumPartsExpanded(track) {
            height = CGFloat(MXDrumPart.allCases.count) * drumPartRowHeight
        } else {
            height = trackLaneHeight
        }
        if automationLaneTrackIDs.contains(track.id) {
            height += automationLaneHeight + 18
        }
        return height
    }

    private func isAutomationLaneVisible(_ track: MXSessionTrack) -> Bool {
        automationLaneTrackIDs.contains(track.id)
    }

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
            if isLandscape { tracksCollapsed = true }
            MXOrientationLock.applyForRecordMode(session.isRecordMode)
        }
        .onChange(of: session.isRecordMode) { _, isRecordMode in
            MXOrientationLock.applyForRecordMode(isRecordMode)
        }
        .onDisappear {
            MXOrientationLock.unlock()
        }
        .onChange(of: verticalSizeClass) { _, _ in
            // Landscape defaults to Hide Tracks for denser Figma 812×375 arrange.
            if isLandscape {
                tracksCollapsed = true
            }
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
            if id == nil {
                showClipInspector = false
                showPianoRoll = false
            } else if selectedMIDIClipForRoll == nil {
                showPianoRoll = false
            }
        }
    }

    /// Selected MIDI clip suitable for the Week 55 piano-roll editor.
    private var selectedMIDIClipForRoll: MXClip? {
        guard let id = session.selectedClipID,
              let clip = session.project.tracks.flatMap(\.clips).first(where: { $0.id == id }),
              let track = session.project.tracks.first(where: { $0.id == clip.trackID }),
              track.kind == .midi
        else { return nil }
        return clip
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
                // Landscape + piano/pads: hide details strip so Figma 812×375 keeps net + keys usable.
                if !(isLandscape && (session.showsPianoKeyboard || session.showsDrumPads)) {
                    studioDetailsStrip
                        .frame(height: detailsStripHeight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if session.showsPianoKeyboard {
                    PianoKeyboardView(
                        onNoteOn: { session.noteOn($0, velocity: $1) },
                        onNoteOff: { session.noteOff($0) }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } else if session.showsDrumPads {
                    VStack(spacing: 0) {
                        drumInputModePicker
                        if drumInputMode == .pads {
                            DrumPadView(
                                onPadHit: { session.noteOn($0, velocity: $1) },
                                onPadRelease: { session.noteOff($0) }
                            )
                        } else {
                            DrumStepSequencerView(
                                velocityGrid: $drumStepVelocityGrid,
                                bars: $drumStepBars,
                                activeStep: session.isPlaying
                                    ? MXDrumStepSequencer.stepIndex(
                                        atBeat: session.playheadBeat,
                                        bars: drumStepBars
                                    )
                                    : nil,
                                canApply: session.phase == .ready,
                                canLoadFromClip: session.canLoadDrumStepPatternFromSelectedClip,
                                onPreviewHit: { note, vel in
                                    session.previewNote(note, velocity: vel)
                                },
                                onApply: {
                                    _ = session.commitDrumStepPattern(
                                        drumStepVelocityGrid,
                                        bars: drumStepBars
                                    )
                                },
                                onClear: {
                                    drumStepVelocityGrid = MXDrumStepSequencer.emptyVelocityGrid(
                                        bars: drumStepBars
                                    )
                                },
                                onLoadFromClip: {
                                    if let loaded = session.loadDrumStepPatternFromSelectedClip() {
                                        drumStepBars = loaded.bars
                                        drumStepVelocityGrid = loaded.grid
                                    }
                                }
                            )
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if showPianoRoll, let clip = selectedMIDIClipForRoll {
                    MIDIPianoRollEditorView(
                        notes: clip.midiNotes,
                        lengthBeats: clip.lengthBeats,
                        onMove: { id, start, pitch in
                            _ = session.updateMIDINote(
                                id: id,
                                startBeat: start,
                                pitch: pitch,
                                renderBed: false,
                                recordUndo: pianoRollDragUndoArmed
                            )
                            pianoRollDragUndoArmed = false
                        },
                        onResize: { id, length in
                            _ = session.updateMIDINote(
                                id: id,
                                lengthBeats: length,
                                renderBed: false,
                                recordUndo: pianoRollDragUndoArmed
                            )
                            pianoRollDragUndoArmed = false
                        },
                        onVelocity: { id, velocity in
                            _ = session.updateMIDINote(
                                id: id,
                                velocity: velocity,
                                renderBed: false,
                                recordUndo: pianoRollDragUndoArmed
                            )
                            pianoRollDragUndoArmed = false
                        },
                        onMoveEnded: {
                            _ = session.commitSelectedMIDIClipBed()
                            pianoRollDragUndoArmed = true
                        },
                        onAdd: { start, pitch in
                            _ = session.addMIDINote(startBeat: start, pitch: pitch)
                        },
                        onDelete: { id in
                            _ = session.deleteMIDINote(id: id)
                        }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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

            if let tempoMessage = session.tempoDetectMessage {
                tempoDetectBanner(tempoMessage)
                    .padding(.top, session.trackLimitMessage == nil ? 56 : 96)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let clipWarning = session.clipLoadWarnings.last {
                clipWarningBanner(clipWarning)
                    .padding(.top, {
                        var top: CGFloat = 56
                        if session.trackLimitMessage != nil { top += 40 }
                        if session.tempoDetectMessage != nil { top += 40 }
                        return top
                    }())
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
        .animation(.easeInOut(duration: 0.2), value: session.tempoDetectMessage)
        .animation(.easeInOut(duration: 0.2), value: session.clipLoadWarnings.count)
        .animation(.easeInOut(duration: 0.2), value: session.isExporting)
    }

    /// Pads / Steps segmented control above the drum surface (BandLab-style).
    private var drumInputModePicker: some View {
        HStack(spacing: 0) {
            ForEach(DrumInputMode.allCases) { mode in
                let selected = drumInputMode == mode
                Button {
                    drumInputMode = mode
                } label: {
                    Text(mode.label)
                        .font(MXFont.caption())
                        .foregroundStyle(selected ? MXColor.black : MXColor.lightGrey)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isLandscape ? 4 : 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? MXColor.orange : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.label) drum input")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MXColor.layer2)
        )
        .padding(.horizontal, isLandscape ? 8 : 12)
        .padding(.top, isLandscape ? 4 : 6)
        .padding(.bottom, 2)
        .background(MXColor.surfaceRaised)
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
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tracksCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: tracksCollapsed ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tracksCollapsed ? MXColor.accent : MXColor.white)
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
                .accessibilityLabel(tracksCollapsed ? "Show track names" : "Hide tracks")
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MXColor.black)
            )

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button { showCollabSheet = true } label: {
                    Group {
                        if isLandscape {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MXColor.white)
                                .frame(width: 20, height: 20)
                                .padding(10)
                        } else {
                            Text("+ Collab")
                                .font(MXFont.mediumButton())
                                .foregroundStyle(MXColor.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                    }
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
                .accessibilityLabel("Collaborate")

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
        .padding(.horizontal, isLandscape ? 10 : 16)
        .padding(.vertical, isLandscape ? 6 : 12)
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
            if tracksCollapsed {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
                    .frame(maxWidth: .infinity)
                    .frame(height: rulerHeight)
            } else {
                Text(session.playheadTimeLabel)
                    .font(MXFont.body3())
                    .foregroundStyle(MXColor.grey)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .frame(height: rulerHeight)
            }

            ForEach(session.project.tracks) { track in
                if tracksCollapsed {
                    collapsedTrackRailButton(track)
                        .frame(height: trackArrangementHeight(for: track))
                } else {
                    StudioTrackHeader(
                        track: track,
                        isSelected: selectedTrackID == track.id,
                        isArmed: track.isArmed,
                        takeLaneCount: playlistTakeIndices(for: track).count,
                        takeRepresentatives: session.takes(onTrackID: track.id),
                        isPlaylistExpanded: isPlaylistExpanded(track),
                        drumPartLabels: isDrumPartsExpanded(track)
                            ? MXDrumPart.allCases.sorted().map(\.shortLabel)
                            : [],
                        mutedDrumParts: isDrumPartsExpanded(track)
                            ? Set(MXDrumPart.allCases.sorted().filter { track.isDrumPartMuted($0) })
                            : [],
                        soloedDrumParts: isDrumPartsExpanded(track)
                            ? Set(MXDrumPart.allCases.sorted().filter { track.isDrumPartSoloed($0) })
                            : [],
                        isDrumPartsExpanded: isDrumPartsExpanded(track),
                        showsDrumPartChevron: isDrumPartFolder(track) && !isPlaylistFolder(track),
                        onSelect: {
                            selectedTrackID = track.id
                            session.armTrack(id: track.id)
                        },
                        onMute: { session.toggleMute(trackID: track.id) },
                        onSolo: { session.toggleSolo(trackID: track.id) },
                        onSetActiveTake: { session.setActiveTake(clipID: $0) },
                        onTogglePlaylist: {
                            withAnimation {
                                if collapsedPlaylistTrackIDs.contains(track.id) {
                                    collapsedPlaylistTrackIDs.remove(track.id)
                                } else {
                                    collapsedPlaylistTrackIDs.insert(track.id)
                                }
                            }
                        },
                        onToggleDrumParts: {
                            withAnimation {
                                if collapsedDrumPartTrackIDs.contains(track.id) {
                                    collapsedDrumPartTrackIDs.remove(track.id)
                                } else {
                                    collapsedDrumPartTrackIDs.insert(track.id)
                                }
                            }
                        },
                        onToggleDrumPartMute: { part in
                            session.toggleDrumPartMute(trackID: track.id, part: part)
                        },
                        onToggleDrumPartSolo: { part in
                            session.toggleDrumPartSolo(trackID: track.id, part: part)
                        },
                        showsAutomation: isAutomationLaneVisible(track),
                        onToggleAutomation: {
                            withAnimation {
                                if automationLaneTrackIDs.contains(track.id) {
                                    automationLaneTrackIDs.remove(track.id)
                                } else {
                                    automationLaneTrackIDs.insert(track.id)
                                    session.ensureDefaultVolumeAutomation(trackID: track.id)
                                }
                            }
                        },
                        playbackLevel: session.trackPlaybackLevels[track.id] ?? 0,
                        playbackPeakHold: session.trackPlaybackPeakHolds[track.id] ?? 0
                    )
                    .frame(height: trackArrangementHeight(for: track))
                    .clipped()
                }
            }

            Button {
                showAddTrackSheet = true
            } label: {
                Group {
                    if tracksCollapsed {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("ADD TRACK")
                                .font(MXFont.caption())
                                .fontWeight(.semibold)
                        }
                    }
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
        .animation(.easeInOut(duration: 0.2), value: tracksCollapsed)
    }

    /// Figma Hide Tracks — icon rail for denser arrange.
    private func collapsedTrackRailButton(_ track: MXSessionTrack) -> some View {
        let tint = mixerCategoryTint(track.category)
        let icon: String = {
            switch track.category {
            case .vocal: return "mic.fill"
            case .guitar: return "guitars.fill"
            case .keys: return "pianokeys"
            case .drums: return "circle.grid.2x2.fill"
            case .imported: return "waveform"
            }
        }()
        return Button {
            selectedTrackID = track.id
            session.armTrack(id: track.id)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(track.isArmed ? MXColor.red : tint)
                if track.isMuted {
                    Text("M")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MXColor.grey)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.layer2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selectedTrackID == track.id ? tint : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityLabel(track.name)
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

    private func tempoDetectBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "metronome.fill")
                .foregroundStyle(MXColor.accent)
            Text(message)
                .font(MXFont.body3())
                .foregroundStyle(MXColor.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("OK") {
                session.dismissTempoDetectMessage()
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
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                session.dismissTempoDetectMessage()
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
                            .frame(height: trackArrangementHeight(for: track))
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

    @ViewBuilder
    private func trackLane(track: MXSessionTrack, width: CGFloat, pixelsPerBeat: CGFloat, isPrimary: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                if isPlaylistExpanded(track) {
                    // One timeline row per takeIndex (GarageBand / Logic playlist lite).
                    VStack(spacing: 0) {
                        ForEach(playlistTakeIndices(for: track), id: \.self) { takeIndex in
                            playlistTakeRow(
                                track: track,
                                takeIndex: takeIndex,
                                pixelsPerBeat: pixelsPerBeat
                            )
                            .frame(height: takeRowHeight)
                        }
                    }
                } else if isDrumPartsExpanded(track) {
                    // One timeline row per drum part (BandLab / GarageBand kit columns).
                    VStack(spacing: 0) {
                        ForEach(MXDrumPart.allCases.sorted()) { part in
                            drumPartRow(
                                track: track,
                                part: part,
                                pixelsPerBeat: pixelsPerBeat
                            )
                            .frame(height: drumPartRowHeight)
                        }
                    }
                } else {
                    // Single-take or collapsed folder: summary lane with active clips only.
                    let activeClips = track.clips.filter(\.isActive)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(MXColor.surfaceRaised.opacity(0.35))
                            .contentShape(Rectangle())
                            .modifier(LaneBackgroundPointerModifier(
                                pixelsPerBeat: pixelsPerBeat,
                                hasSelection: session.selectedClipID != nil,
                                onSeek: { session.seek(toBeat: max(0, $0)) },
                                onClearSelection: { session.selectClip(nil) }
                            ))

                        if activeClips.isEmpty {
                            if isPrimary {
                                Text(emptyLaneHint(for: track))
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
                                    bpm: session.bpm,
                                    isSelected: session.selectedClipID == clip.id,
                                    onSelect: { session.selectClip(clip.id) },
                                    onMove: { session.moveClip(id: clip.id, toStartBeat: $0) },
                                    onTrimStart: { session.trimClipStart(id: clip.id, toStartBeat: $0) },
                                    onTrimEnd: { session.trimClipEnd(id: clip.id, toEndBeat: $0) },
                                    onFadeChange: { session.setClipFades(fadeInSeconds: $0, fadeOutSeconds: $1, clipID: clip.id) }
                                )
                            }
                        }
                    }
                    .frame(height: trackLaneHeight)
                }
            }

            if isAutomationLaneVisible(track) {
                let mode = automationLaneModes[track.id] ?? .trackVolume
                let selectedClip = session.selectedClipID.flatMap { id in
                    track.clips.first(where: { $0.id == id })
                }
                VStack(spacing: 2) {
                    automationModePicker(trackID: track.id, mode: mode, hasSelectedClip: selectedClip != nil)
                    automationLaneContent(
                        track: track,
                        mode: mode,
                        selectedClip: selectedClip,
                        pixelsPerBeat: pixelsPerBeat
                    )
                }
                .frame(height: automationLaneHeight + 18)
            }
        }
    }

    @ViewBuilder
    private func automationModePicker(
        trackID: UUID,
        mode: AutomationLaneMode,
        hasSelectedClip: Bool
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(AutomationLaneMode.allCases) { option in
                let enabled = option == .trackVolume || hasSelectedClip
                Button {
                    guard enabled else { return }
                    automationLaneModes[trackID] = option
                    switch option {
                    case .trackVolume:
                        session.ensureDefaultVolumeAutomation(trackID: trackID)
                    case .clipVolume:
                        if let id = session.selectedClipID {
                            session.ensureDefaultClipVolumeAutomation(clipID: id)
                        }
                    case .clipPan:
                        if let id = session.selectedClipID {
                            session.ensureDefaultClipPanAutomation(clipID: id)
                        }
                    }
                } label: {
                    Text(option.label)
                        .font(MXFont.caption())
                        .foregroundStyle(
                            mode == option
                                ? MXColor.orange
                                : (enabled ? MXColor.lightGrey : MXColor.grey.opacity(0.5))
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(mode == option ? MXColor.orange.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func automationLaneContent(
        track: MXSessionTrack,
        mode: AutomationLaneMode,
        selectedClip: MXClip?,
        pixelsPerBeat: CGFloat
    ) -> some View {
        switch mode {
        case .trackVolume:
            VolumeAutomationLaneView(
                points: track.volumeAutomation,
                pixelsPerBeat: pixelsPerBeat,
                beatsVisible: beatsVisible,
                height: automationLaneHeight,
                valueMin: MXVolumeAutomation.minValue,
                valueMax: MXVolumeAutomation.maxValue,
                beatOffset: 0,
                beatMax: nil,
                onAdd: { beat, value in
                    session.upsertVolumeAutomation(trackID: track.id, beat: beat, value: value)
                },
                onMove: { id, beat, value in
                    session.moveVolumeAutomationPoint(trackID: track.id, pointID: id, beat: beat, value: value)
                },
                onDelete: { id in
                    session.removeVolumeAutomationPoint(trackID: track.id, pointID: id)
                }
            )
        case .clipVolume:
            if let clip = selectedClip {
                VolumeAutomationLaneView(
                    points: clip.volumeAutomation,
                    pixelsPerBeat: pixelsPerBeat,
                    beatsVisible: beatsVisible,
                    height: automationLaneHeight,
                    valueMin: MXVolumeAutomation.minValue,
                    valueMax: MXVolumeAutomation.maxValue,
                    beatOffset: clip.startBeat,
                    beatMax: clip.lengthBeats,
                    onAdd: { beat, value in
                        session.upsertClipVolumeAutomation(clipID: clip.id, beat: beat, value: value)
                    },
                    onMove: { id, beat, value in
                        session.moveClipVolumeAutomationPoint(
                            clipID: clip.id,
                            pointID: id,
                            beat: beat,
                            value: value
                        )
                    },
                    onDelete: { id in
                        session.removeClipVolumeAutomationPoint(clipID: clip.id, pointID: id)
                    }
                )
            } else {
                Text("Select a clip for clip volume automation")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
        case .clipPan:
            if let clip = selectedClip {
                VolumeAutomationLaneView(
                    points: clip.panAutomation,
                    pixelsPerBeat: pixelsPerBeat,
                    beatsVisible: beatsVisible,
                    height: automationLaneHeight,
                    valueMin: MXPanAutomation.minValue,
                    valueMax: MXPanAutomation.maxValue,
                    beatOffset: clip.startBeat,
                    beatMax: clip.lengthBeats,
                    centerValue: 0,
                    onAdd: { beat, value in
                        session.upsertClipPanAutomation(clipID: clip.id, beat: beat, value: value)
                    },
                    onMove: { id, beat, value in
                        session.moveClipPanAutomationPoint(
                            clipID: clip.id,
                            pointID: id,
                            beat: beat,
                            value: value
                        )
                    },
                    onDelete: { id in
                        session.removeClipPanAutomationPoint(clipID: clip.id, pointID: id)
                    }
                )
            } else {
                Text("Select a clip for clip pan automation")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
        }
    }

    private func emptyLaneHint(for track: MXSessionTrack) -> String {
        if track.category == .drums { return "Pads or Steps · Add pattern to timeline" }
        if track.kind == .midi { return "Play the keys below" }
        return "Tap ● to record"
    }

    /// Part-lane row: same performance clip(s), notes filtered to Kick/Snare/Hats…
    private func drumPartRow(
        track: MXSessionTrack,
        part: MXDrumPart,
        pixelsPerBeat: CGFloat
    ) -> some View {
        let activeClips = track.clips.filter(\.isActive)
        let interactiveHeight = drumPartRowHeight - 6
        let partMuted = track.isDrumPartMuted(part)
        let anySolo = !track.soloedDrumPartSet.isEmpty
        let partSoloed = track.isDrumPartSoloed(part)
        let partSilent = partMuted || (anySolo && !partSoloed)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.surfaceRaised.opacity(partSilent ? 0.18 : 0.35))
                .contentShape(Rectangle())
                .modifier(LaneBackgroundPointerModifier(
                    pixelsPerBeat: pixelsPerBeat,
                    hasSelection: session.selectedClipID != nil,
                    onSeek: { session.seek(toBeat: max(0, $0)) },
                    onClearSelection: { session.selectClip(nil) }
                ))

            if activeClips.isEmpty {
                if part == .kick {
                    Text("Tap pads below")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            } else {
                ForEach(activeClips) { clip in
                    let partNotes = clip.midiNotes.filtered(to: part)
                    if partNotes.isEmpty {
                        // Faint clip shell so empty columns still align with the take (BandLab).
                        StudioDrumPartClipShell(
                            clip: clip,
                            pixelsPerBeat: pixelsPerBeat,
                            rowHeight: drumPartRowHeight,
                            onSelect: { session.selectClip(clip.id) }
                        )
                    } else {
                        InteractiveStudioClip(
                            clip: clip,
                            pixelsPerBeat: pixelsPerBeat,
                            bpm: session.bpm,
                            isSelected: session.selectedClipID == clip.id,
                            clipHeight: interactiveHeight,
                            displayNotes: partNotes,
                            onSelect: { session.selectClip(clip.id) },
                            onMove: { session.moveClip(id: clip.id, toStartBeat: $0) },
                            onTrimStart: { session.trimClipStart(id: clip.id, toStartBeat: $0) },
                            onTrimEnd: { session.trimClipEnd(id: clip.id, toEndBeat: $0) },
                            onFadeChange: { session.setClipFades(fadeInSeconds: $0, fadeOutSeconds: $1, clipID: clip.id) }
                        )
                    }
                }
            }
        }
        .opacity(partSilent ? 0.45 : 1)
        .clipped()
        .accessibilityLabel("\(part.shortLabel) lane\(partSilent ? ", silent" : "")")
    }

    private func playlistTakeRow(
        track: MXSessionTrack,
        takeIndex: Int,
        pixelsPerBeat: CGFloat
    ) -> some View {
        let clips = track.clips.filter { $0.takeIndex == takeIndex }
        let interactiveHeight = takeRowHeight - 6
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

            ForEach(clips) { clip in
                if clip.isActive {
                    InteractiveStudioClip(
                        clip: clip,
                        pixelsPerBeat: pixelsPerBeat,
                        bpm: session.bpm,
                        isSelected: session.selectedClipID == clip.id,
                        clipHeight: interactiveHeight,
                        onSelect: { session.selectClip(clip.id) },
                        onMove: { session.moveClip(id: clip.id, toStartBeat: $0) },
                        onTrimStart: { session.trimClipStart(id: clip.id, toStartBeat: $0) },
                        onTrimEnd: { session.trimClipEnd(id: clip.id, toEndBeat: $0) },
                        onFadeChange: { session.setClipFades(fadeInSeconds: $0, fadeOutSeconds: $1, clipID: clip.id) }
                    )
                } else {
                    GhostStudioClip(
                        clip: clip,
                        pixelsPerBeat: pixelsPerBeat,
                        rowHeight: takeRowHeight,
                        onActivate: { session.setActiveTake(clipID: clip.id) }
                    )
                }
            }
        }
        .clipped()
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
        // Landscape: compact Rec + tighter padding (Figma Studio landscape 97:113250).
        let recOuter: CGFloat = isLandscape ? 40 : 52
        let recInner: CGFloat = isLandscape ? 22 : 28
        let iconPad: CGFloat = isLandscape ? 7 : 10
        return HStack {
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

            Spacer(minLength: isLandscape ? 4 : 8)

            Button {
                guard session.canRecordAudio else { return }
                session.enterRecordMode()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: isLandscape ? 12 : 16, style: .continuous)
                        .fill(MXColor.layer2)
                        .frame(width: recOuter, height: recOuter)
                    Circle()
                        .fill(session.canRecordAudio ? MXColor.red : MXColor.grey)
                        .frame(width: recInner, height: recInner)
                }
                .padding(isLandscape ? 2 : 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(MXColor.black)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.phase != .ready || session.isInterrupted || !session.canRecordAudio)
            .opacity(session.canRecordAudio ? 1 : 0.4)

            Spacer(minLength: isLandscape ? 4 : 8)

            HStack(spacing: 2) {
                Button(action: session.togglePlayback) {
                    Group {
                        if session.isPlaying {
                            Image(systemName: "pause.fill")
                                .font(.system(size: isLandscape ? 14 : 16, weight: .semibold))
                                .foregroundStyle(MXColor.white)
                                .frame(width: 20, height: 20)
                        } else {
                            studioGlyph("studio_play", systemFallback: "play.fill", size: 20)
                        }
                    }
                    .padding(iconPad)
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
                        .padding(iconPad)
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
        .padding(.horizontal, isLandscape ? 10 : 16)
        .padding(.vertical, isLandscape ? 4 : 8)
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
                title: "Drums",
                subtitle: "Pad machine with Drum Kit patch",
                systemImage: "circle.grid.2x2.fill",
                tint: MXColor.orange
            ) {
                if let track = session.addDrumTrack() {
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

                if !clip.midiNotes.isEmpty || session.project.tracks.first(where: { $0.id == clip.trackID })?.kind == .midi {
                    Button {
                        showClipInspector = false
                        showPianoRoll = true
                    } label: {
                        Label("Edit Piano Roll", systemImage: "pianokeys")
                            .font(MXFont.mediumButton())
                            .foregroundStyle(MXColor.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(MXColor.accent.opacity(0.9))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open Cubasis-style note editor for this clip")
                }

                if !clip.midiNotes.isEmpty {
                    Button {
                        _ = session.requantizeSelectedMIDIClip()
                    } label: {
                        Label("Re-quantize MIDI", systemImage: "metronome")
                            .font(MXFont.mediumButton())
                            .foregroundStyle(MXColor.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(MXColor.orange.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Applies Strength and Swing from Studio Settings")
                }
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
                    title: "Quantize MIDI capture",
                    subtitle: "Snap pad/key note starts to 16ths on Pause/Stop",
                    isOn: session.isMIDIQuantizeEnabled
                ) {
                    session.isMIDIQuantizeEnabled.toggle()
                }
                if session.isMIDIQuantizeEnabled {
                    Divider().overlay(MXColor.layer2)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Strength")
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                            Spacer()
                            Text("\(Int((session.midiQuantizeStrength * 100).rounded()))%")
                                .font(MXFont.body3())
                                .foregroundStyle(MXColor.lightGrey)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { session.midiQuantizeStrength },
                                set: { session.midiQuantizeStrength = $0 }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                        .tint(MXColor.accent)
                        HStack {
                            Text("Swing")
                                .font(MXFont.caption())
                                .foregroundStyle(MXColor.grey)
                            Spacer()
                            Text("\(Int((session.midiQuantizeSwing * 100).rounded()))%")
                                .font(MXFont.body3())
                                .foregroundStyle(MXColor.lightGrey)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { session.midiQuantizeSwing },
                                set: { session.midiQuantizeSwing = $0 }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                        .tint(MXColor.accent)
                        Text("Applies on capture and Re-quantize")
                            .font(MXFont.caption())
                            .foregroundStyle(MXColor.grey.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
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
                Divider().overlay(MXColor.layer2)
                settingsToggleRow(
                    title: "Lock portrait while recording",
                    subtitle: "Keeps Rec chrome upright; off allows landscape record",
                    isOn: MXOrientationLock.prefersPortraitWhileRecording
                ) {
                    MXOrientationLock.prefersPortraitWhileRecording.toggle()
                    MXOrientationLock.applyForRecordMode(session.isRecordMode)
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
                Text(
                    session.headphonesConnected
                        ? "Play the chirp into the mic with headphones on (GarageBand-style)"
                        : "Plug in headphones first — speaker loopback causes feedback"
                )
                    .font(MXFont.body3())
                    .foregroundStyle(session.headphonesConnected ? MXColor.grey : MXColor.orange)
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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Manual offset")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                    Spacer()
                    Text(String(format: "%.0f ms", session.latencyCompensationMilliseconds))
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.lightGrey)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { session.latencyCompensationMilliseconds },
                        set: { session.setLatencyCompensationMilliseconds($0) }
                    ),
                    in: 0...80,
                    step: 1
                )
                .tint(MXColor.accent)
                Text("Fine-tune if auto-calibrate drifts (0–80 ms)")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey.opacity(0.8))
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

            HStack(spacing: 10) {
                Button {
                    session.calibrateLatency()
                } label: {
                    HStack(spacing: 8) {
                        if session.isCalibrating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(MXColor.black)
                        }
                        Text(session.isCalibrating ? "Calibrating…" : "Auto-calibrate")
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
                .disabled(
                    session.isCalibrating
                        || session.phase != .ready
                        || session.isRecording
                        || !session.headphonesConnected
                )
                .opacity(
                    session.isCalibrating
                        || session.phase != .ready
                        || session.isRecording
                        || !session.headphonesConnected
                        ? 0.5 : 1
                )

                Button {
                    session.clearLatencyCompensation()
                } label: {
                    Text("Reset")
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                        .frame(width: 72)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MXColor.layer2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!session.hasLatencyCompensation || session.isCalibrating)
                .opacity(!session.hasLatencyCompensation || session.isCalibrating ? 0.45 : 1)
            }

            if let error = session.calibrationError {
                Text(error)
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                session.isMonitoringEnabled
                    ? "Monitor is on — keep headphones on to avoid feedback while calibrating."
                    : "Tip: enable Monitor after calibrating so you hear yourself aligned to the beat."
            )
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)

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
        .onAppear {
            if session.isPlaying {
                session.ensurePlaybackMetersRunning()
            }
        }
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
        if track?.category == .guitar {
            return "Pedalboard"
        }
        if track?.category == .drums {
            return "Drum Kit"
        }
        if track?.category == .keys {
            return "Piano FX"
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
        let isGuitar = track.category == .guitar
        let isKeys = track.category == .keys
        let isDrums = track.category == .drums
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(mixerCategoryTint(track.category))
                    .frame(width: 3, height: 16)
                Text(track.name)
                    .font(MXFont.mediumButton())
                    .foregroundStyle(MXColor.white)
                    .lineLimit(1)
                if isGuitar {
                    Spacer(minLength: 4)
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MXColor.teal)
                } else if isKeys {
                    Spacer(minLength: 4)
                    Image(systemName: "pianokeys")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MXColor.orange)
                } else if isDrums {
                    Spacer(minLength: 4)
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MXColor.orange)
                }
            }

            insertChainBar(for: track)

            if isGuitar {
                // Figma Select Guitar Effect (`95:89964`): named amp/pedal presets.
                guitarPedalPresetRow(for: track)
            }

            if isKeys {
                // Figma Piano Midi (`95:86149`): instrument bank switch.
                pianoSynthBankRow(for: track)
                Text("Play keys while transport runs — stop to drop a keys clip on the timeline.")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isDrums {
                Text("Tap pads while transport runs — stop to drop a drum clip. Kit is short one-shots.")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isGuitar {
                // Pedalboard order: Dist → Delay → Rev (matches live insert chain).
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
                    label: "Tone",
                    valueLabel: String(format: "%+.0f", track.eqMidGain),
                    value: Binding(
                        get: { Double(track.eqMidGain) },
                        set: { session.setTrackEQMidGain(Float($0), trackID: track.id) }
                    ),
                    range: -12...12,
                    labelWidth: 56
                )

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
            } else if !isKeys && !isDrums {
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
            }

            if isKeys || isDrums {
                mixerSliderRow(
                    label: "Send",
                    valueLabel: String(format: "%.0f", track.reverbSend),
                    value: Binding(
                        get: { Double(track.reverbSend) },
                        set: { session.setTrackReverbSend(Float($0), trackID: track.id) }
                    ),
                    range: 0...100,
                    labelWidth: 56
                )
            }

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

            if !isGuitar && !isKeys && !isDrums {
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
                HStack(alignment: .bottom, spacing: 4) {
                    PlaybackStripMeter(
                        level: session.trackPlaybackLevels[track.id] ?? 0,
                        peakHold: session.trackPlaybackPeakHolds[track.id] ?? 0
                    )
                    MixerVerticalFader(
                        value: Binding(
                            get: { Double(track.volume) },
                            set: { session.setTrackVolume(Float($0), trackID: track.id) }
                        ),
                        tint: tint
                    )
                }
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
        let isGuitar = track.category == .guitar
        let isKeys = track.category == .keys
        let isDrums = track.category == .drums
        // Guitar: Dist → Dly → Rev. Keys/Drums: Synth → Send → Rev. Vocal: HPF → EQ → …
        let stages: [(label: String, active: Bool)]
        if isGuitar {
            stages = [
                ("Dist", track.distortionMix > 0.5),
                ("Dly", track.delayMix > 0.5),
                ("Rev", track.reverbMix > 0.5),
            ]
        } else if isKeys || isDrums {
            stages = [
                ("Synth", true),
                ("Send", track.reverbSend > 0.5),
                ("Rev", track.reverbMix > 0.5),
            ]
        } else {
            stages = [
                ("HPF", session.isHighPassEnabled || track.reelsVocalEnabled),
                ("EQ", abs(track.eqMidGain) >= 0.05 || (track.deEsserEnabled && track.deEsserAmount > 0.5)),
                ("Dly", track.delayMix > 0.5),
                ("Dist", track.distortionMix > 0.5),
                ("Dyn", track.reelsVocalEnabled || track.noiseGateEnabled),
                ("Rev", track.reverbMix > 0.5),
            ]
        }
        let activeFill = isGuitar ? MXColor.teal : ((isKeys || isDrums) ? MXColor.orange : MXColor.accent)
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
                                .fill(stage.active ? activeFill : MXColor.black)
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
        .accessibilityLabel(
            isGuitar ? "Pedalboard chain" : (isKeys ? "Piano FX chain" : (isDrums ? "Drum kit chain" : "Insert chain"))
        )
    }

    /// Figma Piano Midi — Soft Keys / Pad / Bass / Pluck / Synthwave chips.
    private func pianoSynthBankRow(for track: MXSessionTrack) -> some View {
        let selected = session.synthBankPreset(for: track.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Instrument")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MXSynthBankPreset.pianoBank) { bank in
                        let isOn = selected == bank
                        Button {
                            session.loadSynthBankPreset(bank, trackID: track.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bank.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isOn ? MXColor.black : MXColor.white)
                                Text(bank.subtitle)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(isOn ? MXColor.black.opacity(0.7) : MXColor.grey)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minWidth: 92, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isOn ? MXColor.orange : MXColor.black)
                            )
                            .overlay {
                                if !isOn {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(bank.title) instrument preset")
                    }
                }
            }
        }
    }

    /// Figma Select Guitar Effect — Clean / Crunch / Lead / Ambient chips.
    private func guitarPedalPresetRow(for track: MXSessionTrack) -> some View {
        let matched = session.matchingGuitarPedalPreset(for: track.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Effect")
                .font(MXFont.caption())
                .foregroundStyle(MXColor.grey)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MXGuitarPedalPreset.allCases) { preset in
                        let selected = matched == preset
                        Button {
                            session.applyGuitarPedalPreset(preset, trackID: track.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selected ? MXColor.black : MXColor.white)
                                Text(preset.subtitle)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(selected ? MXColor.black.opacity(0.7) : MXColor.grey)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minWidth: 88, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected ? MXColor.teal : MXColor.black)
                            )
                            .overlay {
                                if !selected {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.title) pedalboard preset")
                    }
                }
            }
        }
    }

    private func mixerCategoryTint(_ category: MXSessionTrack.Category) -> Color {
        switch category {
        case .vocal: return MXColor.accent
        case .guitar: return MXColor.teal
        case .keys: return MXColor.orange
        case .drums: return MXColor.orange
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

/// Vertical peak meter beside mixer faders / arrange headers (Studio One / Logic strip style).
private struct PlaybackStripMeter: View {
    var level: Float
    var peakHold: Float
    var height: CGFloat = 140
    var width: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(max(level, 0), 1))
            let hold = CGFloat(min(max(peakHold, 0), 1))
            let fillHeight = max(level > 0.001 ? 2 : 0, geo.size.height * clamped)
            let holdY = geo.size.height * (1 - hold)
            let hot = level > 0.9

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.layer2)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hot ? MXColor.red : MXColor.accent)
                    .frame(height: fillHeight)

                // Peak hold marker
                if peakHold > 0.001 {
                    Rectangle()
                        .fill(hot ? MXColor.red : MXColor.white)
                        .frame(width: geo.size.width, height: 2)
                        .position(x: geo.size.width / 2, y: max(1, min(geo.size.height - 1, holdY)))
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Track header (95:85033)

private struct StudioTrackHeader: View {
    let track: MXSessionTrack
    var isSelected: Bool
    var isArmed: Bool
    var takeLaneCount: Int
    var takeRepresentatives: [MXClip]
    var isPlaylistExpanded: Bool
    /// When non-empty, header stacks Kick/Snare/Hats… labels for expanded drum folder.
    var drumPartLabels: [String] = []
    /// Currently muted drum parts (Week 42 per-part M).
    var mutedDrumParts: Set<MXDrumPart> = []
    /// Currently soloed drum parts (Week 44 per-part S).
    var soloedDrumParts: Set<MXDrumPart> = []
    var isDrumPartsExpanded: Bool = false
    var showsDrumPartChevron: Bool = false
    var onSelect: () -> Void
    var onMute: () -> Void
    var onSolo: () -> Void
    var onSetActiveTake: (UUID) -> Void
    var onTogglePlaylist: () -> Void
    var onToggleDrumParts: () -> Void = {}
    var onToggleDrumPartMute: (MXDrumPart) -> Void = { _ in }
    var onToggleDrumPartSolo: (MXDrumPart) -> Void = { _ in }
    /// Volume automation lane visibility (Week 52).
    var showsAutomation: Bool = false
    var onToggleAutomation: () -> Void = {}
    /// Live playback peak (Week 38 taps / Week 43 arrange meter).
    var playbackLevel: Float = 0
    var playbackPeakHold: Float = 0

    private var categoryTint: Color {
        switch track.category {
        case .vocal: return MXColor.accent
        case .guitar: return MXColor.teal
        case .keys: return MXColor.orange
        case .drums: return MXColor.orange
        case .imported: return MXColor.red
        }
    }

    private var categoryIcon: String {
        switch track.category {
        case .vocal: return "mic.fill"
        case .guitar: return "guitars.fill"
        case .keys: return "pianokeys"
        case .drums: return "circle.grid.2x2.fill"
        case .imported: return "waveform"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 6) {
                if takeLaneCount > 1 {
                    Button(action: onTogglePlaylist) {
                        Image(systemName: isPlaylistExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MXColor.grey)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaylistExpanded ? "Collapse takes" : "Expand takes")
                } else if showsDrumPartChevron {
                    Button(action: onToggleDrumParts) {
                        Image(systemName: isDrumPartsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MXColor.grey)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDrumPartsExpanded ? "Collapse drum parts" : "Expand drum parts")
                }

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(categoryTint)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)

                if isDrumPartsExpanded && !drumPartLabels.isEmpty {
                    drumPartLabelsColumn
                } else {
                    trackSummaryColumn
                }

                PlaybackStripMeter(
                    level: playbackLevel,
                    peakHold: playbackPeakHold,
                    height: isDrumPartsExpanded ? 72 : 48,
                    width: 5
                )

                VStack(spacing: 3) {
                    muteSoloButton("M", active: track.isMuted, action: onMute)
                    muteSoloButton("S", active: track.isSolo, action: onSolo)
                    muteSoloButton("A", active: showsAutomation, action: onToggleAutomation)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, isDrumPartsExpanded ? 0 : 6)
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

    /// Collapsed / non-drum header: name, arm badge, takes menu, volume.
    private var trackSummaryColumn: some View {
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
                if takeLaneCount > 1 {
                    Text("T\(takeLaneCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MXColor.grey)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MXColor.black.opacity(0.35))
                        )
                    Menu {
                        ForEach(takeRepresentatives) { take in
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
                } else if showsDrumPartChevron {
                    Text("Parts")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MXColor.grey)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MXColor.black.opacity(0.35))
                        )
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
    }

    /// Expanded drum folder: label + part M/S per Kick / Snare / Hats… lane.
    private var drumPartLabelsColumn: some View {
        let parts = MXDrumPart.allCases.sorted()
        let anySolo = !soloedDrumParts.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                let muted = mutedDrumParts.contains(part)
                let soloed = soloedDrumParts.contains(part)
                let dimmed = muted || (anySolo && !soloed)
                HStack(spacing: 3) {
                    if index == 0 {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isArmed ? MXColor.red : categoryTint)
                    } else {
                        Color.clear.frame(width: 10, height: 10)
                    }
                    Text(part.shortLabel)
                        .font(MXFont.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(dimmed ? MXColor.grey : MXColor.lightGrey)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button {
                        onToggleDrumPartMute(part)
                    } label: {
                        Text("M")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(muted ? MXColor.black : MXColor.lightGrey)
                            .frame(width: 15, height: 15)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(muted ? MXColor.orange : MXColor.black.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(muted ? "Unmute \(part.shortLabel)" : "Mute \(part.shortLabel)")
                    Button {
                        onToggleDrumPartSolo(part)
                    } label: {
                        Text("S")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(soloed ? MXColor.black : MXColor.lightGrey)
                            .frame(width: 15, height: 15)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(soloed ? MXColor.accent : MXColor.black.opacity(0.35))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(soloed ? "Unsolo \(part.shortLabel)" : "Solo \(part.shortLabel)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .opacity(dimmed ? 0.75 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    var rowHeight: CGFloat = 36
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
        .frame(width: width, height: rowHeight - 6)
        .offset(x: x, y: 3)
        .opacity(0.45)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .accessibilityLabel("Inactive \(clip.name)")
        .accessibilityHint("Activates this take lane")
    }
}

// MARK: - Volume automation lane (Logic / Ableton lite)

/// Track / clip automation polyline under arrange clips (Weeks 52 / 54).
private struct VolumeAutomationLaneView: View {
    let points: [MXAutomationPoint]
    let pixelsPerBeat: CGFloat
    let beatsVisible: Double
    let height: CGFloat
    var valueMin: Float = MXVolumeAutomation.minValue
    var valueMax: Float = MXVolumeAutomation.maxValue
    /// Project-beat offset applied when drawing (clip-local points → timeline).
    var beatOffset: Double = 0
    /// When set, edits clamp to `[0, beatMax]` in the point’s native beat space.
    var beatMax: Double? = nil
    /// Reference line value (unity for volume, center for pan).
    var centerValue: Float = 1
    var onAdd: (_ beat: Double, _ value: Float) -> Void
    var onMove: (_ id: UUID, _ beat: Double, _ value: Float) -> Void
    var onDelete: (_ id: UUID) -> Void

    @State private var selectedPointID: UUID?

    private var sorted: [MXAutomationPoint] { points.sorted { $0.beat < $1.beat } }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.layer2.opacity(0.55))

                // Reference line (unity / center)
                Path { path in
                    let y = yPosition(for: centerValue, height: h)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(MXColor.grey.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))

                Path { path in
                    guard let first = sorted.first else { return }
                    path.move(to: CGPoint(
                        x: xPosition(for: first.beat + beatOffset),
                        y: yPosition(for: first.value, height: h)
                    ))
                    for point in sorted.dropFirst() {
                        path.addLine(to: CGPoint(
                            x: xPosition(for: point.beat + beatOffset),
                            y: yPosition(for: point.value, height: h)
                        ))
                    }
                }
                .stroke(MXColor.accent, lineWidth: 1.5)

                ForEach(sorted) { point in
                    Circle()
                        .fill(selectedPointID == point.id ? MXColor.orange : MXColor.accent)
                        .overlay(Circle().strokeBorder(MXColor.white.opacity(0.85), lineWidth: 1))
                        .frame(width: 12, height: 12)
                        .position(
                            x: xPosition(for: point.beat + beatOffset),
                            y: yPosition(for: point.value, height: h)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    selectedPointID = point.id
                                    let projectBeat = max(0, Double(value.location.x / pixelsPerBeat))
                                    let localBeat = clampBeat(projectBeat - beatOffset)
                                    let gain = valueFromY(value.location.y, height: h)
                                    onMove(point.id, localBeat, gain)
                                }
                        )
                        .onTapGesture {
                            if selectedPointID == point.id {
                                onDelete(point.id)
                                selectedPointID = nil
                            } else {
                                selectedPointID = point.id
                            }
                        }
                        .accessibilityLabel("Automation point")
                        .accessibilityValue(String(format: "%.2f at beat %.2f", point.value, point.beat))
                        .accessibilityHint("Drag to move. Tap twice to delete.")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let projectBeat = max(0, Double(location.x / pixelsPerBeat))
                let localBeat = clampBeat(projectBeat - beatOffset)
                let gain = valueFromY(location.y, height: h)
                onAdd(localBeat, gain)
            }
            .frame(width: w, height: h)
        }
        .accessibilityLabel("Automation lane")
        .accessibilityHint("Tap to add a point")
    }

    private func clampBeat(_ beat: Double) -> Double {
        let lower = max(0, beat)
        if let beatMax {
            return min(beatMax, lower)
        }
        return lower
    }

    private func xPosition(for beat: Double) -> CGFloat {
        CGFloat(beat) * pixelsPerBeat
    }

    private func yPosition(for value: Float, height: CGFloat) -> CGFloat {
        let span = max(1e-6, valueMax - valueMin)
        let t = CGFloat((value - valueMin) / span)
        return height * (1 - min(1, max(0, t)))
    }

    private func valueFromY(_ y: CGFloat, height: CGFloat) -> Float {
        guard height > 0 else { return centerValue }
        let t = 1 - min(1, max(0, y / height))
        let span = valueMax - valueMin
        return valueMin + Float(t) * span
    }
}

// MARK: - Clip fade wedges (Logic / Pro Tools visual)

/// Equal-power fade-in / fade-out overlays on arrange clips (drag handles when selected).
private struct StudioClipFadeWedges: View {
    let fadeInSeconds: Double
    let fadeOutSeconds: Double
    let bpm: Double
    let pixelsPerBeat: CGFloat
    let clipWidth: CGFloat
    let clipHeight: CGFloat

    var body: some View {
        let inBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: fadeInSeconds, bpm: bpm)
        let outBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: fadeOutSeconds, bpm: bpm)
        let inW = min(clipWidth, CGFloat(inBeats) * pixelsPerBeat)
        let outW = min(clipWidth, CGFloat(outBeats) * pixelsPerBeat)
        Canvas { context, size in
            if inW > 1 {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: 0))
                let steps = max(8, Int(inW / 2))
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let x = inW * CGFloat(t)
                    let gain = MXClipFadeGeometry.fadeInGain(t)
                    // Darken where gain is low (top of wedge).
                    let y = size.height * (1 - CGFloat(gain))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: inW, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(Color.black.opacity(0.45)))
            }
            if outW > 1 {
                var path = Path()
                let startX = size.width - outW
                path.move(to: CGPoint(x: startX, y: 0))
                let steps = max(8, Int(outW / 2))
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let x = startX + outW * CGFloat(t)
                    let gain = MXClipFadeGeometry.fadeOutGain(t)
                    let y = size.height * (1 - CGFloat(gain))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(Color.black.opacity(0.45)))
            }
        }
        .frame(width: clipWidth, height: clipHeight)
        .clipped()
    }
}

// MARK: - Interactive clip (select / move / trim / fade)

private struct InteractiveStudioClip: View {
    let clip: MXClip
    let pixelsPerBeat: CGFloat
    /// Project tempo — converts fade seconds → timeline width for wedges.
    var bpm: Double = 120
    let isSelected: Bool
    /// Clip body height; smaller in expanded playlist take rows.
    var clipHeight: CGFloat = 52
    /// When set (drum part lanes), draw only these notes instead of the full clip roll.
    var displayNotes: [MXMIDINote]? = nil
    var onSelect: () -> Void
    var onMove: (_ toStartBeat: Double) -> Void
    var onTrimStart: (_ toStartBeat: Double) -> Void
    var onTrimEnd: (_ toEndBeat: Double) -> Void
    /// Logic-style drag edit for fade-in / fade-out (Week 50).
    var onFadeChange: (_ fadeInSeconds: Double?, _ fadeOutSeconds: Double?) -> Void = { _, _ in }

    private var rollNotes: [MXMIDINote] { displayNotes ?? clip.midiNotes }

    private let handleWidth: CGFloat = 14
    private let fadeHandleSize: CGFloat = 16

    @State private var activeDrag: DragKind?
    @State private var dragDeltaX: CGFloat = 0
    @State private var previewFadeIn: Double?
    @State private var previewFadeOut: Double?

    private enum DragKind {
        case move, trimStart, trimEnd, fadeIn, fadeOut
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
        case .trimEnd, .fadeIn, .fadeOut, .none: return baseX
        }
    }

    private var displayWidth: CGFloat {
        switch activeDrag {
        case .trimStart: return max(24, baseWidth - dragDeltaX)
        case .trimEnd: return max(24, baseWidth + dragDeltaX)
        case .move, .fadeIn, .fadeOut, .none: return baseWidth
        }
    }

    private var displayFadeIn: Double { previewFadeIn ?? clip.fadeInSeconds }
    private var displayFadeOut: Double { previewFadeOut ?? clip.fadeOutSeconds }

    private var maxFadeSeconds: Double {
        if let duration = clip.sourceDurationSeconds { return max(0, duration) }
        return max(0, clip.lengthBeats * 60.0 / max(bpm, 1))
    }

    var body: some View {
        clipChrome
            .accessibilityLabel(clip.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var clipChrome: some View {
        let base = ZStack(alignment: .leading) {
            if rollNotes.isEmpty && clip.midiNotes.isEmpty {
                StudioWaveformClip()
                    .frame(width: displayWidth, height: clipHeight)
                    .opacity(isSelected ? 1 : 0.92)
            } else if rollNotes.isEmpty {
                // Part lane with no hits for this column — keep clip bounds selectable.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.layer2.opacity(0.35))
                    .frame(width: displayWidth, height: clipHeight)
            } else {
                StudioMIDIRollClip(notes: rollNotes, lengthBeats: clip.lengthBeats)
                    .frame(width: displayWidth, height: clipHeight)
                    .opacity(isSelected ? 1 : 0.92)
            }

            // Logic / Pro Tools equal-power fade wedges (drag when selected — Week 50).
            StudioClipFadeWedges(
                fadeInSeconds: displayFadeIn,
                fadeOutSeconds: displayFadeOut,
                bpm: bpm,
                pixelsPerBeat: pixelsPerBeat,
                clipWidth: displayWidth,
                clipHeight: clipHeight
            )
            .allowsHitTesting(false)

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

                // Fade drag knobs above chrome so they stay hittable (Logic / Pro Tools).
                fadeInHandle
                fadeOutHandle
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

    private var fadeInHandleX: CGFloat {
        let beats = MXClipFadeGeometry.widthBeats(fadeSeconds: displayFadeIn, bpm: bpm)
        return min(displayWidth - fadeHandleSize, max(0, CGFloat(beats) * pixelsPerBeat - fadeHandleSize / 2))
    }

    private var fadeOutHandleX: CGFloat {
        let beats = MXClipFadeGeometry.widthBeats(fadeSeconds: displayFadeOut, bpm: bpm)
        let outW = min(displayWidth, CGFloat(beats) * pixelsPerBeat)
        return max(0, displayWidth - outW - fadeHandleSize / 2)
    }

    private var fadeInHandle: some View {
        fadeHandleKnob
            .position(x: fadeInHandleX + fadeHandleSize / 2, y: fadeHandleSize / 2 + 2)
            .highPriorityGesture(fadeInGesture)
            .accessibilityLabel("Fade in")
            .accessibilityValue(String(format: "%.2f seconds", displayFadeIn))
            .accessibilityHint("Drag to adjust fade in")
    }

    private var fadeOutHandle: some View {
        fadeHandleKnob
            .position(x: fadeOutHandleX + fadeHandleSize / 2, y: fadeHandleSize / 2 + 2)
            .highPriorityGesture(fadeOutGesture)
            .accessibilityLabel("Fade out")
            .accessibilityValue(String(format: "%.2f seconds", displayFadeOut))
            .accessibilityHint("Drag to adjust fade out")
    }

    private var fadeHandleKnob: some View {
        Circle()
            .fill(MXColor.accent)
            .overlay(
                Circle()
                    .strokeBorder(MXColor.white.opacity(0.85), lineWidth: 1)
            )
            .frame(width: fadeHandleSize, height: fadeHandleSize)
            .contentShape(Circle().scale(1.4))
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

    private var fadeInGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                activeDrag = .fadeIn
                let baseBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: clip.fadeInSeconds, bpm: bpm)
                let nextBeats = max(0, baseBeats + Double(value.translation.width / pixelsPerBeat))
                let nextSec = min(maxFadeSeconds, MXClipFadeGeometry.seconds(widthBeats: nextBeats, bpm: bpm))
                previewFadeIn = nextSec
            }
            .onEnded { value in
                let baseBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: clip.fadeInSeconds, bpm: bpm)
                let nextBeats = max(0, baseBeats + Double(value.translation.width / pixelsPerBeat))
                let nextSec = min(maxFadeSeconds, MXClipFadeGeometry.seconds(widthBeats: nextBeats, bpm: bpm))
                previewFadeIn = nil
                activeDrag = nil
                onFadeChange(nextSec, nil)
            }
    }

    private var fadeOutGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                activeDrag = .fadeOut
                // Drag left widens fade-out (Logic / Pro Tools).
                let baseBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: clip.fadeOutSeconds, bpm: bpm)
                let nextBeats = max(0, baseBeats - Double(value.translation.width / pixelsPerBeat))
                let nextSec = min(maxFadeSeconds, MXClipFadeGeometry.seconds(widthBeats: nextBeats, bpm: bpm))
                previewFadeOut = nextSec
            }
            .onEnded { value in
                let baseBeats = MXClipFadeGeometry.widthBeats(fadeSeconds: clip.fadeOutSeconds, bpm: bpm)
                let nextBeats = max(0, baseBeats - Double(value.translation.width / pixelsPerBeat))
                let nextSec = min(maxFadeSeconds, MXClipFadeGeometry.seconds(widthBeats: nextBeats, bpm: bpm))
                previewFadeOut = nil
                activeDrag = nil
                onFadeChange(nil, nextSec)
            }
    }
}

// MARK: - Empty drum part shell (aligns columns when a part has no hits)

private struct StudioDrumPartClipShell: View {
    let clip: MXClip
    let pixelsPerBeat: CGFloat
    var rowHeight: CGFloat = 40
    var onSelect: () -> Void = {}

    private var width: CGFloat {
        max(24, CGFloat(clip.lengthBeats) * pixelsPerBeat)
    }

    private var x: CGFloat {
        CGFloat(clip.startBeat) * pixelsPerBeat
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(MXColor.grey.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(MXColor.layer2.opacity(0.2))
            )
            .frame(width: width, height: rowHeight - 6)
            .offset(x: x, y: 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityLabel("Empty \(clip.name) part")
            .accessibilityHint("Selects the drum clip")
    }
}

// MARK: - Piano-roll lite clip (MIDI notes)

private struct StudioMIDIRollClip: View {
    let notes: [MXMIDINote]
    let lengthBeats: Double

    var body: some View {
        Canvas { context, size in
            let beats = max(lengthBeats, 0.25)
            // Single-pitch part lanes (Kick/Snare…) use a mid-band hit bar for readability.
            let uniquePitches = Set(notes.map(\.note))
            if uniquePitches.count <= 2 {
                let rowH = max(4, size.height * 0.55)
                let y = (size.height - rowH) / 2
                for note in notes {
                    let x = CGFloat(note.startBeat / beats) * size.width
                    let w = max(3, CGFloat(note.lengthBeats / beats) * size.width)
                    let rect = CGRect(x: x, y: y, width: w, height: rowH)
                    let alpha = 0.5 + 0.5 * (Double(note.velocity) / 127.0)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(MXColor.orange.opacity(alpha))
                    )
                }
            } else {
                let minNote = notes.map(\.note).min() ?? 60
                let maxNote = notes.map(\.note).max() ?? 72
                let noteSpan = max(1, Int(maxNote) - Int(minNote) + 1)
                let rowH = size.height / CGFloat(noteSpan)
                for note in notes {
                    let x = CGFloat(note.startBeat / beats) * size.width
                    let w = max(2, CGFloat(note.lengthBeats / beats) * size.width)
                    let row = Int(maxNote) - Int(note.note)
                    let y = CGFloat(row) * rowH + 1
                    let rect = CGRect(x: x, y: y, width: w, height: max(2, rowH - 2))
                    let alpha = 0.45 + 0.55 * (Double(note.velocity) / 127.0)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(MXColor.orange.opacity(alpha))
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MXColor.layer2.opacity(0.65))
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
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
