import DuoKit
import Foundation

/// The project pane's hierarchy (DL-174): NEEDS YOU, TASKS, OTHER SESSIONS and its time groups.
@MainActor func sidebarHierarchyChecks(_ base: Fixture) {
    print("project pane hierarchy: needs you, tasks, other sessions by time (DL-174)")
    var f = base
    let p = "checkout-redesign"
    f.sessions.removeAll { $0.project == p }
    f.groups.removeAll { $0.project == p }
    func add(_ name: String, _ st: SessionState, _ wait: String) {
        let json = ["name": name, "project": p, "state": st.rawValue, "wait": wait]
        f.sessions.append(try! JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    add("In task", .idle, "2h"); add("Waiting in task", .needsYou, "5m"); add("Waiting alone", .needsYou, "9m")
    add("Open one", .working, "1m"); add("Today one", .idle, "3h"); add("Week one", .idle, "3d"); add("Old one", .idle, "20d")
    let group: [String: Any] = ["name": "Launch", "project": p, "sessions": ["In task", "Waiting in task"], "threads": [["In task"], ["Waiting in task"]], "task": "tasks/launch.md"]
    f.groups.append(try! JSONDecoder().decode(Fixture.Group.self, from: JSONSerialization.data(withJSONObject: group)))
    let cal = Calendar.current
    let noon = cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: Date()))!
    let secs = SidebarRow.sections(for: p, in: f, isOpen: { $0 == "Open one" }, now: noon, calendar: cal)
    func rows(_ id: String) -> [String] { secs.first { $0.id == id }?.rows.map(\.name) ?? [] }

    check(secs.map(\.id) == ["needs", "tasks", "open", "today", "week", "earlier"], "sections in order: needs you, tasks, open, today, this week, earlier")
    check(Set(rows("needs")) == ["Waiting in task", "Waiting alone"], "a waiting session leaves its task for NEEDS YOU, with the ones in no task")
    let task = secs.first { $0.id == "tasks" }?.rows.first
    check(task?.name == "Launch" && task?.state == .needsYou, "its task row keeps the state: the hand shows meanwhile")
    if case .group(let threads, let n)? = task?.kind {
        check(threads.map(\.name) == ["In task"] && n == 2, "the task's own list holds the sessions that aren't waiting, and counts both")
    } else { check(false, "the task is a group row") }
    let others = ["open", "today", "week", "earlier"].flatMap(rows)
    check(Set(others) == ["Open one", "Today one", "Week one", "Old one"] && others.count == 4, "a task's sessions appear only under their task; the rest sit once in a time group")
    check(rows("open") == ["Open one"] && rows("today") == ["Today one"] && rows("week") == ["Week one"] && rows("earlier") == ["Old one"], "each lands in its time group")

    // The flat list the pane draws.
    let items = SidebarItem.items(secs, tasksShown: true, folded: { $0 == "earlier" })
    let ids = items.map(\.id)
    check(ids.firstIndex(of: "section/needs")! < ids.firstIndex(of: "section/tasks")!
          && ids.firstIndex(of: "section/tasks")! < ids.firstIndex(of: "section/tasks-tail")!
          && ids.firstIndex(of: "section/tasks-tail")! < ids.firstIndex(of: "section/other")!
          && ids.firstIndex(of: "section/other")! < ids.firstIndex(of: "section/open")!, "NEEDS YOU, then TASKS and its tail, then OTHER SESSIONS and the groups")
    check(!ids.contains { $0.hasSuffix("Old one") } && ids.contains("section/earlier"), "a folded group keeps its row and hides its sessions")
    let indented = items.compactMap { i -> Bool? in if case .row(let r, let ind) = i.kind, ["Open one", "Today one"].contains(r.name) { return ind }; return nil }
    check(indented == [true, true], "sessions in a time group are indented to the nested inset")
    let waiting = items.compactMap { i -> Bool? in if case .row(let r, let ind) = i.kind, r.name == "Waiting alone" { return ind }; return nil }
    check(waiting == [false], "NEEDS YOU rows are not indented")
    var none = f
    none.sessions.removeAll { $0.project == p }; none.groups.removeAll { $0.project == p }
    let empty = SidebarRow.sections(for: p, in: none, isOpen: { _ in false }, now: noon, calendar: cal)
    let eItems = SidebarItem.items(empty, tasksShown: true, folded: { _ in false }).map(\.id)
    check(eItems == ["section/tasks", "section/tasks-tail"], "with no sessions and no tasks only TASKS shows, with its tail (the explainer and New task)")
    check(SidebarItem.items(empty, tasksShown: false, folded: { _ in false }).isEmpty, "outside a live project there is no TASKS section")
}
