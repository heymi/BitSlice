import SwiftUI

/// Right export rail — layout matches design mockup.
struct InspectorSidebarView: View {
    let model: AppViewModel

    private var lang: AppLanguage { model.appSettings.language }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                strategyBlock
                divider
                durationBlock
                divider
                filenameBlock
                divider
                moreSettingsBlock
                sectionGap
                destinationBlock
                exportBlock
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .background(BiCutTheme.canvas)
    }

    // MARK: Fast / Precise

    private var strategyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(lang.t("Split Mode", "切片模式"))

            HStack(spacing: 3) {
                ForEach(SplittingStrategy.allCases) { strategy in
                    let selected = model.config.splittingStrategy == strategy
                    Button {
                        model.setSplittingStrategy(strategy)
                    } label: {
                        Text(strategy.displayName(for: lang))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selected ? BiCutTheme.label : BiCutTheme.secondaryLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.white.opacity(0.10) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BiCutTheme.control)
            )

            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.config.splittingStrategy == .fast ? BiCutTheme.amber : BiCutTheme.blue)
                    .frame(width: 3, height: 40)
                Text(model.config.splittingStrategy.shortDescription(for: lang))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BiCutTheme.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BiCutTheme.stroke, lineWidth: 1)
            )
        }
    }

    // MARK: Duration

    private var durationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(lang.t("Slice Interval", "切片时长"))
                Spacer()
                Text(formatShortDuration(model.config.segmentDuration))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(BiCutTheme.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BiCutTheme.blueSoft))
            }

            HStack(spacing: 12) {
                stepCircle("minus") {
                    model.setSegmentDuration(max(1, model.config.segmentDuration - 1))
                }
                .disabled(model.config.segmentDuration <= 1)

                Slider(
                    value: Binding(
                        get: { model.config.segmentDuration },
                        set: { model.setSegmentDuration(max(1, $0.rounded())) }
                    ),
                    in: 1 ... max(1, model.videoDuration)
                )
                .tint(BiCutTheme.blue)

                stepCircle("plus") {
                    model.setSegmentDuration(min(model.videoDuration, model.config.segmentDuration + 1))
                }
                .disabled(model.config.segmentDuration >= model.videoDuration)
            }

            HStack(spacing: 6) {
                ForEach(SegmentDurationPreset.allCases) { preset in
                    let selected = isPresetSelected(preset) && !model.isCustomDurationEntry
                    let fitsVideo = preset.seconds <= max(model.videoDuration, 1)
                    Button {
                        model.selectDurationPreset(preset)
                    } label: {
                        Text(preset.displayName(for: lang))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(selected ? BiCutTheme.onAccent : BiCutTheme.secondaryLabel)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? BiCutTheme.blue : BiCutTheme.control)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected ? Color.clear : BiCutTheme.stroke, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!fitsVideo)
                    .opacity(fitsVideo ? 1 : 0.35)
                }

                Button {
                    model.beginCustomDurationEntry()
                } label: {
                    Text(lang.t("Custom", "自定义"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(model.isCustomDurationEntry ? BiCutTheme.onAccent : BiCutTheme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(model.isCustomDurationEntry ? BiCutTheme.blue : BiCutTheme.control)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(model.isCustomDurationEntry ? Color.clear : BiCutTheme.stroke, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if model.isCustomDurationEntry {
                HStack(spacing: 10) {
                    Text(lang.t("Seconds", "秒数"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BiCutTheme.secondaryLabel)
                    TextField(lang.t("sec", "秒"), value: Binding(
                        get: { model.config.segmentDuration },
                        set: { model.setSegmentDuration(max(1, $0.rounded()), customEntry: true) }
                    ), format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(BiCutTheme.label)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(fieldBackground)
                    Text(lang.t("sec", "秒"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BiCutTheme.secondaryLabel)
                }
            }

            Label {
                Text(model.segmentSummary)
                    .font(.system(size: 12, weight: .medium))
            } icon: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1.0))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BiCutTheme.blueSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BiCutTheme.blue.opacity(0.28), lineWidth: 1)
            )
        }
    }

    private func isPresetSelected(_ preset: SegmentDurationPreset) -> Bool {
        abs(model.config.segmentDuration - preset.seconds) < 0.5
    }

    // MARK: Filename

    private var filenameBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(lang.t("Output Filename", "输出文件名"))

            TextField(lang.t("Use source filename", "使用源文件名"), text: Binding(
                get: { model.config.customTitle },
                set: { model.setCustomTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(BiCutTheme.label)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(fieldBackground)

            HStack(spacing: 10) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(BiCutTheme.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.t("FIRST OUTPUT PREVIEW", "首个文件预览"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(BiCutTheme.tertiaryLabel)
                    Text(model.namingPreview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BiCutTheme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BiCutTheme.well)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BiCutTheme.stroke, lineWidth: 1)
            )
        }
    }

    // MARK: More settings (codec + resolution)

    private var moreSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.toggleMoreExportSettings()
            } label: {
                HStack(spacing: 8) {
                    Text(lang.t("More Settings", "更多设置"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BiCutTheme.label)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BiCutTheme.tertiaryLabel)
                        .rotationEffect(.degrees(model.showMoreExportSettings ? 90 : 0))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if model.showMoreExportSettings {
                VStack(alignment: .leading, spacing: 16) {
                    codecSection
                    resolutionSection
                }
            }
        }
    }

    private var codecSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("Codec Standard", "输出编码"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BiCutTheme.secondaryLabel)

            HStack(spacing: 3) {
                ForEach(VideoCodecPreference.allCases) { codec in
                    codecChip(codec)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BiCutTheme.control)
            )
            .opacity(model.config.splittingStrategy == .fast ? 0.45 : 1)
            .disabled(model.config.splittingStrategy == .fast)

            if model.config.splittingStrategy == .fast {
                Text(lang.t("Kept from source in Fast mode", "快速模式保留源编码"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BiCutTheme.tertiaryLabel)
            }
        }
    }

    private func codecChip(_ codec: VideoCodecPreference) -> some View {
        let selected = model.config.videoCodec == codec
        return Button {
            model.setVideoCodec(codec)
        } label: {
            Text(codec.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(selected ? BiCutTheme.label : BiCutTheme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.10) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.t("Target Resolution", "目标分辨率"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BiCutTheme.secondaryLabel)

            Picker("", selection: Binding(
                get: { model.config.resolution },
                set: { model.setResolution($0) }
            )) {
                ForEach(ExportResolution.allCases, id: \.self) { resolution in
                    Text(resolutionLabel(resolution)).tag(resolution)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 10)
            .background(fieldBackground)
            .opacity(model.config.splittingStrategy == .fast ? 0.45 : 1)
            .disabled(model.config.splittingStrategy == .fast)

            if model.config.splittingStrategy == .fast {
                Text(lang.t("Original resolution only in Fast mode", "快速模式仅输出原始分辨率"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BiCutTheme.tertiaryLabel)
            }
        }
    }

    // MARK: Destination

    private var destinationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(lang.t("Destination Location", "导出位置"))

            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(BiCutTheme.amber)
                Text(model.destinationDisplayPath)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BiCutTheme.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button { pickFolder() } label: {
                    Text(lang.t("Browse…", "选择…"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BiCutTheme.label)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().stroke(BiCutTheme.stroke, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(fieldBackground)
        }
    }

    // MARK: Export CTA

    private var exportBlock: some View {
        VStack(spacing: 12) {
            Button {
                if model.config.outputDirectory == nil {
                    pickFolder(andExport: true)
                } else {
                    Task { await model.startExport() }
                }
            } label: {
                Label(
                    lang.t(
                        "Export Slices (\(model.segments.count) Clips)",
                        "导出 \(model.segments.count) 个片段"
                    ),
                    systemImage: "plus"
                )
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BiCutTheme.blueBright)
                )
                .shadow(color: BiCutTheme.blue.opacity(0.35), radius: 14, y: 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .foregroundStyle(BiCutTheme.onAccent)
            .disabled(model.segments.isEmpty || model.phase.isExporting || model.isLoadingVideo)
            .opacity(model.segments.isEmpty || model.phase.isExporting || model.isLoadingVideo ? 0.45 : 1)
            .padding(.top, 22)

            Text(exportFooterCopy)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BiCutTheme.tertiaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exportFooterCopy: String {
        switch model.config.splittingStrategy {
        case .fast:
            lang.t(
                "Fast mode copies media streams when possible. Cut starts may snap back to the previous keyframe.",
                "快速模式尽量直通复制码流。切点可能回退到上一关键帧。"
            )
        case .precise:
            lang.t(
                "Precise mode re-encodes for frame-aligned cuts. Slower; keeps planned timing, frame rate, and orientation.",
                "精确模式通过重编码实现帧级切点。更慢，但更贴合计划时长、帧率与方向。"
            )
        }
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle()
            .fill(BiCutTheme.hairline)
            .frame(height: 1)
            .padding(.vertical, 20)
    }

    private var sectionGap: some View {
        Color.clear.frame(height: 16)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BiCutTheme.label)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(BiCutTheme.control)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BiCutTheme.stroke, lineWidth: 1)
            )
    }

    private func stepCircle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BiCutTheme.secondaryLabel)
                .frame(width: 30, height: 30)
                .background(Circle().fill(BiCutTheme.control))
                .overlay(Circle().stroke(BiCutTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func resolutionLabel(_ resolution: ExportResolution) -> String {
        guard resolution == .original, let asset = model.videoAsset else {
            return resolution.displayName(for: lang)
        }
        return lang.t(
            "Original: \(Int(asset.naturalSize.width))×\(Int(asset.naturalSize.height))",
            "原始: \(Int(asset.naturalSize.width))×\(Int(asset.naturalSize.height))"
        )
    }

    private func pickFolder(andExport: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = andExport
            ? lang.t("Choose & Export", "选择并导出")
            : lang.t("Choose", "选择")
        if let directory = model.config.outputDirectory {
            panel.directoryURL = directory
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.setOutputDirectory(url)
            if andExport {
                Task { @MainActor in
                    await model.startExport()
                }
            }
        }
    }
}
