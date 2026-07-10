import SwiftUI

struct InspectorSidebarView: View {
    let model: AppViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Label("EXPORT SETTINGS", systemImage: "gearshape")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(BiCutTheme.muted)
                    .padding(.bottom, 26)

                durationSection
                sectionDivider
                namingSection
                sectionDivider
                formatSection
                sectionDivider
                destinationSection
                exportButton
            }
            .padding(26)
        }
        .background(Color(red: 0.064, green: 0.065, blue: 0.074))
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("Slice Interval Duration")
                Spacer()
                Text(formatShortDuration(model.config.segmentDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.31, green: 0.62, blue: 1))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(BiCutTheme.blue.opacity(0.13)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(BiCutTheme.blue.opacity(0.25)))
            }

            HStack(spacing: 13) {
                stepButton("minus") { model.setSegmentDuration(max(1, model.config.segmentDuration - 1)) }
                    .disabled(model.config.segmentDuration <= 1)
                Slider(value: Binding(
                    get: { model.config.segmentDuration },
                    set: { model.setSegmentDuration(max(1, $0.rounded())) }
                ), in: 1 ... max(1, model.videoDuration))
                .tint(BiCutTheme.blue)
                stepButton("plus") { model.setSegmentDuration(min(model.videoDuration, model.config.segmentDuration + 1)) }
                    .disabled(model.config.segmentDuration >= model.videoDuration)
            }

            Label(model.segmentSummaryEnglish, systemImage: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.37, green: 0.65, blue: 1))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(BiCutTheme.blue.opacity(0.075)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(BiCutTheme.blue.opacity(0.14)))
        }
    }

    private var namingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Output Filename")
            TextField("", text: Binding(
                get: { model.config.customTitle },
                set: { model.setCustomTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 15)
            .frame(height: 40)
            .background(controlShape)

            HStack(spacing: 10) {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundStyle(Color(red: 0.30, green: 0.62, blue: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text("FIRST OUTPUT PREVIEW")
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(BiCutTheme.muted)
                    Text(model.namingPreview)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(BiCutTheme.border))
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionLabel("Output Format")
            HStack(spacing: 3) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Button { model.setOutputFormat(format) } label: {
                        Text(format.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(model.config.outputFormat == format ? .white.opacity(0.9) : BiCutTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(model.config.outputFormat == format ? Color.white.opacity(0.11) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.config.outputFormat == format ? BiCutTheme.border : .clear))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(4)
            .background(controlShape)

            sectionLabel("Target Resolution")
                .padding(.top, 5)
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
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(controlShape)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Destination Location")
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(BiCutTheme.amber)
                Text(model.destinationDisplayPath)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.63))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Browse…") { pickFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(controlShape)
        }
    }

    private var exportButton: some View {
        Button {
            if model.config.outputDirectory == nil { pickFolder() }
            else { Task { await model.startExport() } }
        } label: {
            Label("Export \(model.segments.count) Clips", systemImage: "square.and.arrow.up")
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(BiCutTheme.blue))
                .shadow(color: BiCutTheme.blue.opacity(0.3), radius: 12, y: 5)
        }
        .buttonStyle(ScaleButtonStyle())
        .foregroundStyle(.white)
        .disabled(model.segments.isEmpty || !model.hasValidOutputName || model.phase.isExporting)
        .padding(.top, 24)
    }

    private var sectionDivider: some View {
        Rectangle().fill(BiCutTheme.border).frame(height: 1).padding(.vertical, 24)
    }

    private var controlShape: some View {
        RoundedRectangle(cornerRadius: 12).fill(BiCutTheme.control)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(BiCutTheme.border))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.78))
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.6)).frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(BiCutTheme.border))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func resolutionLabel(_ resolution: ExportResolution) -> String {
        guard resolution == .original, let asset = model.videoAsset else { return resolution.displayName }
        return "Original: \(Int(asset.naturalSize.width))×\(Int(asset.naturalSize.height))"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if let directory = model.config.outputDirectory { panel.directoryURL = directory }
        panel.begin { response in
            if response == .OK, let url = panel.url { model.setOutputDirectory(url) }
        }
    }
}
