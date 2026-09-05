import AVFoundation
import CoreGraphics
import Foundation
import MXStudioEngine
import UIKit

/// CapCut / Instagram Reels lite: bounce audio → vertical 9:16 MP4 with brand gradient,
/// title, and animated waveform + playhead (Week 84).
public enum StudioReelsVideoExporter {
    public struct Options: Sendable {
        public var size: MXReelsVideoGeometry.Size
        public var fps: Double
        public var title: String
        public var includeTitle: Bool
        public var includeWaveform: Bool
        public var waveformBarCount: Int
        public var visibleBarCount: Int

        public init(
            size: MXReelsVideoGeometry.Size = .reels720,
            fps: Double = MXReelsVideoGeometry.defaultFPS,
            title: String,
            includeTitle: Bool = true,
            includeWaveform: Bool = true,
            waveformBarCount: Int = MXReelsWaveform.defaultBarCount,
            visibleBarCount: Int = MXReelsWaveform.defaultVisibleBars
        ) {
            self.size = size
            self.fps = max(1, fps)
            self.title = title
            self.includeTitle = includeTitle
            self.includeWaveform = includeWaveform
            self.waveformBarCount = max(16, waveformBarCount)
            self.visibleBarCount = max(8, visibleBarCount)
        }
    }

    public struct Result: Sendable {
        public var mp4URL: URL
        public var durationSeconds: Double
        public var size: MXReelsVideoGeometry.Size
        public var frameCount: Int
    }

