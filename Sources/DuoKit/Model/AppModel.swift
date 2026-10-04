import Foundation
import Observation

/// The two altitudes (handoff §2.3).
public enum Altitude: Equatable, Sendable {
    case allProjects
    case project(String)

    public var isAllProjects: Bool { self == .allProjects }
}

/// Whether panes host real terminals. Fixture captures keep them off: terminal content is
/// exempt from comparison (handoff §0.4) and isn't capturable without Screen Recording (F-17).
public enum TerminalsMode: Sendable, Equatable {
    case off
    /// Real `claude` sessions in scratch folders under `root`, one per fixture project.
    case demo(root: String)
    /// Real projects and sessions (Phase E): terminals resume sessions by id (DL-14).
    case live
}

/// Window-level UI state. One instance per window; views read it from the environment.
@MainActor
@Observable
public final class AppModel {
    public var fixture: Fixture
    public var altitude: Altitude = .allProjects

    /// The left pane is collapsed independently at each altitude (handoff §3.1).
    public var leftCollapsedAllProjects = false
    public var leftCollapsedProject = false

    // All projects
    public var selectedActionSession: String?   // Session.id
    public var focusedTile: String?             // Project.name
    public var homeTab: String?                 // Session.name

    // Inside a project
    public var selectedSidebarItem: String?     // group name or Session.id
    public var expandedGroups: Set<String> = []
    public var consoleTab: String?              // Session.tabKey (id when live, else name)
    public var rightTab: String?                // "Project", a group name, or a document path
    public var selectedFile: String?            // path relative to the project
    /// Open document tabs by project (DL-60): switching to Project no longer closes them.
    public var openDocumentsByProject: [String: [String]] = [:]
    /// The file or folder being named inline in the tree (DL-62).
    public var renamingPath: String?

    public var peekOpen = false
    /// The selected card in the peek, by Session.id.
    public var peekSelection: String?
    /// The session last opened inside a project; selected again on zooming out (flow-zoom-4).
    public var lastVisitedSession: String?
    /// Asks the Home terminal to take keyboard focus (consumed by the Home pane).
    public var focusHomeRequest = 0

    public var terminalsMode: TerminalsMode = .off
    @ObservationIgnored public let terminals = TerminalStore()
    /// The one document editor (live mode; fixture mode keeps the placeholder the targets exempt).
    @ObservationIgnored public lazy var editor: EditorController = { let e = EditorController(); editorIfLoaded = e; return e }()
    /// The editor if it has been created (doc-status mustn't create one).
    @ObservationIgnored public var editorIfLoaded: EditorController?

