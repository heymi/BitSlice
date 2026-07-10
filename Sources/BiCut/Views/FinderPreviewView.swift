import SwiftUI

struct FinderPreviewView: View {
    let model: AppViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 0) {
                successMark

                VStack(spacing: 9) {
                    Text("Your clips are ready")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("\(model.segments.count) clips were saved to your selected folder.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BiCutTheme.muted)
                }

                outputSummary

                HStack(spacing: 10) {
                    Button("Done") { model.resetToIdle() }
                        .buttonStyle(ScaleButtonStyle())
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.09)))

                    Button {
                        if let directory = model.config.outputDirectory {
                            NSWorkspace.shared.open(directory)
                        }
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Capsule().fill(BiCutTheme.blue))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 34)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 24).fill(BiCutTheme.panel))
            .shadow(color: .black.opacity(0.35), radius: 34, y: 18)
        }
    }

    private var successMark: some View {
        ZStack {
            Circle().fill(Color(red: 0.0, green: 0.72, blue: 0.49).opacity(0.15))
            Image(systemName: "checkmark")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Color(red: 0.19, green: 0.86, blue: 0.61))
        }
        .frame(width: 72, height: 72)
        .padding(.bottom, 20)
    }

    private var outputSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BiCutTheme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("SAVED TO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(BiCutTheme.muted)
                Text(model.destinationDisplayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 14).fill(BiCutTheme.control))
        .padding(.vertical, 25)
    }
}
