import AudioToolbox
import AVFoundation
import Foundation
import MXStudioEngine
import Observation
import UniformTypeIdentifiers

/// Studio session — project, transport, record → clip → playback.
@MainActor
@Observable
public final class StudioSessionController {
    public enum Phase: Equatable {
        case idle
        case ready
        case failed(String)
    }

    public private(set) var project: MXProject
    public let preset: StudioPreset

    public private(set) var phase: Phase = .idle
    public private(set) var isPlaying = false
    public private(set) var isRecording = false
    public private(set) var isRecordMode = false
    public private(set) var isCountingIn = false
    public private(set) var isInterrupted = false
    public private(set) var inputLevel: Float = 0
    /// True while peak exceeds ~−1 dBFS (linear ≈ 0.89).
    public private(set) var isInputClipping = false
    public private(set) var peakHoldLevel: Float = 0
    public private(set) var showClipWarning = false
    public private(set) var headphoneTip: String?
    public private(set) var showQuietRoomTip = false
    public private(set) var selectedClipID: UUID?
    public private(set) var canUndo = false
    public private(set) var playheadBeat: Double = 0
    public private(set) var playheadLabel: String = "001 Bar / 1 Beat"
    public private(set) var playheadBar: Int = 1
    public private(set) var playheadBeatInBar: Int = 1
    public private(set) var playheadTimeLabel: String = "00:00.0"
    public private(set) var bpm: Double = 120
    public private(set) var musicalKey: String = "Cmaj"

    /// Vocal “Cut rumble” — 100 Hz HPF on clip playback path. On by default.
    public var isHighPassEnabled: Bool = true {
        didSet { applyHighPassToPlayers() }
    }

    public var isMonitoringEnabled: Bool = false {
        didSet {
            recorder?.isMonitoringEnabled = isMonitoringEnabled
        }
    }

    public private(set) var lastSavedAt: Date?
    public private(set) var saveError: String?
    public private(set) var recordError: String?
    public private(set) var isExporting = false
    public private(set) var exportError: String?
    public private(set) var lastExportURLs: [URL] = []
    /// Non-fatal warnings when clip audio files are missing on disk (Week 24).
    public private(set) var clipLoadWarnings: [String] = []

    public var isMetronomeEnabled: Bool = true {
        didSet { metronome?.isEnabled = isMetronomeEnabled }
    }

    public var metronomeLevel: Float = 0.6 {
        didSet { metronome?.level = metronomeLevel }
    }

    public var countInBars: Int = 1

    public private(set) var graph: MXGraph?
    public private(set) var transport: MXTransport?

    /// True when the armed track is MIDI — drives piano keyboard visibility.
    public var showsPianoKeyboard: Bool {
        armedTrack?.kind == .midi
    }

    /// True when the armed track can accept microphone recording.
    public var canRecordAudio: Bool {
        armedTrack?.kind == .audio
    }

    /// Currently armed session track, if any.
    public var armedTrack: MXSessionTrack? {
        project.tracks.first(where: \.isArmed)
    }

    private var audioSession: MXAudioSession?
    private var metronome: MXMetronome?
    private var recorder: MXRecorder?
    private var calibrator: MXLatencyCalibrator?
    private var playheadObserver: MXPlayheadObserver?
    private var countInTask: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var wasPlayingBeforeInterruption = false
    private var autosaveTask: Task<Void, Never>?
    private var clipPlayers: [UUID: AVAudioPlayerNode] = [:]
    private var clipEQs: [UUID: AVAudioUnitEQ] = [:]
    private var clipDelays: [UUID: AVAudioUnitDelay] = [:]
    private var clipDistortions: [UUID: AVAudioUnitDistortion] = [:]
    private var clipComps: [UUID: AVAudioUnitEffect] = [:]
    private var clipReverbs: [UUID: AVAudioUnitReverb] = [:]
    private var liveInstruments: [UUID: any MXInstrument] = [:]
    private var instrumentChains: [UUID: MXTrackChain] = [:]
    private var reverbAux: MXAuxBus?
    private var activeTakeURL: URL?
    private var editStack = StudioEditStack()
    private var clipWarningClearTask: Task<Void, Never>?
    private static let quietRoomTipKey = "mxstudio.didShowQuietRoomTip"
    /// Linear amplitude ≈ −1 dBFS.
    private static let clipThreshold: Float = 0.891

    public init(project: MXProject) {
        self.project = project
        self.preset = project.preset
        self.bpm = project.bpm
    }

    public convenience init(preset: StudioPreset = .vocal) {
        let project: MXProject
        if preset == .vocal, let existing = MXProjectStore.shared.loadLastOpened(), existing.preset == .vocal {
            project = existing
        } else if preset == .vocal {
            project = (try? MXProjectStore.shared.createVocalProject()) ?? .untitledVocal()
        } else if preset == .guitar, let existing = MXProjectStore.shared.loadLastOpened(), existing.preset == .guitar {
            project = existing
        } else if preset == .guitar {
            project = (try? MXProjectStore.shared.createGuitarProject()) ?? .untitledGuitar()
        } else if preset == .midi, let existing = MXProjectStore.shared.loadLastOpened(), existing.preset == .midi {
            project = existing
        } else if preset == .midi {
            project = (try? MXProjectStore.shared.createMIDIProject()) ?? .untitledMIDI()
        } else {
            project = MXProject(name: "Untitled \(preset.title)", tracks: [
                MXSessionTrack(name: "Track 1", kind: .audio, isArmed: true)
            ], preset: preset)
            try? MXProjectStore.shared.save(project)
        }
        self.init(project: project)
    }

    // MARK: - Lifecycle

    public func start() {
        guard phase == .idle || isFailed else { return }
        do {
            let session = MXAudioSession(configuration: .studio)
            session.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.handleAudioSessionEvent(event)
                }
            }

            let graph = MXGraph(session: session, sampleRate: project.sampleRate)
            let tempoMap = MXTempoMap(
                bpm: project.bpm,
                timeSignature: MXTimeSignature(
                    project.timeSignatureNumerator,
                    project.timeSignatureDenominator
                )
            )
            let transport = MXTransport(
                tempoMap: tempoMap,
                sampleRate: project.sampleRate,
                clockSource: .realtime
            )
            bpm = transport.tempoMap.tempo(atBeat: 0)

