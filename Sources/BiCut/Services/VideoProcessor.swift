import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import os
import VideoToolbox

// MARK: - Export result

enum ExportResult {
    case completed
    case cancelled
}

// MARK: - Video Processor

/// Segment exporter supporting:
/// - **fast**: passthrough/remux (stream copy); starts may snap to prior keyframes
/// - **precise**: decode + re-encode so cuts stay frame-aligned
final class VideoProcessor: @unchecked Sendable {
    private let asset: AVAsset
    private let segment: SegmentInfo
    private let outputURL: URL
    private let config: ExportConfig

    var onProgress: (@Sendable (Double) -> Void)?
    var onWarning: (@Sendable (String) -> Void)?
    private let cancellationState = OSAllocatedUnfairLock(initialState: false)
    /// Non-Sendable AVFoundation session; only touched from export/cancel paths.
    private nonisolated(unsafe) var activeExportSession: AVAssetExportSession?

    init(asset: AVAsset, segment: SegmentInfo, outputURL: URL, config: ExportConfig) {
        self.asset = asset
        self.segment = segment
        self.outputURL = outputURL
        self.config = config
    }

    func cancel() {
        cancellationState.withLock { $0 = true }
        activeExportSession?.cancelExport()
        activeExportSession = nil
    }

    func validateConfiguration() async throws {
        switch config.splittingStrategy {
        case .fast:
            try await validateFastConfiguration()
        case .precise:
            try await validatePreciseConfiguration()
        }
    }

