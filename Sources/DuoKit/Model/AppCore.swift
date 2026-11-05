import AppKit
import DuoControl
import DuoSearch
import Foundation
import Observation

/// What the whole app shares, whatever window shows it (multi-window slice 0, F-537, C-146): the
/// projects and sessions, terminals and chats, the live loop and its app-wide passes, restore,
/// settings, and each project's memory (its open documents, last tabs, shells, web tabs, split
/// tabs). One per process. Each window's `AppModel` holds `core` and forwards these, so its views
/// and `duo2` handlers read them as before. With one window, behaviour is main's.
@MainActor
@Observable
public final class AppCore {
    /// The app's core, for code outside any window (DuoAlert, the harness's window lookups): the
    /// last one made, which in the app is the only one.
    public private(set) static weak var current: AppCore?

    // MARK: - Windows

    struct WeakModel { weak var model: AppModel? }
    @ObservationIgnored var registered: [WeakModel] = []
    /// The window models, oldest first. The first is the primary window: where `duo2` lands with
    /// no session to go by, and the model the app-wide passes run through (Q-430).
    public var models: [AppModel] { registered.compactMap(\.model) }
    public var primary: AppModel? { registered.lazy.compactMap(\.model).first }
    /// The window that is key, as its model's `windowID`; `MainWindow` sets it (menus act on it).
    public var keyWindowID: ObjectIdentifier?
    /// The model whose window is key, else the primary: what the menus and the Dock act on.
    public var keyModel: AppModel? {
        let all = models
        return all.first { $0.windowID != nil && $0.windowID == keyWindowID } ?? all.first
    }

    func attach(_ m: AppModel) {
        registered.removeAll { $0.model == nil || $0.model === m }
        registered.append(WeakModel(model: m))
    }

    /// The model drawing `window`, by identity (never by title).
    public func model(for window: NSWindow?) -> AppModel? {
        guard let window else { return nil }
        return models.first { $0.window === window }
    }

    public func model(forWindowNumber number: Int) -> AppModel? {
        models.first { $0.window?.windowNumber == number }
    }

    /// Where a question shows (SheetCenter): its own window; else a window showing its project;
    /// else the key window's model, else the primary.
    public func model(for target: QuestionTarget) -> AppModel? {
        switch target {
        case .window(let id): return models.first { $0.windowID == id } ?? keyModel
        case .project(let p): return models.first { $0.altitude == .project(p) } ?? keyModel
        case .any: return keyModel
        }
    }

    /// `duo2` requests (Q-430): `--window <n|project>`, else the window showing the caller's session, else
    /// the primary window; never the key window (`AppCore+Windows.swift`, `target(for:)`).
    public func handle(_ req: ControlRequest, done: @escaping @MainActor (ControlResponse) -> Void) {
        let t = target(for: req)
        if let e = t.error { return done(ControlResponse(ok: false, output: e)) }
        guard let m = t.model else { return done(ControlResponse(ok: false, output: "Duo has no window")) }
        m.handle(t.request, done: done)
    }

    // MARK: - The window set (multi-window slice 1, AppCore+Windows.swift)

    /// Made by the app: a window for a new model (`MainWindow`); brings one forward; closes or hides one.
    /// Nil in the checks, which drive the models alone.
    @ObservationIgnored public var windowMaker: ((AppModel) -> Void)?
    @ObservationIgnored public var windowFocuser: ((AppModel) -> Void)?
    @ObservationIgnored public var windowCloser: ((AppModel) -> Void)?
    @ObservationIgnored public var windowHider: ((AppModel) -> Void)?
    /// The windows brought forward, by number, oldest first (the checks read it).
    @ObservationIgnored public internal(set) var focusLog: [Int] = []
    /// The windows `openWindow` made, held until they close (the first window is the app's own).
    @ObservationIgnored var opened: [AppModel] = []
    /// Windows the user closed while they were the last (they only hid), by model (Q-460).
    @ObservationIgnored var hiddenWindows: Set<ObjectIdentifier> = []
    /// Home's window (Q-431), by number; nil is the primary.
    public internal(set) var homeOwnerNumber: Int?
    var colourNewWindowsSetting = DuoState.load().colourNewWindows
    /// Classic is on (DL-252): window colours are off (DL-312). Kept in step with `DuoScheme.classicActive`.
    public internal(set) var classicOn = DuoScheme.classicActive

