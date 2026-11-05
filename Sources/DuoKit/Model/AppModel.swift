import AppKit
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

/// Window-level UI state. One instance per window; views read it from the environment. What the
/// windows share is the core's (`AppCore`), forwarded below.
@MainActor
@Observable
public final class AppModel {
    /// What every window shares (F-537): projects, sessions, terminals, the live loop, each project's memory.
    @ObservationIgnored public let core: AppCore
    /// The window this model draws, set when `MainWindow` makes it (never found by title: there may be two).
    @ObservationIgnored public weak var window: NSWindow? {
        didSet { windowID = window.map(ObjectIdentifier.init) }
    }
    /// The window's identity, for a question's target and the key window (`AppCore.keyWindowID`).
    public private(set) var windowID: ObjectIdentifier?
    /// The window's number (multi-window slice 1): 1 for the first, then the lowest free one. Stable while
    /// the window is open; Home's stand-in and `duo2 window` name windows by it.
    public internal(set) var windowNumber = 1
    /// The window's base colour (DL-312, DL-313), a `DuoWindowColour` id; nil is None.
    public var windowColourID: String?
    public var altitude: Altitude = .allProjects {
        // The idle list belongs to All projects: leaving closes it, so its keys go with it (F-178).
        didSet { if altitude != .allProjects, idleOpen { idleOpen = false; IdleKeys.remove() } }
    }

