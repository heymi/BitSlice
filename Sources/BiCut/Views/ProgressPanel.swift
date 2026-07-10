import SwiftUI

struct ProgressPanel: View {
    let model: AppViewModel

    var body: some View {
        GroupBox {
            switch model.phase {
            case .empty:
                emptyState

            case .loaded:
                readyState

            case .exporting(let current, let total, let overall, let segment):
                exportingState(current: current, total: total, overall: overall, segment: segment)

            case .completed(let url):
                completedState(url: url)

            case .failed(let message):
                failedState(message: message)
            }
        } label: {
            Text("导出")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Image(systemName: "arrow.right.circle")
                .foregroundColor(.secondary)
            Text("拖入视频文件以开始")
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Ready state

    private var readyState: some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .foregroundColor(.accentColor)
                .font(.title3)

            let count = model.segments.count
            Text("准备导出 \(count) 个分片")
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                Task { await model.startExport() }
            } label: {
                Label("开始导出", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.segments.isEmpty || model.config.outputDirectory == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.vertical, 4)
    }

    // MARK: - Exporting state

    private func exportingState(current: Int, total: Int, overall: Double, segment: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView(value: overall, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                Text(String(format: "%.0f%%", overall * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }

            HStack {
                Text("第 \(current + 1) / \(total) 段")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let segName = model.segments[safe: current]?.fileName {
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(segName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("取消") {
                    model.cancelExport()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.red)
            }

            ProgressView(value: segment, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.blue.opacity(0.6))
                .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Completed state

    private func completedState(url: URL) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)

            Text("导出完成！共 \(model.segments.count) 个文件")
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("打开文件夹", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])

            Button("重新导出") {
                model.resetToIdle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Failed state

    private func failedState(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
                .font(.title3)

            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)

            Spacer()

            Button("关闭") {
                model.resetToIdle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Safe array subscript (moved here from extension)

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
