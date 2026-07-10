import SwiftUI

// MARK: - Processing Sheet

struct ProcessingSheetView: View {
    let model: AppViewModel

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {}

            // Modal
            VStack(spacing: 20) {
                if case .exporting(let current, let total, let overall, let segment) = model.phase {
                    // Progress circle
                    progressCircle(current: current, total: total, overall: overall)

                    // Telemetry panel
                    telemetryPanel(current: current, total: total, overall: overall)

                    // Log terminal
                    logTerminal

                    // Cancel button
                    Button("取消导出") {
                        model.cancelExport()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            .frame(width: 460)
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 40, x: 0, y: 20)
        }
    }

    // MARK: - Progress Circle

    private func progressCircle(current: Int, total: Int, overall: Double) -> some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 6)
                .frame(width: 100, height: 100)

            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(overall))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .indigo, .purple]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: overall)

            // Percentage
            VStack(spacing: 0) {
                Text("\(Int(overall * 100))")
                    .font(.title.monospacedDigit())
                    .fontWeight(.bold)
                Text("%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Telemetry

    private func telemetryPanel(current: Int, total: Int, overall: Double) -> some View {
        HStack(spacing: 32) {
            TelemetryItem(label: "切片", value: "\(current + 1) / \(total)")
            TelemetryItem(label: "速度", value: String(format: "%.1f×", model.exportSpeed))
            TelemetryItem(label: "ETA", value: formatETA(model.exportETA))
            TelemetryItem(label: "目标", value: formatTimeDetailed(model.videoDuration))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
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
                            .foregroundColor(line.contains("✅") ? Color.green : Color.green.opacity(0.8))
                            .id(line)
                    }
                    // Anchor for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: model.exportLogs.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .frame(height: 120)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.15), lineWidth: 1)
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
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
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
