import SwiftUI

// MARK: - Local state

@Observable
final class SettingsLocalState {
    var showDirectoryChooser = false
}

// MARK: - View

struct SettingsPanel: View {
    let model: AppViewModel
    private let local = SettingsLocalState()

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                HStack(spacing: 24) {
                    titleField
                    Spacer()
                    outputDirectorySelector
                }
                HStack(spacing: 24) {
                    formatPicker
                    resolutionPicker
                }
            }
        } label: {
            Text("导出设置")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Title field

    private var titleField: some View {
        HStack(spacing: 6) {
            Text("标题:")
                .font(.subheadline)
            TextField("默认使用原文件名", text: Binding(
                get: { model.config.customTitle },
                set: { newValue in
                    model.config.customTitle = newValue
                    model.config.save()
                    model.recalculateSegments()
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
            .disabled(model.phase.isExporting)
        }
    }

    // MARK: - Format picker

    private var formatPicker: some View {
        HStack(spacing: 6) {
            Text("格式:")
                .font(.subheadline)
            Picker("", selection: Binding(
                get: { model.config.outputFormat },
                set: { model.setOutputFormat($0) }
            )) {
                ForEach(OutputFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .disabled(model.phase.isExporting)
        }
    }

    // MARK: - Resolution picker

    private var resolutionPicker: some View {
        HStack(spacing: 6) {
            Text("分辨率:")
                .font(.subheadline)
            Picker("", selection: Binding(
                get: { model.config.resolution },
                set: { model.setResolution($0) }
            )) {
                ForEach(ExportResolution.allCases, id: \.self) { res in
                    Text(res.displayName).tag(res)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .disabled(model.phase.isExporting)

            if let asset = model.videoAsset, let target = model.config.resolution.targetSize {
                let maxSrc = asset.maxDimension
                let maxTarget = max(target.width, target.height)
                if maxTarget > maxSrc {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .help("目标分辨率高于原始分辨率(\(Int(maxSrc))p)，将按原始分辨率输出。")
                }
            }
        }
    }

    // MARK: - Output directory

    private var outputDirectorySelector: some View {
        HStack(spacing: 6) {
            Text("输出:")
                .font(.subheadline)

            if let dir = model.config.outputDirectory {
                Text(dir.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(dir.path)
            } else {
                Text("未选择")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("选择文件夹") {
                local.showDirectoryChooser = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.phase.isExporting)
        }
        .fileImporter(
            isPresented: Binding(
                get: { local.showDirectoryChooser },
                set: { local.showDirectoryChooser = $0 }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.setOutputDirectory(url)
            case .failure:
                break
            }
        }
    }
}