            try graph.prepare(mode: .realtime)
            transport.setSampleRate(graph.sampleRate)

            let metronome = MXMetronome(transport: transport, sampleRate: graph.sampleRate)
            metronome.isEnabled = isMetronomeEnabled
            metronome.level = metronomeLevel
            metronome.prepareSchedule(fromSample: 0)
            graph.connectSourceToMaster(metronome.node)

            let calibrator = MXLatencyCalibrator(session: session, sampleRate: graph.sampleRate)
            let recorder = MXRecorder(graph: graph, transport: transport, calibrator: calibrator)

            try graph.start()

            self.audioSession = session
            self.graph = graph
            self.transport = transport
            self.metronome = metronome
            self.calibrator = calibrator
            self.recorder = recorder
            self.phase = .ready
            applyPreferredMonitoring()
            refreshRouteTip()
            maybeShowQuietRoomTip()

            attachPlayersForExistingClips()
            applyHighPassToPlayers()
            ensureReverbAux(on: graph)
            for track in project.tracks where track.kind == .midi {
                attachMIDIInstrument(for: track.id, name: track.name)
            }

            let observer = MXPlayheadObserver(transport: transport)
            observer.start(preferredFPS: 30) { [weak self] readout in
                Task { @MainActor in
                    guard let self else { return }
                    self.applyPlayhead(readout)
                    self.isPlaying = readout.state == .playing || readout.state == .recording
                    if self.isCountingIn {
                        let beatsPerBar = Double(self.project.timeSignatureNumerator)
                        let countInBeats = Double(self.countInBars) * beatsPerBar
                        if readout.beat >= countInBeats - 1e-6 {
                            self.isCountingIn = false
                        }
                    }
                }
            }
            playheadObserver = observer
            persistSoon()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Retry engine boot after a `.failed` phase (Week 24).
    public func retryStart() {
        shutdown()
        start()
    }

    public func shutdown() {
        countInTask?.cancel()
        countInTask = nil
        meterTask?.cancel()
        meterTask = nil
        autosaveTask?.cancel()
        autosaveTask = nil
        if isRecording {
            _ = try? recorder?.stopRecording()
            isRecording = false
        }
        stopClipPlayers()
        detachAllClipPlayers()
        detachLiveInstrument()
        persistNow()
        playheadObserver?.stop()
        playheadObserver = nil
        transport?.stop()
        graph?.stop()
        graph?.session.deactivate()
        audioSession?.onEvent = nil
        clipPlayers.removeAll()
        clipEQs.removeAll()
        clipDelays.removeAll()
        clipDistortions.removeAll()
        clipComps.removeAll()
        clipReverbs.removeAll()
        editStack.clear()
        canUndo = false
        selectedClipID = nil
        peakHoldLevel = 0
        isInputClipping = false
        showClipWarning = false
        metronome = nil
        recorder = nil
        calibrator = nil
        transport = nil
        graph = nil
        audioSession = nil
        isPlaying = false
        isCountingIn = false
        isInterrupted = false
        isRecordMode = false
        inputLevel = 0
        phase = .idle
    }

    // MARK: - Transport

    public func togglePlayback() {
        guard let transport, phase == .ready, !isInterrupted, !isRecording else { return }
        if transport.isPlaying {
            pausePlayback()
            return
        }
        beginPlayback(fromSample: transport.currentSample, withCountIn: countInBars > 0)
    }

    public func stop() {
        if isRecording {
            stopRecordingAndCommit()
            return
        }
        countInTask?.cancel()
        countInTask = nil
        isCountingIn = false
        stopClipPlayers()
        transport?.stopAndReturn()
        transport?.seek(toSample: 0)
        metronome?.resetCursor(toSample: 0)
        metronome?.prepareSchedule(fromSample: 0)
        isPlaying = false
        playheadBeat = 0
        playheadBar = 1
        playheadBeatInBar = 1
        playheadLabel = "001 Bar / 1 Beat"
        playheadTimeLabel = "00:00.0"
    }

    // MARK: - Record

    public func enterRecordMode() {
        isRecordMode = true
        recordError = nil
        // Arm live input for Monitor even before Rec starts.
        recorder?.setLiveInputArmed(true)
        applyPreferredMonitoring()
        refreshRouteTip()
    }

    public func exitRecordMode() {
        if isRecording {
            stopRecordingAndCommit()
        }
        isRecordMode = false
        inputLevel = 0
        recorder?.setLiveInputArmed(false)
        // Keep monitor preference for guitar sessions with headphones; otherwise off.
        if preset != .guitar {
            isMonitoringEnabled = false
        } else {
            applyPreferredMonitoring()
        }
    }

    public func toggleRecord() {
        if isRecording {
            stopRecordingAndCommit()
        } else {
            Task { await startRecording() }
        }
    }

