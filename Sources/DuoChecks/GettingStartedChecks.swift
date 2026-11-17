import DuoControl
import DuoKit
import Foundation

/// DL-348 (first-run-welcome-handoff): the new-install rule, the ticks, Hide with Undo, Done, Help › Getting Started,
/// and the duo2 verbs and Help menu that go with the card.
@MainActor func gettingStartedChecks(_ base: Fixture) {
    print("getting started (DL-348)")
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "duo-gs-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: dir) }

    // The new-install rule (F-673): neither chat.json nor state.json.
    let fresh = dir.appending(path: "fresh")
    try? fm.createDirectory(at: fresh, withIntermediateDirectories: true)
    check(NewInstall.detect(support: fresh), "an empty support folder is a new install")
    check(GettingStarted.seedIfNewInstall(support: fresh), "a new install is seeded")
    let seeded = DuoState.load(fresh.appending(path: "state.json")).gettingStarted
    check(seeded?.phase == .showing && seeded?.count == 0, "with the card showing and nothing ticked")
    check(ChatPrefs.load(fresh.appending(path: "chat.json")).mode(for: "x") == .chat, "and the chat default (DL-339) still saw a new install")
    check(!NewInstall.detect(support: fresh) && !GettingStarted.seedIfNewInstall(support: fresh), "it is seeded once")
    for file in ["state.json", "chat.json"] {
        let old = dir.appending(path: "old-" + file)
        try? fm.createDirectory(at: old, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: old.appending(path: file))
        check(!GettingStarted.seedIfNewInstall(support: old) && DuoState.load(old.appending(path: "state.json")).gettingStarted == nil, "an install with \(file) never gets the card")
    }

    // Ticks come from the real action, are kept, and never un-tick.
    let url = fresh.appending(path: "state.json")
    let g = GettingStarted(url: url)
    check(g.visible && g.count == 0 && !g.ticked(.project), "the card shows at 0 of 3")
    g.tick(.session, detail: "chat|Outline the Q4 plan")
    check(g.ticked(.session) && !g.ticked(.project) && g.count == 1, "a tick is its step's alone")
    g.tick(.session, detail: "terminal|other")
    check(g.detail(.session) == "chat|Outline the Q4 plan", "the first tick's words are kept")
    check(GettingStarted(url: url).ticked(.session), "ticks survive a relaunch")
    check(GettingStartedWords.line(.session, detail: "chat|Outline the Q4 plan") == "“Outline the Q4 plan” · in Chat. Terminal is one click on its tab."
          && GettingStartedWords.line(.session, detail: "terminal|") == "Started in Terminal. Chat is one click on its tab.", "a ticked session says what was done and its mode")
    check(!g.allDone && { g.done(); return g.visible }(), "Done waits for all three")

    // Hide with Undo.
    g.hide()
    check(!g.visible && g.noticeOpen && g.state?.phase == .hidden, "Hide hides the card and leaves the notice")
    g.tick(.project, detail: "p · ~/p")
    check(g.ticked(.project), "ticks still count while it is hidden")
    g.undoHide()
    check(g.visible && !g.noticeOpen && g.count == 2, "Undo brings it back as it was")

    // Done, after all three.
    g.tick(.task, detail: "t · p")
    check(g.allDone, "three ticks is all done")
    g.done()
    check(!g.visible && g.state?.phase == .done && GettingStarted(url: url).state?.phase == .done, "Done folds it away for good")
    g.tick(.task, detail: "again")
    check(g.detail(.task) == "t · p", "and a done card records nothing more")

    // Help › Getting Started brings it back for anyone; on an install that never had it, from what Duo can see.
    g.show()
    check(g.visible && g.count == 3, "Help › Getting Started brings it back, ticked as it stands")
    let never = GettingStarted(url: dir.appending(path: "never.json"))
    check(never.state == nil && !never.visible, "an existing install has no card")
    never.show(inferred: [.project: "p · ~/p"])
    check(never.visible && never.ticked(.project) && !never.ticked(.session), "and Help starts it, ticking what is already done")

    // A tick from a Duo action: opening a project (step 1) and not Home.
    let saved = GettingStarted.shared.state
    GettingStarted.shared.hold(GettingStartedState())
    let model = AppModel(fixture: base)
    if let p = model.fixture.projects.first(where: { $0.isHome != true && !$0.isFolderOnly }) {
        model.open(project: p.name)
        check(GettingStarted.shared.ticked(.project), "opening a project ticks step 1")
    }
    GettingStarted.shared.hold(GettingStartedState())
    if let home = model.fixture.projects.first(where: { $0.isHome == true }) {
        model.open(project: home.name)
        check(!GettingStarted.shared.ticked(.project), "opening Home doesn't")
    }
    GettingStarted.shared.hold(saved)

    // duo2 and Help.
    check(DuoAction.resolve(["getting-started", "show"])?.0.id.rawValue == "getting-started", "duo2 getting-started")
    check(DuoAction.resolve(["explain", "director"])?.0.id.rawValue == "explain", "duo2 explain")
    check(ExplainerID.allCases.map(\.rawValue).sorted() == ["director", "home", "modes", "projects", "tasks"], "five explainers, as X1 lists")
    let commands = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Navigation/Commands.swift"), encoding: .utf8)) ?? ""
    let order = ["item(.gettingStarted)", "item(.duoGuide)", "Menu(\"Explain\")", "item(.explainProjects)", "item(.explainModes)", "item(.explainTasks)", "item(.explainHome)", "item(.explainDirector)", "item(.duo2Reference)", "item(.reportIssue)"]
    let at = order.compactMap { commands.range(of: $0)?.lowerBound }
    check(at.count == order.count && at == at.sorted(), "the Help menu is in X1's order")
}
