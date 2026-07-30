import MetalKit
import SwiftUI

/// Metal-backed scrolling live waveform for record / monitor.
struct MetalLiveWaveformView: UIViewRepresentable {
    var level: Float
    var isActive: Bool
    var isClipping: Bool = false
    /// 0…1 metronome / count-in accent so silent takes still animate.
    var beatPulse: Float = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator

        if let device = MTLCreateSystemDefaultDevice() {
            view.device = device
            context.coordinator.setup(device: device, view: view)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.currentLevel = max(0, min(level, 1.25))
        context.coordinator.isActive = isActive
        context.coordinator.isClipping = isClipping
        context.coordinator.beatPulse = max(0, min(beatPulse, 1))
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private static let sampleCount = 256

        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var uniformBuffer: MTLBuffer?
        private var amplitudeBuffer: MTLBuffer?

        private var amplitudes = [Float](repeating: 0.08, count: sampleCount)
        private var writeIndex = 0
        private var lastSampleTime = CACurrentMediaTime()
        private var phase: Float = 0
        private var startTime = CACurrentMediaTime()

        var currentLevel: Float = 0
        var isActive = false
        var isClipping = false
        var beatPulse: Float = 0

        func setup(device: MTLDevice, view: MTKView) {
            self.device = device
            commandQueue = device.makeCommandQueue()

            uniformBuffer = device.makeBuffer(
                length: MemoryLayout<WaveUniforms>.stride,
                options: .storageModeShared
            )
            amplitudeBuffer = device.makeBuffer(
                length: MemoryLayout<Float>.stride * Self.sampleCount,
                options: .storageModeShared
            )

            // Seed a pleasant starter envelope so first frame isn’t empty.
            for i in 0..<Self.sampleCount {
                let x = Float(i) / Float(Self.sampleCount)
                amplitudes[i] = 0.12 + 0.18 * abs(sinf(x * 18)) * abs(cosf(x * 7))
            }

            guard
                let library = device.makeDefaultLibrary(),
                let vertex = library.makeFunction(name: "wave_vertex"),
                let fragment = library.makeFunction(name: "wave_fragment")
            else {
                return
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }

        /// Advance the scrolling ring from the render loop (~100 Hz writes).
        private func advanceHistoryIfNeeded() {
            let now = CACurrentMediaTime()
            let interval = isActive ? 1.0 / 100.0 : 1.0 / 36.0
            guard now - lastSampleTime >= interval else { return }
            lastSampleTime = now
            phase += 0.41

            let mic = powf(currentLevel, 0.55) * 1.35
            // Procedural “signal” so silent / simulator still looks like audio.
            let a = abs(sinf(phase * 1.3))
            let b = abs(sinf(phase * 2.7 + 0.4))
            let c = abs(cosf(phase * 0.55))
            let procedural = (0.22 * a + 0.35 * b * b + 0.18 * c) * (isActive ? 1.0 : 0.55)
            let pulse = beatPulse * (0.45 + 0.4 * abs(sinf(phase * 2.1)))
            var shaped = max(mic, procedural * max(0.35, mic * 0.8 + 0.25), pulse)
            // Occasional transient spikes like consonants / picks.
            if abs(sinf(phase * 0.17)) > 0.97 {
                shaped = min(1, shaped + 0.35 + 0.25 * mic)
            }
            shaped = min(max(shaped, 0.05), 1)

            let n = Self.sampleCount
            amplitudes[writeIndex % n] = shaped
            amplitudes[(writeIndex + n - 1) % n] = max(
                amplitudes[(writeIndex + n - 1) % n] * 0.78,
                shaped * 0.7
            )
            writeIndex += 1
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            advanceHistoryIfNeeded()

            guard
                let pipeline,
                let commandQueue,
                let drawable = view.currentDrawable,
                let pass = view.currentRenderPassDescriptor,
                let uniformBuffer,
                let amplitudeBuffer,
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            else {
                return
            }

            var ordered = [Float](repeating: 0, count: Self.sampleCount)
            for i in 0..<Self.sampleCount {
                ordered[i] = amplitudes[(writeIndex + i) % Self.sampleCount]
            }
            memcpy(
                amplitudeBuffer.contents(),
                ordered,
                MemoryLayout<Float>.stride * Self.sampleCount
            )

            var uniforms = WaveUniforms(
                time: Float(CACurrentMediaTime() - startTime),
                level: currentLevel,
                clipping: isClipping ? 1 : 0,
                active: isActive ? 1 : 0,
                sampleCount: Float(Self.sampleCount),
                resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                _pad: 0
            )
            memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<WaveUniforms>.stride)

            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            encoder.setFragmentBuffer(amplitudeBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

/// Must match `WaveUniforms` in `MetalWaveform.metal`.
private struct WaveUniforms {
    var time: Float
    var level: Float
    var clipping: Float
    var active: Float
    var sampleCount: Float
    var resolution: SIMD2<Float>
    var _pad: Float
}
