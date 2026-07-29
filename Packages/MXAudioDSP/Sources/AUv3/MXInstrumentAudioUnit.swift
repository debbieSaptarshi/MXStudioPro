import AVFoundation
import Foundation

/// What an `MXInstrumentAudioUnit` renders.
///
/// Both `MXSynthEngine` and the SFZ engine satisfy this, so the same AU shell
/// ships either one. A vendored sfizz bridge satisfies it too, which is why the
/// AU never learns which engine it is driving.
public protocol MXAudioUnitRenderSource: AnyObject {
    func setSampleRate(_ rate: Double)
    func render(left: UnsafeMutablePointer<Float>,
                right: UnsafeMutablePointer<Float>,
                frameCount: Int)
    func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, frameOffset: Int)
    func noteOff(note: UInt8, channel: UInt8, frameOffset: Int)
    func allNotesOff()

    var exposedParameters: [MXParamID] { get }
    func setParameter(_ id: MXParamID, value: Float)
    func parameter(_ id: MXParamID) -> Float

    func captureState() -> Data
    func restoreState(_ data: Data) throws
}

/// `AUAudioUnit` shell for MXStudio instruments.
///
/// Used two ways:
/// - inside the app, when an instrument needs to be a real AU rather than a
///   source node (for example to expose ramped `AUParameter` automation);
/// - inside the AUv3 extension, where it is what other DAWs actually load.
///
/// The render block captures the engine once at block-construction time, so no
/// ARC or dictionary lookups happen per buffer.
public final class MXInstrumentAudioUnit: AUAudioUnit, @unchecked Sendable {

    public static let maximumFramesToRender: AVAudioFrameCount = 4_096

    private let engine: MXAudioUnitRenderSource
    private var outputBus: AUAudioUnitBus
    private var busArray: AUAudioUnitBusArray!
    private var format: AVAudioFormat

    private var scratchLeft: UnsafeMutablePointer<Float>?
    private var scratchRight: UnsafeMutablePointer<Float>?
    private var outputBuffer: AVAudioPCMBuffer?

    private var parameterTreeStorage: AUParameterTree!

    public init(componentDescription: AudioComponentDescription,
                options: AudioComponentInstantiationOptions = [],
                engine: MXAudioUnitRenderSource) throws {
        self.engine = engine
        guard let defaultFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000,
                                                channels: 2) else {
            throw MXAudioError.instantiationFailed("could not build default format")
        }
        format = defaultFormat
        outputBus = try AUAudioUnitBus(format: defaultFormat)
        outputBus.maximumChannelCount = 2

        try super.init(componentDescription: componentDescription, options: options)

        busArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = Self.maximumFramesToRender
        buildParameterTree()
    }

    deinit {
        freeScratch()
    }

    public override var outputBusses: AUAudioUnitBusArray { busArray }

    /// Instruments have no audio input; MIDI arrives through the render event
    /// list instead.
    public override var inputBusses: AUAudioUnitBusArray {
        AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
    }

    public override var virtualMIDICableCount: Int { 1 }
    public override var supportsUserPresets: Bool { true }

    // MARK: - Parameters

    private func buildParameterTree() {
        var parameters: [AUParameter] = []
        for id in engine.exposedParameters {
            let range = id.range
            let parameter = AUParameterTree.createParameter(
                withIdentifier: "p\(id.rawValue)",
                name: String(describing: id),
                address: AUParameterAddress(id.rawValue),
                min: range.lowerBound,
                max: range.upperBound,
                unit: Self.unit(for: id),
                unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp],
                valueStrings: nil,
                dependentParameters: nil)
            parameter.value = engine.parameter(id)
            parameters.append(parameter)
        }

        let tree = AUParameterTree.createTree(withChildren: parameters)
        let source = engine
        tree.implementorValueObserver = { parameter, value in
            guard let id = MXParamID(rawValue: parameter.address) else { return }
            source.setParameter(id, value: value)
        }
        tree.implementorValueProvider = { parameter in
            guard let id = MXParamID(rawValue: parameter.address) else { return 0 }
            return source.parameter(id)
        }
        parameterTreeStorage = tree
        parameterTree = tree
    }

    private static func unit(for id: MXParamID) -> AudioUnitParameterUnit {
        switch id {
        case .filterCutoff:
            return .hertz
        case .ampAttack, .ampDecay, .ampRelease:
            return .seconds
        case .fxTime:
            return .milliseconds
        case .osc1Fine, .osc2Fine, .osc2Detune:
            return .cents
        case .osc1Coarse, .osc2Coarse:
            return .relativeSemiTones
        case .pan:
            return .pan
        default:
            return .linearGain
        }
    }

    // MARK: - Resources

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()

        format = outputBus.format
        engine.setSampleRate(format.sampleRate)

        let capacity = Int(maximumFramesToRender)
        freeScratch()
        let left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
        scratchLeft = left
        scratchRight = right

        outputBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                        frameCapacity: maximumFramesToRender)
    }

    public override func deallocateRenderResources() {
        engine.allNotesOff()
        freeScratch()
        outputBuffer = nil
        super.deallocateRenderResources()
    }

    private func freeScratch() {
        let capacity = Int(Self.maximumFramesToRender)
        if let scratchLeft {
            scratchLeft.deinitialize(count: capacity)
            scratchLeft.deallocate()
        }
        if let scratchRight {
            scratchRight.deinitialize(count: capacity)
            scratchRight.deallocate()
        }
        scratchLeft = nil
        scratchRight = nil
    }

    // MARK: - Render

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Everything the block needs is captured once here so the audio thread
        // never touches `self` or the Swift runtime.
        let source = engine
        guard let left = scratchLeft, let right = scratchRight,
              let buffer = outputBuffer else {
            return { _, _, _, _, _, _, _ in kAudioUnitErr_Uninitialized }
        }
        let maxFrames = Int(Self.maximumFramesToRender)

        return { _, _, frameCount, _, outputData, realtimeEventListHead, _ in
            let frames = min(Int(frameCount), maxFrames)

            // Drain scheduled MIDI, preserving each event's frame offset so
            // sequenced notes stay sample-accurate.
            var event = realtimeEventListHead?.pointee
            while let current = event {
                if current.head.eventType == .MIDI {
                    let midi = current.MIDI
                    let bytes = withUnsafeBytes(of: midi.data) { Array($0.prefix(3)) }
                    let status = bytes[0] & 0xF0
                    let channel = bytes[0] & 0x0F
                    let offset = Int(midi.eventSampleTime)
                    switch status {
                    case 0x90 where bytes[2] > 0:
                        source.noteOn(note: bytes[1], velocity: bytes[2],
                                      channel: channel, frameOffset: offset)
                    case 0x80, 0x90:
                        source.noteOff(note: bytes[1], channel: channel, frameOffset: offset)
                    case 0xB0 where bytes[1] == 123 || bytes[1] == 120:
                        source.allNotesOff()
                    default:
                        break
                    }
                }
                event = current.head.next?.pointee
            }

            source.render(left: left, right: right, frameCount: frames)

            // A host may hand us null buffer pointers, meaning "use your own".
            let outputList = UnsafeMutableAudioBufferListPointer(outputData)
            if outputList.count > 0, outputList[0].mData == nil {
                guard let owned = buffer.audioBufferList as UnsafePointer<AudioBufferList>? else {
                    return kAudioUnitErr_Uninitialized
                }
                let ownedList = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: owned))
                for index in 0..<outputList.count where index < ownedList.count {
                    outputList[index].mNumberChannels = ownedList[index].mNumberChannels
                    outputList[index].mData = ownedList[index].mData
                    outputList[index].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
                }
            }

            for (index, audioBuffer) in outputList.enumerated() {
                guard let data = audioBuffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                data.update(from: index == 0 ? left : right, count: frames)
                if Int(frameCount) > frames {
                    (data + frames).update(repeating: 0, count: Int(frameCount) - frames)
                }
            }
            return noErr
        }
    }

    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            state[MXInstrumentAudioUnit.engineStateKey] = engine.captureState()
            return state
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[MXInstrumentAudioUnit.engineStateKey] as? Data else { return }
            try? engine.restoreState(data)
            // Push restored values back into the tree so the host UI updates.
            for parameter in parameterTreeStorage.allParameters {
                guard let id = MXParamID(rawValue: parameter.address) else { continue }
                parameter.value = engine.parameter(id)
            }
        }
    }

    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }

    public static let engineStateKey = "com.mxstudio.engineState"
}
