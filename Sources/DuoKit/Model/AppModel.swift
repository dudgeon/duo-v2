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

    public var peekOpen = false
    /// The selected card in the peek, by Session.id.
    public var peekSelection: String?
    /// The session last opened inside a project; selected again on zooming out (flow-zoom-4).
    public var lastVisitedSession: String?
    /// Asks the Home terminal to take keyboard focus (consumed by the Home pane).
    public var focusHomeRequest = 0

    public var terminalsMode: TerminalsMode = .off
    @ObservationIgnored public let terminals = TerminalStore()

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
            let resumable = ClaudeStorage.transcript(sessionId: id, cwd: folder.path) != nil
            return terminals.session(key, command: resumable ? .resumeClaude(sessionID: id) : .newClaude(sessionID: id, prompt: nil),
                                     cwd: folder.path)
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
    /// Duo's "seen" marks (handoff §10): looking at a session clears ready-for-review.
    @ObservationIgnored public var seen: [String: Double] = [:]
    @ObservationIgnored public var rememberedHome: String?

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
        let ctx = LiveSnapshot.Context(root: root, rememberedHome: rememberedHome, events: DuoPaths.events, seen: seen)
        Task.detached(priority: .utility) { [weak self] in
            let beacons = Beacon.readAll()
            let (snapshot, folders) = LiveSnapshot.build(ctx, beacons: beacons)
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
        if let home = snapshot.home, let folder = folders[home.name]?.path, folder != rememberedHome {
            // First choice, or the remembered one is gone: remember what is in use now (DL-42).
            rememberedHome = folder
            DuoState.update { $0.home = folder }
        }
        let mine = Set(terminals.all.compactMap { t -> Int32? in t.view.process?.shellPid })
        liveElsewhere = Set(beacons.filter { !mine.contains($0.pid) }.map(\.sessionId))
        if merged != fixture { fixture = merged }
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

    /// `+ New session` (handoff §6.2): a new Claude Code session in the current project's folder,
    /// with a Duo-minted id recorded in the project's session index first (CONS FR-7.7.7).
    public func newSession() {
        guard let project = currentProject?.name else { return }
        newSession(in: project)
        consoleTab = fixture.sessions.last?.tabKey
    }

    public func newSession(in project: String) {
        guard terminalsMode == .live, let folder = liveFolders[project] else { return }
        let id = UUID().uuidString.lowercased()
        var index = SessionIndex.load(project: folder)
        index.sessions.append(.init(sessionId: id))
        try? index.save(project: folder)
        _ = terminals.session(id, command: .newClaude(sessionID: id, prompt: nil), cwd: folder.path)
        fixture.sessions.append(Fixture.Session(name: "New session", project: project, state: .working, wait: "now",
                                                question: nil, options: nil, summary: nil, forkOf: nil, document: nil,
                                                sessionId: id))
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
