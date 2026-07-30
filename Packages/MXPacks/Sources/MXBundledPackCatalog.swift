import Foundation

/// First-party bundled pack catalog (Week 79 — BandLab / Loopcloud lite).
///
/// Procedural / placeholder entries only — no licensed binary assets and no
/// network downloads. Install materializes a minimal on-disk `.mxpack`
/// directory (`manifest.json` + entry file) then hands it to `MXPackInstaller`.
public enum MXBundledPackCatalog {

    /// Human-facing subtitle for browser rows (type / engine).
    public struct Item: Identifiable, Equatable, Sendable {
        public var manifest: MXPackManifest
        public var subtitle: String
        public var systemImage: String

        public var id: String { manifest.id }
        public var name: String { manifest.name }
    }

    public static let all: [Item] = [
        Item(
            manifest: MXPackManifest(
                id: "com.mxstudio.packs.kit-lite",
                name: "MX Kit Lite",
                type: .drumkit,
                engine: .drumkit,
                entry: "kit.json",
                category: "Drums",
                sizeBytes: 256,
                tier: .bundled,
                license: MXPackLicense(
                    spdx: "LicenseRef-MXStudio-Proprietary",
                    source: "MXStudio first-party procedural stub",
                    attribution: "MXStudio Pro"
                ),
                presets: [
                    MXPackPreset(id: "kit_default", name: "Lite Kit"),
                ]
            ),
            subtitle: "Drum kit · bundled stub",
            systemImage: "circle.grid.2x2.fill"
        ),
        Item(
            manifest: MXPackManifest(
                id: "com.mxstudio.packs.keys-lite",
                name: "MX Keys Lite",
                type: .instrument,
                engine: .synth,
                entry: "synth.json",
                category: "Keys",
                sizeBytes: 256,
                tier: .bundled,
                license: MXPackLicense(
                    spdx: "LicenseRef-MXStudio-Proprietary",
                    source: "MXStudio first-party procedural stub",
                    attribution: "MXStudio Pro"
                ),
                presets: [
                    MXPackPreset(id: "keys_default", name: "Lite Keys", program: 0),
                ]
            ),
            subtitle: "Synth · bundled stub",
            systemImage: "pianokeys"
        ),
        Item(
            manifest: MXPackManifest(
                id: "com.mxstudio.packs.samples-lite",
                name: "MX Samples Lite",
                type: .samplePack,
                engine: .appleSampler,
                entry: "samples.json",
                category: "Samples",
                sizeBytes: 256,
                tier: .bundled,
                license: MXPackLicense(
                    spdx: "LicenseRef-MXStudio-Proprietary",
                    source: "MXStudio first-party procedural stub",
                    attribution: "MXStudio Pro"
                ),
                presets: [
                    MXPackPreset(id: "samples_default", name: "Lite Hits"),
                ],
                rootNote: 60
            ),
            subtitle: "Sample pack · bundled stub",
            systemImage: "waveform"
        ),
    ]

    public static func item(id: String) -> Item? {
        all.first { $0.id == id }
    }

    public static func manifest(id: String) -> MXPackManifest? {
        item(id: id)?.manifest
    }

    /// Writes a minimal pack directory: `manifest.json` + the entry file.
    ///
    /// The entry is a tiny JSON placeholder so install validation passes without
    /// shipping binary sample assets.
    @discardableResult
    public static func materializePackDirectory(
        id: String,
        into directory: URL
    ) throws -> URL {
        guard let item = item(id: id) else {
            throw MXAudioError.resourceNotFound(path: id)
        }
        try item.manifest.validate()

        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let manifestURL = directory.appendingPathComponent(MXPackManifest.fileName)
        try item.manifest.encoded().write(to: manifestURL, options: .atomic)

        let entryURL = directory.appendingPathComponent(item.manifest.entry)
        let entryParent = entryURL.deletingLastPathComponent()
        if entryParent.path != directory.path {
            try fm.createDirectory(at: entryParent, withIntermediateDirectories: true)
        }
        let entryPayload = try entryPlaceholderJSON(for: item.manifest)
        try entryPayload.write(to: entryURL, options: .atomic)

        return directory
    }

    /// Materialize into a staging folder under `temporaryDirectory`, then install.
    @discardableResult
    public static func install(
        id: String,
        into installer: MXPackInstaller
    ) throws -> MXInstalledPack {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXBundledPack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        let packDir = stagingRoot.appendingPathComponent(id, isDirectory: true)
        try materializePackDirectory(id: id, into: packDir)
        return try installer.install(from: packDir)
    }

    private static func entryPlaceholderJSON(for manifest: MXPackManifest) throws -> Data {
        let payload: [String: Any] = [
            "packID": manifest.id,
            "name": manifest.name,
            "type": manifest.type.rawValue,
            "engine": manifest.engine.rawValue,
            "placeholder": true,
            "note": "Week 79 bundled stub — replace with real assets later",
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
