import AVFoundation
import CoreGraphics
import Foundation

/// Wraps AVAsset and provides lazily loaded metadata.
@Observable
final class VideoAsset: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let fileSize: Int64

    private let asset: AVAsset

    // MARK: - Async-loaded metadata

    private(set) var isMetadataLoaded = false
    private(set) var duration: CMTime = .zero
    private(set) var durationSeconds: Double = 0
    private(set) var naturalSize: CGSize = .zero
    private(set) var frameRate: Float = 0
    private(set) var frameDuration: CMTime?
    private(set) var videoCodec: String = ""
    private(set) var hasAudioTrack = false
    private(set) var hasVideoTrack = false

    private(set) var loadError: String?

    init(url: URL) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)) ?? 0
        self.asset = AVAsset(url: url)
    }

    /// Asynchronously loads core metadata. Called once after the user drops a file.
    func loadMetadata() async {
        do {
            // Load duration and tracks using the modern async API
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration
            durationSeconds = CMTimeGetSeconds(cmDuration)

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            let audioTracks = tracks.filter { $0.mediaType == .audio }

            hasVideoTrack = !videoTracks.isEmpty
            hasAudioTrack = !audioTracks.isEmpty

            if let videoTrack = videoTracks.first {
                let rawSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let transformed = rawSize.applying(transform)
                naturalSize = CGSize(
                    width: abs(transformed.width),
                    height: abs(transformed.height)
                )
                frameRate = try await videoTrack.load(.nominalFrameRate)
                let minimumFrameDuration = try await videoTrack.load(.minFrameDuration)
                if minimumFrameDuration.isValid,
                   minimumFrameDuration.isNumeric,
                   CMTimeCompare(minimumFrameDuration, .zero) > 0 {
                    frameDuration = minimumFrameDuration
                }

                let formatDescs = try await videoTrack.load(.formatDescriptions)
                if let first = formatDescs.first {
                    videoCodec = Self.codecString(from: first)
                }
            }

            isMetadataLoaded = true
        } catch {
            loadError = error.localizedDescription
            isMetadataLoaded = true
        }
    }

    /// Resolution of the largest side, used for upscale guard.
    var maxDimension: CGFloat {
        max(naturalSize.width, naturalSize.height)
    }

    /// Expose the underlying AVAsset for the export pipeline.
    var avAsset: AVAsset { asset }

    var preciseExportCompatibilityError: PreciseExportCompatibilityError? {
        PreciseExportCompatibility.validate(
            fileExtension: url.pathExtension,
            codecFourCC: videoCodec
        )
    }

    /// Resolves planned cuts to real sample presentation timestamps. The reader
    /// streams compressed samples and retains only the sample on either side of
    /// each requested boundary, so long inputs do not accumulate frame data.
    nonisolated static func resolveFrameAlignedSegments(
        at sourceURL: URL,
        plannedSegments: [SegmentInfo]
    ) async throws -> [SegmentInfo] {
        guard plannedSegments.count > 1 else { return plannedSegments }
        let sourceAsset = AVURLAsset(url: sourceURL)
        let tracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ExportError.noVideoTrack }

        let requestedBoundaries = plannedSegments.dropLast().map(\.end)
        let reader = try AVAssetReader(asset: sourceAsset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ExportError.configurationFailed("无法读取源视频帧时间戳")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "无法读取源视频帧时间戳")
        }

        let requestedSeconds = requestedBoundaries.map(CMTimeGetSeconds)
        var closestTimes = [CMTime?](repeating: nil, count: requestedBoundaries.count)
        var closestDistances = [Double](repeating: .infinity, count: requestedBoundaries.count)
        while let sample = output.copyNextSampleBuffer() {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            guard presentationTime.isValid, presentationTime.isNumeric else { continue }
            let seconds = CMTimeGetSeconds(presentationTime)
            guard seconds.isFinite else { continue }
            let insertionIndex = requestedSeconds.partitioningIndex { $0 >= seconds }
            for index in [insertionIndex - 1, insertionIndex]
                where requestedSeconds.indices.contains(index) {
                let distance = abs(requestedSeconds[index] - seconds)
                if distance < closestDistances[index] {
                    closestDistances[index] = distance
                    closestTimes[index] = presentationTime
                }
            }
        }
        guard reader.status != .failed else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "读取源视频帧时间戳失败")
        }

        let resolvedBoundaries = closestTimes.compactMap { $0 }
        guard resolvedBoundaries.count == requestedBoundaries.count else {
            throw ExportError.configurationFailed("无法为每个计划切点找到唯一的视频帧")
        }
        guard zip(resolvedBoundaries, resolvedBoundaries.dropFirst()).allSatisfy({ CMTimeCompare($0, $1) < 0 }) else {
            throw ExportError.configurationFailed("相邻切点无法映射到不同的视频帧")
        }

        let totalDuration = plannedSegments.last?.end ?? .zero
        let boundaries = [.zero] + resolvedBoundaries.filter { CMTimeCompare($0, totalDuration) < 0 } + [totalDuration]
        return (0 ..< boundaries.count - 1).map { index in
            SegmentInfo(
                index: index,
                start: boundaries[index],
                end: boundaries[index + 1],
                fileName: plannedSegments[min(index, plannedSegments.count - 1)].fileName
            )
        }
    }

    // MARK: - Helpers

    private static func codecString(from formatDesc: CMFormatDescription) -> String {
        let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
        return fourCCToString(codec)
    }
}

private extension Array where Element == Double {
    func partitioningIndex(where belongsInSecondPartition: (Double) -> Bool) -> Int {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if belongsInSecondPartition(self[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }
}

enum PreciseExportCompatibility {
    private static let supportedContainers = Set(["mp4", "mov", "m4v"])
    private static let supportedCodecs = Set(["avc1", "avc3", "hvc1", "hev1"])

    static func validate(fileExtension: String, codecFourCC: String) -> PreciseExportCompatibilityError? {
        let normalizedExtension = fileExtension.lowercased()
        guard supportedContainers.contains(normalizedExtension) else {
            return .unsupportedContainer(fileExtension.isEmpty ? "未知" : fileExtension.uppercased())
        }
        guard supportedCodecs.contains(codecFourCC.lowercased()) else {
            return .unsupportedCodec(codecFourCC.isEmpty ? "未知" : codecFourCC)
        }
        return nil
    }
}

enum PreciseExportCompatibilityError: LocalizedError, Equatable {
    case unsupportedContainer(String)
    case unsupportedCodec(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedContainer(let container):
            "暂不支持 \(container) 容器的精确分片。首发支持 MP4、MOV、M4V。"
        case .unsupportedCodec(let codec):
            "暂不支持 \(codec) 编码的精确分片。首发支持 H.264 与 HEVC。"
        }
    }
}

// MARK: - Errors

enum VideoAssetError: LocalizedError {
    case noVideoTrack
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "视频文件中没有找到视频轨道"
        case .noAudioTrack: "视频文件中没有找到音频轨道（仍可导出，仅无声音）"
        }
    }
}

/// Convert a FourCharCode to a human-readable string.
func fourCCToString(_ code: FourCharCode) -> String {
    var code = code.bigEndian
    let data = Data(bytes: &code, count: 4)
    return String(data: data, encoding: .ascii) ?? "????"
}
