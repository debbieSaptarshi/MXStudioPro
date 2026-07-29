import AVFoundation
import Foundation

/// Immutable decoded audio owned by the store. Voices read it through an
/// `UnsafePointer`, so the store must keep it alive for as long as any voice
/// references it.
public final class MXSampleBuffer: @unchecked Sendable {
    public let frameCount: Int
    public let channelCount: Int
    public let sampleRate: Double
    /// Frames actually decoded so far. Equal to `frameCount` once promoted.
    public private(set) var residentFrames: Int
    public private(set) var isFullyResident: Bool

    /// Deinterleaved, channel-major.
    fileprivate let storage: UnsafeMutablePointer<Float>

    init(frameCount: Int, channelCount: Int, sampleRate: Double) {
        self.frameCount = frameCount
        self.channelCount = max(1, channelCount)
        self.sampleRate = sampleRate
        self.residentFrames = 0
        self.isFullyResident = false
        storage = .allocate(capacity: frameCount * self.channelCount)
        storage.initialize(repeating: 0, count: frameCount * self.channelCount)
    }

    deinit {
        storage.deinitialize(count: frameCount * channelCount)
        storage.deallocate()
    }

    public var byteCount: Int {
        frameCount * channelCount * MemoryLayout<Float>.size
    }

    /// Render-thread read. Out-of-range indices return silence rather than
    /// trapping, because a voice can outrun the resident window mid-block.
    @inline(__always)
    public func sample(frame: Int, channel: Int) -> Float {
        guard frame >= 0, frame < residentFrames else { return 0 }
        let ch = min(channel, channelCount - 1)
        return storage[ch * frameCount + frame]
    }

    fileprivate func write(from buffer: AVAudioPCMBuffer, atFrame offset: Int) {
        guard let src = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let srcChannels = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            let source = src[min(ch, srcChannels - 1)]
            let dest = storage + ch * frameCount + offset
            let count = min(frames, frameCount - offset)
            if count > 0 { dest.update(from: source, count: count) }
        }
    }

    fileprivate func markResident(frames: Int) {
        residentFrames = min(frames, frameCount)
        isFullyResident = residentFrames >= frameCount
    }
}

/// Decodes samples, keeps memory bounded, and promotes hot samples to fully
/// resident in the background.
///
/// Strategy: decode a preload window synchronously so a voice can start
/// immediately, then promote the remainder off-thread. An LRU eviction pass
/// keeps total residency under `budgetBytes`, which is what keeps a large kit
/// inside the AUv3 extension's memory limit (plan scenario SFZ-03).
public final class MXSampleStore: @unchecked Sendable {
    public struct Statistics: Sendable {
        public var residentBytes: Int
        public var sampleCount: Int
        public var fullyResidentCount: Int
        public var evictionCount: Int
    }

    private struct Entry {
        var buffer: MXSampleBuffer
        var lastUsed: UInt64
        var url: URL
    }

    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private var evictionCount = 0
    private let lock = NSLock()
    private let promotionQueue = DispatchQueue(label: "com.mxstudio.samplestore.promote",
                                               qos: .utility)

    /// Frames decoded synchronously on first request.
    public let preloadFrames: Int
    /// Samples at or under this size skip streaming entirely.
    public let fullLoadThresholdBytes: Int
    public private(set) var budgetBytes: Int

    public init(budgetBytes: Int = 96 * 1024 * 1024,
                preloadFrames: Int = 48_000,
                fullLoadThresholdBytes: Int = 2 * 1024 * 1024) {
        self.budgetBytes = budgetBytes
        self.preloadFrames = preloadFrames
        self.fullLoadThresholdBytes = fullLoadThresholdBytes
    }

    public func setBudget(_ bytes: Int) {
        lock.lock()
        budgetBytes = bytes
        lock.unlock()
        enforceBudget()
    }

    public func statistics() -> Statistics {
        lock.lock()
        defer { lock.unlock() }
        let resident = entries.values.reduce(0) {
            $0 + $1.buffer.residentFrames * $1.buffer.channelCount * MemoryLayout<Float>.size
        }
        return Statistics(residentBytes: resident,
                          sampleCount: entries.count,
                          fullyResidentCount: entries.values.filter { $0.buffer.isFullyResident }.count,
                          evictionCount: evictionCount)
    }

