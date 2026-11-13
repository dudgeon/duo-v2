import Foundation

/// All projects' middle (DL-142 (1)): the map, or one list of every session.
public enum HomeView: String, CaseIterable, Sendable {
    case board, list
    public var title: String { self == .board ? "Board" : "List" }
}

/// How the List groups its sessions (DL-341): by recency (Today, This week, Earlier) or by project.
public enum ListGroup: String, CaseIterable, Sendable {
    case recent, project
    public var title: String { self == .recent ? "Recent" : "Project" }
}

/// The List at All projects (DL-142, home-evolution-handoff `list-1440`): every active and recent
/// session across projects, in a project's sections (DL-91): Open, Today, This week, then the
/// Earlier and Archived folds. Needs-you sessions are the column's (N1): the list leaves them out of
/// its sections and counts them in one line, unless the column is hidden.
public struct SessionList: Sendable, Equatable {
    public struct Row: Identifiable, Sendable, Equatable {
        public var session: Fixture.Session
        /// `★ home` for Home, the folder's path outside Home, else the project's name.
        public var project: String
        /// The task it's attributed to (DL-93), when there is one.
        public var task: String?
        /// A terminal is open for it in Duo: it reads `working` / `at prompt` (DL-133).
        public var open: Bool
        public var id: String { session.id }
        public var wait: String? { session.state.waitText(session.wait, open: open) }
    }