    // MARK: - Counts for the checks (C-146): how many times each app-wide pass ran

    @ObservationIgnored public private(set) var passCounts: [String: Int] = [:]
    func count(_ pass: String) { passCounts[pass, default: 0] += 1 }

    public init(fixture: Fixture) {
        self.fixture = fixture
        Self.current = self
        NotificationCenter.default.addObserver(forName: DuoScheme.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.classicOn = DuoScheme.classicActive }
        }
        // A terminal's process ended by itself: once for the app, not once per window.
        terminals.onEnded = { [weak self] t in
            guard let self else { return }
            self.endedRevision += 1
            self.primary?.shellEnded(t)
        }
    }

    /// The live loop (C-146): one 2 s refresh and one minute clock for the app, however many windows
    /// start live. Each tick runs through the primary window's model.
    public func startLoop() {
        guard refreshTimer == nil else { return }
        count("loop")
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.minute = Date() }
        }.loose()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }.loose()
    }

    /// Stops the loop (the checks).
    public func stopLoop() {
        refreshTimer?.invalidate(); refreshTimer = nil
        minuteTimer?.invalidate(); minuteTimer = nil
    }

    /// What a refresh reads (off the main thread): Claude's logs, the beacons and Home's folders.
    /// The checks put a stand-in here, so a refresh runs without touching real folders.
    @ObservationIgnored public var snapshotSource: @Sendable (LiveSnapshot.Context, [Beacon]) -> (Fixture, folders: [String: URL], moves: [LiveSnapshot.Move]) = {
        LiveSnapshot.build($0, beacons: $1)
    }

    /// One tick of the loop: the refresh, then the trust screens (DL-229).
    public func tick() {
        guard let p = primary else { return }
        p.refreshLive()
        count("trust")
        p.scanTrustNotices()
    }

    /// Voice input (DL-260): one microphone for the app, made and wired by the first window that asks.
    @ObservationIgnored var voiceInput: VoiceInput?
    /// The window that started the running dictation (C-150): the host's callbacks reach its composer or editor.
    @ObservationIgnored weak var voiceWindow: AppModel?

    /// Split tabs by project (DL-275): a project's split follows it to whichever window shows it.
    public let splitTabs = SplitTabs()

    // MARK: - App-wide and per-project state (AppModel forwards each)

    public var fixture: Fixture { didSet { sessionSlots = nil } }
    /// Each session's index in `fixture.sessions` by tab key, built on first use after the fixture changes (F-598): the
    /// session list looked each row's session up by a linear scan, 6,150² comparisons a refresh on a heavy Home.
    @ObservationIgnored private var sessionSlots: [String: Int]?
    /// The first session with this tab key, as `fixture.sessions.first { $0.tabKey == key }` gives it.
    func session(tabKey key: String) -> Fixture.Session? {
        let ss = fixture.sessions
        if let i = sessionSlots?[key], i < ss.count, ss[i].tabKey == key { return ss[i] }
        if sessionSlots == nil || sessionSlots?[key] != nil {   // never built, or a slot that no longer holds its key
            var slots: [String: Int] = [:]
            for (i, s) in ss.enumerated() where slots[s.tabKey] == nil { slots[s.tabKey] = i }
            sessionSlots = slots
        }
        return sessionSlots?[key].map { ss[$0] }
    }
    /// Linked GitHub issues' live state, by the issue's URL (DL-226); read through gh, cached.
    public var issueStates: [String: IssueState] = [:]
    @ObservationIgnored var issueFetched: [String: Date] = [:]
    /// Folders whose old-named files were looked at this launch (DL-259).
    @ObservationIgnored var movesChecked: Set<String> = []
    @ObservationIgnored var issueFetching: Set<String> = []
    @ObservationIgnored var issueRepos: [String: RemoteRepo?] = [:]
    /// Counts changes Duo shows before the snapshot does (Q-78). A snapshot started before the
    /// latest one is stale: it would put the old state back for a beat, so it's dropped.
    @ObservationIgnored var localChange = 0
    /// `.duo/director.json` as last read, by project, with its modification time: the sidebar asks on every draw.
    @ObservationIgnored var directorRegistryCache: [String: (modified: Date, reg: DirectorRegistry)] = [:]
    /// Bumped when a terminal's process ends by itself, so the console shows its bar (DB-3).
    public var endedRevision = 0
    /// Archived projects' folders (ENH-6), and whether the rollup is open.
    public var archivedProjectPaths: [String] = DuoState.load().archivedProjects
    /// Sessions whose `/fork` Claude Code refused for an untrusted folder, by tab key (DL-229). In memory only.
    public var trustNotices: [String: TrustNotice] = [:]
    /// Plain shells open in each project's console, by key, in the order opened (DB-4).
    public var shellTabs: [String: [String]] = [:]
    /// What each shell is running, for its tab's title.
    public var shellTitles: [String: String] = [:]
    /// Open document tabs by project (DL-60): switching to Project no longer closes them.
    public var openDocumentsByProject: [String: [String]] = [:]
    /// The console's tab order by project, where the user moved a tab (ENH-042, DL-220): tab keys,
    /// applied over sessions-then-shells by `TabOrder.apply`. Empty until a tab is moved.
    public var consoleTabOrder: [String: [String]] = [:]
    /// The file tree (DL-105): hidden files on or off, and the folders open in each project's tree.
    public var showHiddenFiles = DuoState.load().showHiddenFiles
    /// View › Hide Formatting Bar (DL-266): the Markdown bar over the editor, remembered.
    public var formatBarHidden = DuoState.load().formatBarHidden
    /// Documents shown in Source mode (DL-167), by standardized path; remembered.
    public var sourceDocuments = Set(DuoState.load().sourceDocuments)
    public var expandedFolders: [String: Set<String>] = [:]
    /// The folder the tree shows when it has gone up from the project's (DL-106, Q-162), by project; none = the project's own.
    public var browseRoots: [String: URL] = [:]
    /// Folders opened while browsing up, as paths from that browse root.
    public var browseExpanded: [String: Set<String>] = [:]
    /// The console and right-pane tab each project showed when the user left it (DL-107).
    public var lastConsoleTab: [String: String] = [:]
    public var lastRightTab: [String: String] = [:]
    public var terminalsMode: TerminalsMode = .off
    @ObservationIgnored public let terminals = TerminalStore()
    /// Chat mode (DL-118 to DL-120): each Claude session's chat over its terminal.
    @ObservationIgnored public lazy var chats = ChatStore()
    /// @claude comments in flight, by "<file>#<thread>" (DL-236 10A); who last edited a document through Duo, by file.
    @ObservationIgnored var reviewDeliveries: [String: ReviewDelivery] = DuoState.load().reviewDeliveries
    @ObservationIgnored var reviewLastEditor: [String: String] = [:]
    @ObservationIgnored var reviewSending: Set<String> = []
    /// Browser tabs by id (`web:…`), kept alive while their tab is open (Phase K, ENH-8).
    @ObservationIgnored public var webTabs: [String: WebTab] = [:]
    /// Downloads browser tabs saved since launch, oldest first (`duo2 browser downloads`, DL-124).
    @ObservationIgnored public var downloads: [DownloadRecord] = []
    /// Word documents being converted to Markdown (DL-123), by the .docx's tab: how far, and what
    /// it's doing. Set only once a conversion has taken half a second, so a quick one shows nothing.
    public var converting: [String: (fraction: Double, stage: String)] = [:]
    @ObservationIgnored var conversionTasks: [String: Task<Void, Never>] = [:]
    /// Why a .docx couldn't be converted, by its tab, until it's converted or closed (F, F2).
    public var conversionFailures: [String: Docx.Failure] = [:]
    /// The notice on a Markdown copy just made (D, E), by its tab, until OK.
    public var conversions: [String: DocxConversion] = [:]
    /// The time views cut relative labels by (`4m`, age buckets, activity order, `fetched … ago`). It moves once a
    /// minute, so an idle refresh that changes nothing needn't republish `fixture` to keep them right (C-79).
    public internal(set) var minute = Date()
    /// Home's folder (DL-85); nil until one is chosen. Live mode runs either way (DL-82).
    public var liveRoot: URL?
    /// The folders in Home that aren't projects (`homeFolders(root:)`), read with each refresh: All
    /// projects offers them when Home has no projects yet (DL-212).
    public var homeFolderList: [URL] = []
    @ObservationIgnored public var isLive = false
    /// Sessions already notified for their current wait (S3-6).
    @ObservationIgnored var notified = Set<String>()
    /// Sparkle's "Check for Updates", when the app started it (release builds).
    @ObservationIgnored public var sparkleCheck: (() -> Void)?
    /// Each project's repository, when its folder is in one (DL-149, DL-157), by project name.
    public var repos: [String: RepoView] = [:]
    @ObservationIgnored var repoChecked: [String: Date] = [:]
    @ObservationIgnored var repoRefreshing: Set<String> = []
    /// Restore on relaunch (LR-58): off for scripted and capture runs.
    @ObservationIgnored public var restoreEnabled = false
    /// DL-156: see `tabSessions`.
    public var parkedTabs: Set<String> = []
    /// `/fork`s whose attach tab was closed: the fork runs on in Claude's background (DL-227), its row stays,
    /// and its tab is gone until the row is opened again.
    public var detachedForks: Set<String> = []
    /// SessionStart sources the hook reported, by new session id (`duo2 hook context`): `fork` tells `/branch` from `/clear`.
    @ObservationIgnored var startSources: [String: String] = [:]
    /// `/fork` jobs Duo has already seen (the first scan sets the baseline: only a fork made after Duo is looking opens a tab).
    @ObservationIgnored var forksSeen: Set<String>?
    /// Sessions set to Keep Running (DL-192), by session id: never parked, resumed at launch.
    public var keepRunningIDs: Set<String> = []
    /// What the park check reads, replaceable in checks: a process's children (argv each), a session's hook events.
    @ObservationIgnored public var parkChildren: (Int32) -> [[String]] = { ProcessTable.children(of: $0) }
    @ObservationIgnored public var parkEvents: (String) -> [HookEvents.Event] = { HookEvents.read($0) }
    @ObservationIgnored public var parkPressure: ParkPressure?
    @ObservationIgnored var pressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored var restoreApplied = false
    @ObservationIgnored var lastRestoreSave = Date.distantPast
    @ObservationIgnored var lastRestoreData: Data?
    @ObservationIgnored public var liveFolders: [String: URL] = [:]
    /// Live sessions whose process Duo doesn't own (Terminal, the Desktop app, another Duo).
    public var liveElsewhere: Set<String> = []
    /// The checks' stand-in for a terminal in a guarded submit (@claude review comments); nil in the app.
    public var submitHooks: AppModel.SubmitIO?
    @ObservationIgnored var refreshTimer: Timer?
    @ObservationIgnored var minuteTimer: Timer?
    @ObservationIgnored var refreshing = false
    @ObservationIgnored var lastArchive = Date.distantPast
    /// False for scripted captures: nothing may block on a prompt.
    @ObservationIgnored public var interactivePrompts = true
    /// Duo's "seen" marks (handoff §10): looking at a session clears ready-for-review.
    @ObservationIgnored public var seen: [String: Double] = [:]
    @ObservationIgnored public var rememberedHome: String?
    /// Projects outside the workspace root (DL-63), from Duo's state.
    @ObservationIgnored public var extraProjects: [URL] = []
    /// Whether `~/Documents` exists, read off the main thread with each refresh (DL-262); nil until read.
    /// The New session row's default when there's no Home. Captures and checks set it.
    public var documentsExists: Bool?
    /// Folders chosen for the New session row, newest first (DL-262), from Duo's state.
    @ObservationIgnored public var startFolders: [String] = []
    /// Which of those folders are still there, read off the main thread with each refresh.
    public var startFoldersPresent: Set<String> = []
    /// Task titles as last seen, by "project/path": a title that changes moves its note to the
    /// new name's slug once it settles (DL-115, C-24).
    @ObservationIgnored var taskTitlesSeen: [String: String]?
    /// Whether each task was done when last seen, by "project/path": one that becomes done folds its sessions, one reopened unfolds them (DL-187).
    @ObservationIgnored public var taskStatusSeen: [String: Bool]?
}
