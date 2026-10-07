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
    check(l.filtered("synthesis").map(\.session.name) == ["Buyer synthesis"] && l.filtered("home").contains { $0.session.name == "Morning triage" },
          "the filter reads title, project and task, needs-you sessions too")
    check(l.visibleRows(showsNeedsYou: true, earlierOpen: false, archivedOpen: false).first?.session.name == "Morning triage"
          && l.visibleRows(showsNeedsYou: false, earlierOpen: true, archivedOpen: false).count == listed.count, "arrow keys walk the rows as drawn")
    check(HomeView(rawValue: DuoState().homeView ?? "") == nil, "a new user has no choice yet, so sees List")
    check(DuoAction.resolve(["view", "home", "list"]) != nil && ActionID.viewHome.action.ui.contains("Show List"), "duo2 view home (DL-71)")
}
