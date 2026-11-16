import DuoControl
import DuoKit
import Foundation

/// All projects' List (DL-142): every session across projects, cut as a project's list is.
@MainActor func homeListChecks(_ base: Fixture) {
    print("all projects' list (DL-142)")
    let f = HomeListTargets.boardSessions(base, outsideFolder: true)
    let open: Set<String> = ["Teardown research", "Edge-case matrix", "Rule audit", "Weekly status draft", "Fix footer links"]
    let keys = Set(f.sessions.filter { open.contains($0.name) }.map(\.tabKey))
    let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
    let l = SessionList.build(f, isOpen: { keys.contains($0) }, now: evening)
    let listed = l.sections.flatMap(\.rows) + l.earlier
    check(l.needsYou.map(\.session.name) == ["Morning triage", "Copy review pass 2", "PRD v2 edits"], "needs you is the column's, in its order (N1)")
    check(!listed.contains { $0.session.state == .needsYou }, "needs-you sessions are left out of the sections")
    check(listed.count + l.needsYou.count == f.sessions.count && Set(listed.map(\.id)).count == listed.count, "every other session listed once")
    check(l.sections.map(\.id) == ["open", "today", "week"], "Open, Today, This week")
    check(l.sections.first?.rows.map(\.session.name) == ["Teardown research", "Edge-case matrix", "Rule audit", "Weekly status draft", "Fix footer links"],
          "Open: most urgent first, then the longest wait (DL-93), as the board draws")
    check(l.sections.first?.rows.map(\.wait) == ["working", "working", "working", "at prompt", "at prompt"], "open rows read working / at prompt (DL-133)")
    check(l.sections[1].rows.map(\.session.name) == ["Results readout", "Funnel SQL", "Buyer synthesis", "Q4 plan outline", "Vendor shortlist"], "Today: newest first")
    check(l.sections[2].rows.map(\.session.name) == ["Checkout copy audit", "Deprecation email", "“Summarise the six buyer interviews”"], "This week")
    check(l.earlier.count == 9 && l.archived.count == 4, "Earlier · 9 and Archived · 4, as drawn")
    check(WaitTime("2w").seconds == 14 * 86400, "a wait in weeks is weeks (it read as 0, so Today)")
    let byName = Dictionary(uniqueKeysWithValues: (l.sections.flatMap(\.rows)).map { ($0.session.name, $0) })
    check(byName["Weekly status draft"]?.project == "★ home" && byName["Fix footer links"]?.project == "~/repos/site" && byName["Rule audit"]?.project == "fraud-rules-review",
          "project column: ★ home, a folder outside Home by its path, else the name")
    check(byName["Teardown research"]?.task == "Exec review prep" && byName["Edge-case matrix"]?.task == nil, "the task when there is one, else nothing")
    let hits = [SessionList.SearchMatch(sessionId: "fixture-teardown", snippet: "You: What do the teardowns do at checkout?\n\nClaude: Three of the five teardowns let guests save a card at checkout.")]
    let fl = l
    let m = fl.matches("saved cards in scope", search: hits, in: f)
    check(m.first?.row.session.name == "PRD v2 edits" && m.first?.who == "question", "a needs-you session matches too, by the question it waits on (N1 doesn't hide it)")
    check(m.contains { $0.row.session.name == "Teardown research" && $0.who == "Claude, 40m" }, "a search hit shows Claude's part when the words are there, who and when first")
    check(fl.matches("synthesis", search: [], in: f).map(\.row.session.name) == ["Buyer synthesis"] && fl.matches("Exec review", search: [], in: f).first?.row.session.name == "Teardown research",
          "the word match reads title, project, folder and task names")
    check(fl.matches("   ", search: hits, in: f).isEmpty, "an empty filter matches nothing (the sections come back)")
    check(SessionList.words("saved cards in scope") == ["save", "card", "scop"], "the filter's words: three letters or more, lightly stemmed")
    check(l.visibleRows(showsNeedsYou: true, earlierOpen: false, archivedOpen: false).first?.session.name == "Morning triage"
          && l.visibleRows(showsNeedsYou: false, earlierOpen: true, archivedOpen: false).count == listed.count, "arrow keys walk the rows as drawn")
    check(HomeView(rawValue: DuoState().homeView ?? "") == nil, "a new user has no choice yet, so sees List")
    do {
        let m = AppModel(fixture: base)
        m.altitude = .allProjects
        m.homeView = .board
        m.idleOpen = true
        m.homeView = .list   // not setHomeView: it writes Duo's state file
        check(!IdleKeys.handle(m, code: 36, flags: [], chars: "\r"), "the idle list's keys stop on the List, which has no idle footer (F-178)")
        m.idleOpen = false
    }
    do {
        // Home opens in chat (DL-142 (6)): new Home sessions in chat; each keeps its own once switched;
        // other sessions still the mode used last; --home terminal|last.
        var p = ChatPrefs()
        check(p.mode(for: "h1", home: true) == .chat && p.mode(for: "s1") == .terminal, "a new Home session opens in chat; others in the mode used last (terminal until chat is used)")
        p.set(.terminal, for: "h1")
        check(p.mode(for: "h1", home: true) == .terminal, "a Home session keeps its own mode once switched")
        p.home = .terminal
        check(p.mode(for: "h2", home: true) == .terminal, "--home terminal")
        p.home = .last; p.last = .chat
        check(p.mode(for: "h3", home: true) == .chat && { var q = p; q.fixedDefault = .terminal; return q.mode(for: "h3", home: true) == .terminal }(), "--home last follows --default, else the mode used last")
        let old = try? JSONDecoder().decode(ChatPrefs.self, from: Data(#"{"modes":{},"last":"terminal"}"#.utf8))
        check(old?.home == nil && old?.mode(for: "x", home: true) == .chat, "a chat.json from before reads, and Home opens in chat")
        check(DuoAction.resolve(["session", "chat"]).map { $0.0.args.contains("--home chat|terminal|last") } == true, "duo2 session chat --home (DL-71)")
    }
    check(DuoAction.resolve(["view", "home", "list"]) != nil && ActionID.viewHome.action.ui.contains("Show List"), "duo2 view home (DL-71)")
    // The List grouped by project (DL-341, Q-547).
    do {
        let all = l.projects + l.quietProjects
        let ago = l.projects.map(\.newestAgo)
        check(ago == ago.sorted() && l.projects.allSatisfy { $0.newestAgo <= SessionList.quietAfter } && l.quietProjects.allSatisfy { $0.newestAgo > SessionList.quietAfter },
              "by project: projects newest activity first; those with nothing this week are Quieter projects")
        check(all.flatMap(\.rows).count == f.sessions.count && Set(all.flatMap(\.rows).map(\.id)).count == f.sessions.count,
              "by project: every live session sits under its project once, needs-you ones too (as L1 draws them)")
        check(all.allSatisfy { g in zip(g.rows, g.rows.dropFirst()).allSatisfy { SessionList.secondsAgo($0.session, now: evening) <= SessionList.secondsAgo($1.session, now: evening) } },
              "by project: sessions newest first inside a project")
        let home = all.first { $0.home }
        check(home?.title == "★ home" && home.map { $0.firstRows.count == min(5, $0.rows.count) && $0.hiddenCount == max(0, $0.rows.count - 5) } == true,
              "by project: Home is ★ home; five rows then 'n more'")
        check(l.archived.count == 4, "by project: Archived stays its own fold, last")
        let m = AppModel(fixture: f)
        m.altitude = .allProjects; m.homeView = .list
        check(m.listGroup == .recent && m.listSelectedProject == nil, "the List groups by recent until chosen; nothing selected, ⌘T is DL-262's")
        m.listGroup = .project   // not setListGroup: it writes Duo's state file
        let first = all.first { !$0.home }!
        m.listSelection = SessionListKeys.header(first.id)
        check(m.listSelectedProject == first.id && m.startPlace(forProject: first.id)?.project == first.id, "a selected header: ⌘T starts in its project")
        m.listSelection = first.rows[0].id
        check(m.listSelectedProject == first.id, "a selected row of a project: ⌘T starts in its project")
        let entries = m.listProjectEntries(l)
        check(entries.first?.id == SessionListKeys.header(l.projects[0].id) && entries.contains { $0.row == nil && $0.id == SessionListKeys.header(first.id) },
              "arrow keys stop at each project's header, then its rows")
        m.expandedGroups.insert(SessionListKeys.folded(first.id))
        check(!m.listProjectEntries(l).contains { $0.row?.session.project == first.id } && m.listProjectEntries(l).contains { $0.id == SessionListKeys.header(first.id) },
              "a folded project keeps its header, and its rows leave the walk")
        check(m.startPlace(forProject: home?.id ?? "")?.kind == .home, "Home's + starts in Home")
        check(ListGroup(rawValue: DuoState().listGroup ?? "") == nil, "a new user's List groups by recent")
        check(DuoAction.resolve(["view", "list", "group", "project"]) != nil && ActionID.viewList.action.ui.contains("Group Sessions By")
              && ActionID.sessionNew.action.ui.contains("List project header +"), "duo2 view list group, and the header's + is session new (DL-71)")
    }
    // The List's header carries the Board tile's action (Q-158): same sheet call, same verb.
    let panes = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/AllProjects/AllProjectsPanes.swift"), encoding: .utf8)) ?? ""
    let calls = panes.split(separator: "\n").filter { $0.contains("model.showNewProject()") && $0.contains("// action: project new") }
    check(calls.count == 2 && ActionID.projectNew.action.ui.contains("+ New project"), "the Board tile and the List header's + New project both run `duo2 project new` (Q-158)")
    boardActivityChecks(f, now: evening)
}

/// The Board by activity (DL-347): sections, pins, grouping, ⌘T on a focused tile, the verbs.
@MainActor func boardActivityChecks(_ f: Fixture, now: Date) {
    print("the board by activity (DL-347)")
    let ms = now.timeIntervalSince1970 * 1000
    let pins: Set<String> = ["home", "checkout-redesign"]
    func build(_ g: BoardGroup = .activity, filter: String = "", earlierOpen: Bool = false, pinned: Set<String> = pins) -> ActivityLayout {
        ActivityLayout.build(f, group: g, filter: filter, earlierOpen: earlierOpen, isPinned: { pinned.contains($0.name) },
                             isOpen: { _ in false }, now: ms)
    }
    let l = build()
    let ids = l.sections.map(\.id)
    check(ids == ids.filter { ["pinned", "now", "today", "week", "earlier"].contains($0) } && ids.first == "pinned", "sections: Pinned first, then Now, Today, This week, Earlier")
    check(l.sections.first?.projects.map(\.name).first == "home" && Set(l.sections.first?.projects.map(\.name) ?? []) == pins, "Pinned holds the pins, Home first")
    let names = l.sections.flatMap { $0.projects.map(\.name) }
    check(Set(names).count == names.count && names.count == f.projects.count, "every project is in one section, once (a folder with no project file too)")
    let nowNames = Set(l.sections.first { $0.id == "now" }?.projects.map(\.name) ?? [])
    let liveNames = Set(f.projects.map(\.name).filter { n in !pins.contains(n) && f.sessions(inProject: n).contains { [.needsYou, .readyForReview, .working].contains($0.state) } })
    check(!nowNames.isEmpty && nowNames == liveNames, "Now: exactly the unpinned projects with a session needing you, to review or working")
    check(l.sections.first { $0.id == "week" }?.style == .rows && l.sections.first { $0.id == "earlier" }.map { $0.style == .fold && !$0.open && $0.shownProjects.isEmpty } ?? true,
          "This week is rows; Earlier is a fold, closed by default")
    check(build(earlierOpen: true).visibleNames.count >= l.visibleNames.count, "opening Earlier adds its rows to the arrow-key walk")
    check(build(.none).sections.count == 1 && build(.none).sections[0].title.isEmpty && build(.none).sections[0].projects.count == f.projects.count, "None: one flat run of tiles")
    let vendor = build(filter: "checkout", pinned: [])
    check(vendor.shown >= 1 && vendor.shown < f.projects.count && vendor.sections.flatMap(\.projects).allSatisfy { ($0.name + $0.path).lowercased().contains("checkout") }, "the filter narrows to matching names and folders")
    let unpinned = build(pinned: [])
    check(!unpinned.sections.contains { $0.id == "pinned" }, "no pins, no Pinned section (Home is just a project, then)")
    let archived = ActivityLayout.build(f, group: .activity, filter: "", isArchived: { $0 == "vendor-review" }, isPinned: { _ in false }, now: ms)
    check(!archived.sections.flatMap(\.projects).contains { $0.name == "vendor-review" }, "an archived project leaves the sections (the Archived rollup has it)")
    check(MapPacking.columnCount(width: 1060, items: 12, minWidth: DuoMetric.mapColumnMin, spacing: 12, maxPerRow: Int(DuoMetric.mapPerRowMax)) >= 4
          && MapPacking.columnCount(width: 1560, items: 12, minWidth: DuoMetric.mapColumnMin, spacing: 12, maxPerRow: Int(DuoMetric.mapPerRowMax)) >= 6,
          "as many tiles across as fit at 220: more than three (DL-83's cap lifted)")
    let m = AppModel(fixture: f)
    m.altitude = .allProjects; m.homeView = .board
    m.fixturePinned = []
    check(BoardGroup(rawValue: DuoState().boardGroup ?? "") == nil && m.boardGroup == .activity, "a new user's Board is grouped by activity")
    let home = f.projects.first { $0.isHome == true }!
    check(!m.isPinned(home) , "fixture pins stand in: none pinned")
    m.fixturePinned = nil
    check(m.isPinned(home), "★ home starts pinned when there is a Home")
    m.fixturePinned = []
    m.setPinned("checkout-redesign", true)
    check(m.fixturePinned == ["checkout-redesign"] && m.isPinned(f.projects.first { $0.name == "checkout-redesign" }!), "Pin to Top pins")
    m.setPinned("checkout-redesign", false)
    check(m.fixturePinned == [], "Unpin unpins")
    m.focusedTile = nil
    check(m.boardFocusedProject == nil, "⌘T with no tile focused is DL-262's")
    m.focusedTile = "checkout-redesign"
    check(m.boardFocusedProject == "checkout-redesign" && m.startPlace(forProject: "checkout-redesign")?.project == "checkout-redesign", "⌘T with a tile focused starts in its project")
    m.homeView = .list
    check(m.boardFocusedProject == nil, "…but only on the Board")
    m.homeView = .board
    m.fixturePinned = pins
    m.focusedTile = nil
    m.moveTileFocus(dx: 1, dy: 0)
    let order = m.activityLayout.visibleNames
    check(m.focusedTile == order.first, "the first arrow focuses the first tile")
    m.moveTileFocus(dx: 1, dy: 0)
    check(m.focusedTile == order[1], "right steps to the next tile in reading order")
    m.boardPerRow = 2
    m.moveTileFocus(dx: 0, dy: 1)
    check(m.focusedTile == order[3], "down steps a row of tiles")
    check(DuoAction.resolve(["view", "group", "activity"]) != nil && ActionID.viewGroup.action.ui.contains("Group Projects By")
          && DuoAction.resolve(["project", "pin", "home"]) != nil && ActionID.projectPin.action.ui.contains("Pin to Top")
          && ActionID.sessionNew.action.ui.contains("Board tile New session row"), "duo2 view group activity|folder|none, project pin, and the tile's New session row (DL-71)")
}
