import SwiftUI
import UniformTypeIdentifiers

@Observable
final class DropZoneLocalState {
    var isTargeted = false
    var showFileImporter = false
}

struct DropZoneView: View {
    let model: AppViewModel
    private let local = DropZoneLocalState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: AppLanguage { model.appSettings.language }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                uploadTarget
                recentSection
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BiCutTheme.canvas)
        .fileImporter(
            isPresented: Binding(
                get: { local.showFileImporter },
                set: { local.showFileImporter = $0 }
            ),
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await model.loadVideo(from: url) }
        }
    }

    private var uploadTarget: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BiCutTheme.blueSoft)
                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(BiCutTheme.blue)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 8) {
                Text(lang.t("Drag a video here, or click to browse", "拖入视频，或点击选择文件"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BiCutTheme.label)
                Text(lang.t("Supports MP4, MOV & M4V · H.264 / HEVC", "支持 MP4、MOV、M4V · H.264 / HEVC"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(local.isTargeted ? BiCutTheme.blueSoft : BiCutTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    local.isTargeted ? BiCutTheme.blue.opacity(0.7) : BiCutTheme.stroke,
                    style: StrokeStyle(lineWidth: local.isTargeted ? 1.5 : 1, dash: local.isTargeted ? [] : [6, 5])
                )
        )
        .scaleEffect(local.isTargeted && !reduceMotion ? 1.006 : 1)
        .animation(
            reduceMotion ? .linear(duration: 0.1) : .interactiveSpring(response: 0.26, dampingFraction: 1),
            value: local.isTargeted
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { local.showFileImporter = true }
        .onDrop(
            of: [.fileURL, .movie, .mpeg4Movie, .quickTimeMovie, .video],
            isTargeted: Binding(
                get: { local.isTargeted },
                set: { local.isTargeted = $0 }
            )
        ) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recentVideos.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text(lang.t("RECENTLY PROCESSED", "最近处理"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(BiCutTheme.tertiaryLabel)
                    Spacer()
                }

                ForEach(model.recentVideos) { recent in
                    Button {
                        Task { await model.openRecentVideo(recent) }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BiCutTheme.control)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Image(systemName: "play.rectangle")
                                        .foregroundStyle(BiCutTheme.secondaryLabel)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recent.fileName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(BiCutTheme.label)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(recent.width)×\(recent.height) · \(recent.frameRate) fps")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(BiCutTheme.secondaryLabel)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BiCutTheme.tertiaryLabel)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(BiCutTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BiCutTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard error == nil,
                          let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    Task { @MainActor in await model.loadVideo(from: url) }
                }
                return
            }
        }
    }
}
