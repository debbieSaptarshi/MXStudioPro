import AVFoundation
import CoreGraphics
import Foundation
import MXStudioEngine
import UIKit

/// CapCut / Instagram Reels lite: bounce audio → vertical 9:16 MP4 with brand gradient + title.
///
/// Offline only — no network upload. Video is a still gradient (one drawn buffer reused).
public enum StudioReelsVideoExporter {
    public struct Options: Sendable {
        public var size: MXReelsVideoGeometry.Size
        public var fps: Double
        public var title: String
        public var includeTitle: Bool
        /// Animated waveform bars + playhead (Week 84). Set false for still-frame regression.
        public var includeWaveform: Bool

        public init(
            size: MXReelsVideoGeometry.Size = .reels720,
            fps: Double = MXReelsVideoGeometry.defaultFPS,
            title: String,
            includeTitle: Bool = true,
            includeWaveform: Bool = true
        ) {
            self.size = size
            self.fps = max(1, fps)
            self.title = title
            self.includeTitle = includeTitle
            self.includeWaveform = includeWaveform
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

        let waveformPeaks: MXReelsWaveform.Peaks?
        if options.includeWaveform {
            waveformPeaks = try? loadWaveformPeaks(from: audioURL)
        } else {
            waveformPeaks = nil
        }

        let timescale: CMTimeScale = 600
        for frameIndex in 0..<frames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let pts = CMTime(
                seconds: MXReelsVideoGeometry.presentationTime(frame: frameIndex, fps: fps),
                preferredTimescale: timescale
            )
            let pixelBuffer = try makeFrame(
                size: size,
                title: options.includeTitle ? options.title : "",
                waveform: waveformPeaks,
                frameIndex: frameIndex,
                frameCount: frames
            )
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

    // MARK: - Frame

    private static func loadWaveformPeaks(from audioURL: URL) throws -> MXReelsWaveform.Peaks {
        let file = try AVAudioFile(forReading: audioURL)
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else {
            return MXReelsWaveform.peaks(mono: [])
        }
        try file.read(into: buffer)
        let channels = Int(buffer.format.channelCount)
        let n = Int(buffer.frameLength)
        guard let data = buffer.floatChannelData, n > 0 else {
            return MXReelsWaveform.peaks(mono: [])
        }
        var mono = [Float](repeating: 0, count: n)
        if channels >= 2 {
            for i in 0..<n {
                mono[i] = 0.5 * (data[0][i] + data[1][i])
            }
        } else {
            for i in 0..<n { mono[i] = data[0][i] }
        }
        return MXReelsWaveform.peaks(mono: mono)
    }

    private static func makeFrame(
        size: MXReelsVideoGeometry.Size,
        title: String,
        waveform: MXReelsWaveform.Peaks?,
        frameIndex: Int,
        frameCount: Int
    ) throws -> CVPixelBuffer {
        let playheadFraction = MXReelsWaveform.playheadFraction(
            frameIndex: frameIndex,
            frameCount: frameCount
        )
        let playheadBar = waveform.map {
            MXReelsWaveform.playheadBarIndex(fraction: playheadFraction, barCount: $0.barCount)
        }

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

            if let waveform {
                drawWaveform(
                    in: cg,
                    size: size,
                    peaks: waveform,
                    playheadBar: playheadBar ?? 0
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
            guard !trimmed.isEmpty else { return }
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

        guard let cgImage = image.cgImage else {
            throw VideoError.writerFailed("Could not render frame")
        }
        return try pixelBuffer(from: cgImage, size: size)
    }

    private static func drawWaveform(
        in cg: CGContext,
        size: MXReelsVideoGeometry.Size,
        peaks: MXReelsWaveform.Peaks,
        playheadBar: Int
    ) {
        let barCount = peaks.barCount
        guard barCount > 0 else { return }

        let marginX: CGFloat = 48
        let bottomY = CGFloat(size.height) * 0.78
        let maxBarHeight = CGFloat(size.height) * 0.22
        let totalWidth = CGFloat(size.width) - marginX * 2
        let gap: CGFloat = 2
        let barWidth = max(2, (totalWidth - gap * CGFloat(barCount - 1)) / CGFloat(barCount))

        for (index, amp) in peaks.bars.enumerated() {
            let x = marginX + CGFloat(index) * (barWidth + gap)
            let h = max(4, CGFloat(amp) * maxBarHeight)
            let rect = CGRect(x: x, y: bottomY - h, width: barWidth, height: h)
            let isPast = index <= playheadBar
            cg.setFillColor(
                isPast
                    ? UIColor(red: 0.95, green: 0.45, blue: 0.12, alpha: 0.95).cgColor
                    : UIColor.white.withAlphaComponent(0.35).cgColor
            )
            cg.fill(rect)
        }

        let playX = marginX + CGFloat(playheadBar) * (barWidth + gap) + barWidth * 0.5
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        cg.setLineWidth(2)
        cg.move(to: CGPoint(x: playX, y: bottomY - maxBarHeight - 8))
        cg.addLine(to: CGPoint(x: playX, y: bottomY + 6))
        cg.strokePath()
    }

    private static func pixelBuffer(from cgImage: CGImage, size: MXReelsVideoGeometry.Size) throws -> CVPixelBuffer {
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