    /// A project-relative path as a real file, in live mode.
    public func liveFile(_ path: String) -> URL? {
        guard terminalsMode == .live, let project = currentProject?.name, let folder = liveFolders[project] else { return nil }
        let url = folder.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The terminal for a session, created on first use; nil when terminals are off, or when the
    /// session is running somewhere else (never two writers, LR-8).
    public func terminal(project: String, session key: String) -> TerminalSession? {
        switch terminalsMode {
        case .off:
            return nil
        case .demo(let root):
            return terminals.session("\(project)/\(key)", command: .newClaude(sessionID: UUID().uuidString.lowercased(), prompt: nil),
                                     cwd: (root as NSString).appendingPathComponent(project))
        case .live:
            if let mine = terminals.existing(key) { return mine }
            guard let s = fixture.sessions(inProject: project).first(where: { $0.tabKey == key }),
                  let id = s.sessionId, let folder = liveFolders[project] else { return nil }
            if liveElsewhere.contains(id) { return nil }  // shown as running elsewhere
            // A transcript Claude's cleanup removed comes back from Duo's archive first (DL-44).
            if ClaudeStorage.transcript(sessionId: id, cwd: folder.path) == nil { _ = try? SessionArchive.restore(id) }
            let transcript = ClaudeStorage.transcript(sessionId: id, cwd: folder.path)
            // A session moved here from another folder (DL-64) resumes where it was, then /cd moves
            // it (and its transcript) to this folder, as Claude does itself. /cd to the folder it's
            // already in moves nothing (F-45), hence starting in the old one.
            let filed = transcript.flatMap(ClaudeStorage.filedCwd).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
            let movedHere = filed.map { $0 != folder.resolvingSymlinksInPath().path && FileManager.default.fileExists(atPath: $0) } ?? false
            let t = terminals.session(key, command: transcript != nil ? .resumeClaude(sessionID: id) : .newClaude(sessionID: id, prompt: nil),
                                      cwd: movedHere ? filed! : folder.path)
            if movedHere { relocate(t, to: folder) }
            return t
        }
    }

    /// A pane's session tabs: live sessions, plus any Duo holds a terminal for. A Claude process
    /// sitting at its prompt reports `idle`, but it is open, so it keeps its tab (findings F-25).
    public func tabSessions(inProject project: String) -> [Fixture.Session] {
        fixture.sessions(inProject: project).filter {
            [.needsYou, .readyForReview, .working].contains($0.state) || terminals.existing($0.tabKey) != nil
        }
    }

    // MARK: - Live workspace (Phase E)

    @ObservationIgnored public var liveRoot: URL?
    @ObservationIgnored public var liveFolders: [String: URL] = [:]
    /// Live sessions whose process Duo doesn't own (Terminal, the Desktop app, another Duo).
    public var liveElsewhere: Set<String> = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var lastArchive = Date.distantPast
    /// False for scripted captures: nothing may block on a prompt.
    @ObservationIgnored public var interactivePrompts = true
    /// Duo's "seen" marks (handoff §10): looking at a session clears ready-for-review.
    @ObservationIgnored public var seen: [String: Double] = [:]
    @ObservationIgnored public var rememberedHome: String?
    /// Projects outside the workspace root (DL-63), from Duo's state.
    @ObservationIgnored public var extraProjects: [URL] = []

    public var visibleTerminal: TerminalSession? { visibleSessionId.flatMap { terminals.existing($0) } }

    /// The session whose terminal is on screen now.
    var visibleSessionId: String? {
        switch altitude {
        case .allProjects: return homeTab
        case .project: return consoleTab
        }
    }

    /// Switches to real projects under `root`, refreshing every 2 s from disk and beacons.
    public func startLive(root: URL) {
        liveRoot = root
        terminalsMode = .live
        let state = DuoState.load()
        seen = state.seen
        rememberedHome = state.home
        extraProjects = state.projects.map { URL(fileURLWithPath: $0) }
        fixture = LiveSnapshot.empty()  // never show the design fixture while the first scan runs
        refreshLive()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLive() }
        }
    }

    /// Rebuilds the snapshot off the main thread, one refresh at a time: disk reads can block
    /// (a privacy prompt for ~/Documents, a slow network volume) and must never freeze the UI (F-28).
    public func refreshLive() {
        guard let root = liveRoot, !refreshing else { return }
        refreshing = true
        if let id = visibleSessionId, fixture.sessions.contains(where: { $0.sessionId == id && $0.state == .readyForReview }) {
            seen[id] = Date().timeIntervalSince1970
            DuoState.update { $0.seen[id] = seen[id] }
        }
        var ctx = LiveSnapshot.Context(root: root, rememberedHome: rememberedHome, events: DuoPaths.events, seen: seen)
        ctx.extraProjects = extraProjects
        Task.detached(priority: .utility) { [weak self] in
            let beacons = Beacon.readAll()
            let (snapshot, folders, moves) = LiveSnapshot.build(ctx, beacons: beacons)
            // Follow `/cd`: move the index entry to the project the session now lives in (F-32).
            for m in moves {
                var from = SessionIndex.load(project: m.from), to = SessionIndex.load(project: m.to)
                guard let i = from.sessions.firstIndex(where: { $0.sessionId == m.sessionId }) else { continue }
                var entry = from.sessions.remove(at: i)
                if !to.sessions.contains(where: { $0.sessionId == m.sessionId }) {
                    entry.provenance = "relocated-from:\(m.from.lastPathComponent)"
                    to.sessions.append(entry)
                    try? to.save(project: m.to)
                }
                try? from.save(project: m.from)
            }
            await self?.apply(snapshot, folders: folders, beacons: beacons)
        }
    }

    private func apply(_ snapshot: Fixture, folders: [String: URL], beacons: [Beacon]) {
        refreshing = false
        // Sessions Duo started but Claude hasn't written a beacon for yet keep their tab.
        var merged = snapshot
        for s in fixture.sessions where s.sessionId != nil && terminals.existing(s.tabKey) != nil
            && !merged.sessions.contains(where: { $0.sessionId == s.sessionId }) {
            merged.sessions.append(s)
        }
        liveFolders = folders
        followSessionChanges(beacons)
        SearchService.shared.update(projects: folders)
        if let home = snapshot.home, let folder = folders[home.name]?.path, folder != rememberedHome {
            // First choice, or the remembered one is gone: remember what is in use now (DL-42).
            rememberedHome = folder
            DuoState.update { $0.home = folder }
        }
        let mine = Set(terminals.all.compactMap { t -> Int32? in t.view.process?.shellPid })
        liveElsewhere = Set(beacons.filter { !mine.contains($0.pid) }.map(\.sessionId))
        // One row per session id, whatever the sources disagree on (seen once, F-29).
        var ids = Set<String>()
        merged.sessions = merged.sessions.filter { s in s.sessionId.map { ids.insert($0).inserted } ?? true }
        if merged != fixture { fixture = merged }
        archiveListedSessions()  // after the snapshot is applied: it archives what's listed now
        GitIgnoreOffer.consider(folders, interactive: interactivePrompts)
        // Home is always on (brief: the director agent); its empty state isn't designed (§13), so
        // live mode starts one Home session when there is none (concerns C-15).
        if let home = fixture.home {
            let homeSessions = fixture.sessions(inProject: home.name)
            if homeSessions.isEmpty { newSession(in: home.name) }
            if homeTab == nil || !fixture.sessions(inProject: home.name).contains(where: { $0.tabKey == homeTab }) {
                homeTab = fixture.sessions(inProject: home.name).first?.tabKey
            }
        }
    }

    /// Keeps Duo's copy of every listed session's transcript (DL-44), at most once a minute, off
    /// the main thread.
    private func archiveListedSessions() {
        guard Date().timeIntervalSince(lastArchive) > 60 else { return }
        lastArchive = Date()
        let listed: [(String, String)] = fixture.sessions.compactMap { s in
            guard let id = s.sessionId, let folder = liveFolders[s.project] else { return nil }
            return (id, folder.path)
        }
        Task.detached(priority: .utility) {
            let found = listed.compactMap { id, cwd in ClaudeStorage.transcript(sessionId: id, cwd: cwd).map { (id: id, transcript: $0) } }
            do {
                let n = try SessionArchive.sync(found)
                if n > 0 { FileHandle.standardError.write(Data("archive: copied \(n) of \(found.count) listed transcripts\n".utf8)) }
            } catch {
                FileHandle.standardError.write(Data("archive: \(error)\n".utf8))
            }
            // DL-47: keep listed sessions out of Claude's cleanup as well as archiving them.
            if let days = SessionArchive.cleanupPeriodDays() { SessionArchive.keepAlive(found.map(\.transcript), periodDays: days) }
        }
    }

    /// Types `/cd <folder>` into a resumed session once Claude reports its prompt idle (its beacon,
    /// F-23). A trust dialog comes before the session starts, so it can't receive the keystrokes.
    /// Gives up after 20 s: the session still works, just stays filed under its old folder in Claude.
    func relocate(_ t: TerminalSession, to folder: URL, tries: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !t.exited, let pid = t.view.process?.shellPid else { return }
                let ready = Beacon.readAll().contains { $0.pid == pid && $0.status == "idle" }
                if ready {
                    // Text and Return as separate keystrokes: sent in one burst, Claude Code treats
                    // it as a paste and the Return doesn't submit (F-45).
                    t.view.send(txt: "/cd \(folder.path)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { t.view.send(txt: "\r") }
                    FileHandle.standardError.write(Data("relocate: sent /cd \(folder.path)\n".utf8))
                } else if tries < 40 {
                    self.relocate(t, to: folder, tries: tries + 1)
                } else {
                    FileHandle.standardError.write(Data("relocate: prompt not ready; skipped\n".utf8))
                }
            }
        }
    }

    /// `/clear` or `/resume` inside a Duo terminal starts or opens another session in the same
    /// process. File the new id where the old one was, and move the tab with it (F-29).
    private func followSessionChanges(_ beacons: [Beacon]) {
        for t in terminals.all {
            guard let pid = t.view.process?.shellPid, let b = beacons.first(where: { $0.pid == pid }),
                  b.sessionId != t.key, let old = fixture.sessions.first(where: { $0.tabKey == t.key }),
                  let folder = liveFolders[old.project] else { continue }
            var index = SessionIndex.load(project: folder)
            if !index.sessions.contains(where: { $0.sessionId == b.sessionId }) {
                index.sessions.append(.init(sessionId: b.sessionId, provenance: "continued-from:\(t.key)"))
                try? index.save(project: folder)
            }
            if consoleTab == t.key { consoleTab = b.sessionId }
            if homeTab == t.key { homeTab = b.sessionId }
            terminals.rekey(t.key, to: b.sessionId)
        }
    }

    /// ⌘W: ends the visible session's process. The session stays filed and resumable; its tab
    /// goes unless the session is still in a live state, and the next tab is selected.
    public func closeVisibleSession() {
        guard let key = visibleSessionId, terminals.existing(key) != nil else { return }
        let project: String? = altitude.isAllProjects ? fixture.home?.name : currentProject?.name
        terminals.close(key)
        let next = project.map { tabSessions(inProject: $0).first { $0.tabKey != key }?.tabKey } ?? nil
        if altitude.isAllProjects { homeTab = next } else { consoleTab = next }
        fixture = fixture  // republish: tabs depend on which terminals exist
    }

    /// LR-5: agent self-narration, stored Duo-side in the project's index and shown verbatim.
    func setNarration(_ id: String, kind: String, text: String) -> Bool {
        guard let s = fixture.sessions.first(where: { $0.sessionId == id }), let folder = liveFolders[s.project] else { return false }
        var index = SessionIndex.load(project: folder)
        if !index.sessions.contains(where: { $0.sessionId == id }) {
            index.sessions.append(.init(sessionId: id, provenance: "attributed-by-cwd"))  // it spoke to Duo: file it
        }
        guard let i = index.sessions.firstIndex(where: { $0.sessionId == id }) else { return false }
        if kind == "note" { index.sessions[i].note = text } else { index.sessions[i].next = text }
        try? index.save(project: folder)
        refreshLive()
        return true
    }

    /// `+ New session` (handoff §6.2): a new Claude Code session in the current project's folder,
    /// with a Duo-minted id recorded in the project's session index first (CONS FR-7.7.7).
    public func newSession() {
        guard let project = currentProject?.name else { return }
        newSession(in: project)
        consoleTab = fixture.sessions.last?.tabKey
    }

    @discardableResult
    public func newSession(in project: String, prompt: String? = nil, provenance: String = "created-by-duo") -> String? {
        guard terminalsMode == .live, let folder = liveFolders[project] else { return nil }
        let id = UUID().uuidString.lowercased()
        var index = SessionIndex.load(project: folder)
        index.sessions.append(.init(sessionId: id, provenance: provenance))
        try? index.save(project: folder)
        _ = terminals.session(id, command: .newClaude(sessionID: id, prompt: prompt), cwd: folder.path)
        fixture.sessions.append(Fixture.Session(name: "New session", project: project, state: .working, wait: "now",
                                                question: nil, options: nil, summary: nil, forkOf: nil, document: nil,
                                                sessionId: id))
        return id
    }

    /// Carries an archived session into a new one in the same project (Q-19, Geoff's idea).
    public func carryOn(_ oldId: String) -> String? {
        guard let s = fixture.sessions.first(where: { $0.sessionId == oldId }), let prompt = SessionArchive.carryOnPrompt(oldId) else { return nil }
        guard let id = newSession(in: s.project, prompt: prompt, provenance: "carried-on-from:\(oldId)") else { return nil }
        open(project: s.project)
        consoleTab = id
        return id
    }

    public init(fixture: Fixture) {
        self.fixture = fixture
    }

    public var leftCollapsed: Bool {
        get { altitude.isAllProjects ? leftCollapsedAllProjects : leftCollapsedProject }
        set {
            if altitude.isAllProjects { leftCollapsedAllProjects = newValue } else { leftCollapsedProject = newValue }
        }
    }

    public var currentProject: Fixture.Project? {
        guard case .project(let name) = altitude else { return nil }
        return fixture.projects.first { $0.name == name }
    }

    // MARK: - Navigation (handoff §6.1, §6.2)

    /// Zooms into a project. With no session given, the console opens on the session that needs
    /// you (or the most recent live one) and the right pane on the document it is editing [P].
    public func open(project name: String, session sessionName: String? = nil, document: String? = nil) {
        let live = fixture.liveSessions(inProject: name)
        let target = sessionName.flatMap { n in fixture.sessions(inProject: name).first { $0.name == n } }
            ?? SidebarRow.mostUrgent(live)
        altitude = .project(name)
        peekOpen = false
        consoleTab = target?.tabKey
        if let target { lastVisitedSession = target.id }
        if let target, let group = fixture.groups.first(where: { g in g.project == name && g.sessions.contains(target.name) }) {
            selectedSidebarItem = group.name
            expandedGroups.insert(group.name)
        } else {
            selectedSidebarItem = target?.id
        }
        if let doc = document ?? target?.document {
            if !(openDocumentsByProject[name] ?? []).contains(doc) { openDocumentsByProject[name, default: []].append(doc) }
            rightTab = doc
            selectedFile = doc
        } else {
            rightTab = "Project"
            selectedFile = nil
        }
    }

    /// Back to All projects; the session last opened is the selected row (flow-zoom-4).
    public func zoomOut() {
        altitude = .allProjects
        peekOpen = false
        if let last = lastVisitedSession { selectedActionSession = last }
        focusedTile = nil
    }

    /// `⇧⌘H`: All projects with the Home terminal focused.
    public func goHome() {
        zoomOut()
        if let s = fixture.needsYou.first(where: { $0.project == fixture.home?.name }) { homeTab = s.tabKey }
        focusHomeRequest += 1
    }

    /// `⌘↩` in the peek: jump into the selected card's project, on that session.
    public func jumpToPeekSelection() {
        guard let id = peekSelection, let s = needsYouElsewhere.first(where: { $0.id == id }) else { return }
        if s.project == fixture.home?.name { goHome() } else { open(project: s.project, session: s.name) }
    }

    /// Opens or focuses a session's console tab inside the current project. Liveness is
    /// re-checked here once sessions are real (LR-8).
    public func openConsoleTab(_ key: String) {
        guard let project = currentProject?.name,
              let s = fixture.sessions(inProject: project).first(where: { $0.tabKey == key || $0.name == key }) else { return }
        consoleTab = s.tabKey
        lastVisitedSession = s.id
    }

    public func togglePeek() {
        peekOpen.toggle()
        if peekOpen { peekSelection = needsYouElsewhere.first?.id }
    }

    /// `↑` / `↓` in the peek.
    public func movePeekSelection(by delta: Int) {
        let ids = needsYouElsewhere.map(\.id)
        guard !ids.isEmpty else { return }
        let i = peekSelection.flatMap { ids.firstIndex(of: $0) } ?? 0
        peekSelection = ids[max(0, min(ids.count - 1, i + delta))]
    }

    /// Arrow keys between tiles on the map: columns are topics, rows are tiles.
    public func moveTileFocus(dx: Int, dy: Int) {
        let columns = fixture.topics.map { fixture.projects(inTopic: $0).map(\.name) }
        guard let current = focusedTile,
              let c = columns.firstIndex(where: { $0.contains(current) }),
              let r = columns[c].firstIndex(of: current) else {
            focusedTile = columns.first?.first
            return
        }
        let nc = max(0, min(columns.count - 1, c + dx))
        guard !columns[nc].isEmpty else { return }
        let nr = dx != 0 ? min(r, columns[nc].count - 1) : max(0, min(columns[nc].count - 1, r + dy))
        focusedTile = columns[nc][nr]
    }

    /// Sessions needing you outside the current project: the toolbar chip's count (handoff §3.1).
    public var needsYouElsewhere: [Fixture.Session] {
        let here = currentProject?.name
        return fixture.needsYou.filter { $0.project != here }
    }
}
