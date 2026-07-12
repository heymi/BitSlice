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
    var appSettings: AppSettings
    var phase: AppPhase = .empty
    var isLoadingVideo = false
    var segments: [SegmentInfo] = []
    var recentVideos: [RecentVideo]

    // Player state
    var player: AVPlayer?
    var currentTime: Double = 0
    var isPlaying = false
    var isMuted = false
    var playbackSpeed: Double = 1.0
    private var timeObserver: Any?
    private var endPlaybackObserver: NSObjectProtocol?

    // Export tracking
    var exportLogs: [String] = []
    var exportSpeed: Double = 0
    var exportETA: Double = 0
    private var exportStartTime: Date?

    // Sidebar chrome (kept on the model so CLT builds work without SwiftUI @State macros)
    var showMoreExportSettings = false
    var isCustomDurationEntry = false

    private var sourceBookmark: Data?
    /// Keeps a security-scoped source URL alive for playback/export while loaded.
    private var scopedSourceURL: URL?
    /// Keeps a security-scoped output folder alive after the open panel closes.
    private var scopedOutputURL: URL?

    // MARK: - Init

    init() {
        config = ExportConfig.load()
        appSettings = AppSettings.load()
        recentVideos = RecentVideo.loadAll()
        // Output names are session-specific. Always start with an empty field
        // instead of restoring a stale or malformed value from UserDefaults.
        if !config.customTitle.isEmpty {
            config.customTitle = ""
            config.save()
        }
        if config.splittingStrategy != .fast && config.splittingStrategy != .precise {
            config.splittingStrategy = .fast
            config.save()
        }
        isCustomDurationEntry = !SegmentDurationPreset.allCases.contains {
            abs(config.segmentDuration - $0.seconds) < 0.5
        }
        if let dir = config.outputDirectory {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
                config.outputDirectory = nil
            } else if dir.startAccessingSecurityScopedResource() {
                // Restored paths may not re-grant sandbox access; panel pick is required then.
                scopedOutputURL = dir
            }
        }
        // Do not touch NSApp here — application may not be ready until main.swift finishes setup.
    }

    // MARK: - Video loading

    func loadVideo(from url: URL) async {
        isLoadingVideo = true
        defer { isLoadingVideo = false }

        endSourceAccess()
        videoAsset = nil
        segments = []
        phase = .empty
        isPlaying = false
        player = nil
        stopTimeObserver()

        // Sandboxed picks / recent reopen need the security scope for metadata and playback.
        beginSourceAccess(for: url)

        let asset = VideoAsset(url: url)
        await asset.loadMetadata()

        if let error = asset.loadError {
            endSourceAccess()
            phase = .failed(message: appSettings.language.t(
                "Could not load video: \(error)",
                "无法加载视频: \(error)"
            ))
            return
        }
        guard asset.hasVideoTrack else {
            endSourceAccess()
            phase = .failed(message: appSettings.language.t(
                "This file has no video track.",
                "文件不包含视频轨道。"
            ))
            return
        }
        if let compatibilityError = asset.preciseExportCompatibilityError {
            endSourceAccess()
            phase = .failed(message: compatibilityError.localizedDescription)
            return
        }
        guard asset.durationSeconds >= 1 else {
            endSourceAccess()
            phase = .failed(message: appSettings.language.t(
                "Video is too short (under 1 second).",
                "视频时长过短（< 1 秒）。"
            ))
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
        observePlaybackEnd(for: p)

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
        let url = recent.url
        let probing = url.startAccessingSecurityScopedResource()
        let exists = FileManager.default.fileExists(atPath: url.path)
        if probing { url.stopAccessingSecurityScopedResource() }

        guard exists else {
            recentVideos.removeAll { $0.id == recent.id }
            RecentVideo.saveAll(recentVideos)
            phase = .failed(message: appSettings.language.t(
                "Recent file is missing or inaccessible: \(recent.fileName)",
                "最近文件已不存在或无法访问：\(recent.fileName)"
            ))
            return
        }
        await loadVideo(from: url)
    }

    private func beginSourceAccess(for url: URL) {
        endSourceAccess()
        if url.startAccessingSecurityScopedResource() {
            scopedSourceURL = url
        }
    }

    private func endSourceAccess() {
        if let scopedSourceURL {
            scopedSourceURL.stopAccessingSecurityScopedResource()
            self.scopedSourceURL = nil
        }
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
        if let endPlaybackObserver {
            NotificationCenter.default.removeObserver(endPlaybackObserver)
            self.endPlaybackObserver = nil
        }
    }

    private func observePlaybackEnd(for player: AVPlayer) {
        if let endPlaybackObserver {
            NotificationCenter.default.removeObserver(endPlaybackObserver)
            self.endPlaybackObserver = nil
        }
        guard let item = player.currentItem else { return }
        endPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
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
            frameDuration: asset.frameDuration,
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
        let lang = appSettings.language
        let count = segments.count
        guard count > 0 else { return lang.t("No clips yet.", "无切片") }
        if count == 1 { return lang.t("Exports as one complete clip.", "共 1 个视频") }
        let duration = formatShortDuration(config.segmentDuration)
        if let last = segments.last, last.durationSeconds < config.segmentDuration {
            return lang.t(
                "Splits into \(count) clips. \(count - 1) × \(duration), last clip is \(formatShortDuration(last.durationSeconds)).",
                "\(count) 个视频 — \(count - 1) × \(duration)，最后 1 个 \(formatShortDuration(last.durationSeconds))"
            )
        }
        return lang.t(
            "Splits into \(count) clips of \(duration).",
            "\(count) 个视频 — 每个 \(duration)"
        )
    }

    var destinationDisplayPath: String {
        guard let directory = config.outputDirectory else {
            return appSettings.language.t("Choose output folder", "选择导出文件夹")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return directory.path.replacingOccurrences(of: home, with: "~")
    }

    func requestReplacementFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        panel.prompt = appSettings.language.t("Replace", "替换")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.loadVideo(from: url) }
        }
    }

    // MARK: - Settings

    func setAppearance(_ appearance: AppAppearanceMode) {
        // Reassign the whole struct so @Observable always publishes UI updates.
        var next = appSettings
        next.appearance = appearance
        next.save()
        appSettings = next
        Self.applySystemAppearance(appearance)
    }

    /// Drives NSApp + SwiftUI so theme changes apply to the whole product.
    /// Call only after `NSApplication.shared` is live.
    static func applySystemAppearance(_ appearance: AppAppearanceMode) {
        let app = NSApplication.shared
        switch appearance {
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        case .automatic:
            app.appearance = nil
        }
    }

    func setLanguage(_ language: AppLanguage) {
        // Reassign so main window + settings window both refresh, not only the settings labels.
        var next = appSettings
        next.language = language
        next.save()
        appSettings = next
        ApplicationMenuCoordinator.refreshMenuTitles(language: language)
        SettingsWindowCoordinator.shared.refreshTitle(language: language)
    }

    func setPlaySoundWhenFinished(_ enabled: Bool) {
        var next = appSettings
        next.playSoundWhenFinished = enabled
        next.save()
        appSettings = next
    }

    func setPreferHardwareAcceleration(_ enabled: Bool) {
        var next = appSettings
        next.preferHardwareAcceleration = enabled
        next.save()
        appSettings = next
    }

    func setParallelFastExports(_ enabled: Bool) {
        var next = appSettings
        next.parallelFastExports = enabled
        next.save()
        appSettings = next
    }

    func useDownloadsAsDefaultDestination() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloads else { return }
        setOutputDirectory(downloads)
    }

    func resetAllDefaults() {
        appSettings = AppSettings.reset()
        let fresh = ExportConfig()
        // Preserve nothing — full product defaults.
        fresh.save()
        config = fresh
        if let dir = config.outputDirectory,
           dir.startAccessingSecurityScopedResource() {
            scopedOutputURL = dir
        }
        recalculateSegments()
    }

    func setSegmentDuration(_ seconds: TimeInterval, customEntry: Bool? = nil) {
        guard seconds >= 1 else { return }
        config.segmentDuration = validSegmentDuration(seconds, videoDuration: videoDuration)
        config.save()
        if let customEntry {
            isCustomDurationEntry = customEntry
        } else if !isCustomDurationEntry {
            isCustomDurationEntry = !SegmentDurationPreset.allCases.contains {
                abs(config.segmentDuration - $0.seconds) < 0.5
            }
        }
        recalculateSegments()
    }

    func selectDurationPreset(_ preset: SegmentDurationPreset) {
        setSegmentDuration(preset.seconds, customEntry: false)
    }

    func beginCustomDurationEntry() {
        isCustomDurationEntry = true
    }

    func toggleMoreExportSettings() {
        showMoreExportSettings.toggle()
    }

    func setOutputFormat(_ format: OutputFormat) {
        config.outputFormat = format
        config.save()
        recalculateSegments()
    }

    func setVideoCodec(_ codec: VideoCodecPreference) {
        config.videoCodec = codec
        config.save()
    }

    func setResolution(_ resolution: ExportResolution) {
        config.resolution = resolution
        config.save()
    }

    func setSplittingStrategy(_ strategy: SplittingStrategy) {
        config.splittingStrategy = strategy
        config.save()
    }

    func cycleAppearance() {
        let next: AppAppearanceMode = switch appSettings.appearance {
        case .automatic: .light
        case .light: .dark
        case .dark: .automatic
        }
        setAppearance(next)
    }

    var sourceCodecBadge: String {
        guard let asset = videoAsset else { return "—" }
        let codec = asset.videoCodec.uppercased()
        switch codec.lowercased() {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "": return asset.url.pathExtension.uppercased()
        default: return codec
        }
    }

    /// Design-style clock: 00:00.00
    var currentTimeDetailed: String { formatPlayhead(currentTime) }
    var durationDetailed: String { formatPlayhead(videoDuration) }

    private func formatPlayhead(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00.00" }
        let totalCs = Int((seconds * 100).rounded())
        let cs = totalCs % 100
        let totalSec = totalCs / 100
        let m = totalSec / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }

    func setOutputDirectory(_ url: URL) {
        if let scopedOutputURL {
            scopedOutputURL.stopAccessingSecurityScopedResource()
            self.scopedOutputURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            scopedOutputURL = url
        }
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
        let lang = appSettings.language
        guard let outputDir = config.outputDirectory else {
            phase = .failed(message: lang.t("Choose an export folder first.", "请先选择导出目录。"))
            return
        }
        guard FileManager.default.isWritableFile(atPath: outputDir.path) else {
            phase = .failed(message: lang.t("Export folder is not writable.", "导出目录不可写。"))
            return
        }
        let spaceMultiplier: Int64 = config.splittingStrategy == .fast ? 2 : 3
        if let free = freeSpace(at: outputDir),
           asset.fileSize > 0,
           free < asset.fileSize * spaceMultiplier / 2 {
            phase = .failed(message: lang.t("Not enough free disk space.", "磁盘空间可能不足。"))
            return
        }

        let modeLabel = config.splittingStrategy == .fast
            ? lang.t("Fast stream-copy", "快速直通")
            : lang.t("Precise re-encode", "精确重编码")
        exportLogs = [
            lang.t("[BiCut Core] Starting export engine…", "[BiCut Core] 初始化导出引擎…"),
            lang.t("[BiCut Core] Mode: \(modeLabel)", "[BiCut Core] 模式: \(modeLabel)"),
            lang.t("[BiCut Core] Analyzing video tracks…", "[BiCut Core] 分析视频轨道结构…")
        ]

        let exportSegments: [SegmentInfo]
        do {
            switch config.splittingStrategy {
            case .precise:
                exportSegments = try await VideoAsset.resolveFrameAlignedSegments(
                    at: asset.url,
                    plannedSegments: segments
                )
                exportLogs.append(lang.t(
                    "[BiCut Core] Cuts aligned to source frames",
                    "[BiCut Core] 切点已按源视频帧对齐"
                ))
            case .fast:
                // Keep planned timeline; passthrough may snap starts to prior keyframes.
                exportSegments = segments
                exportLogs.append(lang.t(
                    "[BiCut Core] Fast mode: cuts may snap to nearby keyframes",
                    "[BiCut Core] 快速模式：切点可能回退到附近关键帧"
                ))
            }

            guard let firstSegment = exportSegments.first else { return }
            let preflightURL = outputDir.appendingPathComponent(firstSegment.fileName)
            let preflight = VideoProcessor(
                asset: asset.avAsset,
                segment: firstSegment,
                outputURL: preflightURL,
                config: config
            )
            preflight.onWarning = { [weak self] warning in
                Task { @MainActor in
                    guard let self else { return }
                    self.appendExportLog(self.appSettings.language.t("[Note] \(warning)", "[提示] \(warning)"))
                }
            }
            try await preflight.validateConfiguration()
        } catch {
            let prefix = config.splittingStrategy == .fast
                ? lang.t("Could not start fast split", "无法开始快速分片")
                : lang.t("Could not start precise split", "无法开始精确分片")
            phase = .failed(message: "\(prefix): \(error.localizedDescription)")
            return
        }
        segments = exportSegments

        exportStartTime = Date()
        exportSpeed = 0
        exportETA = 0

        let concurrency = (config.splittingStrategy == .fast && appSettings.parallelFastExports) ? 2 : 1
        let pipeline = ExportPipeline(
            asset: asset,
            config: config,
            segments: exportSegments,
            outputDir: outputDir,
            maxConcurrent: concurrency
        )

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
                        guard let self else { return }
                        self.appendExportLog(self.appSettings.language.t(
                            "[Compatibility] \(warning)",
                            "[兼容性提示] \(warning)"
                        ))
                    }
                }
            )
        } catch is CancellationError {
            if assertionID != 0 { IOPMAssertionRelease(assertionID) }
            exportLogs.append(lang.t("[BiCut Core] Export cancelled", "[BiCut Core] 导出已取消"))
            phase = .loaded
            return
        } catch {
            if assertionID != 0 { IOPMAssertionRelease(assertionID) }
            exportLogs.append(lang.t(
                "[BiCut Core] Error: \(error.localizedDescription)",
                "[BiCut Core] 错误: \(error.localizedDescription)"
            ))
            phase = .failed(message: lang.t(
                "Export failed: \(error.localizedDescription)",
                "导出失败: \(error.localizedDescription)"
            ))
            return
        }

        if assertionID != 0 { IOPMAssertionRelease(assertionID) }

        switch result {
        case .completed:
            exportLogs.append(lang.t(
                "[BiCut Core] ✅ Export complete — \(segments.count) files",
                "[BiCut Core] ✅ 导出完成 — \(segments.count) 个文件"
            ))
            phase = .completed(outputURL: outputDir)
            if appSettings.playSoundWhenFinished {
                NSSound(named: "Glass")?.play()
            }
        case .cancelled:
            exportLogs.append(lang.t("[BiCut Core] Export cancelled", "[BiCut Core] 导出已取消"))
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
        phase = videoAsset == nil ? .empty : .loaded
    }

    /// Dismiss a failure card and return to the nearest safe idle state.
    func dismissFailure() {
        resetToIdle()
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