    /// The left pane is collapsed independently at each altitude (handoff §3.1).
    /// All projects' left sidebar starts closed until the person opens or closes it themselves
    /// (`leftTouchedAllProjects`); a project's starts open (DL-315).
    public var leftCollapsedAllProjects = true
    public var leftTouchedAllProjects = false
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
    /// Several sessions selected in one list (DL-247).
    public var sessionSelection = SessionSelection()
    /// Each list's rows as last drawn, session keys and breakers (`SessionSelection.breaker`): what a ⇧-click ranges over.
    @ObservationIgnored public var selectionOrders: [String: [String]] = [:]
    /// Each list's folded fork threads as last drawn: the row's key → its fold key and its sessions (DL-250).
    @ObservationIgnored public var selectionThreads: [String: [String: (fold: String, members: [String])]] = [:]
    public var expandedGroups: Set<String> = []
    /// The session list's order while the pointer is in it (Q-80, DL-130): project, then each
    /// section's row ids. Nil when the list is free to reorder.
    public var sidebarHold: (project: String, order: [String: [String]])?
    /// Tasks just marked complete, still listed (checked, struck through) for `rowHold` (DL-130).
    public var completingTasks: Set<String> = []
    /// Mark Complete's "Close #n too" notice (github-issues-handoff board 6), for 5 s.
    public var issueOffer: IssueOffer?
    /// The project's layout fading up after a jump from another project (DL-130): the panes are
    /// the same views (terminals live in them), so the new content shows at once and fades up.
    public var projectShown: Double = 1
    /// Which section each row of the session list was in when last shown, to lift the rows that
    /// change section above the ones they pass (DL-130).
    @ObservationIgnored var sidebarShown: [String: String] = [:]
    /// The director's slot in a fixture state (DL-218); live, it's read from `.duo/director.json`.
    public var fixtureDirector: DirectorSlotInfo?
    /// The project pane's width, for the slot's second line (under 280 it drops "Director", DL-218).
    public var sidebarWidth: CGFloat = 300
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
    /// Each project's lanes as read from its brief, until the brief changes.
    @ObservationIgnored var baseOrderCache: [String: (url: URL, stamp: Date?, order: [String]?)] = [:]
    @ObservationIgnored var briefLanesCache: [String: (url: URL, stamp: Date?, lanes: [String])] = [:]
    /// The tab under the pointer (a console or Home tab's key, or a right-pane document path),
    /// which shows its close button (DL-126); `hoveredTabClose` when the pointer is on the button,
    /// `pressedTabClose` a press held for a capture (FixtureHarness `hover-tab`).
    public var hoveredTab: String?
    public var hoveredTabClose: String?
    /// The pill segment under the pointer (`PillSegment`, DL-253): `new-claude` or `new-shell`; a fixture sets it for the target's hovered halves.
    public var hoveredPill: String?
    public var pressedTabClose: String?
    public var consoleTab: String?              // Session.tabKey (id when live, else name)
    public var rightTab: String?                // "Project", a group name, or a document path
    /// The search modal (DL-76, DL-80).
    public let search = SearchUI()
    /// Split view (DL-275 to DL-278): the split tabs, what they took to make room, their previews.
    public let splits: SplitState
    /// The Explainer popover (DL-172): which is open, where, and the hover clocks.
    public let explainer = ExplainerState()
    /// A session opened read-only from search, shown as a right-pane tab (search-open-session).
    public var readOnlySession: ReadOnlySession?
    /// Fixture mode's stand-in document: the section a search result landed on (search-open-file).
    public var searchLanding: SearchLanding?
    /// Fixture mode: the console message a target shows (DB-3).
    public var fixtureConsole: ConsoleEmpty?
    /// The idle list (DB-1): open, and which row is selected.
    public var idleOpen = false
    public var idleSelection = 0
    /// Fixture mode: the rows the idle-list targets show.
    public var fixtureIdle: [IdleRow]?
    /// Fixture mode: sessions shown as having a terminal open (ENH-7).
    public var fixtureActive: Set<String>?
    /// Fixture mode: archived projects by name (ENH-6).
    public var fixtureArchived: Set<String>?
    public var archivedOpen = false
    public var fixtureIdleBuckets: [(label: String, rows: [IdleRow])]?
    /// Fixture mode: a console tab whose session has ended, and the bar's text (console-ended).
    public var fixtureEnded: (key: String, message: String)?
    /// Fixture mode: chats the chat-mode targets show, by console tab (ChatTargets).
    public var fixtureChats: [String: ChatSession] = [:]
    /// The intro video's demo (VideoTargets): terminals showing a recorded screen, by tab; no process behind them.
    public var fixtureTerminals: [String: TerminalSession] = [:]
    /// The intro video's demo: a folder of real files the right pane opens in fixture mode, as a live project's would.
    public var videoDemoFolder: URL?
    /// The intro video's scene 10: this project's tasks UI (the Tasks fold, + New task, the Sessions | Tasks switch and the board) shows
    /// as in a live project, though the demo has no live folder behind it (VideoTargets+S9S10).
    public var videoTasks = false
    /// The intro video's scene 9: folders the file tree shows closed (as a live project's start), by path.
    public var videoClosedFolders: Set<String> = []
    /// The intro video's demo: the right pane's opening width, wide enough for its tabs.
    public var videoRightWidth: CGFloat?
    public var selectedFile: String?            // path relative to the project
    /// Bumped by every reveal in the tree, so the tree scrolls to the selection even when it was already selected (BUG-053).
    public var treeRevealTick = 0
    /// A tab being dragged along its strip (ENH-042): the strips draw it lifted under the pointer.
    public var tabDrag: TabDrag?
    /// Each tab's frame on its strip, for where a drag lands; written as the strips lay out.
    @ObservationIgnored var tabFrames: [String: CGRect] = [:]
    /// Each scrolling tab strip's offset and measures (DL-225): console (.middle), right pane (.right), Home (.left).
    public let tabStrips: [DuoPane: TabStripState] = [.left: TabStripState(), .middle: TabStripState(), .right: TabStripState()]
    /// Where the pointer is on a strip while a tab is dragged along it, in the strip's scrolling part (edge scroll).
    var tabDragPointer: (pane: DuoPane, x: CGFloat)?
    /// The formatting bar's control under the pointer, and the one whose menu is open (the bar stays while a menu is).
    var formatBarHover: String?
    var formatBarMenuOpen = false
    /// Where each of the bar's menu buttons is, in the window's content view (to pop its menu under it).
    @ObservationIgnored public var formatBarFrames: [String: CGRect] = [:]
    /// The main window is full screen (View › Enter / Exit Full Screen, DL-108).
    public var fullScreen = false
    /// The file or folder being named inline in the tree (DL-62).
    public var renamingPath: String?

    public var peekOpen = false
    /// The toolbar swatch's popover (DL-312, board 4b) is open.
    public var colourPopoverOpen = false
    /// The selected card in the peek, by Session.id.
    public var peekSelection: String?
    /// The session last opened inside a project; selected again on zooming out (flow-zoom-4).
    public var lastVisitedSession: String?
    /// Asks the Home terminal to take keyboard focus (consumed by the Home pane).
    public var focusHomeRequest = 0
    /// The pane that has the keyboard's attention at each altitude (DL-165); `activePane` reads the one on screen.
    public var activePaneProject: DuoPane = .middle
    public var activePaneAllProjects: DuoPane = .left

