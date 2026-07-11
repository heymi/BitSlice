import AVFoundation
import AVFAudio
import CoreVideo
import Foundation
import Testing
@testable import BiCut

@Suite("Precise media export")
struct PreciseExportIntegrationTests {
    @Test func exportsFrameAlignedH264ToEveryLaunchContainer() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeVideoFixture(at: sourceURL, frameRate: 24, frameCount: 54)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let plannedSegments = calculateSegments(
            totalDuration: CMTime(value: 54, timescale: 24),
            segmentDuration: CMTime(seconds: 1, preferredTimescale: 600),
            baseName: "clip",
            fileExtension: "mp4"
        )
        let resolvedSegments = try await VideoAsset.resolveFrameAlignedSegments(
            at: sourceURL,
            plannedSegments: plannedSegments
        )
        let segment = try #require(resolvedSegments[safe: 1])
        #expect(segment.start == CMTime(seconds: 1, preferredTimescale: 24))
        #expect(try await sampleIsSync(at: segment.start, in: sourceAsset) == false)

        for format in OutputFormat.allCases {
            var config = ExportConfig()
            config.outputFormat = format
            let outputURL = directory.appendingPathComponent("output.\(format.fileExtension)")
            let processor = VideoProcessor(
                asset: sourceAsset,
                segment: segment,
                outputURL: outputURL,
                config: config
            )

            try await processor.validateConfiguration()
            try await processor.export()

            let outputAsset = AVURLAsset(url: outputURL)
            let duration = try await outputAsset.load(.duration)
            let tracks = try await outputAsset.load(.tracks)
            let videoTrack = try #require(tracks.first(where: { $0.mediaType == .video }))
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            let size = try await videoTrack.load(.naturalSize)

            #expect(abs(CMTimeGetSeconds(duration) - 1) <= 1.0 / 24.0)
            #expect(abs(frameRate - 24) < 0.1)
            #expect(size == CGSize(width: 64, height: 48))
            let metadata = try await outputAsset.load(.commonMetadata)
            let title = try await metadata.first?.load(.stringValue)
            #expect(title == "BiCut Fixture")
            #expect(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    @Test func preserves24_30_60FPSAndPortraitOrientation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cases: [(fps: Int32, codec: AVVideoCodecType, rotated: Bool)] = [
            (24, .h264, false),
            (30, .hevc, false),
            (60, .h264, true)
        ]