    public struct Section: Identifiable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var rows: [Row]
        public var needsYou = false
    }

    /// One project in the List grouped by project (DL-341): its header and its sessions, newest first.
    public struct ProjectGroup: Identifiable, Sendable, Equatable {
        /// The project's name (a folder's too): the key of its folds.
        public var id: String
        /// What the header says: `★ home` for Home, else the project's name.
        public var title: String
        /// Its folder, as `~/…`.
        public var folder: String
        public var home: Bool
        /// Every session in it, newest first.
        public var rows: [Row]
        /// Seconds since its newest session was used.
        public var newestAgo: Double
        public var count: Int { rows.count }
        /// The five shown before "n more" (Q-547).
        public var firstRows: [Row] { Array(rows.prefix(SessionList.shownPerProject)) }
        public var hiddenCount: Int { max(0, rows.count - SessionList.shownPerProject) }
    }

    public static let shownPerProject = 5
    /// Projects with nothing this week fold into Quieter projects (Q-547).
    public static let quietAfter: Double = 7 * 86400

    /// Needs you, most urgent first (the column's order).
    public var needsYou: [Row] = []
    public var sections: [Section] = []
    public var earlier: [Row] = []
    public var archived: [Row] = []
    /// The List grouped by project (DL-341): projects with a session this week, newest first, then the quiet ones.
    public var projects: [ProjectGroup] = []
    public var quietProjects: [ProjectGroup] = []

    /// The sessions, cut as a project's list is (DL-91): open in Duo first, most urgent first
    /// (DL-93); the rest by last use, newest first, into Today, This week and Earlier.
    public static func build(_ f: Fixture, isOpen: (String) -> Bool, now: Date = Date(), calendar: Calendar = .current) -> SessionList {
        // Each row's task, from one pass over the tasks and groups (F-598), as `task(of:in:)` answers it row by row.
        var taskOfID: [String: String] = [:], groupOfName: [String: String] = [:]
        for t in f.tasks ?? [] where t.archived != true {
            for id in t.sessionIds where taskOfID["\(t.project)\u{1}\(id)"] == nil { taskOfID["\(t.project)\u{1}\(id)"] = t.title }
        }
        for g in f.groups where g.task != nil {
            for n in g.sessions where groupOfName["\(g.project)\u{1}\(n)"] == nil { groupOfName["\(g.project)\u{1}\(n)"] = g.name }
        }
        func taskName(_ s: Fixture.Session) -> String? {
            s.sessionId.flatMap { taskOfID["\(s.project)\u{1}\($0)"] } ?? groupOfName["\(s.project)\u{1}\(s.name)"]
        }
        func row(_ s: Fixture.Session, open: Bool) -> Row {
            Row(session: s, project: projectLabel(s.project, in: f), task: taskName(s), open: open)
        }
        var out = SessionList()
        out.needsYou = f.needsYou.map { row($0, open: isOpen($0.tabKey)) }
        let rest = f.sessions.filter { $0.state != .needsYou }
        let opened = rest.filter { isOpen($0.tabKey) }.sorted(by: urgency).map { row($0, open: true) }
        let past = rest.filter { !isOpen($0.tabKey) }.map { (s: $0, ago: secondsAgo($0, now: now)) }.sorted { $0.ago < $1.ago }
        let sinceMidnight = now.timeIntervalSince(calendar.startOfDay(for: now))
        let today = past.filter { $0.ago <= sinceMidnight }.map { row($0.s, open: false) }
        let week = past.filter { $0.ago > sinceMidnight && $0.ago <= 7 * 86400 }.map { row($0.s, open: false) }
        out.earlier = past.filter { $0.ago > 7 * 86400 }.map { row($0.s, open: false) }
        if !opened.isEmpty { out.sections.append(Section(id: "open", title: "Open", rows: opened)) }
        if !today.isEmpty { out.sections.append(Section(id: "today", title: "Today", rows: today)) }
        if !week.isEmpty { out.sections.append(Section(id: "week", title: "This week", rows: week)) }
        // By project (DL-341, Q-547): every live session, needs-you ones too (the board draws them in their project).
        let live = f.needsYou + rest
        let byProject = Dictionary(grouping: live.map { (s: $0, ago: secondsAgo($0, now: now)) }, by: { $0.s.project })
        let groups: [ProjectGroup] = byProject.map { name, items in
            let sorted = items.sorted { $0.ago != $1.ago ? $0.ago < $1.ago : $0.s.name < $1.s.name }
            // A session whose project isn't in the list (a fixture's) still gets its header, with no folder.
            let p = f.projects.first(where: { $0.name == name })
            return ProjectGroup(id: name, title: p?.isHome == true ? "★ \(name)" : name,
                                folder: p.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "", home: p?.isHome == true,
                                rows: sorted.map { row($0.s, open: isOpen($0.s.tabKey)) }, newestAgo: sorted.first?.ago ?? .infinity)
        }.sorted { $0.newestAgo != $1.newestAgo ? $0.newestAgo < $1.newestAgo : $0.id < $1.id }
        out.projects = groups.filter { $0.newestAgo <= quietAfter }
        out.quietProjects = groups.filter { $0.newestAgo > quietAfter }
        out.archived = (f.archivedSessions ?? []).map { (s: $0, ago: secondsAgo($0, now: now)) }.sorted { $0.ago < $1.ago }.map { row($0.s, open: false) }
        return out
    }

    /// Seconds since a session was last used: its timestamp when live, else its wait text.
    public static func secondsAgo(_ s: Fixture.Session, now: Date) -> Double {
        if let t = s.lastActive { return max(0, now.timeIntervalSince1970 - t / 1000) }
        return Double(WaitTime(s.wait).seconds)
    }

    /// Most urgent state first, then the longest wait (DL-93), as a project's list orders its rows.
    static func urgency(_ a: Fixture.Session, _ b: Fixture.Session) -> Bool {
        if a.state != b.state { return a.state < b.state }
        let quiet = a.state == .idle || a.state == .resolved
        return quiet ? WaitTime(a.wait) < WaitTime(b.wait) : WaitTime(a.wait) > WaitTime(b.wait)
    }

    /// What the project column says (rows board): `★ home` for Home, the folder's path for a folder
    /// outside Home (its parent is a path, DL-104), else the project's own name.
    public static func projectLabel(_ name: String, in f: Fixture) -> String {
        guard let p = f.projects.first(where: { $0.name == name }) else { return name }
        if p.isHome == true { return "★ \(p.name)" }
        if let t = p.topic, MapLayout.isPath(t) { return (p.path as NSString).abbreviatingWithTildeInPath }
        return p.name.split(separator: "/").last.map(String.init) ?? p.name
    }

    /// The task a session belongs to (DL-93): a task note listing it, else a task bundle holding it.
    public static func task(of s: Fixture.Session, in f: Fixture) -> String? {
        if let id = s.sessionId, let t = f.tasks?.first(where: { $0.project == s.project && $0.archived != true && $0.sessionIds.contains(id) }) {
            return t.title
        }
        return f.groups.first { $0.project == s.project && $0.task != nil && $0.sessions.contains(s.name) }?.name
    }

    /// The rows as drawn, top to bottom, for the arrow keys: needs you when the list shows them, the
    /// sections, then each fold that's open.
    public func visibleRows(showsNeedsYou: Bool, earlierOpen: Bool, archivedOpen: Bool) -> [Row] {
        (showsNeedsYou ? needsYou : []) + sections.flatMap(\.rows) + (earlierOpen ? earlier : []) + (archivedOpen ? archived : [])
    }

}

@MainActor
extension AppModel {
    /// The list as it stands now.
    public var sessionList: SessionList {
        SessionList.build(fixture, isOpen: { [self] in hasOpenTerminal($0) }, now: listClock ?? minute)
    }

    /// Board or List (`duo2 view home`, View › Show Board / Show List); remembered from then on.
    public func setHomeView(_ v: HomeView) {
        // The List has no idle footer: its list closes, keys and all (F-178).
        if v == .list, idleOpen { idleOpen = false; IdleKeys.remove() }
        homeView = v
        DuoState.update { $0.homeView = v.rawValue }
    }

    /// The rows the arrow keys move through, as drawn.
    public var listRows: [SessionList.Row] {
        let l = sessionList
        if !listFilter.trimmingCharacters(in: .whitespaces).isEmpty { return listMatches.map(\.row) }
        if listGroup == .project { return listProjectEntries(l).compactMap(\.row) }
        return l.visibleRows(showsNeedsYou: rightCollapsedAllProjects, earlierOpen: expandedGroups.contains(SessionListKeys.earlier),
                             archivedOpen: listShowsArchived && expandedGroups.contains(SessionListKeys.archived))
    }

