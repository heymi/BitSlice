import SwiftUI

struct ContentView: View {
    let model: AppViewModel

    var body: some View {
        ZStack {
            if model.videoAsset == nil {
                DropZoneView(model: model).padding(40)
            } else {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            videoStage
                            segmentTimeline
                            Spacer(minLength: 0)
                        }
                        Divider()
                        InspectorSidebarView(model: model).frame(width: 340)
                    }
                }
            }

            if case .exporting = model.phase {
                ProcessingSheetView(model: model)
            }
            if case .completed = model.phase {
                FinderPreviewView(model: model)
            }
        }
    }

    private var videoStage: some View {
        VStack(spacing: 6) {
            ZStack {
                if let player = model.player {
                    VideoPlayerViewRepresentable(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.5))
                        .aspectRatio(16/9, contentMode: .fit)
                }
                if !model.isPlaying {
                    Image(systemName: "play.fill").font(.largeTitle).foregroundColor(.white.opacity(0.6))
                }
            }
            .onTapGesture { model.togglePlayback() }

            HStack(spacing: 14) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.body)
                }.buttonStyle(.plain)
                Button { model.stepFrame(forward: false) } label: {
                    Image(systemName: "backward.frame").font(.caption)
                }.buttonStyle(.plain)
                Button { model.stepFrame(forward: true) } label: {
                    Image(systemName: "forward.frame").font(.caption)
                }.buttonStyle(.plain)
                Text("\(formatMMSS(model.currentTime)) / \(formatMMSS(model.videoDuration))")
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                Spacer()
                Button { model.toggleMute() } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.caption)
                }.buttonStyle(.plain)
                Menu {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { s in
                        Button("\(String(format: "%.1f", s))×") { model.setSpeed(s) }
                    }
                } label: {
                    Text("\(String(format: "%.1f", model.playbackSpeed))×")
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }.menuStyle(.borderlessButton).frame(width: 44)
            }
            .padding(.horizontal, 10)
        }
        .padding(14)
    }

    private var segmentTimeline: some View {
        let totalSec = model.videoDuration
        let count = model.segments.count
        let colors: [(bg: Color, text: Color)] = [
            (Color.indigo.opacity(0.18), Color.indigo),
            (Color.green.opacity(0.18), Color.green),
            (Color.orange.opacity(0.18), Color.orange),
            (Color.pink.opacity(0.18), Color.pink),
            (Color.cyan.opacity(0.18), Color.cyan),
            (Color.purple.opacity(0.18), Color.purple),
            (Color.yellow.opacity(0.18), Color.yellow),
            (Color.teal.opacity(0.18), Color.teal),
        ]
        return VStack(spacing: 4) {
            if count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, seg in
                            let w = totalSec > 0 ? max(seg.durationSeconds / totalSec * 600, 38) : 38
                            let c = colors[i % colors.count]
                            let active = model.activeSegmentIndex == i
                            Button { model.seekTo(seconds: seg.startSeconds) } label: {
                                VStack(spacing: 1) {
                                    Text("\(i + 1)").font(.system(size: 9, design: .monospaced)).fontWeight(.medium)
                                    Text(formatMMSS(seg.durationSeconds)).font(.system(size: 7, design: .monospaced))
                                }
                                .foregroundColor(c.text).frame(width: w).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 4).fill(c.bg))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(active ? Color.blue : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(Color.blue).frame(width: max(4, CGFloat(model.playbackProgress)) * 600, height: 4)
                Circle().fill(Color.blue).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .offset(x: max(-4, CGFloat(model.playbackProgress)) * 600 - 6)
            }
            .frame(height: 16).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                model.seekTo(seconds: max(0, min(1, v.location.x / 600)) * model.videoDuration)
            })
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
    }
}

func formatMMSS(_ s: Double) -> String {
    guard s.isFinite else { return "0:00" }
    let t = Int(s.rounded())
    return String(format: "%d:%02d", t / 60, t % 60)
}

final class WindowDelegate: NSObject, NSWindowDelegate {
    let model: AppViewModel
    init(model: AppViewModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.phase.isExporting {
            let a = NSAlert(); a.messageText = "正在导出中"; a.informativeText = "确定要取消吗？"
            a.alertStyle = .warning; a.addButton(withTitle: "继续导出"); a.addButton(withTitle: "关闭")
            if a.runModal() == .alertSecondButtonReturn { model.cancelExport(); return true }
            return false
        }
        NSApp.terminate(nil); return true
    }
}
