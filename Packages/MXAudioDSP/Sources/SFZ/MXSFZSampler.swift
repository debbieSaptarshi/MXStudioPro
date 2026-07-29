import AVFoundation
import Foundation

/// Native SFZ playback engine.
///
/// Division of labour that keeps the render thread clean:
/// - Control thread does region selection, round-robin advance and choke
///   resolution, then pushes a resolved event into the ring.
/// - Render thread only pops events and mixes voices. It touches no Swift
///   collections, allocates nothing, and holds no locks.
///
/// Sample buffers are retained by the sampler for the lifetime of the loaded
/// instrument and addressed by integer index, so voices never trigger ARC.
public final class MXSFZSampler: MXSFZEngine, @unchecked Sendable {

    // MARK: - Voice

    private struct Voice {
        var bufferIndex: Int = -1
        var position: Double = 0
        var increment: Double = 1
        var envelope = MXEnvelope()
        var gain: Float = 1
        var panLeft: Float = 1
        var panRight: Float = 1
        var loopStart: Int = 0
        var loopEnd: Int = 0
        var loops: Bool = false
        var isOneShot: Bool = false
        var active: Bool = false
    }

    /// Resolved on the control thread so the render thread has no searching to do.
    private struct StartEvent {
        var bufferIndex: Int32 = -1
        var voiceIndex: Int32 = -1
        var increment: Double = 1
        var gain: Float = 1
        var panLeft: Float = 1
        var panRight: Float = 1
        var loopStart: Int32 = 0
        var loopEnd: Int32 = 0
        var loops: Bool = false
        var isOneShot: Bool = false
        var offset: Int32 = 0
        var attack: Float = 0.001
        var decay: Float = 0
        var sustain: Float = 1
        var release: Float = 0.05
        var frameOffset: Int32 = 0
    }

    private enum PendingKind: UInt8 {
        case start, stop, stopAll
    }

    private struct Pending {
        var kind: PendingKind
        var start: StartEvent
        var voiceIndex: Int32
        var frameOffset: Int32
    }

    // MARK: - State

    private let store: MXSampleStore
    private var sampleRate: Double

    private var regions: [MXSFZRegion] = []
    private var buffers: [MXSampleBuffer] = []
    private var regionBufferIndex: [Int] = []
    private var roundRobinCounters: [Int: Int] = [:]

    /// Parameters exposed when this engine is hosted inside an `AUAudioUnit`.
    public let auParameters = MXParameterStore()
    /// The SFZ currently loaded, persisted in AU state instead of the samples.
    public private(set) var loadedURL: URL?

    private let allocator = MXVoiceAllocator(capacity: 32, maxCapacity: 256)
    private var voices: [Voice]
    private let pending: UnsafeMutablePointer<Pending>
    private let pendingCapacity = 512
    private var pendingWrite = 0
    private var pendingRead = 0
    private let pendingLock = NSLock()

    private let controlLock = NSLock()

    public init(sampleRate: Double = 48_000, store: MXSampleStore? = nil) {
        self.sampleRate = sampleRate
        self.store = store ?? MXSampleStore()
        voices = Array(repeating: Voice(), count: 256)
        pending = .allocate(capacity: pendingCapacity)
        pending.initialize(repeating: Pending(kind: .stopAll,
                                              start: StartEvent(),
                                              voiceIndex: -1,
                                              frameOffset: 0),
                           count: pendingCapacity)
        for i in 0..<voices.count {
            voices[i].envelope.setSampleRate(sampleRate)
        }
    }

    deinit {
        pending.deinitialize(count: pendingCapacity)
        pending.deallocate()
    }

    // MARK: - Loading

    public func loadSFZ(url: URL) throws {
        let parser = MXSFZParser()
        let result = try parser.parse(contentsOf: url)

        let baseDirectory = url.deletingLastPathComponent()
        let root = result.defaultPath.isEmpty
            ? baseDirectory
            : baseDirectory.appendingPathComponent(result.defaultPath)

        var newBuffers: [MXSampleBuffer] = []
        var newIndex: [Int] = []
        var bufferByPath: [String: Int] = [:]

        for region in result.regions {
            let sampleURL = root.appendingPathComponent(region.samplePath).standardizedFileURL
            let key = sampleURL.path
            if let existing = bufferByPath[key] {
                newIndex.append(existing)
                continue
            }
            let buffer = try store.load(url: sampleURL)
            newBuffers.append(buffer)
            let idx = newBuffers.count - 1
            bufferByPath[key] = idx
            newIndex.append(idx)
        }

        controlLock.lock()
        regions = result.regions
        buffers = newBuffers
        regionBufferIndex = newIndex
        roundRobinCounters.removeAll()
        loadedURL = url
        controlLock.unlock()

        allNotesOff()
    }

