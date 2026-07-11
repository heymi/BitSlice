import AVFoundation
import Foundation

// MARK: - Export Pipeline

/// Orchestrates sequential export of all segments with progress aggregation.
///
/// Supports cancellation: completed segments are kept; in-progress segment is discarded.
final class ExportPipeline: @unchecked Sendable {
    private let asset: VideoAsset
    private let config: ExportConfig
    private let segments: [SegmentInfo]
    private let outputDir: URL

    /// Shared reference for cancellation. Single-threaded pipeline — safe as nonisolated(unsafe).
    private nonisolated(unsafe) static var activePipeline: ExportPipeline?

    init(asset: VideoAsset, config: ExportConfig, segments: [SegmentInfo], outputDir: URL) {
        self.asset = asset
        self.config = config
        self.segments = segments
        self.outputDir = outputDir
    }

    static func cancelActive() {
        activePipeline?.currentProcessor?.cancel()
    }

    private var currentProcessor: VideoProcessor?

    /// Runs the pipeline, calling `onProgress` after each segment completes
    /// and periodically during each segment's export.
    func run(
        onProgress: @escaping @Sendable (Int, Int, Double, Double) -> Void,
        onWarning: @escaping @Sendable (String) -> Void
    ) async throws -> ExportResult {
        Self.activePipeline = self
        defer { Self.activePipeline = nil }

        let total = segments.count
        let avAsset = asset.avAsset

        for (i, segment) in segments.enumerated() {
            try Task.checkCancellation()

            let outputURL = outputDir.appendingPathComponent(segment.fileName)

            // Remove stale output if it exists
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            let processor = VideoProcessor(
                asset: avAsset,
                segment: segment,
                outputURL: outputURL,
                config: config
            )
            currentProcessor = processor

            processor.onProgress = { segProgress in
                let overall = (Double(i) + segProgress) / Double(max(total, 1))
                onProgress(i, total, overall, segProgress)
            }
            processor.onWarning = { warning in
                onWarning(warning)
            }

            do {
                try await processor.export()
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }

            currentProcessor = nil
            onProgress(i + 1, total, Double(i + 1) / Double(max(total, 1)), 1.0)
        }

        return .completed
    }
}