    /// One stop for the arrow keys in the grouped List: a project's header, or a session row.
    public struct ListEntry: Sendable {
        public var id: String
        public var row: SessionList.Row?
    }

    /// The grouped List as drawn, top to bottom: each project's header (always), then its rows when it is open
    /// (five, or all after "n more"); Quieter projects and Archived when they are open.
    public func listProjectEntries(_ l: SessionList) -> [ListEntry] {
        var out: [ListEntry] = []
        func add(_ g: SessionList.ProjectGroup) {
            out.append(ListEntry(id: SessionListKeys.header(g.id), row: nil))
            guard !expandedGroups.contains(SessionListKeys.folded(g.id)) else { return }
            let rows = expandedGroups.contains(SessionListKeys.more(g.id)) ? g.rows : g.firstRows
            out += rows.map { ListEntry(id: $0.id, row: $0) }
        }
        l.projects.forEach(add)
        if expandedGroups.contains(SessionListKeys.quieter) { l.quietProjects.forEach(add) }
        if listShowsArchived, expandedGroups.contains(SessionListKeys.archived) { out += l.archived.map { ListEntry(id: $0.id, row: $0) } }
        return out
    }

    /// ↑ / ↓ in the list.
    public func moveListSelection(_ dy: Int) {
        let ids: [String] = listGroup == .project && listFilter.trimmingCharacters(in: .whitespaces).isEmpty
            ? listProjectEntries(sessionList).map(\.id) : listRows.map(\.id)
        guard !ids.isEmpty else { return }
        let i = ids.firstIndex(of: listSelection ?? "").map { max(0, min(ids.count - 1, $0 + dy)) } ?? (dy > 0 ? 0 : ids.count - 1)
        listSelection = ids[i]
    }

    /// Return on the List's selection: a header folds its project, a row opens (DL-142 (5)).
    public func activateListSelection() {
        guard let id = listSelection else { return }
        if let p = SessionListKeys.project(ofHeader: id) { toggleProjectFold(p) } else { openListRow(id) }
    }

    /// Fold or open a project's header in the grouped List.
    public func toggleProjectFold(_ project: String) {
        let key = SessionListKeys.folded(project)
        withDuoAnimation(.fold) { if expandedGroups.contains(key) { expandedGroups.remove(key) } else { expandedGroups.insert(key) } }
    }

    /// Group › Recent / Project (`duo2 view list group`, View › Group Sessions By); remembered, as `homeView` is.
    public func setListGroup(_ g: ListGroup) {
        listGroup = g
        DuoState.update { $0.listGroup = g.rawValue }
    }

    /// The project the List's selection is in (a header selected, or one of its rows), when the List is grouped by project.
    public var listSelectedProject: String? {
        guard altitude.isAllProjects, homeView == .list, listGroup == .project, let id = listSelection else { return nil }
        if let p = SessionListKeys.project(ofHeader: id) { return p }
        return (fixture.sessions + (fixture.archivedSessions ?? [])).first { $0.id == id }?.project
    }

    /// Where a project's header + (and ⌘T on its selection) starts a session: the project, Home, or a plain folder.
    public func startPlace(forProject name: String) -> StartPlace? {
        guard let p = fixture.projects.first(where: { $0.name == name }) else { return nil }
        let folder = liveFolders[p.name] ?? URL(fileURLWithPath: p.path)
        if p.isHome == true { return StartPlace(kind: .home, label: "★ home", folder: folder, project: p.name) }
        if p.isFolderOnly { return StartPlace(kind: .folder, label: Self.tilde(folder.path), folder: folder) }
        return StartPlace(kind: .project, label: p.name, folder: folder, project: p.name)
    }

    /// The header's + (`duo2 session new --project <p>`): a session in that project, opening its page on it.
    public func newSessionFromHeader(_ project: String) {
        guard let place = startPlace(forProject: project) else { return }
        startSession(in: place)
    }

    /// A row's click or Return (DL-142 (5)): into its project with that session selected, as a tile's
    /// session row does.
    public func openListRow(_ id: String) {
        guard let s = (fixture.sessions + (fixture.archivedSessions ?? [])).first(where: { $0.id == id }) else { return }
        listSelection = id
        open(project: s.project, session: s.name)
    }
}

/// The folds' keys in `expandedGroups`.
public enum SessionListKeys {
    public static let earlier = "list/earlier"
    public static let archived = "list/archived"
    /// The grouped List's (DL-341): Quieter projects open; a project's fold (present = folded, a project is open by default); its "n more" open.
    public static let quieter = "list/quieter"
    public static func folded(_ project: String) -> String { "list/project-folded/\(project)" }
    public static func more(_ project: String) -> String { "list/project-more/\(project)" }
    /// A header's selection id, which can't be a session's.
    public static func header(_ project: String) -> String { "project:\(project)" }
    public static func project(ofHeader id: String) -> String? { id.hasPrefix("project:") ? String(id.dropFirst(8)) : nil }
}
