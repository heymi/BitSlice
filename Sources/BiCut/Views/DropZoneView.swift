import SwiftUI
import UniformTypeIdentifiers

// MARK: - Local UI state (replaces @State, unavailable w/ CLI tools)

@Observable
final class DropZoneLocalState {
    var isTargeted = false
    var showFileImporter = false
}

// MARK: - View

struct DropZoneView: View {
    let model: AppViewModel
    private let local = DropZoneLocalState()

    var body: some View {
        GroupBox {
            if let asset = model.videoAsset {
                loadedState(asset)
            } else {
                emptyState
            }
        }
        .dropZoneStyle(isTargeted: local.isTargeted)
        .onDrop(
            of: [.fileURL, .movie, .mpeg4Movie, .quickTimeMovie, .video],
            isTargeted: Binding(
                get: { local.isTargeted },
                set: { local.isTargeted = $0 }
            )
        ) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onTapGesture {
            local.showFileImporter = true
        }
        .fileImporter(
            isPresented: Binding(
                get: { local.showFileImporter },
                set: { local.showFileImporter = $0 }
            ),
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.loadVideo(from: url) }
            case .failure:
                break
            }
        }
        .frame(minHeight: 80)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("拖入视频文件")
                .font(.headline)
                .foregroundColor(.primary)

            Text("或点击此处选择文件")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("支持 MP4 / MOV 格式")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Loaded state

    @ViewBuilder
    private func loadedState(_ asset: VideoAsset) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if asset.isMetadataLoaded {
                    HStack(spacing: 12) {
                        Label(formatTimeDetailed(asset.durationSeconds), systemImage: "clock")
                        Label(asset.hasVideoTrack ? resolutionLabel(asset) : "无视频", systemImage: "rectangle.on.rectangle")
                        Label("\(Int(asset.frameRate)) fps", systemImage: "livephoto")
                        if !asset.videoCodec.isEmpty {
                            Label(asset.videoCodec, systemImage: "gearshape")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("正在加载视频信息...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatBytes(asset.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("更换") {
                    local.showFileImporter = true
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard error == nil,
                          let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        await model.loadVideo(from: url)
                    }
                }
                return
            }
            for type in [UTType.movie.identifier, UTType.mpeg4Movie.identifier, UTType.quickTimeMovie.identifier] {
                if provider.hasItemConformingToTypeIdentifier(type) {
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                        guard error == nil, let url = item as? URL else { return }
                        Task { @MainActor in
                            await model.loadVideo(from: url)
                        }
                    }
                    return
                }
            }
        }
    }

    private func resolutionLabel(_ asset: VideoAsset) -> String {
        let w = Int(asset.naturalSize.width.rounded())
        let h = Int(asset.naturalSize.height.rounded())
        return "\(w)×\(h)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Custom group box style for drop zone

struct DropZoneStyle: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(
                            lineWidth: isTargeted ? 2.5 : 1.5,
                            dash: [8, 4]
                        )
                    )
            )
            .scaleEffect(isTargeted ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isTargeted)
    }
}

extension View {
    func dropZoneStyle(isTargeted: Bool) -> some View {
        modifier(DropZoneStyle(isTargeted: isTargeted))
    }
}