    /// Decodes the preload window synchronously and schedules full promotion.
    @discardableResult
    public func load(url: URL) throws -> MXSampleBuffer {
        let key = url.standardizedFileURL.path

        lock.lock()
        if let existing = entries[key] {
            clock &+= 1
            entries[key]?.lastUsed = clock
            lock.unlock()
            return existing.buffer
        }
        lock.unlock()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MXAudioError.resourceNotFound(path: url.path)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw MXAudioError.sampleDecodeFailed(path: url.path,
                                                  underlying: error.localizedDescription)
        }

        let totalFrames = Int(file.length)
        guard totalFrames > 0 else {
            throw MXAudioError.sampleDecodeFailed(path: url.path, underlying: "zero-length file")
        }

        let channels = Int(file.processingFormat.channelCount)
        let buffer = MXSampleBuffer(frameCount: totalFrames,
                                    channelCount: channels,
                                    sampleRate: file.processingFormat.sampleRate)

        let wantsFullLoad = buffer.byteCount <= fullLoadThresholdBytes
        let firstChunk = wantsFullLoad ? totalFrames : min(preloadFrames, totalFrames)
        try decode(file: file, into: buffer, startFrame: 0, frameCount: firstChunk, url: url)
        buffer.markResident(frames: firstChunk)

        lock.lock()
        clock &+= 1
        entries[key] = Entry(buffer: buffer, lastUsed: clock, url: url)
        lock.unlock()

        if !buffer.isFullyResident {
            promotionQueue.async { [weak self] in
                self?.promote(buffer: buffer, url: url)
            }
        }

        enforceBudget()
        return buffer
    }

    /// Blocks until a sample is fully decoded. Tests use this to remove the
    /// race between promotion and assertions.
    public func loadFully(url: URL) throws -> MXSampleBuffer {
        let buffer = try load(url: url)
        if !buffer.isFullyResident {
            promote(buffer: buffer, url: url)
        }
        return buffer
    }

    public func purgeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    /// Frees samples not referenced elsewhere. Called on memory pressure from
    /// the control thread, never from the render thread.
    public func evictUnused(keeping retained: Set<String> = []) {
        lock.lock()
        let candidates = entries
            .filter { !retained.contains($0.key) && isKnownUniquelyReferenced(&entries[$0.key]!.buffer) == false }
            .sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, _) in candidates {
            entries.removeValue(forKey: key)
            evictionCount += 1
        }
        lock.unlock()
    }

    // MARK: - Private

    private func promote(buffer: MXSampleBuffer, url: URL) {
        guard !buffer.isFullyResident else { return }
        do {
            let file = try AVAudioFile(forReading: url)
            let start = buffer.residentFrames
            let remaining = buffer.frameCount - start
            guard remaining > 0 else {
                buffer.markResident(frames: buffer.frameCount)
                return
            }
            try decode(file: file, into: buffer, startFrame: start, frameCount: remaining, url: url)
            buffer.markResident(frames: buffer.frameCount)
        } catch {
            // Promotion failure leaves the preload window playable; the voice
            // simply runs out of sample early rather than crashing.
        }
    }

    private func decode(file: AVAudioFile,
                        into buffer: MXSampleBuffer,
                        startFrame: Int,
                        frameCount: Int,
                        url: URL) throws {
        file.framePosition = AVAudioFramePosition(startFrame)
        let chunk: AVAudioFrameCount = 16_384
        guard let scratch = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: chunk) else {
            throw MXAudioError.sampleDecodeFailed(path: url.path,
                                                  underlying: "could not allocate scratch buffer")
        }

        var written = 0
        while written < frameCount {
            let want = AVAudioFrameCount(min(Int(chunk), frameCount - written))
            do {
                try file.read(into: scratch, frameCount: want)
            } catch {
                throw MXAudioError.sampleDecodeFailed(path: url.path,
                                                      underlying: error.localizedDescription)
            }
            if scratch.frameLength == 0 { break }
            buffer.write(from: scratch, atFrame: startFrame + written)
            written += Int(scratch.frameLength)
        }
    }

    private func enforceBudget() {
        lock.lock()
        var resident = entries.values.reduce(0) { $0 + $1.buffer.byteCount }
        guard resident > budgetBytes else {
            lock.unlock()
            return
        }
        let ordered = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, entry) in ordered {
            guard resident > budgetBytes else { break }
            entries.removeValue(forKey: key)
            resident -= entry.buffer.byteCount
            evictionCount += 1
        }
        lock.unlock()
    }
}
