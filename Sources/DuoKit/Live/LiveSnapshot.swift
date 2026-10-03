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

        public init(root: URL, rememberedHome: String? = nil, events: URL? = nil, seen: [String: Double] = [:]) {
            self.root = root
            self.rememberedHome = rememberedHome
            self.events = events
            self.seen = seen
        }
    }

    public static func build(_ ctx: Context, beacons: [Beacon] = Beacon.readAll()) -> (Fixture, folders: [String: URL]) {
        let found = ProjectDiscovery.scan(root: ctx.root)
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

        for f in projects {
            let name = f.project.name
            folders[name] = f.folder
            let index = SessionIndex.load(project: f.folder)
            let folderPath = resolve(f.folder.path)
            // Sessions filed in the index, plus live sessions running in the folder (started
            // outside Duo: attributed by cwd, CONS FR-7.2.5).
            var ids = index.sessions.filter { $0.archived != true }.map(\.sessionId)
            for b in beacons where resolve(b.cwd) == folderPath || resolve(b.cwd).hasPrefix(folderPath + "/") {
                if !ids.contains(b.sessionId) { ids.append(b.sessionId) }
            }
            for id in ids where !claimed.contains(id) {
                claimed.insert(id)
                let beacon = beacons.first { $0.sessionId == id }
                let entry = index.sessions.first { $0.sessionId == id }
                let created = entry?.createdAt
                let hooks = ctx.events.flatMap { HookEvents.summarize(HookEvents.read(id, in: $0)) }
                let live = beacon.map { Attention.live(beacon: $0, hooks: hooks, seenAt: ctx.seen[id]) }
                let since = live?.since ?? created.map { $0.timeIntervalSince1970 * 1000 }
                sessions.append(Fixture.Session(
                    name: title(id: id, folder: f.folder, beacon: beacon),
                    project: name,
                    state: live?.state ?? .idle,
                    wait: live?.state == .readyForReview ? nil : Attention.waitText(since: since, now: ctx.now),
                    question: live?.question, options: live?.options,
                    summary: live?.summary ?? entry?.note.map { e in entry?.next.map { "\(e) · Next: \($0)" } ?? e },
                    forkOf: nil, document: nil,
                    sessionId: id
                ))
            }
            for g in index.groups {
                let names = g.sessions.compactMap { id in sessions.first { $0.sessionId == id }?.name }
                groups.append(Fixture.Group(name: g.name, project: name, sessions: names, threads: names.map { [$0] }))
            }
            files[name] = topLevelFiles(f.folder)
        }

        var topics: [String] = []
        for p in projects { if let t = p.project.topic, !topics.contains(t) { topics.append(t) } }
        let live = sessions.filter { [.needsYou, .readyForReview, .working].contains($0.state) }
        let fixture = Fixture(
            now: ISO8601DateFormatter().string(from: ctx.now),
            user: NSFullUserName(),
            topics: topics,
            projects: projects.map(\.project).map { p in
                var p = p
                if let h = home, p.name == h.project.name { p.isHome = true; p.topic = nil }
                return p
            },
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
        return (fixture, folders)
    }

    /// LR-6: a name the user gave wins; then the transcript's ladder. A session with no
    /// transcript was never used, so it is a new session; Claude's derived names are unstable
    /// across processes (F-26) and aren't used.
    static func title(id: String, folder: URL, beacon: Beacon?) -> String {
        if let b = beacon, b.nameSource == "user", let n = b.name, !n.isEmpty { return n }
        guard let t = ClaudeStorage.transcript(sessionId: id, cwd: beacon?.cwd ?? folder.path) else { return "New session" }
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
            if ["node_modules", ".build", "build"].contains(u.lastPathComponent) { e.skipDescendants(); continue }
            if (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { out.append(rel) }
            if out.count >= 200 { break }
        }
        return out.sorted()
    }
}
