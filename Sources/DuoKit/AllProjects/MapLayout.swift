import Foundation

/// The map's order (DL-104): newest activity first, or by name.
public enum MapSort: String, CaseIterable, Sendable {
    case recent, name
    public var title: String { self == .recent ? "Recent" : "Name" }
}

/// What the map draws, in order (DL-104): Home's tile and columns as tiles; folders outside Home as
/// rows under their parent folder, except those with a session that needs you or is working, which
/// stay tiles in ACTIVE OUTSIDE HOME. Grouping stays by parent folder (DL-83).
public struct MapLayout: Sendable, Equatable {
    public struct Column: Sendable, Equatable, Identifiable {
        public var topic: String
        public var projects: [Fixture.Project]
        /// Rows past the first five, until the group is opened (`+ n more`).
        public var hidden: Int = 0
        public var id: String { topic }
    }

    /// Rows a group shows before `+ n more`.
    public static let rowsPerGroup = 5

    public var home: Fixture.Project?
    public var homeColumns: [Column] = []
    public var active: [Fixture.Project] = []
    public var outside: [Column] = []
    /// Folders outside Home before the filter, and every project on the map before and after it.
    public var outsideTotal = 0
    public var total = 0
    public var shown = 0

    public var isEmpty: Bool { home == nil && homeColumns.allSatisfy(\.projects.isEmpty) && active.isEmpty && outside.isEmpty }

    /// Columns for the arrow keys, as drawn: Home's (its tile first), the active tiles, each group's visible rows.
    public var focusColumns: [[String]] {
        var cols = homeColumns.map { $0.projects.map(\.name) }
        if let h = home, !cols.isEmpty { cols[0].insert(h.name, at: 0) }
        if !active.isEmpty { cols.append(active.map(\.name)) }
        cols += outside.map { $0.projects.map(\.name) }
        return cols.filter { !$0.isEmpty }
    }

    public static func isPath(_ topic: String) -> Bool { topic.hasPrefix("~") || topic.hasPrefix("/") }

    /// Minutes since a session was last active, from its wait text when it has no timestamp
    /// (fixture sessions): `now`, `4m`, `1h`, `3d`, `2w`. Open sessions (`working`, `at prompt`) are 0.
    public static func minutesAgo(_ wait: String?) -> Double? {
        guard let w = wait?.trimmingCharacters(in: .whitespaces), !w.isEmpty else { return nil }
        if w == "now" || w == "working" || w == "at prompt" { return 0 }
        guard let unit = w.last, let n = Double(w.dropLast()) else { return nil }
        switch unit {
        case "m": return n
        case "h": return n * 60
        case "d": return n * 1440
        case "w": return n * 10080
        default: return nil
        }
    }

    /// A project's newest activity, ms since 1970: now for a session that needs you, is ready for
    /// review or is working; otherwise its sessions' last activity. No sessions: 0 (oldest).
    public static func activity(of project: String, in f: Fixture, now: Double) -> Double {
        f.sessions(inProject: project).map { s -> Double in
            if [.needsYou, .readyForReview, .working].contains(s.state) { return now }
            if let t = s.lastActive { return t }
            return minutesAgo(s.wait).map { now - $0 * 60_000 } ?? 0
        }.max() ?? 0
    }

