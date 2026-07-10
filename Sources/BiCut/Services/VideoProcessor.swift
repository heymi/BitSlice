import AVFoundation
import CoreMedia
import CoreVideo

// MARK: - Export result

enum ExportResult {
    case completed
    case cancelled
}

// MARK: - Video Processor

final class VideoProcessor {
    private let asset: AVAsset
    private let segment: SegmentInfo
    private let outputURL: URL
    private let config: ExportConfig
    private let needsReencode: Bool

    var onProgress: ((Double) -> Void)?
    private var isCancelled = false

    init(asset: AVAsset, segment: SegmentInfo, outputURL: URL, config: ExportConfig, needsReencode: Bool) {
        self.asset = asset
        self.segment = segment
        self.outputURL = outputURL
        self.config = config
        self.needsReencode = needsReencode
    }

    func cancel() { isCancelled = true }

    // MARK: - Main entry

    func export() async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let tracks = try await asset.load(.tracks)
        guard tracks.first(where: { $0.mediaType == .video }) != nil else {
            throw ExportError.noVideoTrack
        }

        let timeRange = CMTimeRange(start: segment.start, end: segment.end)

        if needsReencode {
            let videoTrack = tracks.first(where: { $0.mediaType == .video })!
            let audioTrack = tracks.first(where: { $0.mediaType == .audio })
            try await exportReencode(videoTrack: videoTrack, audioTrack: audioTrack, timeRange: timeRange)
        } else {
            try await exportPassthrough(timeRange: timeRange)
        }
    }

    // MARK: - Passthrough mode (AVAssetExportSession — most reliable)

    private func exportPassthrough(timeRange: CMTimeRange) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.configurationFailed("无法创建导出会话")
        }
        session.outputURL = outputURL
        session.outputFileType = config.outputFormat.avFileType
        session.timeRange = timeRange

        // Export synchronously (passthrough is fast; progress reported at completion)
        await session.export()

        if isCancelled {
            session.cancelExport()
            throw CancellationError()
        }

        switch session.status {
        case .completed:
            onProgress?(1.0)
        case .failed:
            throw ExportError.writerFailed(session.error?.localizedDescription ?? "导出失败")
        case .cancelled:
            throw CancellationError()
        default:
            throw ExportError.writerFailed("导出异常: \(session.status.rawValue)")
        }
    }

    // MARK: - Re-encode mode (AVAssetReader + Writer, read-all → write-all)

    private func exportReencode(
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        timeRange: CMTimeRange
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange

        let writer = try AVAssetWriter(url: outputURL, fileType: config.outputFormat.avFileType)

        let rawSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize: CGSize = {
            let t = rawSize.applying(transform)
            return CGSize(width: abs(t.width), height: abs(t.height))
        }()

        let originalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let targetSize = effectiveTargetSize(sourceSize: naturalSize)
        let codec = try await deriveCodec(from: videoTrack)

        let videoComposition = buildScalingComposition(
            videoTrack: videoTrack,
            sourceSize: naturalSize,
            targetSize: targetSize,
            frameRate: originalFrameRate
        )

        let decompressSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: decompressSettings
        )
        videoOutput.videoComposition = videoComposition

        let compressSettings: [String: Any] = [
            AVVideoCodecKey: codec.rawValue,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: originalFrameRate,
                AVVideoProfileLevelKey: (codec == .hevc
                    ? kVTProfileLevel_HEVC_Main_AutoLevel as String
                    : kVTProfileLevel_H264_High_AutoLevel as String)
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: compressSettings)
        videoInput.expectsMediaDataInRealTime = false

        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw ExportError.configurationFailed("无法配置视频重编码流")
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        // Audio passthrough
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let at = audioTrack {
            let ao = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
            let afmts = try await at.load(.formatDescriptions) as! [CMFormatDescription]
            let ai: AVAssetWriterInput
            if let afmt = afmts.first {
                ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: afmt)
            } else {
                ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            }
            ai.expectsMediaDataInRealTime = false
            if reader.canAdd(ao), writer.canAdd(ai) {
                reader.add(ao)
                writer.add(ai)
                audioOutput = ao
                audioInput = ai
            }
        }

        let totalDuration = CMTimeGetSeconds(timeRange.duration)
        let estimatedFrames = max(1, Int(totalDuration * Double(max(originalFrameRate, 1))))

        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "未知错误")
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "未知错误")
        }
        writer.startSession(atSourceTime: timeRange.start)

        // Read all decoded video frames (decompressed → won't hang like passthrough)
        var videoSamples: [CMSampleBuffer] = []
        while let sample = videoOutput.copyNextSampleBuffer() {
            if isCancelled { throw CancellationError() }
            videoSamples.append(sample)
        }

        var audioSamples: [CMSampleBuffer] = []
        if let ao = audioOutput {
            while let sample = ao.copyNextSampleBuffer() {
                if isCancelled { throw CancellationError() }
                audioSamples.append(sample)
            }
        }

        // Write video
        var frameCount = 0
        var lastProgressReport = 0
        for sample in videoSamples {
            if isCancelled { throw CancellationError() }
            while !videoInput.isReadyForMoreMediaData {
                if isCancelled { throw CancellationError() }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            videoInput.append(sample)
            frameCount += 1
            if frameCount - lastProgressReport >= 30 {
                onProgress?(min(Double(frameCount) / Double(estimatedFrames), 1.0))
                lastProgressReport = frameCount
            }
        }
        videoInput.markAsFinished()

        // Write audio
        if let ai = audioInput {
            for sample in audioSamples {
                if isCancelled { throw CancellationError() }
                while !ai.isReadyForMoreMediaData {
                    if isCancelled { throw CancellationError() }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                ai.append(sample)
            }
            ai.markAsFinished()
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "写入失败")
        }
    }

    // MARK: - Helpers

    private func effectiveTargetSize(sourceSize: CGSize) -> CGSize {
        guard let targetSize = config.resolution.targetSize else {
            return CGSize(width: abs(sourceSize.width), height: abs(sourceSize.height))
        }
        let sw = abs(sourceSize.width)
        let sh = abs(sourceSize.height)
        let tw = targetSize.width
        let th = targetSize.height
        if sw <= tw, sh <= th { return CGSize(width: sw, height: sh) }
        let scale = min(tw / sw, th / sh)
        return CGSize(width: round(sw * scale), height: round(sh * scale))
    }

    private func buildScalingComposition(
        videoTrack: AVAssetTrack,
        sourceSize: CGSize,
        targetSize: CGSize,
        frameRate: Float
    ) -> AVMutableVideoComposition {
        let comp = AVMutableVideoComposition()
        comp.renderSize = targetSize
        comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate, 1)))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        let sw = abs(sourceSize.width)
        let sh = abs(sourceSize.height)
        let scale = min(targetSize.width / sw, targetSize.height / sh)
        let tx = (targetSize.width - sw * scale) / 2
        let ty = (targetSize.height - sh * scale) / 2
        let t = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: tx / scale, y: ty / scale)
        layer.setTransform(t, at: .zero)
        instruction.layerInstructions = [layer]
        comp.instructions = [instruction]
        return comp
    }

    private func deriveCodec(from videoTrack: AVAssetTrack) async throws -> AVVideoCodecType {
        let fmts = try await videoTrack.load(.formatDescriptions) as! [CMFormatDescription]
        guard let first = fmts.first else { return .h264 }
        switch CMFormatDescriptionGetMediaSubType(first) {
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return .hevc
        default: return .h264
        }
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case noVideoTrack
    case configurationFailed(String)
    case readerFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "源视频中没有视频轨道"
        case .configurationFailed(let d): "编码器配置失败: \(d)"
        case .readerFailed(let d): "读取视频失败: \(d)"
        case .writerFailed(let d): "写入视频失败: \(d)"
        }
    }
}
