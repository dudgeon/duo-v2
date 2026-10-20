import DuoKit
import Foundation

// DL-227, DL-228: /branch splits instead of re-keying, /fork opens an attach tab, forks join their original's tasks, and
// the pane lists a thread as one row placed by its liveliest member.
@MainActor func forkChecks(_ base: Fixture) throws {
    print("fork tabs and threads: /branch splits, /fork attaches, one thread row (DL-227, DL-228)")

    // Telling the cases apart: the SessionStart source and the pid
    check(ForkSource.classify(source: "fork", ownsPid: true, parentIsDuoTab: false) == .branch, "fork with Duo's own pid is /branch")
    check(ForkSource.classify(source: "fork", ownsPid: false, parentIsDuoTab: true) == .fork, "fork from a daemon whose parent is a Duo tab is /fork")
    check(ForkSource.classify(source: "fork", ownsPid: false, parentIsDuoTab: false) == nil, "a fork of a session outside Duo is none of Duo's")
    check(ForkSource.classify(source: "clear", ownsPid: true, parentIsDuoTab: false) == nil
          && ForkSource.classify(source: "resume", ownsPid: true, parentIsDuoTab: false) == nil
          && ForkSource.classify(source: nil, ownsPid: true, parentIsDuoTab: false) == nil, "/clear and /resume keep re-keying")

    // The parent from the files: a /fork job's state.json, a /branch transcript's forkedFrom
    let root = FileManager.default.temporaryDirectory.appending(path: "fork-checks-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: root) }
    let job = root.appending(path: "jobs/ab12cd34")
    try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
    try Data(#"{"forkParentSessionId":"parent-1","forkSessionId":"fork-1","needs":"send a prompt to start"}"#.utf8).write(to: job.appending(path: "state.json"))
    let plain = root.appending(path: "jobs/ff00ff00")
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    try Data(#"{"state":"done"}"#.utf8).write(to: plain.appending(path: "state.json"))
    let jobs = ForkSource.jobs(in: root)
    check(jobs == [ForkSource.Job(short: "ab12cd34", parent: "parent-1", sessionId: "fork-1", needs: "send a prompt to start")], "a job with forkParentSessionId is a fork; another isn't")
    check(ForkSource.forkedFrom(records: [["type": "queue"], ["forkedFrom": ["sessionId": "old-1", "messageUuid": "m"]]]) == "old-1", "forkedFrom names the /branch parent")
    check(ForkSource.forkedFrom(records: [["type": "user"]]) == nil, "no forkedFrom, no parent")

    // Placement: right of the original, wherever it is
    check(ForkPlacement.inserting("b", after: "a", in: ["a", "x", "y"]) == ["a", "b", "x", "y"], "the new tab goes right after its original")
    check(ForkPlacement.inserting("b", after: "y", in: ["a", "x", "y"]) == ["a", "x", "y", "b"], "…at the end when the original is last")
    check(ForkPlacement.inserting("b", after: "x", in: ["a", "x", "b", "y"]) == ["a", "x", "b", "y"], "…and a tab already there is moved, not doubled")
    check(ForkThread.ordered([("f1", "o"), ("o", nil), ("f2", "f1")]) == ["o", "f1", "f2"], "a thread lists the original first, then its forks by age (a fork of a fork too)")

    let oldId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", newId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    // /branch splits; /clear re-keys. A project on disk with a task that holds the original.
    let project = root.appending(path: "proj")
    try FileManager.default.createDirectory(at: project.appending(path: "tasks"), withIntermediateDirectories: true)
    try Data("---\ntitle: Pricing\nstatus: open\nsessions:\n  - \"[Pricing research](duo2://session/\(oldId))\"\n---\n# Pricing\n".utf8).write(to: project.appending(path: "tasks/pricing.md"))
    var f = base
    f.sessions.removeAll { $0.project == "p" }
    for (id, name) in [(oldId, "Pricing research"), ("other-1", "Other"), ("tail-1", "Tail")] {
        f.sessions.append(session(name, .idle, "1m", id: id))
    }
    let m = AppModel(fixture: f)
    m.liveFolders["p"] = project
    m.consoleTabOrder["p"] = ["other-1", oldId, "tail-1"]
    m.parkedTabs = ["other-1", oldId, "tail-1"]
    m.consoleTab = oldId
    let old = f.sessions.first { $0.tabKey == oldId }!
    m.noteSessionStart(newId, source: "fork")
    check(m.isBranch(newId: newId, from: oldId, folder: project), "the hook's source fork on the terminal's own process is /branch")
    check(!m.isBranch(newId: "new-2", from: oldId, folder: project), "a start with no fork source is not")
    m.splitBranch(from: old, to: newId, folder: project)
    check(m.consoleTab == newId, "the branch is selected: that's where you're typing")
    check(m.consoleTabOrder["p"] == ["other-1", oldId, newId, "tail-1"], "the branch's tab is right of the original, in the original's place (\(m.consoleTabOrder["p"] ?? []))")
    let entry = SessionIndex.load(project: project).sessions.first { $0.sessionId == newId }
    check(entry?.provenance == "forked-from:\(oldId)" && entry?.fork == "branch", "the branch is filed forked-from the original, as a branch")
    let note = try String(contentsOf: project.appending(path: "tasks/pricing.md"), encoding: .utf8)
    check(note.contains("duo2://session/\(oldId)") && note.contains("duo2://session/\(newId)"), "the branch joins the original's task, which keeps it")
    check(m.expandedGroups.contains("p/thread/\(oldId)"), "the thread opens by itself")
    check(m.detachedForks.isEmpty, "a branch is not a detached fork")

    // The pane: one thread row, the original's name, placed by its liveliest member
    var g = base
    g.sessions.removeAll { $0.project == "p" }
    func add(_ name: String, _ st: SessionState, _ wait: String, fork: String? = nil, id: String? = nil) {
        var s = session(name, st, wait, id: id ?? name)
        if let fork { s.forkOf = fork; s.forkParent = fork; s.fork = "branch" }
        g.sessions.append(s)
    }
    add("Pricing research", .idle, "20m"); add("Pricing research (Branch)", .working, "now", fork: "Pricing research"); add("Fork two", .idle, "3m", fork: "Pricing research")
    let rows = SidebarRow.rows(for: "p", in: g)
    guard let thread = rows.first, case .thread(let n, let members) = thread.kind else { return check(false, "forks fold into one thread row") }
    check(rows.count == 1 && n == 3, "a session and its forks are one row")
    check(thread.name == "Pricing research" && thread.state == .working, "the folded row keeps the original's name and shows the most urgent member's state")
    check(members.map(\.name) == ["Pricing research", "Pricing research (Branch)", "Fork two"] && members.map(\.isFork) == [false, true, true], "open: the original first, its forks after")
    let open = SidebarRow.sections(for: "p", in: g, isOpen: { $0 == "Pricing research (Branch)" })
    check(open.first?.id == "open" && open.first?.sessionCount == 3, "a thread with one open member is in OPEN, counted by its sessions")
    let quiet = SidebarRow.sections(for: "p", in: g.settingStates(["Pricing research (Branch)": .idle]), isOpen: { _ in false })
    check(quiet.first.map { ["today", "week", "earlier"].contains($0.id) } == true && quiet.first?.rows.first?.wait == "now", "with none open, it goes where its most recent member would")
    let waiting = SidebarRow.sections(for: "p", in: g.settingStates(["Pricing research (Branch)": .needsYou]), isOpen: { _ in true })
    check(waiting.first?.id == "needs" && waiting.first?.rows.first?.name == "Pricing research (Branch)" && waiting.first?.rows.first?.showsOrigin == true
          && waiting.first?.rows.first?.forkOf == "Pricing research", "a fork that needs you leaves for NEEDS YOU with \"Fork of ‹original›\"")
    if case .thread(let rest, _)? = waiting.dropFirst().first?.rows.first?.kind { check(rest == 2, "the rest of the thread stays") } else { check(false, "the rest of the thread stays in OPEN") }
    let origWaiting = SidebarRow.sections(for: "p", in: g.settingStates(["Pricing research": .needsYou]), isOpen: { _ in true })
    check(origWaiting.first?.rows.first?.name == "Pricing research" && origWaiting.first?.rows.first?.showsOrigin == false, "the original needing you leaves with no second line")
}

private func session(_ name: String, _ state: SessionState, _ wait: String, id: String) -> Fixture.Session {
    let json = ["name": name, "project": "p", "state": state.rawValue, "wait": wait, "sessionId": id]
    return try! JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: json))
}

extension Fixture {
    /// This fixture with some sessions (by name) in other states.
    func settingStates(_ states: [String: SessionState]) -> Fixture {
        var f = self
        for i in f.sessions.indices { if let s = states[f.sessions[i].name] { f.sessions[i].state = s } }
        return f
    }
}
