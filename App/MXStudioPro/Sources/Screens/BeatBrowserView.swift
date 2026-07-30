import SwiftUI

/// BandLab / Loopcloud-style beat browser (Week 74).
///
/// Lists bundled procedural loops + one-shots; tapping imports a new track.
struct BeatBrowserView: View {
    let session: StudioSessionController
    var onClose: () -> Void
    var onImported: (UUID) -> Void

    @State private var importError: String?
    @State private var isImportingID: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Procedural packs · first-party stubs (not licensed sample packs)")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .listRowBackground(Color.clear)
                }

                Section("Loops") {
                    ForEach(MXBeatCatalog.all.filter { $0.kind == .loop }) { item in
                        beatRow(item)
                    }
                }

                Section("One-shots") {
                    ForEach(MXBeatCatalog.all.filter { $0.kind == .oneShot }) { item in
                        beatRow(item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MXColor.surface.ignoresSafeArea())
            .navigationTitle("Beats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .foregroundStyle(MXColor.lightGrey)
                }
            }
            .alert("Couldn’t import beat", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func beatRow(_ item: MXBeatCatalogItem) -> some View {
        Button {
            importItem(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MXColor.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(MXFont.mediumButton())
                        .foregroundStyle(MXColor.white)
                    Text(item.subtitle)
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                }
                Spacer(minLength: 0)
                if isImportingID == item.id {
                    ProgressView()
                        .tint(MXColor.accent)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(MXColor.accent)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(isImportingID != nil)
        .listRowBackground(MXColor.layer2)
        .accessibilityLabel("\(item.name), \(item.subtitle)")
        .accessibilityHint("Adds a new track with this beat")
    }

    private func importItem(_ item: MXBeatCatalogItem) {
        isImportingID = item.id
        do {
            let track = try session.importBeatItem(item)
            isImportingID = nil
            onImported(track.id)
            onClose()
        } catch {
            isImportingID = nil
            importError = error.localizedDescription
        }
    }
}
