import DuoControl
import DuoKit
import Foundation

// Parking (DL-192): who can park, the Keep Running pin, the memory-pressure question, and a park
// then a show end to end with stand-in claudes that record their arguments (never a real claude).
@MainActor func parkChecks() throws {
    print("parking sessions on demand (DL-192)")

    // Eligibility, in priority order.
    func inputs(_ change: (inout ParkInputs) -> Void = { _ in }) -> ParkInputs { var i = ParkInputs(); change(&i); return i }
    let snapshotArgv = ["/bin/zsh", "-c", "source /Users/x/.claude/shell-snapshots/snapshot-zsh-1791-ab.sh 2>/dev/null || true && eval 'sleep 240'"]
    let mcpArgv = ["/opt/homebrew/bin/node", "/Users/x/mcp/server.js", "--stdio"]
    let caffeinateArgv = ["/usr/bin/caffeinate", "-i", "-t", "300"]
    check(ParkCheck.why(inputs()) == nil, "an idle Claude tab at its prompt can park")
    check(ParkCheck.why(inputs { $0.state = .readyForReview }) == nil, "so can one whose finished turn is waiting to be reviewed")
    check(ParkCheck.why(inputs { $0.isShell = true; $0.keepRunning = true; $0.state = .working }) == .shell, "a shell never parks, whatever else is true")
    check(ParkCheck.why(inputs { $0.hasTerminal = false }) == .notRunning && ParkCheck.why(inputs { $0.hasTerminal = false; $0.parked = true }) == .alreadyParked,
          "no process in Duo: not running, or already parked")
    check(ParkCheck.why(inputs { $0.keepRunning = true; $0.state = .working }) == .keepRunning, "Keep Running beats what the tab is doing")
    check(ParkCheck.why(inputs { $0.state = .working; $0.children = [snapshotArgv] }) == .working, "working comes before a background shell")
    check(ParkCheck.why(inputs { $0.state = .needsYou }) == .needsYou, "a tab waiting on you stays")
    check(ParkCheck.why(inputs { $0.children = [snapshotArgv] }) == .background, "a child running a shell-snapshots command (Bash or Monitor) blocks")
    check(ParkCheck.why(inputs { $0.children = [mcpArgv, caffeinateArgv] }) == nil, "an MCP server and caffeinate beside Claude do not")
    check(ParkCheck.why(inputs { $0.children = [mcpArgv, snapshotArgv] }) == .background, "...but a command among them does")
    let started = HookEvents.Event(name: "SubagentStart", agentId: "a1"), stopped = HookEvents.Event(name: "SubagentStop", agentId: "a1")
    check(ParkCheck.why(inputs { $0.events = [started] }) == .subagent, "SubagentStart without its Stop blocks")
    check(ParkCheck.why(inputs { $0.events = [started, stopped] }) == nil, "...and with the Stop does not")
    check(ParkCheck.why(inputs { $0.events = [started, HookEvents.Event(name: "SubagentStart", agentId: "a2"), stopped] }) == .subagent, "two subagents, one stopped: still blocked")
    check(ParkCheck.runningSubagents([started, HookEvents.Event(name: "SessionStart")]) == 0, "a restarted process (SessionStart) forgets a subagent the old one never stopped")
    check(ParkCheck.why(inputs { $0.onScreen = true }) == nil && ParkCheck.why(inputs { $0.onScreen = true }, bulk: true) == .onScreen,
          "on screen blocks the bulk command only")
    check(ParkBlock.working.why == "is working" && ParkBlock.needsYou.why == "is waiting on you" && ParkBlock.background.why == "is running something in the background"
          && ParkBlock.subagent.why == "has a subagent running" && ParkBlock.keepRunning.why == "is set to Keep Running" && ParkBlock.onScreen.why == "is on screen",
          "each block's reason reads as the handoff words it")

    // Real child processes of this process: what ProcessTable reads from the system.
    do {
        let snap = Process(); snap.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        snap.arguments = ["-e", "sleep 20", "--", "/tmp/cfg/shell-snapshots/snapshot-zsh-1-x.sh"]
        let caf = Process(); caf.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate"); caf.arguments = ["-i", "-t", "300"]
        try caf.run()
        defer { caf.terminate(); snap.terminate() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let mine = ProcessTable.children(of: getpid())
        check(mine.contains { $0.contains("-t") && $0.first?.hasSuffix("caffeinate") == true } && !ParkCheck.hasBackgroundWork(mine),
              "ProcessTable lists a real child's argv, and caffeinate is not background work")
        try snap.run()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(ParkCheck.hasBackgroundWork(ProcessTable.children(of: getpid())), "a real child with /shell-snapshots/snapshot- in its argv is")
    }

    // The notice (park-handoff, menus).
    check(ParkCheck.notice(parked: 4, kept: []) == "Parked 4 sessions. Each picks up where it left off when you show it.", "notice: all parked")
    check(ParkCheck.notice(parked: 3, kept: [("Buyer interviews", .needsYou), ("Release watcher", .keepRunning)])
          == "Parked 3 sessions. 2 kept running: “Buyer interviews” is waiting on you, “Release watcher” is set to Keep Running.", "notice: some kept, with why")
    check(ParkCheck.notice(parked: 0, kept: [("x", .working)]) == "No idle sessions to park: “x” is working.", "notice: none could park, says why")
    check(ParkCheck.notice(parked: 0, kept: []) == "No idle sessions to park.", "notice: nothing running")

    // Hooks: SubagentStart/Stop are registered for every CLI (2.1.219 accepts them).
    do {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-park-hooks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = try HookEvents.settingsFile(for: "a", in: dir, cli: "/x/duo2")
        let hooks = (try JSONSerialization.jsonObject(with: Data(contentsOf: plain)) as? [String: Any])?["hooks"] as? [String: Any] ?? [:]
        check(hooks["SubagentStart"] != nil && hooks["SubagentStop"] != nil && hooks["MessageDisplay"] == nil, "SubagentStart and SubagentStop are logged without chat's events")
    }

    // Keep Running persists, and an old state file without it still decodes.
    do {
        let url = FileManager.default.temporaryDirectory.appending(path: "duo-park-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        DuoState.update(url) { $0.keepRunning = ["s1", "s2"] }
        check(DuoState.load(url).keepRunning == ["s1", "s2"], "Keep Running survives a relaunch (state round trip)")
        let old = try JSONDecoder().decode(DuoState.self, from: Data(#"{"seen":{},"archivedSessions":["a"]}"#.utf8))
        check(old.keepRunning.isEmpty && old.archivedSessions == ["a"], "a state file from before it decodes, with nothing pinned")
    }

    // One question per memory-pressure episode.
    do {
        let p = ParkPressure()
        var asks = 0, eligible = 3, sheet = false
        var pending: [() -> Void] = []
        p.eligible = { eligible }; p.sheetUp = { sheet }; p.ask = { asks += 1 }
        p.later = { _, work in pending.append { work() } }
        func runLater() { let w = pending; pending = []; w.forEach { $0() } }
        p.changed(to: .warning)
        check(asks == 0, "warning asks nothing")
        p.changed(to: .critical); p.changed(to: .critical)
        check(asks == 1, "critical asks once; a second critical in the episode doesn't")
        p.changed(to: .warning); p.changed(to: .critical)
        check(asks == 1, "warning between is still the same episode")
        p.changed(to: .normal); p.changed(to: .critical)
        check(asks == 2, "back to normal, then critical: asked again")
        p.changed(to: .normal); eligible = 0; p.changed(to: .critical)
        check(asks == 2 && !p.asked, "nothing eligible: not asked")
        p.changed(to: .normal); eligible = 3; sheet = true; p.changed(to: .critical)
        check(asks == 2 && pending.count == 1, "another sheet up: it waits, retrying")
        runLater(); check(asks == 2 && pending.count == 1, "still up: waits again")
        sheet = false; runLater()
        check(asks == 3 && pending.isEmpty, "the sheet gone: asked")
        p.changed(to: .normal); sheet = true; p.changed(to: .critical)
        p.changed(to: .warning); sheet = false; runLater()
        check(asks == 3, "pressure eased while waiting: dropped")
    }

    try parkEndToEnd()
}

@MainActor private func parkEndToEnd() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-park-\(UUID().uuidString.prefix(8))")
    let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p"), solo = root.appending(path: "q")
    let log = root.appending(path: "claude.log")
    for d in [support, config, proj, solo] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try Data("# p\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
    try Data("# q\n".utf8).write(to: solo.appending(path: "PROJECT.md"))
    let script = """
    #!/usr/bin/python3
    import os, sys, json
    a = sys.argv[1:]
    if a == ["--version"]: print("2.1.292 (Claude Code)"); sys.exit(0)
    if a == ["--help"]: print("Options:\\n  --resume [value]   Resume a conversation"); sys.exit(0)
    open("\(log.path)", "a").write("ARGS " + json.dumps(a) + "\\n")
    sid = a[a.index("--session-id") + 1] if "--session-id" in a else a[a.index("--resume") + 1]
    d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "sessions"); os.makedirs(d, exist_ok=True)
    json.dump({"pid": os.getpid(), "sessionId": sid, "cwd": os.getcwd(), "status": "idle"}, open(os.path.join(d, "%d.json" % os.getpid()), "w"))
    while os.read(0, 4096): pass
    """
    let claude = root.appending(path: "claude")
    try Data(script.utf8).write(to: claude)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

    let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    setenv("CLAUDE_CONFIG_DIR", config.path, 1)
    DuoState.update { $0.claudePath = claude.path }
    ClaudeLocator.forget()
    var models: [AppModel] = []
    defer {
        for m in models { for s in m.fixture.sessions { m.terminals.existing(s.tabKey)?.terminate() } }
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        ClaudeLocator.forget()
        try? fm.removeItem(at: root)
    }

    var fx = try repoFixture()
    for (name, dir) in [("parkproj", proj), ("soloproj", solo)] {
        fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": name, "topic": "Platform", "path": dir.path, "goal": "g"])))
    }
    func model(_ fixture: Fixture) -> AppModel {
        let m = AppModel(fixture: fixture)
        m.terminalsMode = .live
        m.liveFolders["parkproj"] = proj
        m.liveFolders["soloproj"] = solo
        m.parkChildren = { _ in [] }
        m.parkEvents = { _ in [] }
        models.append(m)
        return m
    }
    func wait(_ what: () -> Bool) { let until = Date().addingTimeInterval(8); while !what(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    var seen = 0
    func argsFor(_ id: String) -> [String] {
        let until = Date().addingTimeInterval(10)
        while Date() < until {
            let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            if let i = lines.indices.dropFirst(seen).first(where: { lines[$0].contains(id) }) {
                seen = i + 1
                return (try? JSONSerialization.jsonObject(with: Data(lines[i].dropFirst(5).utf8))) as? [String] ?? []
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return []
    }
    func setState(_ m: AppModel, _ id: String, _ state: SessionState) {
        if let i = m.fixture.sessions.firstIndex(where: { $0.sessionId == id }) { m.fixture.sessions[i].state = state }
    }

    let m = model(fx)
    m.open(project: "parkproj")
    let a = m.newSession(in: "parkproj")!, b = m.newSession(in: "parkproj")!, c = m.newSession(in: "parkproj")!, d = m.newSession(in: "parkproj")!
    for id in [a, b, c, d] { _ = argsFor(id); setState(m, id, .idle) }
    m.consoleTab = a
    setState(m, b, .working)
    setState(m, d, .needsYou)

    check(m.parkBlock(a) == nil && m.parkBlock(a, bulk: true) == .onScreen, "the tab on screen can park by itself, not in bulk")
    check(m.parkBlock(b, bulk: true) == .working && m.parkBlock(d, bulk: true) == .needsYou && m.parkBlock(c, bulk: true) == nil, "working and waiting tabs stay; an idle one off screen can park")
    m.parkChildren = { _ in [["/bin/zsh", "-c", "source /c/shell-snapshots/snapshot-zsh-1.sh && sleep 9"]] }
    check(m.parkBlock(c, bulk: true) == .background, "a tab with a command running in the background stays (through the model's process probe)")
    m.parkChildren = { _ in [] }
    m.parkEvents = { id in id == c ? [HookEvents.Event(name: "SubagentStart", agentId: "z")] : [] }
    check(m.parkBlock(c, bulk: true) == .subagent, "...and one with a subagent")
    m.parkEvents = { _ in [] }

    // Keep Running.
    m.setKeepRunning(d, true)
    check(m.isKeepRunning(d) && DuoState.load().keepRunning.contains(d) && m.parkBlock(d, bulk: true) == .keepRunning, "Keep Running is remembered and blocks")
    let relaunched = model(fx)
    relaunched.loadKeepRunning()
    check(relaunched.isKeepRunning(d) && !relaunched.isKeepRunning(c), "a relaunched Duo reads the pins")

    // Park Background Sessions.
    let report = m.parkBackground(notify: false)
    check(report.parked.compactMap(\.sessionId) == [c] && Set(report.kept.compactMap(\.session.sessionId)) == [b, d], "Park Background Sessions parks the idle tab off screen and keeps the rest")
    check(report.text.hasPrefix("Parked 1 session. 2 kept running: ") && report.text.contains(" is working") && report.text.contains(" is set to Keep Running"), "and says why (\(report.text))")
    wait { m.terminals.existing(c) == nil && m.terminals.closingCount == 0 }
    check(m.parkedTabs.contains(c) && m.terminals.existing(c) == nil && m.tabSessions(inProject: "parkproj").contains { $0.tabKey == c }, "parked: no terminal, the tab stays in its strip")
    check(m.terminals.existing(a) != nil && m.terminals.existing(b) != nil && m.terminals.existing(d) != nil, "the others are untouched")
    check(m.parkBlock(c) == .alreadyParked, "a parked tab can't be parked again")
    check(m.currentRestoreState().projects.flatMap(\.sessions).contains(c), "the restore file keeps a parked tab")

    // Showing it resumes the same session.
    let projectPath = proj.resolvingSymlinksInPath().path
    let bucket = config.appending(path: "projects").appending(path: ClaudeStorage.encode(projectPath))
    try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
    try Data("{\"type\":\"user\",\"cwd\":\"\(projectPath)\",\"sessionId\":\"\(c)\"}\n".utf8).write(to: bucket.appending(path: c + ".jsonl"))
    let shown = m.terminal(project: "parkproj", session: c)
    let resumed = argsFor(c)
    check(shown?.command == .resumeClaude(sessionID: c, remoteControl: nil) && resumed.contains("--resume") && resumed.contains(c), "showing a parked tab resumes it with --resume and the same session id (\(resumed.prefix(2)))")

    // Park the tab on screen: the pane moves to the next tab first.
    check(m.consoleTab == a && m.park(a) == nil && m.consoleTab != a && m.consoleTab != nil, "parking the tab on screen gives its pane to another tab")
    wait { m.terminals.existing(a) == nil }
    check(m.parkedTabs.contains(a) && m.terminals.existing(a) == nil, "and parks it")

    // Pin a parked tab: it wakes.
    m.parkedTabs.insert(b); setState(m, b, .idle)
    m.terminals.close(b); wait { m.terminals.existing(b) == nil && m.terminals.closingCount == 0 }
    try Data("{\"type\":\"user\",\"cwd\":\"\(projectPath)\",\"sessionId\":\"\(b)\"}\n".utf8).write(to: bucket.appending(path: b + ".jsonl"))
    m.setKeepRunning(b, true)
    check(m.terminals.existing(b) != nil, "pinning a parked tab resumes it")

    // The only tab in its pane can't be parked.
    let m2 = model(fx)
    m2.open(project: "soloproj")
    let only = m2.newSession(in: "soloproj")!
    _ = argsFor(only); setState(m2, only, .idle)
    m2.consoleTab = only
    check(m2.park(only) == .onScreen && m2.terminals.existing(only) != nil, "a pane's only tab is refused as on screen")

    // The question.
    var many = (0..<8).map { i -> Fixture.Session in
        var s = m.fixture.sessions.first { $0.sessionId == c }!
        s.name = "Session \(i)"; s.lastActive = Date().addingTimeInterval(-7200).timeIntervalSince1970 * 1000
        return s
    }
    let q8 = m.parkQuestion(many)
    check(q8.title == "Your Mac is low on memory. Park 8 idle sessions?" && q8.items.count == 6 && q8.items[5].what == "and 3 more"
          && q8.items[0].detail == "\(many[0].project) · 2h" && q8.choices.map(\.label) == ["Not Now", "Park 8 Sessions"] && q8.choices[1].isDefault && q8.choices[0].isCancel,
          "the question: title, first 5 tabs with project · idle time, then “and 3 more”, Not Now and Park N Sessions")
    many.removeLast(2)
    check(m.parkQuestion(many).items.count == 6 && m.parkQuestion(many).items.last?.what == "Session 5", "six tabs are all listed")

    // Critical pressure, end to end: the question goes up, and its default parks what can park.
    setState(m, c, .idle)
    let c2 = m.newSession(in: "parkproj")!
    _ = argsFor(c2); setState(m, c2, .idle)
    let p = m.makeParkPressure()
    SheetCenter.shared.cancelCurrent()
    p.changed(to: .critical)
    let asked = SheetCenter.shared.current
    check(asked?.title.hasPrefix("Your Mac is low on memory. Park ") == true, "critical memory pressure puts the question up on Duo's own sheet (\(asked?.title ?? "none"))")
    if let asked, let go = asked.choices.first(where: \.isDefault) { SheetCenter.shared.answer(go) }
    wait { m.parkedTabs.contains(c2) && m.terminals.existing(c2) == nil }
    check(m.parkedTabs.contains(c2) && SheetCenter.shared.current == nil, "Park N Sessions parks the idle tabs, and the window says nothing more")
}
