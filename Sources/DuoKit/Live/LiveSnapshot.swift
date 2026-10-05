import DuoSearch
import Foundation

/// Builds the same snapshot the fixture provides from real sources (Phase E): projects found on
/// disk, each project's session index, and the beacons of live Claude sessions. The views don't
/// know which they are looking at.
public enum LiveSnapshot {
    public struct Context: Sendable {
        /// Home's folder, the container of its projects (DL-85); nil with no Home yet: every session
        /// is still listed, by folder (DL-82).
        public var root: URL?
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

        public init(root: URL?, rememberedHome: String? = nil, events: URL? = nil, seen: [String: Double] = [:]) {
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

    /// A group's sessions as threads: each fork family (linked by `forkOf`) is one thread, parent first.
    public static func threads(_ names: [String], in sessions: [Fixture.Session]) -> [[String]] {
        var left = names
        var out: [[String]] = []
        while let first = left.first {
            var family = [first]
            var grew = true
            while grew {
                grew = false
                for n in left where !family.contains(n) {
                    let s = sessions.first { $0.name == n }
                    if family.contains(where: { f in s?.forkOf == f || sessions.first { $0.name == f }?.forkOf == n }) { family.append(n); grew = true }
                }
            }
            // Parent first, then the sessions forked from it, breadth first.
            func parent(_ n: String) -> String? { sessions.first { $0.name == n }?.forkOf }
            var ordered = family.filter { parent($0).map { !family.contains($0) } ?? true }
            var i = 0
            while i < ordered.count {
                ordered += family.filter { parent($0) == ordered[i] && !ordered.contains($0) }
                i += 1
            }
            out.append(ordered + family.filter { !ordered.contains($0) })
            left.removeAll { family.contains($0) }
        }
        return out
    }

    public static func build(_ ctx: Context, beacons: [Beacon] = Beacon.readAll()) -> (Fixture, folders: [String: URL], moves: [Move]) {
        let resolve = { (p: String) in URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        // Claude's history, plus sessions only Duo's archive still has (Claude's cleanup removed the
        // transcript, DL-44): they stay listed by title and resume from the copy.
        let history = ctx.historyOverride ?? (ctx.includeHistory
            ? ClaudeStorage.history() + SessionArchive.purged().map { (id: $0.id, transcript: $0.copy, cwd: $0.cwd) } : [])
        let scanned = ctx.root.map { ProjectDiscovery.scanAll(root: $0) }
        var found = scanned?.projects ?? []
        let claudeFolders = scanned?.claudeFolders ?? []
        // Projects outside Home: made in Duo (DL-63), or any folder Claude ran in that has (or sits
        // inside) a PROJECT.md (DL-82).
        var outside = ctx.extraProjects
        for cwd in Set(history.map { resolve($0.cwd) } + beacons.map { resolve($0.cwd) }).sorted() {
            if let p = ProjectDiscovery.enclosingProject(URL(fileURLWithPath: cwd)) { outside.append(p) }
        }
        for folder in outside {
            let path = resolve(folder.path)
            guard !found.contains(where: { resolve($0.folder.path) == path }), let f = ProjectDiscovery.found(at: folder, root: ctx.root) else { continue }
            found.append(f)
        }
        let (home, _) = ProjectDiscovery.chooseHome(found, remembered: ctx.rememberedHome)
        // Other HOME.md folders appear as normal projects (DL-42).
        let projects: [ProjectDiscovery.Found] = found.map { f in
            guard f.isHomeCandidate, f.folder != home?.folder else { return f }
            var g = f
            g.project.isHome = nil
            g.project.topic = ProjectDiscovery.topic(for: f.folder, root: ctx.root)
            return g
        }
        var sessions: [Fixture.Session] = []
        var groups: [Fixture.Group] = []
        var files: [String: [String]] = [:]
        var folders: [String: URL] = [:]
        var claimed = Set<String>()
        var allTasks: [Fixture.TaskSummary] = []

        // Where each filed session actually is (F-32): a live session's cwd, else the project
        // whose folder its transcript is filed under. `/cd` moves both.
        let byPath = projects.map { (path: resolve($0.folder.path), found: $0) }
        let homePath = home.map { resolve($0.folder.path) }
        // The deepest project a folder is in. Home holds only what runs in its own folder (DL-85):
        // a folder inside Home without a project file is listed as a folder.
        func owner(ofPath p: String) -> ProjectDiscovery.Found? {
            byPath.filter { p == $0.path || ($0.path != homePath && p.hasPrefix($0.path + "/")) }.max { $0.path.count < $1.path.count }?.found
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

        func makeSession(_ id: String, project name: String, folder: URL, entry: SessionIndex.Entry?) -> Fixture.Session {
            let beacon = beacons.first { $0.sessionId == id }
            let hooks = ctx.events.flatMap { HookEvents.summarize(HookEvents.read(id, in: $0)) }
            let live = beacon.map { Attention.live(beacon: $0, hooks: hooks, seenAt: ctx.seen[id]) }
            let mtime = history.first { $0.id == id }.flatMap { try? $0.transcript.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            // Last activity: the transcript's change time when it's newer than the filing (a session
            // filed 44 minutes ago and used 2 minutes ago is 2m old).
            let since = live?.since ?? [entry?.createdAt, mtime].compactMap { $0 }.max().map { $0.timeIntervalSince1970 * 1000 }
            return Fixture.Session(
                name: title(id: id, folder: folder, beacon: beacon, started: entry?.createdAt),
                project: name,
                state: live?.state ?? .idle,
                wait: live?.state == .readyForReview ? nil : Attention.waitText(since: since, now: ctx.now),
                question: live?.question, options: live?.options,
                summary: live?.summary ?? entry?.note.map { e in entry?.next.map { "\(e) · Next: \($0)" } ?? e },
                forkOf: nil, document: nil,
                sessionId: id,
                reason: live?.state == .needsYou ? Self.reason(beacon: beacon, hooks: hooks) : nil)
        }

        // Where each session ran, last (after any /cd): a project that moved still has sessions
        // filed under its old path, which won't resume until they follow it (DB-8).
        let cwdOf = Dictionary(history.map { ($0.id, resolve($0.cwd)) }, uniquingKeysWith: { a, _ in a })
        var projectList = projects.map(\.project)
        for f in projects {
            let name = f.project.name
            folders[name] = f.folder
            let index = SessionIndex.load(project: f.folder)
            let folderPath = resolve(f.folder.path)
            // Sessions filed in the index, plus live sessions running in the folder (started
            // outside Duo: attributed by cwd, CONS FR-7.2.5).
            var ids = index.sessions.filter { $0.archived != true && actual[$0.sessionId]?.folder ?? f.folder == f.folder }.map(\.sessionId)
            for m in moves where m.to == f.folder && !ids.contains(m.sessionId) { ids.append(m.sessionId) }
            func inside(_ cwd: String) -> Bool { owner(ofPath: resolve(cwd))?.folder == f.folder }
            func filedElsewhere(_ id: String) -> Bool { filedIn[id].map { $0 != folderPath } ?? false }
            for b in beacons where inside(b.cwd) && !filedElsewhere(b.sessionId) {
                if !ids.contains(b.sessionId) { ids.append(b.sessionId) }
            }
            // Every past session in the folder (DL-59), newest first, not only those Duo filed.
            for h in history.sorted(by: { $0.transcript.path > $1.transcript.path }) where inside(h.cwd) && !filedElsewhere(h.id) {
                if !ids.contains(h.id) { ids.append(h.id) }
            }
            var stale: [String: Int] = [:]
            for id in ids where !claimed.contains(id) {
                claimed.insert(id)
                sessions.append(makeSession(id, project: name, folder: f.folder, entry: index.sessions.first { $0.sessionId == id }))
                if let cwd = cwdOf[id], cwd != folderPath, !cwd.hasPrefix(folderPath + "/"), !FileManager.default.fileExists(atPath: cwd) {
                    stale[cwd, default: 0] += 1
                }
            }
            if let (from, _) = stale.max(by: { $0.value < $1.value }), let i = projectList.firstIndex(where: { $0.name == name }) {
                projectList[i].movedFrom = from.replacingOccurrences(of: resolve(FileManager.default.homeDirectoryForCurrentUser.path), with: "~")
                projectList[i].staleSessions = stale.values.reduce(0, +)
            }
            // Tasks (DL-93): a note's `sessions:` links make its bundle, beside the groups (DL-88).
            for t in TaskNotes.load(project: f.folder) {
                allTasks.append(.init(project: name, path: t.path, title: t.title, status: t.status, sessionIds: t.sessionIds))
                let names = t.sessionIds.compactMap { id in sessions.first { $0.sessionId == id && $0.project == name }?.name }
                guard !names.isEmpty else { continue }
                groups.append(Fixture.Group(name: t.title, project: name, sessions: names, threads: names.map { [$0] }, task: t.path))
            }
            for g in index.groups {
                let names = g.sessions.compactMap { id in sessions.first { $0.sessionId == id }?.name }
                groups.append(Fixture.Group(name: g.name, project: name, sessions: names, threads: names.map { [$0] }))
            }
            files[name] = topLevelFiles(f.folder)
        }

        // Folders with Claude sessions or a CLAUDE.md that aren't projects (DL-63): shown in their own place,
        // marked, so they can stay as they are, become projects, or merge into one.
        var folderProjects: [Fixture.Project] = []
        var byFolder: [String: [String]] = [:]
        for h in history where !claimed.contains(h.id) && filedIn[h.id] == nil { byFolder[resolve(h.cwd), default: []].append(h.id) }
        for b in beacons where !claimed.contains(b.sessionId) && filedIn[b.sessionId] == nil {
            if !(byFolder[resolve(b.cwd)] ?? []).contains(b.sessionId) { byFolder[resolve(b.cwd), default: []].append(b.sessionId) }
        }
        // Claude folders in Home without sessions (DL-103): a CLAUDE.md is made with intent.
        for url in claudeFolders where owner(ofPath: resolve(url.path)) == nil { byFolder[resolve(url.path), default: []] += [] }
        let userHome = resolve(FileManager.default.homeDirectoryForCurrentUser.path)
        let forgotten = Set(DuoState.load().forgottenFolders)
        for (path, ids) in byFolder.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: path)
            // A folder that's gone keeps its tile, saying what happened (DB-8, LR-23), unless the
            // user removed it from Duo. Never the user's home folder or a system folder.
            let gone = !FileManager.default.fileExists(atPath: path)
            if gone && (forgotten.contains(path) || path == userHome || !path.hasPrefix("/Users/") && !path.hasPrefix("/Volumes/")) { continue }
            // Names are keys (`folders[name]`): add parent folders until the name is unique among
            // projects and other folders; two `payments/checkout`s once hid each other.
            let taken: (String) -> Bool = { n in projects.contains { $0.project.name == n } || folderProjects.contains { $0.name == n } }
            let parts = url.pathComponents.filter { $0 != "/" }
            var depth = 1
            var name = parts.suffix(depth).joined(separator: "/")
            while taken(name) && depth < parts.count { depth += 1; name = parts.suffix(depth).joined(separator: "/") }
            let topic = ProjectDiscovery.topic(for: url, root: ctx.root)
            var p = Fixture.Project(name: name, topic: topic, path: path.replacingOccurrences(of: userHome, with: "~"),
                                    isHome: nil, goal: "", health: nil, next: nil, kind: gone ? "missing" : "folder",
                                    hasClaudeMD: FileManager.default.fileExists(atPath: url.appending(path: "CLAUDE.md").path))
            if gone {
                // Only what still matters: found elsewhere, on a disk that's away, or used in the
                // last 14 days. Older deleted scratch folders stay out of the map (search keeps them).
                if url.pathComponents.contains(where: { $0.hasPrefix(".") }) { continue }
                let recent = ids.contains { id in
                    let t = history.first { $0.id == id }?.transcript
                    let m = t.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                    return (m?.timeIntervalSince(ctx.now) ?? -.infinity) > -14 * 86400
                }
                // Looking for where it went costs a walk of Home: only for recent ones.
                let status = recent ? MissingFolders.status(of: path, sessionIds: ids, searchIn: [ctx.root].compactMap { $0 })
                                    : MissingFolders.volumeStatus(of: path)
                if status == .notFound { if !recent { continue } }
                p.missing = status.text
                if case .movedTo(let to) = status { p.movedTo = to }
            }
            folderProjects.append(p)
            folders[name] = url
            for id in ids where !claimed.contains(id) {
                claimed.insert(id)
                sessions.append(makeSession(id, project: name, folder: url, entry: nil))
            }
        }

        // Threads (DL-24): a fork folds under the session it came from; a group lists its threads.
        if ctx.includeHistory || ctx.historyOverride != nil {
            let transcripts = Dictionary(history.map { ($0.id, $0.transcript) }, uniquingKeysWith: { a, _ in a })
            for project in Set(sessions.map(\.project)) {
                let members = sessions.filter { $0.project == project }.compactMap { s in s.sessionId.flatMap { id in transcripts[id].map { (id: id, transcript: $0) } } }
                guard members.count > 1 else { continue }
                for (child, parent) in ThreadCache.shared.parents(members) {
                    guard let ci = sessions.firstIndex(where: { $0.sessionId == child }),
                          let pname = sessions.first(where: { $0.sessionId == parent && $0.project == project })?.name else { continue }
                    sessions[ci].forkOf = pname
                }
            }
            groups = groups.map { g in
                var g = g
                g.threads = Self.threads(g.sessions, in: sessions.filter { $0.project == g.project })
                return g
            }
        }

        // Archived sessions (filing): out of every list and count, kept for their project's Archived fold.
        let archivedIDs = Set(DuoState.load().archivedSessions)
        let archived = sessions.filter { $0.sessionId.map(archivedIDs.contains) ?? false }
        sessions.removeAll { $0.sessionId.map(archivedIDs.contains) ?? false }
        groups = groups.map { g in var g = g; g.sessions.removeAll { n in archived.contains { $0.project == g.project && $0.name == n } }
                                g.threads = g.threads.map { $0.filter { n in !archived.contains { $0.project == g.project && $0.name == n } } }.filter { !$0.isEmpty }; return g }
            .filter { !$0.sessions.isEmpty }

        // Columns (DL-83): projects directly in Home first (unlabelled), Home's topic folders, then
        // the folders outside Home by path.
        var topics: [String] = []
        for p in projects where p.folder != home?.folder { if let t = p.project.topic, !topics.contains(t) { topics.append(t) } }
        for p in folderProjects { if let t = p.topic, !topics.contains(t) { topics.append(t) } }
        let isPath = { (t: String) in t.hasPrefix("~") || t.hasPrefix("/") }
        topics = topics.filter { $0.isEmpty } + topics.filter { !$0.isEmpty && !isPath($0) } + topics.filter(isPath).sorted()
        let live = sessions.filter { [.needsYou, .readyForReview, .working].contains($0.state) }
        let fixture = Fixture(
            now: ISO8601DateFormatter().string(from: ctx.now),
            user: NSFullUserName(),
            topics: topics,
            projects: projectList.map { p in
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
            projectFiles: files,
            archivedSessions: archived,
            tasks: allTasks
        )
        return (fixture, folders, moves)
    }

    /// LR-6: a name the user gave wins; then the transcript's ladder. A session with no
    /// transcript was never used, so it is a new session; Claude's derived names are unstable
    /// across processes (F-26) and aren't used.
    /// A session nothing has been typed in yet: its start time (DL-90), "Session 4:12 PM".
    public static func untitled(_ started: Date) -> String {
        Calendar.current.isDateInToday(started)
            ? "Session \(started.formatted(date: .omitted, time: .shortened))"
            : "Session \(started.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    static func title(id: String, folder: URL, beacon: Beacon?, started: Date? = nil) -> String {
        if let b = beacon, b.nameSource == "user", let n = b.name, !n.isEmpty { return n }
        guard let t = ClaudeStorage.transcript(sessionId: id, cwd: beacon?.cwd ?? folder.path) else {
            // Purged by Claude's cleanup but kept by Duo (DL-44): still has its title.
            let m = SessionArchive.manifest()
            return m.sessions[id]?.title ?? untitled(started ?? Date())
        }
        return SessionTitles.title(transcript: t) ?? "Session \(id.prefix(8))"
    }

    /// Why a session needs you, in the card's words (DL-100).
    static func reason(beacon: Beacon?, hooks: HookEvents.Summary?) -> String {
        if let q = hooks?.question, q.contains("ExitPlanMode") { return "plan to approve" }
        if hooks?.reason == .permission || beacon?.waitingFor == "permission prompt" { return "permission" }
        return "question"
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
