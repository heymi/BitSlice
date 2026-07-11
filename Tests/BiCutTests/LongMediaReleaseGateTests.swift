import AVFoundation
import Darwin
import Foundation
import Testing
@testable import BiCut

@Suite("Long media release gate")
struct LongMediaReleaseGateTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["BICUT_BENCHMARK_VIDEO"] != nil,
        "Set BICUT_BENCHMARK_VIDEO to a representative 10-minute or 1-hour source."
    ))
    func benchmarkRepresentativeLongVideo() async throws {
        let environment = ProcessInfo.processInfo.environment
        let sourcePath = try #require(environment["BICUT_BENCHMARK_VIDEO"])
        let benchmarkClass = try #require(environment["BICUT_BENCHMARK_CLASS"])
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceDuration = try await sourceAsset.load(.duration)
        let sourceDurationSeconds = CMTimeGetSeconds(sourceDuration)
        switch benchmarkClass {
        case "10m":
            #expect((540 ... 720).contains(sourceDurationSeconds), "The 10m gate requires a 9–12 minute input.")
        case "1h":
            #expect((3_300 ... 3_900).contains(sourceDurationSeconds), "The 1h gate requires a 55–65 minute input.")
        default:
            Issue.record("BICUT_BENCHMARK_CLASS must be 10m or 1h.")
            return
        }

        let sourceTrack = try #require(try await sourceAsset.loadTracks(withMediaType: .video).first)
        let sourceFrameRate = try await sourceTrack.load(.nominalFrameRate)
        let sourceRawSize = try await sourceTrack.load(.naturalSize)
        let sourceTransform = try await sourceTrack.load(.preferredTransform)
        let transformedSource = CGRect(origin: .zero, size: sourceRawSize).applying(sourceTransform)
        let sourceDisplayedSize = CGSize(width: abs(transformedSource.width), height: abs(transformedSource.height))
        let sourceFileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

        let plannedSegments = calculateSegments(
            totalDuration: sourceDuration,
            segmentDuration: CMTime(seconds: 60, preferredTimescale: sourceDuration.timescale),
            baseName: "benchmark",
            fileExtension: "mp4"
        )
        let preciseSegments = try await VideoAsset.resolveFrameAlignedSegments(
            at: sourceURL,
            plannedSegments: plannedSegments
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BiCutLongMediaGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let startedAt = ContinuousClock.now
        var outputBytes = 0
        var maximumDurationError = 0.0
        for segment in preciseSegments {
            let outputURL = outputDirectory.appendingPathComponent(segment.fileName)
            let processor = VideoProcessor(
                asset: sourceAsset,
                segment: segment,
                outputURL: outputURL,
                config: ExportConfig()
            )
            if segment.index == 0 { try await processor.validateConfiguration() }
            try await processor.export()

            let outputAsset = AVURLAsset(url: outputURL)
            #expect(try await outputAsset.load(.isPlayable))
            let outputDuration = try await outputAsset.load(.duration)
            maximumDurationError = max(
                maximumDurationError,
                abs(CMTimeGetSeconds(outputDuration) - segment.durationSeconds)
            )
            let outputTrack = try #require(try await outputAsset.loadTracks(withMediaType: .video).first)
            let outputFrameRate = try await outputTrack.load(.nominalFrameRate)
            let outputSize = try await outputTrack.load(.naturalSize)
            #expect(abs(outputFrameRate - sourceFrameRate) < 0.1)
            #expect(outputSize == sourceDisplayedSize)
            outputBytes += try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }

        let frameTolerance = 1 / Double(max(sourceFrameRate, 1))
        #expect(maximumDurationError <= frameTolerance)
        let elapsed = startedAt.duration(to: .now)
        let elapsedSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        let peakResidentBytes = peakResidentMemoryBytes()
        #expect(peakResidentBytes < 1_500_000_000, "Peak RSS must stay below the 1.5 GB release gate.")

        let report: [String: Any] = [
            "source": sourceURL.lastPathComponent,
            "benchmarkClass": benchmarkClass,
            "sourceDurationSeconds": sourceDurationSeconds,
            "segmentCount": preciseSegments.count,
            "elapsedSeconds": elapsedSeconds,
            "peakResidentBytes": peakResidentBytes,
            "sourceFrameRate": sourceFrameRate,
            "sourceWidth": sourceDisplayedSize.width,
            "sourceHeight": sourceDisplayedSize.height,
            "maximumDurationErrorSeconds": maximumDurationError,
            "sourceBytes": sourceFileSize,
            "outputBytes": outputBytes,
            "outputToSourceSizeRatio": sourceFileSize > 0 ? Double(outputBytes) / Double(sourceFileSize) : 0
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: reportData, as: UTF8.self))
        if let reportPath = environment["BICUT_BENCHMARK_REPORT"] {
            try reportData.write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        }
    }
}

private func peakResidentMemoryBytes() -> Int64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .max }
    return Int64(usage.ru_maxrss)
}
