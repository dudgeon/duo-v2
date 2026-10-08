import DuoControl
import DuoSearch
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
    public var altitude: Altitude = .allProjects {
        // The idle list belongs to All projects: leaving closes it, so its keys go with it (F-178).
        didSet { if altitude != .allProjects, idleOpen { idleOpen = false; IdleKeys.remove() } }
    }

    /// The left pane is collapsed independently at each altitude (handoff §3.1).
    public var leftCollapsedAllProjects = false
    public var leftCollapsedProject = false
    /// The right pane hidden (DL-129): the action column at All projects, the document pane in a project.
    public var rightCollapsedAllProjects = false
    public var rightCollapsedProject = false

    // All projects
    public var selectedActionSession: String?   // Session.id
    public var focusedTile: String?             // Project.name
    public var homeTab: String?                 // Session.name

    // Inside a project
    public var selectedSidebarItem: String?     // group name or Session.id
    public var expandedGroups: Set<String> = []
    /// The session list's order while the pointer is in it (Q-80, DL-130): project, then each
    /// section's row ids. Nil when the list is free to reorder.
    public var sidebarHold: (project: String, order: [String: [String]])?
    /// Tasks just marked complete, still listed (checked, struck through) for `rowHold` (DL-130).
    public var completingTasks: Set<String> = []
    /// The project's layout fading up after a jump from another project (DL-130): the panes are
    /// the same views (terminals live in them), so the new content shows at once and fades up.
    public var projectShown: Double = 1
    /// Counts changes Duo shows before the snapshot does (Q-78). A snapshot started before the
    /// latest one is stale: it would put the old state back for a beat, so it's dropped.
    @ObservationIgnored var localChange = 0
    /// Which section each row of the session list was in when last shown, to lift the rows that
    /// change section above the ones they pass (DL-130).
    @ObservationIgnored var sidebarShown: [String: String] = [:]
    /// The task row under the pointer ("<project>/<note path>"), which shows its + (DL-112).
    public var hoveredTaskRow: String?
    /// Projects showing their task board in place of the session list and console (DL-148, C):
    /// the toolbar's Sessions | Tasks switch.
    public var boardProjects: Set<String> = []
    /// The board's Filter tasks field and Anyone ▾ popup (nil: anyone; "" : you).
    public var boardFilter = ""
    public var boardOwner: String?
    /// The card under the pointer ("<project>/<note path>"), the session row under it, and a lane
    /// header under it (for its ⋯).
    public var hoveredCard: String?
    public var hoveredCardSession: String?
    public var hoveredLane: String?
    /// A card being dragged ("<project>/<note path>") and the lane it's over (DL-148, board 7).
    public var boardDrag: String?
    public var boardDropLane: String?
    /// Cards just dropped on Done, held ticked in the lane they left for Mark Complete's hold
    /// (DL-130): "<project>/<note path>" → that lane's status.
    public var boardHeld: [String: String] = [:]
    /// A column being named: "" at the end of the lanes, or the status it goes after.
    public var addingColumn: String?
    @ObservationIgnored var boardKeyMonitor: Any?
    /// Each project's lanes as read from its brief, until the brief changes.
    @ObservationIgnored var baseOrderCache: [String: (url: URL, stamp: Date?, order: [String]?)] = [:]
    @ObservationIgnored var briefLanesCache: [String: (url: URL, stamp: Date?, lanes: [String])] = [:]
    /// The tab under the pointer (a console or Home tab's key, or a right-pane document path),
    /// which shows its close button (DL-126); `hoveredTabClose` when the pointer is on the button,
    /// `pressedTabClose` a press held for a capture (FixtureHarness `hover-tab`).
    public var hoveredTab: String?
    public var hoveredTabClose: String?
    public var pressedTabClose: String?
    public var consoleTab: String?              // Session.tabKey (id when live, else name)
    public var rightTab: String?                // "Project", a group name, or a document path
    /// The search modal (DL-76, DL-80).
    public let search = SearchUI()
    /// A session opened read-only from search, shown as a right-pane tab (search-open-session).
    public var readOnlySession: ReadOnlySession?
    /// Fixture mode's stand-in document: the section a search result landed on (search-open-file).
    public var searchLanding: SearchLanding?
    /// Fixture mode: the console message a target shows (DB-3).
    public var fixtureConsole: ConsoleEmpty?
    /// Bumped when a terminal's process ends by itself, so the console shows its bar (DB-3).
    public var endedRevision = 0
    /// The idle list (DB-1): open, and which row is selected.
    public var idleOpen = false
    public var idleSelection = 0
    /// Fixture mode: the rows the idle-list targets show.
    public var fixtureIdle: [IdleRow]?
    /// Fixture mode: sessions shown as having a terminal open (ENH-7).
    public var fixtureActive: Set<String>?
    /// Fixture mode: archived projects by name (ENH-6).
    public var fixtureArchived: Set<String>?
    /// Archived projects' folders (ENH-6), and whether the rollup is open.
    public var archivedProjectPaths: [String] = DuoState.load().archivedProjects
    public var archivedOpen = false
    public var fixtureIdleBuckets: [(label: String, rows: [IdleRow])]?
    /// Fixture mode: a console tab whose session has ended, and the bar's text (console-ended).
    public var fixtureEnded: (key: String, message: String)?
    /// Fixture mode: chats the chat-mode targets show, by console tab (ChatTargets).
    public var fixtureChats: [String: ChatSession] = [:]
    /// Plain shells open in each project's console, by key, in the order opened (DB-4).
    public var shellTabs: [String: [String]] = [:]
    /// What each shell is running, for its tab's title.
    public var shellTitles: [String: String] = [:]
    public var selectedFile: String?            // path relative to the project
    /// Open document tabs by project (DL-60): switching to Project no longer closes them.
    public var openDocumentsByProject: [String: [String]] = [:]
    /// The file tree (DL-105): hidden files on or off, and the folders open in each project's tree.
    public var showHiddenFiles = DuoState.load().showHiddenFiles
    /// The main window is full screen (View › Enter / Exit Full Screen, DL-108).
    public var fullScreen = false
    public var expandedFolders: [String: Set<String>] = [:]
    /// The console and right-pane tab each project showed when the user left it (DL-107).
    public var lastConsoleTab: [String: String] = [:]
    public var lastRightTab: [String: String] = [:]
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
    /// Chat mode (DL-118 to DL-120): each Claude session's chat over its terminal.
    @ObservationIgnored public lazy var chats = ChatStore()
    /// The one document editor (live mode; fixture mode keeps the placeholder the targets exempt).
    @ObservationIgnored public lazy var editor: EditorController = { let e = EditorController(); editorIfLoaded = e; wireEditor(e); return e }()
    /// Local HTML pages in the right pane (created on first use).
    @ObservationIgnored public lazy var htmlViewer: HTMLViewer = { let v = HTMLViewer(); htmlViewerIfLoaded = v; wireHTMLViewer(v); return v }()
    @ObservationIgnored public var htmlViewerIfLoaded: HTMLViewer?
    /// PowerPoint decks in the right pane (ENH-12, DL-125).
    @ObservationIgnored public lazy var deckViewer: DeckViewer = { let v = DeckViewer(); deckViewerIfLoaded = v; wireDeckViewer(v); return v }()
    @ObservationIgnored public var deckViewerIfLoaded: DeckViewer?
    /// Browser tabs by id (`web:…`), kept alive while their tab is open (Phase K, ENH-8).
    @ObservationIgnored public var webTabs: [String: WebTab] = [:]
    /// Downloads browser tabs saved since launch, oldest first (`duo2 browser downloads`, DL-124).
    @ObservationIgnored public var downloads: [DownloadRecord] = []
    /// Bumped when the picker starts, freezes or ends, so the picker bar redraws.
    public var pickerRevision = 0
    /// Which web view has the keyboard (menus re-validate on change).
    public var webFocus: WebFocus = .none
    public enum WebFocus: Equatable, Sendable { case none, editor, html }
    /// Drag and drop on the map (F-51): what's being dragged, the tile under it, the tile that
    /// just took a drop (it pulses).
    public var dragging: String?
    /// The session whose right-click menu is open (Q-147): its row shows the `menuTarget` fill until the menu closes.
    public var contextMenuSession: String?
    public var dropTarget: String?
    public var landed: String?
    public var landedNote = ""
    /// The file tree's folder under a drag of files (DL-117): its path, "" for the project root.
    public var treeDropTarget: String?
    /// Bumped when the editor's document goes into or out of conflict or removed-on-disk.
    public var editorRevision = 0
    /// The editor if it has been created (doc-status mustn't create one).
    @ObservationIgnored public var editorIfLoaded: EditorController?
    /// Word documents being converted to Markdown (DL-123), by the .docx's tab: how far, and what
    /// it's doing. Set only once a conversion has taken half a second, so a quick one shows nothing.
    public var converting: [String: (fraction: Double, stage: String)] = [:]
    @ObservationIgnored var conversionTasks: [String: Task<Void, Never>] = [:]
    /// Why a .docx couldn't be converted, by its tab, until it's converted or closed (F, F2).
    public var conversionFailures: [String: Docx.Failure] = [:]
    /// The notice on a Markdown copy just made (D, E), by its tab, until OK.
    public var conversions: [String: DocxConversion] = [:]

    /// A tab for a file outside the project (DL-106): `file:` and its absolute path.
    public static let outsideFilePrefix = "file:"
    public static func isOutsideFile(_ tab: String) -> Bool { tab.hasPrefix(outsideFilePrefix) }

    /// A project-relative path as a real file, in live mode; or an outside file's tab (DL-106).
    public func liveFile(_ path: String) -> URL? {
        guard terminalsMode == .live else { return nil }
        if Self.isOutsideFile(path) {
            let url = URL(fileURLWithPath: String(path.dropFirst(Self.outsideFilePrefix.count)))
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        guard let project = currentProject?.name, let folder = liveFolders[project],
              let url = Self.contained(path, in: folder) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A relative path inside `folder`, or nil when `..` takes it outside (C-20). Symlinks the user
    /// made inside the project are theirs to follow, so only the path itself is checked.
    public static func contained(_ path: String, in folder: URL) -> URL? {
        guard !path.hasPrefix("/") else { return nil }
        let root = folder.standardizedFileURL.path
        let url = folder.appending(path: path).standardizedFileURL
        return url.path == root || url.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") ? url : nil
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
            // Its folder is gone (DB-8): nothing to run in until it's located.
            guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
            // A transcript Claude's cleanup removed comes back from Duo's archive first (DL-44).
            if ClaudeStorage.transcript(sessionId: id, cwd: folder.path) == nil { _ = try? SessionArchive.restore(id) }
            let transcript = ClaudeStorage.transcript(sessionId: id, cwd: folder.path)
            // A session moved here from another folder (DL-64) resumes where it was, then /cd moves
            // it (and its transcript) to this folder, as Claude does itself. /cd to the folder it's
            // already in moves nothing (F-45), hence starting in the old one.
            var filed = transcript.flatMap(ClaudeStorage.filedCwd).map { URL(fileURLWithPath: $0).realPath }
            // Still filed under a folder that's gone (the project was moved outside Duo): it follows
            // the project first, or Claude wouldn't find it here (DB-8, F-78).
            if let f = filed, f != folder.realPath, !FileManager.default.fileExists(atPath: f),
               reconnectForResume(id, to: folder) { filed = folder.realPath }
            let movedHere = filed.map { $0 != folder.realPath && FileManager.default.fileExists(atPath: $0) } ?? false
            // Remote Control stays on for a session started with it (DL-128).
            let remote = SessionIndex.load(project: folder).sessions.first { $0.sessionId == id }?.remoteControl
            let t = terminals.session(key, command: transcript != nil ? .resumeClaude(sessionID: id, remoteControl: remote) : .newClaude(sessionID: id, prompt: nil, remoteControl: remote),
                                      cwd: movedHere ? filed! : folder.path)
            if movedHere { relocate(t, to: folder) }
            return t
        }
    }

    /// A pane's session tabs: live sessions, plus any Duo holds a terminal for. A Claude process
    /// sitting at its prompt reports `idle`, but it is open, so it keeps its tab (findings F-25).
    public func tabSessions(inProject project: String) -> [Fixture.Session] {
        fixture.sessions(inProject: project).filter {
            [.needsYou, .readyForReview, .working].contains($0.state) || terminals.existing($0.tabKey) != nil || fixtureEnded?.key == $0.tabKey
                || parkedTabs.contains($0.tabKey)
        }
    }

    /// Tabs restored at launch whose sessions haven't resumed yet (DL-156): each resumes when its tab
    /// is shown (the console or Home creates its terminal then), or when `duo2` or a send needs it.
    /// So a launch resumes only what's on screen, not every tab at once (F-208).

    // MARK: - Live workspace (Phase E)

    /// The map's order, filter and opened groups (DL-104). `mapSettled` holds each project's
    /// activity as it was on arrival at All projects, so tiles don't reshuffle while you look.
    public var mapSort: MapSort = MapSort(rawValue: DuoState.load().mapSort ?? "") ?? .recent
    public var mapFilter = ""
    public var openOutsideGroups: Set<String> = []
    @ObservationIgnored public var mapSettled: [String: Double] = [:]
    /// The middle at All projects (DL-142): Board (the map) or List (every session by recency). A new
    /// user sees List; after that the last choice (`setHomeView`).
    public var homeView: HomeView = HomeView(rawValue: DuoState.load().homeView ?? "") ?? .list
    /// The list's filter, its selected row (a session's `id`), and Group › Show Archived.
    public var listFilter = "" { didSet { if listFilter != oldValue { listFilterChanged() } } }
    /// The filter's answer (DL-142 (4)): sessions best first, each with the passage that matched;
    /// `listSearching` while search's index hasn't answered yet.
    public var listMatches: [SessionList.Match] = []
    public var listSearching = false
    @ObservationIgnored var listGeneration = 0
    public var listSelection: String?
    public var listShowsArchived = true
    /// Target states only: the clock the list's Today and This week are cut by.
    @ObservationIgnored public var listClock: Date?

    /// Home's folder (DL-85); nil until one is chosen. Live mode runs either way (DL-82).
    public var liveRoot: URL?
    @ObservationIgnored public var isLive = false
    /// Needs-you cards showing their whole question (DL-100: past 6 lines they fold).
    public var expandedQuestions: Set<String> = []
    /// The sheet on the window, if any (DL-100): Move into Home… or New project.
    public var moveIntoHomeForm: MoveIntoHomeForm?
    /// Property names and values for the properties block's suggestions, per project (PropertyCorpus).
    @ObservationIgnored var propertyCorpus: (project: String, at: Date, json: [String: Any])?
    @ObservationIgnored var scanningCorpus = false
    /// The project's files and folders for a task's references field (DL-150), rescanned at most once a minute.
    @ObservationIgnored var referenceFiles: (project: String, at: Date, files: [String])?
    @ObservationIgnored var scanningReferences = false
    /// Sessions already notified for their current wait (S3-6).
    @ObservationIgnored var notified = Set<String>()
    /// Sparkle's "Check for Updates", when the app started it (release builds).
    @ObservationIgnored public var sparkleCheck: (() -> Void)?
    public var newProjectForm: NewProjectForm?
    /// Each project's repository, when its folder is in one (DL-149, DL-157), by project name.
    public var repos: [String: RepoView] = [:]
    /// The Push sheet (board 6), when it's up.
    public var pushForm: PushForm?
    /// New project from GitHub (board 1), when it's up.
    public var gitHubProjectForm: GitHubProjectForm?
    /// The notice after a push (board 6), until it's used or 8 s pass.
    public var repoNotice: RepoNotice?
    /// The repo line's details popover (board 4).
    public var repoDetailsShown = false
    @ObservationIgnored var repoChecked: [String: Date] = [:]
    @ObservationIgnored var repoRefreshing: Set<String> = []
    /// Restore on relaunch (LR-58): off for scripted and capture runs.
    @ObservationIgnored public var restoreEnabled = false
    /// DL-156: see `tabSessions`.
    public var parkedTabs: Set<String> = []
    @ObservationIgnored var restoreApplied = false
    @ObservationIgnored var lastRestoreSave = Date.distantPast
    @ObservationIgnored var lastRestoreData: Data?
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
    /// Task titles as last seen, by "project/path": a title that changes moves its note to the
    /// new name's slug once it settles (DL-115, C-24).
    @ObservationIgnored var taskTitlesSeen: [String: String]?
    /// Undo steps being gathered into one (a task with its sessions archives, moves or comes back in one step).
    @ObservationIgnored var undoBatch: [(String, @MainActor (AppModel) -> Void)]?
    /// Checks only: undo steps go here instead of the window's undo manager.
    @ObservationIgnored public var undoRecorder: ((String, @escaping @MainActor (AppModel) -> Void) -> Void)?
    /// The last context sent to a session (Send to Claude), for `duo2 selection` and checks.
    @ObservationIgnored public var lastSent: (key: String, text: String)?
    /// The last task reference drafted into a new session's prompt (DL-112), for the harness and checks.
    @ObservationIgnored public var lastDrafted: (key: String, text: String)?

    public var visibleTerminal: TerminalSession? { visibleSessionId.flatMap { terminals.existing($0) } }

    /// The session whose terminal is on screen now.
    var visibleSessionId: String? {
        switch altitude {
        case .allProjects: return homeTab
        case .project: return consoleTab
        }
    }

    /// Switches to every real session (DL-82), with Home's projects under `root` when there is a
    /// Home, refreshing every 2 s from disk and beacons.
    public func startLive(root: URL?) {
        liveRoot = root
        // Home's prompt dismissed earlier: the pane starts collapsed until a Home exists (DL-100).
        if root == nil, DuoState.load().homePromptDismissed { leftCollapsedAllProjects = true }
        guard !isLive else { return refreshLive() }
        isLive = true
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
        guard isLive, !refreshing else { return }
        let root = liveRoot
        refreshing = true
        if let id = visibleSessionId, fixture.sessions.contains(where: { $0.sessionId == id && $0.state == .readyForReview }) {
            seen[id] = Date().timeIntervalSince1970
            DuoState.update { $0.seen[id] = seen[id] }
        }
        var ctx = LiveSnapshot.Context(root: root, rememberedHome: rememberedHome, events: DuoPaths.events, seen: seen)
        ctx.extraProjects = extraProjects
        ctx.showHidden = showHiddenFiles
        ctx.expanded = Dictionary(expandedFolders.compactMap { k, v in liveFolders[k].map { ($0.path, v) } }, uniquingKeysWith: { a, b in a.union(b) })
        let generation = localChange
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
            await self?.apply(snapshot, folders: folders, beacons: beacons, generation: generation)
        }
    }

    private func apply(_ snapshot: Fixture, folders: [String: URL], beacons: [Beacon], generation: Int) {
        refreshing = false
        // Read before a change Duo has already shown (Q-78): drop it and read again now.
        guard generation == localChange else {
            FileHandle.standardError.write(Data("live: dropped a snapshot read before a change Duo had shown (Q-78)\n".utf8))
            refreshLive(); return
        }
        // Sessions Duo started but Claude hasn't written a beacon for yet keep their tab.
        var merged = snapshot
        for s in fixture.sessions where s.sessionId != nil && terminals.existing(s.tabKey) != nil
            && !merged.sessions.contains(where: { $0.sessionId == s.sessionId }) {
            merged.sessions.append(s)
        }
        liveFolders = folders
        followSessionChanges(beacons)
        followShells(beacons)
        SearchService.shared.update(projects: folders)
        if let home = snapshot.home, let folder = folders[home.name]?.path, folder != rememberedHome {
            // First choice, or the remembered one is gone: remember what is in use now (DL-42).
            rememberedHome = folder
            DuoState.update { $0.home = folder }
        }
        let mine = Set(terminals.all.compactMap { t -> Int32? in t.view.process?.shellPid } + terminals.closingPids)
        // A Claude started by typing `claude` in a Duo shell is a child of that shell: still Duo's (DB-4).
        liveElsewhere = Set(beacons.filter { b in !mine.contains(b.pid) && !mine.contains { AppOwning.descends(b.pid, from: $0) } }.map(\.sessionId))
        // One row per session id, whatever the sources disagree on (seen once, F-29).
        var ids = Set<String>()
        merged.sessions = merged.sessions.filter { s in s.sessionId.map { ids.insert($0).inserted } ?? true }
        // Claude Code reports "waiting" while any screen of its own is up. One you opened from chat
        // (/model, /help …) isn't Claude waiting on you: no needs-you dot while it's up (DL-143).
        for i in merged.sessions.indices where merged.sessions[i].state == .needsYou {
            guard let id = merged.sessions[i].sessionId, chats.existing(id)?.ownScreenUp == true else { continue }
            merged.sessions[i].state = .idle
            merged.sessions[i].reason = nil
            merged.counts.needsYou = max(0, merged.counts.needsYou - 1)
        }
        if merged != fixture { fixture = merged }
        followTaskTitles()
        // The map's order settles on the first scan, then on each arrival at All projects (DL-104).
        if mapSettled.isEmpty || altitude != .allProjects { settleMapOrder() }
        pushNoteContext()
        Notifier.shared.model = self
        notifyNeedsYou()
        archiveListedSessions()  // after the snapshot is applied: it archives what's listed now
        GitIgnoreOffer.consider(folders, interactive: interactivePrompts && !SupportFolder.isIsolated)   // C-28: no first-run questions in an isolated instance
        refreshRepo()   // the open project's repository state (DL-149, DL-157)
        // What was open when Duo last quit comes back once the sessions are known (LR-58).
        if !restoreApplied, !fixture.sessions.isEmpty || !folders.isEmpty { applyRestore() }
        defer { saveRestoreState() }
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
            guard let pid = t.view.process?.shellPid, let b = beacons.first(where: { $0.pid == pid || AppOwning.descends($0.pid, from: pid) }),
                  b.sessionId != t.key, let old = fixture.sessions.first(where: { $0.tabKey == t.key }),
                  let folder = liveFolders[old.project] else { continue }
            var index = SessionIndex.load(project: folder)
            if !index.sessions.contains(where: { $0.sessionId == b.sessionId }) {
                index.sessions.append(.init(sessionId: b.sessionId, provenance: "continued-from:\(t.key)"))
                try? index.save(project: folder)
            }
            if consoleTab == t.key { consoleTab = b.sessionId }
            if homeTab == t.key { homeTab = b.sessionId }
            chats.rekey(t.key, to: b.sessionId)
            terminals.rekey(t.key, to: b.sessionId)
        }
    }

    /// ⌘W: ends the visible session's process. The session stays filed and resumable; its tab
    /// goes unless the session is still in a live state, and the next tab is selected.
    public func closeVisibleSession() {
        guard let key = visibleSessionId, terminals.existing(key) != nil else { return }
        confirmClose(key) { [weak self] in self?.endVisibleSession(key) }   // asks first when busy (Q-71)
    }

    private func endVisibleSession(_ key: String) {
        guard terminals.existing(key) != nil else { return }
        if isShell(key) { closeShell(key); return }
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
    public func newSession(in project: String, prompt: String? = nil, provenance: String = "created-by-duo",
                           id: String = UUID().uuidString.lowercased(), remoteControl: String? = nil) -> String? {
        guard terminalsMode == .live, let folder = liveFolders[project] else { return nil }
        var index = SessionIndex.load(project: folder)
        var entry = SessionIndex.Entry(sessionId: id, provenance: provenance)
        entry.remoteControl = remoteControl
        index.sessions.append(entry)
        try? index.save(project: folder)
        _ = terminals.session(id, command: .newClaude(sessionID: id, prompt: prompt, remoteControl: remoteControl), cwd: folder.path)
        fixture.sessions.append(Fixture.Session(name: LiveSnapshot.untitled(Date()), project: project, state: .working, wait: "now",
                                                question: nil, options: nil, summary: nil, forkOf: nil, document: nil,
                                                sessionId: id, remoteControl: remoteControl))
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
        terminals.onEnded = { [weak self] t in self?.endedRevision += 1; self?.shellEnded(t) }
    }

    public var leftCollapsed: Bool {
        get { altitude.isAllProjects ? leftCollapsedAllProjects : leftCollapsedProject }
        set {
            if altitude.isAllProjects { leftCollapsedAllProjects = newValue } else { leftCollapsedProject = newValue }
        }
    }

    /// The toolbar's right-pane button, ⌥⌘0 and `duo2 view right` (DL-129), for the altitude on screen.
    public var rightCollapsed: Bool {
        get { altitude.isAllProjects ? rightCollapsedAllProjects : rightCollapsedProject }
        set {
            if altitude.isAllProjects { rightCollapsedAllProjects = newValue } else { rightCollapsedProject = newValue }
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
        rememberTabs()
        let live = fixture.liveSessions(inProject: name)
        // Coming back (DL-107): the tab the user left on, while it's still open.
        let returning = sessionName == nil ? lastConsoleTab[name] : nil
        let returningShell = returning.flatMap { k in isShell(k) && shells(inProject: name).contains(k) ? k : nil }
        // The named session, else the one the user left on, else the most urgent live one, else one
        // with a running terminal: a session idle at its prompt has a tab, and left the console blank when skipped.
        let target = sessionName.flatMap { n in fixture.sessions(inProject: name).first { $0.name == n } }
            ?? returning.flatMap { k in tabSessions(inProject: name).first { $0.tabKey == k } }
            ?? (returningShell == nil ? SidebarRow.mostUrgent(live) : nil)
            ?? (returningShell == nil ? tabSessions(inProject: name).first { terminals.existing($0.tabKey) != nil } : nil)
        if case .project(let was) = altitude, was != name, !MotionSettings.shared.reduce {
            projectShown = 0
            DispatchQueue.main.async { [weak self] in withDuoAnimation(.altitude) { self?.projectShown = 1 } }
        }
        altitude = .project(name)
        peekOpen = false
        consoleTab = returningShell ?? target?.tabKey
        if let target { lastVisitedSession = target.id }
        if let target, let group = fixture.groups.first(where: { g in g.project == name && g.sessions.contains(target.name) }) {
            selectedSidebarItem = group.name
            expandedGroups.insert(group.name)
        } else {
            selectedSidebarItem = target?.id
        }
        // A document asked for, or the named session's, wins; then the tab left open (DL-107).
        let returningRight = lastRightTab[name].flatMap { t in t == "Project" || (openDocumentsByProject[name] ?? []).contains(t) ? t : nil }
        if let doc = document ?? (sessionName != nil || returningRight == nil ? target?.document : nil) {
            if !(openDocumentsByProject[name] ?? []).contains(doc) { openDocumentsByProject[name, default: []].append(doc) }
            rightTab = doc
            selectedFile = doc
        } else if let tab = returningRight, tab != "Project" {
            rightTab = tab
            selectedFile = tab
        } else {
            rightTab = "Project"
            selectedFile = nil
        }
    }

    /// Notes the tabs the current project shows, before leaving it (DL-107).
    func rememberTabs() {
        guard let p = currentProject?.name else { return }
        lastConsoleTab[p] = consoleTab
        lastRightTab[p] = rightTab
    }

    /// Back to All projects; the session last opened is the selected row (flow-zoom-4).
    public func zoomOut() {
        rememberTabs()
        altitude = .allProjects
        settleMapOrder()
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
        if isShell(key), shells(inProject: currentProject?.name ?? "").contains(key) { consoleTab = key; return }
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

    /// Arrow keys between tiles on the map: columns as drawn (DL-104), rows are tiles.
    public func moveTileFocus(dx: Int, dy: Int) {
        let columns = mapLayout.focusColumns
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

extension AppModel {
    /// The open project's session list as shown: held still while the pointer is in it (Q-80).
    public func sidebarSections() -> [SidebarSection] {
        guard let p = currentProject?.name else { return [] }
        let fresh = SidebarRow.sections(for: p, in: fixture, isOpen: { hasOpenTerminal($0) })
        guard let hold = sidebarHold, hold.project == p else { return fresh }
        return SidebarRow.held(fresh, order: hold.order)
    }

    /// The pointer came into the session list, or left it. Coming in, the list holds its order;
    /// leaving, rows move to where they belong now (`rowMove`, DL-130).
    public func hoverSidebar(_ inside: Bool) {
        guard let p = currentProject?.name else { return }
        if inside {
            guard sidebarHold?.project != p else { return }
            sidebarHold = (p, Dictionary(uniqueKeysWithValues: sidebarSections().map { ($0.id, $0.rows.map(\.id)) }))
        } else if sidebarHold != nil {
            withDuoAnimation(.rowMove) { sidebarHold = nil }
        }
    }
}

extension AppModel {
    /// Shows a change the user just made at once, before the snapshot that confirms it (Q-78,
    /// DL-130). The lists move by their own animations (keyed on their rows), so text and marks
    /// change at once. A snapshot already in flight is dropped (`localChange`), so the old state
    /// never comes back for a beat; if the change didn't happen on disk, the next snapshot shows that.
    func showNow(_ change: () -> Void) {
        localChange += 1
        change()
    }
}

extension AppModel {
    /// Rows now in a different section from where they were last shown: the ones that travel.
    func sidebarMovers(_ sections: [SidebarSection]) -> Set<String> {
        var out = Set<String>()
        for s in sections { for r in s.rows where sidebarShown[r.id].map({ $0 != s.id }) ?? false { out.insert(r.id) } }
        return out
    }

    func noteSidebar(_ sections: [SidebarSection]) {
        sidebarShown = Dictionary(sections.flatMap { s in s.rows.map { ($0.id, s.id) } }, uniquingKeysWith: { a, _ in a })
    }
}
