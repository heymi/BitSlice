import SwiftUI

struct FinderPreviewView: View {
    let model: AppViewModel

    private var isChinese: Bool {
        model.appSettings.language == .simplifiedChinese
    }

    var body: some View {
        ZStack {
            BeCutTheme.scrim
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 0) {
                successMark

                VStack(spacing: 9) {
                    Text(isChinese ? "切片已就绪" : "Your clips are ready")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(BeCutTheme.label)
                    Text(
                        isChinese
                            ? "已将 \(model.segments.count) 个片段保存到所选文件夹。"
                            : "\(model.segments.count) clips were saved to your selected folder."
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BeCutTheme.secondaryLabel)
                }

                outputSummary

                HStack(spacing: 10) {
                    Button { model.resetToIdle() } label: {
                        Text(isChinese ? "完成" : "Done")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Capsule().fill(BeCutTheme.elevated))
                            .overlay(Capsule().stroke(BeCutTheme.stroke, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .foregroundStyle(BeCutTheme.label)

                    Button {
                        if let directory = model.config.outputDirectory {
                            NSWorkspace.shared.open(directory)
                        }
                    } label: {
                        Label(isChinese ? "在 Finder 中显示" : "Show in Finder", systemImage: "folder")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Capsule().fill(BeCutTheme.blue))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .foregroundStyle(BeCutTheme.onAccent)
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 34)
            .frame(width: 420)
            .becutModalChrome()
        }
    }

    private var successMark: some View {
        ZStack {
            Circle().fill(BeCutTheme.success.opacity(0.14))
            Image(systemName: "checkmark")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(BeCutTheme.success)
        }
        .frame(width: 72, height: 72)
        .padding(.bottom, 20)
    }

    private var outputSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BeCutTheme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(isChinese ? "保存位置" : "SAVED TO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(BeCutTheme.tertiaryLabel)
                Text(model.destinationDisplayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(BeCutTheme.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(height: 62)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BeCutTheme.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BeCutTheme.stroke, lineWidth: 1)
        )
        .padding(.vertical, 25)
    }
}
