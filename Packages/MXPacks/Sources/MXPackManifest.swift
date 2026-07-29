import Foundation
import MXAudioDSP

/// Which backend plays a pack. Adding an engine later means adding a case and a
/// resolver entry — never touching a call site.
public enum MXPackEngine: String, Codable, CaseIterable, Sendable {
    case appleSampler = "apple_sampler"
    case sfz
    case drumkit
    case synth
    case auv3
}

public enum MXPackType: String, Codable, CaseIterable, Sendable {
    case instrument
    case drumkit
    case samplePack
    case impulseResponse
    case effectPreset
}

/// Three-tier delivery from section 5 of the plan.
public enum MXPackTier: String, Codable, CaseIterable, Sendable {
    /// Ships inside the app binary; must stay within the bundled size budget.
    case bundled
    /// Fetched on first launch.
    case download
    /// Fetched when the user asks for it.
    case onDemand = "on_demand"
}

/// Licence and provenance.
///
/// Section 9 of the plan treats this as a shipping blocker rather than
/// metadata: SoundFonts circulating as "public domain" routinely contain
/// unlicensed commercial samples, so every pack must be able to prove where it
/// came from.
public struct MXPackLicense: Codable, Equatable, Sendable {
    public var spdx: String
    public var source: String
    public var attribution: String?

    public init(spdx: String, source: String, attribution: String? = nil) {
        self.spdx = spdx
        self.source = source
        self.attribution = attribution
    }

    /// Licences cleared for App Store distribution. Anything outside this list
    /// needs a human decision, so it fails the gate rather than passing quietly.
    public static let approvedSPDX: Set<String> = [
        "CC0-1.0", "CC-BY-4.0", "CC-BY-3.0", "CC-BY-SA-4.0",
        "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause",
        "LGPL-3.0-or-later", "Unlicense",
        // First-party content.
        "LicenseRef-MXStudio-Proprietary",
    ]

    public static let unlicensedMarker = "UNLICENSED"

    public var isApproved: Bool {
        MXPackLicense.approvedSPDX.contains(spdx)
    }
}

public struct MXPackPreset: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Program number for `apple_sampler` packs.
    public var program: UInt8?

    public init(id: String, name: String, program: UInt8? = nil) {
        self.id = id
        self.name = name
        self.program = program
    }
}

/// The `.mxpack` manifest. One schema covers instruments, drum kits, sample
/// packs, IRs and effect presets.
public struct MXPackManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let fileName = "manifest.json"

    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var type: MXPackType
    public var engine: MXPackEngine
    /// Path to the pack's entry file, relative to the pack root.
    public var entry: String
    public var category: String
    public var sizeBytes: Int
    public var tier: MXPackTier
    public var license: MXPackLicense
    public var presets: [MXPackPreset]

    /// SHA-256 of the archive, verified before install completes.
    public var checksum: String?
    public var downloadURL: URL?
    /// Root note for `sample_pack` packs that need one.
    public var rootNote: UInt8?

    public init(schemaVersion: Int = MXPackManifest.currentSchemaVersion,
                id: String,
                name: String,
                type: MXPackType,
                engine: MXPackEngine,
                entry: String,
                category: String,
                sizeBytes: Int,
                tier: MXPackTier,
                license: MXPackLicense,
                presets: [MXPackPreset] = [],
                checksum: String? = nil,
                downloadURL: URL? = nil,
                rootNote: UInt8? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.type = type
        self.engine = engine
        self.entry = entry
        self.category = category
        self.sizeBytes = sizeBytes
        self.tier = tier
        self.license = license
        self.presets = presets
        self.checksum = checksum
        self.downloadURL = downloadURL
        self.rootNote = rootNote
    }

    // MARK: - Validation

    /// Structural and licensing validation. Called at install time and again by
    /// the CI gate, so a bad pack cannot reach a build.
    public func validate() throws {
        guard schemaVersion == MXPackManifest.currentSchemaVersion else {
            throw MXAudioError.manifestInvalid(
                reason: "unsupported schemaVersion \(schemaVersion), expected \(MXPackManifest.currentSchemaVersion)")
        }
        guard !id.isEmpty, id.contains(".") else {
            throw MXAudioError.manifestInvalid(reason: "id must be reverse-DNS, got '\(id)'")
        }
        guard !name.isEmpty else {
            throw MXAudioError.manifestInvalid(reason: "name is empty")
        }
        guard !entry.isEmpty else {
            throw MXAudioError.manifestInvalid(reason: "entry is empty")
        }
        guard !entry.hasPrefix("/"), !entry.contains("..") else {
            throw MXAudioError.manifestInvalid(
                reason: "entry must be a relative path inside the pack, got '\(entry)'")
        }
        guard sizeBytes >= 0 else {
            throw MXAudioError.manifestInvalid(reason: "sizeBytes is negative")
        }
        if tier != .bundled, downloadURL == nil {
            throw MXAudioError.manifestInvalid(
                reason: "tier '\(tier.rawValue)' requires a downloadURL")
        }
        try validateLicense()
    }

    public func validateLicense() throws {
        guard !license.spdx.isEmpty,
              license.spdx != MXPackLicense.unlicensedMarker else {
            throw MXAudioError.licenseMissing(packID: id)
        }
        guard !license.source.isEmpty else {
            throw MXAudioError.manifestInvalid(
                reason: "pack '\(id)' has an SPDX id but no provenance source")
        }
        guard license.isApproved else {
            throw MXAudioError.manifestInvalid(
                reason: "pack '\(id)' uses unapproved licence '\(license.spdx)'")
        }
    }

    // MARK: - Serialisation

    public static func decode(from data: Data) throws -> MXPackManifest {
        do {
            return try JSONDecoder().decode(MXPackManifest.self, from: data)
        } catch let error as DecodingError {
            throw MXAudioError.manifestInvalid(reason: describe(error))
        } catch {
            throw MXAudioError.manifestInvalid(reason: error.localizedDescription)
        }
    }

    public static func load(from url: URL) throws -> MXPackManifest {
        guard let data = try? Data(contentsOf: url) else {
            throw MXAudioError.resourceNotFound(path: url.path)
        }
        return try decode(from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decoding errors are otherwise opaque; a missing key should say which key.
    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _):
            return "missing required field '\(key.stringValue)'"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "field '\(path)' should be \(type)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "field '\(path)' is null but must be \(type)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "malformed JSON" : "field '\(path)' is malformed"
        @unknown default:
            return "\(error)"
        }
    }
}

/// An installed pack on disk.
public struct MXInstalledPack: Equatable, Sendable {
    public var manifest: MXPackManifest
    public var root: URL

    public init(manifest: MXPackManifest, root: URL) {
        self.manifest = manifest
        self.root = root
    }

    public var entryURL: URL {
        root.appendingPathComponent(manifest.entry)
    }

    public var isEntryPresent: Bool {
        FileManager.default.fileExists(atPath: entryURL.path)
    }
}
