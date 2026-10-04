import DuoSearch
import Foundation

/// Builds the same snapshot the fixture provides from real sources (Phase E): projects found on
/// disk, each project's session index, and the beacons of live Claude sessions. The views don't
/// know which they are looking at.
public enum LiveSnapshot {
    public struct Context: Sendable {
        public var root: URL
        public var rememberedHome: String?
        public var now = Date()
        /// Hook events for sessions Duo started; nil reads none.
        public var events: URL?
        /// Duo's "seen" marks, epoch seconds by session id.
        public var seen: [String: Double]
        /// Read Claude's whole session history from disk (off in checks, which use their own files).
        public var includeHistory = true
        /// Projects made outside the workspace root (DL-63).
        public var extraProjects: [URL] = []
        /// Checks supply their own history.
        public var historyOverride: [(id: String, transcript: URL, cwd: String)]?

        public init(root: URL, rememberedHome: String? = nil, events: URL? = nil, seen: [String: Double] = [:]) {
            self.root = root
            self.rememberedHome = rememberedHome
            self.events = events
            self.seen = seen
        }
    }

    /// A filed session that now lives in another project (`/cd`, F-32): its index entry moves.
    public struct Move: Sendable, Equatable {
        public var sessionId: String
        public var from: URL
        public var to: URL
    }

