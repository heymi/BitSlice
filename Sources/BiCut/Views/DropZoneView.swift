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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                uploadTarget
                recentSection
            }
            .frame(maxWidth: 660)
            .padding(.top, 40)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
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
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 17)
                    .fill(BiCutTheme.elevated)
                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 9) {
                Text("Drag a video here, or click to browse")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                Text("Supports MP4, MOV, MKV, AVI & more")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BiCutTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(local.isTargeted ? BiCutTheme.blue.opacity(0.10) : BiCutTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    local.isTargeted ? BiCutTheme.blue.opacity(0.72) : .clear,
                    lineWidth: 1.5
                )
        )
        .scaleEffect(local.isTargeted && !reduceMotion ? 1.008 : 1)
        .shadow(color: local.isTargeted ? BiCutTheme.blue.opacity(0.12) : .black.opacity(0.10), radius: local.isTargeted ? 20 : 14, y: 6)
        .animation(
            reduceMotion ? .linear(duration: 0.12) : .interactiveSpring(response: 0.26, dampingFraction: 1),
            value: local.isTargeted
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
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
            VStack(spacing: 12) {
                HStack {
                    Label("RECENTLY PROCESSED", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(BiCutTheme.muted)
                        .labelStyle(AmberIconLabelStyle())
                    Spacer()
                    Text("Local files")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BiCutTheme.muted)
                }

                VStack(spacing: 8) {
                    ForEach(model.recentVideos) { recent in
                        recentRow(recent)
                    }
                }
            }
        }
    }

    private func recentRow(_ recent: RecentVideo) -> some View {
        Button { Task { await model.openRecentVideo(recent) } } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(BiCutTheme.elevated)
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(BiCutTheme.muted)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 7) {
                    Text(recent.fileName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(recent.width)×\(recent.height)  ·  \(recent.frameRate) fps  ·  \(formattedBytes(recent.fileSize))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BiCutTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.18))
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(RoundedRectangle(cornerRadius: 15).fill(BiCutTheme.panel))
        }
        .buttonStyle(ScaleButtonStyle())
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

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct AmberIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 9) {
            configuration.icon.foregroundStyle(BiCutTheme.amber)
            configuration.title
        }
    }
}
