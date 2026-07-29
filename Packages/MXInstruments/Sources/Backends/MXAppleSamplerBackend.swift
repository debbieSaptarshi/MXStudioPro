import AVFoundation
import Foundation
import MXAudioDSP

/// `AVAudioUnitSampler` behind the `MXInstrument` protocol.
///
/// This is the cheapest route to a large amount of existing content —
/// SoundFonts, DLS banks, EXS24 instruments and `.aupreset` files all load
/// here, it streams from disk, and it costs no extra dependency. It backs the
/// General MIDI layer and the Grand Piano on the Piano MIDI screen.
///
/// Known limitation, called out in the plan: its metadata parsing is lenient,
/// so packs are validated at install time rather than trusted at load time.
public final class MXAppleSamplerBackend: MXInstrument, @unchecked Sendable {

    public let sampler = AVAudioUnitSampler()
    public var node: AVAudioNode { sampler }
    public var displayName: String

    private let allocator: MXVoiceAllocator
    private let loadedResource = MXProtected<MXInstrumentResource?>(nil)
    private let store = MXParameterStore()

    public init(displayName: String = "Apple Sampler", polyphony: Int = 32) {
        self.displayName = displayName
        allocator = MXVoiceAllocator(capacity: polyphony, maxCapacity: 64)
        store.set(.volume, 1)
    }

    public var polyphony: Int {
        get { allocator.capacity }
        set {
            allocator.setCapacity(newValue) { [weak self] index in
                guard let self else { return }
                let slot = allocator.slot(at: index)
                sampler.stopNote(slot.note, onChannel: slot.channel)
            }
        }
    }

    /// What is currently loaded, so a project file can re-load it verbatim.
    public var resource: MXInstrumentResource? {
        loadedResource.value
    }

    // MARK: - Loading

    public func load(_ resource: MXInstrumentResource) async throws {
        switch resource {
        case .soundBank(let url, let program, let bankMSB, let bankLSB):
            try loadSoundBank(url: url, program: program, bankMSB: bankMSB, bankLSB: bankLSB)

        case .sampleFolder(let url, _):
            try loadSampleFolder(url: url)

        case .sfz, .synthPreset, .auv3:
            throw MXAudioError.unsupportedResource(
                "\(resource.displayName) cannot be loaded by the Apple sampler")
        }

        loadedResource.value = resource
    }

