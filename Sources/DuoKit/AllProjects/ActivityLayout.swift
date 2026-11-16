import Foundation

/// How the Board groups its projects (DL-347, Q-540): by activity (the default), by folder (DL-83's
/// bands) or not at all. Replaces Sort on the Board.
public enum BoardGroup: String, CaseIterable, Sendable {
    case activity, folder, none
    public var title: String { self == .activity ? "Activity" : self == .folder ? "Folder" : "None" }
}

/// The Board by activity (DL-347, boards B1 and B2): Pinned, Now and Today as tiles, This week as
/// rows, Earlier folded (Archived is the rollup under the Board). Home is a project like another,
/// pinned until it's unpinned; a folder with no project file sits in the same sections.
public struct ActivityLayout: Sendable, Equatable {
    public enum Style: Sendable { case tiles, rows, fold }

    public struct Section: Identifiable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var style: Style
        public var projects: [Fixture.Project]
        /// A fold's state: its rows show only when open.
        public var open = true
        public var shownProjects: [Fixture.Project] { style == .fold && !open ? [] : projects }
    }

    public var sections: [Section] = []
    public var total = 0
    public var shown = 0

    /// Every project as drawn, in reading order, for the arrow keys (a closed fold has none).
    public var visibleNames: [String] { sections.flatMap { $0.shownProjects.map(\.name) } }
    public var isEmpty: Bool { sections.allSatisfy { $0.projects.isEmpty } }

    /// Seconds in a week: a project with nothing newer is Earlier.
    public static let weekSeconds: Double = 7 * 86400

    /// A project's urgency for Now: needs you, to review, working, then open in a Duo terminal; nil when none apply.
    static func nowRank(_ p: Fixture.Project, in f: Fixture, isOpen: (String) -> Bool) -> Int? {
        let states = f.sessions(inProject: p.name).map(\.state)
        if states.contains(.needsYou) { return 0 }
        if states.contains(.readyForReview) { return 1 }
        if states.contains(.working) { return 2 }
        return isOpen(p.name) ? 3 : nil
    }

    public static func build(_ f: Fixture, group: BoardGroup, filter: String, earlierOpen: Bool = false,
                             isArchived: (String) -> Bool = { _ in false }, isPinned: (Fixture.Project) -> Bool = { $0.isHome == true },
                             isOpen: (String) -> Bool = { _ in false }, settled: [String: Double] = [:],
                             now: Double = Date().timeIntervalSince1970 * 1000, calendar: Calendar = .current) -> ActivityLayout {
        var out = ActivityLayout()
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let matches: (Fixture.Project) -> Bool = { p in
            needle.isEmpty || p.name.lowercased().contains(needle) || p.path.lowercased().contains(needle)
        }
        let all = f.projects.filter { !isArchived($0.name) }
        out.total = all.count
        let act: (Fixture.Project) -> Double = { p in settled[p.name] ?? MapLayout.activity(of: p.name, in: f, now: now) }
        // Newest first, the source order for equals; `key` ranks first when given.
        func ordered(_ ps: [Fixture.Project], rank: (Fixture.Project) -> Int = { _ in 0 }) -> [Fixture.Project] {
            ps.enumerated().sorted { x, y in
                let (ra, rb) = (rank(x.element), rank(y.element))
                if ra != rb { return ra < rb }
                let (ta, tb) = (act(x.element), act(y.element))
                return ta != tb ? ta > tb : x.offset < y.offset
            }.map(\.element)
        }
        let shown = all.filter(matches)
        out.shown = shown.count
        if group == .none {
            out.sections = [Section(id: "all", title: "", style: .tiles, projects: ordered(shown) )]
            return out
        }
        let startOfToday = calendar.startOfDay(for: Date(timeIntervalSince1970: now / 1000)).timeIntervalSince1970 * 1000
        var pinned: [Fixture.Project] = [], nowP: [Fixture.Project] = [], today: [Fixture.Project] = []
        var week: [Fixture.Project] = [], earlier: [Fixture.Project] = []
        for p in shown {
            if isPinned(p) { pinned.append(p); continue }
            if nowRank(p, in: f, isOpen: isOpen) != nil { nowP.append(p); continue }
            let t = act(p)
            if t >= startOfToday { today.append(p) } else if t >= now - weekSeconds * 1000 && t > 0 { week.append(p) } else { earlier.append(p) }
        }
        // Home leads Pinned, then the pinned by activity.
        let pinnedOrdered = ordered(pinned, rank: { $0.isHome == true ? 0 : 1 })
        let nowOrdered = ordered(nowP, rank: { nowRank($0, in: f, isOpen: isOpen) ?? 9 })
        let candidates: [Section] = [
            Section(id: "pinned", title: "Pinned", style: .tiles, projects: pinnedOrdered),
            Section(id: "now", title: "Now", style: .tiles, projects: nowOrdered),
            Section(id: "today", title: "Today", style: .tiles, projects: ordered(today)),
            Section(id: "week", title: "This week", style: .rows, projects: ordered(week)),
            Section(id: "earlier", title: "Earlier", style: .fold, projects: ordered(earlier), open: earlierOpen),
        ]
        out.sections = candidates.filter { !$0.projects.isEmpty }
        return out
    }
}