    public var loadedRegionCount: Int {
        controlLock.lock(); defer { controlLock.unlock() }
        return regions.count
    }

    public var residentBytes: Int {
        store.statistics().residentBytes
    }

    public var activeVoiceCount: Int {
        allocator.activeVoiceCount
    }

    public func setSampleRate(_ rate: Double) {
        controlLock.lock()
        sampleRate = rate
        controlLock.unlock()
        for i in 0..<voices.count {
            voices[i].envelope.setSampleRate(rate)
        }
    }

    public func setPolyphony(_ voicesCount: Int) {
        allocator.setCapacity(voicesCount) { index in
            enqueue(Pending(kind: .stop, start: StartEvent(),
                            voiceIndex: Int32(index), frameOffset: 0))
        }
    }

    // MARK: - Control thread

    public func noteOn(note: UInt8, velocity: UInt8, channel: UInt8, frameOffset: Int) {
        guard velocity > 0 else {
            noteOff(note: note, channel: channel, frameOffset: frameOffset)
            return
        }

        controlLock.lock()
        let localRegions = regions
        let localIndex = regionBufferIndex
        let localBuffers = buffers
        let rrKey = Int(note)
        let counter = roundRobinCounters[rrKey] ?? 0

        var selected: [Int] = []
        var sawSequenced = false
        for (i, region) in localRegions.enumerated() where region.matches(note: note, velocity: velocity) {
            if region.seqLength > 1 { sawSequenced = true }
            if region.matchesSequence(counter: counter) {
                selected.append(i)
            }
        }
        if sawSequenced {
            roundRobinCounters[rrKey] = counter + 1
        }
        let rate = sampleRate
        controlLock.unlock()

        guard !selected.isEmpty else { return }

        for regionIndex in selected {
            let region = localRegions[regionIndex]
            let bufferIndex = localIndex[regionIndex]
            guard bufferIndex >= 0, bufferIndex < localBuffers.count else { continue }
            let buffer = localBuffers[bufferIndex]

            // A region's `off_by` says which group silences it; store that on the
            // voice so a later trigger in that group can find it.
            let voiceIndex = allocator.allocate(note: note,
                                                channel: channel,
                                                chokeGroup: region.offBy)

            // Trigger side: silence anything this region's group chokes.
            if region.group >= 0 {
                allocator.chokeGroup(region.group, excluding: voiceIndex) { victim in
                    enqueue(Pending(kind: .stop, start: StartEvent(),
                                    voiceIndex: Int32(victim),
                                    frameOffset: Int32(frameOffset)))
                }
            }

            let semitones = Double(Int(note) - Int(region.pitchKeyCenter))
                + Double(region.tuneCents) / 100
            let pitchRatio = pow(2.0, semitones / 12.0)
            let rateRatio = buffer.sampleRate / rate

            let velocityGain = Float(velocity) / 127
            let pan = min(max(region.pan, -1), 1)
            let angle = (pan + 1) * 0.25 * Float.pi

            var event = StartEvent()
            event.bufferIndex = Int32(bufferIndex)
            event.voiceIndex = Int32(voiceIndex)
            event.increment = pitchRatio * rateRatio
            event.gain = region.linearGain * velocityGain
            event.panLeft = cos(angle)
            event.panRight = sin(angle)
            event.loopStart = Int32(region.loopStart)
            event.loopEnd = Int32(region.loopEnd > 0 ? region.loopEnd : buffer.frameCount - 1)
            event.loops = region.loopMode == .loopContinuous || region.loopMode == .loopSustain
            event.isOneShot = region.loopMode == .oneShot
            event.offset = Int32(region.offset)
            event.attack = region.ampegAttack
            event.decay = region.ampegDecay
            event.sustain = region.ampegSustain
            event.release = region.ampegRelease
            event.frameOffset = Int32(frameOffset)

            enqueue(Pending(kind: .start, start: event,
                            voiceIndex: Int32(voiceIndex),
                            frameOffset: Int32(frameOffset)))
        }
    }

    public func noteOff(note: UInt8, channel: UInt8, frameOffset: Int) {
        allocator.release(note: note, channel: channel) { index in
            enqueue(Pending(kind: .stop, start: StartEvent(),
                            voiceIndex: Int32(index),
                            frameOffset: Int32(frameOffset)))
        }
    }

