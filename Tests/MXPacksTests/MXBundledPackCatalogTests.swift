import XCTest
@testable import MXPacks

/// Week 79 — bundled catalog + install path (BandLab / Loopcloud lite).
final class MXBundledPackCatalogTests: XCTestCase {

    func testCatalogIsNonEmpty() {
        XCTAssertGreaterThanOrEqual(MXBundledPackCatalog.all.count, 2)
        XCTAssertLessThanOrEqual(MXBundledPackCatalog.all.count, 4)
    }

    func testCatalogIDsAreReverseDNSAndUnique() {
        let ids = MXBundledPackCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ids {
            XCTAssertTrue(id.hasPrefix("com.mxstudio.packs."), "unexpected id \(id)")
            XCTAssertTrue(id.contains("."))
        }
    }

    func testAllManifestsValidate() throws {
        for item in MXBundledPackCatalog.all {
            try item.manifest.validate()
            XCTAssertEqual(item.manifest.tier, .bundled)
            XCTAssertEqual(item.manifest.license.spdx, "LicenseRef-MXStudio-Proprietary")
            XCTAssertFalse(item.manifest.license.source.isEmpty)
            XCTAssertNil(item.manifest.downloadURL)
        }
    }

    func testMaterializeWritesManifestAndEntry() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXPackMaterialize-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let id = "com.mxstudio.packs.kit-lite"
        _ = try MXBundledPackCatalog.materializePackDirectory(id: id, into: dir)

        let manifestURL = dir.appendingPathComponent(MXPackManifest.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))

        let manifest = try MXPackManifest.load(from: manifestURL)
        XCTAssertEqual(manifest.id, id)
        try manifest.validate()

        let entryURL = dir.appendingPathComponent(manifest.entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: entryURL.path))
    }

    func testInstallFromGeneratedDirectory() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXPackLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: library) }

        let installer = try MXPackInstaller(libraryRoot: library)
        let id = "com.mxstudio.packs.keys-lite"

        XCTAssertFalse(installer.isInstalled(id: id))
        let installed = try MXBundledPackCatalog.install(id: id, into: installer)

        XCTAssertEqual(installed.manifest.id, id)
        XCTAssertTrue(installer.isInstalled(id: id))
        XCTAssertTrue(installed.isEntryPresent)
        XCTAssertEqual(installer.installedPacks().count, 1)
    }

    func testInstallUnknownIDFails() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXPackLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: library) }

        let installer = try MXPackInstaller(libraryRoot: library)
        XCTAssertThrowsError(try MXBundledPackCatalog.install(id: "com.mxstudio.packs.missing", into: installer))
    }

    func testInstallAllBundledPacks() throws {
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent("MXPackLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: library) }

        let installer = try MXPackInstaller(libraryRoot: library)
        for item in MXBundledPackCatalog.all {
            _ = try MXBundledPackCatalog.install(id: item.id, into: installer)
        }
        XCTAssertEqual(installer.installedPacks().count, MXBundledPackCatalog.all.count)
    }
}
