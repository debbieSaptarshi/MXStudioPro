import AVFoundation
import Foundation
import MXAudioDSP

/// Click track driven straight off the tempo map.
///
/// Beat sample positions are precomputed on the control thread into a fixed
/// array; the render block only scans that array and writes click envelopes at
/// exact frame offsets. That keeps the tempo-map lock off the audio thread and
/// makes offline renders bit-identical run to run, which is what scenario T-06
/// (onset spacing within ±1 sample) needs.
public final class MXMetronome: @unchecked Sendable {

    private struct Click {
        var sample: Int64
        var isDownbeat: Bool
    }

    public private(set) var node: AVAudioSourceNode!

    private let transport: MXTransport
    private var sampleRate: Double

    private let scheduleCapacity = 4096
    private let schedule: UnsafeMutablePointer<Click>
    private var scheduleCount = 0
    private let scheduleLock = NSLock()

    /// Sample counter owned by the render thread; reset on transport start.
    private var renderCursor: Int64 = 0
    private var pendingCursorReset: Int64?

    /// Active click voices. Two is enough headroom for overlapping decays.
    private var voicePhase: [Double] = [0, 0]
    private var voiceEnvelope: [Float] = [0, 0]
    private var voiceFrequency: [Float] = [0, 0]
    private var nextVoice = 0

    public var isEnabled: Bool = false
    public var level: Float = 0.6
    public var accentDownbeat: Bool = true

    public var downbeatFrequency: Float = 1_760
    public var beatFrequency: Float = 1_174
    public var clickDecaySeconds: Float = 0.035

    public init(transport: MXTransport, sampleRate: Double = 48_000) {
        self.transport = transport
        self.sampleRate = sampleRate
        schedule = .allocate(capacity: scheduleCapacity)
        schedule.initialize(repeating: Click(sample: 0, isDownbeat: false),
                            count: scheduleCapacity)

        node = AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                                       channels: 2)!) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            return self.render(frameCount: Int(frameCount), into: audioBufferList)
        }
    }

    deinit {
        schedule.deinitialize(count: scheduleCapacity)
        schedule.deallocate()
    }

    public func setSampleRate(_ rate: Double) {
        sampleRate = rate
    }

    /// Precomputes click positions covering `beats` beats from `startSample`.
    public func prepareSchedule(fromSample startSample: Int64, beats: Int = 512) {
        let map = transport.tempoMap
        let startBeat = map.beat(forSample: startSample, sampleRate: sampleRate)
        var beat = ceil(startBeat - 1e-9)

        scheduleLock.lock()
        var count = 0
        while count < min(beats, scheduleCapacity) {
            let sample = map.sample(forBeat: beat, sampleRate: sampleRate)
            let position = map.position(forBeat: beat)
            schedule[count] = Click(sample: sample, isDownbeat: position.beat == 1)
            count += 1
            beat += 1
        }
        scheduleCount = count
        scheduleLock.unlock()

        pendingCursorReset = startSample
    }

    /// Aligns the render cursor with a transport seek.
    public func resetCursor(toSample sample: Int64) {
        pendingCursorReset = sample
    }

    private func render(frameCount: Int, into audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in buffers {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }

        if let reset = pendingCursorReset {
            renderCursor = reset
            pendingCursorReset = nil
            for i in voiceEnvelope.indices { voiceEnvelope[i] = 0 }
        }

        guard isEnabled else {
            // The transport still moves while the click is off, so the cursor
            // has to keep up or re-enabling would fire a burst of stale clicks.
            if transport.isPlaying { renderCursor += Int64(frameCount) }
            return noErr
        }

        let blockStart = renderCursor
        let blockEnd = blockStart + Int64(frameCount)

        // Trigger any clicks that land inside this block.
        if transport.isPlaying {
            scheduleLock.lock()
            let count = scheduleCount
            for i in 0..<count {
                let click = schedule[i]
                guard click.sample >= blockStart, click.sample < blockEnd else { continue }
                let voice = nextVoice
                nextVoice = (nextVoice + 1) % voiceEnvelope.count
                voicePhase[voice] = 0
                voiceEnvelope[voice] = 1
                voiceFrequency[voice] = (accentDownbeat && click.isDownbeat)
                    ? downbeatFrequency
                    : beatFrequency
                // Offset is applied by advancing the voice below.
                pendingOffsets[voice] = Int(click.sample - blockStart)
            }
            scheduleLock.unlock()
        }

        let decay = exp(-1.0 / (Double(clickDecaySeconds) * sampleRate))

        for v in voiceEnvelope.indices {
            guard voiceEnvelope[v] > 0.0001 else { continue }
            let startOffset = pendingOffsets[v]
            pendingOffsets[v] = 0
            let increment = Double(voiceFrequency[v]) / sampleRate

            for frame in startOffset..<frameCount {
                let value = Float(sin(2 * Double.pi * voicePhase[v])) * voiceEnvelope[v] * level
                voicePhase[v] += increment
                if voicePhase[v] >= 1 { voicePhase[v] -= 1 }
                voiceEnvelope[v] *= Float(decay)

                for buffer in buffers {
                    let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                    data[frame] += value
                }
                if voiceEnvelope[v] <= 0.0001 { break }
            }
        }

        if transport.isPlaying {
            renderCursor = blockEnd
        }
        return noErr
    }

    private var pendingOffsets: [Int] = [0, 0]
}
