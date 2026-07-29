import AVFoundation
import Foundation
import MXAudioDSP

/// Owns the `AVAudioEngine` and every topology change made to it.
///
/// Two rules the rest of the engine relies on:
/// 1. Nothing outside this class calls `attach`, `detach`, `connect` or
///    `disconnect`. All of it funnels through `graphMutation`, which is
///    serialised and asserts it is never on the render thread.
/// 2. A mutation zeroes the affected track's output before rewiring and
///    restores it after, so live insert changes stay under the −40 dBFS
///    transient bar (plan scenarios G-03 / G-04).
public final class MXGraph: @unchecked Sendable {

    public enum RenderMode: Equatable, Sendable {
        case realtime
        /// Manual rendering, used by the offline test harness and by bounce.
        case offline(sampleRate: Double, maximumFrameCount: AVAudioFrameCount)
    }

    public let engine = AVAudioEngine()
    public let session: MXAudioSession

    /// Everything sums here before master processing.
    public let masterBus = AVAudioMixerNode()
    public private(set) var masterInserts: [MXEffect] = []

    public private(set) var tracks: [MXTrackChain] = []
    public private(set) var auxBuses: [MXAuxBus] = []
    public private(set) var renderMode: RenderMode = .realtime

    /// Reentrant because a mutation can legitimately trigger another (adding a
    /// track rebuilds the master bus, for example).
    private let mutationLock = NSRecursiveLock()
    private var attachedNodes: Set<ObjectIdentifier> = []
    private var isConfigured = false

    public var processingFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    public private(set) var sampleRate: Double

    public init(session: MXAudioSession = MXAudioSession(), sampleRate: Double = 48_000) {
        self.session = session
        self.sampleRate = sampleRate
    }

    // MARK: - Lifecycle

