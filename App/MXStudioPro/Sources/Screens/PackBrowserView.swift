import SwiftUI

/// BandLab / Loopcloud-style sound pack browser (Week 79).
///
/// Lists first-party bundled catalog packs; Install materializes a minimal
/// on-disk pack and copies it into Application Support via `MXPackInstaller`.
struct PackBrowserView: View {
    let session: StudioSessionController
    var onClose: () -> Void

    @State private var installedIDs: Set<String> = []
    @State private var installingID: String?
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("First-party bundled stubs · not licensed Loopcloud packs")
                        .font(MXFont.caption())
                        .foregroundStyle(MXColor.grey)
                        .listRowBackground(Color.clear)
                }

                Section("Bundled packs") {
                    ForEach(MXBundledPackCatalog.all) { item in
                        packRow(item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MXColor.surface.ignoresSafeArea())
            .navigationTitle("Packs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                        .foregroundStyle(MXColor.lightGrey)
                }
            }
            .alert("Couldn’t install pack", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .onAppear { refreshInstalled() }
        }
        .preferredColorScheme(.dark)
    }

    private func packRow(_ item: MXBundledPackCatalog.Item) -> some View {
        let isInstalled = installedIDs.contains(item.id)
        return HStack(spacing: 12) {
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
            if installingID == item.id {
                ProgressView()
                    .tint(MXColor.accent)
            } else if isInstalled {
                Text("Installed")
                    .font(MXFont.caption())
                    .foregroundStyle(MXColor.accent)
            } else {
                Button("Install") {
                    install(item)
                }
                .font(MXFont.caption())
                .foregroundStyle(MXColor.accent)
                .disabled(installingID != nil)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(MXColor.layer2)
        .accessibilityLabel("\(item.name), \(item.subtitle)")
        .accessibilityValue(isInstalled ? "Installed" : "Not installed")
    }

    private func refreshInstalled() {
        installedIDs = Set(session.installedPacks().map(\.manifest.id))
    }

    private func install(_ item: MXBundledPackCatalog.Item) {
        installingID = item.id
        do {
            _ = try session.installBundledPack(id: item.id)
            installingID = nil
            refreshInstalled()
        } catch {
            installingID = nil
            actionError = error.localizedDescription
        }
    }
}
