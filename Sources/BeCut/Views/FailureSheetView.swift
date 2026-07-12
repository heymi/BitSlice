import SwiftUI

/// Modal shown whenever `AppPhase.failed` is set so load/export errors are never silent.
struct FailureSheetView: View {
    let model: AppViewModel
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isChinese: Bool {
        model.appSettings.language == .simplifiedChinese
    }

    var body: some View {
        ZStack {
            BeCutTheme.scrim
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(BeCutTheme.danger.opacity(0.12))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(BeCutTheme.danger)
                }
                .frame(width: 72, height: 72)
                .padding(.bottom, 18)

                VStack(spacing: 9) {
                    Text(isChinese ? "出了点问题" : "Something went wrong")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(BeCutTheme.label)
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BeCutTheme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.dismissFailure()
                } label: {
                    Text(isChinese ? "知道了" : "OK")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: BeCutTheme.controlRadius, style: .continuous)
                                .fill(BeCutTheme.blue)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScaleButtonStyle())
                .foregroundStyle(BeCutTheme.onAccent)
                .padding(.top, 26)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 32)
            .frame(width: 420)
            .becutModalChrome()
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isChinese ? "错误" : "Error")
        .accessibilityValue(message)
    }
}