    private func loadSoundBank(url: URL, program: UInt8, bankMSB: UInt8, bankLSB: UInt8) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MXAudioError.resourceNotFound(path: url.path)
        }

        let ext = url.pathExtension.lowercased()
        do {
            switch ext {
            case "sf2", "sf3", "dls":
                try sampler.loadSoundBankInstrument(at: url,
                                                    program: program,
                                                    bankMSB: bankMSB,
                                                    bankLSB: bankLSB)
            case "aupreset", "exs":
                // These describe an instrument directly rather than a bank.
                try sampler.loadInstrument(at: url)
            default:
                throw MXAudioError.unsupportedResource("sound bank extension '.\(ext)'")
            }
        } catch let error as MXAudioError {
            throw error
        } catch {
            throw MXAudioError.soundBankLoadFailed(path: url.path,
                                                   underlying: error.localizedDescription)
        }
    }

    private func loadSampleFolder(url: URL) throws {
        let contents: [URL]
        do {
            contents = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { ["wav", "aif", "aiff", "caf"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw MXAudioError.resourceNotFound(path: url.path)
        }
        guard !contents.isEmpty else {
            throw MXAudioError.resourceNotFound(path: "\(url.path) (no audio files)")
        }
        do {
            try sampler.loadAudioFiles(at: contents)
        } catch {
            throw MXAudioError.soundBankLoadFailed(path: url.path,
                                                   underlying: error.localizedDescription)
        }
    }

    /// Selects a different GM program on an already-loaded bank without
    /// re-reading the file.
    public func selectProgram(_ program: UInt8, bankMSB: UInt8, bankLSB: UInt8) throws {
        guard case .soundBank(let url, _, _, _) = resource else {
            throw MXAudioError.invalidState("no sound bank loaded")
        }
        try loadSoundBank(url: url, program: program, bankMSB: bankMSB, bankLSB: bankLSB)
        loadedResource.value = .soundBank(url: url, program: program,
                                          bankMSB: bankMSB, bankLSB: bankLSB)
    }

    // MARK: - Playback

    public func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        guard velocity > 0 else {
            noteOff(note, channel: channel)
            return
        }
        // Enforce our own cap: the AU will happily exceed the project's
        // configured polyphony otherwise, which I-04 checks for.
        if allocator.activeVoiceCount >= allocator.capacity {
            let index = allocator.allocate(note: note, channel: channel)
            let stolen = allocator.slot(at: index)
            if stolen.note != note || stolen.channel != channel {
                sampler.stopNote(stolen.note, onChannel: stolen.channel)
            }
        } else {
            _ = allocator.allocate(note: note, channel: channel)
        }
        sampler.startNote(note, withVelocity: velocity, onChannel: channel)
    }

    public func noteOff(_ note: UInt8, channel: UInt8) {
        allocator.release(note: note, channel: channel) { index in
            allocator.recycle(index)
        }
        sampler.stopNote(note, onChannel: channel)
    }

    public func allNotesOff() {
        allocator.releaseAll { _ in }
        allocator.reset()
        for channel in UInt8(0)...UInt8(15) {
            // CC 123 = all notes off, CC 120 = all sound off.
            sampler.sendController(123, withValue: 0, onChannel: channel)
            sampler.sendController(120, withValue: 0, onChannel: channel)
        }
    }

    public var activeVoiceCount: Int { allocator.activeVoiceCount }

    // MARK: - Parameters

    public func setParameter(_ id: MXParamID, value: Float) {
        store.set(id, value)
        switch id {
        case .volume:
            // AU gain is in dB; the protocol's 0...1 is linear.
            sampler.overallGain = 20 * log10(max(store.value(.volume), 1e-4))
        case .pan:
            sampler.stereoPan = store.value(.pan) * 100
        default:
            break
        }
    }

    public func parameter(_ id: MXParamID) -> Float {
        store.value(id)
    }

    // MARK: - State

    private struct State: Codable {
        var parameters: [UInt64: Float]
        var soundBankPath: String?
        var program: UInt8?
        var bankMSB: UInt8?
        var bankLSB: UInt8?
        var sampleFolderPath: String?
        var polyphony: Int
    }

    public func captureState() -> Data {
        var state = State(parameters: store.snapshot(),
                          soundBankPath: nil, program: nil,
                          bankMSB: nil, bankLSB: nil,
                          sampleFolderPath: nil,
                          polyphony: polyphony)
        switch resource {
        case .soundBank(let url, let program, let msb, let lsb):
            state.soundBankPath = url.path
            state.program = program
            state.bankMSB = msb
            state.bankLSB = lsb
        case .sampleFolder(let url, _):
            state.sampleFolderPath = url.path
        default:
            break
        }
        return (try? JSONEncoder().encode(state)) ?? Data()
    }

    public func restoreState(_ data: Data) throws {
        let state: State
        do {
            state = try JSONDecoder().decode(State.self, from: data)
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }

        polyphony = state.polyphony
        for (raw, value) in state.parameters {
            guard let id = MXParamID(rawValue: raw) else { continue }
            setParameter(id, value: value)
        }

        if let path = state.soundBankPath {
            try loadSoundBank(url: URL(fileURLWithPath: path),
                              program: state.program ?? 0,
                              bankMSB: state.bankMSB ?? UInt8(kAUSampler_DefaultMelodicBankMSB),
                              bankLSB: state.bankLSB ?? UInt8(kAUSampler_DefaultBankLSB))
            loadedResource.value = .soundBank(url: URL(fileURLWithPath: path),
                                              program: state.program ?? 0,
                                              bankMSB: state.bankMSB ?? UInt8(kAUSampler_DefaultMelodicBankMSB),
                                              bankLSB: state.bankLSB ?? UInt8(kAUSampler_DefaultBankLSB))
        } else if let path = state.sampleFolderPath {
            try loadSampleFolder(url: URL(fileURLWithPath: path))
            loadedResource.value = .sampleFolder(url: URL(fileURLWithPath: path), rootNote: 60)
        }
    }
}

// MARK: - General MIDI

/// Bank selectors and the handful of GM programs the app references by name.
public enum MXGeneralMIDI {
    public static let melodicBankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
    public static let percussionBankMSB = UInt8(kAUSampler_DefaultPercussionBankMSB)
    public static let defaultBankLSB = UInt8(kAUSampler_DefaultBankLSB)

    /// GM channel 10 is percussion. Zero-based that is channel 9.
    public static let percussionChannel: UInt8 = 9

    public enum Program: UInt8 {
        case acousticGrandPiano = 0
        case electricPiano = 4
        case acousticGuitarSteel = 25
        case electricGuitarClean = 27
        case overdrivenGuitar = 29
        case acousticBass = 32
        case electricBassFinger = 33
        case violin = 40
        case stringEnsemble = 48
        case synthPad = 88
    }

    /// The system bank ships with macOS and is a licensing-clean default for
    /// development and tests. iOS builds bundle their own vetted SoundFont.
    public static var systemSoundBankURL: URL? {
        let path = "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    public static func melodicResource(bank url: URL, program: Program) -> MXInstrumentResource {
        .soundBank(url: url, program: program.rawValue,
                   bankMSB: melodicBankMSB, bankLSB: defaultBankLSB)
    }

    public static func percussionResource(bank url: URL) -> MXInstrumentResource {
        .soundBank(url: url, program: 0,
                   bankMSB: percussionBankMSB, bankLSB: defaultBankLSB)
    }
}
