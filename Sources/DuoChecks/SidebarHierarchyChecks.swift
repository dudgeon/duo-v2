import DuoKit
import Foundation

/// The project pane's hierarchy (DL-217, DL-218): PINNED, NEEDS YOU, OPEN, TASKS and Later, OTHER SESSIONS.
@MainActor func sidebarHierarchyChecks(_ base: Fixture) {
    print("project pane hierarchy: pinned, needs you, open, tasks and Later, other sessions (DL-217, DL-218)")
    var f = base
    let p = "checkout-redesign"
    f.sessions.removeAll { $0.project == p }
    f.groups.removeAll { $0.project == p }
    f.tasks = (f.tasks ?? []).filter { $0.project != p }
    func add(_ name: String, _ st: SessionState, _ wait: String) {
        let json = ["name": name, "project": p, "state": st.rawValue, "wait": wait, "sessionId": "id-" + name]
        f.sessions.append(try! JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    let cal = Calendar.current
    let noon = cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: Date()))!
    let nowMs = noon.timeIntervalSince1970 * 1000
    func task(_ title: String, _ members: [String], quietDays: Double?, status: String = "open", group: Bool = true) {
        var t = Fixture.TaskSummary(project: p, path: "tasks/\(title).md", title: title, status: status, sessionIds: members.map { "id-" + $0 })
        t.modified = quietDays.map { nowMs - $0 * 86400_000 }
        f.tasks = (f.tasks ?? []) + [t]
        if group && !members.isEmpty {
            let g: [String: Any] = ["name": title, "project": p, "sessions": members, "threads": members.map { [$0] }, "task": t.path]
            f.groups.append(try! JSONDecoder().decode(Fixture.Group.self, from: JSONSerialization.data(withJSONObject: g)))
        }
    }
    add("Director", .working, "now"); add("Old director", .idle, "2h"); add("Kept", .idle, "5m"); add("Kept in task", .idle, "4m")
    add("In task", .idle, "2h"); add("Waiting in task", .needsYou, "5m"); add("Waiting alone", .needsYou, "9m")
    add("Open one", .working, "1m"); add("Open in task", .idle, "20d"); add("Today one", .idle, "3h"); add("Week one", .idle, "3d"); add("Old one", .idle, "20d")
    add("Quiet task session", .idle, "5d"); add("Recent task session", .idle, "2d")
    task("Launch", ["In task", "Waiting in task", "Kept in task"], quietDays: 30)   // sessions need you: in play whatever the note says
    task("Open task", ["Open in task"], quietDays: 30)                            // a session open in Duo: in play
    task("Quiet", ["Quiet task session"], quietDays: 40)
    task("Recent session", ["Recent task session"], quietDays: 40)                // a session ran 2 days ago
    task("Recent note", [], quietDays: 1)                                         // its note changed yesterday
    task("Old line", [], quietDays: 12)
    task("Older line", [], quietDays: 70)
    task("Done lately", [], quietDays: 1, status: "done")
    task("Done long ago", [], quietDays: 9, status: "done")
    let director = DirectorSlotInfo(sessionId: "id-Director", workers: 2, workersNeedYou: 1, replaced: [.init(sessionId: "id-Old director", ago: "2h")])
    func sections(director: DirectorSlotInfo? = director, open: Set<String> = ["id-Open one", "id-Old director", "id-Open in task"], kept: Set<String> = ["id-Director", "id-Kept", "id-Kept in task"]) -> [SidebarSection] {
        SidebarRow.sections(for: p, in: f, isOpen: { open.contains($0) }, isPinned: { kept.contains($0) }, director: director,
                            listedTask: { $0.status != "dropped" }, now: noon, calendar: cal)
    }
    let secs = sections()
    func rows(_ id: String) -> [String] { secs.first { $0.id == id }?.rows.map(\.name) ?? [] }

    check(secs.map(\.id) == ["pinned", "needs", "open", "tasks", "later", "today", "week", "earlier"], "sections in order: pinned, needs you, open, tasks, later, today, this week, earlier")
    check(rows("pinned") == ["Director", "Old director", "Kept in task", "Kept"], "PINNED: the director, a replaced director still open, then the kept sessions, most recent first")
    check(secs[0].rows[0].slot == .director(open: false, needsYou: false, workers: 2, workersNeedYou: 1, projects: nil), "the director's row carries its slot")
    check(secs[0].rows[1].slot == .replaced(ago: "2h"), "a replaced director's row says when it was replaced")
    check(Set(rows("needs")) == ["Waiting in task", "Waiting alone"], "a waiting session leaves its task for NEEDS YOU, with the ones in no task")
    check(rows("open") == ["Open one"], "OPEN: open sessions in no task, not pinned or waiting")
    let launch = secs.first { $0.id == "tasks" }?.rows.first { $0.name == "Launch" }
    check(launch?.state == .needsYou, "a task keeps its state while its session waits (the hand shows)")
    if case .group(let threads, let n)? = launch?.kind {
        check(threads.map(\.name) == ["In task"] && n == 3, "a pinned or waiting session leaves its task for its section, and the task still counts it")
    } else { check(false, "the task is a group row") }
    check(Set(rows("tasks")) == ["Launch", "Open task", "Recent session", "Recent note", "Done lately"], "in play: a live session, a session or its note within 3 days, a done task that was quiet less than 3 days")
    check(rows("tasks").last == "Done lately", "a done task sinks below the tasks in play")
    check(Set(rows("later")) == ["Quiet", "Old line", "Older line", "Done long ago"], "Later: every task not in play, a done one after 3 quiet days included")
    check(rows("later") == ["Quiet", "Done long ago", "Old line", "Older line"], "Later lists the most recent first")
    check(secs.first { $0.id == "later" }?.rows.first { $0.name == "Quiet" }?.age == "5d" && secs.first { $0.id == "later" }?.rows.first { $0.name == "Older line" }?.age == "2mo"
          && secs.first { $0.id == "later" }?.rows.first { $0.name == "Old line" }?.age == "12d", "ages read 5d, 12d, 2mo")
    check(["today", "week", "earlier"].flatMap(rows).sorted() == ["Old one", "Today one", "Week one"], "OTHER SESSIONS holds the sessions in no task that aren't open, pinned or waiting")
    check(!(secs.flatMap(\.rows).contains { $0.name == "Open in task" }) && launch != nil, "a task's open tabs stay under their task")

    // The slot is keyed by session id, never by name.
    let byName = SidebarRow.sections(for: p, in: f, isOpen: { _ in false }, isPinned: { _ in false },
                                     director: DirectorSlotInfo(sessionId: "director-checkout"), now: noon, calendar: cal)
    check(!byName.contains { $0.id == "pinned" } && byName.flatMap(\.rows).allSatisfy { $0.slot == nil }, "a director on record whose session isn't listed makes no slot, and no row is promoted by its name")
    let noDirector = sections(director: nil, kept: [])
    check(!noDirector.contains { $0.id == "pinned" }, "with no director and nothing kept, PINNED isn't shown")
    check(sections(director: nil, kept: ["id-Kept"]).first?.rows.map(\.name) == ["Kept"], "Keep Running alone shows PINNED")
    let waitingDirector = SidebarRow.sections(for: p, in: { var g = f; g.sessions = g.sessions.map { var s = $0; if s.name == "Director" { s.state = .needsYou }; return s }; return g }(), isOpen: { _ in true },
                                              isPinned: { _ in false }, director: director, now: noon, calendar: cal)
    check(waitingDirector.first { $0.id == "pinned" }?.rows.first?.name == "Director" && !(waitingDirector.first { $0.id == "needs" }?.rows.contains { $0.name == "Director" } ?? false),
          "a director that needs you keeps its slot and isn't repeated in NEEDS YOU")

    // The flat list the pane draws.
    let items = SidebarItem.items(secs, tasksShown: true, folded: { $0 == "earlier" || $0 == "later" })
    let ids = items.map(\.id)
    func at(_ id: String) -> Int { ids.firstIndex(of: id)! }
    check(at("section/pinned") < at("section/needs") && at("section/needs") < at("section/open") && at("section/open") < at("section/tasks")
          && at("section/tasks") < at("section/later") && at("section/later") < at("section/tasks-tail") && at("section/tasks-tail") < at("section/other"),
          "PINNED, NEEDS YOU, OPEN, TASKS, the Later fold, the tail, then OTHER SESSIONS")
    check(!ids.contains { $0.hasSuffix("Old line.md") } && ids.contains("section/later"), "a folded Later keeps its row and hides its tasks")
    let opened = SidebarItem.items(secs, tasksShown: true, folded: { $0 == "earlier" }).map(\.id)
    check(opened.contains { $0.hasSuffix("Old line.md") }, "an opened Later lists its tasks")
    let indented = items.compactMap { i -> Bool? in if case .row(let r, let ind) = i.kind, ["Open one", "Today one", "Kept"].contains(r.name) { return ind }; return nil }
    check(indented.sorted { !$0 && $1 } == [false, false, true], "OPEN and PINNED rows sit at the top level; sessions in a time group are indented")
    var none = f
    none.sessions.removeAll { $0.project == p }; none.groups.removeAll { $0.project == p }; none.tasks = []
    let empty = SidebarRow.sections(for: p, in: none, isOpen: { _ in false }, now: noon, calendar: cal)
    let eItems = SidebarItem.items(empty, tasksShown: true, folded: { _ in false }).map(\.id)
    check(eItems == ["section/tasks", "section/tasks-tail"], "with no sessions and no tasks only TASKS shows, with its tail (the explainer and New task)")
    check(SidebarItem.items(empty, tasksShown: false, folded: { _ in false }).isEmpty, "outside a live project there is no TASKS section")
    // DL-130: a held list knows the new sections.
    let held = SidebarRow.held(secs, order: Dictionary(uniqueKeysWithValues: secs.map { ($0.id, $0.rows.map(\.id)) }))
    check(held.map(\.id) == secs.map(\.id), "a held list keeps PINNED and Later in their places")
}

/// The sidebar's height split (DL-219).
@MainActor func sidebarSplitChecks() {
    print("sidebar height: sessions and files share it 50/50 only when both are long (DL-219)")
    let t: CGFloat = 800
    let a = SidebarHeights.split(total: t, sessions: 200, files: 900)
    check(a.sessions == 200 && a.files == 600, "sessions short: they take only their content and the files get the rest")
    let b = SidebarHeights.split(total: t, sessions: 900, files: 150)
    check(b.sessions == 650 && b.files == 150, "files short: they take only their content and the sessions get the rest")
    let c = SidebarHeights.split(total: t, sessions: 900, files: 1200)
    check(c.sessions == 400 && c.files == 400, "both long: half each")
    let d = SidebarHeights.split(total: t, sessions: 300, files: 200)
    check(d.sessions == 600 && d.files == 200, "both short: the files keep their content, the sessions take the white space")
    let e = SidebarHeights.split(total: t, sessions: 400, files: 700)
    check(e.sessions == 400 && e.files == 400, "exactly half is enough for the sessions: the files get the other half")
    let z = SidebarHeights.split(total: 0, sessions: 5, files: 5)
    check(z.sessions == 0 && z.files == 0, "no height, no sections")
}
