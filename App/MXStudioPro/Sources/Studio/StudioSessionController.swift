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
    /// Per-track playback peak 0…1 (post-volume estimate from player taps).
    public private(set) var trackPlaybackLevels: [UUID: Float] = [:]
    public private(set) var trackPlaybackPeakHolds: [UUID: Float] = [:]
    public private(set) var showClipWarning = false
    public private(set) var headphoneTip: String?
    /// First-record quiet-room checklist (GarageBand / BandLab-style onboarding).
    public private(set) var showQuietRoomTip = false
    /// Checklist row completion — indices match `QuietRoomChecklistItem.allCases`.
    public private(set) var quietRoomChecklistDone: Set<Int> = []
    /// Rows the user manually unchecked — auto-check will not re-insert these.
    private var quietRoomChecklistUserCleared: Set<Int> = []
    public private(set) var selectedClipID: UUID?
    public private(set) var canUndo = false
    public private(set) var canRedo = false
    public private(set) var playheadBeat: Double = 0
    public private(set) var playheadLabel: String = "001 Bar / 1 Beat"
    public private(set) var playheadBar: Int = 1
    public private(set) var playheadBeatInBar: Int = 1
    public private(set) var playheadTimeLabel: String = "00:00.0"
    public private(set) var bpm: Double = 120
    public private(set) var musicalKey: String = "Cmaj"
    /// Last BPM estimated from an imported audio file (Week 48). `nil` until a
    /// confident detect succeeds; not persisted.
    public private(set) var lastDetectedBPM: Double?

    /// Vocal “Cut rumble” — 100 Hz HPF on clip playback path. On by default.
    public var isHighPassEnabled: Bool = true {
        didSet { applyHighPassToPlayers() }
    }

    public var isMonitoringEnabled: Bool = false {
        didSet {
            // Sync topology (guitar wet vs vocal dry) before attaching monitor path.
            syncMonitorChain()
            recorder?.isMonitoringEnabled = isMonitoringEnabled
        }
    }

    /// Snap move/trim/loop edits to 16th-note grid. Session preference (not persisted).
    public var isSnapEnabled: Bool = true

    /// Snap MIDI note starts to 16ths when committing a pad/keys performance.
    /// Session preference (not persisted). Independent of arrange `isSnapEnabled`.
    public var isMIDIQuantizeEnabled: Bool = true
    /// GarageBand-style quantize strength 0…1 (blend original → grid). Default full snap.
    public var midiQuantizeStrength: Double = 1 {
        didSet { midiQuantizeStrength = min(1, max(0, midiQuantizeStrength)) }
    }
    /// Logic-style swing 0…1 applied to odd 16ths when quantizing. Default straight.
    public var midiQuantizeSwing: Double = 0 {
        didSet { midiQuantizeSwing = min(1, max(0, midiQuantizeSwing)) }
    }

    /// Prefer mono capture when recording on a vocal-category armed track.
    /// Session preference (not persisted). Guitar / import paths leave this unused.
    ///
    /// Hardware may still deliver stereo; `MXRecorder` asks
    /// `AVAudioSession.setPreferredInputNumberOfChannels(1)` and downmixes the
    /// write tap when needed.
    public var preferMonoVocalRecord: Bool = true

    /// Capture-before-Rec buffer in milliseconds (GarageBand-style pre-roll).
    /// Filled while record mode is armed; prepended when Rec starts. 0 = off.
    public var preRollMilliseconds: Double = 250 {
        didSet {
            let clamped = min(max(preRollMilliseconds, 0), 1_000)
            if clamped != preRollMilliseconds {
                preRollMilliseconds = clamped
                return
            }
            recorder?.preRollMilliseconds = clamped
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

    /// True while a latency calibration run is in flight.
    public private(set) var isCalibrating = false
    /// Last calibration failure message (does not block recording).
    public private(set) var calibrationError: String?
    /// Last successful measurement summary for the settings sheet, if any.
    public private(set) var lastCalibrationSummary: String?

    public var isMetronomeEnabled: Bool = true {
        didSet { metronome?.isEnabled = isMetronomeEnabled }
    }

    public var metronomeLevel: Float = 0.6 {
        didSet { metronome?.level = metronomeLevel }
    }

    public var countInBars: Int = 1

    public private(set) var graph: MXGraph?
    public private(set) var transport: MXTransport?

    /// True when the armed track is keys MIDI — drives Virtual Piano visibility.
    public var showsPianoKeyboard: Bool {
        armedTrack?.kind == .midi && armedTrack?.category == .keys
    }

    /// True when the armed track is drums — drives DrumPad surface visibility.
    public var showsDrumPads: Bool {
        armedTrack?.kind == .midi && armedTrack?.category == .drums
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
    private var playbackMeterTask: Task<Void, Never>?
    /// Updated from audio taps (may be off-main).
    nonisolated(unsafe) private var clipMeterPeaks: [UUID: Float] = [:]
    nonisolated(unsafe) private let clipMeterLock = NSLock()
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
    /// Beat where the current take began (punch-in or cold start). Used on commit.
    private var recordingStartBeat: Double?
    /// Sample where the current take began — pairs with `recordingStartBeat`.
    private var recordingStartSample: Int64?
    /// True when record started while transport was already playing (punch-in).
    private var isPunchInRecording = false
    /// Open MIDI note-ons captured while transport is playing (Piano Studio performance capture).
    private var pendingMIDINoteOns: [UInt8: (startBeat: Double, velocity: UInt8, trackID: UUID)] = [:]
    /// Completed MIDI notes waiting to be committed into a clip on stop/pause.
    private var pendingMIDINotes: [MXMIDINote] = []
    private var pendingMIDITrackID: UUID?
    private var editStack = StudioEditStack()
    private var clipWarningClearTask: Task<Void, Never>?
    /// Last playhead sample from the observer — used to detect loop wraps.
    private var lastObservedSample: Int64 = 0
    private static let quietRoomTipKey = "mxstudio.didShowQuietRoomTip"
    private static let quietRoomChecklistKey = "mxstudio.didShowQuietRoomChecklist"
    /// Linear amplitude ≈ −1 dBFS.
    private static let clipThreshold: Float = 0.891
    /// Mic-level checklist auto-check threshold (~−40 dBFS linear).
    private static let quietRoomMicLevelThreshold: Float = 0.01

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
        } else if preset == .drums, let existing = MXProjectStore.shared.loadLastOpened(), existing.preset == .drums {
            project = existing
        } else if preset == .drums {
            project = (try? MXProjectStore.shared.createDrumsProject()) ?? .untitledDrums()
        } else if preset == .quickRecord {
            // Fresh vocal project each Quick Recording — GarageBand Quick / BandLab capture.
            var quick = (try? MXProjectStore.shared.createVocalProject()) ?? .untitledVocal()
            quick.name = "Quick Recording"
            quick.presetRaw = StudioPreset.quickRecord.rawValue
            try? MXProjectStore.shared.save(quick)
            project = quick
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
            recorder.preRollMilliseconds = preRollMilliseconds

            try graph.start()

            self.audioSession = session
            self.graph = graph
            self.transport = transport
            self.metronome = metronome
            self.calibrator = calibrator
            self.recorder = recorder
            self.phase = .ready
            applyPreferredMonitoring()
            syncMonitorNoiseGate()
            refreshRouteTip()
            maybeShowQuietRoomTip()

            attachPlayersForExistingClips()
            applyHighPassToPlayers()
            ensureReverbAux(on: graph)
            for track in project.tracks where track.kind == .midi {
                attachMIDIInstrument(for: track.id, name: track.name)
            }
            syncTransportLoop()

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

            // Quick Recording: land on Record Vocal chrome immediately (Figma 96:58733).
            if preset == .quickRecord {
                enterRecordMode()
            }
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
        stopPlaybackMeterPolling()
        autosaveTask?.cancel()
        autosaveTask = nil
        if isRecording {
            _ = try? recorder?.stopRecording()
            isRecording = false
        }
        isPunchInRecording = false
        recordingStartBeat = nil
        recordingStartSample = nil
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
        canRedo = false
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
        zeroPlaybackMeters()
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
        commitMIDIPerformanceCapture()
        stopClipPlayers()
        transport?.stopAndReturn()
        transport?.seek(toSample: 0)
        metronome?.resetCursor(toSample: 0)
        metronome?.prepareSchedule(fromSample: 0)
        isPlaying = false
        stopPlaybackMeterPolling()
        zeroPlaybackMeters()
        playheadBeat = 0
        playheadBar = 1
        playheadBeatInBar = 1
        playheadLabel = "001 Bar / 1 Beat"
        playheadTimeLabel = "00:00.0"
    }

    /// Ensure playback strip meters poll while mixer is open during play.
    public func ensurePlaybackMetersRunning() {
        guard isPlaying else { return }
        startPlaybackMeterPolling()
    }

    // MARK: - Record

    public func enterRecordMode() {
        isRecordMode = true
        recordError = nil
        // Arm live input for Monitor + pre-roll ring even before Rec starts.
        recorder?.preRollMilliseconds = preRollMilliseconds
        recorder?.setLiveInputArmed(true)
        applyPreferredMonitoring()
        syncMonitorNoiseGate()
        startMeterPolling()
        refreshRouteTip()
        // Prefer showing the checklist when the user actually opens Record
        // (BandLab/GarageBand first-capture moment), not only on engine start.
        maybeShowQuietRoomTip()
        refreshQuietRoomAutoChecks()
    }

    public func exitRecordMode() {
        if isRecording {
            stopRecordingAndCommit()
        }
        isRecordMode = false
        inputLevel = 0
        meterTask?.cancel()
        meterTask = nil
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

        // Punch-in: if already playing, keep the playhead and backing clips —
        // do not rewind to 0 or pause. Cold start records from the current playhead.
        let wasPlaying = transport.isPlaying
        let punchSample = transport.currentSample
        let punchBeat = transport.tempoMap.beat(forSample: punchSample, sampleRate: transport.sampleRate)

        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let fileName = "take_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
        let url = audioDir.appendingPathComponent(fileName)

        do {
            let preferMono = preferMonoVocalRecord && (armedTrack?.category == .vocal)
            try recorder.startRecording(to: url, preferMono: preferMono)
            activeTakeURL = url
            isRecording = true
            isPunchInRecording = wasPlaying
            recordingStartBeat = punchBeat
            recordingStartSample = punchSample
            startMeterPolling()

            metronome?.prepareSchedule(fromSample: punchSample)
            metronome?.resetCursor(toSample: punchSample)

            if wasPlaying {
                // Immediate punch-in — no count-in; re-anchor as recording and keep clips audible.
                isCountingIn = false
                transport.record(fromSample: punchSample)
                scheduleClipPlayers(fromSample: punchSample)
            } else {
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
                // Cold Rec: still schedule other tracks so overdub demos hear FX beds
                // (BandLab / GarageBand overdub path).
                transport.record(fromSample: punchSample)
                scheduleClipPlayers(fromSample: punchSample)
            }
            isPlaying = true
            startPlaybackMeterPolling()
        } catch {
            isRecording = false
            isPunchInRecording = false
            recordingStartBeat = nil
            recordingStartSample = nil
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
            stopPlaybackMeterPolling()
            zeroPlaybackMeters()

            let punchBeat = recordingStartBeat
            let punchSample = recordingStartSample ?? take.startSample
            recordingStartBeat = nil
            recordingStartSample = nil
            isPunchInRecording = false

            guard take.frameCount > 0, let trackID = project.armedTrack?.id ?? project.tracks.first?.id else {
                try? FileManager.default.removeItem(at: take.url)
                activeTakeURL = nil
                isRecordMode = false
                meterTask?.cancel()
                meterTask = nil
                recorder.setLiveInputArmed(false)
                return
            }

            // Pre-roll frames were captured before Rec — shift clip earlier so timeline matches audio.
            // If punch is near 0, trim excess pre-roll that would fall before the project start.
            let preRollFrames = Int64(take.preRollFrames)
            let excessPreRoll = max(0, preRollFrames - punchSample)
            let usablePreRoll = preRollFrames - excessPreRoll
            let audioStartSample = max(0, punchSample - usablePreRoll)
            let sampleRate = max(transport.sampleRate, 1)
            let sourceOffsetSeconds = Double(excessPreRoll) / sampleRate
            let audibleFrames = max(0, Int64(take.frameCount) - excessPreRoll)
            let startBeat = transport.tempoMap.beat(forSample: audioStartSample, sampleRate: sampleRate)
            let endSample = audioStartSample + audibleFrames
            let endBeat = transport.tempoMap.beat(forSample: endSample, sampleRate: sampleRate)
            let lengthBeats = max(0.25, endBeat - startBeat)
            let durationSeconds = Double(audibleFrames) / sampleRate

            let trackClips = project.tracks.first(where: { $0.id == trackID })?.clips ?? []
            let nextTakeIndex = (trackClips.map(\.takeIndex).max() ?? -1) + 1
            let takeNumber = nextTakeIndex + 1
            let clip = MXClip(
                trackID: trackID,
                name: "Take \(takeNumber)",
                startBeat: startBeat,
                lengthBeats: lengthBeats,
                audioFileName: take.url.lastPathComponent,
                sourceOffsetSeconds: sourceOffsetSeconds,
                sourceDurationSeconds: durationSeconds,
                takeIndex: nextTakeIndex,
                isActive: true
            )

            pushUndoSnapshot()
            var committed = clip
            if let index = project.tracks.firstIndex(where: { $0.id == trackID }) {
                // Playlist / crossfade comps lite (Logic punch comps):
                // split overlapping ACTIVE takes into before/after, keep them
                // audible outside the punch, and apply ~12 ms overlapping
                // equal-power X-fades.
                applyPunchCompLite(punch: &committed, trackIndex: index, transport: transport)
                project.tracks[index].clips.append(committed)
            }

            attachPlayer(for: committed)
            applyHighPassToPlayers()
            selectedClipID = committed.id
            persistNow()
            activeTakeURL = nil
            // Return to Figma 95:85026 — Studio After Record
            isRecordMode = false
            meterTask?.cancel()
            meterTask = nil
            recorder.setLiveInputArmed(false)
            refreshPlayheadFromTransport()
            if peakHoldLevel >= Self.clipThreshold {
                showClipWarning = true
                scheduleClipWarningClear()
            }
        } catch {
            isRecording = false
            isPunchInRecording = false
            recordingStartBeat = nil
            recordingStartSample = nil
            inputLevel = 0
            recordError = error.localizedDescription
            activeTakeURL = nil
            isRecordMode = false
            meterTask?.cancel()
            meterTask = nil
            recorder.setLiveInputArmed(false)
        }
    }

    /// Split overlapping active takes around a punch clip with overlapping equal-power X-fades.
    private func applyPunchCompLite(punch: inout MXClip, trackIndex: Int, transport: MXTransport) {
        let punchStart = punch.startBeat
        let punchEnd = punch.startBeat + punch.lengthBeats
        let secondsBetween: (Double, Double) -> Double = { a, b in
            transport.tempoMap.seconds(forBeat: b) - transport.tempoMap.seconds(forBeat: a)
        }

        var afterPieces: [MXClip] = []
        for i in project.tracks[trackIndex].clips.indices {
            let sib = project.tracks[trackIndex].clips[i]
            guard sib.isActive, sib.overlaps(with: punch) else { continue }

            let source = MXCompRegionSplit.SourceClip(
                startBeat: sib.startBeat,
                lengthBeats: sib.lengthBeats,
                sourceOffsetSeconds: sib.sourceOffsetSeconds,
                sourceDurationSeconds: sib.sourceDurationSeconds,
                fadeInSeconds: sib.fadeInSeconds,
                fadeOutSeconds: sib.fadeOutSeconds
            )
            let result = MXCompRegionSplit.split(
                sibling: source,
                punchStartBeat: punchStart,
                punchEndBeat: punchEnd,
                secondsBetween: secondsBetween
            )

            if let before = result.before {
                var kept = sib
                kept.startBeat = before.startBeat
                kept.lengthBeats = before.lengthBeats
                kept.sourceOffsetSeconds = before.sourceOffsetSeconds
                kept.sourceDurationSeconds = before.sourceDurationSeconds
                kept.fadeInSeconds = before.fadeInSeconds
                kept.fadeOutSeconds = before.fadeOutSeconds
                kept.isActive = true
                project.tracks[trackIndex].clips[i] = kept
                // Interior punch: keep original as before; append after as a new piece.
                if let after = result.after {
                    afterPieces.append(Self.makeCompPiece(from: sib, piece: after))
                }
            } else if let after = result.after {
                // Punch at start (or tiny before discarded): shrink original to the
                // after piece — do not leave a full-length inactive ghost.
                var kept = sib
                kept.startBeat = after.startBeat
                kept.lengthBeats = after.lengthBeats
                kept.sourceOffsetSeconds = after.sourceOffsetSeconds
                kept.sourceDurationSeconds = after.sourceDurationSeconds
                kept.fadeInSeconds = after.fadeInSeconds
                kept.fadeOutSeconds = after.fadeOutSeconds
                kept.isActive = true
                project.tracks[trackIndex].clips[i] = kept
            } else if result.deactivateOriginal {
                // Whole-cover punch: keep original as an inactive alternate take.
                project.tracks[trackIndex].clips[i].isActive = false
            }

            punch.fadeInSeconds = max(punch.fadeInSeconds, result.punchFadeInSeconds)
            punch.fadeOutSeconds = max(punch.fadeOutSeconds, result.punchFadeOutSeconds)
        }

        if let dur = punch.sourceDurationSeconds {
            punch.fadeInSeconds = min(punch.fadeInSeconds, dur)
            punch.fadeOutSeconds = min(punch.fadeOutSeconds, dur)
        }

        for piece in afterPieces {
            project.tracks[trackIndex].clips.append(piece)
            attachPlayer(for: piece)
        }
    }

    private static func makeCompPiece(from sibling: MXClip, piece: MXCompRegionSplit.Piece) -> MXClip {
        var clip = sibling
        clip.id = UUID()
        clip.startBeat = piece.startBeat
        clip.lengthBeats = piece.lengthBeats
        clip.sourceOffsetSeconds = piece.sourceOffsetSeconds
        clip.sourceDurationSeconds = piece.sourceDurationSeconds
        clip.fadeInSeconds = piece.fadeInSeconds
        clip.fadeOutSeconds = piece.fadeOutSeconds
        clip.isActive = true
        // Same takeIndex — playlist lane of the original take.
        return clip
    }

    // MARK: - Track controls

    public static let maxTracks = 8

    public var canAddTrack: Bool { project.tracks.count < Self.maxTracks }

    public private(set) var trackLimitMessage: String?

    /// Transient banner after import tempo detect (Week 48+).
    public private(set) var tempoDetectMessage: String?

    public func dismissTrackLimitMessage() {
        trackLimitMessage = nil
    }

    public func dismissTempoDetectMessage() {
        tempoDetectMessage = nil
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
        let seed = MXGuitarPedalPreset.trackSeed
        let track = MXSessionTrack(
            name: trackName,
            kind: .audio,
            category: .guitar,
            isArmed: true,
            reverbMix: seed.reverbMix,
            eqMidGain: seed.eqMidGain,
            delayMix: seed.delayMix,
            delayTime: seed.delayTime,
            distortionMix: seed.distortionMix
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
        let keysIndex = project.tracks.filter { $0.category == .keys }.count + 1
        let trackName = name ?? (keysIndex == 1 ? "Piano" : "Piano \(keysIndex)")
        let track = MXSessionTrack(
            name: trackName,
            kind: .midi,
            category: .keys,
            isArmed: true,
            reverbMix: 14,
            reverbSend: 20,
            synthBankPresetID: MXSynthBankPreset.trackSeed.rawValue
        )
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

    /// Append a MIDI drums track with Drum Kit patch and arm it.
    @discardableResult
    public func addDrumTrack(named name: String? = nil) -> MXSessionTrack? {
        guard canAddTrack else {
            trackLimitMessage = "Track limit reached (\(Self.maxTracks))"
            return nil
        }
        let drumIndex = project.tracks.filter { $0.category == .drums }.count + 1
        let trackName = name ?? (drumIndex == 1 ? "Drums" : "Drums \(drumIndex)")
        let track = MXSessionTrack(
            name: trackName,
            kind: .midi,
            category: .drums,
            isArmed: true,
            reverbMix: 8,
            reverbSend: 12,
            synthBankPresetID: MXSynthBankPreset.drumKit.rawValue
        )
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
        syncMonitorNoiseGate()
        persistSoon()
    }

    func setTrackCategory(_ category: MXSessionTrack.Category, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].category = category
        syncMonitorNoiseGate()
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

        // Week 48 — estimate BPM before placing the clip so lengthBeats matches
        // the (possibly updated) project tempo. Failure is non-fatal.
        if let detected = Self.estimateImportBPM(from: destURL) {
            lastDetectedBPM = detected
            setBPM(detected)
            tempoDetectMessage = "Tempo set to \(Int(detected.rounded())) BPM from import"
        }

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

    /// Read mono PCM from an imported file and run `MXTempoDetect` (Week 48).
    /// Returns `nil` on I/O failure, silence, or low-confidence estimates.
    private static func estimateImportBPM(from url: URL, maxSeconds: Double = 20) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }

        let maxFrames = min(file.length, AVAudioFramePosition((maxSeconds * sampleRate).rounded()))
        guard maxFrames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(maxFrames)
              )
        else { return nil }

        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(maxFrames))
        } catch {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else { return nil }

        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frameCount)
        if channelCount <= 1 {
            for i in 0..<frameCount {
                mono[i] = channels[0][i]
            }
        } else {
            let scale = 1 / Float(channelCount)
            for i in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<channelCount {
                    sum += channels[c][i]
                }
                mono[i] = sum * scale
            }
        }

        return MXTempoDetect.estimateBPM(mono: mono, sampleRate: sampleRate)
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
        quietRoomChecklistDone.removeAll()
        quietRoomChecklistUserCleared.removeAll()
        UserDefaults.standard.set(true, forKey: Self.quietRoomTipKey)
        UserDefaults.standard.set(true, forKey: Self.quietRoomChecklistKey)
    }

    /// Toggle a quiet-room checklist row (user tap). Auto-checked rows can also be toggled off.
    public func toggleQuietRoomChecklistItem(_ item: QuietRoomChecklistItem) {
        if quietRoomChecklistDone.contains(item.rawValue) {
            quietRoomChecklistDone.remove(item.rawValue)
            quietRoomChecklistUserCleared.insert(item.rawValue)
        } else {
            quietRoomChecklistDone.insert(item.rawValue)
            quietRoomChecklistUserCleared.remove(item.rawValue)
        }
    }

    /// True when every quiet-room checklist row is marked done.
    public var isQuietRoomChecklistComplete: Bool {
        QuietRoomChecklistItem.allCases.allSatisfy { quietRoomChecklistDone.contains($0.rawValue) }
    }

    public func undo() {
        guard let previous = editStack.undo(current: project) else { return }
        let wasPlaying = transport?.isPlaying == true
        if wasPlaying { pausePlayback() }
        rebuildPlayers(for: previous)
        refreshAllDrumAudibleBeds()
        syncTransportLoop()
        canUndo = editStack.canUndo
        canRedo = editStack.canRedo
        selectedClipID = nil
        persistNow()
    }

    public func redo() {
        guard let next = editStack.redo(current: project) else { return }
        let wasPlaying = transport?.isPlaying == true
        if wasPlaying { pausePlayback() }
        rebuildPlayers(for: next)
        refreshAllDrumAudibleBeds()
        syncTransportLoop()
        canUndo = editStack.canUndo
        canRedo = editStack.canRedo
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

    /// Activate one take lane on its track (all pieces sharing `takeIndex`).
    /// Competing punch-comp siblings become inactive; sequential non-overlapping
    /// takes that only abut stay active (`MXTakeLaneActivation`).
    public func setActiveTake(clipID: UUID) {
        guard let loc = locateClip(clipID) else { return }
        pushUndoSnapshot()
        let trackClips = project.tracks[loc.trackIndex].clips
        let refs = trackClips.map {
            MXTakeLaneActivation.ClipRef(
                id: $0.id,
                takeIndex: $0.takeIndex,
                startBeat: $0.startBeat,
                lengthBeats: $0.lengthBeats
            )
        }
        let activeIDs = MXTakeLaneActivation.activeIDs(afterSelecting: clipID, clips: refs)
        for i in project.tracks[loc.trackIndex].clips.indices {
            project.tracks[loc.trackIndex].clips[i].isActive =
                activeIDs.contains(project.tracks[loc.trackIndex].clips[i].id)
        }
        selectedClipID = clipID
        persistNow()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    /// One representative clip per distinct `takeIndex` for take menus / playlist folders.
    /// Prefers an active piece when present; otherwise the earliest clip by `startBeat`. Sorted by takeIndex.
    public func takes(onTrackID trackID: UUID) -> [MXClip] {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return [] }
        let grouped = Dictionary(grouping: track.clips, by: \.takeIndex)
        return grouped.keys.sorted().compactMap { index in
            guard let clips = grouped[index], !clips.isEmpty else { return nil }
            if let active = clips.first(where: \.isActive) { return active }
            return clips.sorted { $0.startBeat < $1.startBeat }.first
        }
    }

    public func moveSelectedClip(byBeats delta: Double) {
        guard let id = selectedClipID, var clip = clip(id) else { return }
        pushUndoSnapshot()
        clip.startBeat = max(0, snapBeat(clip.startBeat + delta))
        replaceClip(clip)
        persistSoon()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    public func moveClip(id: UUID, toStartBeat newStart: Double) {
        guard var clip = clip(id) else { return }
        pushUndoSnapshot()
        clip.startBeat = max(0, snapBeat(newStart))
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
        let constrained = max(0, min(newStartBeat, rightEdge - 0.25))
        let snappedStart = snapBeat(constrained)
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
        let audible: Double
        if let dur = clip.sourceDurationSeconds {
            audible = dur
        } else {
            audible = clip.lengthBeats * 60.0 / max(project.bpm, 1)
        }
        let fades = MXClipFadeGeometry.meetInMiddle(
            fadeIn: clip.fadeInSeconds,
            fadeOut: clip.fadeOutSeconds,
            duration: audible
        )
        clip.fadeInSeconds = fades.fadeIn
        clip.fadeOutSeconds = fades.fadeOut
        clip.volumeAutomation = MXVolumeAutomation.clampingBeats(
            clip.volumeAutomation,
            lengthBeats: clip.lengthBeats
        )
        clip.panAutomation = MXPanAutomation.clampingBeats(
            clip.panAutomation,
            lengthBeats: clip.lengthBeats
        )
        replaceClip(clip)
        persistSoon()
        if transport.isPlaying {
            scheduleClipPlayers(fromSample: transport.currentSample)
        }
    }

    /// Trim right edge: `newEndBeat` on timeline; keeps left edge fixed.
    public func trimClipEnd(id: UUID, toEndBeat newEndBeat: Double) {
        guard var clip = clip(id), let transport else { return }
        let snappedEnd = max(clip.startBeat + 0.25, snapBeat(newEndBeat))
        let newLength = snappedEnd - clip.startBeat
        guard abs(newLength - clip.lengthBeats) > 1e-6 else { return }

        pushUndoSnapshot()
        clip.lengthBeats = newLength
        let startSec = transport.tempoMap.seconds(forBeat: clip.startBeat)
        let endSec = transport.tempoMap.seconds(forBeat: snappedEnd)
        let audible = max(0.05, endSec - startSec)
        clip.sourceDurationSeconds = audible
        let fades = MXClipFadeGeometry.meetInMiddle(
            fadeIn: clip.fadeInSeconds,
            fadeOut: clip.fadeOutSeconds,
            duration: audible
        )
        clip.fadeInSeconds = fades.fadeIn
        clip.fadeOutSeconds = fades.fadeOut
        clip.volumeAutomation = MXVolumeAutomation.clampingBeats(
            clip.volumeAutomation,
            lengthBeats: clip.lengthBeats
        )
        clip.panAutomation = MXPanAutomation.clampingBeats(
            clip.panAutomation,
            lengthBeats: clip.lengthBeats
        )
        replaceClip(clip)
        persistSoon()
        if transport.isPlaying {
            scheduleClipPlayers(fromSample: transport.currentSample)
        }
    }

    /// Snap to 16th-note grid when `isSnapEnabled`; otherwise pass through.
    private func snapBeat(_ beat: Double) -> Double {
        guard isSnapEnabled else { return beat }
        return MXMIDIQuantize.snapBeat(beat)
    }

    /// Clip gain in linear units (0.1…4). BandLab / GarageBand style clip volume.
    public func setClipGain(_ gain: Float, clipID: UUID) {
        guard var clip = clip(clipID) else { return }
        let clamped = min(max(gain, 0.1), 4)
        guard abs(clamped - clip.gain) > 1e-4 else { return }
        clip.gain = clamped
        replaceClip(clip)
        persistSoon()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        } else if let player = clipPlayers[clipID],
                  let track = project.tracks.first(where: { $0.id == clip.trackID }) {
            let auto = MXVolumeAutomation.value(atBeat: playheadBeat, points: track.volumeAutomation)
            let clipAuto = clip.volumeAutomationGain(atProjectBeat: playheadBeat)
            let panOffset = clip.panAutomationOffset(atProjectBeat: playheadBeat)
            player.volume = track.volume * clip.gain * auto * clipAuto
            player.pan = MXPanAutomation.combined(trackPan: track.pan, clipOffset: panOffset)
        }
    }

    /// Fade-in / fade-out in seconds (Logic / Ableton style clip fades).
    /// Meet-in-middle: when both sides would exceed audible length, the side being
    /// edited is preferred and the other shrinks.
    public func setClipFades(fadeInSeconds: Double?, fadeOutSeconds: Double?, clipID: UUID) {
        guard var clip = clip(clipID) else { return }
        let audible: Double
        if let duration = clip.sourceDurationSeconds {
            audible = duration
        } else if let transport {
            audible = transport.tempoMap.seconds(forBeat: clip.startBeat + clip.lengthBeats)
                - transport.tempoMap.seconds(forBeat: clip.startBeat)
        } else {
            audible = clip.lengthBeats * 60.0 / max(project.bpm, 1)
        }
        var nextIn = clip.fadeInSeconds
        var nextOut = clip.fadeOutSeconds
        var prefer: MXClipFadeGeometry.FadeEdge?
        if let fadeIn = fadeInSeconds {
            nextIn = max(0, fadeIn)
            prefer = .fadeIn
        }
        if let fadeOut = fadeOutSeconds {
            nextOut = max(0, fadeOut)
            prefer = fadeInSeconds != nil ? prefer : .fadeOut
        }
        // Both set in one call (e.g. inspector) → proportional shrink.
        if fadeInSeconds != nil, fadeOutSeconds != nil {
            prefer = nil
        }
        let fades = MXClipFadeGeometry.meetInMiddle(
            fadeIn: nextIn,
            fadeOut: nextOut,
            duration: max(0, audible),
            prefer: prefer
        )
        nextIn = fades.fadeIn
        nextOut = fades.fadeOut
        let changed =
            abs(nextIn - clip.fadeInSeconds) > 1e-4 || abs(nextOut - clip.fadeOutSeconds) > 1e-4
        guard changed else { return }
        pushUndoSnapshot()
        clip.fadeInSeconds = nextIn
        clip.fadeOutSeconds = nextOut
        replaceClip(clip)
        persistSoon()
        if transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    /// Toggle arrangement loop (engine `MXTransport.LoopRegion`).
    public func setLoopEnabled(_ enabled: Bool) {
        project.loopEnabled = enabled
        if enabled, project.loopEndBeat <= project.loopStartBeat + 0.24 {
            project.loopEndBeat = project.loopStartBeat + Double(project.timeSignatureNumerator) * 2
        }
        syncTransportLoop()
        persistSoon()
        if enabled, transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    public func setLoopRegion(startBeat: Double, endBeat: Double) {
        let start = max(0, snapBeat(startBeat))
        let end = max(start + 0.25, snapBeat(endBeat))
        project.loopStartBeat = start
        project.loopEndBeat = end
        syncTransportLoop()
        persistSoon()
        if project.loopEnabled, transport?.isPlaying == true, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    /// Set loop to the selected clip’s span, or one bar around the playhead.
    public func setLoopToSelectionOrBar() {
        if let id = selectedClipID, let clip = clip(id) {
            setLoopRegion(startBeat: clip.startBeat, endBeat: clip.startBeat + clip.lengthBeats)
        } else {
            let bar = Double(project.timeSignatureNumerator)
            let start = (playheadBeat / bar).rounded(.down) * bar
            setLoopRegion(startBeat: start, endBeat: start + bar)
        }
        setLoopEnabled(true)
    }

    private func syncTransportLoop() {
        guard let transport else { return }
        if project.loopEnabled {
            transport.loop = MXTransport.LoopRegion(
                startBeat: project.loopStartBeat,
                endBeat: project.loopEndBeat,
                isEnabled: true
            )
        } else {
            transport.loop = nil
        }
    }

    public func toggleMute(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].isMuted.toggle()
        applyTrackMix(trackID: trackID)
        persistSoon()
    }

    /// BandLab-style kit-part mute: silence Kick/Snare/Hats… without deleting notes.
    public func toggleDrumPartMute(trackID: UUID, part: MXDrumPart) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.tracks[index].category == .drums else { return }
        let key = part.rawValue
        if project.tracks[index].mutedDrumParts.contains(key) {
            project.tracks[index].mutedDrumParts.remove(key)
        } else {
            project.tracks[index].mutedDrumParts.insert(key)
        }
        refreshDrumAudibleBeds(trackID: trackID)
        persistSoon()
    }

    /// BandLab-style kit-part solo: when any parts are soloed, only those play.
    public func toggleDrumPartSolo(trackID: UUID, part: MXDrumPart) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.tracks[index].category == .drums else { return }
        let key = part.rawValue
        if project.tracks[index].soloedDrumParts.contains(key) {
            project.tracks[index].soloedDrumParts.remove(key)
        } else {
            project.tracks[index].soloedDrumParts.insert(key)
        }
        refreshDrumAudibleBeds(trackID: trackID)
        persistSoon()
    }

    public func isDrumPartMuted(trackID: UUID, part: MXDrumPart) -> Bool {
        project.tracks.first(where: { $0.id == trackID })?.isDrumPartMuted(part) ?? false
    }

    public func isDrumPartSoloed(trackID: UUID, part: MXDrumPart) -> Bool {
        project.tracks.first(where: { $0.id == trackID })?.isDrumPartSoloed(part) ?? false
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
        syncMonitorChain()
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

    /// One-tap Reels Vocal: HPF + light comp + short room reverb + light de-ess.
    public func toggleReelsVocal(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let enabled = !project.tracks[index].reelsVocalEnabled
        project.tracks[index].reelsVocalEnabled = enabled
        if enabled {
            isHighPassEnabled = true
            project.tracks[index].reverbMix = max(project.tracks[index].reverbMix, 22)
            project.tracks[index].deEsserEnabled = true
            project.tracks[index].deEsserAmount = max(project.tracks[index].deEsserAmount, 40)
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
        syncMonitorChain()
        persistSoon()
    }

    public func setTrackDelay(mix: Float, time: Float? = nil, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].delayMix = min(max(mix, 0), 100)
        if let time {
            project.tracks[index].delayTime = min(max(time, 0.01), 1)
        }
        applyTrackFX(trackID: trackID)
        syncMonitorChain()
        persistSoon()
    }

    public func setTrackDistortionMix(_ mix: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].distortionMix = min(max(mix, 0), 100)
        applyTrackFX(trackID: trackID)
        syncMonitorChain()
        persistSoon()
    }

    /// Apply a named guitar pedalboard preset (Figma Select Guitar Effect / BandLab amp path).
    public func applyGuitarPedalPreset(_ preset: MXGuitarPedalPreset, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let track = project.tracks[index]
        guard track.category == .guitar else { return }
        project.tracks[index].distortionMix = preset.distortionMix
        project.tracks[index].delayMix = preset.delayMix
        project.tracks[index].delayTime = preset.delayTime
        project.tracks[index].reverbMix = preset.reverbMix
        project.tracks[index].eqMidGain = preset.eqMidGain
        applyTrackFX(trackID: trackID)
        syncMonitorChain()
        persistSoon()
    }

    /// Which named preset (if any) matches the track's current Dist/Delay/Rev/Tone mixes.
    public func matchingGuitarPedalPreset(for trackID: UUID) -> MXGuitarPedalPreset? {
        guard let track = project.tracks.first(where: { $0.id == trackID }),
              track.category == .guitar
        else { return nil }
        return MXGuitarPedalPreset.allCases.first {
            $0.matches(
                distortionMix: track.distortionMix,
                delayMix: track.delayMix,
                delayTime: track.delayTime,
                reverbMix: track.reverbMix,
                eqMidGain: track.eqMidGain
            )
        }
    }

    public func setNoiseGateEnabled(_ enabled: Bool, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].noiseGateEnabled = enabled
        applyTrackFX(trackID: trackID)
        syncMonitorNoiseGate()
        persistSoon()
    }

    public func setNoiseGateThreshold(_ threshold: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].noiseGateThreshold = min(max(threshold, 0), 0.2)
        applyTrackFX(trackID: trackID)
        syncMonitorNoiseGate()
        persistSoon()
    }

    public func setDeEsserEnabled(_ enabled: Bool, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].deEsserEnabled = enabled
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    public func setDeEsserAmount(_ amount: Float, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[index].deEsserAmount = min(max(amount, 0), 100)
        applyTrackFX(trackID: trackID)
        persistSoon()
    }

    // MARK: - Latency calibration

    /// Applied round-trip latency in milliseconds (persisted via `MXLatencyCalibrator`).
    public var latencyCompensationMilliseconds: Double {
        if let calibrator {
            return calibrator.compensationMilliseconds
        }
        let sr = project.sampleRate > 0 ? project.sampleRate : 48_000
        return MXLatencyCalibrator.persistedCompensationMilliseconds(sampleRate: sr)
    }

    /// True when a non-zero compensation is stored (measured or restored).
    public var hasLatencyCompensation: Bool {
        if let calibrator {
            return calibrator.compensationFrames > 0
        }
        return MXLatencyCalibrator.persistedCompensationFrames > 0
    }

    /// Runs the engine calibrator (hardware loopback). Safe to call from UI —
    /// failures set `calibrationError` and never tear down the recorder.
    public func calibrateLatency() {
        guard !isCalibrating else { return }
        guard !isRecording else {
            calibrationError = "Stop recording before calibrating latency."
            return
        }
        guard let calibrator else {
            calibrationError = "Studio isn’t ready. Open Studio and try again."
            return
        }

        calibrationError = nil
        isCalibrating = true

        Task { @MainActor in
            defer { isCalibrating = false }
            do {
                // Pause playback so the chirp isn’t masked by project audio.
                if isPlaying { pausePlayback() }
                let measurement = try await calibrator.measure(runs: 3, source: .hardware)
                calibrator.apply(measurement)
                if measurement.isStable {
                    lastCalibrationSummary = String(
                        format: "%.1f ms · %d frames",
                        measurement.meanMilliseconds,
                        calibrator.compensationFrames
                    )
                    calibrationError = nil
                } else {
                    lastCalibrationSummary = String(
                        format: "%.1f ms · %d frames",
                        measurement.meanMilliseconds,
                        calibrator.compensationFrames
                    )
                    // Applied anyway — warn so the user can re-run if takes drift.
                    calibrationError = MXLatencyCalibrator.CalibrationError
                        .measurementUnstable(stdDev: measurement.standardDeviationFrames)
                        .errorDescription
                }
            } catch {
                // Leave previous compensation intact so recording still aligns.
                calibrationError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    public func dismissCalibrationError() {
        calibrationError = nil
    }

    // MARK: - Live MIDI instrument

    public func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        activeMIDIInstrument()?.noteOn(note, velocity: velocity)
        captureMIDINoteOn(note, velocity: velocity)
    }

    public func noteOff(_ note: UInt8) {
        activeMIDIInstrument()?.noteOff(note)
        captureMIDINoteOff(note)
    }

    /// Audition a kit hit without performance capture (step-sequencer cell preview).
    public func previewNote(_ note: UInt8, velocity: UInt8 = 100) {
        guard let instrument = activeMIDIInstrument() else { return }
        instrument.noteOn(note, velocity: velocity)
        // Hold briefly so the drum envelope can speak (immediate noteOff is silent).
        let held = note
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            instrument.noteOff(held)
        }
    }

    public func allNotesOff() {
        activeMIDIInstrument()?.allNotesOff()
        // Close any open capture notes at the current playhead.
        for note in Array(pendingMIDINoteOns.keys) {
            captureMIDINoteOff(note)
        }
    }

    /// Load a named synth bank preset onto a MIDI / keys track (Piano FX sheet).
    public func loadSynthBankPreset(_ bank: MXSynthBankPreset, trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.tracks[index].kind == .midi else { return }
        project.tracks[index].synthBankPresetID = bank.rawValue
        persistSoon()
        guard let synth = liveInstruments[trackID] else { return }
        Task {
            try? await synth.load(.synthPreset(bank.preset))
        }
    }

    public func synthBankPreset(for trackID: UUID) -> MXSynthBankPreset {
        guard let track = project.tracks.first(where: { $0.id == trackID }),
              let id = track.synthBankPresetID,
              let bank = MXSynthBankPreset(rawValue: id)
        else { return .trackSeed }
        return bank
    }

    private func activeMIDITrackID() -> UUID? {
        if let armed = armedTrack, armed.kind == .midi { return armed.id }
        return project.tracks.first(where: { $0.kind == .midi })?.id
    }

    private func activeMIDIInstrument() -> (any MXInstrument)? {
        if let id = activeMIDITrackID() {
            return liveInstruments[id]
        }
        return nil
    }

    /// While transport plays, keys performances are captured into a MIDI clip on stop/pause.
    private func captureMIDINoteOn(_ note: UInt8, velocity: UInt8) {
        guard isPlaying, !isRecording, let trackID = activeMIDITrackID() else { return }
        // Retrigger: close prior note of same pitch.
        if pendingMIDINoteOns[note] != nil {
            captureMIDINoteOff(note)
        }
        pendingMIDINoteOns[note] = (startBeat: playheadBeat, velocity: max(1, velocity), trackID: trackID)
        pendingMIDITrackID = trackID
    }

    private func captureMIDINoteOff(_ note: UInt8) {
        guard let open = pendingMIDINoteOns.removeValue(forKey: note) else { return }
        let endBeat = max(open.startBeat + 0.0625, playheadBeat)
        let length = endBeat - open.startBeat
        pendingMIDINotes.append(
            MXMIDINote(
                note: note,
                velocity: open.velocity,
                startBeat: open.startBeat,
                lengthBeats: length
            )
        )
        pendingMIDITrackID = open.trackID
    }

    /// Render captured notes to a WAV bed and place an `MXClip` on the MIDI track.
    private func commitMIDIPerformanceCapture() {
        // Close still-held notes at the current playhead before committing.
        for note in Array(pendingMIDINoteOns.keys) {
            captureMIDINoteOff(note)
        }
        var notes = pendingMIDINotes
        let trackID = pendingMIDITrackID
        pendingMIDINotes.removeAll()
        pendingMIDITrackID = nil
        pendingMIDINoteOns.removeAll()
        guard let trackID, !notes.isEmpty,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID })
        else { return }

        // Quantize absolute starts so the clip lands on the grid (GarageBand-style).
        if isMIDIQuantizeEnabled {
            notes = MXMIDIQuantize.quantizeStarts(
                notes,
                strength: midiQuantizeStrength,
                swing: midiQuantizeSwing
            )
        }

        let startBeat = notes.map(\.startBeat).min() ?? 0
        let endBeat = notes.map(\.endBeat).max() ?? startBeat
        // Shift notes so the clip-local timeline starts at 0.
        let localNotes = notes.map {
            MXMIDINote(
                id: $0.id,
                note: $0.note,
                velocity: $0.velocity,
                startBeat: max(0, $0.startBeat - startBeat),
                lengthBeats: $0.lengthBeats
            )
        }
        let lengthBeats = max(0.25, endBeat - startBeat)
        let bank = synthBankPreset(for: trackID)
        let isDrums = project.tracks[trackIndex].category == .drums
        let mutedParts = isDrums ? project.tracks[trackIndex].mutedDrumPartSet : []
        let soloedParts = isDrums ? project.tracks[trackIndex].soloedDrumPartSet : []
        let audibleNotes = isDrums
            ? localNotes.audibleDrumNotes(muted: mutedParts, soloed: soloedParts)
            : localNotes
        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        let filePrefix = isDrums ? "drums" : "keys"
        let fileName = "\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
        let url = audioDir.appendingPathComponent(fileName)
        do {
            try renderMIDIAudibleBed(
                notes: audibleNotes,
                to: url,
                preset: bank.preset,
                lengthBeats: lengthBeats
            )
        } catch {
            let label = isDrums ? "Drums" : "Keys"
            recordError = "\(label) capture failed: \(error.localizedDescription)"
            return
        }

        pushUndoSnapshot()
        let clipLabel = isDrums ? "Drums" : "Keys"
        let clip = MXClip(
            trackID: trackID,
            name: "\(clipLabel) \(project.tracks[trackIndex].clips.count + 1)",
            startBeat: startBeat,
            lengthBeats: lengthBeats,
            audioFileName: fileName,
            sourceDurationSeconds: lengthBeats * 60.0 / max(bpm, 1),
            midiNotes: localNotes
        )
        project.tracks[trackIndex].clips.append(clip)
        attachPlayer(for: clip)
        selectedClipID = clip.id
        persistSoon()
    }

    /// Place a BandLab-style step-sequencer pattern as a MIDI clip on the armed drums track.
    ///
    /// Notes are clip-local (bar starts at 0). The clip is anchored at `playheadBeat`
    /// (snapped when arrange snap is on). Empty grids are no-ops.
    /// After a successful place, the playhead advances by the pattern length (BandLab).
    @discardableResult
    public func commitDrumStepPattern(_ velocityGrid: [[UInt8]], bars: Int = 1) -> UUID? {
        let barCount = MXDrumStepSequencer.clampBars(bars)
        guard MXDrumStepSequencer.hasHits(velocityGrid) else { return nil }
        let trackID = activeMIDITrackID()
            ?? project.tracks.first(where: { $0.category == .drums })?.id
        guard let trackID,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              project.tracks[trackIndex].kind == .midi,
              project.tracks[trackIndex].category == .drums
        else {
            recordError = "Arm a Drums track to place a step pattern."
            return nil
        }

        let localNotes = MXDrumStepSequencer.notes(fromVelocityGrid: velocityGrid, bars: barCount)
        guard !localNotes.isEmpty else { return nil }

        let lengthBeats = MXDrumStepSequencer.patternLengthBeats(bars: barCount)
        let startBeat = snapBeat(playheadBeat)
        let bank = synthBankPreset(for: trackID)
        let mutedParts = project.tracks[trackIndex].mutedDrumPartSet
        let soloedParts = project.tracks[trackIndex].soloedDrumPartSet
        let audibleNotes = localNotes.audibleDrumNotes(muted: mutedParts, soloed: soloedParts)
        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        let fileName = "drums_steps_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
        let url = audioDir.appendingPathComponent(fileName)
        do {
            try renderMIDIAudibleBed(
                notes: audibleNotes,
                to: url,
                preset: bank.preset,
                lengthBeats: lengthBeats
            )
        } catch {
            recordError = "Step pattern failed: \(error.localizedDescription)"
            return nil
        }

        pushUndoSnapshot()
        let clip = MXClip(
            trackID: trackID,
            name: "Steps \(project.tracks[trackIndex].clips.count + 1)",
            startBeat: startBeat,
            lengthBeats: lengthBeats,
            audioFileName: fileName,
            sourceDurationSeconds: lengthBeats * 60.0 / max(bpm, 1),
            midiNotes: localNotes
        )
        project.tracks[trackIndex].clips.append(clip)
        attachPlayer(for: clip)
        selectedClipID = clip.id
        persistSoon()
        // Advance playhead so the next Add doesn't stack on the same beat.
        seek(toBeat: startBeat + lengthBeats)
        return clip.id
    }

    /// Week 49 boolean-grid overload.
    @discardableResult
    public func commitDrumStepPattern(_ grid: [[Bool]]) -> UUID? {
        commitDrumStepPattern(
            MXDrumStepSequencer.velocityGrid(fromBool: grid),
            bars: 1
        )
    }

    /// Load the selected drums MIDI clip into a velocity grid + bar count (Week 53).
    /// Returns `nil` when nothing suitable is selected.
    public func loadDrumStepPatternFromSelectedClip() -> (grid: [[UInt8]], bars: Int)? {
        guard let id = selectedClipID, let clip = clip(id) else { return nil }
        guard !clip.midiNotes.isEmpty else { return nil }
        guard let track = project.tracks.first(where: { $0.id == clip.trackID }),
              track.kind == .midi,
              track.category == .drums
        else { return nil }
        // Prefer clip length so sparse hits in a long clip keep trailing empty bars.
        let fromLength = Int(ceil(max(clip.lengthBeats, 0.25) / 4.0))
        let fromNotes = MXDrumStepSequencer.inferredBarCount(from: clip.midiNotes)
        let bars = MXDrumStepSequencer.clampBars(max(fromLength, fromNotes))
        let grid = MXDrumStepSequencer.velocityGrid(from: clip.midiNotes, bars: bars)
        guard MXDrumStepSequencer.hasHits(grid) else { return nil }
        return (grid, bars)
    }

    /// Whether the selected clip can feed the drum step sequencer.
    public var canLoadDrumStepPatternFromSelectedClip: Bool {
        loadDrumStepPatternFromSelectedClip() != nil
    }

    /// Re-apply capture quantize settings to the selected MIDI clip (Logic Quantize).
    /// Updates `midiNotes`, re-renders the audible WAV bed, and keeps length/start.
    @discardableResult
    public func requantizeSelectedMIDIClip() -> Bool {
        guard let id = selectedClipID, var clip = clip(id) else { return false }
        guard !clip.midiNotes.isEmpty else { return false }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == clip.trackID }),
              project.tracks[trackIndex].kind == .midi
        else { return false }

        let quantized = MXMIDIQuantize.quantizeStarts(
            clip.midiNotes,
            strength: midiQuantizeStrength,
            swing: midiQuantizeSwing
        )
        let identical = zip(clip.midiNotes, quantized).allSatisfy {
            abs($0.startBeat - $1.startBeat) < 1e-9
                && abs($0.lengthBeats - $1.lengthBeats) < 1e-9
        }
        guard !identical else { return false }

        pushUndoSnapshot()
        clip.midiNotes = quantized
        // Expand length if swing pushes a note past the clip end.
        let endBeat = quantized.map(\.endBeat).max() ?? clip.lengthBeats
        if endBeat > clip.lengthBeats {
            clip.lengthBeats = endBeat
            clip.sourceDurationSeconds = endBeat * 60.0 / max(bpm, 1)
        }

        let bank = synthBankPreset(for: clip.trackID)
        let isDrums = project.tracks[trackIndex].category == .drums
        let audible: [MXMIDINote]
        if isDrums {
            audible = quantized.audibleDrumNotes(
                muted: project.tracks[trackIndex].mutedDrumPartSet,
                soloed: project.tracks[trackIndex].soloedDrumPartSet
            )
        } else {
            audible = quantized
        }

        let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
        let prefix = isDrums ? "drums" : "keys"
        let fileName = "\(prefix)_q_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
        let url = audioDir.appendingPathComponent(fileName)
        do {
            stopClipPlayers()
            try renderMIDIAudibleBed(
                notes: audible,
                to: url,
                preset: bank.preset,
                lengthBeats: clip.lengthBeats
            )
            clip.audioFileName = fileName
        } catch {
            recordError = "Quantize failed: \(error.localizedDescription)"
            return false
        }

        replaceClip(clip)
        attachPlayer(for: clip)
        persistSoon()
        if isPlaying, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
        return true
    }

    /// Rewrite selected MIDI clip notes and re-render the audible bed (Week 55).
    @discardableResult
    public func updateMIDINote(
        id noteID: UUID,
        startBeat: Double,
        pitch: UInt8,
        renderBed: Bool = true,
        recordUndo: Bool = true
    ) -> Bool {
        guard var clip = selectedMIDIClip() else { return false }
        guard let existing = clip.midiNotes.first(where: { $0.id == noteID }) else { return false }
        let updated = MXMIDINoteEdit.moving(
            existing,
            startBeat: startBeat,
            pitch: pitch,
            clipLengthBeats: clip.lengthBeats
        )
        let next = MXMIDINoteEdit.replacing(
            clip.midiNotes,
            id: noteID,
            with: updated,
            clipLengthBeats: clip.lengthBeats
        )
        return commitMIDINotes(next, for: &clip, renderBed: renderBed, recordUndo: recordUndo)
    }

    @discardableResult
    public func addMIDINote(startBeat: Double, pitch: UInt8) -> Bool {
        guard var clip = selectedMIDIClip() else { return false }
        let note = MXMIDINoteEdit.making(
            pitch: pitch,
            startBeat: startBeat,
            clipLengthBeats: clip.lengthBeats
        )
        let next = MXMIDINoteEdit.appending(clip.midiNotes, note: note, clipLengthBeats: clip.lengthBeats)
        return commitMIDINotes(next, for: &clip, renderBed: true, recordUndo: true)
    }

    @discardableResult
    public func deleteMIDINote(id noteID: UUID) -> Bool {
        guard var clip = selectedMIDIClip() else { return false }
        guard clip.midiNotes.contains(where: { $0.id == noteID }) else { return false }
        let next = MXMIDINoteEdit.removing(clip.midiNotes, id: noteID)
        return commitMIDINotes(next, for: &clip, renderBed: true, recordUndo: true)
    }

    /// Force re-render of the selected MIDI clip bed after a drag gesture ends.
    @discardableResult
    public func commitSelectedMIDIClipBed() -> Bool {
        guard var clip = selectedMIDIClip() else { return false }
        return commitMIDINotes(clip.midiNotes, for: &clip, renderBed: true, recordUndo: false)
    }

    private func selectedMIDIClip() -> MXClip? {
        guard let id = selectedClipID, let clip = clip(id) else { return nil }
        guard let track = project.tracks.first(where: { $0.id == clip.trackID }),
              track.kind == .midi
        else { return nil }
        return clip
    }

    @discardableResult
    private func commitMIDINotes(
        _ notes: [MXMIDINote],
        for clip: inout MXClip,
        renderBed: Bool,
        recordUndo: Bool
    ) -> Bool {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == clip.trackID }),
              project.tracks[trackIndex].kind == .midi
        else { return false }

        if recordUndo { pushUndoSnapshot() }
        clip.midiNotes = notes
        let endBeat = notes.map(\.endBeat).max() ?? 0
        if endBeat > clip.lengthBeats {
            clip.lengthBeats = endBeat
            clip.sourceDurationSeconds = endBeat * 60.0 / max(bpm, 1)
        }

        if renderBed {
            let bank = synthBankPreset(for: clip.trackID)
            let isDrums = project.tracks[trackIndex].category == .drums
            let audible: [MXMIDINote]
            if isDrums {
                audible = notes.audibleDrumNotes(
                    muted: project.tracks[trackIndex].mutedDrumPartSet,
                    soloed: project.tracks[trackIndex].soloedDrumPartSet
                )
            } else {
                audible = notes
            }

            let audioDir = MXProjectStore.shared.audioDirectory(for: project.id)
            let prefix = isDrums ? "drums" : "keys"
            let fileName = "\(prefix)_edit_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(8)).wav"
            let url = audioDir.appendingPathComponent(fileName)
            do {
                stopClipPlayers()
                try renderMIDIAudibleBed(
                    notes: audible,
                    to: url,
                    preset: bank.preset,
                    lengthBeats: clip.lengthBeats
                )
                clip.audioFileName = fileName
            } catch {
                recordError = "MIDI edit failed: \(error.localizedDescription)"
                return false
            }
        }

        replaceClip(clip)
        if renderBed {
            attachPlayer(for: clip)
        }
        persistSoon()
        if renderBed, isPlaying, let sample = transport?.currentSample {
            scheduleClipPlayers(fromSample: sample)
        }
        return true
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

        let bank = synthBankPreset(for: trackID)
        let synth = MXSynthBackend(displayName: bank.preset.name, sampleRate: graph.sampleRate)
        liveInstruments[trackID] = synth
        let chain = graph.addTrack(name: name, instrument: synth)
        instrumentChains[trackID] = chain
        // Post-fader peak on track mixer for live MIDI strip meters.
        installPlaybackMeterTap(on: chain.trackMixer, meterID: trackID)

        if let track = project.tracks.first(where: { $0.id == trackID }) {
            let aux = ensureReverbAux(on: graph)
            graph.setSend(track.reverbSend / 100, from: chain, to: aux)
        }
        syncLiveInstrumentMix()

        Task { [weak self] in
            try? await synth.load(.synthPreset(bank.preset))
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
            for (trackID, chain) in instrumentChains {
                chain.trackMixer.removeTap(onBus: 0)
                clearClipMeterPeak(trackID)
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

    /// Bounce audible tracks to WAV + M4A.
    /// - Parameters:
    ///   - normalize: When true, applies `loudnessMode` after mixing.
    ///   - loudnessMode: Peak normalize (~−1 dBFS) or Reels LUFS (~−14).
    public func bounceMix(
        normalize: Bool = true,
        loudnessMode: StudioBounceExporter.LoudnessMode = .peakNormalize
    ) async throws -> StudioBounceExporter.Result {
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
        let mode = loudnessMode

        let highPass = isHighPassEnabled
        let result = try await Task.detached(priority: .userInitiated) {
            try StudioBounceExporter.bounce(
                project: snapshot,
                audioDirectory: audioDir,
                outputDirectory: exportDir,
                normalize: normalize,
                loudnessMode: mode,
                highPassEnabled: highPass
            )
        }.value

        lastExportURLs = [result.wavURL, result.m4aURL]
        return result
    }

    /// Bounce each track to its own WAV + M4A stem set (ignores mute/solo).
    public func bounceStems(
        normalize: Bool = true,
        loudnessMode: StudioBounceExporter.LoudnessMode = .peakNormalize
    ) async throws -> StudioBounceExporter.StemsResult {
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
        let mode = loudnessMode
        let highPass = isHighPassEnabled

        let result = try await Task.detached(priority: .userInitiated) {
            try StudioBounceExporter.bounceStems(
                project: snapshot,
                audioDirectory: audioDir,
                outputDirectory: exportDir,
                normalize: normalize,
                loudnessMode: mode,
                highPassEnabled: highPass
            )
        }.value

        lastExportURLs = result.allURLs
        return result
    }

    public func audioURL(for clip: MXClip) -> URL? {
        guard let name = clip.audioFileName else { return nil }
        return MXProjectStore.shared.audioDirectory(for: project.id).appendingPathComponent(name)
    }

    /// Re-render drum clip WAV beds from full `midiNotes` with current part mutes applied.
    private func refreshDrumAudibleBeds(trackID: UUID) {
        guard let track = project.tracks.first(where: { $0.id == trackID }),
              track.category == .drums
        else { return }
        // Stop readers before overwriting WAVs (players may hold the file open).
        stopClipPlayers()
        let muted = track.mutedDrumPartSet
        let soloed = track.soloedDrumPartSet
        let bank = synthBankPreset(for: trackID)
        let rate = transport?.sampleRate ?? 48_000
        for clip in track.clips where !clip.midiNotes.isEmpty {
            guard let url = audioURL(for: clip) else { continue }
            let audible = clip.midiNotes.audibleDrumNotes(muted: muted, soloed: soloed)
            do {
                try renderMIDIAudibleBed(
                    notes: audible,
                    to: url,
                    preset: bank.preset,
                    lengthBeats: clip.lengthBeats,
                    sampleRate: rate
                )
            } catch {
                recordError = "Drum part mute failed: \(error.localizedDescription)"
            }
        }
        if let sample = transport?.currentSample, isPlaying {
            scheduleClipPlayers(fromSample: sample)
        }
    }

    /// Re-sync every drums track bed after undo/redo restores mute state vs disk WAV.
    private func refreshAllDrumAudibleBeds() {
        for track in project.tracks where track.category == .drums {
            refreshDrumAudibleBeds(trackID: track.id)
        }
    }

    private func renderMIDIAudibleBed(
        notes: [MXMIDINote],
        to url: URL,
        preset: MXSynthPreset,
        lengthBeats: Double,
        sampleRate: Double? = nil
    ) throws {
        let rate = sampleRate ?? transport?.sampleRate ?? 48_000
        if notes.isEmpty {
            let duration = max(0.05, lengthBeats * 60.0 / max(bpm, 1) + 0.15)
            try MXMIDIClipRenderer.writeSilenceWAV(
                durationSeconds: duration,
                to: url,
                sampleRate: rate
            )
        } else {
            try MXMIDIClipRenderer.writeWAV(
                notes: notes,
                to: url,
                preset: preset,
                bpm: bpm,
                sampleRate: rate
            )
        }
    }

    // MARK: - Private transport

    private func beginPlayback(fromSample sample: Int64, withCountIn: Bool) {
        guard let transport else { return }
        syncTransportLoop()
        countInTask?.cancel()
        metronome?.prepareSchedule(fromSample: sample)
        metronome?.resetCursor(toSample: sample)
        lastObservedSample = sample

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
        startPlaybackMeterPolling()
    }

    private func pausePlayback() {
        countInTask?.cancel()
        countInTask = nil
        isCountingIn = false
        commitMIDIPerformanceCapture()
        stopClipPlayers()
        transport?.stop()
        isPlaying = false
        stopPlaybackMeterPolling()
        zeroPlaybackMeters()
    }

    private func scheduleClipPlayers(fromSample sample: Int64) {
        guard let transport else { return }
        // Stop every player first so deactivated takes do not keep sounding.
        stopClipPlayers()
        let anySolo = project.tracks.contains(where: \.isSolo)
        let loopEnabled = project.loopEnabled
        let loopEndSample: Int64 = loopEnabled
            ? transport.tempoMap.sample(forBeat: project.loopEndBeat, sampleRate: transport.sampleRate)
            : Int64.max

        for track in project.tracks {
            if track.isMuted { continue }
            if anySolo && !track.isSolo { continue }

            for clip in track.clips {
                guard clip.isActive else { continue }
                guard clipAudioIsPlayable(clip) else { continue }
                guard let player = clipPlayers[clip.id],
                      let url = audioURL(for: clip),
                      let file = try? AVAudioFile(forReading: url) else { continue }

                let auto = MXVolumeAutomation.value(atBeat: playheadBeat, points: track.volumeAutomation)
                let clipAuto = clip.volumeAutomationGain(atProjectBeat: playheadBeat)
                let panOffset = clip.panAutomationOffset(atProjectBeat: playheadBeat)
                player.volume = track.volume * clip.gain * auto * clipAuto
                player.pan = MXPanAutomation.combined(trackPan: track.pan, clipOffset: panOffset)

                let clipStart = transport.tempoMap.sample(forBeat: clip.startBeat, sampleRate: transport.sampleRate)
                let clipEnd = transport.tempoMap.sample(
                    forBeat: clip.startBeat + clip.lengthBeats,
                    sampleRate: transport.sampleRate
                )
                if sample >= clipEnd { continue }
                // Skip clips that only exist past the loop end (would bleed on hostTime).
                if loopEnabled && clipStart >= loopEndSample { continue }

                let fileStart = AVAudioFramePosition(
                    (clip.sourceOffsetSeconds * transport.sampleRate).rounded()
                )
                let maxFrames = AVAudioFrameCount(max(0, file.length - fileStart))
                let durationSeconds = clip.sourceDurationSeconds
                    ?? (Double(maxFrames) / max(transport.sampleRate, 1))
                var frameCount = AVAudioFrameCount(
                    min(Double(maxFrames), (durationSeconds * transport.sampleRate).rounded())
                )
                // Cap the whole-clip schedule at loop end so fades bake correctly.
                let clippedFromStart = MXLoopScheduleClamp.clampFrameCount(
                    requestedFrames: Int64(frameCount),
                    audibleStartSample: clipStart,
                    loopEndSample: loopEndSample,
                    loopEnabled: loopEnabled
                )
                frameCount = AVAudioFrameCount(clippedFromStart)
                guard frameCount > 0 else { continue }

                let needsFade = clip.fadeInSeconds > 1e-3 || clip.fadeOutSeconds > 1e-3
                if needsFade {
                    scheduleFadedSegment(
                        player: player,
                        file: file,
                        clip: clip,
                        fileStart: fileStart,
                        frameCount: frameCount,
                        clipStart: clipStart,
                        fromSample: sample,
                        transport: transport
                    )
                } else if sample <= clipStart {
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: clipStart))
                    player.scheduleSegment(
                        file,
                        startingFrame: fileStart,
                        frameCount: frameCount,
                        at: at,
                        completionHandler: nil
                    )
                    player.play()
                } else {
                    let intoClip = sample - clipStart
                    let startFrame = fileStart + AVAudioFramePosition(intoClip)
                    let remainingFile = AVAudioFrameCount(max(0, file.length - startFrame))
                    let remainingClip = AVAudioFrameCount(max(0, Int64(frameCount) - intoClip))
                    frameCount = min(remainingFile, remainingClip)
                    // Mid-clip: also clamp from the current playhead to loop end.
                    let midClamped = MXLoopScheduleClamp.clampFrameCount(
                        requestedFrames: Int64(frameCount),
                        audibleStartSample: sample,
                        loopEndSample: loopEndSample,
                        loopEnabled: loopEnabled
                    )
                    frameCount = AVAudioFrameCount(midClamped)
                    guard frameCount > 0 else { continue }
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: sample))
                    player.scheduleSegment(
                        file,
                        startingFrame: startFrame,
                        frameCount: frameCount,
                        at: at,
                        completionHandler: nil
                    )
                    player.play()
                }
            }
        }
    }

    /// Bake clip fade envelope into a PCM buffer for live preview (Logic-style fades).
    private func scheduleFadedSegment(
        player: AVAudioPlayerNode,
        file: AVAudioFile,
        clip: MXClip,
        fileStart: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        clipStart: Int64,
        fromSample sample: Int64,
        transport: MXTransport
    ) {
        let format = file.processingFormat
        guard let full = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        file.framePosition = fileStart
        do {
            try file.read(into: full, frameCount: frameCount)
        } catch {
            return
        }
        let read = Int(full.frameLength)
        guard read > 0, let channels = full.floatChannelData else { return }
        let channelCount = Int(format.channelCount)
        let duration = Double(read) / max(transport.sampleRate, 1)

        for ch in 0..<channelCount {
            let data = channels[ch]
            for i in 0..<read {
                let env = clip.fadeEnvelope(atSeconds: Double(i) / max(transport.sampleRate, 1), durationSeconds: duration)
                data[i] *= env
            }
        }

        let intoClip = max(0, sample - clipStart)
        if intoClip >= Int64(read) { return }
        let remaining = AVAudioFrameCount(Int64(read) - intoClip)
        let scheduleAt = sample <= clipStart ? clipStart : sample
        let at = AVAudioTime(hostTime: transport.hostTime(forSample: scheduleAt))

        if intoClip == 0 {
            player.scheduleBuffer(full, at: at, options: [], completionHandler: nil)
        } else if let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remaining) {
            slice.frameLength = remaining
            guard let dst = slice.floatChannelData else { return }
            for ch in 0..<channelCount {
                let src = channels[ch].advanced(by: Int(intoClip))
                dst[ch].update(from: src, count: Int(remaining))
            }
            player.scheduleBuffer(slice, at: at, options: [], completionHandler: nil)
        } else {
            return
        }
        player.play()
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
        // 3 bands: HPF, mid parametric, de-esser peaking (~6.5 kHz).
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let delay = AVAudioUnitDelay()
        let distortion = AVAudioUnitDistortion()
        let reverb = AVAudioUnitReverb()
        configureEQ(eq, for: clip)
        configureDelay(delay, for: clip)
        configureDistortion(distortion, for: clip)
        configureReverb(reverb, for: clip)
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })
        // Gate on track category only so vocal lanes in a Guitar project keep Dyn chain.
        let isGuitar = track?.category == .guitar
        // Guitar pedalboard (Figma Select Guitar Effect): Dist → Delay → Rev.
        // Vocal / general: EQ → Delay → Dist → Dyn → Rev.
        let inserts: [AVAudioNode]
        if isGuitar {
            inserts = [eq, distortion, delay, reverb]
        } else {
            let comp = Self.makeDynamicsProcessor()
            configureComp(comp, for: clip)
            clipComps[clip.id] = comp
            inserts = [eq, delay, distortion, comp, reverb]
        }
        graph.connectSourceThroughInsertsToMaster(source: player, inserts: inserts)
        clipPlayers[clip.id] = player
        clipEQs[clip.id] = eq
        clipDelays[clip.id] = delay
        clipDistortions[clip.id] = distortion
        clipReverbs[clip.id] = reverb
        // Post-FX peak tap (last insert) for mixer strip meters.
        installPlaybackMeterTap(on: reverb, meterID: clip.id)
        if let trackID = track?.id {
            applyTrackMix(trackID: trackID)
        }
    }

    private func detachPlayer(for id: UUID) {
        guard let graph else {
            if let reverb = clipReverbs[id] {
                reverb.removeTap(onBus: 0)
            }
            clearClipMeterPeak(id)
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
        // Remove meter tap before disconnecting the chain.
        reverb?.removeTap(onBus: 0)
        clearClipMeterPeak(id)
        player?.stop()
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == id }) })
        let isGuitar = track?.category == .guitar
        var inserts: [AVAudioNode] = []
        if isGuitar {
            if let eq { inserts.append(eq) }
            if let distortion { inserts.append(distortion) }
            if let delay { inserts.append(delay) }
            if let reverb { inserts.append(reverb) }
        } else {
            if let eq { inserts.append(eq) }
            if let delay { inserts.append(delay) }
            if let distortion { inserts.append(distortion) }
            if let comp { inserts.append(comp) }
            if let reverb { inserts.append(reverb) }
        }
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
        if eq.bands.count > 2 {
            // BandLab / Logic-style vocal de-ess: narrow peaking cut around sibilance.
            let deEss = eq.bands[2]
            deEss.filterType = .parametric
            deEss.frequency = 6_500
            deEss.bandwidth = 0.7
            let amount = track?.deEsserAmount ?? 0
            let enabled = track?.deEsserEnabled == true && amount > 0.5
            deEss.gain = enabled ? -(amount / 100) * 12 : 0
            deEss.bypass = !enabled
        }
        eq.globalGain = 0
    }

    private func configureComp(_ comp: AVAudioUnitEffect, for clip: MXClip) {
        let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })
        let reels = track?.reelsVocalEnabled == true
        let gateOn = track?.noiseGateEnabled == true
        let au = comp.audioUnit
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -18, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 5, 0)
        // Soft expander when gate is on — quiets room between phrases on live playback.
        let linearThresh = max(track?.noiseGateThreshold ?? 0.02, 1e-6)
        let expansionThreshDB = max(-60, min(-10, 20 * log10(linearThresh)))
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, gateOn ? 10 : 2, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, gateOn ? expansionThreshDB : -40, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.01, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, gateOn ? 0.08 : 0.15, 0)
        AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, reels ? 2 : 0, 0)
        comp.bypass = !(reels || gateOn)
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
        // Guitar gets a warmer grit; other tracks keep the bit-brush texture.
        if track?.category == .guitar {
            distortion.loadFactoryPreset(.multiBrokenSpeaker)
            distortion.preGain = -3
        } else {
            distortion.loadFactoryPreset(.drumsBitBrush)
            distortion.preGain = -6
        }
        distortion.wetDryMix = track?.distortionMix ?? 0
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
        let autoGain = MXVolumeAutomation.value(atBeat: playheadBeat, points: track.volumeAutomation)
        for clip in track.clips {
            guard let player = clipPlayers[clip.id] else { continue }
            let audible = !track.isMuted && (!anySolo || track.isSolo)
            let clipAuto = clip.volumeAutomationGain(atProjectBeat: playheadBeat)
            let panOffset = clip.panAutomationOffset(atProjectBeat: playheadBeat)
            player.volume = audible ? track.volume * clip.gain * autoGain * clipAuto : 0
            player.pan = MXPanAutomation.combined(trackPan: track.pan, clipOffset: panOffset)
        }
        // Solo/mute changes should refresh all tracks' audible state
        if anySolo || track.isMuted {
            for other in project.tracks where other.id != trackID {
                let otherAudible = !other.isMuted && (!anySolo || other.isSolo)
                let otherAuto = MXVolumeAutomation.value(atBeat: playheadBeat, points: other.volumeAutomation)
                for clip in other.clips {
                    let clipAuto = clip.volumeAutomationGain(atProjectBeat: playheadBeat)
                    clipPlayers[clip.id]?.volume = otherAudible
                        ? other.volume * clip.gain * otherAuto * clipAuto
                        : 0
                    if let player = clipPlayers[clip.id] {
                        let panOffset = clip.panAutomationOffset(atProjectBeat: playheadBeat)
                        player.pan = MXPanAutomation.combined(trackPan: other.pan, clipOffset: panOffset)
                    }
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
            let autoGain = MXVolumeAutomation.value(atBeat: playheadBeat, points: track.volumeAutomation)
            chain.volume = audible ? track.volume * autoGain : 0
            chain.pan = track.pan
            chain.isMuted = !audible
        }
    }

    /// Apply volume automation at the playhead for every track (Logic-style live follow).
    private func applyVolumeAutomationAtPlayhead() {
        let anySolo = project.tracks.contains(where: \.isSolo)
        for track in project.tracks {
            let autoGain = MXVolumeAutomation.value(atBeat: playheadBeat, points: track.volumeAutomation)
            let audible = !track.isMuted && (!anySolo || track.isSolo)
            for clip in track.clips {
                guard let player = clipPlayers[clip.id] else { continue }
                let clipAuto = clip.volumeAutomationGain(atProjectBeat: playheadBeat)
                let panOffset = clip.panAutomationOffset(atProjectBeat: playheadBeat)
                player.volume = audible ? track.volume * clip.gain * autoGain * clipAuto : 0
                player.pan = MXPanAutomation.combined(trackPan: track.pan, clipOffset: panOffset)
            }
            if track.kind == .midi, let chain = instrumentChains[track.id] {
                chain.volume = audible ? track.volume * autoGain : 0
            }
        }
    }

    /// Upsert a volume automation breakpoint on a track (Week 52).
    public func upsertVolumeAutomation(trackID: UUID, beat: Double, value: Float) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        pushUndoSnapshot()
        project.tracks[index].volumeAutomation = MXVolumeAutomation.upserting(
            project.tracks[index].volumeAutomation,
            beat: beat,
            value: value
        )
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func moveVolumeAutomationPoint(trackID: UUID, pointID: UUID, beat: Double, value: Float) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        pushUndoSnapshot()
        project.tracks[index].volumeAutomation = MXVolumeAutomation.moving(
            project.tracks[index].volumeAutomation,
            id: pointID,
            beat: beat,
            value: value
        )
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func removeVolumeAutomationPoint(trackID: UUID, pointID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        pushUndoSnapshot()
        project.tracks[index].volumeAutomation = MXVolumeAutomation.removing(
            project.tracks[index].volumeAutomation,
            id: pointID
        )
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    /// Seed a unity hold curve when opening an empty automation lane.
    public func ensureDefaultVolumeAutomation(trackID: UUID) {
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard project.tracks[index].volumeAutomation.isEmpty else { return }
        pushUndoSnapshot()
        project.tracks[index].volumeAutomation = [
            MXAutomationPoint(beat: 0, value: 1),
            MXAutomationPoint(beat: 4, value: 1),
        ]
        persistSoon()
    }

    // MARK: - Clip-relative automation (Week 54)

    public func upsertClipVolumeAutomation(clipID: UUID, beat: Double, value: Float) {
        guard var clip = clip(clipID) else { return }
        let local = min(clip.lengthBeats, max(0, beat))
        pushUndoSnapshot()
        clip.volumeAutomation = MXVolumeAutomation.upserting(
            clip.volumeAutomation,
            beat: local,
            value: value
        )
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func moveClipVolumeAutomationPoint(clipID: UUID, pointID: UUID, beat: Double, value: Float) {
        guard var clip = clip(clipID) else { return }
        let local = min(clip.lengthBeats, max(0, beat))
        pushUndoSnapshot()
        clip.volumeAutomation = MXVolumeAutomation.moving(
            clip.volumeAutomation,
            id: pointID,
            beat: local,
            value: value
        )
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func removeClipVolumeAutomationPoint(clipID: UUID, pointID: UUID) {
        guard var clip = clip(clipID) else { return }
        pushUndoSnapshot()
        clip.volumeAutomation = MXVolumeAutomation.removing(clip.volumeAutomation, id: pointID)
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func upsertClipPanAutomation(clipID: UUID, beat: Double, value: Float) {
        guard var clip = clip(clipID) else { return }
        let local = min(clip.lengthBeats, max(0, beat))
        pushUndoSnapshot()
        clip.panAutomation = MXPanAutomation.upserting(
            clip.panAutomation,
            beat: local,
            value: value
        )
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func moveClipPanAutomationPoint(clipID: UUID, pointID: UUID, beat: Double, value: Float) {
        guard var clip = clip(clipID) else { return }
        let local = min(clip.lengthBeats, max(0, beat))
        pushUndoSnapshot()
        clip.panAutomation = MXPanAutomation.moving(
            clip.panAutomation,
            id: pointID,
            beat: local,
            value: value
        )
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func removeClipPanAutomationPoint(clipID: UUID, pointID: UUID) {
        guard var clip = clip(clipID) else { return }
        pushUndoSnapshot()
        clip.panAutomation = MXPanAutomation.removing(clip.panAutomation, id: pointID)
        replaceClip(clip)
        persistSoon()
        applyVolumeAutomationAtPlayhead()
    }

    public func ensureDefaultClipVolumeAutomation(clipID: UUID) {
        guard var clip = clip(clipID) else { return }
        guard clip.volumeAutomation.isEmpty else { return }
        pushUndoSnapshot()
        clip.volumeAutomation = [
            MXAutomationPoint(beat: 0, value: 1),
            MXAutomationPoint(beat: max(0.25, clip.lengthBeats), value: 1),
        ]
        replaceClip(clip)
        persistSoon()
    }

    public func ensureDefaultClipPanAutomation(clipID: UUID) {
        guard var clip = clip(clipID) else { return }
        guard clip.panAutomation.isEmpty else { return }
        pushUndoSnapshot()
        clip.panAutomation = [
            MXAutomationPoint(beat: 0, value: 0),
            MXAutomationPoint(beat: max(0.25, clip.lengthBeats), value: 0),
        ]
        replaceClip(clip)
        persistSoon()
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self, self.isRecording || self.isRecordMode else { return }
                    let level = self.recorder?.inputLevel ?? 0
                    self.inputLevel = level
                    self.peakHoldLevel = max(self.peakHoldLevel * 0.995, level)
                    let clipping = level >= Self.clipThreshold
                    self.isInputClipping = clipping
                    if clipping {
                        self.showClipWarning = true
                        self.scheduleClipWarningClear()
                    }
                    if self.showQuietRoomTip {
                        self.refreshQuietRoomAutoChecks()
                    }
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    // MARK: - Playback strip meters

    private func startPlaybackMeterPolling() {
        playbackMeterTask?.cancel()
        playbackMeterTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.pollPlaybackMeters()
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func stopPlaybackMeterPolling() {
        playbackMeterTask?.cancel()
        playbackMeterTask = nil
    }

    private func pollPlaybackMeters() {
        guard isPlaying else {
            zeroPlaybackMeters()
            return
        }
        let peaks = snapshotAndClearClipMeterPeaks()
        var levels = trackPlaybackLevels
        var holds = trackPlaybackPeakHolds
        for track in project.tracks {
            var raw: Float = 0
            for clip in track.clips {
                raw = max(raw, peaks[clip.id] ?? 0)
            }
            // Live MIDI instrument peaks are keyed by track id.
            if instrumentChains[track.id] != nil {
                raw = max(raw, peaks[track.id] ?? 0)
            }
            let previous = levels[track.id] ?? 0
            let level = max(raw, previous * 0.85)
            levels[track.id] = level
            holds[track.id] = max((holds[track.id] ?? 0) * 0.995, level)
        }
        // Drop stale track keys no longer in the project.
        let liveIDs = Set(project.tracks.map(\.id))
        levels = levels.filter { liveIDs.contains($0.key) }
        holds = holds.filter { liveIDs.contains($0.key) }
        trackPlaybackLevels = levels
        trackPlaybackPeakHolds = holds
    }

    private func zeroPlaybackMeters() {
        clearAllClipMeterPeaks()
        if !trackPlaybackLevels.isEmpty {
            trackPlaybackLevels = [:]
        }
        if !trackPlaybackPeakHolds.isEmpty {
            trackPlaybackPeakHolds = [:]
        }
    }

    private func installPlaybackMeterTap(on node: AVAudioNode, meterID: UUID) {
        // Avoid AVAudioEngine "tap already installed" if a prior detach was skipped.
        node.removeTap(onBus: 0)
        let format = node.outputFormat(forBus: 0)
        let tapFormat: AVAudioFormat? = format.sampleRate > 0 ? format : nil
        node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let peak = Self.peakLevel(in: buffer)
            self.storeClipMeterPeak(meterID, peak)
        }
    }

    nonisolated private func storeClipMeterPeak(_ id: UUID, _ peak: Float) {
        clipMeterLock.lock()
        clipMeterPeaks[id] = peak
        clipMeterLock.unlock()
    }

    nonisolated private func clearClipMeterPeak(_ id: UUID) {
        clipMeterLock.lock()
        clipMeterPeaks.removeValue(forKey: id)
        clipMeterLock.unlock()
    }

    nonisolated private func clearAllClipMeterPeaks() {
        clipMeterLock.lock()
        clipMeterPeaks.removeAll()
        clipMeterLock.unlock()
    }

    nonisolated private func snapshotAndClearClipMeterPeaks() -> [UUID: Float] {
        clipMeterLock.lock()
        defer { clipMeterLock.unlock() }
        let copy = clipMeterPeaks
        clipMeterPeaks.removeAll()
        return copy
    }

    /// Peak absolute sample across channels — same algorithm as `MXRecorder.peakLevel`.
    nonisolated private static func peakLevel(in buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var peak: Float = 0
        let channelCount = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            let data = channels[ch]
            for i in 0..<frames {
                peak = max(peak, abs(data[i]))
            }
        }
        return min(1, peak)
    }

    /// Push armed-track monitor chain: wet guitar pedalboard or dry vocal + optional gate.
    private func syncMonitorChain() {
        guard let recorder else { return }
        let track = armedTrack
        if let track, track.category == .guitar {
            recorder.monitorGuitarFX = MXMonitorGuitarFX.clamped(
                enabled: true,
                distortionMix: track.distortionMix,
                delayMix: track.delayMix,
                delayTime: track.delayTime,
                reverbMix: track.reverbMix,
                eqMidGain: track.eqMidGain
            )
            recorder.monitorGateEnabled = false
        } else {
            recorder.monitorGuitarFX = .disabled
            let vocalGate = track?.category == .vocal && track?.noiseGateEnabled == true
            recorder.monitorGateEnabled = vocalGate
            recorder.monitorGateThreshold = track?.noiseGateThreshold ?? 0.02
        }
    }

    /// Compatibility wrapper — prefer `syncMonitorChain()`.
    private func syncMonitorNoiseGate() {
        syncMonitorChain()
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
        // Quick Recording (GarageBand Quick): skip onboarding for minimal chrome.
        guard preset != .quickRecord else { return }
        // Week 29 checklist key — show once even if the Week 5 copy-only tip was seen.
        guard !UserDefaults.standard.bool(forKey: Self.quietRoomChecklistKey) else { return }
        showQuietRoomTip = true
        quietRoomChecklistDone.removeAll()
        quietRoomChecklistUserCleared.removeAll()
        refreshQuietRoomAutoChecks()
    }

    /// Auto-check headphones + mic-level rows from live route / meter (BandLab-style).
    /// Respects rows the user manually unchecked so the meter poll doesn’t fight taps.
    private func refreshQuietRoomAutoChecks() {
        guard showQuietRoomTip else { return }
        #if os(iOS)
        let headphones = QuietRoomChecklistItem.headphones.rawValue
        if Self.currentRouteHasHeadphones(), !quietRoomChecklistUserCleared.contains(headphones) {
            quietRoomChecklistDone.insert(headphones)
        }
        #endif
        let mic = QuietRoomChecklistItem.micLevel.rawValue
        if (inputLevel >= Self.quietRoomMicLevelThreshold || peakHoldLevel >= Self.quietRoomMicLevelThreshold),
           !quietRoomChecklistUserCleared.contains(mic) {
            quietRoomChecklistDone.insert(mic)
        }
    }

    private func applyPreferredMonitoring() {
        #if os(iOS)
        let hasHeadphones = Self.currentRouteHasHeadphones()
        // Guitar sessions prefer Monitor on with headphones (BandLab-style).
        if (preset == .guitar || armedTrack?.category == .guitar) && hasHeadphones {
            isMonitoringEnabled = true
        } else if !hasHeadphones {
            isMonitoringEnabled = false
        }
        #else
        isMonitoringEnabled = false
        #endif
        // Chain first so guitar wet / vocal dry is set before attach.
        syncMonitorChain()
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
        let isGuitar = preset == .guitar || armedTrack?.category == .guitar
        if hasHeadphones {
            if isGuitar {
                headphoneTip = isMonitoringEnabled
                    ? "Hearing pedalboard (Dist→Delay→Rev). DI records dry; FX on monitor & playback."
                    : "Headphones connected — turn on Monitor to hear your pedalboard / DI."
            } else {
                headphoneTip = isMonitoringEnabled
                    ? nil
                    : "Headphones connected — turn on Monitor to hear yourself (optional)."
            }
        } else {
            if isMonitoringEnabled {
                isMonitoringEnabled = false
            }
            headphoneTip = isGuitar
                ? "Speaker monitoring stays off (feedback). Plug in headphones for pedalboard / DI monitor."
                : "Monitoring stays off on speaker to avoid feedback."
        }
        #else
        headphoneTip = nil
        #endif
    }

    private func pushUndoSnapshot() {
        editStack.push(project)
        canUndo = editStack.canUndo
        canRedo = editStack.canRedo
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
        // Detect loop wrap: playhead jumped backward while playing with loop on.
        if project.loopEnabled,
           readout.state == .playing || readout.state == .recording,
           lastObservedSample > 0,
           readout.sample < lastObservedSample {
            let loopLengthSamples: Int64
            if let transport {
                let start = transport.tempoMap.sample(forBeat: project.loopStartBeat, sampleRate: transport.sampleRate)
                let end = transport.tempoMap.sample(forBeat: project.loopEndBeat, sampleRate: transport.sampleRate)
                loopLengthSamples = max(1, end - start)
            } else {
                loopLengthSamples = 1
            }
            // Ignore tiny backward jitter. Use a small sample floor so short loops
            // (e.g. ~0.25 beat) still reschedule — a half-loop threshold missed those.
            let jump = lastObservedSample - readout.sample
            let wrapFloor = Int64(max(64, min(256, loopLengthSamples / 8)))
            if jump >= wrapFloor {
                // Punch-out at loop end: commit the take instead of wrapping while recording.
                if isRecording {
                    lastObservedSample = readout.sample
                    playheadBeat = readout.beat
                    playheadLabel = readout.position.description
                    playheadBar = readout.position.bar
                    playheadBeatInBar = readout.position.beat
                    playheadTimeLabel = Self.formatTime(readout.seconds)
                    stopRecordingAndCommit()
                    return
                }
                // Re-anchor host clock so scheduled hostTimes are in the future.
                transport?.seek(toSample: readout.sample)
                metronome?.resetCursor(toSample: readout.sample)
                scheduleClipPlayers(fromSample: readout.sample)
            }
        }
        lastObservedSample = readout.sample
        playheadBeat = readout.beat
        playheadLabel = readout.position.description
        playheadBar = readout.position.bar
        playheadBeatInBar = readout.position.beat
        playheadTimeLabel = Self.formatTime(readout.seconds)
        if project.tracks.contains(where: { track in
            !track.volumeAutomation.isEmpty
                || track.clips.contains(where: {
                    !$0.volumeAutomation.isEmpty || !$0.panAutomation.isEmpty
                })
        }) {
            applyVolumeAutomationAtPlayhead()
        }
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
