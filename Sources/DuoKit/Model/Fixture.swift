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
        /// The Remote Control name it was started with (DL-128), from the session index.
        public var remoteControl: String? = nil
        /// A Claude process is running for it (a hook beacon). With no Duo terminal open for it, it runs
        /// outside Duo: a terminal session as far as its glyph goes (DL-174).
        public var liveProcess: Bool? = nil
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
        /// Opt-in demo text (video fixtures): a markdown file beside the fixture, split at `## Heading`
        /// into `body`. Absent in the design fixture, so default captures don't change.
        public var markdownFile: String? = nil
        /// Section name -> body text; filled by `Fixture.load` from `markdownFile`.
        public var body: [String: String]? = nil
    }

    /// Opt-in demo for the intro video's scene 2 (`--state video-s2-*`, VideoTargets): real files in the
    /// project's right pane, recorded screens in its terminals. Absent in the design fixture.
    public struct VideoS2: Codable, Sendable, Equatable {
        public struct Terminal: Codable, Sendable, Equatable {
            public var name: String
            public var state: SessionState
            public var wait: String?
            /// A text file beside the fixture: the terminal's screen, ANSI allowed.
            public var screen: String
        }
        /// The project's folder, relative to the fixture's own: its real files.
        public var folder: String
        public var terminals: [Terminal]
        /// A chat recording folder beside the fixture (meta.json, transcript.jsonl) for the last terminal's chat view.
        public var chat: String
        /// Documents open in the right pane, project-relative, in tab order.
        public var tabs: [String]
        /// What the Files block lists.
        public var files: [String]
        /// The project the scene opens (default checkout-redesign, the first fixture's) and the chat's working
        /// folder as Claude saw it. Set by the demo world (video/fixture/SCENARIO.md).
        public var project: String? = nil
        public var cwd: String? = nil
        /// Scene 4's terminal screen for "Auto-add decision" (ANSI allowed), relative to the fixture; missing: an empty screen.
        public var s4Terminal: String? = nil
        /// Scene 5's chat recording folder for the same session, relative to the fixture.
        public var s5Chat: String? = nil
    }
    public var videoS2: VideoS2? = nil
    /// The folder the fixture was loaded from (not part of the file).
    public var baseDir: String? = nil

    public var now: String
    /// Equal but for the clock: `now` is stamped on every refresh and nothing reads it, so it mustn't make an idle refresh look like a change (C-79).
    public func sameApartFromClock(_ other: Fixture) -> Bool { var c = self; c.now = other.now; return c == other }
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
        /// Archived (DL-115): out of the lists and counts, in the project's Archived fold.
        public var archived: Bool? = nil
        /// What a board card shows (DL-148); absent in the design fixture.
        public var owner: String? = nil
        public var waitingOn: String? = nil
        public var due: String? = nil
        public var created: String? = nil
        public var completed: String? = nil
        public var references: Int? = nil
        public var id: String { project + "/" + path }
        public init(project: String, path: String, title: String, status: String?, sessionIds: [String], archived: Bool? = nil) {
            self.project = project; self.path = path; self.title = title; self.status = status; self.sessionIds = sessionIds; self.archived = archived
        }
        /// A task note as the lists and the board see it.
        public init(project: String, note t: TaskNote) {
            self.init(project: project, path: t.path, title: t.title, status: t.status, sessionIds: t.sessionIds, archived: t.archived ? true : nil)
            owner = t.owner; waitingOn = t.waitingOn; due = t.due; created = t.created; completed = t.completed
            references = t.references.isEmpty ? nil : t.references.count
        }
        /// Done and dropped tasks leave the lists (they stay notes), and so do archived ones.
        public var isOpen: Bool { !["done", "dropped"].contains(status ?? "") && archived != true }
    }

    public static func load(from url: URL) throws -> Fixture {
        var f = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        f.baseDir = url.deletingLastPathComponent().path
        if let name = f.focusDocument.markdownFile {
            let md = try String(contentsOf: url.deletingLastPathComponent().appending(path: name), encoding: .utf8)
            var body: [String: String] = [:]
            var current: String?
            for line in md.components(separatedBy: "\n") {
                if line.hasPrefix("## ") { current = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces); continue }
                if line.hasPrefix("# ") { current = nil; continue }
                if let c = current { body[c, default: ""] += (body[c] == nil ? "" : "\n") + line }
            }
            f.focusDocument.body = body.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return f
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

    /// The Dock badge (S3-6, DL-138): how many sessions need you, every project and Home counted,
    /// the one on screen too, the same list `duo2 needs-you` prints; nothing at 0 or when it's off.
    /// The Dock menu (ENH-24, DL-144): one item per waiting session, longest wait first, titled
    /// "session · project · wait"; past `limit`, how many more wait.
    public func dockMenuItems(limit: Int = 9) -> (items: [(title: String, session: Session)], more: Int) {
        let list = needsYou
        return (list.prefix(limit).map { ("\($0.name) · \($0.project) · \($0.wait ?? "now")", $0) }, max(0, list.count - limit))
    }

    public func dockBadgeLabel(enabled: Bool) -> String? {
        let n = needsYou.count
        return enabled && n > 0 ? "\(n)" : nil
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
        case "w": seconds = n * 7 * 86400   // a session from 2w ago is Earlier, not Today
        default: seconds = 0
        }
    }

    public static func < (a: WaitTime, b: WaitTime) -> Bool { a.seconds < b.seconds }
}