    /// Voice input (DL-260): one dictation at a time, into a chat composer or a terminal's prompt.
    /// One for the app (the core's), wired by the first window that asks.
    public var voice: VoiceInput {
        if let v = core.voiceInput { return v }
        let v = VoiceInput()
        core.voiceInput = v
        wireVoice(v)
        return v
    }
    /// The document editors, one per side of a split (C-135, DL-278): `editor` is the active one.
    @ObservationIgnored public lazy var editors: EditorSet = makeEditorSet()
    /// Local HTML pages in the right pane (created on first use).
    @ObservationIgnored public lazy var htmlViewer: HTMLViewer = { let v = HTMLViewer(); htmlViewerIfLoaded = v; wireHTMLViewer(v); return v }()
    @ObservationIgnored public var htmlViewerIfLoaded: HTMLViewer?
    /// PowerPoint decks in the right pane (ENH-12, DL-125).
    @ObservationIgnored public lazy var deckViewer: DeckViewer = { let v = DeckViewer(); deckViewerIfLoaded = v; wireDeckViewer(v); return v }()
    @ObservationIgnored public var deckViewerIfLoaded: DeckViewer?
    /// Word documents in the right pane (DL-162).
    @ObservationIgnored public lazy var docxViewer: DocxViewer = { let v = DocxViewer(); docxViewerIfLoaded = v; wireDocxViewer(v); return v }()
    @ObservationIgnored public var docxViewerIfLoaded: DocxViewer?
    /// The Markup menu is open (W4); the viewer's bar shows Markup pressed while it is.
    public var docxMenuOpen = false
    @ObservationIgnored var reviewPillMenu: AnyObject?
    /// The Markdown review bar's open menu: "markup" or "all" (DL-237).
    public var reviewMenu: String?
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
    /// A Markdown document's review view while Duo runs, by file path (DL-162, DL-237): the markup mode and Show Closed Comments.
    @ObservationIgnored public var markdownMarkup: [String: MarkdownMarkup] = [:]
    /// Set once, when the editor first shows a document. Observed, so commands that depend on the
    /// (unobserved) editor re-evaluate then: Save stayed disabled until something else invalidated.
    public var editorOpened = false

    /// A tab for a file outside the project (DL-106): `file:` and its absolute path.
    public static let outsideFilePrefix = "file:"
    public static func isOutsideFile(_ tab: String) -> Bool { tab.hasPrefix(outsideFilePrefix) }

    /// A project-relative path as a real file, in live mode; or an outside file's tab (DL-106).
    public func liveFile(_ path: String) -> URL? {
        guard terminalsMode == .live || videoDemoFolder != nil else { return nil }
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
        // Lexical on both sides: standardizedFileURL drops /private from a path that exists but not
        // from one that doesn't, so a file gone from a folder under /tmp was "outside" it (F-262).
        let root = folder.standardized.path
        let url = folder.appending(path: path).standardized
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
            // A /fork detached from its tab runs on in Claude's background: opening it attaches again (DL-227).
            if liveElsewhere.contains(id), s.fork == ForkSource.Kind.fork.rawValue, let job = ForkSource.jobs().first(where: { $0.sessionId == id }) {
                detachedForks.remove(id)
                return terminals.session(key, command: .attachClaude(short: job.short, sessionID: id), cwd: folder.path)
            }
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
            !(detachedForks.contains($0.tabKey) && terminals.existing($0.tabKey) == nil)
            && ([.needsYou, .readyForReview, .working].contains($0.state) || terminals.existing($0.tabKey) != nil || fixtureEnded?.key == $0.tabKey
                || parkedTabs.contains($0.tabKey))
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
    public var newProjectForm: NewProjectForm?
    /// New Deck… and Convert to Duo Deck… (Duo Decks P3-4).
    public var newDeckForm: NewDeckForm?
    public var convertDeckForm: ConvertDeckForm?
    /// The Push sheet (board 6), when it's up.
    public var pushForm: PushForm?
    /// New project from GitHub (board 1), when it's up.
    public var gitHubProjectForm: GitHubProjectForm?
    /// The notice after a push (board 6), until it's used or 8 s pass.
    public var repoNotice: RepoNotice?
    /// The repo line's details popover (board 4).
    public var repoDetailsShown = false
    /// The New session row's pointer state and whether the List has scrolled (DL-262); state lives here, not in views.
    public var newSessionRowHover = false
    public var newSessionRowPressed = false
    public var listScrolled = false
    /// Undo steps being gathered into one (a task with its sessions archives, moves or comes back in one step).
    @ObservationIgnored var undoBatch: [(String, @MainActor (AppModel) -> Void)]?
    /// Checks only: undo steps go here instead of the window's undo manager.
    @ObservationIgnored public var undoRecorder: ((String, @escaping @MainActor (AppModel) -> Void) -> Void)?
    /// The last context sent to a session (Send to Claude), for `duo2 selection` and checks.
    @ObservationIgnored public var lastSent: (key: String, text: String)?
    /// The last task reference drafted into a new session's prompt (DL-112), for the harness and checks.
    @ObservationIgnored public var lastDrafted: (key: String, text: String)?
    /// The session the last Make a Project or New Project started to interview the user (DL-223), for `duo2` and checks.
    @ObservationIgnored public var lastInterview: String?

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
        guard !isLive else { return refreshLive() }   // the core's loop runs once, whichever window starts it (C-146)
        isLive = true
        terminalsMode = .live
        let state = DuoState.load()
        seen = state.seen
        rememberedHome = state.home
        keepRunningIDs = Set(state.keepRunning)
        extraProjects = state.projects.map { URL(fileURLWithPath: $0) }
        startFolders = state.startFolders
        startMemoryPressureWatch()
        fixture = LiveSnapshot.empty()  // never show the design fixture while the first scan runs
        refreshLive()
        core.startLoop()
    }

