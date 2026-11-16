import AppKit
import Foundation
import DuoControl

/// Restore on relaunch (LR-58): what was open when Duo quit comes back. Written on quit and every
/// few seconds while live (so a crash loses little), to its own versioned file; a file Duo can't
/// read, or one from a newer Duo, is ignored rather than trusted (graceful downgrade). Only for the
/// same Home: a run on another workspace (the acceptance fixtures) neither reads nor replaces it.
public struct RestoreState: Codable, Equatable, Sendable {
    /// 2 adds `windows` (DL-351); 1 is the one-window file.
    public static let version = 2
    public var version = RestoreState.version
    /// Home's folder for the run that wrote it; nil with no Home.
    public var root: String?
    /// The project on screen, by folder; nil at All projects.
    public var project: String?
    public var leftCollapsedProject = false
    /// Old files carry All projects' sidebar state; All projects has no sidebar now (DL-336), so they decode and are ignored.
    public var leftCollapsedAllProjects: Bool? = nil
    public var leftTouchedAllProjects: Bool? = nil
    /// The right pane hidden (DL-129); absent in files from before it.
    public var rightCollapsedAllProjects: Bool? = nil
    public var rightCollapsedProject: Bool? = nil
    /// Home's session on screen.
    public var homeTab: String?
    public var projects: [Project] = []
    /// What a split took to make room (DL-276), so it can be given back; absent with no split.
    public var splitRoom: SplitRoom.Taken? = nil
    /// The window set (DL-351, multi-window slice 2): every window at quit, the primary first. The top-level
    /// fields above stay the primary window's, as v1 wrote them. Absent in v1 files: one window.
    public var windows: [Window]? = nil

    public init() {}

    /// One window: its number, project, colour, frame and panes. Its project's tabs and documents are in `projects`.
    public struct Window: Codable, Equatable, Sendable {
        public var number: Int
        /// The project it shows, by folder; nil at All projects.
        public var project: String?
        /// Its colour (a `DuoWindowColour` id); nil is None.
        public var colour: String?
        /// Its frame, x, y, width, height in AppKit's screen coordinates; nil: where AppKit puts it.
        public var frame: [Double]? = nil
        /// The key window at quit: it comes forward last.
        public var key: Bool? = nil
        public var leftCollapsedProject: Bool? = nil
        public var rightCollapsedAllProjects: Bool? = nil
        public var rightCollapsedProject: Bool? = nil
        public var homeTab: String? = nil
        public var splitRoom: SplitRoom.Taken? = nil

        public init(number: Int, project: String?, colour: String?) { self.number = number; self.project = project; self.colour = colour }

        public var rect: CGRect? {
            guard let f = frame, f.count == 4, f[2] > 0, f[3] > 0 else { return nil }
            return CGRect(x: f[0], y: f[1], width: f[2], height: f[3])
        }

        /// Where a saved frame opens: where it was while a screen shows enough of its title bar to grab
        /// (100 × 20 pt); else moved fully onto the screen it overlaps most (the first if none), shrunk to fit.
        public static func placed(_ frame: CGRect, screens: [CGRect]) -> CGRect {
            guard !screens.isEmpty else { return frame }
            let titleBar = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
            if screens.contains(where: { s in let i = s.intersection(titleBar); return !i.isNull && i.width >= 100 && i.height >= 20 }) { return frame }
            func overlap(_ s: CGRect) -> CGFloat { let i = s.intersection(frame); return i.isNull ? 0 : i.width * i.height }
            let screen = screens.max { overlap($0) < overlap($1) }!
            var r = frame
            r.size.width = min(r.width, screen.width)
            r.size.height = min(r.height, screen.height)
            r.origin.x = min(max(r.minX, screen.minX), screen.maxX - r.width)
            r.origin.y = min(max(r.minY, screen.minY), screen.maxY - r.height)
            return r
        }
    }

    /// The last v1 file, kept once when Duo first writes v2. An older Duo ignores a v2 file (it's newer than it
    /// reads) and opens one window with nothing restored; renaming this to `restore-<key>.json` gives it back.
    public static func backupFile(root: String?) -> URL {
        file(root: root).deletingPathExtension().appendingPathExtension("v1.json")
    }