    public enum VideoError: LocalizedError {
        case invalidSize
        case noAudio
        case writerFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidSize:
                return "Reels video size must be even (H.264)."
            case .noAudio:
                return "No bounced audio to mux into Reels video."
            case .writerFailed(let message):
                return message
            }
        }
    }

    /// Mux `audioURL` (WAV/M4A) into a vertical MP4 under `outputDirectory`.
    public static func export(
        audioURL: URL,
        outputDirectory: URL,
        baseName: String,
        options: Options
    ) async throws -> Result {
        guard MXReelsVideoGeometry.isValidEvenSize(options.size) else {
            throw VideoError.invalidSize
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw VideoError.noAudio
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let safeBase = baseName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = safeBase.isEmpty ? "MXStudio-Reels" : safeBase
        let outURL = outputDirectory.appendingPathComponent("\(name)-reels.mp4")
        try? FileManager.default.removeItem(at: outURL)

        let audioAsset = AVURLAsset(url: audioURL)
        let cmDuration = try await audioAsset.load(.duration)
        let audioDuration = CMTimeGetSeconds(cmDuration)
        let duration = MXReelsVideoGeometry.clampedDuration(
            audioDuration.isFinite && audioDuration > 0 ? audioDuration : 0
        )
        guard duration > 0 else { throw VideoError.noAudio }

        let frames = MXReelsVideoGeometry.frameCount(durationSeconds: duration, fps: options.fps)
        let fps = options.fps
        let size = options.size

        let waveformPeaks: [Float]
        if options.includeWaveform {
            let mono = try readMonoPCM(from: audioURL)
            let raw = MXReelsWaveform.peaks(mono: mono, barCount: options.waveformBarCount)
            waveformPeaks = MXReelsWaveform.normalizedPeaks(raw)
        } else {
            waveformPeaks = []
        }

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttrs
        )
        guard writer.canAdd(videoInput) else {
            throw VideoError.writerFailed("Cannot add video input")
        }
        writer.add(videoInput)

        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw VideoError.noAudio
        }
        let audioReader = try AVAssetReader(asset: audioAsset)
        let audioReaderOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        audioReaderOutput.alwaysCopiesSampleData = false
        guard audioReader.canAdd(audioReaderOutput) else {
            throw VideoError.writerFailed("Cannot read audio track")
        }
        audioReader.add(audioReaderOutput)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 160_000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(audioInput) else {
            throw VideoError.writerFailed("Cannot add audio input")
        }
        writer.add(audioInput)

        guard writer.startWriting() else {
            throw VideoError.writerFailed(writer.error?.localizedDescription ?? "Writer failed to start")
        }
        audioReader.startReading()
        writer.startSession(atSourceTime: .zero)

        let timescale: CMTimeScale = 600
        for frameIndex in 0..<frames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let presentationSeconds = MXReelsVideoGeometry.presentationTime(frame: frameIndex, fps: fps)
            let progress = MXReelsWaveform.playheadProgress(
                presentationSeconds: presentationSeconds,
                durationSeconds: duration
            )
            let pixelBuffer = try makeFrame(
                size: size,
                title: options.includeTitle ? options.title : "",
                peaks: waveformPeaks,
                playheadProgress: progress,
                includeWaveform: options.includeWaveform,
                visibleBarCount: options.visibleBarCount
            )
            let pts = CMTime(seconds: presentationSeconds, preferredTimescale: timescale)
            if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                throw VideoError.writerFailed(writer.error?.localizedDescription ?? "Failed appending video frame")
            }
        }
        videoInput.markAsFinished()

        while audioReader.status == .reading {
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            if let sample = audioReaderOutput.copyNextSampleBuffer() {
                let samplePTS = CMSampleBufferGetPresentationTimeStamp(sample)
                if CMTimeGetSeconds(samplePTS) > duration + 0.05 {
                    break
                }
                if !audioInput.append(sample) {
                    throw VideoError.writerFailed(writer.error?.localizedDescription ?? "Failed appending audio")
                }
            } else {
                break
            }
        }
        audioInput.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }
        guard writer.status == .completed else {
            throw VideoError.writerFailed(writer.error?.localizedDescription ?? "Finish writing failed")
        }

        return Result(
            mp4URL: outURL,
            durationSeconds: duration,
            size: size,
            frameCount: frames
        )
    }

    // MARK: - PCM decode

    private static func readMonoPCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            return []
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return [] }
        let channels = Int(buffer.format.channelCount)
        let count = Int(buffer.frameLength)
        guard count > 0 else { return [] }
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: data[0], count: count))
        }
        var mono = [Float](repeating: 0, count: count)
        for ch in 0..<channels {
            let channel = data[ch]
            for i in 0..<count {
                mono[i] += channel[i]
            }
        }
        let scale = 1 / Float(channels)
        for i in 0..<count { mono[i] *= scale }
        return mono
    }

    // MARK: - Frame

    private static func makeFrame(
        size: MXReelsVideoGeometry.Size,
        title: String,
        peaks: [Float],
        playheadProgress: Double,
        includeWaveform: Bool,
        visibleBarCount: Int
    ) throws -> CVPixelBuffer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: size.width, height: size.height),
            format: format
        )
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.06, green: 0.08, blue: 0.10, alpha: 1).cgColor,
                UIColor(red: 0.08, green: 0.28, blue: 0.32, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let maxWidth = CGFloat(size.width) - 80

            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
                .paragraphStyle: paragraph,
            ]
            ("MXStudio Pro" as NSString).draw(
                in: CGRect(x: 40, y: CGFloat(size.height) * 0.12, width: maxWidth, height: 28),
                withAttributes: brandAttrs
            )

            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 42, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                ]
                let ns = trimmed as NSString
                let bounding = ns.boundingRect(
                    with: CGSize(width: maxWidth, height: 400),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                let textRect = CGRect(
                    x: 40,
                    y: CGFloat(size.height) * 0.42 - bounding.height * 0.5,
                    width: maxWidth,
                    height: ceil(bounding.height)
                )
                ns.draw(in: textRect, withAttributes: attrs)
            }

            guard includeWaveform, !peaks.isEmpty else { return }

            let trackY = CGFloat(size.height) * 0.62
            let trackH = CGFloat(size.height) * 0.16
            let margin: CGFloat = 48
            let trackW = CGFloat(size.width) - margin * 2
            let center = MXReelsWaveform.centerBar(progress: playheadProgress, totalBars: peaks.count)
            let range = MXReelsWaveform.visibleBarRange(
                totalBars: peaks.count,
                visibleBars: visibleBarCount,
                centerBar: center
            )
            let layout = MXReelsWaveform.barLayout(peaks: peaks, visibleRange: range, maxHeight: 1)
            let barW = max(2, trackW / CGFloat(max(1, layout.count)))
            let playheadX = margin + CGFloat(MXReelsWaveform.playheadX(progress: playheadProgress)) * trackW

            for bar in layout {
                let x = margin + CGFloat(bar.x) * trackW - barW * 0.5
                let h = CGFloat(bar.height) * trackH
                let y = trackY + (trackH - h) * 0.5
                let played = x + barW * 0.5 <= playheadX
                let alpha: CGFloat = played ? 0.92 : 0.38
                cg.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                cg.fill(CGRect(x: x, y: y, width: barW * 0.85, height: max(2, h)))
            }

            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: playheadX, y: trackY - 4))
            cg.addLine(to: CGPoint(x: playheadX, y: trackY + trackH + 4))
            cg.strokePath()
        }

        guard let cgImage = image.cgImage else {
            throw VideoError.writerFailed("Could not render frame")
        }
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size.width,
            size.height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw VideoError.writerFailed("Could not create pixel buffer")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw VideoError.writerFailed("Pixel buffer has no base address")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: base,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw VideoError.writerFailed("Could not create pixel context")
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return pixelBuffer
    }
}
