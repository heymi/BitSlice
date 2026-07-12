import AppKit
import SwiftUI

@Observable
final class SettingsPaneState {
    var pane: SettingsPane = .general
}

/// Preferences window matching the design mockup: sidebar + detail panes.
struct AppSettingsView: View {
    let model: AppViewModel
    private let paneState = SettingsPaneState()

    private var isChinese: Bool { model.appSettings.language == .simplifiedChinese }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(BiCutTheme.hairline).frame(width: 1)
            detail
        }
        .frame(width: 760, height: 520)
        .background(BiCutTheme.canvas)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, Locale(identifier: model.appSettings.language.localeIdentifier))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isChinese ? "偏好设置" : "PREFERENCES")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(BiCutTheme.tertiaryLabel)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 14)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { item in
                    sidebarButton(item)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Button {
                model.resetAllDefaults()
            } label: {
                Label(isChinese ? "恢复默认" : "Reset Defaults", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(
                        Capsule()
                            .fill(BiCutTheme.control.opacity(0.55))
                    )
                    .overlay(
                        Capsule().stroke(BiCutTheme.stroke, lineWidth: 1)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 200)
        .background(BiCutTheme.panel.opacity(0.55))
    }

    private func sidebarButton(_ item: SettingsPane) -> some View {
        let selected = paneState.pane == item
        return Button {
            paneState.pane = item
        } label: {
            Label(item.title(isChinese: isChinese), systemImage: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? BiCutTheme.onAccent : BiCutTheme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? BiCutTheme.blueBright : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(detailTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(BiCutTheme.label)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ScrollView {
                Group {
                    switch paneState.pane {
                    case .general: generalPane
                    case .engine: enginePane
                    case .notifications: notificationsPane
                    case .about: aboutPane
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BiCutTheme.canvas)
    }

    private var detailTitle: String {
        switch paneState.pane {
        case .general: isChinese ? "通用设置" : "General Settings"
        case .engine: isChinese ? "引擎设置" : "Engine Settings"
        case .notifications: isChinese ? "通知设置" : "Notifications Settings"
        case .about: isChinese ? "关于 BiCut" : "About BiCut"
        }
    }

    // MARK: General

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsCard {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "外观" : "Appearance Theme")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BiCutTheme.label)
                        Text(isChinese ? "在浅色与深色之间切换。" : "Switch between light or dark mode styling.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BiCutTheme.secondaryLabel)
                    }
                    Spacer()
                    // Design: dark capsule control with sun / moon + label
                    Button {
                        cycleAppearanceForDesignPill()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: appearanceActionIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BiCutTheme.amber)
                            Text(appearanceActionTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BiCutTheme.label)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                        .overlay(Capsule().stroke(BiCutTheme.stroke, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }

            settingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "语言" : "Language")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BiCutTheme.label)
                        Text(isChinese ? "切换整个应用界面语言（保存在本机）。" : "Changes the entire app interface language (saved on this Mac).")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(BiCutTheme.secondaryLabel)
                    }
                    Spacer()
                    languageSegment
                }
            }

            sectionHeader(isChinese ? "默认编码（精确模式）" : "DEFAULT CODEC (PRECISE MODE)")
            Text(
                isChinese
                    ? "精确重编码时使用。快速直通会保留源视频编码。"
                    : "Used when re-encoding in Precise mode. Fast mode keeps the source codec."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BiCutTheme.tertiaryLabel)

            HStack(spacing: 4) {
                ForEach(VideoCodecPreference.allCases) { codec in
                    codecChip(codec)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BiCutTheme.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BiCutTheme.stroke, lineWidth: 1)
            )

            sectionHeader(isChinese ? "默认导出位置" : "DEFAULT DESTINATION")
            HStack(spacing: 10) {
                Text(model.destinationDisplayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(BiCutTheme.control)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BiCutTheme.stroke, lineWidth: 1)
                    )

                secondaryPillButton(isChinese ? "选择…" : "Browse…") {
                    pickDefaultFolder()
                }

                secondaryPillButton(isChinese ? "用下载文件夹" : "Use Downloads") {
                    model.useDownloadsAsDefaultDestination()
                }
            }
        }
    }

    private var languageSegment: some View {
        HStack(spacing: 3) {
            ForEach(AppLanguage.allCases) { lang in
                let selected = model.appSettings.language == lang
                Button {
                    model.setLanguage(lang)
                } label: {
                    Text(lang.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selected ? BiCutTheme.label : BiCutTheme.secondaryLabel)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.white.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BiCutTheme.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BiCutTheme.stroke, lineWidth: 1)
        )
    }

    private func codecChip(_ codec: VideoCodecPreference) -> some View {
        let selected = model.config.videoCodec == codec
        return Button {
            model.setVideoCodec(codec)
        } label: {
            Text(codec.displayName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected ? BiCutTheme.label : BiCutTheme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func secondaryPillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BiCutTheme.label)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BiCutTheme.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BiCutTheme.stroke, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: Engine

    private var enginePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(BiCutTheme.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isChinese ? "硬件加速导出" : "GPU Hardware Acceleration")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(BiCutTheme.amber)
                    Text(
                        isChinese
                            ? "在 Apple 芯片上优先使用系统媒体引擎加速编码，配合快速直通，让长视频切片更快完成。"
                            : "Leverages the Apple media engine on Apple Silicon for faster re-encoding, and pairs with stream-copy Fast mode for near-instant slices."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BiCutTheme.amber.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BiCutTheme.amber.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BiCutTheme.amber.opacity(0.28), lineWidth: 1)
            )

            toggleCard(
                title: isChinese ? "启用硬件加速" : "Enable GPU Acceleration",
                subtitle: isChinese
                    ? "推荐在 4K 与精确重编码场景开启，以缩短导出时间。"
                    : "Highly recommended for 4K and Precise re-encode exports.",
                isOn: Binding(
                    get: { model.appSettings.preferHardwareAcceleration },
                    set: { model.setPreferHardwareAcceleration($0) }
                )
            )

            toggleCard(
                title: isChinese ? "多线程并行切片" : "Multi-Threaded Parallel Slices",
                subtitle: isChinese
                    ? "快速模式下并导出多个片段，充分利用多核性能。"
                    : "Exports Fast slices concurrently to use more of your processor.",
                isOn: Binding(
                    get: { model.appSettings.parallelFastExports },
                    set: { model.setParallelFastExports($0) }
                )
            )

            sectionHeader(isChinese ? "默认切片协议" : "FRAME INDEXING PROTOCOL")
            Menu {
                Button(isChinese ? "快速直通（关键帧对齐）" : "GOP Fast Align (stream copy)") {
                    model.setSplittingStrategy(.fast)
                }
                Button(isChinese ? "精确重编码（帧级对齐）" : "Precise Frame Align (re-encode)") {
                    model.setSplittingStrategy(.precise)
                }
            } label: {
                HStack {
                    Text(splitProtocolLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BiCutTheme.label)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BiCutTheme.tertiaryLabel)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BiCutTheme.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BiCutTheme.stroke, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var splitProtocolLabel: String {
        switch model.config.splittingStrategy {
        case .fast:
            return isChinese ? "快速直通（关键帧对齐）" : "GOP Fast Align (stream copy)"
        case .precise:
            return isChinese ? "精确重编码（帧级对齐）" : "Precise Frame Align (re-encode)"
        }
    }

    private var appearanceActionTitle: String {
        // Design shows the theme you can switch into / current intent.
        switch model.appSettings.appearance {
        case .light: return isChinese ? "深色模式" : "Dark Theme"
        case .dark, .automatic: return isChinese ? "浅色模式" : "Light Theme"
        }
    }

    private var appearanceActionIcon: String {
        switch model.appSettings.appearance {
        case .light: return "moon.fill"
        case .dark, .automatic: return "sun.max.fill"
        }
    }

    private func cycleAppearanceForDesignPill() {
        switch model.appSettings.appearance {
        case .dark, .automatic:
            model.setAppearance(.light)
        case .light:
            model.setAppearance(.dark)
        }
    }

    // MARK: Notifications

    private var notificationsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            toggleCard(
                title: isChinese ? "完成后播放提示音" : "Play sound when finished",
                subtitle: isChinese
                    ? "导出成功时播放系统提示音。"
                    : "Plays a subtle macOS chime when exports complete successfully.",
                isOn: Binding(
                    get: { model.appSettings.playSoundWhenFinished },
                    set: { model.setPlaySoundWhenFinished($0) }
                )
            )

            storageCard
        }
    }

    private var storageCard: some View {
        let free = freeSpaceDescription
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(BiCutTheme.blue)
                Text(isChinese ? "目标磁盘剩余空间" : "Target Storage Space")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BiCutTheme.label)
                Spacer()
                Text(free.label)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(BiCutTheme.blue)
                        .frame(width: max(8, geo.size.width * free.usedFraction))
                }
            }
            .frame(height: 6)

            Text(
                isChinese
                    ? "基于当前默认导出目录所在磁盘。导出前仍会做空间检查。"
                    : "Based on the volume of your default export folder. Exports still preflight free space."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BiCutTheme.tertiaryLabel)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(BiCutTheme.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BiCutTheme.stroke, lineWidth: 1)
        )
    }

    private var freeSpaceDescription: (label: String, usedFraction: CGFloat) {
        let url = model.config.outputDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let url,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let free = values.volumeAvailableCapacity,
              let total = values.volumeTotalCapacity,
              total > 0
        else {
            return (isChinese ? "未知" : "Unknown", 0.35)
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let freeText = formatter.string(fromByteCount: Int64(free))
        let used = 1 - (CGFloat(free) / CGFloat(total))
        return ("\(freeText) Free", min(max(used, 0.05), 0.95))
    }

    // MARK: About

    private var aboutPane: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(BiCutTheme.blueSoft)
                    .frame(width: 72, height: 72)
                Image(systemName: "scissors")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(BiCutTheme.blue)
            }
            .padding(.top, 20)

            Text("BiCut")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(BiCutTheme.label)

            Text("Version \(BiCutAppMetadata.versionLabel)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(BiCutTheme.secondaryLabel)

            Text(
                isChinese
                    ? "macOS 本地视频等时长分片工具。支持快速直通与精确重编码两种模式，处理均在本机完成。"
                    : "A local macOS tool for fixed-duration video slicing. Fast stream-copy and precise re-encode modes — all processing stays on device."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(BiCutTheme.secondaryLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            Divider().overlay(BiCutTheme.hairline).padding(.vertical, 8)

            HStack(spacing: 16) {
                Link(destination: BiCutAppMetadata.websiteURL) {
                    Label(isChinese ? "项目主页" : "Website", systemImage: "safari")
                }
                Link(destination: BiCutAppMetadata.supportURL) {
                    Label(isChinese ? "支持邮箱" : "Support", systemImage: "envelope")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BiCutTheme.blue)

            Text("© \(Calendar.current.component(.year, from: Date())) BiCut")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BiCutTheme.tertiaryLabel)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shared chrome

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BiCutTheme.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BiCutTheme.stroke, lineWidth: 1)
            )
    }

    private func toggleCard(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        settingsCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BiCutTheme.label)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(BiCutTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(BiCutTheme.blue)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(BiCutTheme.tertiaryLabel)
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.appSettings.appearance {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func pickDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = isChinese ? "选择" : "Choose"
        if let directory = model.config.outputDirectory {
            panel.directoryURL = directory
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.setOutputDirectory(url)
        }
    }
}