    public struct Project: Codable, Equatable, Sendable {
        public var folder: String
        /// Claude sessions with a tab open, by session id, in tab order.
        public var sessions: [String]
        public var consoleTab: String?
        public var documents: [String]
        public var rightTab: String?
        /// Browser tabs among `documents` (`web:…`), by the address each had.
        public var webTabs: [String: String]? = nil
        /// The console's order where the user moved a tab (DL-220), by session id; absent otherwise.
        public var tabOrder: [String]? = nil
        /// Split tabs (DL-275; Duo Decks R10): source, preview kind, ratio, active side, fold. Validated on restore.
        public var splits: [SplitTab]? = nil

        public init(folder: String, sessions: [String], consoleTab: String?, documents: [String], rightTab: String?, webTabs: [String: String]? = nil, tabOrder: [String]? = nil) {
            self.folder = folder; self.sessions = sessions; self.consoleTab = consoleTab; self.documents = documents; self.rightTab = rightTab; self.webTabs = webTabs
            self.tabOrder = tabOrder
        }
    }

    /// One file per Home, so a run on another workspace never replaces this one's.
    public static func file(root: String?) -> URL {
        let key = root.map { r in String(r.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }, radix: 36) } ?? "no-home"
        return DuoPaths.support.appending(path: "restore-\(key).json")
    }

    public static func load(_ url: URL) -> RestoreState? {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(RestoreState.self, from: data),
              s.version <= version else { return nil }
        return s
    }
}

extension AppModel {
    /// What's open now, as a restore state: the top level is the primary window's (as v1), `windows` every window's (DL-351).
    public func currentRestoreState() -> RestoreState {
        // The app's first model may have lost its window (closed while another stayed): the primary speaks for the set.
        if let primary = core.primary, primary !== self { return primary.currentRestoreState() }
        let windows = core.models.isEmpty ? [self] : core.models
        var s = RestoreState()
        s.root = liveRoot?.path
        s.leftCollapsedProject = leftCollapsedProject
        s.rightCollapsedAllProjects = rightCollapsedAllProjects
        s.rightCollapsedProject = rightCollapsedProject
        s.homeTab = homeTab
        let current = currentProject?.name
        s.project = current.flatMap { liveFolders[$0]?.path }
        var byProject: [String: [String]] = [:]
        let parkedNow = parkedTabs.filter { terminals.existing($0) == nil }
        for key in terminals.all.filter({ $0.isLiveClaude && !$0.exited }).map(\.key) + parkedNow.sorted() {
            guard let session = session(tabKey: key), let id = session.sessionId,
                  session.project != fixture.home?.name else { continue }
            byProject[session.project, default: []].append(id)
        }
        // Every project with something open or a tab remembered (DL-107), not only the one on screen.
        let names = Set(byProject.keys).union(openDocumentsByProject.filter { !$0.value.isEmpty }.keys).union(current.map { [$0] } ?? [])
            .union(lastConsoleTab.keys).union(lastRightTab.keys).union(windows.compactMap(\.currentProject?.name))
        for name in names.sorted() {
            guard let folder = liveFolders[name]?.path else { continue }
            let ids = Set(tabSessions(inProject: name).compactMap(\.sessionId))
            let tabs = consoleTabKeys(inProject: name).filter(ids.contains)   // in tab order, as moved (DL-220)
            let open = byProject[name] ?? []
            let docs = openDocumentsByProject[name] ?? []
            let shownIn = windows.first { $0.currentProject?.name == name }   // the window on it has its live tabs (DL-308: one)
            let web = Dictionary(docs.compactMap { d in webTabs[d]?.url.map { (d, $0.absoluteString) } }, uniquingKeysWith: { a, _ in a })
            s.projects.append(.init(folder: folder, sessions: tabs.filter(open.contains) + open.filter { !tabs.contains($0) },
                                    consoleTab: shownIn.map(\.consoleTab) ?? lastConsoleTab[name],
                                    documents: docs.filter { !$0.hasPrefix("web:") || web[$0] != nil },
                                    rightTab: shownIn.map(\.rightTab) ?? lastRightTab[name], webTabs: web.isEmpty ? nil : web,
                                    tabOrder: consoleTabOrder[name].map { $0.filter(ids.contains) }.flatMap { $0.isEmpty ? nil : $0 }))
            s.projects[s.projects.count - 1].splits = splitsForRestore(name)
        }
        s.splitRoom = splits.any ? splits.taken : nil
        s.windows = windows.map { m in
            var w = RestoreState.Window(number: m.windowNumber, project: m.currentProject.flatMap { liveFolders[$0.name]?.path }, colour: m.windowColourID)
            if let f = m.window?.frame ?? m.restoreFrame { w.frame = [f.minX, f.minY, f.width, f.height].map { Double($0) } }
            if core.keyWindowID != nil, m.windowID == core.keyWindowID { w.key = true }
            w.leftCollapsedProject = m.leftCollapsedProject
            w.rightCollapsedAllProjects = m.rightCollapsedAllProjects
            w.rightCollapsedProject = m.rightCollapsedProject
            w.homeTab = m.homeTab
            w.splitRoom = m.splits.any ? m.splits.taken : nil
            return w
        }
        return s
    }