    public func prepare(mode: RenderMode = .realtime) throws {
        try graphMutation {
            if engine.isRunning { engine.stop() }
            renderMode = mode

            switch mode {
            case .realtime:
                try session.activate()
                sampleRate = session.actualSampleRate
                engine.disableManualRenderingMode()
            case .offline(let rate, let maxFrames):
                sampleRate = rate
                guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
                    throw MXAudioError.engineStartFailed("could not build offline format")
                }
                do {
                    try engine.enableManualRenderingMode(.offline,
                                                         format: format,
                                                         maximumFrameCount: maxFrames)
                } catch {
                    throw MXAudioError.engineStartFailed(
                        "manual rendering: \(error.localizedDescription)")
                }
            }

            configureMasterIfNeeded()
            for track in tracks { rebuildConnections(for: track) }
            rebuildMasterChain()
        }
    }

    public func start() throws {
        try graphMutation {
            configureMasterIfNeeded()
            engine.prepare()
            do {
                try engine.start()
            } catch {
                throw MXAudioError.engineStartFailed(error.localizedDescription)
            }
        }
    }

    public func stop() {
        graphMutation {
            engine.stop()
        }
    }

    public var isRunning: Bool { engine.isRunning }

    /// Exposed so G-07 can assert that removing tracks leaves no orphan nodes.
    public var attachedNodeCount: Int {
        mutationLock.lock(); defer { mutationLock.unlock() }
        return attachedNodes.count
    }

    // MARK: - Mutation

    /// The single funnel for topology changes.
    ///
    /// Serialised, and never valid from the render thread — a debug assertion
    /// catches accidental use, because the failure mode in production is an
    /// intermittent glitch that is painful to trace back.
    @discardableResult
    public func graphMutation<T>(_ body: () throws -> T) rethrows -> T {
        assert(!MXGraph.isRenderThread, "graph mutation attempted on the render thread")
        mutationLock.lock()
        defer { mutationLock.unlock() }
        return try body()
    }

    private static var isRenderThread: Bool {
        // The render thread runs at a real-time scheduling policy; the main and
        // ordinary worker threads do not.
        var policy: Int32 = 0
        var param = sched_param()
        guard pthread_getschedparam(pthread_self(), &policy, &param) == 0 else { return false }
        return policy == SCHED_FIFO || policy == SCHED_RR
    }

    // MARK: - Tracks

    @discardableResult
    public func addTrack(name: String, instrument: MXInstrument? = nil) -> MXTrackChain {
        graphMutation {
            let track = MXTrackChain(name: name)
            track.setInstrument(instrument)
            tracks.append(track)
            configureMasterIfNeeded()
            attach(track.allNodes)
            rebuildConnections(for: track)
            return track
        }
    }

    public func removeTrack(id: UUID) {
        graphMutation {
            guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
            let track = tracks.remove(at: index)
            track.instrument?.allNotesOff()
            track.trackMixer.outputVolume = 0
            disconnectAndDetach(track.allNodes)
            resolveSoloBus()
        }
    }

    public func track(id: UUID) -> MXTrackChain? {
        tracks.first { $0.id == id }
    }

    /// Swaps the sound source without disturbing the rest of the chain.
    public func setInstrument(_ instrument: MXInstrument?, on track: MXTrackChain) {
        graphMutation {
            if let previous = track.instrument {
                previous.allNotesOff()
                disconnectAndDetach([previous.node])
            }
            track.setInstrument(instrument)
            if let instrument {
                attach([instrument.node])
                engine.connect(instrument.node, to: track.inputMixer, format: processingFormat)
            }
        }
    }

    public func setInserts(_ effects: [MXEffect], on track: MXTrackChain) {
        graphMutation {
            let previous = Set(track.inserts.map { ObjectIdentifier($0.node) })
            let next = Set(effects.map { ObjectIdentifier($0.node) })

            let removedNodes = track.inserts
                .filter { !next.contains(ObjectIdentifier($0.node)) }
                .map(\.node)

            track.setInserts(effects)
            attach(effects.map(\.node).filter { !previous.contains(ObjectIdentifier($0)) })
            rebuildConnections(for: track)
            disconnectAndDetach(removedNodes)
        }
    }

    public func insert(_ effect: MXEffect, on track: MXTrackChain, at index: Int? = nil) {
        var next = track.inserts
        let position = min(max(index ?? next.count, 0), next.count)
        next.insert(effect, at: position)
        setInserts(next, on: track)
    }

    public func removeInsert(_ effect: MXEffect, from track: MXTrackChain) {
        let next = track.inserts.filter { $0 !== effect }
        setInserts(next, on: track)
    }

    /// Reordering is a full chain rebuild; FX-04 asserts the rendered result
    /// actually differs when order changes.
    public func moveInsert(on track: MXTrackChain, from: Int, to: Int) {
        graphMutation {
            var next = track.inserts
            guard next.indices.contains(from) else { return }
            let effect = next.remove(at: from)
            next.insert(effect, at: min(max(to, 0), next.count))
            track.setInserts(next)
            rebuildConnections(for: track)
        }
    }

    /// Bypass toggles that need rerouting rebuild the chain; the rest are
    /// handled inside the effect and need no graph work.
    public func setBypass(_ bypassed: Bool, for effect: MXEffect, on track: MXTrackChain) {
        graphMutation {
            effect.isBypassed = bypassed
            if let routable = effect as? MXBypassRoutable, routable.prefersGraphLevelBypass {
                rebuildConnections(for: track)
            }
        }
    }

    // MARK: - Mute / solo

    public func setMuted(_ muted: Bool, on track: MXTrackChain) {
        track.isMuted = muted
        if muted { track.instrument?.allNotesOff() }
    }

    public func setSoloed(_ soloed: Bool, on track: MXTrackChain) {
        track.isSoloed = soloed
        resolveSoloBus()
    }

    public func clearAllSolos() {
        for track in tracks { track.isSoloed = false }
        resolveSoloBus()
    }

    private func resolveSoloBus() {
        let anySoloed = tracks.contains { $0.isSoloed }
        for track in tracks {
            track.isDucked = anySoloed && !track.isSoloed
        }
    }

    // MARK: - Aux buses

    @discardableResult
    public func addAuxBus(name: String, effect: MXEffect? = nil) -> MXAuxBus {
        graphMutation {
            let bus = MXAuxBus(index: auxBuses.count, name: name, effect: effect)
            auxBuses.append(bus)
            configureMasterIfNeeded()
            attach(bus.allNodes)
            rebuildConnections(for: bus)
            return bus
        }
    }

    public func setSend(_ level: Float, from track: MXTrackChain, to bus: MXAuxBus) {
        graphMutation {
            track.setSend(bus: bus.index, level: level)
            rebuildConnections(for: track)
        }
    }

    // MARK: - Click / utility sources

    /// Attaches an arbitrary source (e.g. metronome) straight to the master bus.
    /// Used by the Studio session for the click track before it becomes a
    /// first-class mixable track.
    public func connectSourceToMaster(_ node: AVAudioNode) {
        graphMutation {
            configureMasterIfNeeded()
            attach([node])
            engine.connect(node, to: masterBus, format: processingFormat)
        }
    }

    /// Detaches a utility source previously connected with `connectSourceToMaster`.
    public func disconnectSourceFromMaster(_ node: AVAudioNode) {
        graphMutation {
            engine.disconnectNodeOutput(node)
            disconnectAndDetach([node])
        }
    }

    /// Connects `source → insert → master` with tracked attach (clip player → EQ).
    public func connectSourceThroughInsertToMaster(source: AVAudioNode, insert: AVAudioNode) {
        connectSourceThroughInsertsToMaster(source: source, inserts: [insert])
    }

    /// Connects `source → inserts[0] → … → inserts[n] → master` with tracked attach.
    public func connectSourceThroughInsertsToMaster(source: AVAudioNode, inserts: [AVAudioNode]) {
        graphMutation {
            configureMasterIfNeeded()
            attach(inserts + [source])
            var chain: [AVAudioNode] = [source] + inserts
            for (a, b) in zip(chain, chain.dropFirst()) {
                engine.connect(a, to: b, format: processingFormat)
            }
            if let last = chain.last {
                engine.connect(last, to: masterBus, format: processingFormat)
            }
        }
    }

    /// Tears down a chain built with `connectSourceThroughInsertToMaster`.
    public func disconnectSourceThroughInsertFromMaster(source: AVAudioNode, insert: AVAudioNode) {
        disconnectSourceThroughInsertsFromMaster(source: source, inserts: [insert])
    }

    /// Tears down a chain built with `connectSourceThroughInsertsToMaster`.
    public func disconnectSourceThroughInsertsFromMaster(source: AVAudioNode, inserts: [AVAudioNode]) {
        graphMutation {
            engine.disconnectNodeOutput(source)
            for node in inserts {
                engine.disconnectNodeOutput(node)
            }
            disconnectAndDetach([source] + inserts)
        }
    }

    /// Attach a utility node into the tracked set (e.g. monitor mixer) without connecting.
    public func attachUtilityNode(_ node: AVAudioNode) {
        graphMutation {
            configureMasterIfNeeded()
            attach([node])
        }
    }

    /// Connect two already-attached nodes (or engine-owned nodes like `inputNode`).
    public func connect(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat?) {
        graphMutation {
            engine.connect(source, to: destination, format: format)
        }
    }

    /// Disconnect + detach a tracked utility node.
    public func detachUtilityNode(_ node: AVAudioNode) {
        graphMutation {
            disconnectAndDetach([node])
        }
    }

    // MARK: - Master chain

    public func setMasterInserts(_ effects: [MXEffect]) {
        graphMutation {
            let removed = masterInserts
                .filter { effect in !effects.contains(where: { $0 === effect }) }
                .map(\.node)
            masterInserts = effects
            attach(effects.map(\.node))
            rebuildMasterChain()
            disconnectAndDetach(removed)
        }
    }

    private func configureMasterIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        attach([masterBus])
        // Touching mainMixerNode instantiates it, so do it once here rather than
        // implicitly from an arbitrary call site.
        _ = engine.mainMixerNode
        rebuildMasterChain()
    }

    private func rebuildMasterChain() {
        let format = processingFormat
        var chain: [AVAudioNode] = [masterBus]
        chain.append(contentsOf: masterInserts.filter { !$0.isBypassed }.map(\.node))

        for node in chain {
            engine.disconnectNodeOutput(node)
        }
        for (a, b) in zip(chain, chain.dropFirst()) {
            engine.connect(a, to: b, format: format)
        }
        if let last = chain.last {
            engine.connect(last, to: engine.mainMixerNode, format: format)
        }
    }

    // MARK: - Connection building

    private func rebuildConnections(for track: MXTrackChain) {
        let format = processingFormat
        let restoreVolume = track.trackMixer.outputVolume
        track.trackMixer.outputVolume = 0
        defer { track.trackMixer.outputVolume = restoreVolume }

        attach(track.allNodes)

        let path = track.serialPath
        for node in path {
            engine.disconnectNodeOutput(node)
        }
        if let instrument = track.instrument {
            engine.disconnectNodeOutput(instrument.node)
            engine.connect(instrument.node, to: track.inputMixer, format: format)
        }

        for (a, b) in zip(path, path.dropFirst()) {
            engine.connect(a, to: b, format: format)
        }

        // trackMixer fans out to the master bus plus any active sends.
        var destinations = [AVAudioConnectionPoint(node: masterBus, bus: masterBus.nextAvailableInputBus)]
        for (busIndex, level) in track.sendLevels where level > 0 {
            guard busIndex < auxBuses.count else { continue }
            let aux = auxBuses[busIndex]
            destinations.append(AVAudioConnectionPoint(node: aux.input,
                                                       bus: aux.input.nextAvailableInputBus))
        }
        engine.connect(track.trackMixer, to: destinations, fromBus: 0, format: format)
    }

    private func rebuildConnections(for bus: MXAuxBus) {
        let format = processingFormat
        for node in bus.allNodes {
            engine.disconnectNodeOutput(node)
        }
        var chain: [AVAudioNode] = [bus.input]
        if let effect = bus.effect { chain.append(effect.node) }
        chain.append(bus.output)
        for (a, b) in zip(chain, chain.dropFirst()) {
            engine.connect(a, to: b, format: format)
        }
        engine.connect(bus.output, to: masterBus, format: format)
    }

    // MARK: - Attach / detach bookkeeping

    private func attach(_ nodes: [AVAudioNode]) {
        for node in nodes {
            let key = ObjectIdentifier(node)
            guard !attachedNodes.contains(key) else { continue }
            engine.attach(node)
            attachedNodes.insert(key)
        }
    }

    private func disconnectAndDetach(_ nodes: [AVAudioNode]) {
        for node in nodes {
            let key = ObjectIdentifier(node)
            guard attachedNodes.contains(key) else { continue }
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeInput(node)
            engine.detach(node)
            attachedNodes.remove(key)
        }
    }
}

/// A shared effect bus tracks can send to, backing the mixer screen's sends.
public final class MXAuxBus: @unchecked Sendable {
    public let index: Int
    public var name: String
    public let input = AVAudioMixerNode()
    public let output = AVAudioMixerNode()
    public private(set) var effect: MXEffect?

    init(index: Int, name: String, effect: MXEffect?) {
        self.index = index
        self.name = name
        self.effect = effect
    }

    public var returnLevel: Float {
        get { output.outputVolume }
        set { output.outputVolume = min(max(newValue, 0), 2) }
    }

    var allNodes: [AVAudioNode] {
        var nodes: [AVAudioNode] = [input, output]
        if let effect { nodes.append(effect.node) }
        return nodes
    }
}