        for item in cases {
            let sourceURL = directory.appendingPathComponent("source-\(item.fps).mov")
            try await makeVideoFixture(
                at: sourceURL,
                fileType: .mov,
                frameRate: item.fps,
                frameCount: Int(item.fps),
                codec: item.codec,
                rotated: item.rotated
            )
            let outputURL = directory.appendingPathComponent("output-\(item.fps).mp4")
            let processor = VideoProcessor(
                asset: AVURLAsset(url: sourceURL),
                segment: SegmentInfo(index: 0, start: .zero, end: CMTime(seconds: 1, preferredTimescale: item.fps), fileName: outputURL.lastPathComponent),
                outputURL: outputURL,
                config: ExportConfig()
            )

            try await processor.export()

            let outputAsset = AVURLAsset(url: outputURL)
            let videoTrack = try #require(try await outputAsset.loadTracks(withMediaType: .video).first)
            let outputFPS = try await videoTrack.load(.nominalFrameRate)
            let outputSize = try await videoTrack.load(.naturalSize)
            #expect(abs(outputFPS - Float(item.fps)) < 0.2)
            #expect(outputSize == (item.rotated ? CGSize(width: 48, height: 64) : CGSize(width: 64, height: 48)))
        }
    }

    @Test func keepsAudioThroughAnExactSegmentBoundary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let silentVideoURL = directory.appendingPathComponent("video.mov")
        let toneURL = directory.appendingPathComponent("tone.caf")
        let sourceURL = directory.appendingPathComponent("source-with-audio.mov")
        try await makeVideoFixture(at: silentVideoURL, fileType: .mov, frameRate: 30, frameCount: 45)
        try makeToneFixture(at: toneURL, duration: 1.5)
        try await combine(videoURL: silentVideoURL, audioURL: toneURL, outputURL: sourceURL)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceAudioSamples = try await decodedAudioSamples(in: sourceAsset)

        let plannedSegments = calculateSegments(
            totalDuration: CMTime(seconds: 1.5, preferredTimescale: 600),
            segmentDuration: CMTime(seconds: 0.75, preferredTimescale: 600),
            baseName: "audio",
            fileExtension: "mp4"
        )
        let resolvedSegments = try await VideoAsset.resolveFrameAlignedSegments(at: sourceURL, plannedSegments: plannedSegments)
        var totalOutputDuration = 0.0
        var totalAudioFrames = 0

        for segment in resolvedSegments {
            let outputURL = directory.appendingPathComponent(segment.fileName)
            let processor = VideoProcessor(
                asset: sourceAsset,
                segment: segment,
                outputURL: outputURL,
                config: ExportConfig()
            )

            try await processor.export()

            let outputAsset = AVURLAsset(url: outputURL)
            let duration = try await outputAsset.load(.duration)
            let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
            #expect(audioTracks.count == 1)
            let stats = try await audioStats(in: outputAsset)
            #expect(stats.leadingRMS > 0.02)
            #expect(stats.trailingRMS > 0.02)
            let outputSamples = try await decodedAudioSamples(in: outputAsset)
            let expectedSourceIndex = Int((segment.startSeconds * 48_000).rounded())
            let matchedSourceIndex = bestSourceMatch(
                for: Array(outputSamples.prefix(min(2_048, outputSamples.count))),
                in: sourceAudioSamples,
                near: expectedSourceIndex,
                searchRadius: 2_048
            )
            #expect(abs(matchedSourceIndex - expectedSourceIndex) <= 256)
            totalAudioFrames += stats.frameCount
            totalOutputDuration += CMTimeGetSeconds(duration)
        }
        #expect(abs(totalOutputDuration - 1.5) <= 1.0 / 30.0)
        #expect(abs(totalAudioFrames - 72_000) <= 2_048)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BiCutTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeVideoFixture(
    at url: URL,
    fileType: AVFileType = .mp4,
    frameRate: Int32,
    frameCount: Int,
    codec: AVVideoCodecType = .h264,
    rotated: Bool = false
) async throws {
    let writer = try AVAssetWriter(url: url, fileType: fileType)
    let title = AVMutableMetadataItem()
    title.identifier = .quickTimeMetadataTitle
    title.value = "BiCut Fixture" as NSString
    writer.metadata = [title]
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 48,
            AVVideoCompressionPropertiesKey: [
                AVVideoMaxKeyFrameIntervalKey: max(Int(frameRate * 2), 1)
            ]
        ]
    )
    if rotated {
        input.transform = CGAffineTransform(rotationAngle: .pi / 2).translatedBy(x: 0, y: -48)
    }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48
        ]
    )
    guard writer.canAdd(input) else { throw FixtureError.cannotConfigureWriter }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? FixtureError.cannotStartWriter }
    writer.startSession(atSourceTime: .zero)

    for index in 0 ..< frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        let pixelBuffer = try makePixelBuffer(frameIndex: index)
        guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
            throw writer.error ?? FixtureError.cannotAppendFrame
        }
    }

    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? FixtureError.cannotFinishWriter }
}

private func makeToneFixture(at url: URL, duration: Double) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let frameCount = AVAudioFrameCount(duration * format.sampleRate)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let samples = try #require(buffer.floatChannelData?[0])
    for frame in 0 ..< Int(frameCount) {
        let time = Float(frame) / Float(format.sampleRate)
        let phase = 2 * Float.pi * (180 * time + 260 * time * time)
        let marker = sin(2 * Float.pi * 37 * time * time) * 0.015
        samples[frame] = sin(phase) * 0.085 + marker
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

private func combine(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
    let videoAsset = AVURLAsset(url: videoURL)
    let audioAsset = AVURLAsset(url: audioURL)
    let composition = AVMutableComposition()
    let duration = CMTime(seconds: 1.5, preferredTimescale: 600)
    let videoSource = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
    let audioSource = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
    let videoTrack = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    let audioTrack = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoSource, at: .zero)
    try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioSource, at: .zero)

    let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
    session.outputURL = outputURL
    session.outputFileType = .mov
    await session.export()
    guard session.status == .completed else { throw session.error ?? FixtureError.cannotCombineMedia }
}