    public static func build(_ ctx: Context, beacons: [Beacon] = Beacon.readAll()) -> (Fixture, folders: [String: URL], moves: [Move]) {
        let found = ProjectDiscovery.scan(root: ctx.root) + ctx.extraProjects.compactMap { ProjectDiscovery.found(at: $0, root: ctx.root) }
        let (home, _) = ProjectDiscovery.chooseHome(found, remembered: ctx.rememberedHome)
        // Other HOME.md folders appear as normal projects (DL-42).
        let projects: [ProjectDiscovery.Found] = found.map { f in
            guard f.isHomeCandidate, f.folder != home?.folder else { return f }
            var g = f
            g.project.isHome = nil
            g.project.topic = nil
            return g
        }
        let resolve = { (p: String) in URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        var sessions: [Fixture.Session] = []
        var groups: [Fixture.Group] = []
        var files: [String: [String]] = [:]
        var folders: [String: URL] = [:]
        var claimed = Set<String>()

        // Where each filed session actually is (F-32): a live session's cwd, else the project
        // whose folder its transcript is filed under. `/cd` moves both.
        let byPath = projects.map { (path: resolve($0.folder.path), found: $0) }
        func owner(ofPath p: String) -> ProjectDiscovery.Found? {
            byPath.filter { p == $0.path || p.hasPrefix($0.path + "/") }.max { $0.path.count < $1.path.count }?.found
        }
        let byEncoded = Dictionary(byPath.map { (ClaudeStorage.encode($0.path), $0.found) }, uniquingKeysWith: { a, _ in a })
        var actual: [String: ProjectDiscovery.Found] = [:]   // session id → project
        var moves: [Move] = []
        for f in projects {
            for e in SessionIndex.load(project: f.folder).sessions where e.archived != true {
                let live = beacons.first { $0.sessionId == e.sessionId }.flatMap { owner(ofPath: resolve($0.cwd)) }
                let filed = live == nil
                    ? ClaudeStorage.transcript(sessionId: e.sessionId, cwd: f.folder.path).flatMap { byEncoded[$0.deletingLastPathComponent().lastPathComponent] }
                    : nil
                // A session the user moved stays where they filed it (DL-64), whatever its cwd.
                let here = e.provenance.hasPrefix("moved-by-user") ? f : (live ?? filed ?? f)
                actual[e.sessionId] = here
                if here.folder != f.folder { moves.append(Move(sessionId: e.sessionId, from: f.folder, to: here.folder)) }
            }
        }

        // Every session filed anywhere, and where: cwd-based attribution never steals them.
        var filedIn: [String: String] = [:]   // id → resolved folder path
        for (id, f) in actual { filedIn[id] = resolve(f.folder.path) }
        // Claude's history, plus sessions only Duo's archive still has (Claude's cleanup removed the
        // transcript, DL-44): they stay listed by title and resume from the copy.
        let history = ctx.historyOverride ?? (ctx.includeHistory
            ? ClaudeStorage.history() + SessionArchive.purged().map { (id: $0.id, transcript: $0.copy, cwd: $0.cwd) } : [])

        func makeSession(_ id: String, project name: String, folder: URL, entry: SessionIndex.Entry?) -> Fixture.Session {
            let beacon = beacons.first { $0.sessionId == id }
            let hooks = ctx.events.flatMap { HookEvents.summarize(HookEvents.read(id, in: $0)) }
            let live = beacon.map { Attention.live(beacon: $0, hooks: hooks, seenAt: ctx.seen[id]) }
            let mtime = history.first { $0.id == id }.flatMap { try? $0.transcript.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            // Last activity: the transcript's change time when it's newer than the filing (a session
            // filed 44 minutes ago and used 2 minutes ago is 2m old).
            let since = live?.since ?? [entry?.createdAt, mtime].compactMap { $0 }.max().map { $0.timeIntervalSince1970 * 1000 }
            return Fixture.Session(
                name: title(id: id, folder: folder, beacon: beacon),
                project: name,
                state: live?.state ?? .idle,
                wait: live?.state == .readyForReview ? nil : Attention.waitText(since: since, now: ctx.now),
                question: live?.question, options: live?.options,
                summary: live?.summary ?? entry?.note.map { e in entry?.next.map { "\(e) · Next: \($0)" } ?? e },
                forkOf: nil, document: nil,
                sessionId: id)
        }

        for f in projects {
            let name = f.project.name
            folders[name] = f.folder
            let index = SessionIndex.load(project: f.folder)
            let folderPath = resolve(f.folder.path)
            // Sessions filed in the index, plus live sessions running in the folder (started
            // outside Duo: attributed by cwd, CONS FR-7.2.5).
            var ids = index.sessions.filter { $0.archived != true && actual[$0.sessionId]?.folder ?? f.folder == f.folder }.map(\.sessionId)
            for m in moves where m.to == f.folder && !ids.contains(m.sessionId) { ids.append(m.sessionId) }
            func inside(_ cwd: String) -> Bool { let c = resolve(cwd); return c == folderPath || c.hasPrefix(folderPath + "/") }
            func filedElsewhere(_ id: String) -> Bool { filedIn[id].map { $0 != folderPath } ?? false }
            for b in beacons where inside(b.cwd) && !filedElsewhere(b.sessionId) {
                if !ids.contains(b.sessionId) { ids.append(b.sessionId) }
            }
            // Every past session in the folder (DL-59), newest first, not only those Duo filed.
            for h in history.sorted(by: { $0.transcript.path > $1.transcript.path }) where inside(h.cwd) && !filedElsewhere(h.id) {
                if !ids.contains(h.id) { ids.append(h.id) }
            }
            for id in ids where !claimed.contains(id) {
                claimed.insert(id)
                sessions.append(makeSession(id, project: name, folder: f.folder, entry: index.sessions.first { $0.sessionId == id }))
            }
            for g in index.groups {
                let names = g.sessions.compactMap { id in sessions.first { $0.sessionId == id }?.name }
                groups.append(Fixture.Group(name: g.name, project: name, sessions: names, threads: names.map { [$0] }))
            }
            files[name] = topLevelFiles(f.folder)
        }

        // Folders with Claude sessions that aren't projects (DL-63): shown in their own place,
        // marked, so they can stay as they are, become projects, or merge into one.
        var folderProjects: [Fixture.Project] = []
        let rootPath = resolve(ctx.root.path)
        var byFolder: [String: [String]] = [:]
        for h in history where !claimed.contains(h.id) && filedIn[h.id] == nil { byFolder[resolve(h.cwd), default: []].append(h.id) }
        for b in beacons where !claimed.contains(b.sessionId) && filedIn[b.sessionId] == nil {
            if !(byFolder[resolve(b.cwd)] ?? []).contains(b.sessionId) { byFolder[resolve(b.cwd), default: []].append(b.sessionId) }
        }
        let homePath = resolve(FileManager.default.homeDirectoryForCurrentUser.path)
        for (path, ids) in byFolder.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { continue }  // folder deleted: archive only
            // Names are keys (`folders[name]`): add parent folders until the name is unique among
            // projects and other folders; two `payments/checkout`s once hid each other.
            let taken: (String) -> Bool = { n in projects.contains { $0.project.name == n } || folderProjects.contains { $0.name == n } }
            let parts = url.pathComponents.filter { $0 != "/" }
            var depth = 1
            var name = parts.suffix(depth).joined(separator: "/")
            while taken(name) && depth < parts.count { depth += 1; name = parts.suffix(depth).joined(separator: "/") }
            let underRoot = path.hasPrefix(rootPath + "/")
            let parent = url.deletingLastPathComponent().path
            let topic = underRoot && parent != rootPath ? url.deletingLastPathComponent().lastPathComponent.capitalized : "Elsewhere"
            folderProjects.append(Fixture.Project(name: name, topic: topic, path: path.replacingOccurrences(of: homePath, with: "~"),
                                                  isHome: nil, goal: "", health: nil, next: nil, kind: "folder",
                                                  hasClaudeMD: FileManager.default.fileExists(atPath: url.appending(path: "CLAUDE.md").path)))
            folders[name] = url
            for id in ids where !claimed.contains(id) {
                claimed.insert(id)
                sessions.append(makeSession(id, project: name, folder: url, entry: nil))
            }
        }

        var topics: [String] = []
        for p in projects { if let t = p.project.topic, !topics.contains(t) { topics.append(t) } }
        for p in folderProjects { if let t = p.topic, !topics.contains(t) { topics.append(t) } }
        let live = sessions.filter { [.needsYou, .readyForReview, .working].contains($0.state) }
        let fixture = Fixture(
            now: ISO8601DateFormatter().string(from: ctx.now),
            user: NSFullUserName(),
            topics: topics,
            projects: projects.map(\.project).map { p in
                var p = p
                if let h = home, p.name == h.project.name { p.isHome = true; p.topic = nil }
                return p
            } + folderProjects,
            sessions: sessions,
            otherIdleSessions: 0,
            groups: groups,
            counts: .init(needsYou: live.filter { $0.state == .needsYou }.count,
                          readyForReview: live.filter { $0.state == .readyForReview }.count,
                          working: live.filter { $0.state == .working }.count,
                          // Resumable means not running: an open, quiet session isn't counted (C-16).
                          idle: sessions.filter { s in s.state == .idle && !beacons.contains { $0.sessionId == s.sessionId } }.count),
            homeInbox: [],
            focusDocument: .init(project: "", path: "", sections: [], addedByClaude: []),
            projectFiles: files
        )
        return (fixture, folders, moves)
    }

    /// LR-6: a name the user gave wins; then the transcript's ladder. A session with no
    /// transcript was never used, so it is a new session; Claude's derived names are unstable
    /// across processes (F-26) and aren't used.
    static func title(id: String, folder: URL, beacon: Beacon?) -> String {
        if let b = beacon, b.nameSource == "user", let n = b.name, !n.isEmpty { return n }
        guard let t = ClaudeStorage.transcript(sessionId: id, cwd: beacon?.cwd ?? folder.path) else {
            // Purged by Claude's cleanup but kept by Duo (DL-44): still has its title.
            let m = SessionArchive.manifest()
            return m.sessions[id]?.title ?? "New session"
        }
        return SessionTitles.title(transcript: t) ?? "Session \(id.prefix(8))"
    }

    /// Nothing found yet: the state before the first scan completes.
    public static func empty() -> Fixture {
        Fixture(now: ISO8601DateFormatter().string(from: Date()), user: NSFullUserName(), topics: [], projects: [],
                sessions: [], otherIdleSessions: 0, groups: [],
                counts: .init(needsYou: 0, readyForReview: 0, working: 0, idle: 0), homeInbox: [],
                focusDocument: .init(project: "", path: "", sections: [], addedByClaude: []), projectFiles: [:])
    }

    /// Markdown and text files near the top of a project, for the file tree (fixture-shaped).
    static func topLevelFiles(_ folder: URL) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let u as URL in e {
            let rel = u.path.replacingOccurrences(of: folder.path + "/", with: "")
            if rel.split(separator: "/").count > 3 { e.skipDescendants(); continue }
            if ["node_modules", ".build", "build"].contains(u.lastPathComponent) || ProtectedFolders.skip(u, root: folder) { e.skipDescendants(); continue }
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { out.append(rel) }
            else if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { out.append(rel + "/") }
            if out.count >= 200 { break }
        }
        return out.sorted()
    }
}
