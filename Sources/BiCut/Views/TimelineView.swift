import SwiftUI

// MARK: - Local state for timeline

@Observable
final class TimelineLocalState {
    var dragValue: Double = 0
    var isDragging = false
}

// MARK: - View

struct TimelineView: View {
    let model: AppViewModel
    private let local = TimelineLocalState()

    private let minDuration: Double = 15
    private let maxDuration: Double = 3600
    private let stepDuration: Double = 15

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                sliderRow
                timelineBar
                summaryText
            }
        } label: {
            Text("分片设置")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Slider row

    private var sliderRow: some View {
        let maxDur = effectiveMaxDuration
        let minDur = minDuration
        // Safety: only render Slider when range is valid
        guard maxDur > minDur else {
            return AnyView(Text("加载中...").font(.subheadline).foregroundColor(.secondary))
        }

        return AnyView(HStack(spacing: 12) {
            Text("分片时长:")
                .font(.subheadline)

            Slider(
                value: Binding(
                    get: { model.config.segmentDuration },
                    set: { newValue in
                        let clamped = min(newValue, effectiveMaxDuration)
                        let rounded = (clamped / stepDuration).rounded() * stepDuration
                        let final = max(minDuration, rounded)
                        if final != model.config.segmentDuration {
                            model.setSegmentDuration(final)
                        }
                    }
                ),
                in: minDuration ... effectiveMaxDuration,
                step: stepDuration
            )
            .disabled(model.phase.isExporting)

            Text(formatDuration(Int(model.config.segmentDuration)))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 60, alignment: .trailing)

            HStack(spacing: 4) {
                Button {
                    adjustDuration(by: -stepDuration)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(model.config.segmentDuration <= minDuration || model.phase.isExporting)

                Button {
                    adjustDuration(by: stepDuration)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(model.config.segmentDuration >= effectiveMaxDuration || model.phase.isExporting)
            }
        })
    }

    // MARK: - Timeline bar

    private var timelineBar: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width
            let totalSec = model.videoAsset?.durationSeconds ?? 0
            let segSec = model.config.segmentDuration
            let count = model.segments.count

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 24)

                if totalSec > 0, count > 0 {
                    ForEach(0 ..< count, id: \.self) { i in
                        let xPos = min(Double(i) * segSec / totalSec * barWidth, barWidth - 1)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.6))
                            .frame(width: 2, height: 24)
                            .offset(x: xPos)
                    }
                }

                if totalSec > 0, count > 0 {
                    ForEach(0 ..< count, id: \.self) { i in
                        let startX = Double(i) * segSec / totalSec * barWidth
                        let endX = min(Double(i + 1) * segSec / totalSec * barWidth, barWidth)
                        let width = max(endX - startX, 1)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(segmentColor(index: i, total: count))
                            .frame(width: width, height: 20)
                            .offset(x: startX + 2, y: 2)
                    }
                }

                if local.isDragging {
                    let handleX = min(local.dragValue / effectiveMaxDuration * barWidth, barWidth - 4)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: handleX - 5, y: 7)
                        .shadow(radius: 2)
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: - Summary text

    @ViewBuilder
    private var summaryText: some View {
        let count = model.segments.count
        if count > 0 {
            if count == 1 {
                Text("共 1 个分片（完整视频）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                let segSec = model.config.segmentDuration
                let segLabel = formatDuration(Int(segSec))
                let lastDuration = model.segments.last?.durationSeconds ?? 0
                let lastLabel = formatDuration(Int(lastDuration.rounded()))
                if lastDuration < segSec {
                    Text("共 \(count) 个分片，前 \(count - 1) 个各 \(segLabel)，最后 1 个 \(lastLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text("共 \(count) 个分片，每个 \(segLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Helpers

    private var effectiveMaxDuration: Double {
        let dur = model.videoAsset?.durationSeconds ?? maxDuration
        return max(minDuration + stepDuration, dur)
    }

    private func adjustDuration(by delta: Double) {
        let new = model.config.segmentDuration + delta
        let clamped = max(minDuration, min(new, effectiveMaxDuration))
        model.setSegmentDuration(clamped)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 {
            return "\(m) 分钟"
        }
        return "\(m)分\(s)秒"
    }

    private func segmentColor(index: Int, total: Int) -> Color {
        let fraction = total > 1 ? Double(index) / Double(total - 1) : 0.5
        return Color(hue: 0.55 + fraction * 0.3, saturation: 0.6, brightness: 0.75)
    }
}