    public func startRecording() async {
        guard phase == .ready, !isRecording, !isInterrupted else { return }
        recordError = nil

        let permitted = await requestMicPermission()
        guard permitted else {
            recordError = "Microphone access is required to record."
            isRecordMode = true
            return
        }

        guard let transport, let recorder else { return }

        isRecordMode = true
        if transport.isPlaying {
            pausePlayback()
        }

        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let fileName = "take_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
        let url = audioDir.appendingPathComponent(fileName)

        do {
            try recorder.startRecording(to: url)
            activeTakeURL = url
            isRecording = true
            startMeterPolling()

            let sample = transport.currentSample
            metronome?.prepareSchedule(fromSample: sample)
            metronome?.resetCursor(toSample: sample)

            if countInBars > 0 {
                isCountingIn = true
                let beatsPerBar = Double(project.timeSignatureNumerator)
                let seconds = Double(countInBars) * beatsPerBar * 60.0 / max(bpm, 1)
                countInTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    await MainActor.run {
                        guard let self, !Task.isCancelled else { return }
                        self.isCountingIn = false
                    }
                }
            }

            transport.record(fromSample: sample)
            isPlaying = true
        } catch {
            isRecording = false
            activeTakeURL = nil
            recordError = error.localizedDescription
        }
    }

    public func stopRecordingAndCommit() {
        guard isRecording, let recorder, let transport else {
            isRecording = false
            return
        }

        countInTask?.cancel()
        countInTask = nil
        isCountingIn = false
        meterTask?.cancel()
        meterTask = nil

        do {
            let take = try recorder.stopRecording()
            transport.stop()
            isPlaying = false
            isRecording = false
            inputLevel = 0

            guard take.frameCount > 0, let trackID = project.armedTrack?.id ?? project.tracks.first?.id else {
                try? FileManager.default.removeItem(at: take.url)
                activeTakeURL = nil
                return
            }

            let startBeat = transport.tempoMap.beat(forSample: take.startSample, sampleRate: transport.sampleRate)
            let endSample = take.startSample + Int64(take.frameCount)
            let endBeat = transport.tempoMap.beat(forSample: endSample, sampleRate: transport.sampleRate)
            let lengthBeats = max(0.25, endBeat - startBeat)
            let durationSeconds = Double(take.frameCount) / max(transport.sampleRate, 1)

            let takeNumber = (project.tracks.first(where: { $0.id == trackID })?.clips.count ?? 0) + 1
            let clip = MXClip(
                trackID: trackID,
                name: "Take \(takeNumber)",
                startBeat: startBeat,
                lengthBeats: lengthBeats,
                audioFileName: take.url.lastPathComponent,
                sourceOffsetSeconds: 0,
                sourceDurationSeconds: durationSeconds
            )

            pushUndoSnapshot()
            if let index = project.tracks.firstIndex(where: { $0.id == trackID }) {
                project.tracks[index].clips.append(clip)
            }

            attachPlayer(for: clip)
            applyHighPassToPlayers()
            selectedClipID = clip.id
            persistNow()
            activeTakeURL = nil
            // Return to Figma 95:85026 — Studio After Record
            isRecordMode = false
            refreshPlayheadFromTransport()
            if peakHoldLevel >= Self.clipThreshold {
                showClipWarning = true
                scheduleClipWarningClear()
            }
        } catch {
            isRecording = false
            inputLevel = 0
            recordError = error.localizedDescription
            activeTakeURL = nil
        }
    }

    // MARK: - Track controls

    public static let maxTracks = 8

    public var canAddTrack: Bool { project.tracks.count < Self.maxTracks }

    public private(set) var trackLimitMessage: String?

    public func dismissTrackLimitMessage() {
        trackLimitMessage = nil
    }

    /// Append an empty Vocals/Audio track and arm it (BandLab-style).
    @discardableResult
    public func addAudioTrack(named name: String? = nil) -> MXSessionTrack? {
        guard canAddTrack else {
            trackLimitMessage = "Track limit reached (\(Self.maxTracks))"
            return nil
        }
        let index = project.tracks.count + 1
        let trackName = name ?? (index == 1 ? "Vocals/Audio" : "Vocals/Audio \(index)")
        let track = MXSessionTrack(name: trackName, kind: .audio, category: .vocal, isArmed: true)
        for i in project.tracks.indices {
            project.tracks[i].isArmed = false
        }
        project.tracks.append(track)
        persistSoon()
        return track
    }

    /// Append a guitar audio track with pedalboard seed FX and arm it.
    @discardableResult
    public func addGuitarTrack(named name: String? = nil) -> MXSessionTrack? {
        guard canAddTrack else {
            trackLimitMessage = "Track limit reached (\(Self.maxTracks))"
            return nil
        }
        let guitarIndex = project.tracks.filter { $0.category == .guitar }.count + 1
        let trackName = name ?? (guitarIndex == 1 ? "Guitar" : "Guitar \(guitarIndex)")
        let track = MXSessionTrack(
            name: trackName,
            kind: .audio,
            category: .guitar,
            isArmed: true,
            reverbMix: 18,
            eqMidGain: 1.5,
            delayMix: 20,
            delayTime: 0.32,
            distortionMix: 35
        )
        for i in project.tracks.indices {
            project.tracks[i].isArmed = false
        }
        project.tracks.append(track)
        persistSoon()
        return track
    }

    /// Append a MIDI keys track, arm it, and attach a live instrument when ready.
    @discardableResult
    public func addMIDITrack(named name: String? = nil) -> MXSessionTrack? {
        guard canAddTrack else {
            trackLimitMessage = "Track limit reached (\(Self.maxTracks))"
            return nil
        }
        let keysIndex = project.tracks.filter { $0.kind == .midi }.count + 1
        let trackName = name ?? (keysIndex == 1 ? "Piano" : "Piano \(keysIndex)")
        let track = MXSessionTrack(name: trackName, kind: .midi, category: .keys, isArmed: true)
        for i in project.tracks.indices {
            project.tracks[i].isArmed = false
        }
        project.tracks.append(track)
        if let graph {
            _ = ensureReverbAux(on: graph)
            attachMIDIInstrument(for: track.id, name: track.name)
        }
        persistSoon()
        return track
    }

    public func armTrack(id: UUID) {
        guard project.tracks.contains(where: { $0.id == id }) else { return }
        for i in project.tracks.indices {
            project.tracks[i].isArmed = (project.tracks[i].id == id)
        }
        persistSoon()
    }

    func setTrackCategory(_ category: MXSessionTrack.Category, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].category = category
        persistSoon()
    }

    /// Copy an external audio file into the project Audio folder, create a new
    /// track + clip at beat 0. Supports common phone audio containers.
    @discardableResult
    public func importAudioFile(from sourceURL: URL) throws -> MXSessionTrack {
        guard canAddTrack else {
            trackLimitMessage = "Track limit reached (\(Self.maxTracks))"
            throw ImportError.trackLimitReached
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let ext = sourceURL.pathExtension.lowercased()
        let allowed = Set(["wav", "m4a", "mp3", "caf", "aac", "aiff", "aif"])
        guard allowed.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .audio) == true else {
            throw ImportError.unsupportedType
        }

        // Validate readable audio
        let probe = try AVAudioFile(forReading: sourceURL)
        let durationSeconds = Double(probe.length) / max(probe.fileFormat.sampleRate, 1)
        guard durationSeconds > 0.05 else { throw ImportError.emptyFile }

        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let base = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let destName = "import_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext.isEmpty ? "wav" : ext)"
        let destURL = audioDir.appendingPathComponent(destName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let lengthBeats: Double
        if let transport {
            let endBeat = transport.tempoMap.beat(
                forSample: Int64((durationSeconds * transport.sampleRate).rounded()),
                sampleRate: transport.sampleRate
            )
            lengthBeats = max(0.25, endBeat)
        } else {
            lengthBeats = max(0.25, durationSeconds * bpm / 60.0)
        }

        let trackName = base.isEmpty ? "Import" : String(base.prefix(28))
        guard let track = addAudioTrack(named: trackName) else {
            try? FileManager.default.removeItem(at: destURL)
            throw ImportError.trackLimitReached
        }
        if let index = project.tracks.firstIndex(where: { $0.id == track.id }) {
            project.tracks[index].category = .imported
        }

        let clip = MXClip(
            trackID: track.id,
            name: trackName,
            startBeat: 0,
            lengthBeats: lengthBeats,
            audioFileName: destName,
            sourceOffsetSeconds: 0,
            sourceDurationSeconds: durationSeconds
        )
        if let index = project.tracks.firstIndex(where: { $0.id == track.id }) {
            project.tracks[index].clips.append(clip)
        }
        attachPlayer(for: clip)
        applyHighPassToPlayers()
        selectedClipID = clip.id
        persistNow()
        return track
    }

    /// Import a stub AI-generated clip into the current project (Week 18).
    @discardableResult
    public func importAIResult(_ result: AIComposeResult) throws -> MXSessionTrack {
        try MXAIStudioImporter.importIntoSession(self, result: result)
    }

    /// Append a clip whose audio file already lives in the project `Audio/` folder.
    func addImportedClip(_ clip: MXClip, toTrackID trackID: UUID) throws {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].clips.append(clip)
        attachPlayer(for: clip)
        applyHighPassToPlayers()
        selectedClipID = clip.id
        persistNow()
    }

    public enum ImportError: Error, LocalizedError {
        case trackLimitReached
        case unsupportedType
        case emptyFile

        public var errorDescription: String? {
            switch self {
            case .trackLimitReached: return "Track limit reached (\(StudioSessionController.maxTracks))"
            case .unsupportedType: return "Unsupported audio file"
            case .emptyFile: return "That file has no audio"
            }
        }
    }

    public func selectClip(_ id: UUID?) {
        selectedClipID = id
    }

    public func dismissQuietRoomTip() {
        showQuietRoomTip = false
        UserDefaults.standard.set(true, forKey: Self.quietRoomTipKey)
    }

    public func undo() {
        guard let previous = editStack.pop() else { return }
        let wasPlaying = transport?.isPlaying == true
        if wasPlaying { pausePlayback() }
        rebuildPlayers(for: previous)
        canUndo = editStack.canUndo
        selectedClipID = nil
        persistNow()
    }

    public func deleteSelectedClip() {
        guard let id = selectedClipID else { return }
        deleteClip(id: id)
    }

    public func deleteClip(id: UUID) {
        guard let loc = locateClip(id) else { return }
        pushUndoSnapshot()
        detachPlayer(for: id)
        project.tracks[loc.trackIndex].clips.remove(at: loc.clipIndex)
        if selectedClipID == id { selectedClipID = nil }
        persistSoon()
    }

    public func moveSelectedClip(byBeats delta: Double) {
        guard let id = selectedClipID, var clip = clip(id) else { return }
        pushUndoSnapshot()
        clip.startBeat = max(0, ((clip.startBeat + delta) * 4).rounded() / 4) // 16th snap
        replaceClip(clip)
        persistSoon()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    public func moveClip(id: UUID, toStartBeat newStart: Double) {
        guard var clip = clip(id) else { return }
        pushUndoSnapshot()
        clip.startBeat = max(0, (newStart * 4).rounded() / 4)
        replaceClip(clip)
        persistSoon()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    /// Trim left edge: `newStartBeat` on timeline; keeps right edge fixed when possible.
    public func trimClipStart(id: UUID, toStartBeat newStartBeat: Double) {
        guard var clip = clip(id), let transport else { return }
        let rightEdge = clip.startBeat + clip.lengthBeats
        let snapped = max(0, min(newStartBeat, rightEdge - 0.25))
        let snappedStart = (snapped * 4).rounded() / 4
        guard abs(snappedStart - clip.startBeat) > 1e-6 else { return }

        pushUndoSnapshot()
        let deltaBeats = snappedStart - clip.startBeat
        let deltaSeconds = transport.tempoMap.seconds(forBeat: clip.startBeat + deltaBeats)
            - transport.tempoMap.seconds(forBeat: clip.startBeat)
        clip.sourceOffsetSeconds = max(0, clip.sourceOffsetSeconds + deltaSeconds)
        if let dur = clip.sourceDurationSeconds {
            clip.sourceDurationSeconds = max(0.05, dur - deltaSeconds)
        }
        clip.startBeat = snappedStart
        clip.lengthBeats = max(0.25, rightEdge - snappedStart)
        replaceClip(clip)
        persistSoon()
        if transport.isPlaying {
            scheduleClipPlayers(fromSample: transport.currentSample)
        }
    }

    /// Trim right edge: `newEndBeat` on timeline; keeps left edge fixed.
    public func trimClipEnd(id: UUID, toEndBeat newEndBeat: Double) {
        guard var clip = clip(id), let transport else { return }
        let snappedEnd = max(clip.startBeat + 0.25, (newEndBeat * 4).rounded() / 4)
        let newLength = snappedEnd - clip.startBeat
        guard abs(newLength - clip.lengthBeats) > 1e-6 else { return }

        pushUndoSnapshot()
        clip.lengthBeats = newLength
        let startSec = transport.tempoMap.seconds(forBeat: clip.startBeat)
        let endSec = transport.tempoMap.seconds(forBeat: snappedEnd)
        clip.sourceDurationSeconds = max(0.05, endSec - startSec)
        replaceClip(clip)
        persistSoon()
        if transport.isPlaying {
            scheduleClipPlayers(fromSample: transport.currentSample)
        }
    }

    public func toggleMute(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].isMuted.toggle()
        applyTrackMix(trackID: trackID)
        persistSoon()
    }

    public func toggleSolo(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].isSolo.toggle()
        applyTrackMix(trackID: trackID)
        persistSoon()
    }

    public func setTrackVolume(_ volume: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].volume = min(max(volume, 0), 1)
        applyTrackMix(trackID: trackID)
        persistSoon()
    }

    public func setTrackPan(_ pan: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].pan = min(max(pan, -1), 1)
        applyTrackMix(trackID: trackID)
        persistSoon()
    }

    public func setTrackReverbMix(_ mix: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].reverbMix = min(max(mix, 0), 100)
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    /// Aux reverb send (0…100). MIDI tracks route through the shared aux bus;
    /// audio tracks map to insert reverb mix for an audible approximation.
    public func setTrackReverbSend(_ mix: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let clamped = min(max(mix, 0), 100)
        project.tracks[index].reverbSend = clamped
        let track = project.tracks[index]
        if track.kind == .midi,
           let chain = instrumentChains[trackID],
           let aux = reverbAux,
           let graph {
            graph.setSend(clamped / 100, from: chain, to: aux)
        } else if track.kind == .audio {
            setTrackReverbMix(clamped, trackID: trackID)
        }
        persistSoon()
    }

    /// One-tap Reels Vocal: HPF + light comp + short room reverb.
    public func toggleReelsVocal(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let enabled = !project.tracks[index].reelsVocalEnabled
        project.tracks[index].reelsVocalEnabled = enabled
        if enabled {
            isHighPassEnabled = true
            project.tracks[index].reverbMix = max(project.tracks[index].reverbMix, 22)
        } else if project.tracks[index].reverbMix <= 25 {
            project.tracks[index].reverbMix = 0
        }
        applyHighPassToPlayers()
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    public func setTrackEQMidGain(_ gain: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].eqMidGain = min(max(gain, -12), 12)
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    public func setTrackDelay(mix: Float, time: Float? = nil, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].delayMix = min(max(mix, 0), 100)
        if let time {
            project.tracks[index].delayTime = min(max(time, 0.01), 1)
        }
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    public func setTrackDistortionMix(_ mix: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].distortionMix = min(max(mix, 0), 100)
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    // MARK: - Live MIDI instrument

    public func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        activeMIDIInstrument()?.noteOn(note, velocity: velocity)
    }

    public func noteOff(_ note: UInt8) {
        activeMIDIInstrument()?.noteOff(note)
    }

    public func allNotesOff() {
        activeMIDIInstrument()?.allNotesOff()
    }

    private func activeMIDIInstrument() -> (any MXInstrument)? {
        if let armed = armedTrack, armed.kind == .midi {
            return liveInstruments[armed.id]
        }
        if let firstMIDI = project.tracks.first(where: { $0.kind == .midi }) {
            return liveInstruments[firstMIDI.id]
        }
        return nil
    }

    @discardableResult
    private func ensureReverbAux(on graph: MXGraph) -> MXAuxBus {
        if let reverbAux { return reverbAux }
        let bus = graph.addAuxBus(name: "Reverb", effect: MXAUReverbEffect())
        bus.returnLevel = 0.7
        reverbAux = bus
        return bus
    }

    private func attachMIDIInstrument(for trackID: UUID, name: String) {
        guard let graph, phase == .ready else { return }
        guard project.tracks.first(where: { $0.id == trackID })?.kind == .midi else { return }
        guard instrumentChains[trackID] == nil else { return }

        let synth = MXSynthBackend(displayName: name, sampleRate: graph.sampleRate)
        liveInstruments[trackID] = synth
        let chain = graph.addTrack(name: name, instrument: synth)
        instrumentChains[trackID] = chain

        if let track = project.tracks.first(where: { $0.id == trackID }) {
            let aux = ensureReverbAux(on: graph)
            graph.setSend(track.reverbSend / 100, from: chain, to: aux)
        }
        syncLiveInstrumentMix()

        Task { [weak self] in
            try? await synth.load(.synthPreset(.synthwave1974))
            await MainActor.run {
                self?.syncLiveInstrumentMix()
            }
        }
    }

    private func detachLiveInstrument() {
        for instrument in liveInstruments.values {
            instrument.allNotesOff()
        }
        if let graph {
            for chain in instrumentChains.values {
                graph.removeTrack(id: chain.id)
            }
        }
        liveInstruments.removeAll()
        instrumentChains.removeAll()
        reverbAux = nil
    }

    public func seekByBars(_ delta: Int) {
        guard phase == .ready, !isRecording else { return }
        let targetBar = max(1, playheadBar + delta)
        seek(toBar: targetBar)
    }

    public func seek(toBar bar: Int) {
        guard let transport, phase == .ready, !isRecording else { return }
        let clamped = max(1, bar)
        let wasPlaying = transport.isPlaying
        if wasPlaying { pausePlayback() }
        transport.seek(toBar: clamped)
        let sample = transport.currentSample
        metronome?.prepareSchedule(fromSample: sample)
        metronome?.resetCursor(toSample: sample)
        refreshPlayheadFromTransport()
        if wasPlaying {
            beginPlayback(fromSample: sample, withCountIn: false)
        }
    }

    public func seek(toBeat beat: Double) {
        guard let transport, phase == .ready, !isRecording else { return }
        let wasPlaying = transport.isPlaying
        if wasPlaying { pausePlayback() }
        transport.seek(toBeat: max(0, beat))
        let sample = transport.currentSample
        metronome?.prepareSchedule(fromSample: sample)
        metronome?.resetCursor(toSample: sample)
        refreshPlayheadFromTransport()
        if wasPlaying {
            beginPlayback(fromSample: sample, withCountIn: false)
        }
    }

    public func setBPM(_ value: Double) {
        let clamped = min(max(value.rounded(), 40), 240)
        guard abs(clamped - bpm) > 0.01 else { return }
        bpm = clamped
        project.bpm = clamped
        transport?.tempoMap.setTempo(clamped)
        if let transport {
            let sample = transport.currentSample
            metronome?.prepareSchedule(fromSample: sample)
            metronome?.resetCursor(toSample: sample)
        }
        persistSoon()
    }

    public func nudgeBPM(_ delta: Double) {
        setBPM(bpm + delta)
    }

    public func persistNow() {
        do {
            try MXProjectStore.shared.save(project)
            lastSavedAt = .now
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Collab lite (Week 22)

    public var collabInviteURL: URL {
        URL(string: "mxstudio://collab/\(project.id.uuidString)")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("collab-link.txt")
    }

    public var collaboratorCount: Int {
        project.collaborators.count
    }

    @discardableResult
    public func addCollaborator(email: String, role: MXCollaboratorRole = .viewer) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else { return false }
        guard !project.collaborators.contains(where: { $0.email == trimmed }) else { return false }

        project.collaborators.append(MXCollaborator(email: trimmed, role: role))
        persistSoon()

        let inviter = MXAuthSession.shared.displayName ?? "Someone"
        MXNotificationStore.shared.notifyCollabInvite(
            inviterName: inviter,
            projectName: project.name,
            projectID: project.id
        )
        return true
    }

    public func removeCollaborator(id: UUID) {
        project.collaborators.removeAll { $0.id == id }
        persistSoon()
    }

    /// Bounce audible tracks to WAV + M4A (peak-normalized ~−1 dBFS).
    public func bounceMix(normalize: Bool = true) async throws -> StudioBounceExporter.Result {
        guard !isExporting else {
            throw StudioBounceExporter.BounceError.writeFailed("Export already in progress")
        }
        isExporting = true
        exportError = nil
        defer { isExporting = false }

        persistNow()
        let snapshot = project
        let audioDir = MXProjectStore.shared.audioDirectory(for: snapshot.id)
        let exportDir = MXProjectStore.shared.exportsDirectory(for: snapshot.id)

        let result = try await Task.detached(priority: .userInitiated) {
            try StudioBounceExporter.bounce(
                project: snapshot,
                audioDirectory: audioDir,
                outputDirectory: exportDir,
                normalize: normalize
            )
        }.value

        lastExportURLs = [result.wavURL, result.m4aURL]
        return result
    }

    public func audioURL(for clip: MXClip) -> URL? {
        guard let name = clip.audioFileName else { return nil }
        return MXProjectStore.shared.audioDirectory(for: project.id).appendingPathComponent(name)
    }

    // MARK: - Private transport

    private func beginPlayback(fromSample sample: Int64, withCountIn: Bool) {
        guard let transport else { return }
        countInTask?.cancel()
        metronome?.prepareSchedule(fromSample: sample)
        metronome?.resetCursor(toSample: sample)

        if withCountIn, countInBars > 0 {
            isCountingIn = true
            let beatsPerBar = Double(project.timeSignatureNumerator)
            let seconds = Double(countInBars) * beatsPerBar * 60.0 / max(bpm, 1)
            countInTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.isCountingIn = false
                }
            }
        } else {
            isCountingIn = false
        }

        transport.play(fromSample: sample)
        scheduleClipPlayers(fromSample: sample)
        isPlaying = true
    }

    private func pausePlayback() {
        countInTask?.cancel()
        countInTask = nil
        isCountingIn = false
        stopClipPlayers()
        transport?.stop()
        isPlaying = false
    }

    private func scheduleClipPlayers(fromSample sample: Int64) {
        guard let transport else { return }
        let anySolo = project.tracks.contains(where: \.isSolo)

        for track in project.tracks {
            if track.isMuted { continue }
            if anySolo && !track.isSolo { continue }

            for clip in track.clips {
                guard clipAudioIsPlayable(clip) else { continue }
                guard let player = clipPlayers[clip.id],
                      let url = audioURL(for: clip),
                      let file = try? AVAudioFile(forReading: url) else { continue }

                player.stop()
                player.volume = track.volume
                player.pan = track.pan

                let clipStart = transport.tempoMap.sample(forBeat: clip.startBeat, sampleRate: transport.sampleRate)
                let clipEnd = transport.tempoMap.sample(
                    forBeat: clip.startBeat + clip.lengthBeats,
                    sampleRate: transport.sampleRate
                )
                if sample >= clipEnd { continue }

                let fileStart = AVAudioFramePosition(
                    (clip.sourceOffsetSeconds * transport.sampleRate).rounded()
                )
                let maxFrames = AVAudioFrameCount(max(0, file.length - fileStart))
                let durationSeconds = clip.sourceDurationSeconds
                    ?? (Double(maxFrames) / max(transport.sampleRate, 1))
                var frameCount = AVAudioFrameCount(
                    min(Double(maxFrames), (durationSeconds * transport.sampleRate).rounded())
                )
                guard frameCount > 0 else { continue }

                if sample <= clipStart {
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: clipStart))
                    player.scheduleSegment(
                        file,
                        startingFrame: fileStart,
                        frameCount: frameCount,
                        at: at,
                        completionHandler: nil
                    )
                } else {
                    let intoClip = sample - clipStart
                    let startFrame = fileStart + AVAudioFramePosition(intoClip)
                    let remainingFile = AVAudioFrameCount(max(0, file.length - startFrame))
                    let remainingClip = AVAudioFrameCount(max(0, Int64(frameCount) - intoClip))
                    frameCount = min(remainingFile, remainingClip)
                    guard frameCount > 0 else { continue }
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: sample))
                    player.scheduleSegment(
                        file,
                        startingFrame: startFrame,
                        frameCount: frameCount,
                        at: at,
                        completionHandler: nil
                    )
                }
                player.play()
            }
        }
    }

    private func stopClipPlayers() {
        for player in clipPlayers.values {
            player.stop()
        }
    }

    private func attachPlayersForExistingClips() {
        for track in project.tracks {
            for clip in track.clips {
                _ = clipAudioIsPlayable(clip)
                attachPlayer(for: clip)
            }
        }
    }

    @discardableResult
    private func clipAudioIsPlayable(_ clip: MXClip) -> Bool {
        guard let name = clip.audioFileName else { return true }
        let url = MXProjectStore.shared.audioDirectory(for: project.id).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            noteMissingClipAudio(clipName: clip.name)
            return false
        }
        return true
    }

    private func noteMissingClipAudio(clipName: String) {
        let message = "Missing audio for “\(clipName)” — skipped playback."
        guard !clipLoadWarnings.contains(message) else { return }
        clipLoadWarnings.append(message)
    }

    public func dismissClipLoadWarnings() {
        clipLoadWarnings.removeAll()
    }

    private func attachPlayer(for clip: MXClip) {
        guard clipPlayers[clip.id] == nil, let graph else { return }
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let delay = AVAudioUnitDelay()
        let distortion = AVAudioUnitDistortion()
        let comp = Self.makeDynamicsProcessor()
        let reverb = AVAudioUnitReverb()
        configureEQ(eq, for: clip)
        configureDelay(delay, for: clip)
        configureDistortion(distortion, for: clip)
        configureComp(comp, for: clip)
        configureReverb(reverb, for: clip)
        // player → EQ → delay → distortion → dynamics → reverb → master
        graph.connectSourceThroughInsertsToMaster(
            source: player,
            inserts: [eq, delay, distortion, comp, reverb]
        )
        clipPlayers[clip.id] = player
        clipEQs[clip.id] = eq
        clipDelays[clip.id] = delay
        clipDistortions[clip.id] = distortion
        clipComps[clip.id] = comp
        clipReverbs[clip.id] = reverb
        if let trackID = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })?.id {
            applyTrackMix(trackID: trackID)
        }
    }

    private func detachPlayer(for id: UUID) {
        guard let graph else {
            clipPlayers.removeValue(forKey: id)
            clipEQs.removeValue(forKey: id)
            clipDelays.removeValue(forKey: id)
            clipDistortions.removeValue(forKey: id)
            clipComps.removeValue(forKey: id)
            clipReverbs.removeValue(forKey: id)
            return
        }
        let player = clipPlayers.removeValue(forKey: id)
        let eq = clipEQs.removeValue(forKey: id)
        let delay = clipDelays.removeValue(forKey: id)
        let distortion = clipDistortions.removeValue(forKey: id)
        let comp = clipComps.removeValue(forKey: id)
        let reverb = clipReverbs.removeValue(forKey: id)
        player?.stop()
        var inserts: [AVAudioNode] = []
        if let eq { inserts.append(eq) }
        if let delay { inserts.append(delay) }
        if let distortion { inserts.append(distortion) }
        if let comp { inserts.append(comp) }
        if let reverb { inserts.append(reverb) }
        if let player {
            if inserts.isEmpty {
                graph.disconnectSourceFromMaster(player)
            } else {
                graph.disconnectSourceThroughInsertsFromMaster(source: player, inserts: inserts)
            }
        }
    }

    private func detachAllClipPlayers() {
        let ids = Array(clipPlayers.keys)
        for id in ids {
            detachPlayer(for: id)
        }
        clipPlayers.removeAll()
        clipEQs.removeAll()
        clipDelays.removeAll()
        clipDistortions.removeAll()
        clipComps.removeAll()
        clipReverbs.removeAll()
    }

    private func rebuildPlayers(for project: MXProject) {
        detachAllClipPlayers()
        self.project = project
        attachPlayersForExistingClips()
        applyHighPassToPlayers()
        for track in project.tracks {
            applyTrackFX(trackID: track.id)
        }
    }

    private func configureHighPass(_ eq: AVAudioUnitEQ, for clip: MXClip? = nil) {
        configureEQ(eq, for: clip)
    }

    private func configureEQ(_ eq: AVAudioUnitEQ, for clip: MXClip? = nil) {
        let track = clip.flatMap { c in
            project.tracks.first(where: { $0.clips.contains(where: { $0.id == c.id }) })
        }
        let hpfOn = isHighPassEnabled || (track?.reelsVocalEnabled == true)
        let hpf = eq.bands[0]
        hpf.filterType = .highPass
        hpf.frequency = 100
        hpf.bandwidth = 0.5
        hpf.bypass = !hpfOn

        if eq.bands.count > 1 {
            let mid = eq.bands[1]
            mid.filterType = .parametric
            mid.frequency = 1_200
            mid.bandwidth = 1.0
            mid.gain = track?.eqMidGain ?? 0
            mid.bypass = abs(mid.gain) < 0.05
        }
        eq.globalGain = 0
    }

    private func configureDelay(_ delay: AVAudioUnitDelay, for clip: MXClip) {
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })
        delay.delayTime = TimeInterval(track?.delayTime ?? 0.25)
        delay.feedback = 35
        delay.lowPassCutoff = 12_000
        delay.wetDryMix = track?.delayMix ?? 0
    }

    private func configureDistortion(_ distortion: AVAudioUnitDistortion, for clip: MXClip) {
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })
        // Guitar gets a warmer grit; other presets keep the bit-brush texture.
        if preset == .guitar || track?.category == .guitar {
            distortion.loadFactoryPreset(.multiBrokenSpeaker)
            distortion.preGain = -3
        } else {
            distortion.loadFactoryPreset(.drumsBitBrush)
            distortion.preGain = -6
        }
        distortion.wetDryMix = track?.distortionMix ?? 0
    }

    private func configureComp(_ comp: AVAudioUnitEffect, for clip: MXClip) {
        let reels = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })?.reelsVocalEnabled == true
        let au = comp.audioUnit
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -18, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 5, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 2, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -40, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.01, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.15, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, reels ? 2 : 0, 0)
        comp.bypass = !reels
    }

    private static func makeDynamicsProcessor() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    private func configureReverb(_ reverb: AVAudioUnitReverb, for clip: MXClip) {
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })
        reverb.loadFactoryPreset(track?.reelsVocalEnabled == true ? .smallRoom : .mediumRoom)
        reverb.wetDryMix = track?.reverbMix ?? 0
    }

    private func applyHighPassToPlayers() {
        for (id, eq) in clipEQs {
            let clip = project.tracks.flatMap(\.clips).first(where: { $0.id == id })
            configureHighPass(eq, for: clip)
        }
    }

    private func applyTrackFX(trackID: UUID) {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return }
        for clip in track.clips {
            if let eq = clipEQs[clip.id] { configureEQ(eq, for: clip) }
            if let delay = clipDelays[clip.id] { configureDelay(delay, for: clip) }
            if let distortion = clipDistortions[clip.id] { configureDistortion(distortion, for: clip) }
            if let comp = clipComps[clip.id] { configureComp(comp, for: clip) }
            if let reverb = clipReverbs[clip.id] { configureReverb(reverb, for: clip) }
        }
    }

    private func applyTrackMix(trackID: UUID) {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return }
        let anySolo = project.tracks.contains(where: \.isSolo)
        for clip in track.clips {
            guard let player = clipPlayers[clip.id] else { continue }
            let audible = !track.isMuted && (!anySolo || track.isSolo)
            player.volume = audible ? track.volume : 0
            player.pan = track.pan
        }
        // Solo/mute changes should refresh all tracks' audible state
        if anySolo || track.isMuted {
            for other in project.tracks where other.id != trackID {
                let otherAudible = !other.isMuted && (!anySolo || other.isSolo)
                for clip in other.clips {
                    clipPlayers[clip.id]?.volume = otherAudible ? other.volume : 0
                }
            }
        }
        syncLiveInstrumentMix()
    }

    /// Keep live VI graph tracks aligned with their project track mixer state.
    private func syncLiveInstrumentMix() {
        let anySolo = project.tracks.contains(where: \.isSolo)
        for track in project.tracks where track.kind == .midi {
            guard let chain = instrumentChains[track.id] else { continue }
            let audible = !track.isMuted && (!anySolo || track.isSolo)
            chain.volume = audible ? track.volume : 0
            chain.pan = track.pan
            chain.isMuted = !audible
        }
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self, self.isRecording else { return }
                    let level = self.recorder?.inputLevel ?? 0
                    self.inputLevel = level
                    self.peakHoldLevel = max(self.peakHoldLevel * 0.995, level)
                    let clipping = level >= Self.clipThreshold
                    self.isInputClipping = clipping
                    if clipping {
                        self.showClipWarning = true
                        self.scheduleClipWarningClear()
                    }
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func scheduleClipWarningClear() {
        clipWarningClearTask?.cancel()
        clipWarningClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self?.showClipWarning = false
            }
        }
    }

    private func maybeShowQuietRoomTip() {
        if !UserDefaults.standard.bool(forKey: Self.quietRoomTipKey) {
            showQuietRoomTip = true
        }
    }

    private func applyPreferredMonitoring() {
        #if os(iOS)
        let hasHeadphones = Self.currentRouteHasHeadphones()
        // Guitar sessions prefer Monitor on with headphones (BandLab-style).
        if preset == .guitar && hasHeadphones {
            isMonitoringEnabled = true
        } else if !hasHeadphones {
            isMonitoringEnabled = false
        }
        #else
        isMonitoringEnabled = false
        #endif
        recorder?.isMonitoringEnabled = isMonitoringEnabled
    }

    private static func currentRouteHasHeadphones() -> Bool {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType)
        }
        #else
        return false
        #endif
    }

    private func refreshRouteTip() {
        #if os(iOS)
        let hasHeadphones = Self.currentRouteHasHeadphones()
        if hasHeadphones {
            headphoneTip = isMonitoringEnabled
                ? (preset == .guitar
                   ? "Monitoring on — hear yourself while you play."
                   : nil)
                : "Headphones connected — turn on Monitor to hear yourself (optional)."
        } else {
            if isMonitoringEnabled {
                isMonitoringEnabled = false
            }
            headphoneTip = "Monitoring stays off on speaker to avoid feedback."
        }
        #else
        headphoneTip = nil
        #endif
    }

    private func pushUndoSnapshot() {
        editStack.push(project)
        canUndo = editStack.canUndo
    }

    private func clip(_ id: UUID) -> MXClip? {
        for track in project.tracks {
            if let found = track.clips.first(where: { $0.id == id }) {
                return found
            }
        }
        return nil
    }

    private func locateClip(_ id: UUID) -> (trackIndex: Int, clipIndex: Int)? {
        for (ti, track) in project.tracks.enumerated() {
            if let ci = track.clips.firstIndex(where: { $0.id == id }) {
                return (ti, ci)
            }
        }
        return nil
    }

    private func replaceClip(_ clip: MXClip) {
        guard let loc = locateClip(clip.id) else { return }
        project.tracks[loc.trackIndex].clips[loc.clipIndex] = clip
    }

    private func requestMicPermission() async -> Bool {
        #if os(iOS)
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
        #else
        return true
        #endif
    }

    private func refreshPlayheadFromTransport() {
        guard let transport else { return }
        playheadBeat = transport.currentBeat
        let position = transport.currentPosition
        playheadLabel = position.description
        playheadBar = position.bar
        playheadBeatInBar = position.beat
        playheadTimeLabel = Self.formatTime(transport.currentSeconds)
    }

    private func applyPlayhead(_ readout: MXPlayheadObserver.Readout) {
        playheadBeat = readout.beat
        playheadLabel = readout.position.description
        playheadBar = readout.position.bar
        playheadBeatInBar = readout.position.beat
        playheadTimeLabel = Self.formatTime(readout.seconds)
    }

    private static func formatTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        let minutes = whole / 60
        let secs = whole % 60
        return String(format: "%02d:%02d.%d", minutes, secs, tenths)
    }

    private func handleAudioSessionEvent(_ event: MXAudioSession.Event) {
        switch event {
        case .interruptionBegan:
            wasPlayingBeforeInterruption = isPlaying && !isRecording
            if isRecording {
                stopRecordingAndCommit()
            } else if isPlaying {
                pausePlayback()
            }
            isInterrupted = true
        case .interruptionEnded(let shouldResume):
            isInterrupted = false
            if shouldResume, wasPlayingBeforeInterruption, phase == .ready {
                beginPlayback(fromSample: transport?.currentSample ?? 0, withCountIn: false)
            }
            wasPlayingBeforeInterruption = false
        case .routeChanged:
            applyPreferredMonitoring()
            refreshRouteTip()
            if let transport {
                metronome?.prepareSchedule(fromSample: transport.currentSample)
            }
        case .mediaServicesReset:
            let resume = (isPlaying || wasPlayingBeforeInterruption) && !isRecording
            shutdown()
            start()
            if resume, phase == .ready {
                beginPlayback(fromSample: 0, withCountIn: false)
            }
        }
    }

    private func persistSoon() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { self?.persistNow() }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}
