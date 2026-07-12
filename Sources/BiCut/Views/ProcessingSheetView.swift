import SwiftUI

// MARK: - Processing Sheet

struct ProcessingSheetView: View {
    let model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isChinese: Bool {
        model.appSettings.language == .simplifiedChinese
    }

    private var isFast: Bool {
        model.config.splittingStrategy == .fast
    }

    private var exportTitle: String {
        if isFast {
            return isChinese ? "正在快速分片" : "Fast splitting"
        }
        return isChinese ? "正在精确分片" : "Precise splitting"
    }

    private var exportSubtitle: String {
        if isFast {
            return isChinese
                ? "直通复制码流，尽量不重编码。切点可能略提前到关键帧。"
                : "Stream-copying when possible. Cuts may snap slightly earlier to a keyframe."
        }
        return isChinese
            ? "正在按帧对齐并重新编码，请保持 BiCut 开启。"
            : "Aligning cuts to source frames and re-encoding. Keep BiCut open."
    }

    var body: some View {
        ZStack {
            BiCutTheme.scrim
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 20) {
                if case .exporting(let current, let total, let overall, _) = model.phase {
                    VStack(spacing: 6) {
                        Text(exportTitle)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(BiCutTheme.label)
                        Text(exportSubtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BiCutTheme.secondaryLabel)
                            .multilineTextAlignment(.center)
                    }

                    progressCircle(current: current, total: total, overall: overall)
                    telemetryPanel(current: current, total: total, overall: overall)
                    logTerminal

                    Button {
                        model.cancelExport()
                    } label: {
                        Text(isChinese ? "取消导出" : "Cancel export")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BiCutTheme.danger)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Capsule().fill(BiCutTheme.danger.opacity(0.10)))
                            .overlay(Capsule().stroke(BiCutTheme.danger.opacity(0.22), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .frame(width: 460)
            .padding(32)
            .bicutModalChrome()
        }
    }

    // MARK: - Progress Circle

    private func progressCircle(current: Int, total: Int, overall: Double) -> some View {
        ZStack {
            Circle()
                .stroke(BiCutTheme.control, lineWidth: 6)
                .frame(width: 100, height: 100)

            Circle()
                .trim(from: 0, to: CGFloat(overall))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [BiCutTheme.blue, .indigo, .purple]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 1),
                    value: overall
                )

            VStack(spacing: 0) {
                Text("\(Int(overall * 100))")
                    .font(.title.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(BiCutTheme.label)
                Text("%")
                    .font(.caption)
                    .foregroundStyle(BiCutTheme.secondaryLabel)
            }
        }
    }

    // MARK: - Telemetry

    private func telemetryPanel(current: Int, total: Int, overall: Double) -> some View {
        HStack(spacing: 32) {
            TelemetryItem(label: isChinese ? "切片" : "Clip", value: "\(current + 1) / \(total)")
            TelemetryItem(label: isChinese ? "速度" : "Speed", value: String(format: "%.1f×", model.exportSpeed))
            TelemetryItem(label: "ETA", value: formatETA(model.exportETA))
            TelemetryItem(label: isChinese ? "目标" : "Source", value: formatTimeDetailed(model.videoDuration))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(BiCutTheme.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(BiCutTheme.stroke, lineWidth: 1)
        )
    }

    // MARK: - Log Terminal

    private var logTerminal: some View {
        ScrollView(.vertical) {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.exportLogs.enumerated()), id: \.0) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(
                                line.contains("✅")
                                    ? BiCutTheme.success
                                    : Color(red: 0.25, green: 0.72, blue: 0.42)
                            )
                            .id(line)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: model.exportLogs.count) {
                    if reduceMotion {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    } else {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 1)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: 120)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BiCutTheme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Telemetry Item

struct TelemetryItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(BiCutTheme.label)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(BiCutTheme.secondaryLabel)
        }
    }
}

private func formatETA(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    if seconds < 60 { return "\(Int(seconds))s" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return "\(m)m\(s)s"
}
