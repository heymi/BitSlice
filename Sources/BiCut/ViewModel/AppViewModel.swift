import AppKit
import AVFoundation
import IOKit.pwr_mgt
import Observation
import SwiftUI

// MARK: - App Phase

enum AppPhase: Equatable {
    case empty
    case loaded
    case exporting(currentSegment: Int, totalSegments: Int, overallProgress: Double, segmentProgress: Double)
    case completed(outputURL: URL)
    case failed(message: String)

    var isExporting: Bool {
        if case .exporting = self { true } else { false }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class AppViewModel {
    var videoAsset: VideoAsset?
    var config: ExportConfig
    var phase: AppPhase = .empty
    var segments: [SegmentInfo] = []
    var recentVideos: [RecentVideo]

    // Player state
    var player: AVPlayer?
    var currentTime: Double = 0
    var isPlaying = false
    var isMuted = false
    var playbackSpeed: Double = 1.0
    private var timeObserver: Any?

    // Export tracking
    var exportLogs: [String] = []
    var exportSpeed: Double = 0
    var exportETA: Double = 0
    private var exportStartTime: Date?

    private var sourceBookmark: Data?

    // MARK: - Init

    init() {
        config = ExportConfig.load()
        recentVideos = RecentVideo.loadAll()
        // Output names are session-specific. Always start with an empty field
        // instead of restoring a stale or malformed value from UserDefaults.
        if !config.customTitle.isEmpty {
            config.customTitle = ""
            config.save()
        }
        if let dir = config.outputDirectory {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
                config.outputDirectory = nil
            }
        }
    }

    // MARK: - Video loading

    func loadVideo(from url: URL) async {
        videoAsset = nil
        segments = []
        phase = .empty
        player = nil
        stopTimeObserver()

        let asset = VideoAsset(url: url)
        await asset.loadMetadata()

        if let error = asset.loadError {
            phase = .failed(message: "无法加载视频: \(error)")
            return
        }
        guard asset.hasVideoTrack else {
            phase = .failed(message: "文件不包含视频轨道。")
            return
        }
        if let compatibilityError = asset.preciseExportCompatibilityError {
            phase = .failed(message: compatibilityError.localizedDescription)
            return
        }
        guard asset.durationSeconds >= 1 else {
            phase = .failed(message: "视频时长过短（< 1 秒）。")
            return
        }

        // Persist access when the app is sandboxed. The standalone SwiftPM build
        // does not require a security-scoped bookmark and may not create one.
        sourceBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Set up player
        let p = AVPlayer(url: url)
        p.volume = isMuted ? 0 : 1
        p.rate = Float(playbackSpeed)
        player = p
        startTimeObserver()

        videoAsset = asset
        rememberRecentVideo(asset, bookmark: sourceBookmark)
        let validDuration = validSegmentDuration(config.segmentDuration, videoDuration: asset.durationSeconds)
        if config.segmentDuration != validDuration {
            config.segmentDuration = validDuration
            config.save()
        }
        recalculateSegments()
        phase = .loaded
    }

    func openRecentVideo(_ recent: RecentVideo) async {
        guard FileManager.default.fileExists(atPath: recent.url.path) else {
            recentVideos.removeAll { $0.id == recent.id }
            RecentVideo.saveAll(recentVideos)
            return
        }
        await loadVideo(from: recent.url)
    }

    private func rememberRecentVideo(_ asset: VideoAsset, bookmark: Data?) {
        let recent = RecentVideo(
            path: asset.url.path,
            fileName: asset.fileName,
            width: Int(asset.naturalSize.width.rounded()),
            height: Int(asset.naturalSize.height.rounded()),
            frameRate: Int(asset.frameRate.rounded()),
            fileSize: asset.fileSize,
            lastOpenedAt: Date(),
            bookmark: bookmark
        )
        recentVideos.removeAll { $0.path == recent.path }
        recentVideos.insert(recent, at: 0)
        recentVideos = Array(recentVideos.prefix(3))
        RecentVideo.saveAll(recentVideos)
    }

    // MARK: - Player controls

    func togglePlayback() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play(); p.rate = Float(playbackSpeed) }
        isPlaying.toggle()
    }

    func seekTo(seconds: Double) {
        guard let p = player, let asset = videoAsset else { return }
        let clamped = max(0, min(seconds, asset.durationSeconds))
        let time = CMTime(seconds: clamped, preferredTimescale: asset.duration.timescale)
        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    func stepFrame(forward: Bool) {
        guard player != nil else { return }
        let fps = videoAsset?.frameRate ?? 30
        let delta = 1.0 / Double(fps)
        let newTime = forward ? currentTime + delta : currentTime - delta
        seekTo(seconds: newTime)
    }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        guard let p = player else { return }
        p.rate = isPlaying ? Float(speed) : 0
    }

    func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : 1
    }

    private func startTimeObserver() {
        guard let p = player else { return }
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let sec = CMTimeGetSeconds(time)
            guard sec.isFinite else { return }
            Task { @MainActor [weak self] in self?.currentTime = sec }
        }
    }

    private func stopTimeObserver() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
    }

    var videoDuration: Double { videoAsset?.durationSeconds ?? 0 }

    /// Which segment index the current playhead falls into
    var activeSegmentIndex: Int? {
        guard !segments.isEmpty else { return nil }
        for (i, seg) in segments.enumerated() {
            if currentTime >= seg.startSeconds, currentTime < seg.startSeconds + seg.durationSeconds {
                return i
            }
        }
        return nil
    }

    /// Progress fraction [0...1] of currentTime in total duration
    var playbackProgress: Double {
        guard videoDuration > 0 else { return 0 }
        return min(max(currentTime / videoDuration, 0), 1)
    }

    // MARK: - Segment calculation

    func recalculateSegments() {
        guard let asset = videoAsset, asset.durationSeconds > 0 else {
            segments = []
            return
        }
        let segCMTime = CMTime(seconds: config.segmentDuration, preferredTimescale: asset.duration.timescale)
        let stem: String
        if !config.customTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            stem = config.customTitle.trimmingCharacters(in: .whitespaces)
        } else {
            stem = (asset.fileName as NSString).deletingPathExtension
        }
        segments = calculateSegments(
            totalDuration: asset.duration,
            segmentDuration: segCMTime,
            baseName: stem,
            fileExtension: config.outputFormat.fileExtension
        )
        if case .loaded = phase {} // trigger update
    }

    /// Real-time preview of the first output file name
    var namingPreview: String {
        guard !segments.isEmpty else { return "—" }
        return segments.first?.fileName ?? "—"
    }

    /// Segment summary text
    var segmentSummary: String {
        let count = segments.count
        guard count > 0 else { return "无切片" }
        if count == 1 { return "共 1 个视频" }
        let dur = formatTime(config.segmentDuration)
        if let last = segments.last, last.durationSeconds < config.segmentDuration {
            return "\(count) 个视频 — \(count - 1) × \(dur)，最后 1 个 \(formatTime(last.durationSeconds))"
        }
        return "\(count) 个视频 — 每个 \(dur)"
    }

    var segmentSummaryEnglish: String {
        let count = segments.count
        guard count > 0 else { return "No clips yet." }
        if count == 1 { return "Exports as one complete clip." }
        let duration = formatShortDuration(config.segmentDuration)
        if let last = segments.last, last.durationSeconds < config.segmentDuration {
            return "Splits into \(count) clips. \(count - 1) × \(duration), last clip is \(formatShortDuration(last.durationSeconds))."
        }
        return "Splits into \(count) clips of \(duration)."
    }

    var destinationDisplayPath: String {
        guard let directory = config.outputDirectory else { return "Choose output folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return directory.path.replacingOccurrences(of: home, with: "~")
    }

    func requestReplacementFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.prompt = "Replace"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.loadVideo(from: url) }
        }
    }

    // MARK: - Settings

    func setSegmentDuration(_ seconds: TimeInterval) {
        guard seconds >= 1 else { return }
        config.segmentDuration = validSegmentDuration(seconds, videoDuration: videoDuration)
        config.save()
        recalculateSegments()
    }

    func setOutputFormat(_ format: OutputFormat) {
        config.outputFormat = format
        config.save()
        recalculateSegments()
    }

    func setResolution(_ resolution: ExportResolution) {
        config.resolution = resolution
        config.save()
    }

    func setOutputDirectory(_ url: URL) {
        config.outputDirectory = url
        config.save()
    }

    func setCustomTitle(_ title: String) {
        config.customTitle = title
        recalculateSegments()
    }

    // MARK: - Export

    func startExport() async {
        guard let asset = videoAsset, !segments.isEmpty else { return }
        guard let outputDir = config.outputDirectory else {
            phase = .failed(message: "请先选择导出目录。")
            return
        }
        guard FileManager.default.isWritableFile(atPath: outputDir.path) else {
            phase = .failed(message: "导出目录不可写。")
            return
        }
        if let free = freeSpace(at: outputDir),
           asset.fileSize > 0,
           free < asset.fileSize * 3 / 2 {
            phase = .failed(message: "磁盘空间可能不足。")
            return
        }

        exportLogs = ["[BiCut Core] 初始化导出引擎...", "[BiCut Core] 分析视频轨道结构..."]

        let preciseSegments: [SegmentInfo]
        do {
            preciseSegments = try await VideoAsset.resolveFrameAlignedSegments(
                at: asset.url,
                plannedSegments: segments
            )
            guard let firstSegment = preciseSegments.first else { return }
            let preflightURL = outputDir.appendingPathComponent(firstSegment.fileName)
            let preflight = VideoProcessor(
                asset: asset.avAsset,
                segment: firstSegment,
                outputURL: preflightURL,
                config: config
            )
            preflight.onWarning = { [weak self] warning in
                Task { @MainActor in self?.appendExportLog("[兼容性提示] \(warning)") }
            }
            try await preflight.validateConfiguration()
        } catch {
            phase = .failed(message: "无法开始精确分片: \(error.localizedDescription)")
            return
        }
        segments = preciseSegments

        exportStartTime = Date()
        exportSpeed = 0
        exportETA = 0

        let pipeline = ExportPipeline(asset: asset, config: config, segments: preciseSegments, outputDir: outputDir)

        phase = .exporting(currentSegment: 0, totalSegments: segments.count, overallProgress: 0, segmentProgress: 0)

        var assertionID: IOPMAssertionID = 0
        let reason = "BiCut 视频分片导出" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        let result: ExportResult
        do {
            result = try await pipeline.run(
                onProgress: { [weak self] current, total, overall, segment in
                    guard let self else { return }
                    Task { @MainActor in
                        self.phase = .exporting(currentSegment: current, totalSegments: total, overallProgress: overall, segmentProgress: segment)
                        let segName = self.segments[safe: current]?.fileName ?? "?"
                        if segment > 0.05 {
                            self.appendExportLog("[Chunk \(current + 1)/\(total)] \(segName) — \(Int(segment * 100))%")
                        }
                        // Update telemetry
                        if let start = self.exportStartTime, overall > 0.01 {
                            let elapsed = Date().timeIntervalSince(start)
                            self.exportSpeed = elapsed > 0 ? overall / elapsed * (self.videoDuration) : 0
                            self.exportETA = overall > 0 ? elapsed / overall - elapsed : 0
                        }
                    }
                },
                onWarning: { [weak self] warning in
                    Task { @MainActor in
                        self?.appendExportLog("[兼容性提示] \(warning)")
                    }
                }
            )
        } catch is CancellationError {
            if assertionID != 0 { IOPMAssertionRelease(assertionID) }
            exportLogs.append("[BiCut Core] 导出已取消")
            phase = .loaded
            return
        } catch {
            if assertionID != 0 { IOPMAssertionRelease(assertionID) }
            exportLogs.append("[BiCut Core] 错误: \(error.localizedDescription)")
            phase = .failed(message: "导出失败: \(error.localizedDescription)")
            return
        }

        if assertionID != 0 { IOPMAssertionRelease(assertionID) }

        switch result {
        case .completed:
            exportLogs.append("[BiCut Core] ✅ 导出完成 — \(segments.count) 个文件")
            phase = .completed(outputURL: outputDir)
            NSSound(named: "Glass")?.play()
        case .cancelled:
            exportLogs.append("[BiCut Core] 导出已取消")
            phase = .loaded
        }
    }

    func appendExportLog(_ message: String) {
        exportLogs.append("[\(timeStamp())] \(message)")
        if exportLogs.count > 200 { exportLogs.removeFirst(exportLogs.count - 200) }
    }

    func cancelExport() {
        ExportPipeline.cancelActive()
    }

    func resetToIdle() {
        phase = .loaded
    }
}

// MARK: - Helpers

private func freeSpace(at url: URL) -> Int64? {
    do {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values.volumeAvailableCapacity.map(Int64.init)
    } catch { return nil }
}

private func timeStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}