    /// The save at quit (DL-351): made when the quit is asked, before AppKit closes the windows, and nothing is
    /// written after it, so windows closing on the way out don't drop from the set.
    public func saveRestoreStateForQuit() {
        guard !core.restoreFrozen else { return }
        saveRestoreState(force: true)
        core.restoreFrozen = true
    }

    /// Writes the restore file when it changed (quit, and at most every few seconds from the refresh).
    public func saveRestoreState(force: Bool = false) {
        guard restoreEnabled, isLive, restoreApplied, !core.restoreFrozen else { return }
        if !force, Date().timeIntervalSince(lastRestoreSave) < 5 { return }
        lastRestoreSave = Date()
        guard let data = try? JSONEncoder().encode(currentRestoreState()), data != lastRestoreData else { return }
        lastRestoreData = data
        try? FileManager.default.createDirectory(at: DuoPaths.support, withIntermediateDirectories: true)
        let file = RestoreState.file(root: liveRoot?.path)
        // Once, before v2 first replaces a v1 file: keep it for an older Duo (DL-351).
        if !core.restoreBackupChecked {
            core.restoreBackupChecked = true
            let backup = RestoreState.backupFile(root: liveRoot?.path)
            if let old = try? Data(contentsOf: file), !FileManager.default.fileExists(atPath: backup.path),
               let v = (try? JSONSerialization.jsonObject(with: old)) as? [String: Any], (v["version"] as? Int ?? 1) < 2 {
                try? old.write(to: backup, options: .atomic)
            }
        }
        try? data.write(to: file, options: .atomic)
    }

    /// Reopens what the last run had open, once the first snapshot has the sessions. Sessions now
    /// running in another app stay there (never two writers, LR-8); missing ones are skipped.
    public func applyRestore() {
        defer { restoreApplied = true }
        guard restoreEnabled, let s = RestoreState.load(RestoreState.file(root: liveRoot?.path)), s.root == liveRoot?.path else { return }
        let resolve = { (p: String) in URL(fileURLWithPath: p).realPath }
        func name(_ folder: String) -> String? { liveFolders.first { resolve($0.value.path) == resolve(folder) }?.key }
        var reopened = 0, started = 0
        for p in s.projects {
            guard let project = name(p.folder), let folder = liveFolders[project] else { continue }
            let docs = p.documents.filter { d in
                if d.hasPrefix("web:") { return p.webTabs?[d].flatMap(URL.init(string:)) != nil }
                // A file outside the project (DL-106) is kept by its own path.
                if Self.isOutsideFile(d) { return FileManager.default.fileExists(atPath: String(d.dropFirst(Self.outsideFilePrefix.count))) }
                return Self.contained(d, in: folder).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            }
            for d in docs where d.hasPrefix("web:") {
                guard let u = p.webTabs?[d].flatMap(URL.init(string:)) else { continue }
                let tab = WebTab(id: d)
                tab.fileRoots = [folder]
                wireWebTab(tab)
                webTabs[d] = tab
                tab.defer_(u)   // loads when the tab is first shown (C-83)
            }
            if !docs.isEmpty { openDocumentsByProject[project] = docs }
            if let order = p.tabOrder, !order.isEmpty { consoleTabOrder[project] = order }
            // The tabs it showed, for coming back to it (DL-107).
            if let t = p.consoleTab { lastConsoleTab[project] = t }
            if let r = p.rightTab, r == "Project" || docs.contains(r) { lastRightTab[project] = r }
            restoreSplits(p.splits, project: project, documents: docs)
            // Parked, not resumed (DL-156): each resumes when its tab is shown, so a launch starts
            // what's on screen, not one sign-in per tab at once (F-208).
            for id in p.sessions where !liveElsewhere.contains(id) {
                guard let key = fixture.sessions(inProject: project).first(where: { $0.sessionId == id })?.tabKey else { continue }
                // Keep Running (DL-192): started now, not when shown.
                if keepRunningIDs.contains(id) { if terminal(project: project, session: key) != nil { started += 1 }; continue }
                parkedTabs.insert(key)
                reopened += 1
            }
        }
        if let h = s.homeTab, let home = fixture.home?.name, fixture.sessions(inProject: home).contains(where: { $0.tabKey == h }) { homeTab = h }
        leftCollapsedProject = s.leftCollapsedProject
        rightCollapsedAllProjects = s.rightCollapsedAllProjects ?? false
        rightCollapsedProject = s.rightCollapsedProject ?? false
        if let folder = s.project, let project = name(folder), let p = s.projects.first(where: { resolve($0.folder) == resolve(folder) }) {
            open(project: project)
            if let tab = p.consoleTab, fixture.sessions(inProject: project).contains(where: { $0.tabKey == tab }) { consoleTab = tab }
            else if p.consoleTab != nil || consoleTab == nil { consoleTab = consoleTabKeys(inProject: project).first }   // its tab was a shell, now gone: the first, never none
            if let right = p.rightTab, right == "Project" || (openDocumentsByProject[project] ?? []).contains(right) {
                rightTab = right
                if right != "Project" { selectedFile = right }
            }
        }
        restoreRoom(s.splitRoom)
        if let ws = s.windows { restoreWindows(ws, name: name) }
        FileHandle.standardError.write(Data("restore: parked \(reopened) session(s) in \(s.projects.count) project(s)\n".utf8))
        if started > 0 { FileHandle.standardError.write(Data("restore: resumed \(started) Keep Running session(s) at once\n".utf8)) }
    }