    /// Home's sessions in attention order (needs you, review, working, idle; newest first within each).
    public static func homeSessions(_ f: Fixture) -> [Fixture.Session] {
        guard let h = f.home else { return [] }
        let rank: (SessionState) -> Int = { [.needsYou, .readyForReview, .working, .idle, .resolved].firstIndex(of: $0) ?? 9 }
        return f.sessions(inProject: h.name).enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element.state), rank(b.element.state))
            if ra != rb { return ra < rb }
            let (ma, mb) = (a.element.lastActive.map { -$0 } ?? minutesAgo(a.element.wait) ?? .infinity,
                            b.element.lastActive.map { -$0 } ?? minutesAgo(b.element.wait) ?? .infinity)
            return ma != mb ? ma < mb : a.offset < b.offset
        }.map(\.element)
    }

    /// A folder label for ordering by name: `~/code/work` sorts as `code/work`, `~` first.
    static func nameKey(_ topic: String) -> String {
        var t = topic
        if t.hasPrefix("~") { t.removeFirst() }
        while t.hasPrefix("/") { t.removeFirst() }
        return t.lowercased()
    }

    public static func build(_ f: Fixture, sort: MapSort, filter: String, openGroups: Set<String> = [],
                             isArchived: (String) -> Bool = { _ in false }, settled: [String: Double] = [:],
                             now: Double = Date().timeIntervalSince1970 * 1000) -> MapLayout {
        var out = MapLayout()
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let matches: (Fixture.Project) -> Bool = { p in
            needle.isEmpty || p.name.lowercased().contains(needle) || p.path.lowercased().contains(needle)
        }
        let act: (Fixture.Project) -> Double = { p in settled[p.name] ?? activity(of: p.name, in: f, now: now) }
        let byOrder: (Fixture.Project, Fixture.Project) -> Bool = { a, b in
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .recent: return act(a) > act(b)
            }
        }
        // Stable: equal keys keep the source order.
        func ordered(_ ps: [Fixture.Project]) -> [Fixture.Project] {
            ps.enumerated().sorted { x, y in
                byOrder(x.element, y.element) ? true : byOrder(y.element, x.element) ? false : x.offset < y.offset
            }.map(\.element)
        }
        func orderedColumns(_ cols: [Column]) -> [Column] {
            cols.enumerated().sorted { x, y in
                let (a, b) = (x.element, y.element)
                switch sort {
                case .name:
                    let (ka, kb) = (nameKey(a.topic), nameKey(b.topic))
                    return ka != kb ? ka < kb : x.offset < y.offset
                case .recent:
                    let (ta, tb) = (a.projects.map(act).max() ?? 0, b.projects.map(act).max() ?? 0)
                    return ta != tb ? ta > tb : x.offset < y.offset
                }
            }.map(\.element)
        }

        let all = f.projects.filter { !isArchived($0.name) }
        out.total = all.count
        if let h = f.home, !isArchived(h.name), matches(h) { out.home = h }

        // Home's columns: the unlabelled one first, then its topic folders.
        var homeCols: [Column] = []
        var outsideCols: [Column] = []
        let live: (Fixture.Project) -> Bool = { p in f.sessions(inProject: p.name).contains { [.needsYou, .working].contains($0.state) } }
        for topic in f.topics {
            let ps = all.filter { $0.topic == topic && $0.isHome != true }
            if isPath(topic) {
                out.outsideTotal += ps.count
                let shown = ps.filter(matches)
                out.active += shown.filter(live)
                let rows = ordered(shown.filter { !live($0) })
                if !rows.isEmpty { outsideCols.append(Column(topic: topic, projects: rows)) }
            } else {
                let shown = ordered(ps.filter(matches))
                if !shown.isEmpty { homeCols.append(Column(topic: topic, projects: shown)) }
            }
        }
        // Home's tile heads the unlabelled column; with no projects directly in Home it's that column alone.
        var unlabelled = homeCols.filter { $0.topic.isEmpty }
        if out.home != nil && unlabelled.isEmpty { unlabelled = [Column(topic: "", projects: [])] }
        out.homeColumns = unlabelled + orderedColumns(homeCols.filter { !$0.topic.isEmpty })
        // Needs you before working, then the chosen order.
        let needs: (Fixture.Project) -> Bool = { p in f.sessions(inProject: p.name).contains { $0.state == .needsYou } }
        out.active = ordered(out.active).enumerated().sorted { x, y in
            let (a, b) = (needs(x.element), needs(y.element))
            return a != b ? a : x.offset < y.offset
        }.map(\.element)
        out.outside = orderedColumns(outsideCols).map { c in
            guard !openGroups.contains(c.topic), c.projects.count > rowsPerGroup else { return c }
            var c = c
            c.hidden = c.projects.count - rowsPerGroup
            c.projects = Array(c.projects.prefix(rowsPerGroup))
            return c
        }
        out.shown = (out.home == nil ? 0 : 1) + out.homeColumns.map(\.projects.count).reduce(0, +) + out.active.count
            + out.outside.map { $0.projects.count + $0.hidden }.reduce(0, +)
        return out
    }
}

@MainActor
extension AppModel {
    public var mapLayout: MapLayout {
        MapLayout.build(fixture, sort: mapSort, filter: mapFilter, openGroups: openOutsideGroups,
                        isArchived: { [self] in isArchived($0) }, settled: mapSettled)
    }

    /// Fixes the map's Recent order as of now (DL-104: it settles on arrival, then holds).
    public func settleMapOrder() {
        let now = Date().timeIntervalSince1970 * 1000
        mapSettled = Dictionary(fixture.projects.map { ($0.name, MapLayout.activity(of: $0.name, in: fixture, now: now)) },
                                uniquingKeysWith: { a, _ in a })
    }

    public func setMapSort(_ sort: MapSort) {
        mapSort = sort
        DuoState.update { $0.mapSort = sort.rawValue }
        settleMapOrder()
    }
}
