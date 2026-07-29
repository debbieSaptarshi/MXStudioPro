import SwiftUI

/// Picker for BandLab-style demo templates (Week 19).
struct DemoTemplatesView: View {
    var onSelectTemplate: (MXDemoTemplate) -> Void
    var onClose: () -> Void

    @State private var errorMessage: String?

    init(
        onSelectTemplate: @escaping (MXDemoTemplate) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.onSelectTemplate = onSelectTemplate
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(MXDemoTemplates.all) { template in
                        templateRow(template)
                    }
                }
                .padding(16)
            }
        }
        .background(MXColor.surface.ignoresSafeArea())
        .alert("Template", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo Templates")
                    .font(MXFont.sectionTitle())
                    .foregroundStyle(MXColor.white)
                Text("\(MXDemoTemplates.all.count) starter projects")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.grey)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MXColor.white)
                    .frame(width: 20, height: 20)
            }
            .mxMetalButton(.icon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MXColor.surfaceRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MXColor.layer2).frame(height: 1)
        }
    }

    private func templateRow(_ template: MXDemoTemplate) -> some View {
        Button {
            onSelectTemplate(template)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: template.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MXColor.accent)
                    .frame(width: 24, height: 24)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MXColor.layer2)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(template.subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                    Text("\(Int(template.bpm)) BPM · \(template.tracks.count) track\(template.tracks.count == 1 ? "" : "s")")
                        .font(MXFont.body3())
                        .foregroundStyle(MXColor.accent)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MXColor.grey)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MXColor.surfaceRaised)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Demo Templates") {
    DemoTemplatesView()
}