    /// The window set (DL-351): this (the primary) takes the first window's colour, frame and panes; each other
    /// window opens under its number, on its project (at All projects when the project's folder is gone, or
    /// another window already shows it, DL-308), in its colour and frame. The key window comes forward last.
    func restoreWindows(_ ws: [RestoreState.Window], name: (String) -> String?) {
        guard let mine = ws.first else { return }
        windowColourID = mine.colour
        if let f = mine.rect { restoreFrame = f; placeRestoredFrame() }
        var key: AppModel? = mine.key == true ? self : nil
        for w in ws.dropFirst() {
            let project = w.project.flatMap(name)
            if let folder = w.project, project == nil {
                FileHandle.standardError.write(Data("restore: window \(w.number)'s project folder \(folder) is gone; it opens at All projects\n".utf8))
            }
            if let p = project, core.model(showing: p) != nil {
                FileHandle.standardError.write(Data("restore: \(p) is already in a window (DL-308); window \(w.number) is left closed\n".utf8))
                continue
            }
            let number = w.number >= 1 && core.model(number: w.number) == nil ? w.number : core.freeWindowNumber()
            let m = core.openRestoredWindow(number: number, colour: w.colour, frame: w.rect) { m in
                m.leftCollapsedProject = w.leftCollapsedProject ?? false
                m.rightCollapsedAllProjects = w.rightCollapsedAllProjects ?? false
                m.rightCollapsedProject = w.rightCollapsedProject ?? false
                if let h = w.homeTab { m.homeTab = h }
                if let p = project {
                    m.open(project: p)
                    if let tab = lastConsoleTab[p], fixture.sessions(inProject: p).contains(where: { $0.tabKey == tab }) { m.consoleTab = tab }
                    if let right = lastRightTab[p], right == "Project" || (openDocumentsByProject[p] ?? []).contains(right) {
                        m.rightTab = right
                        if right != "Project" { m.selectedFile = right }
                    }
                    m.restoreRoom(w.splitRoom)
                }
            }
            if w.key == true { key = m }
        }
        if ws.count > 1 { FileHandle.standardError.write(Data("restore: \(core.models.count) window(s)\n".utf8)) }
        if let key, ws.count > 1 { core.bringForward(key) }
    }

    /// Puts the window at its restored frame, on a screen (a frame off every screen is moved on, DL-351).
    public func placeRestoredFrame() {
        guard let f = restoreFrame, let window else { return }
        let placed = RestoreState.Window.placed(f, screens: NSScreen.screens.map(\.visibleFrame))
        window.setFrame(placed, display: false)
    }
}
