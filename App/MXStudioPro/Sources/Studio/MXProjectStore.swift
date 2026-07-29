import Foundation

/// Local project persistence: `Documents/Projects/<id>/project.json` + `Audio/`.
///
/// Week 3 exit criterion: kill app → reopen loads the same project.
public final class MXProjectStore: @unchecked Sendable {
    public static let shared = MXProjectStore()

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let lastOpenedKey = "mxstudio.lastOpenedProjectID"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init() {}

    public var projectsRoot: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    public func projectDirectory(for id: UUID) -> URL {
        projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func audioDirectory(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent("Audio", isDirectory: true)
    }

    public var lastOpenedProjectID: UUID? {
        get {
            guard let raw = defaults.string(forKey: lastOpenedKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: lastOpenedKey)
        }
    }

    public func createVocalProject(bpm: Double = 120) throws -> MXProject {
        var project = MXProject.untitledVocal(bpm: bpm)
        try save(project)
        lastOpenedProjectID = project.id
        return project
    }

    public func save(_ project: MXProject) throws {
        var mutable = project
        mutable.modifiedAt = .now

        let dir = projectDirectory(for: mutable.id)
        let audio = audioDirectory(for: mutable.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: audio, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("project.json")
        let data = try encoder.encode(mutable)
        try data.write(to: url, options: [.atomic])
        lastOpenedProjectID = mutable.id
    }

    public func load(id: UUID) throws -> MXProject {
        let url = projectDirectory(for: id).appendingPathComponent("project.json")
        let data = try Data(contentsOf: url)
        let project = try decoder.decode(MXProject.self, from: data)
        lastOpenedProjectID = project.id
        return project
    }

    public func loadLastOpened() -> MXProject? {
        guard let id = lastOpenedProjectID else { return nil }
        return try? load(id: id)
    }

    /// Opens last project when present; otherwise creates a new vocals project.
    public func openOrCreateVocalProject() throws -> MXProject {
        if let existing = loadLastOpened(), existing.preset == .vocal {
            return existing
        }
        return try createVocalProject()
    }
}
