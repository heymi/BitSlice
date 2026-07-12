import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let model: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lang: AppLanguage { model.appSettings.language }

    private static let dropTypes: [UTType] = [
        .fileURL,
        .movie,
        .mpeg4Movie,
        .quickTimeMovie,
        .video,
        .mpeg,
        .avi
    ]

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
        .background(BeCutTheme.canvas)
        // Entire empty state is a drop target (not only the dashed card).
        .contentShape(Rectangle())
        .onDrop(
            of: Self.dropTypes,
            isTargeted: Binding(
                get: { model.isDropTargeted },
                set: { model.isDropTargeted = $0 }
            ),
            perform: handleDrop
        )
        // Modern path: Finder → URL. More reliable than loadItem(Data) on recent macOS.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            beginOpenDroppedVideo(url, model: model)
            return true
        } isTargeted: { targeted in
            model.isDropTargeted = targeted
        }
        .fileImporter(
            isPresented: Binding(
                get: { model.showFileImporter },
                set: { model.showFileImporter = $0 }
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
                    .fill(BeCutTheme.blueSoft)
                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(BeCutTheme.blue)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 8) {
                Text(lang.t("Drag a video here, or click to browse", "拖入视频，或点击选择文件"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BeCutTheme.label)
                Text(lang.t("Supports MP4, MOV & M4V · H.264 / HEVC", "支持 MP4、MOV、M4V · H.264 / HEVC"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BeCutTheme.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(model.isDropTargeted ? BeCutTheme.blueSoft : BeCutTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    model.isDropTargeted ? BeCutTheme.blue.opacity(0.7) : BeCutTheme.stroke,
                    style: StrokeStyle(lineWidth: model.isDropTargeted ? 1.5 : 1, dash: model.isDropTargeted ? [] : [6, 5])
                )
        )
        .scaleEffect(model.isDropTargeted && !reduceMotion ? 1.006 : 1)
        .animation(
            reduceMotion ? .linear(duration: 0.1) : .interactiveSpring(response: 0.26, dampingFraction: 1),
            value: model.isDropTargeted
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { model.showFileImporter = true }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !model.recentVideos.isEmpty {
            VStack(spacing: 10) {
                HStack {
                    Text(lang.t("RECENTLY PROCESSED", "最近处理"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(BeCutTheme.tertiaryLabel)
                    Spacer()
                }

                ForEach(model.recentVideos) { recent in
                    Button {
                        Task { await model.openRecentVideo(recent) }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BeCutTheme.control)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Image(systemName: "play.rectangle")
                                        .foregroundStyle(BeCutTheme.secondaryLabel)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recent.fileName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(BeCutTheme.label)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(recent.width)×\(recent.height) · \(recent.frameRate) fps")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(BeCutTheme.secondaryLabel)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(BeCutTheme.tertiaryLabel)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(BeCutTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BeCutTheme.stroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if resolveProvider(provider) {
                return true
            }
        }
        return false
    }

    /// Returns true if we started loading a video from this provider.
    @discardableResult
    private func resolveProvider(_ provider: NSItemProvider) -> Bool {
        let model = model

        // 1) public.file-url — Finder’s primary type for dropped files on macOS.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = dropItemURL(item) else { return }
                Task { @MainActor in
                    beginOpenDroppedVideo(url, model: model)
                }
            }
            return true
        }

        // 2) Movie / video type identifiers via temporary file representation.
        let mediaTypes = [UTType.movie, .mpeg4Movie, .quickTimeMovie, .video, .mpeg, .avi]
        for type in mediaTypes {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return }
                // File representation is deleted when the callback returns — copy first.
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BeCut-drop-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(at: url, to: dest)
                    Task { @MainActor in
                        beginOpenDroppedVideo(dest, model: model)
                    }
                } catch {
                    // Fall through — try next type / provider.
                }
            }
            return true
        }

        return false
    }
}

@MainActor
private func beginOpenDroppedVideo(_ url: URL, model: AppViewModel) {
    model.isDropTargeted = false
    guard !model.isLoadingVideo else { return }
    Task { await model.loadVideo(from: url) }
}

/// macOS Finder may deliver the file URL as URL, NSURL, Data, or a path string.
/// Free function so NSItemProvider callbacks stay off the main actor.
private nonisolated func dropItemURL(_ item: (any NSSecureCoding)?) -> URL? {
    if let url = item as? URL {
        return url
    }
    if let url = item as? NSURL {
        return url as URL
    }
    if let data = item as? Data {
        if let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            if path.hasPrefix("file:") {
                return URL(string: path)
            }
            return URL(fileURLWithPath: path)
        }
    }
    if let path = item as? String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file:") {
            return URL(string: trimmed)
        }
        if !trimmed.isEmpty {
            return URL(fileURLWithPath: trimmed)
        }
    }
    return nil
}
