import Foundation

/// The sample data shown on every design target (`docs/design/build-handoff/fixture.json`).
/// Previews, screenshots and tests load it; the live state layer (phase E) fills the same model.
public struct Fixture: Codable, Sendable, Equatable {
    public struct Project: Codable, Sendable, Equatable, Identifiable {
        public var name: String
        public var topic: String?
        public var path: String
        public var isHome: Bool?
        public var goal: String
        public var health: String?
        public var next: String?
        /// "folder": a folder with Claude sessions but no PROJECT.md (DL-63); nil for projects.
        public var kind: String?
        /// The folder has a CLAUDE.md: it was set up with intent, a likely project (DL-63).
        public var hasClaudeMD: Bool?
        /// DB-8: a folder whose sessions remain but which isn't where they ran ("missing" kind):
        /// what happened, in words, and where Duo found it, if it did.
        public var missing: String? = nil
        public var movedTo: String? = nil
        /// A project whose sessions are still filed under the folder it moved from: that path, and how many.
        public var movedFrom: String? = nil
        public var staleSessions: Int? = nil
        /// A folder whose Make a Project notice the user said Not Now to (DL-110).
        public var notNow: Bool? = nil
        public var id: String { name }
        public var isFolderOnly: Bool { kind == "folder" || kind == "missing" }
        public var isMissing: Bool { kind == "missing" }
    }

    public struct Session: Codable, Sendable, Equatable, Identifiable {
        public var name: String
        public var project: String
        public var state: SessionState
        public var wait: String?
        public var question: String?
        public var options: [String]?
        public var summary: String?
        public var forkOf: String?
        public var document: String?
        /// The Claude Code session id, for live sessions (Phase E). Fixture sessions have none.
        public var sessionId: String?
        /// Why it needs you, said after the project on its card (DL-100): question, permission, plan to approve.
        public var reason: String? = nil
        /// Last activity, ms since 1970 (live sessions; DL-104's Recent order). Fixture sessions have
        /// none and are ordered by their wait text instead.
        public var lastActive: Double? = nil
        public var id: String { "\(project)/\(name)" }
        /// What console tabs and terminals are keyed by: the session id when there is one.
        public var tabKey: String { sessionId ?? name }
    }

    public struct Group: Codable, Sendable, Equatable {
        public var name: String
        public var project: String
        public var sessions: [String]
        public var threads: [[String]]
        /// A task note's path in the project (DL-93), when this bundle is a task rather than a group.
        public var task: String? = nil
    }

    public struct Counts: Codable, Sendable, Equatable {
        public var needsYou: Int
        public var readyForReview: Int
        public var working: Int
        public var idle: Int
    }

    public struct InboxItem: Codable, Sendable, Equatable {
        public var title: String
        public var source: String?
        public var status: String?
    }

    public struct FocusDocument: Codable, Sendable, Equatable {
        public var project: String
        public var path: String
        public var sections: [String]
        public var addedByClaude: [String]
    }

    public var now: String
    public var user: String
    public var topics: [String]
    public var projects: [Project]
    public var sessions: [Session]
    public var otherIdleSessions: Int
    public var groups: [Group]
    public var counts: Counts
    public var homeInbox: [InboxItem]
    public var focusDocument: FocusDocument
    public var projectFiles: [String: [String]]
    /// Sessions the user archived (filed away), kept apart from `sessions` so no list or count shows them.
    public var archivedSessions: [Session]? = nil
    /// Every task note in every project (DL-93), with or without sessions.
    public var tasks: [TaskSummary]? = nil

    public struct TaskSummary: Codable, Sendable, Equatable, Identifiable {
        public var project: String
        public var path: String
        public var title: String
        public var status: String?
        public var sessionIds: [String]
        public var id: String { project + "/" + path }
        /// Done and dropped tasks leave the lists (they stay notes).
        public var isOpen: Bool { !["done", "dropped"].contains(status ?? "") }
    }

    public static func load(from url: URL) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    public var home: Project? { projects.first { $0.isHome == true } }

    public func projects(inTopic topic: String) -> [Project] {
        projects.filter { $0.topic == topic }
    }

    /// Archived sessions in a project (filed away: not in lists or counts).
    public func archivedSessions(inProject project: String) -> [Session] {
        (archivedSessions ?? []).filter { $0.project == project }
    }

    public func sessions(inProject project: String) -> [Session] {
        sessions.filter { $0.project == project }
    }

    /// Live sessions in a project (needs you, ready for review, working), in source order.
    /// Tiles keep this order as states change (flow-zoom-4), so rows don't jump around.
    public func liveSessions(inProject project: String) -> [Session] {
        sessions.filter { $0.project == project && [.needsYou, .readyForReview, .working].contains($0.state) }
    }

    /// Sessions needing you, longest wait first (handoff §2.2).
    public var needsYou: [Session] {
        sessions.filter { $0.state == .needsYou }.sorted { WaitTime($0.wait) > WaitTime($1.wait) }
    }
}

/// A wait time as the targets print it: `now`, `4m`, `1h`, `3d` (handoff §8).
public struct WaitTime: Comparable, Sendable {
    public let seconds: Int

    public init(_ text: String?) {
        guard let text, let unit = text.last, let n = Int(text.dropLast()) else {
            seconds = 0
            return
        }
        switch unit {
        case "m": seconds = n * 60
        case "h": seconds = n * 3600
        case "d": seconds = n * 86400
        default: seconds = 0
        }
    }

    public static func < (a: WaitTime, b: WaitTime) -> Bool { a.seconds < b.seconds }
}
