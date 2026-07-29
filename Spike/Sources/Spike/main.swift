import AVFoundation
import AudioKit
import SoundpipeAudioKit
import Foundation

// Spike goal: prove an AudioKit Node can be attached to an AVAudioEngine that
// WE own, rather than one AudioKit's own Engine type manages. If this holds,
// the hybrid seam in the architecture is viable.

var failures: [String] = []

func check(_ label: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(label)")
    if !condition { failures.append(label) }
}

// ---------------------------------------------------------------------------
// 1. AudioKit node vends a plain AVAudioNode
// ---------------------------------------------------------------------------
let osc = DynamicOscillator()
let akNode: AVAudioNode = osc.avAudioNode
check("AudioKit DynamicOscillator vends AVAudioNode (\(type(of: akNode)))", true)

// ---------------------------------------------------------------------------
// 2. Attach that node to an engine we own and render offline
// ---------------------------------------------------------------------------
let engine = AVAudioEngine()
let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

engine.attach(akNode)
engine.connect(akNode, to: engine.mainMixerNode, format: format)

var attached = false
do {
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    attached = engine.isRunning
} catch {
    print("engine start error: \(error)")
}
check("Owned AVAudioEngine starts with AudioKit node attached", attached)

// ---------------------------------------------------------------------------
// 3. Render and confirm the AudioKit DSP actually produced signal
// ---------------------------------------------------------------------------
osc.frequency = 440
osc.amplitude = 0.5
osc.start()

let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                              frameCapacity: engine.manualRenderingMaximumFrameCount)!
var peak: Float = 0
var framesRendered: AVAudioFrameCount = 0
let target: AVAudioFrameCount = 48_000

while framesRendered < target {
    let frames = min(buffer.frameCapacity, target - framesRendered)
    do {
        let status = try engine.renderOffline(frames, to: buffer)
        guard status == .success else { break }
    } catch {
        print("render error: \(error)")
        break
    }
    if let ch = buffer.floatChannelData {
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(ch[0][i]))
        }
    }
    framesRendered += buffer.frameLength
    if buffer.frameLength == 0 { break }
}

check("AudioKit DSP renders non-silent audio through owned engine (peak=\(peak))", peak > 0.01)

engine.stop()

// ---------------------------------------------------------------------------
// 4. Apple's system DLS soundbank is loadable via AVAudioUnitSampler
// ---------------------------------------------------------------------------
let dls = URL(fileURLWithPath:
    "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
check("System DLS soundbank exists", FileManager.default.fileExists(atPath: dls.path))

let engine2 = AVAudioEngine()
let sampler = AVAudioUnitSampler()
engine2.attach(sampler)
engine2.connect(sampler, to: engine2.mainMixerNode, format: format)

var samplerLoaded = false
var samplerPeak: Float = 0
do {
    try engine2.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine2.start()
    try sampler.loadSoundBankInstrument(
        at: dls, program: 0,
        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8(kAUSampler_DefaultBankLSB))
    samplerLoaded = true

    sampler.startNote(60, withVelocity: 100, onChannel: 0)
    let buf2 = AVAudioPCMBuffer(pcmFormat: engine2.manualRenderingFormat,
                                frameCapacity: engine2.manualRenderingMaximumFrameCount)!
    var rendered: AVAudioFrameCount = 0
    while rendered < 48_000 {
        let frames = min(buf2.frameCapacity, 48_000 - rendered)
        let status = try engine2.renderOffline(frames, to: buf2)
        guard status == .success else { break }
        if let ch = buf2.floatChannelData {
            for i in 0..<Int(buf2.frameLength) { samplerPeak = max(samplerPeak, abs(ch[0][i])) }
        }
        rendered += buf2.frameLength
        if buf2.frameLength == 0 { break }
    }
} catch {
    print("sampler error: \(error)")
}
engine2.stop()

check("AVAudioUnitSampler loads system DLS", samplerLoaded)
check("AVAudioUnitSampler renders note (peak=\(samplerPeak))", samplerPeak > 0.001)

// ---------------------------------------------------------------------------
print("")
if failures.isEmpty {
    print("SPIKE RESULT: all checks passed - hybrid seam is viable")
} else {
    print("SPIKE RESULT: \(failures.count) failure(s): \(failures)")
}
