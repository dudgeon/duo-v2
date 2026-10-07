import Foundation

/// All projects' middle (DL-142 (1)): the map, or one list of every session.
public enum HomeView: String, CaseIterable, Sendable {
    case board, list
    public var title: String { self == .board ? "Board" : "List" }
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

    /// Needs you, most urgent first (the column's order).
    public var needsYou: [Row] = []
    public var sections: [Section] = []
    public var earlier: [Row] = []
    public var archived: [Row] = []

    /// The sessions, cut as a project's list is (DL-91): open in Duo first, most urgent first
    /// (DL-93); the rest by last use, newest first, into Today, This week and Earlier.
    public static func build(_ f: Fixture, isOpen: (String) -> Bool, now: Date = Date(), calendar: Calendar = .current) -> SessionList {
        func row(_ s: Fixture.Session, open: Bool) -> Row {
            Row(session: s, project: projectLabel(s.project, in: f), task: task(of: s, in: f), open: open)
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
        out.archived = (f.archivedSessions ?? []).map { (s: $0, ago: secondsAgo($0, now: now)) }.sorted { $0.ago < $1.ago }.map { row($0.s, open: false) }
        return out
    }

    /// Seconds since a session was last used: its timestamp when live, else its wait text.
    static func secondsAgo(_ s: Fixture.Session, now: Date) -> Double {
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

    /// Rows whose title, project or task has every word of the filter (case and accents aside).
    public func filtered(_ text: String) -> [Row] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let all = needsYou + sections.flatMap(\.rows) + earlier
        return all.filter { r in
            let hay = [r.session.name, r.project, r.task ?? ""].joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { hay.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
        }
    }
}

@MainActor
extension AppModel {
    /// The list as it stands now.
    public var sessionList: SessionList {
        SessionList.build(fixture, isOpen: { [self] in hasOpenTerminal($0) }, now: listClock ?? Date())
    }

    /// Board or List (`duo2 view home`, View › Show Board / Show List); remembered from then on.
    public func setHomeView(_ v: HomeView) {
        // The List has no idle footer: its list closes, keys and all (F-178).
        if v == .list, idleOpen { idleOpen = false; IdleKeys.remove() }
        homeView = v
        DuoState.update { $0.homeView = v.rawValue }
    }

    /// The list shows needs-you rows itself only while the column is hidden (N1).
    public var listShowsNeedsYou: Bool { rightCollapsedAllProjects || !listFilter.isEmpty }

    /// The rows the arrow keys move through, as drawn.
    public var listRows: [SessionList.Row] {
        let l = sessionList
        if !listFilter.trimmingCharacters(in: .whitespaces).isEmpty { return l.filtered(listFilter) }
        return l.visibleRows(showsNeedsYou: rightCollapsedAllProjects, earlierOpen: expandedGroups.contains(SessionListKeys.earlier),
                             archivedOpen: listShowsArchived && expandedGroups.contains(SessionListKeys.archived))
    }

    /// ↑ / ↓ in the list.
    public func moveListSelection(_ dy: Int) {
        let rows = listRows
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.id == listSelection }.map { max(0, min(rows.count - 1, $0 + dy)) } ?? (dy > 0 ? 0 : rows.count - 1)
        listSelection = rows[i].id
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
enum SessionListKeys {
    static let earlier = "list/earlier"
    static let archived = "list/archived"
}
