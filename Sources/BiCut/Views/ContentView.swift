import SwiftUI

enum BiCutTheme {
    static let canvas = Color(red: 0.055, green: 0.057, blue: 0.068)
    static let chrome = Color(red: 0.069, green: 0.071, blue: 0.082)
    static let panel = Color(red: 0.082, green: 0.084, blue: 0.097)
    static let elevated = Color.white.opacity(0.055)
    static let control = Color.black.opacity(0.16)
    static let border = Color.white.opacity(0.06)
    static let muted = Color.white.opacity(0.46)
    static let blue = Color(red: 0.18, green: 0.48, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.0)
    static let largeRadius: CGFloat = 20
    static let controlRadius: CGFloat = 11
}

struct ContentView: View {
    let model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BiCutTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                appHeader

                if model.videoAsset == nil {
                    DropZoneView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    workspace
                }

                statusBar
            }

            if case .exporting = model.phase { ProcessingSheetView(model: model) }
            if case .completed = model.phase { FinderPreviewView(model: model) }
        }
        .preferredColorScheme(.dark)
        .tint(BiCutTheme.blue)
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 22) {
                sourceCard
                videoWorkspace
                Spacer(minLength: 0)
            }
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            InspectorSidebarView(model: model)
                .frame(width: 408)
        }
    }

    private var appHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 10) {
                Text("BiCut")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 0.0, green: 0.75, blue: 0.55)).frame(width: 7, height: 7)
                    Text(model.videoAsset == nil ? "Ready to slice" : "Ready to export")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BiCutTheme.muted)
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.045)))
            }
            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(height: 62)
        .background(.thinMaterial)
    }

    private var sourceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(BiCutTheme.blue.opacity(0.13))
                Image(systemName: "film")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(red: 0.26, green: 0.60, blue: 1.0))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.videoAsset?.fileName ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sourceMetadata)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BiCutTheme.muted)
            }
            Spacer()
            Button { model.requestReplacementFile() } label: {
                Label("Replace File", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 17).frame(height: 36)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .contentShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 18)
        .frame(height: 84)
        .background(RoundedRectangle(cornerRadius: BiCutTheme.largeRadius).fill(BiCutTheme.panel))
    }

    private var videoWorkspace: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let player = model.player {
                    VideoPlayerViewRepresentable(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }
                if !model.isPlaying {
                    Button { model.togglePlayback() } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(.black.opacity(0.56)))
                            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { model.togglePlayback() }

            segmentTimeline
        }
        .background(BiCutTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: BiCutTheme.largeRadius))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var segmentTimeline: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Clips · \(model.segments.count)", systemImage: "scissors")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Text("Select a clip to preview its start")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BiCutTheme.muted)
            }

            GeometryReader { geometry in
                let total = max(model.videoDuration, 1)
                HStack(spacing: 4) {
                    ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                        let fraction = segment.durationSeconds / total
                        Button { model.seekTo(seconds: segment.startSeconds) } label: {
                            Text("#\(index + 1)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(segmentTextColor(index))
                            .frame(width: max(48, (geometry.size.width - CGFloat(max(model.segments.count - 1, 0)) * 4) * fraction), height: 38)
                            .background(RoundedRectangle(cornerRadius: 9).fill(model.activeSegmentIndex == index ? segmentTextColor(index).opacity(0.24) : segmentFillColor(index)))
                            .shadow(color: model.activeSegmentIndex == index ? segmentTextColor(index).opacity(0.18) : .clear, radius: 7, y: 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }
            .frame(height: 38)

            GeometryReader { geometry in
                let x = CGFloat(model.playbackProgress) * geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    Capsule().fill(BiCutTheme.blue).frame(width: max(0, x), height: 3)
                    Circle().fill(BiCutTheme.blue).frame(width: 13, height: 13)
                        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: BiCutTheme.blue.opacity(0.38), radius: 6)
                        .offset(x: min(max(0, x - 6.5), geometry.size.width - 13))
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    model.seekTo(seconds: max(0, min(1, value.location.x / geometry.size.width)) * model.videoDuration)
                })
            }
            .frame(height: 16)

            HStack {
                Text(formatTimestamp(model.currentTime))
                Spacer()
                Text(formatTimestamp(model.videoDuration))
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(BiCutTheme.muted)
        }
        .padding(26)
    }

    private var statusBar: some View {
        HStack {
            Label(model.videoAsset == nil ? "Choose a video to begin" : "Ready to export", systemImage: model.videoAsset == nil ? "film" : "checkmark.circle")
            Spacer()
            Text(model.videoAsset == nil ? "Local processing" : "\(formatShortDuration(model.videoDuration)) source")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(BiCutTheme.muted)
        .padding(.horizontal, 26)
        .frame(height: 46)
        .background(.thinMaterial)
    }

    private var sourceMetadata: String {
        guard let asset = model.videoAsset else { return "" }
        let width = Int(asset.naturalSize.width.rounded())
        let height = Int(asset.naturalSize.height.rounded())
        return "\(width)×\(height)  ·  \(Int(asset.frameRate.rounded())) fps  ·  \(formatShortDuration(asset.durationSeconds))  ·  \(ByteCountFormatter.string(fromByteCount: asset.fileSize, countStyle: .file))"
    }

    private func segmentTextColor(_ index: Int) -> Color {
        [Color(red: 0.49, green: 0.50, blue: 1), Color(red: 0.0, green: 0.81, blue: 0.55), BiCutTheme.amber, Color(red: 1, green: 0.36, blue: 0.65)][index % 4]
    }

    private func segmentFillColor(_ index: Int) -> Color { segmentTextColor(index).opacity(0.14) }
}

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
    if seconds >= 60 { return formatMMSS(seconds) }
    let rounded = seconds.rounded()
    return rounded == seconds ? "\(Int(rounded))s" : String(format: "%.1fs", seconds)
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    let model: AppViewModel
    init(model: AppViewModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.phase.isExporting {
            let alert = NSAlert()
            alert.messageText = "正在导出中"
            alert.informativeText = "确定要取消吗？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "继续导出")
            alert.addButton(withTitle: "关闭")
            if alert.runModal() == .alertSecondButtonReturn { model.cancelExport(); return true }
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
