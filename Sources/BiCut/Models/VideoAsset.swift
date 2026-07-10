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

    // MARK: - Helpers

    private static func codecString(from formatDesc: CMFormatDescription) -> String {
        let codec = CMFormatDescriptionGetMediaSubType(formatDesc)
        return fourCCToString(codec)
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
