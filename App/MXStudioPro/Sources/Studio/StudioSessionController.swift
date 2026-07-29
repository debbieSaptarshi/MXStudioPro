import AVFoundation
import Foundation
import MXStudioEngine
import Observation

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
    public private(set) var playheadBeat: Double = 0
    public private(set) var playheadLabel: String = "001 Bar / 1 Beat"
    public private(set) var playheadBar: Int = 1
    public private(set) var playheadBeatInBar: Int = 1
    public private(set) var playheadTimeLabel: String = "00:00.0"
    public private(set) var bpm: Double = 120
    public private(set) var musicalKey: String = "Cmaj"
    public private(set) var lastSavedAt: Date?
    public private(set) var saveError: String?
    public private(set) var recordError: String?

    public var isMetronomeEnabled: Bool = true {
        didSet { metronome?.isEnabled = isMetronomeEnabled }
    }

    public var metronomeLevel: Float = 0.6 {
        didSet { metronome?.level = metronomeLevel }
    }

    public var countInBars: Int = 1

    public private(set) var graph: MXGraph?
    public private(set) var transport: MXTransport?

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
    private var activeTakeURL: URL?

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

            attachPlayersForExistingClips()

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
        persistNow()
        playheadObserver?.stop()
        playheadObserver = nil
        transport?.stop()
        graph?.stop()
        graph?.session.deactivate()
        audioSession?.onEvent = nil
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
    }

    public func exitRecordMode() {
        if isRecording {
            stopRecordingAndCommit()
        }
        isRecordMode = false
        inputLevel = 0
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

                            let takeNumber = (project.tracks.first(where: { $0.id == trackID })?.clips.count ?? 0) + 1
                            let clip = MXClip(
                trackID: trackID,
                name: "Take \(takeNumber)",
                startBeat: startBeat,
                lengthBeats: lengthBeats,
                audioFileName: take.url.lastPathComponent
            )

            if let index = project.tracks.firstIndex(where: { $0.id == trackID }) {
                project.tracks[index].clips.append(clip)
            }

            attachPlayer(for: clip)
            persistNow()
            activeTakeURL = nil
            // Return to Figma 95:85026 — Studio After Record
            isRecordMode = false
            refreshPlayheadFromTransport()
        } catch {
            isRecording = false
            inputLevel = 0
            recordError = error.localizedDescription
            activeTakeURL = nil
        }
    }

    // MARK: - Track controls

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

    public func seekByBars(_ delta: Int) {
        guard let transport, phase == .ready, !isRecording else { return }
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

                if sample <= clipStart {
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: clipStart))
                    player.scheduleFile(file, at: at, completionHandler: nil)
                } else {
                    let offset = AVAudioFramePosition(sample - clipStart)
                    let remaining = AVAudioFrameCount(max(0, file.length - offset))
                    guard remaining > 0 else { continue }
                    let at = AVAudioTime(hostTime: transport.hostTime(forSample: sample))
                    player.scheduleSegment(
                        file,
                        startingFrame: offset,
                        frameCount: remaining,
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
                attachPlayer(for: clip)
            }
        }
    }

    private func attachPlayer(for clip: MXClip) {
        guard clipPlayers[clip.id] == nil, let graph else { return }
        let player = AVAudioPlayerNode()
        graph.connectSourceToMaster(player)
        clipPlayers[clip.id] = player
    }

    private func detachAllClipPlayers() {
        guard let graph else {
            clipPlayers.removeAll()
            return
        }
        for player in clipPlayers.values {
            player.stop()
            graph.disconnectSourceFromMaster(player)
        }
        clipPlayers.removeAll()
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
    }

    private func startMeterPolling() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self, self.isRecording else { return }
                    self.inputLevel = self.recorder?.inputLevel ?? 0
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
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