    /// Rebuilds the snapshot off the main thread, one refresh at a time: disk reads can block
    /// (a privacy prompt for ~/Documents, a slow network volume) and must never freeze the UI (F-28).
    /// One refresh for the app, whichever window asks: it runs through the primary window's model,
    /// so the scan and the app-wide passes after it happen once (C-146).
    public func refreshLive() {
        if let p = core.primary, p !== self { return p.refreshLive() }
        guard isLive, !core.refreshing else { return }
        let root = liveRoot
        core.refreshing = true
        core.count("scan")
        for m in core.models { m.markVisibleSeen() }
        var ctx = LiveSnapshot.Context(root: root, rememberedHome: rememberedHome, events: DuoPaths.events, seen: seen)
        ctx.extraProjects = extraProjects
        ctx.showHidden = showHiddenFiles
        ctx.expanded = Dictionary(expandedFolders.compactMap { k, v in liveFolders[k].map { ($0.path, v) } }, uniquingKeysWith: { a, b in a.union(b) })
        let generation = localChange
        let startList = startFolders
        let build = core.snapshotSource
        Task.detached(priority: .utility) { [weak self] in
            let beacons = Beacon.readAll()
            let (snapshot, folders, moves) = build(ctx, beacons)
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
            let homeFolders = root.map { AppModel.homeFolders(root: $0) } ?? []
            await self?.apply(snapshot, folders: folders, beacons: beacons, generation: generation)
            await self?.setHomeFolderList(homeFolders)
            let docs = StartDefault.documentsExistsOnDisk()
            await self?.setDocumentsExists(docs)
            let present = Set(startList.filter { FileManager.default.fileExists(atPath: $0) })
            await self?.setStartFoldersPresent(present)
        }
    }

    /// Looking at a session clears ready-for-review (handoff §10): this window's visible session.
    func markVisibleSeen() {
        guard let id = visibleSessionId, fixture.sessions.contains(where: { $0.sessionId == id && $0.state == .readyForReview }) else { return }
        seen[id] = Date().timeIntervalSince1970
        DuoState.update { $0.seen[id] = seen[id] }
    }

    private func setStartFoldersPresent(_ v: Set<String>) {
        if startFoldersPresent != v { startFoldersPresent = v }
    }

    private func setDocumentsExists(_ v: Bool) {
        if documentsExists != v { documentsExists = v }
    }

    private func setHomeFolderList(_ list: [URL]) {
        if list != homeFolderList { homeFolderList = list }   // unchanged: no redraw every refresh
    }

