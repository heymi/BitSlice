import SwiftUI

struct InspectorSidebarView: View {
    let model: AppViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // Slice Duration
                VStack(alignment: .leading, spacing: 8) {
                    Text("切片时长").font(.caption).fontWeight(.semibold)
                    HStack(spacing: 6) {
                        Button { model.setSegmentDuration(max(1, model.config.segmentDuration - 1)) } label: {
                            Image(systemName: "minus").font(.caption).fontWeight(.bold).frame(width: 22, height: 22)
                        }.buttonStyle(.plain).background(Circle().fill(Color.primary.opacity(0.06)))
                            .disabled(model.config.segmentDuration <= 1)
                        Slider(value: Binding(get: { model.config.segmentDuration }, set: { model.setSegmentDuration(max(1, $0.rounded())) }), in: 1 ... max(1, model.videoDuration)).tint(.blue)
                        Button { model.setSegmentDuration(min(model.config.segmentDuration + 1, model.videoDuration)) } label: {
                            Image(systemName: "plus").font(.caption).fontWeight(.bold).frame(width: 22, height: 22)
                        }.buttonStyle(.plain).background(Circle().fill(Color.primary.opacity(0.06)))
                            .disabled(model.config.segmentDuration >= model.videoDuration)
                    }
                    Text(formatTimeDetailed(model.config.segmentDuration)).font(.title3.monospacedDigit()).fontWeight(.semibold)
                    Text(model.segmentSummary).font(.caption).foregroundColor(.secondary)
                        .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                // Naming
                VStack(alignment: .leading, spacing: 8) {
                    Text("输出标题").font(.caption).fontWeight(.semibold)
                    TextField("留空用原文件名", text: Binding(get: { model.config.customTitle }, set: { model.setCustomTitle($0) }))
                        .textFieldStyle(.plain).font(.body)
                        .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                // Codec & Resolution
                VStack(alignment: .leading, spacing: 8) {
                    Text("格式 & 分辨率").font(.caption).fontWeight(.semibold)
                    Picker("", selection: Binding(get: { model.config.outputFormat }, set: { model.setOutputFormat($0) })) {
                        ForEach(OutputFormat.allCases, id: \.self) { f in Text(f.displayName).tag(f) }
                    }.pickerStyle(.segmented)
                    Picker("分辨率", selection: Binding(get: { model.config.resolution }, set: { model.setResolution($0) })) {
                        ForEach(ExportResolution.allCases, id: \.self) { r in Text(r.displayName).tag(r) }
                    }.pickerStyle(.menu)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                // Output Path
                VStack(alignment: .leading, spacing: 6) {
                    Text("导出路径").font(.caption).fontWeight(.semibold)
                    HStack {
                        Image(systemName: "folder").foregroundColor(.accentColor)
                        Text(model.config.outputDirectory?.lastPathComponent ?? "未选择").font(.caption).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button("选择") { pickFolder() }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                // Export button
                Button {
                    if model.config.outputDirectory == nil { pickFolder() } else { Task { await model.startExport() } }
                } label: {
                    Label("导出切片", systemImage: "sparkles").fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(.blue)
                .disabled(model.segments.isEmpty || model.phase.isExporting)
            }
            .padding(14)
        }
    }

    private func pickFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "选择导出文件夹"
        if let d = model.config.outputDirectory { p.directoryURL = d }
        p.begin { r in if r == .OK, let u = p.url { model.setOutputDirectory(u) } }
    }
}
