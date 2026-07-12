import AVFoundation
import Foundation
import os

// MARK: - Export Pipeline

/// Orchestrates export of all segments with progress aggregation.
///
/// Fast mode may run a small number of segments concurrently. Precise mode is
/// always sequential (re-encode is memory-heavy). Cancellation keeps completed
/// outputs and discards the in-flight segment(s).
final class ExportPipeline: @unchecked Sendable {
    private let asset: VideoAsset
    private let config: ExportConfig
    private let segments: [SegmentInfo]
    private let outputDir: URL
    private let maxConcurrent: Int

    private nonisolated(unsafe) static var activePipeline: ExportPipeline?
    private let processorsLock = OSAllocatedUnfairLock(initialState: [VideoProcessor]())

    init(
        asset: VideoAsset,
        config: ExportConfig,
        segments: [SegmentInfo],
        outputDir: URL,
        maxConcurrent: Int = 1
    ) {
        self.asset = asset
        self.config = config
        self.segments = segments
        self.outputDir = outputDir
        // Only Fast passthrough benefits safely from limited parallelism.
        let allowed = config.splittingStrategy == .fast ? max(1, maxConcurrent) : 1
        self.maxConcurrent = min(allowed, 3)
    }

    static func cancelActive() {
        guard let pipeline = activePipeline else { return }
        pipeline.processorsLock.withLock { list in
            for processor in list { processor.cancel() }
        }
    }

    func run(
        onProgress: @escaping @Sendable (Int, Int, Double, Double) -> Void,
        onWarning: @escaping @Sendable (String) -> Void
    ) async throws -> ExportResult {
        Self.activePipeline = self
        defer {
            Self.activePipeline = nil
            processorsLock.withLock { $0.removeAll() }
        }

        if maxConcurrent <= 1 {
            try await runSequential(onProgress: onProgress, onWarning: onWarning)
        } else {
            try await runConcurrent(onProgress: onProgress, onWarning: onWarning)
        }
        return .completed
    }

    private func runSequential(
        onProgress: @escaping @Sendable (Int, Int, Double, Double) -> Void,
        onWarning: @escaping @Sendable (String) -> Void
    ) async throws {
        let total = segments.count
        let avAsset = asset.avAsset

        for (i, segment) in segments.enumerated() {
            try Task.checkCancellation()
            try await exportOne(
                index: i,
                segment: segment,
                avAsset: avAsset,
                onProgress: { segProgress in
                    let overall = (Double(i) + segProgress) / Double(max(total, 1))
                    onProgress(i, total, overall, segProgress)
                },
                onWarning: onWarning
            )
            onProgress(i + 1, total, Double(i + 1) / Double(max(total, 1)), 1.0)
        }
    }

    private func runConcurrent(
        onProgress: @escaping @Sendable (Int, Int, Double, Double) -> Void,
        onWarning: @escaping @Sendable (String) -> Void
    ) async throws {
        let total = segments.count
        let sourceURL = asset.url
        let exportConfig = config
        let directory = outputDir
        let completed = OSAllocatedUnfairLock(initialState: 0)
        let activeLock = OSAllocatedUnfairLock(initialState: [VideoProcessor]())

        // Keep cancel wiring for concurrent processors.
        processorsLock.withLock { $0.removeAll() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0

            func enqueue(_ index: Int) {
                let segment = segments[index]
                group.addTask {
                    try Task.checkCancellation()
                    let outputURL = directory.appendingPathComponent(segment.fileName)
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    // Fresh asset per task avoids sharing non-Sendable AVAsset across isolation.
                    let localAsset = AVURLAsset(url: sourceURL)
                    let processor = VideoProcessor(
                        asset: localAsset,
                        segment: segment,
                        outputURL: outputURL,
                        config: exportConfig
                    )
                    activeLock.withLock { $0.append(processor) }
                    Self.activePipeline?.processorsLock.withLock { $0.append(processor) }
                    defer {
                        activeLock.withLock { list in
                            list.removeAll { $0 === processor }
                        }
                        Self.activePipeline?.processorsLock.withLock { list in
                            list.removeAll { $0 === processor }
                        }
                    }

                    processor.onProgress = { segProgress in
                        let done = Double(completed.withLock { $0 })
                        let overall = (done + segProgress) / Double(max(total, 1))
                        onProgress(index, total, min(overall, 0.99), segProgress)
                    }
                    processor.onWarning = onWarning

                    do {
                        try await processor.export()
                    } catch {
                        try? FileManager.default.removeItem(at: outputURL)
                        throw error
                    }

                    let done = completed.withLock { value -> Int in
                        value += 1
                        return value
                    }
                    onProgress(index, total, Double(done) / Double(max(total, 1)), 1.0)
                }
            }

            while nextIndex < total, nextIndex < maxConcurrent {
                enqueue(nextIndex)
                nextIndex += 1
            }

            while try await group.next() != nil {
                if nextIndex < total {
                    enqueue(nextIndex)
                    nextIndex += 1
                }
            }
        }
    }

    private func exportOne(
        index: Int,
        segment: SegmentInfo,
        avAsset: AVAsset,
        onProgress: @escaping @Sendable (Double) -> Void,
        onWarning: @escaping @Sendable (String) -> Void
    ) async throws {
        try Task.checkCancellation()

        let outputURL = outputDir.appendingPathComponent(segment.fileName)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let processor = VideoProcessor(
            asset: avAsset,
            segment: segment,
            outputURL: outputURL,
            config: config
        )
        processorsLock.withLock { $0.append(processor) }
        defer {
            processorsLock.withLock { list in
                list.removeAll { $0 === processor }
            }
        }

        processor.onProgress = onProgress
        processor.onWarning = onWarning

        do {
            try await processor.export()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
