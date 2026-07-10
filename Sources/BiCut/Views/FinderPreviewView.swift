import SwiftUI

// MARK: - Finder Preview View

struct FinderPreviewView: View {
    let model: AppViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { model.resetToIdle() }

            VStack(spacing: 0) {
                // Titlebar
                finderTitlebar

                Divider()

                // Content
                HStack(spacing: 0) {
                    // Sidebar
                    finderSidebar
                        .frame(width: 160)

                    Divider()

                    // File list
                    finderFileList
                }

                Divider()
                finderFooter
            }
            .frame(width: 640, height: 480)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThickMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 48, x: 0, y: 24)
        }
    }

    // MARK: - Titlebar

    private var finderTitlebar: some View {
        HStack(spacing: 0) {
            // Traffic lights
            HStack(spacing: 6) {
                Circle().fill(Color(red: 0.96, green: 0.34, blue: 0.33)).frame(width: 12, height: 12)
                    .overlay(Image(systemName: "xmark").font(.system(size: 6, weight: .bold)).foregroundColor(.black.opacity(0.3)).opacity(0))
                Circle().fill(Color(red: 0.97, green: 0.74, blue: 0.23)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.23, green: 0.78, blue: 0.35)).frame(width: 12, height: 12)
            }
            .padding(.leading, 12)

            Spacer()

            // Window title
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(model.config.outputDirectory?.lastPathComponent ?? "BiCut Exports")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Spacer()

            // Search / actions placeholder
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                Image(systemName: "list.bullet")
                    .font(.caption)
                Image(systemName: "magnifyingglass")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Sidebar

    private var finderSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Favorites
            sidebarSection("个人收藏") {
                SidebarRow(icon: "desktopcomputer", label: "Macintosh HD", isActive: true)
                SidebarRow(icon: "folder", label: "Desktop")
                SidebarRow(icon: "folder", label: "Downloads", badge: "→")
                SidebarRow(icon: "film", label: "Movies")
            }

            Divider().padding(.vertical, 8)

            // Locations
            sidebarSection("位置") {
                SidebarRow(icon: "externaldrive", label: "Macintosh HD")
                SidebarRow(icon: "icloud", label: "iCloud Drive")
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Text(title)
            .font(.system(size: 9))
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        VStack(spacing: 1) { content() }
    }

    // MARK: - File List

    private var finderFileList: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("时长").frame(width: 80, alignment: .trailing)
                Text("大小").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 10))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, seg in
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                                Text(seg.fileName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(formatMMSS(seg.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)

                            Text(formatSize(seg, totalSize: model.videoAsset?.fileSize ?? 0, totalCount: model.segments.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(i % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))

                        if i < model.segments.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var finderFooter: some View {
        HStack(spacing: 12) {
            Button {
                model.resetToIdle()
            } label: {
                Label("关闭", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                if let dir = model.config.outputDirectory {
                    NSWorkspace.shared.open(dir)
                }
            } label: {
                Label("在 Finder 中打开", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let label: String
    var badge: String?
    var isActive = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(isActive ? .accentColor : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}

// Helpers use global formatMMSS from ContentView

private func formatSize(_ seg: SegmentInfo, totalSize: Int64, totalCount: Int) -> String {
    guard totalCount > 0, totalSize > 0 else { return "—" }
    let ratio = seg.durationSeconds / (seg.durationSeconds * Double(totalCount))
    let estSize = Int64(Double(totalSize) * ratio)
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: estSize)
}
