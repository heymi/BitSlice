import CoreMedia
import Testing
@testable import BeCut

@Suite("Export planning")
struct ExportPlanningTests {
    @Test func defaultConfigurationUsesFastSplitting() {
        let config = ExportConfig()

        #expect(config.splittingStrategy == .fast)
        #expect(config.segmentDuration == 180)
        #expect(SplittingStrategy.allCases == [.fast, .precise])
    }

    @Test func durationPresetsMatchProductPlan() {
        #expect(SegmentDurationPreset.allCases.map(\.seconds) == [15, 30, 60, 120, 180])
        #expect(SegmentDurationPreset.allCases.map { $0.displayName(for: .simplifiedChinese) } == ["15 秒", "30 秒", "60 秒", "2 分钟", "3 分钟"])
        #expect(SegmentDurationPreset.allCases.map { $0.displayName(for: .english) } == ["15s", "30s", "60s", "2 min", "3 min"])
    }

    @Test func outputFormatsIncludeAllLaunchContainers() {
        #expect(OutputFormat.allCases == [.mp4, .mov, .m4v])
        #expect(OutputFormat.m4v.fileExtension == "m4v")
    }

    @Test func segmentsAreContinuousAndKeepShortTail() {
        let segments = calculateSegments(
            totalDuration: CMTime(seconds: 125, preferredTimescale: 600),
            segmentDuration: CMTime(seconds: 60, preferredTimescale: 600),
            baseName: "Interview",
            fileExtension: "m4v"
        )

        #expect(segments.map(\.fileName) == ["Interview_01.m4v", "Interview_02.m4v", "Interview_03.m4v"])
        #expect(segments.map(\.durationSeconds) == [60, 60, 5])
        #expect(segments[0].end == segments[1].start)
        #expect(segments[1].end == segments[2].start)
    }

    @Test func requestedBoundariesSnapToNearestFrame() {
        let frameDuration = CMTime(value: 1, timescale: 24)
        let segments = calculateSegments(
            totalDuration: CMTime(seconds: 3, preferredTimescale: 600),
            segmentDuration: CMTime(seconds: 1.02, preferredTimescale: 600),
            frameDuration: frameDuration,
            baseName: "Frames",
            fileExtension: "mp4"
        )

        #expect(segments.count == 3)
        #expect(segments[0].end == CMTime(seconds: 1, preferredTimescale: 24))
        #expect(segments[0].end == segments[1].start)
        #expect(segments[1].end == segments[2].start)
        #expect(segments.last?.end == CMTime(seconds: 3, preferredTimescale: 600))
    }

    @Test func launchCompatibilityAcceptsOnlyValidatedContainersAndCodecs() {
        #expect(PreciseExportCompatibility.validate(fileExtension: "MP4", codecFourCC: "avc1") == nil)
        #expect(PreciseExportCompatibility.validate(fileExtension: "mov", codecFourCC: "hvc1") == nil)
        #expect(PreciseExportCompatibility.validate(fileExtension: "m4v", codecFourCC: "hev1") == nil)

        #expect(PreciseExportCompatibility.validate(fileExtension: "webm", codecFourCC: "vp09") != nil)
        #expect(PreciseExportCompatibility.validate(fileExtension: "mov", codecFourCC: "ap4h") != nil)
    }

    @Test func customDurationStaysInsideSliderRange() {
        #expect(validSegmentDuration(300, videoDuration: 234) == 234)
        #expect(validSegmentDuration(0, videoDuration: 234) == 1)
        #expect(validSegmentDuration(60, videoDuration: 234) == 60)
        #expect(validSegmentDuration(60, videoDuration: 0) == 60)
    }

}
