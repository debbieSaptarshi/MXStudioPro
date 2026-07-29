import CryptoKit
import Foundation
import MXAudioDSP

/// Installs `.mxpack` bundles.
///
/// Installs are staged in a scratch directory and only moved into place once
/// the manifest validates and the checksum matches. A failed install therefore
/// leaves nothing behind, which is what scenario P-03 checks — a half-installed
/// pack is worse than no pack, because it looks available and then plays
/// silence.
public final class MXPackInstaller: @unchecked Sendable {

    public struct Progress: Sendable {
        public var packID: String
        public var bytesReceived: Int64
        public var bytesExpected: Int64

        public var fraction: Double {
            bytesExpected > 0 ? Double(bytesReceived) / Double(bytesExpected) : 0
        }
    }

    public let libraryRoot: URL
    private let fileManager = FileManager.default
    private let session: URLSession

    public init(libraryRoot: URL, session: URLSession = .shared) throws {
        self.libraryRoot = libraryRoot
        self.session = session
        try fileManager.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    /// Default library location under Application Support.
    public static func defaultLibraryRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        return base.appendingPathComponent("MXStudio/Packs", isDirectory: true)
    }

    // MARK: - Query

    public func installedPacks() -> [MXInstalledPack] {
        guard let entries = try? fileManager.contentsOfDirectory(at: libraryRoot,
                                                                 includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { directory in
            let manifestURL = directory.appendingPathComponent(MXPackManifest.fileName)
            guard let manifest = try? MXPackManifest.load(from: manifestURL) else { return nil }
            return MXInstalledPack(manifest: manifest, root: directory)
        }
        .sorted { $0.manifest.name < $1.manifest.name }
    }

    public func installedPack(id: String) -> MXInstalledPack? {
        let root = libraryRoot.appendingPathComponent(id, isDirectory: true)
        let manifestURL = root.appendingPathComponent(MXPackManifest.fileName)
        guard let manifest = try? MXPackManifest.load(from: manifestURL) else { return nil }
        return MXInstalledPack(manifest: manifest, root: root)
    }

    public func isInstalled(id: String) -> Bool {
        installedPack(id: id) != nil
    }

    // MARK: - Install

    /// Installs from an unpacked `.mxpack` directory already on disk.
    @discardableResult
    public func install(from sourceDirectory: URL) throws -> MXInstalledPack {
        let manifestURL = sourceDirectory.appendingPathComponent(MXPackManifest.fileName)
        let manifest = try MXPackManifest.load(from: manifestURL)
        try manifest.validate()

        let entry = sourceDirectory.appendingPathComponent(manifest.entry)
        guard fileManager.fileExists(atPath: entry.path) else {
            throw MXAudioError.manifestInvalid(
                reason: "entry '\(manifest.entry)' does not exist in the pack")
        }

        let destination = libraryRoot.appendingPathComponent(manifest.id, isDirectory: true)
        let staging = try makeStagingDirectory(for: manifest.id)
        defer { try? fileManager.removeItem(at: staging) }

        let staged = staging.appendingPathComponent(manifest.id, isDirectory: true)
        try fileManager.copyItem(at: sourceDirectory, to: staged)

        try commit(staged: staged, to: destination)
        return MXInstalledPack(manifest: manifest, root: destination)
    }

    /// Downloads and installs a pack, verifying the manifest checksum first.
    @discardableResult
    public func download(_ manifest: MXPackManifest,
                         onProgress: (@Sendable (Progress) -> Void)? = nil) async throws -> MXInstalledPack {
        try manifest.validate()
        guard let url = manifest.downloadURL else {
            throw MXAudioError.manifestInvalid(reason: "pack '\(manifest.id)' has no downloadURL")
        }

        let staging = try makeStagingDirectory(for: manifest.id)
        defer { try? fileManager.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("archive.mxpack")
        let (temporaryURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MXAudioError.exportFailed("download failed with HTTP \(http.statusCode)")
        }
        try fileManager.moveItem(at: temporaryURL, to: archive)

        onProgress?(Progress(packID: manifest.id,
                             bytesReceived: Int64(manifest.sizeBytes),
                             bytesExpected: Int64(manifest.sizeBytes)))

        if let expected = manifest.checksum {
            let actual = try Self.sha256(ofFileAt: archive)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                throw MXAudioError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try unpack(archive: archive, to: unpacked)

        let root = try locatePackRoot(in: unpacked)
        let installedManifest = try MXPackManifest.load(
            from: root.appendingPathComponent(MXPackManifest.fileName))
        try installedManifest.validate()
        guard installedManifest.id == manifest.id else {
            throw MXAudioError.manifestInvalid(
                reason: "downloaded pack id '\(installedManifest.id)' does not match catalog id '\(manifest.id)'")
        }

        let destination = libraryRoot.appendingPathComponent(manifest.id, isDirectory: true)
        try commit(staged: root, to: destination)
        return MXInstalledPack(manifest: installedManifest, root: destination)
    }

    public func uninstall(id: String) throws {
        let root = libraryRoot.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    // MARK: - Checksum

    public static func sha256(ofFileAt url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw MXAudioError.resourceNotFound(path: url.path)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        // Chunked so a multi-hundred-megabyte pack does not have to be resident.
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private

    private func makeStagingDirectory(for packID: String) throws -> URL {
        let staging = libraryRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("\(packID)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// Swaps the staged pack into place, keeping the previous version until the
    /// move succeeds so a failed upgrade does not lose a working pack.
    private func commit(staged: URL, to destination: URL) throws {
        let backup = destination.appendingPathExtension("previous")
        try? fileManager.removeItem(at: backup)

        let hadPrevious = fileManager.fileExists(atPath: destination.path)
        if hadPrevious {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if hadPrevious {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw MXAudioError.exportFailed("could not install pack: \(error.localizedDescription)")
        }
        try? fileManager.removeItem(at: backup)
    }

    private func unpack(archive: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        // An unzipped `.mxpack` directory may be handed over directly during
        // development; only actually archived payloads need extraction.
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: archive.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let contents = try fileManager.contentsOfDirectory(at: archive,
                                                               includingPropertiesForKeys: nil)
            for item in contents {
                try fileManager.copyItem(at: item,
                                         to: destination.appendingPathComponent(item.lastPathComponent))
            }
            return
        }

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archive.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MXAudioError.exportFailed("unzip failed with status \(process.terminationStatus)")
        }
        #else
        throw MXAudioError.notSupportedOnPlatform("archive extraction")
        #endif
    }

    /// Archives may or may not wrap the pack in a top-level folder.
    private func locatePackRoot(in directory: URL) throws -> URL {
        let manifestAtRoot = directory.appendingPathComponent(MXPackManifest.fileName)
        if fileManager.fileExists(atPath: manifestAtRoot.path) { return directory }

        let contents = try fileManager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.isDirectoryKey])
        for candidate in contents {
            let manifest = candidate.appendingPathComponent(MXPackManifest.fileName)
            if fileManager.fileExists(atPath: manifest.path) { return candidate }
        }
        throw MXAudioError.manifestInvalid(reason: "archive contains no \(MXPackManifest.fileName)")
    }
}
