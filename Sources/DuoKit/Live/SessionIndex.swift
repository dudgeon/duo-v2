import Foundation

/// `<project>/.duo/sessions.json`: Duo-owned facts about a project's sessions (DL-1). Facts that
/// come from Claude (titles, state, transcripts) are never copied here; task links live in task
/// frontmatter (DL-13).
public struct SessionIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var sessionId: String
        public var createdAt: Date
        /// How the session came to be filed here (CONS FR-7.2.3).
        public var provenance: String
        /// Agent self-narration (LR-5): `duo2 session note` / `next`.
        public var note: String?
        public var next: String?
        public var starred: Bool?
        public var archived: Bool?

        public init(sessionId: String, createdAt: Date = Date(), provenance: String = "created-by-duo") {
            self.sessionId = sessionId
            self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))  // ISO 8601 keeps seconds
            self.provenance = provenance
        }
    }

    public struct Group: Codable, Sendable, Equatable {
        public var name: String
        public var sessions: [String]

        public init(name: String, sessions: [String]) { self.name = name; self.sessions = sessions }
    }

    public var schema = 1
    public var sessions: [Entry] = []
    public var groups: [Group] = []

    public init() {}

    public static func url(for project: URL) -> URL { project.appending(path: ".duo/sessions.json") }

    /// Reads the index; a missing or unreadable file is an empty index, never an error.
    public static func load(project: URL) -> SessionIndex {
        guard let data = try? Data(contentsOf: url(for: project)) else { return SessionIndex() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode(SessionIndex.self, from: data)) ?? SessionIndex()
    }

    /// Atomic write: a unique temp file in `.duo/`, then rename (LR-35). Byte-equal content isn't
    /// rewritten (no spurious watcher events, LDI-39).
    public func save(project: URL) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try e.encode(self) + Data("\n".utf8)
        let target = Self.url(for: project)
        if let existing = try? Data(contentsOf: target), existing == data { return }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = target.deletingLastPathComponent().appending(path: ".sessions.\(UUID().uuidString).tmp")
        try data.write(to: temp)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
    }
}