@MainActor
extension AppModel {
    /// A project's pin key: its folder's path, else its name (a fixture's).
    func pinKey(_ project: String) -> String { liveFolders[project]?.path ?? project }

    /// Pinned to the Board's first row: ones the user pinned, and Home until it's unpinned (DL-347, Q-541).
    public func isPinned(_ p: Fixture.Project) -> Bool {
        if let fixed = fixturePinned { return fixed.contains(p.name) }
        let key = pinKey(p.name)
        if pinnedKeys.contains(key) { return true }
        return p.isHome == true && !unpinnedKeys.contains(key)
    }

    public func setPinned(_ project: String, _ on: Bool) {
        guard let p = fixture.projects.first(where: { $0.name == project }), isPinned(p) != on else { return }
        if fixturePinned != nil {
            if on { fixturePinned?.insert(project) } else { fixturePinned?.remove(project) }
        } else {
            let key = pinKey(project)
            pinnedKeys.removeAll { $0 == key }; unpinnedKeys.removeAll { $0 == key }
            if on { pinnedKeys.append(key) } else { unpinnedKeys.append(key) }
            let (pins, unpins) = (pinnedKeys, unpinnedKeys)
            DuoState.update { $0.pinnedProjects = pins; $0.unpinnedProjects = unpins }
        }
        registerUndo(on ? "Pin to Top" : "Unpin") { model in model.setPinned(project, !on) }
    }

    public func setBoardGroup(_ g: BoardGroup) {
        boardGroup = g
        DuoState.update { $0.boardGroup = g.rawValue }
    }

    /// The Board's key for the Earlier fold in `expandedGroups`.
    public static let boardEarlierKey = "board/earlier"

    public var activityLayout: ActivityLayout {
        ActivityLayout.build(fixture, group: boardGroup, filter: mapFilter, earlierOpen: expandedGroups.contains(Self.boardEarlierKey),
                             isArchived: { [self] in isArchived($0) }, isPinned: { [self] in isPinned($0) },
                             isOpen: { [self] name in fixture.sessions(inProject: name).contains { hasOpenTerminal($0.tabKey) } },
                             settled: mapSettled, now: minute.timeIntervalSince1970 * 1000)
    }

    /// The tile ⌘T starts in (DL-347, Q-543): the focused tile at All projects' Board.
    public var boardFocusedProject: String? {
        guard altitude.isAllProjects, homeView == .board else { return nil }
        return focusedTile
    }

    /// The arrow keys on the activity Board: left and right step through the tiles in reading order, up and down by a row of them.
    func moveActivityFocus(dx: Int, dy: Int) {
        let names = activityLayout.visibleNames
        guard !names.isEmpty else { return }
        guard let current = focusedTile, let i = names.firstIndex(of: current) else { focusedTile = names.first; return }
        let step = dx != 0 ? dx : dy * max(1, boardPerRow)
        focusedTile = names[max(0, min(names.count - 1, i + step))]
    }
}
