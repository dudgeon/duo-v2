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

    // A /branch transcript's first records carry forkedFrom (F-359); the head read finds it with the first user record
    let branchFile = root.appending(path: "branch.jsonl")
    try Data(#"{"type":"user","uuid":"u1","parentUuid":null,"sessionId":"new-x","forkedFrom":{"sessionId":"old-x","messageUuid":"u1"},"timestamp":"2026-10-20T10:00:00.000Z","message":{"role":"user","content":"hi"}}"#.utf8 + Data("\n".utf8)).write(to: branchFile)
    check(ThreadCache().declaredParents([("new-x", branchFile)]) == ["new-x": "old-x"], "a transcript naming forkedFrom gives its parent without the shared-uuid lineage")

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

// /fork: a job in Claude's background whose parent is one of Duo's tabs gets an attach tab, with a stand-in `claude`
// that records how it was started (no daemon, no turn).
@MainActor func forkAdoptChecks() throws {
    print("fork tabs: /fork adopts a daemon fork as an attach tab (DL-227)")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: "fa-\(UUID().uuidString.prefix(6))")
    let config = root.appending(path: "cfg"), support = root.appending(path: "sup"), proj = root.appending(path: "proj")
    for d in [config.appending(path: "jobs"), support, proj.appending(path: "tasks")] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    let argvFile = root.appending(path: "argv")
    let script = "#!/bin/sh\necho \"$@\" >> '\(argvFile.path)'\nwhile read x; do :; done\n"
    let claude = root.appending(path: "claude")
    try Data(script.utf8).write(to: claude)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
    let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    setenv("CLAUDE_CONFIG_DIR", config.path, 1)
    DuoState.update { $0.claudePath = claude.path }
    ClaudeLocator.forget()
    let parent = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", fork = "cccccccc-cccc-cccc-cccc-cccccccccccc", other = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    try Data("---\ntitle: Pricing\nstatus: open\nsessions:\n  - \"[Pricing research](duo2://session/\(parent))\"\n---\n# Pricing\n".utf8).write(to: proj.appending(path: "tasks/pricing.md"))
    var fx = try repoFixture()
    fx.groups = []
    let json: [String: Any] = ["name": "Pricing research", "project": "p", "state": "idle", "wait": "1m", "sessionId": parent]
    fx.sessions = [try JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: json))]
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["p"] = proj
    _ = m.terminals.session(parent, command: .shell, cwd: proj.path)
    m.parkedTabs = [parent]
    m.consoleTab = parent
    defer {
        m.terminals.existing(parent)?.terminate(); m.terminals.existing(fork)?.terminate(); m.terminals.existing(other)?.terminate()
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        ClaudeLocator.forget()
        try? fm.removeItem(at: root)
    }
    func job(_ short: String, parent p: String, fork f: String) throws {
        let d = config.appending(path: "jobs/\(short)")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(#"{"forkParentSessionId":"\#(p)","forkSessionId":"\#(f)","needs":"send a prompt to start"}"#.utf8).write(to: d.appending(path: "state.json"))
    }
    // The first look sets the baseline: a job that was already there opens nothing.
    try job("00000000", parent: parent, fork: other)
    var snap = m.fixture
    m.adoptForks(into: &snap)
    check(m.terminals.existing(other) == nil && snap.sessions.count == 1, "a fork that was there before Duo looked opens no tab")
    // A fork made after, of a Duo tab
    try job("ab12cd34", parent: parent, fork: fork)
    m.adoptForks(into: &snap)
    check(m.terminals.existing(fork) != nil, "the fork gets a terminal")
    let added = snap.sessions.first { $0.sessionId == fork }
    check(added?.fork == "fork" && added?.forkParent == parent && added?.forkOf == "Pricing research", "it is listed at once (no transcript yet), as a fork of its parent")
    check(m.consoleTab == parent, "the original stays selected, focus where it was")
    check(m.consoleTabOrder["p"] == [parent, fork], "the fork's tab is right of its original")
    check(SessionIndex.load(project: proj).sessions.first { $0.sessionId == fork }?.fork == "fork", "it is filed forked-from the original, as a fork")
    let note = try String(contentsOf: proj.appending(path: "tasks/pricing.md"), encoding: .utf8)
    check(note.contains("duo2://session/\(fork)"), "it joins the original's task")
    check(m.expandedGroups.contains("p/thread/\(parent)"), "the thread opens by itself")
    let until = Date().addingTimeInterval(5)
    while !((try? String(contentsOf: argvFile, encoding: .utf8))?.contains("attach") ?? false), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check((try? String(contentsOf: argvFile, encoding: .utf8))?.contains("attach ab12cd34") == true, "the tab runs `claude attach ‹short›`")
    m.adoptForks(into: &snap)
    check(snap.sessions.filter { $0.sessionId == fork }.count == 1, "a fork already adopted isn't adopted again")
    // Detach: closing the tab leaves the session and its row; opening it attaches again.
    m.fixture = snap
    var live = m.fixture
    if let i = live.sessions.firstIndex(where: { $0.sessionId == fork }) { live.sessions[i].liveProcess = true; live.sessions[i].name = "Fork row" }
    m.fixture = live
    m.closeSession(fork)
    check(m.terminals.existing(fork) == nil && m.detachedForks.contains(fork), "closing the attach tab detaches")
    check(!m.tabSessions(inProject: "p").contains { $0.tabKey == fork } && m.fixture.sessions.contains { $0.sessionId == fork }, "its tab is gone, its row stays")
    m.open(project: "p", session: "Fork row")
    check(!m.detachedForks.contains(fork), "opening its row brings it back to attach again")
}