    private func apply(_ snapshot: Fixture, folders: [String: URL], beacons: [Beacon], generation: Int) {
        core.refreshing = false
        core.count("apply")
        // Read before a change Duo has already shown (Q-78): drop it and read again now.
        guard generation == localChange else {
            FileHandle.standardError.write(Data("live: dropped a snapshot read before a change Duo had shown (Q-78)\n".utf8))
            refreshLive(); return
        }
        // Sessions Duo started but Claude hasn't written a beacon for yet keep their tab.
        var merged = snapshot
        adoptForks(into: &merged)
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
        if !merged.sameApartFromClock(fixture) { fixture = merged }
        followTaskTitles()
        followTaskStatus()
        let windows = core.models
        for m in windows { m.didRefreshMap() }
        // The app-wide passes: once per refresh, however many windows (C-146).
        Notifier.shared.model = self
        core.count("notify")
        notifyNeedsYou()
        core.count("prune")
        pruneDirectorRegistries()   // workers whose task is done; messages an older Duo queued (DL-257)
        core.count("deliver")
        deliverReviewComments()     // @claude comments waiting for their session, and their replies (DL-236 10A)
        archiveListedSessions()  // after the snapshot is applied: it archives what's listed now
        core.count("gitignore")
        GitIgnoreOffer.consider(folders, interactive: interactivePrompts && !SupportFolder.isIsolated)   // C-28: no first-run questions in an isolated instance
        core.count("move")
        moveDuoFiles(folders)   // PROJECT.md → _PROJECT.md, once, quietly (DL-259, Q-330)
        for m in windows { m.didRefreshProject() }
        // What was open when Duo last quit comes back once the sessions are known (LR-58).
        if !restoreApplied, !fixture.sessions.isEmpty || !folders.isEmpty { applyRestore() }
        defer { saveRestoreState() }
        // Home is always on (brief: the director agent); its empty state isn't designed (§13), so
        // live mode starts one Home session when there is none (concerns C-15).
        if let home = fixture.home {
            let homeSessions = fixture.sessions(inProject: home.name)
            if homeSessions.isEmpty { newSession(in: home.name) }
            for m in windows where m.homeTab == nil || !fixture.sessions(inProject: home.name).contains(where: { $0.tabKey == m.homeTab }) {
                m.homeTab = fixture.sessions(inProject: home.name).first?.tabKey
            }
        }
    }

    /// A window's part of a refresh, before the app's passes: its map order and its editor's note context.
    func didRefreshMap() {
        core.count("window-refresh")
        // The map's order settles on the first scan, then on each arrival at All projects (DL-104).
        if mapSettled.isEmpty || altitude != .allProjects { settleMapOrder() }
        pushNoteContext()
    }

    /// A window's part of a refresh, after the app's passes: the project it shows.
    func didRefreshProject() {
        refreshRepo()   // the open project's repository state (DL-149, DL-157)
        if let p = currentProject?.name { refreshIssues(project: p) }   // linked issues' live state (DL-226)
    }

