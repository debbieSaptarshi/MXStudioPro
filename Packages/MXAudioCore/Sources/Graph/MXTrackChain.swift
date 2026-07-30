import AVFoundation
import Foundation
import MXAudioDSP

/// One track's node chain:
///
/// ```
/// instrument -> inputMixer -> insert[0..n] -> EQ -> trackMixer -> master (+ sends)
/// ```
///
/// `inputMixer` exists so swapping the instrument only reconnects one edge and
/// leaves the rest of the chain standing — that is what makes a hot instrument
/// swap possible without stopping transport.
///
/// The chain never mutates itself. `MXGraph` owns all topology changes so they
/// stay serialised through a single mutation path.
public final class MXTrackChain: @unchecked Sendable {

    public let id: UUID
    public var name: String

    public let inputMixer = AVAudioMixerNode()
    public let eq: AVAudioUnitEQ
    public let trackMixer = AVAudioMixerNode()

    public private(set) var instrument: MXInstrument?
    public private(set) var inserts: [MXEffect] = []

    /// Send levels keyed by aux bus index.
    public private(set) var sendLevels: [Int: Float] = [:]
    /// Per-aux gain nodes so send level is real attenuation (not just route open/close).
    private var sendGainNodes: [Int: AVAudioMixerNode] = [:]

    private var _volume: Float = 1
    private var _pan: Float = 0
    private var _isMuted = false
    private var _isSoloed = false
    /// Set by the graph when some *other* track is soloed.
    private var _isDucked = false

    public init(id: UUID = UUID(), name: String, bandCount: Int = 4) {
        self.id = id
        self.name = name
        eq = AVAudioUnitEQ(numberOfBands: bandCount)
        eq.globalGain = 0
        configureDefaultEQ()
    }

    private func configureDefaultEQ() {
        let defaults: [(AVAudioUnitEQFilterType, Float, Float)] = [
            (.lowShelf, 80, 0.7),
            (.parametric, 400, 1.0),
            (.parametric, 2_500, 1.0),
            (.highShelf, 8_000, 0.7),
        ]
        for (index, band) in eq.bands.enumerated() where index < defaults.count {
            let (type, frequency, bandwidth) = defaults[index]
            band.filterType = type
            band.frequency = frequency
            band.bandwidth = bandwidth
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Channel strip

    public var volume: Float {
        get { _volume }
        set {
            _volume = min(max(newValue, 0), 2)
            applyGain()
        }
    }

    public var pan: Float {
        get { _pan }
        set {
            _pan = min(max(newValue, -1), 1)
            trackMixer.pan = _pan
        }
    }

    public var isMuted: Bool {
        get { _isMuted }
        set { _isMuted = newValue; applyGain() }
    }

    public var isSoloed: Bool {
        get { _isSoloed }
        set { _isSoloed = newValue; applyGain() }
    }

    var isDucked: Bool {
        get { _isDucked }
        set { _isDucked = newValue; applyGain() }
    }

    /// Effective audibility after mute and the solo bus are resolved.
    public var isAudible: Bool {
        !_isMuted && !_isDucked
    }

    private func applyGain() {
        trackMixer.outputVolume = isAudible ? _volume : 0
    }

    // MARK: - Topology description
    //
    // These are called by MXGraph inside a mutation; they only describe the
    // desired shape, they do not touch the engine.

    func setInstrument(_ newValue: MXInstrument?) {
        instrument = newValue
    }

    func setInserts(_ newValue: [MXEffect]) {
        inserts = newValue
    }

    public func setSend(bus: Int, level: Float) {
        sendLevels[bus] = min(max(level, 0), 1)
    }

    /// Gain node for an aux send (created lazily). `MXGraph` attaches + wires it.
    func sendGainNode(for bus: Int) -> AVAudioMixerNode {
        if let existing = sendGainNodes[bus] { return existing }
        let node = AVAudioMixerNode()
        node.outputVolume = sendLevels[bus] ?? 0
        sendGainNodes[bus] = node
        return node
    }

    /// Insert nodes that should actually be wired, skipping graph-level bypasses.
    /// An effect that handles bypass internally stays in the chain so removing
    /// it cannot click.
    var activeInsertNodes: [AVAudioNode] {
        inserts.compactMap { effect in
            if let routable = effect as? MXBypassRoutable,
               routable.prefersGraphLevelBypass,
               effect.isBypassed {
                return nil
            }
            return effect.node
        }
    }

    /// Every node the graph must attach for this chain.
    var allNodes: [AVAudioNode] {
        var nodes: [AVAudioNode] = [inputMixer, eq, trackMixer]
        if let instrument { nodes.append(instrument.node) }
        nodes.append(contentsOf: inserts.map(\.node))
        nodes.append(contentsOf: sendGainNodes.values)
        return nodes
    }

    /// Ordered serial path from `inputMixer` to `trackMixer`.
    var serialPath: [AVAudioNode] {
        [inputMixer] + activeInsertNodes + [eq, trackMixer]
    }
}
