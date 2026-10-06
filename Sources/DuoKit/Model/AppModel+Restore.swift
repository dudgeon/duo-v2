import Foundation

/// Restore on relaunch (LR-58): what was open when Duo quit comes back. Written on quit and every
/// few seconds while live (so a crash loses little), to its own versioned file; a file Duo can't
/// read, or one from a newer Duo, is ignored rather than trusted (graceful downgrade). Only for the
/// same Home: a run on another workspace (the acceptance fixtures) neither reads nor replaces it.
public struct RestoreState: Codable, Equatable, Sendable {
    public static let version = 1
    public var version = RestoreState.version
    /// Home's folder for the run that wrote it; nil with no Home.
    public var root: String?
    /// The project on screen, by folder; nil at All projects.
    public var project: String?
    public var leftCollapsedAllProjects = false
    public var leftCollapsedProject = false
    /// The right pane hidden (DL-129); absent in files from before it.
    public var rightCollapsedAllProjects: Bool? = nil
    public var rightCollapsedProject: Bool? = nil
    /// Home's session on screen.
    public var homeTab: String?
    public var projects: [Project] = []

    public init() {}

    public struct Project: Codable, Equatable, Sendable {
        public var folder: String
        /// Claude sessions with a tab open, by session id, in tab order.
        public var sessions: [String]
        public var consoleTab: String?
        public var documents: [String]
        public var rightTab: String?
        /// Browser tabs among `documents` (`web:…`), by the address each had.
        public var webTabs: [String: String]? = nil

        public init(folder: String, sessions: [String], consoleTab: String?, documents: [String], rightTab: String?, webTabs: [String: String]? = nil) {
            self.folder = folder; self.sessions = sessions; self.consoleTab = consoleTab; self.documents = documents; self.rightTab = rightTab; self.webTabs = webTabs
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
    /// What's open now, as a restore state.
    public func currentRestoreState() -> RestoreState {
        var s = RestoreState()
        s.root = liveRoot?.path
        s.leftCollapsedAllProjects = leftCollapsedAllProjects
        s.leftCollapsedProject = leftCollapsedProject
        s.rightCollapsedAllProjects = rightCollapsedAllProjects
        s.rightCollapsedProject = rightCollapsedProject
        s.homeTab = homeTab
        let current = currentProject?.name
        s.project = current.flatMap { liveFolders[$0]?.path }
        var byProject: [String: [String]] = [:]
        for t in terminals.all where t.isLiveClaude && !t.exited {
            guard let session = fixture.sessions.first(where: { $0.tabKey == t.key }), let id = session.sessionId,
                  session.project != fixture.home?.name else { continue }
            byProject[session.project, default: []].append(id)
        }
        // Every project with something open or a tab remembered (DL-107), not only the one on screen.
        let names = Set(byProject.keys).union(openDocumentsByProject.filter { !$0.value.isEmpty }.keys).union(current.map { [$0] } ?? [])
            .union(lastConsoleTab.keys).union(lastRightTab.keys)
        for name in names.sorted() {
            guard let folder = liveFolders[name]?.path else { continue }
            let tabs = tabSessions(inProject: name).compactMap(\.sessionId)
            let open = byProject[name] ?? []
            let docs = openDocumentsByProject[name] ?? []
            let web = Dictionary(docs.compactMap { d in webTabs[d]?.url.map { (d, $0.absoluteString) } }, uniquingKeysWith: { a, _ in a })
            s.projects.append(.init(folder: folder, sessions: tabs.filter(open.contains) + open.filter { !tabs.contains($0) },
                                    consoleTab: name == current ? consoleTab : lastConsoleTab[name],
                                    documents: docs.filter { !$0.hasPrefix("web:") || web[$0] != nil },
                                    rightTab: name == current ? rightTab : lastRightTab[name], webTabs: web.isEmpty ? nil : web))
        }
        return s
    }

    /// Writes the restore file when it changed (quit, and at most every few seconds from the refresh).
    public func saveRestoreState(force: Bool = false) {
        guard restoreEnabled, isLive, restoreApplied else { return }
        if !force, Date().timeIntervalSince(lastRestoreSave) < 5 { return }
        lastRestoreSave = Date()
        guard let data = try? JSONEncoder().encode(currentRestoreState()), data != lastRestoreData else { return }
        lastRestoreData = data
        try? FileManager.default.createDirectory(at: DuoPaths.support, withIntermediateDirectories: true)
        try? data.write(to: RestoreState.file(root: liveRoot?.path), options: .atomic)
    }

    /// Reopens what the last run had open, once the first snapshot has the sessions. Sessions now
    /// running in another app stay there (never two writers, LR-8); missing ones are skipped.
    func applyRestore() {
        defer { restoreApplied = true }
        guard restoreEnabled, let s = RestoreState.load(RestoreState.file(root: liveRoot?.path)), s.root == liveRoot?.path else { return }
        let resolve = { (p: String) in URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        func name(_ folder: String) -> String? { liveFolders.first { resolve($0.value.path) == resolve(folder) }?.key }
        var reopened = 0
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
                wireWebTab(tab)
                webTabs[d] = tab
                tab.load(u)
            }
            if !docs.isEmpty { openDocumentsByProject[project] = docs }
            // The tabs it showed, for coming back to it (DL-107).
            if let t = p.consoleTab { lastConsoleTab[project] = t }
            if let r = p.rightTab, r == "Project" || docs.contains(r) { lastRightTab[project] = r }
            for id in p.sessions where !liveElsewhere.contains(id) {
                guard let key = fixture.sessions(inProject: project).first(where: { $0.sessionId == id })?.tabKey else { continue }
                if terminal(project: project, session: key) != nil { reopened += 1 }
            }
        }
        if let h = s.homeTab, let home = fixture.home?.name, fixture.sessions(inProject: home).contains(where: { $0.tabKey == h }) { homeTab = h }
        leftCollapsedAllProjects = s.leftCollapsedAllProjects
        leftCollapsedProject = s.leftCollapsedProject
        rightCollapsedAllProjects = s.rightCollapsedAllProjects ?? false
        rightCollapsedProject = s.rightCollapsedProject ?? false
        if let folder = s.project, let project = name(folder), let p = s.projects.first(where: { resolve($0.folder) == resolve(folder) }) {
            open(project: project)
            if let tab = p.consoleTab, fixture.sessions(inProject: project).contains(where: { $0.tabKey == tab }) { consoleTab = tab }
            if let right = p.rightTab, right == "Project" || (openDocumentsByProject[project] ?? []).contains(right) {
                rightTab = right
                if right != "Project" { selectedFile = right }
            }
        }
        FileHandle.standardError.write(Data("restore: reopened \(reopened) session(s) in \(s.projects.count) project(s)\n".utf8))
    }
}
