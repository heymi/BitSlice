import AppKit
import SwiftUI

// MARK: - Design tokens (adaptive; dark matches mockup)

enum BeCutTheme {
    static let canvas = adaptive(
        dark: NSColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1),
        light: NSColor(red: 0.93, green: 0.93, blue: 0.945, alpha: 1)
    )
    static let panel = adaptive(
        dark: NSColor(red: 0.110, green: 0.110, blue: 0.122, alpha: 1),
        light: .white
    )
    static let control = adaptive(
        dark: NSColor(red: 0.137, green: 0.137, blue: 0.157, alpha: 1),
        light: NSColor(red: 0.94, green: 0.94, blue: 0.955, alpha: 1)
    )
    static let elevated = adaptive(
        dark: NSColor.white.withAlphaComponent(0.06),
        light: NSColor.black.withAlphaComponent(0.05)
    )
    static let well = adaptive(
        dark: NSColor.white.withAlphaComponent(0.04),
        light: NSColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
    )
    static let stroke = adaptive(
        dark: NSColor.white.withAlphaComponent(0.08),
        light: NSColor.black.withAlphaComponent(0.09)
    )
    static let hairline = adaptive(
        dark: NSColor.white.withAlphaComponent(0.06),
        light: NSColor.black.withAlphaComponent(0.08)
    )

    static let label = adaptive(dark: NSColor.white.withAlphaComponent(0.92), light: NSColor(white: 0.08, alpha: 1))
    static let secondaryLabel = adaptive(
        dark: NSColor.white.withAlphaComponent(0.48),
        light: NSColor.black.withAlphaComponent(0.48)
    )
    static let tertiaryLabel = adaptive(
        dark: NSColor.white.withAlphaComponent(0.32),
        light: NSColor.black.withAlphaComponent(0.34)
    )
    static let muted = secondaryLabel
    static let primary = label

    static let blue = Color(red: 0.22, green: 0.45, blue: 1.0)
    static let blueBright = Color(red: 0.28, green: 0.48, blue: 1.0)
    static let blueSoft = adaptive(
        dark: NSColor(red: 0.18, green: 0.40, blue: 0.95, alpha: 0.18),
        light: NSColor(red: 0.18, green: 0.40, blue: 0.95, alpha: 0.10)
    )
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.18)
    static let success = Color(red: 0.20, green: 0.82, blue: 0.52)
    static let danger = Color(red: 0.95, green: 0.32, blue: 0.32)
    static let onAccent = Color.white

    static let scrim = adaptive(
        dark: NSColor.black.withAlphaComponent(0.52),
        light: NSColor.black.withAlphaComponent(0.28)
    )
    static let cardShadow = adaptive(
        dark: NSColor.black.withAlphaComponent(0.45),
        light: NSColor.black.withAlphaComponent(0.08)
    )
    static let cardShadowRadius: CGFloat = 18
    static let cardShadowY: CGFloat = 8

    static let largeRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let sidebarWidth: CGFloat = 360

    static let sliceColors: [Color] = [
        Color(red: 0.35, green: 0.45, blue: 0.98),
        Color(red: 0.20, green: 0.72, blue: 0.55),
        Color(red: 0.85, green: 0.65, blue: 0.18),
        Color(red: 0.78, green: 0.35, blue: 0.70)
    ]

    /// Pill control used across settings (design-aligned).
    static func settingsPillBackground(emphasized: Bool = false) -> Color {
        emphasized ? control : elevated
    }

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    func becutCard(radius: CGFloat = BeCutTheme.largeRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(BeCutTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(BeCutTheme.stroke, lineWidth: 1)
        )
    }

    func becutModalChrome(radius: CGFloat = 22) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(BeCutTheme.panel)
                .shadow(color: BeCutTheme.cardShadow, radius: 28, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(BeCutTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Root

struct ContentView: View {
    let model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: AppLanguage { model.appSettings.language }

    var body: some View {
        ZStack {
            BeCutTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                appHeader
                if model.videoAsset == nil {
                    DropZoneView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(!model.isLoadingVideo && !model.phase.isExporting)
                } else {
                    workspace
                }
                statusBar
            }

            if model.isLoadingVideo { loadingOverlay }
            if case .exporting = model.phase { ProcessingSheetView(model: model) }
            if case .completed = model.phase { FinderPreviewView(model: model) }
            if case .failed(let message) = model.phase {
                FailureSheetView(model: model, message: message)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(BeCutTheme.blue)
        .environment(\.locale, Locale(identifier: lang.localeIdentifier))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.isLoadingVideo)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.appSettings.appearance)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.appSettings.language)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.appSettings.appearance {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    // MARK: Header (BeCut + core badge + theme/help)

    private var appHeader: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 68) // traffic-light clearance

            HStack(spacing: 10) {
                Text("BeCut")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BeCutTheme.label)

                HStack(spacing: 7) {
                    Circle()
                        .fill(BeCutTheme.success)
                        .frame(width: 6, height: 6)
                    Text("Slicer Core \(BeCutAppMetadata.versionLabel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BeCutTheme.secondaryLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(BeCutTheme.elevated))
                .overlay(Capsule().stroke(BeCutTheme.stroke, lineWidth: 1))
            }

            Spacer()

            HStack(spacing: 4) {
                headerIconButton(
                    systemName: "gearshape",
                    help: lang.t("Settings", "设置")
                ) {
                    SettingsWindowCoordinator.shared.show(model: model)
                }
                headerIconButton(
                    systemName: model.appSettings.appearance == .light ? "moon" : "sun.max",
                    help: lang.t("Toggle appearance", "切换外观")
                ) {
                    model.cycleAppearance()
                }
                headerIconButton(systemName: "questionmark.circle", help: lang.t("Support", "支持")) {
                    NSWorkspace.shared.open(BeCutAppMetadata.supportURL)
                }
            }
        }
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(BeCutTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BeCutTheme.hairline).frame(height: 1)
        }
    }

    private func headerIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BeCutTheme.secondaryLabel)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Workspace

    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                sourceReplaceCard
                livePreviewStage
                interactiveSlices
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle().fill(BeCutTheme.hairline).frame(width: 1)

            InspectorSidebarView(model: model)
                .frame(width: BeCutTheme.sidebarWidth)
        }
    }

    // MARK: Source + Replace (retained from previous UI)

    private var sourceReplaceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(BeCutTheme.blueSoft)
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(BeCutTheme.blue)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.videoAsset?.fileName ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BeCutTheme.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sourceMetadataLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BeCutTheme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button { model.requestReplacementFile() } label: {
                Label(lang.t("Replace File", "替换文件"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(BeCutTheme.control))
                    .overlay(Capsule().stroke(BeCutTheme.stroke, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .foregroundStyle(BeCutTheme.label)
            .help(lang.t("Choose a different source video", "选择其他源视频"))
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .becutCard(radius: 14)
    }

    private var sourceMetadataLine: String {
        guard let asset = model.videoAsset else { return "" }
        let width = Int(asset.naturalSize.width.rounded())
        let height = Int(asset.naturalSize.height.rounded())
        let fps = Int(asset.frameRate.rounded())
        let size = ByteCountFormatter.string(fromByteCount: asset.fileSize, countStyle: .file)
        return "\(width)×\(height)  ·  \(fps) fps  ·  \(formatShortDuration(asset.durationSeconds))  ·  \(size)"
    }

    // MARK: Live Preview

    private var livePreviewStage: some View {
        ZStack {
            Color.black

            if let player = model.player {
                VideoPlayerViewRepresentable(player: player)
                    .aspectRatio(previewAspect, contentMode: .fit)
            }

            // Badges
            VStack {
                HStack {
                    previewBadge(lang.t("Live Preview", "实时预览"))
                    Spacer()
                    previewBadge(model.sourceCodecBadge)
                }
                .padding(12)
                Spacer()
            }

            // Center play / pause
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .offset(x: model.isPlaying ? 0 : 1)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.white.opacity(model.isPlaying ? 0.10 : 0.14)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .opacity(model.isPlaying ? 0.0 : 1.0)
            .animation(.easeOut(duration: 0.15), value: model.isPlaying)
            // Keep the control hit-testable while playing via bottom bar; center stays visual when paused.
            .allowsHitTesting(!model.isPlaying)

            // Bottom transport
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button { model.togglePlayback() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(model.isPlaying
                          ? lang.t("Pause", "暂停")
                          : lang.t("Play", "播放"))

                    Text("\(model.currentTimeDetailed) / \(model.durationDetailed)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))

                    Spacer()

                    Button { model.toggleMute() } label: {
                        Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .aspectRatio(previewAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BeCutTheme.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.togglePlayback() }
        .contextMenu {
            Button(lang.t("Replace File…", "替换文件…")) { model.requestReplacementFile() }
        }
    }

    private var previewAspect: CGFloat {
        guard let size = model.videoAsset?.naturalSize, size.height > 0 else { return 16 / 9 }
        return max(0.5, min(size.width / size.height, 2.4))
    }

    private func previewBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.48)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Interactive slices

    private var interactiveSlices: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(lang.t("INTERACTIVE SLICES (\(model.segments.count))", "交互切片 (\(model.segments.count))"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                } icon: {
                    Image(systemName: "scissors")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BeCutTheme.blue)
                }
                .foregroundStyle(BeCutTheme.secondaryLabel)

                Spacer()

                Text(lang.t("Click slices to preview cut start-points", "点击切片预览起点"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BeCutTheme.tertiaryLabel)
            }

            HStack(spacing: 8) {
                ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                    sliceChip(index: index, segment: segment)
                }
            }

            // Scrubber
            GeometryReader { geometry in
                let x = CGFloat(model.playbackProgress) * geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    Capsule()
                        .fill(BeCutTheme.blue)
                        .frame(width: max(0, x), height: 3)
                    Circle()
                        .fill(BeCutTheme.blue)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                        .shadow(color: BeCutTheme.blue.opacity(0.45), radius: 5)
                        .offset(x: min(max(0, x - 6), geometry.size.width - 12))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let p = max(0, min(1, value.location.x / max(geometry.size.width, 1)))
                        model.seekTo(seconds: p * model.videoDuration)
                    }
                )
            }
            .frame(height: 16)

            HStack {
                Text(formatTimestamp(model.currentTime))
                Spacer()
                Text(formatTimestamp(model.videoDuration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(BeCutTheme.tertiaryLabel)
        }
        .padding(16)
        .becutCard(radius: 14)
    }

    private func sliceChip(index: Int, segment: SegmentInfo) -> some View {
        let color = BeCutTheme.sliceColors[index % BeCutTheme.sliceColors.count]
        let active = model.activeSegmentIndex == index
        return Button {
            model.seekTo(seconds: segment.startSeconds)
        } label: {
            Text("#\(index + 1)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(active ? 1 : 0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(color.opacity(active ? 0.16 : 0.08))
                        if active {
                            color.frame(width: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(color.opacity(active ? 0.85 : 0.35), lineWidth: active ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            Label {
                Text(lang.t("macOS Environment: Unified Canvas", "macOS 环境：统一画布"))
            } icon: {
                Image(systemName: "desktopcomputer")
            }
            Spacer()
            Text(lang.t(
                "Timeline: \(formatShortDuration(model.config.segmentDuration))",
                "时间轴: \(formatShortDuration(model.config.segmentDuration))"
            ))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(BeCutTheme.tertiaryLabel)
        .padding(.horizontal, 18)
        .frame(height: 36)
        .background(BeCutTheme.canvas)
        .overlay(alignment: .top) {
            Rectangle().fill(BeCutTheme.hairline).frame(height: 1)
        }
    }

    // MARK: Loading

    private var loadingOverlay: some View {
        ZStack {
            BeCutTheme.scrim.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(BeCutTheme.blue)
                Text(lang.t("Reading video…", "正在读取视频…"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BeCutTheme.label)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .becutModalChrome(radius: 18)
        }
    }
}

// MARK: - Shared controls

struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.08)
                    : .interactiveSpring(response: 0.22, dampingFraction: 1, blendDuration: 0),
                value: configuration.isPressed
            )
    }
}

func formatMMSS(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = Int(seconds.rounded())
    return String(format: "%d:%02d", value / 60, value % 60)
}

func formatTimestamp(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00" }
    let value = Int(seconds.rounded())
    return String(format: "%02d:%02d", value / 60, value % 60)
}

func formatShortDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0s" }
    if seconds >= 60 {
        let m = Int(seconds) / 60
        let s = Int(seconds.rounded()) % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
    let rounded = seconds.rounded()
    if abs(rounded - seconds) < 0.05 {
        return "\(Int(rounded))s"
    }
    return String(format: "%.1fs", seconds)
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    let model: AppViewModel
    init(model: AppViewModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.phase.isExporting {
            let lang = model.appSettings.language
            let alert = NSAlert()
            alert.messageText = lang.t("Export in progress", "正在导出")
            alert.informativeText = lang.t("Cancel export and close?", "取消导出并关闭？")
            alert.alertStyle = .warning
            alert.addButton(withTitle: lang.t("Keep Exporting", "继续导出"))
            alert.addButton(withTitle: lang.t("Close", "关闭"))
            if alert.runModal() == .alertSecondButtonReturn {
                model.cancelExport()
                return true
            }
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
