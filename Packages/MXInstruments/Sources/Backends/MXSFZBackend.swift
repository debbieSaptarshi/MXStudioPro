import AVFoundation
import Foundation
import MXAudioDSP

/// SFZ libraries behind the `MXInstrument` protocol.
///
/// The actual playback engine comes from `MXSFZEngineFactory`, so swapping the
/// native engine for vendored sfizz is a one-line change here and invisible to
/// every call site. This is the route for round-robins, velocity layers,
/// one-shots and disk streaming — the things `AVAudioUnitSampler` cannot do.
public final class MXSFZBackend: MXSourceInstrument, @unchecked Sendable {

    public let engine: MXSFZEngine
    private let loadedURL = MXProtected<URL?>(nil)
    private let store = MXParameterStore()
    private var requestedPolyphony: Int

    public init(displayName: String = "SFZ Instrument",
                sampleRate: Double = 48_000,
                polyphony: Int = 32,
                store sampleStore: MXSampleStore? = nil,
                engine: MXSFZEngine? = nil) {
        self.engine = engine ?? MXSFZEngineFactory.make(sampleRate: sampleRate,
                                                        store: sampleStore)
        requestedPolyphony = polyphony
        super.init(displayName: displayName, sampleRate: sampleRate)
        self.engine.setSampleRate(sampleRate)
        self.engine.setPolyphony(polyphony)
        store.set(.volume, 1)
    }

    public override var polyphony: Int {
        get { requestedPolyphony }
        set {
            requestedPolyphony = max(1, newValue)
            engine.setPolyphony(requestedPolyphony)
        }
    }

    public override func setSampleRate(_ rate: Double) {
        super.setSampleRate(rate)
        engine.setSampleRate(rate)
    }

    public var url: URL? {
        loadedURL.value
    }

    public var regionCount: Int { engine.loadedRegionCount }
    public var residentBytes: Int { engine.residentBytes }
    public var activeVoiceCount: Int { engine.activeVoiceCount }

    public override func load(_ resource: MXInstrumentResource) async throws {
        switch resource {
        case .sfz(let url):
            try engine.loadSFZ(url: url)
            loadedURL.value = url

        case .sampleFolder(let url, let rootNote):
            // Raw sample folders are converted to an SFZ mapping on import so
            // there is only ever one sample-mapping engine in the product.
            let generated = try MXSFZGenerator.generateMapping(forFolderAt: url, rootNote: rootNote)
            try engine.loadSFZ(url: generated)
            loadedURL.value = generated

        case .soundBank, .synthPreset, .auv3:
            throw MXAudioError.unsupportedResource(
                "\(resource.displayName) cannot be loaded by the SFZ backend")
        }
    }

    public override func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        engine.noteOn(note: note, velocity: velocity, channel: channel, frameOffset: 0)
    }

    public override func noteOff(_ note: UInt8, channel: UInt8) {
        engine.noteOff(note: note, channel: channel, frameOffset: 0)
    }

    public override func allNotesOff() {
        engine.allNotesOff()
    }

    public override func setParameter(_ id: MXParamID, value: Float) {
        store.set(id, value)
    }

    public override func parameter(_ id: MXParamID) -> Float {
        store.value(id)
    }

    private struct State: Codable {
        var sfzPath: String?
        var parameters: [UInt64: Float]
        var polyphony: Int
    }

    public override func captureState() -> Data {
        let state = State(sfzPath: url?.path,
                          parameters: store.snapshot(),
                          polyphony: polyphony)
        return (try? JSONEncoder().encode(state)) ?? Data()
    }

    public override func restoreState(_ data: Data) throws {
        let state: State
        do {
            state = try JSONDecoder().decode(State.self, from: data)
        } catch {
            throw MXAudioError.stateDecodeFailed(error.localizedDescription)
        }
        polyphony = state.polyphony
        store.restore(state.parameters)
        if let path = state.sfzPath {
            try engine.loadSFZ(url: URL(fileURLWithPath: path))
            loadedURL.value = URL(fileURLWithPath: path)
        }
    }

    public override func render(left: UnsafeMutablePointer<Float>,
                                right: UnsafeMutablePointer<Float>,
                                frameCount: Int) {
        engine.render(left: left, right: right, frameCount: frameCount)

        let gain = store.value(.volume)
        if abs(gain - 1) > 1e-4 {
            for i in 0..<frameCount {
                left[i] *= gain
                right[i] *= gain
            }
        }
    }
}

/// Turns a folder of raw samples into an SFZ mapping.
///
/// Filenames are matched for a note name or MIDI number so a well-named sample
/// set maps chromatically; anything unmatched is spread across the keyboard
/// from the root note upwards.
public enum MXSFZGenerator {

    public static func generateMapping(forFolderAt folder: URL,
                                       rootNote: UInt8,
                                       outputURL: URL? = nil) throws -> URL {
        let audioExtensions = ["wav", "aif", "aiff", "caf", "flac"]
        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw MXAudioError.resourceNotFound(path: folder.path)
        }

        guard !files.isEmpty else {
            throw MXAudioError.resourceNotFound(path: "\(folder.path) (no audio files)")
        }

        var lines = ["// Generated by MXSFZGenerator for \(folder.lastPathComponent)", "<group>"]
        var fallbackNote = Int(rootNote)

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let note = inferredNote(from: name) ?? UInt8(min(127, fallbackNote))
            if inferredNote(from: name) == nil { fallbackNote += 1 }
            var region = "<region> sample=\(file.lastPathComponent) key=\(note) pitch_keycenter=\(note)"
            let lower = name.lowercased()
            if lower.contains("hat") || lower.contains("hh") || lower.contains("ride") {
                // Week 87 — closed/open hat choke: new hit silences prior hat group.
                region += " group=1 off_by=1"
            } else if lower.contains("kick") {
                region += " group=2"
            }
            lines.append(region)
        }

        let destination = outputURL ?? folder.appendingPathComponent("generated.sfz")
        do {
            try lines.joined(separator: "\n").write(to: destination,
                                                    atomically: true,
                                                    encoding: .utf8)
        } catch {
            throw MXAudioError.sfzParseFailed(reason: "could not write generated mapping: \(error.localizedDescription)",
                                              line: 0)
        }
        return destination
    }

    /// Finds a trailing note name (`piano_C4`) or MIDI number (`kick_36`).
    static func inferredNote(from name: String) -> UInt8? {
        let separators = CharacterSet(charactersIn: "-_ .")
        let components = name.components(separatedBy: separators).filter { !$0.isEmpty }
        for component in components.reversed() {
            if let value = Int(component), (0...127).contains(value) {
                return UInt8(value)
            }
            if let note = MXSFZParser.midiNote(fromName: component) {
                return note
            }
        }
        return nil
    }
}