    func export() async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw ExportError.noVideoTrack
        }

        let timeRange = CMTimeRange(start: segment.start, end: segment.end)
        switch config.splittingStrategy {
        case .fast:
            try await exportFast(timeRange: timeRange)
        case .precise:
            guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
                throw ExportError.noVideoTrack
            }
            try await exportPrecisely(
                videoTrack: videoTrack,
                audioTrack: tracks.first(where: { $0.mediaType == .audio }),
                timeRange: timeRange
            )
        }
    }

    // MARK: - Fast (passthrough)

    private func validateFastConfiguration() async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.configurationFailed("此素材不支持快速直通，请改用精确模式")
        }
        let types = session.supportedFileTypes
        guard types.contains(config.outputFormat.avFileType) else {
            throw ExportError.configurationFailed(
                "快速模式无法以 \(config.outputFormat.displayName) 直通导出，请改用精确模式或更换输出格式"
            )
        }
        if config.resolution != .original {
            onWarning?("快速模式保留原始分辨率与源编码；缩放/编码选项仅在精确模式下生效。")
        }
    }

    private func exportFast(timeRange: CMTimeRange) async throws {
        if cancellationState.withLock({ $0 }) || Task.isCancelled {
            throw CancellationError()
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.configurationFailed("无法创建快速导出会话")
        }
        guard session.supportedFileTypes.contains(config.outputFormat.avFileType) else {
            throw ExportError.configurationFailed(
                "快速模式无法写入 \(config.outputFormat.displayName)"
            )
        }

        session.outputURL = outputURL
        session.outputFileType = config.outputFormat.avFileType
        session.timeRange = timeRange
        // Allow the session to begin slightly early so the segment starts on a
        // decodable keyframe (the typical passthrough trade-off).
        session.canPerformMultiplePassesOverSourceMediaData = false

        activeExportSession = session
        defer { activeExportSession = nil }
        onProgress?(0.05)

        // AVAssetExportSession is not Sendable; confine to this export path.
        nonisolated(unsafe) let exportSession = session
        let status: AVAssetExportSession.Status = await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status)
            }
        }

        if cancellationState.withLock({ $0 }) || Task.isCancelled || status == .cancelled {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        switch status {
        case .completed:
            onProgress?(1)
        case .failed:
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.writerFailed(exportSession.error?.localizedDescription ?? "快速导出失败")
        case .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.writerFailed("快速导出未完成（状态 \(status.rawValue)）")
        }
    }

    // MARK: - Precise (re-encode)

    private func validatePreciseConfiguration() async throws {
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw ExportError.noVideoTrack
        }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BiCut-preflight-\(UUID().uuidString).\(config.outputFormat.fileExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let writer = try AVAssetWriter(url: temporaryURL, fileType: config.outputFormat.avFileType)

        let sourceSize = try await displayedSize(for: videoTrack)
        let targetSize = effectiveTargetSize(sourceSize: sourceSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let sourceDataRate = try await videoTrack.load(.estimatedDataRate)
        let preferredCodec = resolveOutputCodec(source: try await sourceCodec(from: videoTrack))
        let preferredSettings = makeVideoSettings(
            codec: preferredCodec,
            targetSize: targetSize,
            sourceSize: sourceSize,
            frameRate: frameRate,
            sourceDataRate: sourceDataRate
        )
        let canUsePreferred = writer.canApply(outputSettings: preferredSettings, forMediaType: .video)
        let fallbackSettings = makeVideoSettings(
            codec: .h264,
            targetSize: targetSize,
            sourceSize: sourceSize,
            frameRate: frameRate,
            sourceDataRate: sourceDataRate
        )
        guard canUsePreferred || writer.canApply(outputSettings: fallbackSettings, forMediaType: .video) else {
            throw ExportError.configurationFailed("\(config.outputFormat.displayName) 无法写入源视频编码")
        }
        if !canUsePreferred, preferredCodec != .h264 {
            onWarning?("源视频编码无法写入 \(config.outputFormat.displayName)，将兼容回退为 H.264。")
        }

        if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
            let settings = try await audioSettings(for: audioTrack)
            guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
                throw ExportError.configurationFailed("\(config.outputFormat.displayName) 无法写入源音频轨道")
            }
        }
    }

    // MARK: - Precise streaming pipeline

    private func exportPrecisely(
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack?,
        timeRange: CMTimeRange
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let writer = try AVAssetWriter(url: outputURL, fileType: config.outputFormat.avFileType)
        let metadataFormats = try await asset.load(.availableMetadataFormats)
        var metadata: [AVMetadataItem] = []
        for format in metadataFormats {
            metadata.append(contentsOf: try await asset.loadMetadata(for: format))
        }
        writer.metadata = metadata

        let rawSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let displayedSize = displayedSize(rawSize: rawSize, preferredTransform: preferredTransform)
        let targetSize = effectiveTargetSize(sourceSize: displayedSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let frameDuration = try await effectiveFrameDuration(for: videoTrack, frameRate: frameRate)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let assetDuration = try await asset.load(.duration)

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        videoOutput.videoComposition = buildVideoComposition(
            videoTrack: videoTrack,
            rawSize: rawSize,
            preferredTransform: preferredTransform,
            displayedSize: displayedSize,
            targetSize: targetSize,
            frameDuration: frameDuration,
            assetDuration: assetDuration
        )

        let preferredCodec = resolveOutputCodec(source: try await sourceCodec(from: videoTrack))
        var videoSettings = makeVideoSettings(
            codec: preferredCodec,
            targetSize: targetSize,
            sourceSize: displayedSize,
            frameRate: frameRate,
            sourceDataRate: estimatedDataRate
        )
        if !writer.canApply(outputSettings: videoSettings, forMediaType: .video), preferredCodec != .h264 {
            onWarning?("源视频编码无法写入 \(config.outputFormat.displayName)，已兼容回退为 H.264。")
            videoSettings = makeVideoSettings(
                codec: .h264,
                targetSize: targetSize,
                sourceSize: displayedSize,
                frameRate: frameRate,
                sourceDataRate: estimatedDataRate
            )
        }
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw ExportError.configurationFailed("所选容器不支持可用的视频编码器")
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.metadata = try await videoTrack.load(.commonMetadata)
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else {
            throw ExportError.configurationFailed("无法配置视频重编码流")
        }
        reader.add(videoOutput)
        writer.add(videoInput)

        let audioPair = try await makeAudioPipeline(track: audioTrack, reader: reader, writer: writer)

        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "未知错误")
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "未知错误")
        }
        writer.startSession(atSourceTime: timeRange.start)

        do {
            try await streamSamples(
                reader: reader,
                writer: writer,
                videoOutput: videoOutput,
                videoInput: videoInput,
                audioOutput: audioPair?.output,
                audioInput: audioPair?.input,
                timeRange: timeRange
            )
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "写入失败")
        }
        onProgress?(1)
    }

    /// Interleaves video and audio reads so neither writer input starves the
    /// other. At most one decoded sample per track is retained at a time.
    private func streamSamples(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderOutput?,
        audioInput: AVAssetWriterInput?,
        timeRange: CMTimeRange
    ) async throws {
        var videoFinished = false
        var audioFinished = audioOutput == nil || audioInput == nil
        var lastReportedProgress = 0.0
        let startSeconds = CMTimeGetSeconds(timeRange.start)
        let durationSeconds = max(CMTimeGetSeconds(timeRange.duration), 0.001)

        while !videoFinished || !audioFinished {
            if cancellationState.withLock({ $0 }) || Task.isCancelled { throw CancellationError() }
            if reader.status == .failed {
                throw ExportError.readerFailed(reader.error?.localizedDescription ?? "读取失败")
            }
            if writer.status == .failed {
                throw ExportError.writerFailed(writer.error?.localizedDescription ?? "写入失败")
            }

            var madeProgress = false
            if !videoFinished, videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else {
                        throw ExportError.writerFailed(writer.error?.localizedDescription ?? "无法写入视频帧")
                    }
                    madeProgress = true
                    let presentationSeconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                    let progress = min(max((presentationSeconds - startSeconds) / durationSeconds, 0), 1)
                    if progress - lastReportedProgress >= 0.01 {
                        onProgress?(progress)
                        lastReportedProgress = progress
                    }
                } else {
                    videoInput.markAsFinished()
                    videoFinished = true
                    madeProgress = true
                }
            }

            if !audioFinished, let audioOutput, let audioInput, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else {
                        throw ExportError.writerFailed(writer.error?.localizedDescription ?? "无法写入音频样本")
                    }
                } else {
                    audioInput.markAsFinished()
                    audioFinished = true
                }
                madeProgress = true
            }

            if !madeProgress {
                try await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    // MARK: - Pipeline configuration

    private func makeAudioPipeline(
        track: AVAssetTrack?,
        reader: AVAssetReader,
        writer: AVAssetWriter
    ) async throws -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)? {
        guard let track else { return nil }

        let descriptions = try await track.load(.formatDescriptions)
        guard let format = descriptions.first,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else {
            onWarning?("无法读取源音频格式，本次输出将不包含音频。")
            return nil
        }

        let sampleRate = basicDescription.mSampleRate > 0 ? basicDescription.mSampleRate : 48_000
        let channelCount = max(1, Int(basicDescription.mChannelsPerFrame))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount
            ]
        )
        let settings = try await audioSettings(for: track)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.metadata = try await track.load(.commonMetadata)

        guard reader.canAdd(output), writer.canApply(outputSettings: settings, forMediaType: .audio), writer.canAdd(input) else {
            throw ExportError.configurationFailed("所选容器无法写入源视频的音频轨道")
        }
        reader.add(output)
        writer.add(input)
        return (output, input)
    }

    private func audioSettings(for track: AVAssetTrack) async throws -> [String: Any] {
        let descriptions = try await track.load(.formatDescriptions)
        guard let format = descriptions.first,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else {
            throw ExportError.configurationFailed("无法读取源音频格式")
        }
        let sampleRate = basicDescription.mSampleRate > 0 ? basicDescription.mSampleRate : 48_000
        let channelCount = max(1, Int(basicDescription.mChannelsPerFrame))
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: max(128_000, channelCount * 96_000)
        ]
    }

    private func makeVideoSettings(
        codec: AVVideoCodecType,
        targetSize: CGSize,
        sourceSize: CGSize,
        frameRate: Float,
        sourceDataRate: Float
    ) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: frameRate > 0 ? frameRate : 30,
            AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
            AVVideoProfileLevelKey: codec == .hevc
                ? kVTProfileLevel_HEVC_Main_AutoLevel as String
                : kVTProfileLevel_H264_High_AutoLevel as String
        ]
        if sourceDataRate > 0 {
            let sourcePixels = max(sourceSize.width * sourceSize.height, 1)
            let outputPixels = targetSize.width * targetSize.height
            let scaledRate = Double(sourceDataRate) * min(Double(outputPixels / sourcePixels), 1)
            compression[AVVideoAverageBitRateKey] = max(Int(scaledRate.rounded()), 1_000_000)
        }
        return [
            AVVideoCodecKey: codec.rawValue,
            AVVideoWidthKey: Int(targetSize.width),
            AVVideoHeightKey: Int(targetSize.height),
            AVVideoCompressionPropertiesKey: compression
        ]
    }

    private func effectiveTargetSize(sourceSize: CGSize) -> CGSize {
        guard let requested = config.resolution.targetSize else {
            return evenSize(sourceSize)
        }
        let scale = min(requested.width / sourceSize.width, requested.height / sourceSize.height, 1)
        return evenSize(CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale))
    }

    private func displayedSize(for track: AVAssetTrack) async throws -> CGSize {
        let rawSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        return displayedSize(rawSize: rawSize, preferredTransform: transform)
    }

    private func displayedSize(rawSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: rawSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, floor(size.width / 2) * 2),
            height: max(2, floor(size.height / 2) * 2)
        )
    }

    private func effectiveFrameDuration(for track: AVAssetTrack, frameRate: Float) async throws -> CMTime {
        let minimum = try await track.load(.minFrameDuration)
        if minimum.isValid, minimum.isNumeric, CMTimeCompare(minimum, .zero) > 0 {
            return minimum
        }
        return CMTime(seconds: 1 / Double(frameRate > 0 ? frameRate : 30), preferredTimescale: 60_000)
    }

    private func buildVideoComposition(
        videoTrack: AVAssetTrack,
        rawSize: CGSize,
        preferredTransform: CGAffineTransform,
        displayedSize: CGSize,
        targetSize: CGSize,
        frameDuration: CMTime,
        assetDuration: CMTime
    ) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.renderSize = targetSize
        composition.frameDuration = frameDuration

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        let transformedRect = CGRect(origin: .zero, size: rawSize).applying(preferredTransform)
        let normalize = CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        let scale = min(targetSize.width / displayedSize.width, targetSize.height / displayedSize.height)
        let transform = preferredTransform
            .concatenating(normalize)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        layer.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }

    private func sourceCodec(from videoTrack: AVAssetTrack) async throws -> AVVideoCodecType {
        let descriptions = try await videoTrack.load(.formatDescriptions)
        guard let first = descriptions.first else { return .h264 }
        switch CMFormatDescriptionGetMediaSubType(first) {
        case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return .hevc
        default: return .h264
        }
    }

    private func resolveOutputCodec(source: AVVideoCodecType) -> AVVideoCodecType {
        // Precise mode honors the user's codec preference.
        _ = source
        return config.videoCodec.avCodec
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
        case .configurationFailed(let description): "编码器配置失败: \(description)"
        case .readerFailed(let description): "读取视频失败: \(description)"
        case .writerFailed(let description): "写入视频失败: \(description)"
        }
    }
}
