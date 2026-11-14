import AppKit
import DuoControl
import DuoKit
import Foundation

// Multi-window slice 0 (DL-311, F-537, C-146): two window models on one AppCore. Each window keeps its
// own altitude, tabs and split room; what follows the project is shared; and the live loop and the
// app-wide passes run once per refresh, not once per window. `DUO_CHECKS=core swift run DuoChecks`.
@MainActor func appCoreChecks() throws {
    print("app core: two windows on one core (multi-window slice 0, C-146)")
    _ = NSApplication.shared   // the Dock badge (notifyNeedsYou) needs an application
    let f = try repoFixture()
    let core = AppCore(fixture: f)
    let one = AppModel(core: core), two = AppModel(core: core)
    check(core.models.count == 2 && core.primary === one, "two models on the core; the first made is the primary")
    check(core.keyModel === one, "no key window yet: menus act on the primary")
    check(core.model(for: .any) === one && core.model(for: .project("nowhere")) === one, "a question with no window of its own shows in the primary")

    // Each window's own state
    let project = f.projects.first { $0.name != f.home?.name }?.name ?? ""
    one.open(project: project)
    check(one.altitude == .project(project) && two.altitude == .allProjects, "altitude is per window")
    check(core.model(for: .project(project)) === one, "a question about a project shows in the window showing it")
    one.consoleTab = "a-tab"; two.consoleTab = "b-tab"
    check(one.consoleTab == "a-tab" && two.consoleTab == "b-tab", "the console tab is per window")
    one.splits.peek = true
    check(one.splits.peek && !two.splits.peek, "the split's room and peek are per window")
    check(one.search !== two.search && one.editors !== two.editors, "search and the editors are per window")

    // What follows the project
    one.openDocumentsByProject[project, default: []].append("notes.md")
    check(two.openDocumentsByProject[project] == one.openDocumentsByProject[project], "a project's open documents are shared")
    one.splits.tabs[project] = [:]
    check(two.splits.tabs.keys.contains(project), "a project's split tabs are shared")
    one.zoomOut()
    check(two.lastConsoleTab[project] == "a-tab", "the tab a project was left on is shared")
    one.shellTabs[project] = ["shell-1"]
    check(two.shells(inProject: project) == ["shell-1"], "a project's shells are shared")
    check(one.terminals === two.terminals && one.chats === two.chats, "one terminal store and one chat store")
    check(one.voice === two.voice, "one microphone for the app")
    one.shellTabs[project] = nil

    // The loop: started from both windows, it runs once
    core.startLoop(); core.startLoop()
    check(core.passCounts["loop"] == 1, "the 2 s loop starts once, however many windows start it")
    core.stopLoop()

    // A refresh asked for by both windows: one scan, one of each app-wide pass, each window's own part twice
    let snapshot = f
    core.snapshotSource = { _, _ in (snapshot, folders: [:], moves: []) }
    core.isLive = true
    func waitApplied(_ n: Int) {
        let until = Date().addingTimeInterval(10)
        while (core.passCounts["apply"] ?? 0) < n, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    two.refreshLive()
    one.refreshLive()   // a scan is in flight: this one waits for the next tick
    waitApplied(1)
    let c = core.passCounts
    check(c["scan"] == 1 && c["apply"] == 1, "one scan and one snapshot for two windows (scan \(c["scan"] ?? 0), apply \(c["apply"] ?? 0))")
    for pass in ["notify", "prune", "deliver", "gitignore", "move"] {
        check(c[pass] == 1, "\(pass) ran once for the refresh (\(c[pass] ?? 0))")
    }
    check((c["archive"] ?? 0) <= 1, "the archive pass ran at most once (\(c["archive"] ?? 0))")
    check(c["window-refresh"] == 2, "each window's own part ran once per window (\(c["window-refresh"] ?? 0))")
    // The loop's tick, from the core: the same, once (2 s later on the core's clock: DL-318 paces the tick)
    let later = Date().addingTimeInterval(3)
    core.clock = { later }
    core.tick()
    waitApplied(2)
    let d = core.passCounts
    check(d["scan"] == 2 && d["notify"] == 2 && d["deliver"] == 2 && d["prune"] == 2, "a tick refreshes once more, not once per window")
    check(d["trust"] == 1, "the trust screens are read once per tick")
    check((d["archive"] ?? 0) <= 1, "the archive pass keeps its once a minute across windows")
    core.isLive = false

    try backoffChecks()

    // A model made alone still has its own core: the checks and the harness are unchanged
    let alone = AppModel(fixture: f)
    check(alone.core !== core && alone.core.primary === alone, "a model made from a fixture has a core of its own")
}