    public func allNotesOff() {
        allocator.releaseAll { _ in }
        enqueue(Pending(kind: .stopAll, start: StartEvent(), voiceIndex: -1, frameOffset: 0))
    }

    private func enqueue(_ item: Pending) {
        pendingLock.lock()
        if pendingWrite - pendingRead < pendingCapacity {
            pending[pendingWrite % pendingCapacity] = item
            pendingWrite += 1
        }
        pendingLock.unlock()
    }

    private func dequeueAll(_ body: (Pending) -> Void) {
        pendingLock.lock()
        let write = pendingWrite
        var read = pendingRead
        var drained: [Pending] = []
        drained.reserveCapacity(write - read)
        while read < write {
            drained.append(pending[read % pendingCapacity])
            read += 1
        }
        pendingRead = read
        pendingLock.unlock()
        for item in drained { body(item) }
    }

    // MARK: - Render thread

    public func render(left: UnsafeMutablePointer<Float>,
                       right: UnsafeMutablePointer<Float>,
                       frameCount: Int) {
        for i in 0..<frameCount {
            left[i] = 0
            right[i] = 0
        }

        dequeueAll { item in
            let vi = Int(item.voiceIndex)
            switch item.kind {
            case .start:
                guard vi >= 0, vi < voices.count else { return }
                var v = Voice()
                v.bufferIndex = Int(item.start.bufferIndex)
                v.position = Double(item.start.offset)
                v.increment = item.start.increment
                v.gain = item.start.gain
                v.panLeft = item.start.panLeft
                v.panRight = item.start.panRight
                v.loopStart = Int(item.start.loopStart)
                v.loopEnd = Int(item.start.loopEnd)
                v.loops = item.start.loops
                v.isOneShot = item.start.isOneShot
                v.envelope.setSampleRate(sampleRate)
                v.envelope.attackSeconds = item.start.attack
                v.envelope.decaySeconds = item.start.decay
                v.envelope.sustainLevel = item.start.sustain
                v.envelope.releaseSeconds = item.start.release
                v.envelope.noteOn()
                v.active = true
                voices[vi] = v

            case .stop:
                guard vi >= 0, vi < voices.count, voices[vi].active else { return }
                // A one-shot ignores note-off and plays to its natural end.
                if !voices[vi].isOneShot {
                    voices[vi].envelope.noteOff()
                }

            case .stopAll:
                for j in 0..<voices.count where voices[j].active {
                    voices[j].envelope.noteOff()
                }
            }
        }

        for vi in 0..<voices.count where voices[vi].active {
            let bufferIndex = voices[vi].bufferIndex
            guard bufferIndex >= 0, bufferIndex < buffers.count else {
                voices[vi].active = false
                allocator.recycle(vi)
                continue
            }
            let buffer = buffers[bufferIndex]
            renderVoice(&voices[vi], buffer: buffer,
                        left: left, right: right, frameCount: frameCount)
            if !voices[vi].active {
                allocator.recycle(vi)
            }
        }
    }

    private func renderVoice(_ voice: inout Voice,
                             buffer: MXSampleBuffer,
                             left: UnsafeMutablePointer<Float>,
                             right: UnsafeMutablePointer<Float>,
                             frameCount: Int) {
        let stereo = buffer.channelCount > 1

        for i in 0..<frameCount {
            let env = voice.envelope.next()
            if voice.envelope.stage == .idle {
                voice.active = false
                return
            }

            let pos = voice.position
            let index = Int(pos)
            let resident = buffer.residentFrames

            if index >= resident - 1 {
                if voice.loops, voice.loopEnd > voice.loopStart, voice.loopEnd < resident {
                    voice.position = Double(voice.loopStart)
                    continue
                }
                // Ran past the decoded window or the end of the sample.
                voice.envelope.reset()
                voice.active = false
                return
            }

            let frac = Float(pos - Double(index))
            let l0 = buffer.sample(frame: index, channel: 0)
            let l1 = buffer.sample(frame: index + 1, channel: 0)
            let mono = l0 + (l1 - l0) * frac

            let sampleL = mono
            var sampleR = mono
            if stereo {
                let r0 = buffer.sample(frame: index, channel: 1)
                let r1 = buffer.sample(frame: index + 1, channel: 1)
                sampleR = r0 + (r1 - r0) * frac
            }

            let amp = env * voice.gain
            left[i] += sampleL * amp * voice.panLeft
            right[i] += sampleR * amp * voice.panRight

            voice.position += voice.increment

            if voice.loops, voice.loopEnd > voice.loopStart,
               voice.position >= Double(voice.loopEnd) {
                voice.position = Double(voice.loopStart)
            }
        }
    }
}