private func makePixelBuffer(frameIndex: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        64,
        48,
        kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
        &buffer
    )
    guard status == kCVReturnSuccess, let buffer else { throw FixtureError.cannotCreatePixelBuffer }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { throw FixtureError.cannotCreatePixelBuffer }
    let byteCount = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
    memset(baseAddress, 80, byteCount)
    return buffer
}

private func sampleIsSync(at requestedTime: CMTime, in asset: AVAsset) async throws -> Bool {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? FixtureError.cannotReadMedia }

    while let sample = output.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if CMTimeCompare(time, requestedTime) == 0 {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
            return !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        }
    }
    throw FixtureError.cannotReadMedia
}

private func audioStats(in asset: AVAsset) async throws -> (frameCount: Int, leadingRMS: Float, trailingRMS: Float) {
    let samples = try await decodedAudioSamples(in: asset)
    let windowSize = min(2_048, samples.count)
    return (
        samples.count,
        rms(samples.prefix(windowSize)),
        rms(samples.suffix(windowSize))
    )
}

private func decodedAudioSamples(in asset: AVAsset) async throws -> [Float] {
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
    )
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? FixtureError.cannotReadMedia }

    var samples: [Float] = []
    while let sample = output.copyNextSampleBuffer(), let dataBuffer = CMSampleBufferGetDataBuffer(sample) {
        let byteCount = CMBlockBufferGetDataLength(dataBuffer)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let copyStatus = bytes.withUnsafeMutableBytes { destination in
            CMBlockBufferCopyDataBytes(
                dataBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: destination.baseAddress!
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw FixtureError.cannotReadMedia
        }
        bytes.withUnsafeBytes { rawBytes in
            samples.append(contentsOf: rawBytes.bindMemory(to: Float.self))
        }
    }
    guard reader.status != .failed, !samples.isEmpty else { throw reader.error ?? FixtureError.cannotReadMedia }
    return samples
}

private func rms<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
    var sum: Float = 0
    var count: Float = 0
    for sample in samples {
        sum += sample * sample
        count += 1
    }
    return count > 0 ? sqrt(sum / count) : 0
}

private func bestSourceMatch(
    for output: [Float],
    in source: [Float],
    near expectedIndex: Int,
    searchRadius: Int
) -> Int {
    guard !output.isEmpty, source.count >= output.count else { return -1 }
    let lowerBound = max(0, expectedIndex - searchRadius)
    let upperBound = min(source.count - output.count, expectedIndex + searchRadius)
    let outputEnergy = sqrt(output.reduce(0) { $0 + $1 * $1 })
    var bestIndex = lowerBound
    var bestCorrelation = -Float.infinity
    for candidate in lowerBound ... upperBound {
        var dotProduct: Float = 0
        var sourceEnergy: Float = 0
        for offset in output.indices {
            let sourceSample = source[candidate + offset]
            dotProduct += output[offset] * sourceSample
            sourceEnergy += sourceSample * sourceSample
        }
        let denominator = outputEnergy * sqrt(sourceEnergy)
        let correlation = denominator > 0 ? dotProduct / denominator : 0
        if correlation > bestCorrelation {
            bestCorrelation = correlation
            bestIndex = candidate
        }
    }
    return bestIndex
}

private enum FixtureError: Error {
    case cannotConfigureWriter
    case cannotStartWriter
    case cannotAppendFrame
    case cannotFinishWriter
    case cannotCreatePixelBuffer
    case cannotCombineMedia
    case cannotReadMedia
}