    /// Keeps Duo's copy of every listed session's transcript (DL-44), at most once a minute, off
    /// the main thread.
    private func archiveListedSessions() {
        guard Date().timeIntervalSince(core.lastArchive) > 60 else { return }
        core.lastArchive = Date()
        core.count("archive")
        let listed: [(String, String)] = fixture.sessions.compactMap { s in
            guard let id = s.sessionId, let folder = liveFolders[s.project] else { return nil }
            return (id, folder.path)
        }
        Task.detached(priority: .utility) {
            // The refresh's listing names each transcript; a path lookup (a listing of every bucket on a miss) only without one (F-598).
            let found = listed.compactMap { id, cwd in (ClaudeStorage.listed(sessionId: id) ?? (ClaudeStorage.hasListing ? nil : ClaudeStorage.transcript(sessionId: id, cwd: cwd))).map { (id: id, transcript: $0) } }
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
    /// process. File the new id where the old one was, and move the tab with it (F-29). A `/branch`
    /// (SessionStart source `fork`, or the new transcript's `forkedFrom`) splits instead (DL-227).
    private func followSessionChanges(_ beacons: [Beacon]) {
        for t in terminals.all {
            guard let pid = t.view.process?.shellPid, let b = beacons.first(where: { $0.pid == pid || AppOwning.descends($0.pid, from: pid) }),
                  b.sessionId != t.key, let old = fixture.sessions.first(where: { $0.tabKey == t.key }),
                  let folder = liveFolders[old.project] else { continue }
            if isBranch(newId: b.sessionId, from: t.key, folder: folder) {
                splitBranch(from: old, to: b.sessionId, folder: folder)
                continue
            }
            var index = SessionIndex.load(project: folder)
            if !index.sessions.contains(where: { $0.sessionId == b.sessionId }) {
                index.sessions.append(.init(sessionId: b.sessionId, provenance: "continued-from:\(t.key)"))
                try? index.save(project: folder)
            }
            for m in core.models {
                if m.consoleTab == t.key { m.consoleTab = b.sessionId }
                if m.homeTab == t.key { m.homeTab = b.sessionId }
            }
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
        chats.forget(key)
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
        if altitude.isAllProjects { return pressNewSessionRow() }   // F-446, DL-262
        guard let project = currentProject?.name else { return }
        newSession(in: project)
        consoleTab = fixture.sessions.last?.tabKey
    }

    @discardableResult
    public func newSession(in project: String, prompt: String? = nil, provenance: String = "created-by-duo",
                           id: String = UUID().uuidString.lowercased(), remoteControl: String? = nil, name: String? = nil) -> String? {
        guard terminalsMode == .live, let folder = liveFolders[project] else { return nil }
        var index = SessionIndex.load(project: folder)
        var entry = SessionIndex.Entry(sessionId: id, provenance: provenance)
        entry.remoteControl = remoteControl
        index.sessions.append(entry)
        try? index.save(project: folder)
        _ = terminals.session(id, command: .newClaude(sessionID: id, prompt: prompt, remoteControl: remoteControl, name: name), cwd: folder.path)
        fixture.sessions.append(Fixture.Session(name: name ?? LiveSnapshot.untitled(Date()), project: project, state: .working, wait: "now",
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

    /// A window's model on the app's core (multi-window slice 0). The first model made on a core is
    /// its primary window.
    public init(core: AppCore) {
        self.core = core
        self.splits = SplitState(shared: core.splitTabs)
        core.attach(self)
    }

    /// A model with its own core: a one-window app (the checks, the harness, the app in slice 0).
    public convenience init(fixture: Fixture) {
        self.init(core: AppCore(fixture: fixture))
    }

    public var leftCollapsed: Bool {
        get { altitude.isAllProjects ? leftCollapsedAllProjects : leftCollapsedProject }
        set {
            if altitude.isAllProjects { leftCollapsedAllProjects = newValue; leftTouchedAllProjects = true } else { leftCollapsedProject = newValue }
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
    /// A project lives in one window (DL-308): when another window shows it, that window opens it (with the
    /// session or document asked for) and comes forward, and this one stays as it was. Returns the model that
    /// shows the project, for what the caller does next.
    @discardableResult
    public func open(project name: String, session sessionName: String? = nil, document: String? = nil) -> AppModel {
        if let other = core.model(showing: name), other !== self {
            other.open(project: name, session: sessionName, document: document)
            core.bringForward(other)
            return other
        }
        rememberTabs()
        defer { if splitTabs.isEmpty { giveBackRoom() } }   // another project's split doesn't hold the room here (DL-276)
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
        if let target { detachedForks.remove(target.tabKey) }   // a detached /fork attaches again (DL-227)
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
        return self
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
        detachedForks.remove(s.tabKey)   // a detached /fork attaches again (DL-227)
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

    // MARK: - Forwarded to the app's core (multi-window slice 0, F-537): app-wide and per-project state
    // lives in `AppCore`, so every window reads and writes the same value. `_modify` mutates in place.
    public var fixture: Fixture { get { core.fixture } set { core.fixture = newValue } _modify { yield &core.fixture } }
    public var issueStates: [String: IssueState] { get { core.issueStates } set { core.issueStates = newValue } _modify { yield &core.issueStates } }
    var issueFetched: [String: Date] { get { core.issueFetched } set { core.issueFetched = newValue } _modify { yield &core.issueFetched } }
    var movesChecked: Set<String> { get { core.movesChecked } set { core.movesChecked = newValue } _modify { yield &core.movesChecked } }
    var issueFetching: Set<String> { get { core.issueFetching } set { core.issueFetching = newValue } _modify { yield &core.issueFetching } }
    var issueRepos: [String: RemoteRepo?] { get { core.issueRepos } set { core.issueRepos = newValue } _modify { yield &core.issueRepos } }
    var localChange: Int { get { core.localChange } set { core.localChange = newValue } _modify { yield &core.localChange } }
    var directorRegistryCache: [String: (modified: Date, reg: DirectorRegistry)] { get { core.directorRegistryCache } set { core.directorRegistryCache = newValue } _modify { yield &core.directorRegistryCache } }
    public var endedRevision: Int { get { core.endedRevision } set { core.endedRevision = newValue } _modify { yield &core.endedRevision } }
    public var archivedProjectPaths: [String] { get { core.archivedProjectPaths } set { core.archivedProjectPaths = newValue } _modify { yield &core.archivedProjectPaths } }
    public var trustNotices: [String: TrustNotice] { get { core.trustNotices } set { core.trustNotices = newValue } _modify { yield &core.trustNotices } }
    public var shellTabs: [String: [String]] { get { core.shellTabs } set { core.shellTabs = newValue } _modify { yield &core.shellTabs } }
    public var shellTitles: [String: String] { get { core.shellTitles } set { core.shellTitles = newValue } _modify { yield &core.shellTitles } }
    public var openDocumentsByProject: [String: [String]] { get { core.openDocumentsByProject } set { core.openDocumentsByProject = newValue } _modify { yield &core.openDocumentsByProject } }
    public var consoleTabOrder: [String: [String]] { get { core.consoleTabOrder } set { core.consoleTabOrder = newValue } _modify { yield &core.consoleTabOrder } }
    public var showHiddenFiles: Bool { get { core.showHiddenFiles } set { core.showHiddenFiles = newValue } _modify { yield &core.showHiddenFiles } }
    public var formatBarHidden: Bool { get { core.formatBarHidden } set { core.formatBarHidden = newValue } _modify { yield &core.formatBarHidden } }
    public var sourceDocuments: Set<String> { get { core.sourceDocuments } set { core.sourceDocuments = newValue } _modify { yield &core.sourceDocuments } }
    public var expandedFolders: [String: Set<String>] { get { core.expandedFolders } set { core.expandedFolders = newValue } _modify { yield &core.expandedFolders } }
    public var browseRoots: [String: URL] { get { core.browseRoots } set { core.browseRoots = newValue } _modify { yield &core.browseRoots } }
    public var browseExpanded: [String: Set<String>] { get { core.browseExpanded } set { core.browseExpanded = newValue } _modify { yield &core.browseExpanded } }
    public var lastConsoleTab: [String: String] { get { core.lastConsoleTab } set { core.lastConsoleTab = newValue } _modify { yield &core.lastConsoleTab } }
    public var lastRightTab: [String: String] { get { core.lastRightTab } set { core.lastRightTab = newValue } _modify { yield &core.lastRightTab } }
    public var terminalsMode: TerminalsMode { get { core.terminalsMode } set { core.terminalsMode = newValue } _modify { yield &core.terminalsMode } }
    public var terminals: TerminalStore { core.terminals }
    public var chats: ChatStore { get { core.chats } set { core.chats = newValue } _modify { yield &core.chats } }
    var reviewDeliveries: [String: ReviewDelivery] { get { core.reviewDeliveries } set { core.reviewDeliveries = newValue } _modify { yield &core.reviewDeliveries } }
    var reviewLastEditor: [String: String] { get { core.reviewLastEditor } set { core.reviewLastEditor = newValue } _modify { yield &core.reviewLastEditor } }
    var reviewSending: Set<String> { get { core.reviewSending } set { core.reviewSending = newValue } _modify { yield &core.reviewSending } }
    public var webTabs: [String: WebTab] { get { core.webTabs } set { core.webTabs = newValue } _modify { yield &core.webTabs } }
    public var downloads: [DownloadRecord] { get { core.downloads } set { core.downloads = newValue } _modify { yield &core.downloads } }
    public var converting: [String: (fraction: Double, stage: String)] { get { core.converting } set { core.converting = newValue } _modify { yield &core.converting } }
    var conversionTasks: [String: Task<Void, Never>] { get { core.conversionTasks } set { core.conversionTasks = newValue } _modify { yield &core.conversionTasks } }
    public var conversionFailures: [String: Docx.Failure] { get { core.conversionFailures } set { core.conversionFailures = newValue } _modify { yield &core.conversionFailures } }
    public var conversions: [String: DocxConversion] { get { core.conversions } set { core.conversions = newValue } _modify { yield &core.conversions } }
    public var minute: Date { core.minute }
    public var liveRoot: URL? { get { core.liveRoot } set { core.liveRoot = newValue } _modify { yield &core.liveRoot } }
    public var homeFolderList: [URL] { get { core.homeFolderList } set { core.homeFolderList = newValue } _modify { yield &core.homeFolderList } }
    public var isLive: Bool { get { core.isLive } set { core.isLive = newValue } _modify { yield &core.isLive } }
    var notified: Set<String> { get { core.notified } set { core.notified = newValue } _modify { yield &core.notified } }
    public var sparkleCheck: (() -> Void)? { get { core.sparkleCheck } set { core.sparkleCheck = newValue } _modify { yield &core.sparkleCheck } }
    public var repos: [String: RepoView] { get { core.repos } set { core.repos = newValue } _modify { yield &core.repos } }
    var repoChecked: [String: Date] { get { core.repoChecked } set { core.repoChecked = newValue } _modify { yield &core.repoChecked } }
    var repoRefreshing: Set<String> { get { core.repoRefreshing } set { core.repoRefreshing = newValue } _modify { yield &core.repoRefreshing } }
    public var restoreEnabled: Bool { get { core.restoreEnabled } set { core.restoreEnabled = newValue } _modify { yield &core.restoreEnabled } }
    public var parkedTabs: Set<String> { get { core.parkedTabs } set { core.parkedTabs = newValue } _modify { yield &core.parkedTabs } }
    public var detachedForks: Set<String> { get { core.detachedForks } set { core.detachedForks = newValue } _modify { yield &core.detachedForks } }
    var startSources: [String: String] { get { core.startSources } set { core.startSources = newValue } _modify { yield &core.startSources } }
    var forksSeen: Set<String>? { get { core.forksSeen } set { core.forksSeen = newValue } _modify { yield &core.forksSeen } }
    public var keepRunningIDs: Set<String> { get { core.keepRunningIDs } set { core.keepRunningIDs = newValue } _modify { yield &core.keepRunningIDs } }
    public var parkChildren: (Int32) -> [[String]] { get { core.parkChildren } set { core.parkChildren = newValue } _modify { yield &core.parkChildren } }
    public var parkEvents: (String) -> [HookEvents.Event] { get { core.parkEvents } set { core.parkEvents = newValue } _modify { yield &core.parkEvents } }
    public var parkPressure: ParkPressure? { get { core.parkPressure } set { core.parkPressure = newValue } _modify { yield &core.parkPressure } }
    var pressureSource: DispatchSourceMemoryPressure? { get { core.pressureSource } set { core.pressureSource = newValue } _modify { yield &core.pressureSource } }
    var restoreApplied: Bool { get { core.restoreApplied } set { core.restoreApplied = newValue } _modify { yield &core.restoreApplied } }
    var lastRestoreSave: Date { get { core.lastRestoreSave } set { core.lastRestoreSave = newValue } _modify { yield &core.lastRestoreSave } }
    var lastRestoreData: Data? { get { core.lastRestoreData } set { core.lastRestoreData = newValue } _modify { yield &core.lastRestoreData } }
    public var liveFolders: [String: URL] { get { core.liveFolders } set { core.liveFolders = newValue } _modify { yield &core.liveFolders } }
    public var liveElsewhere: Set<String> { get { core.liveElsewhere } set { core.liveElsewhere = newValue } _modify { yield &core.liveElsewhere } }
    public var submitHooks: SubmitIO? { get { core.submitHooks } set { core.submitHooks = newValue } _modify { yield &core.submitHooks } }
    public var interactivePrompts: Bool { get { core.interactivePrompts } set { core.interactivePrompts = newValue } _modify { yield &core.interactivePrompts } }
    public var seen: [String: Double] { get { core.seen } set { core.seen = newValue } _modify { yield &core.seen } }
    public var rememberedHome: String? { get { core.rememberedHome } set { core.rememberedHome = newValue } _modify { yield &core.rememberedHome } }
    public var extraProjects: [URL] { get { core.extraProjects } set { core.extraProjects = newValue } _modify { yield &core.extraProjects } }
    public var documentsExists: Bool? { get { core.documentsExists } set { core.documentsExists = newValue } _modify { yield &core.documentsExists } }
    public var startFolders: [String] { get { core.startFolders } set { core.startFolders = newValue } _modify { yield &core.startFolders } }
    public var startFoldersPresent: Set<String> { get { core.startFoldersPresent } set { core.startFoldersPresent = newValue } _modify { yield &core.startFoldersPresent } }
    var taskTitlesSeen: [String: String]? { get { core.taskTitlesSeen } set { core.taskTitlesSeen = newValue } _modify { yield &core.taskTitlesSeen } }
    public var taskStatusSeen: [String: Bool]? { get { core.taskStatusSeen } set { core.taskStatusSeen = newValue } _modify { yield &core.taskStatusSeen } }
}

extension AppModel {
    /// The open project's session list as shown: held still while the pointer is in it (Q-80).
    public func sidebarSections() -> [SidebarSection] {
        guard let p = currentProject?.name else { return [] }
        let fresh = SidebarRow.sections(for: p, in: fixture, isOpen: { hasOpenTerminal($0) }, isPinned: { isKeepRunning($0) },
                                        director: directorSlotInfo(project: p), listedTask: { listedTask($0) })
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
