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
    // The List's header carries the Board tile's action (Q-158): same sheet call, same verb.
    let panes = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/AllProjects/AllProjectsPanes.swift"), encoding: .utf8)) ?? ""
    let calls = panes.split(separator: "\n").filter { $0.contains("model.showNewProject()") && $0.contains("// action: project new") }
    check(calls.count == 2 && ActionID.projectNew.action.ui.contains("+ New project"), "the Board tile and the List header's + New project both run `duo2 project new` (Q-158)")
}
