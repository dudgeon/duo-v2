import DuoControl
import DuoKit
import Foundation

// ENH-042, DL-220: tabs move along their strip (a drag, Move Tab Left / Right, duo2 view tab-move).
@MainActor func tabOrderChecks() throws {
    print("tab order: moving tabs along their strip (DL-220)")

    // apply
    check(TabOrder.apply([], to: ["a", "b", "c"]) == ["a", "b", "c"], "apply: no order keeps the strip's own")
    check(TabOrder.apply(["c", "a", "b"], to: ["a", "b", "c"]) == ["c", "a", "b"], "apply: the user's order")
    check(TabOrder.apply(["c", "a"], to: ["a", "b", "c", "d"]) == ["c", "a", "b", "d"], "apply: tabs the order doesn't name follow, as they come")
    check(TabOrder.apply(["x", "b", "b", "a"], to: ["a", "b"]) == ["b", "a"], "apply: closed tabs and repeats in the order are skipped")

    // moved
    check(TabOrder.moved(["a", "b", "c"], "b", by: -1) == ["b", "a", "c"], "moved: left")
    check(TabOrder.moved(["a", "b", "c"], "b", by: 1) == ["a", "c", "b"], "moved: right")
    check(TabOrder.moved(["a", "b", "c"], "a", by: -1) == nil && TabOrder.moved(["a", "b", "c"], "c", by: 1) == nil, "moved: not past either end")
    check(TabOrder.moved(["a", "b", "c"], "z", by: 1) == nil, "moved: a tab not on the strip")
    check(TabOrder.moved(["a", "b", "c"], "a", to: 2) == ["b", "c", "a"] && TabOrder.moved(["a", "b", "c"], "a", to: 0) == nil, "moved: to a place; its own place is no move")

    // dropped: the pointer against the other tabs' middles
    let mids: [(key: String, midX: CGFloat)] = [("a", 20), ("b", 80), ("c", 140), ("d", 200)]
    check(TabOrder.dropped(["a", "b", "c", "d"], "a", pointerX: 100, middles: mids) == ["b", "a", "c", "d"], "dropped: past b's middle, after b")
    check(TabOrder.dropped(["a", "b", "c", "d"], "a", pointerX: 70, middles: mids) == nil, "dropped: short of b's middle, no move")
    check(TabOrder.dropped(["a", "b", "c", "d"], "d", pointerX: 5, middles: mids) == ["d", "a", "b", "c"], "dropped: left of everything, first")
    check(TabOrder.dropped(["a", "b", "c", "d"], "a", pointerX: 400, middles: mids) == ["b", "c", "d", "a"], "dropped: right of everything, last")
    check(TabOrder.dropped(["a", "b", "c", "d", "e"], "a", pointerX: 400, middles: mids) == ["b", "c", "d", "a", "e"], "dropped: past the last tab on screen, before the hidden ones")
    check(TabOrder.dropped(["b", "c"], "b", pointerX: 400, middles: [("P", 10), ("b", 80), ("c", 140)]) == ["c", "b"], "dropped: a tab that doesn't move (Project) isn't a place")

    // The model: the console
    let f = try repoFixture()
    let m = AppModel(fixture: f)
    TargetState.project.apply(to: m)
    let project = m.currentProject?.name ?? ""
    let console = m.consoleTabKeys(inProject: project)
    check(console.count >= 2, "the console has tabs to move (\(console.count))")
    check(m.movableTabKeys(in: .middle) == console, "every console tab moves")
    check(!m.canMoveTab(console[0], in: .middle, by: -1) && m.canMoveTab(console[0], in: .middle, by: 1), "Move Tab Left is dimmed on the first tab, Right isn't")
    check(m.moveTab(console[0], in: .middle, by: 1) && m.consoleTabKeys(inProject: project) == [console[1], console[0]] + console.dropFirst(2), "Move Tab Right: the first tab goes one along")
    check(m.tabKeys(in: .middle) == m.consoleTabKeys(inProject: project), "⌃Tab steps the moved order")
    check(!m.moveTab(m.consoleTabKeys(inProject: project).last!, in: .middle, by: 1), "Move Tab Right on the last tab does nothing")
    m.moveTab(console[1], in: .middle, to: console.count - 1)
    check(m.consoleTabKeys(inProject: project).last == console[1], "a drop puts a tab at a place")

    // The right pane: documents move; Project stays first
    m.openDocuments = ["docs/a.md", "docs/b.md", "docs/c.md"]
    check(m.movableTabKeys(in: .right) == ["docs/a.md", "docs/b.md", "docs/c.md"], "the right pane's documents move")
    check(m.rightTabKeys().first == "Project" && !m.canMoveTab("docs/a.md", in: .right, by: -1), "the first document can't pass Project")
    m.moveTab("docs/c.md", in: .right, by: -1)
    check(m.openDocuments == ["docs/a.md", "docs/c.md", "docs/b.md"] && m.rightTabKeys().filter { $0.hasPrefix("docs/") && $0 != "docs/prd-v2.md" } == ["docs/a.md", "docs/c.md", "docs/b.md"], "Move Tab Left on a document; a group page stays where it is (\(m.rightTabKeys()))")
    check(m.paneOfMovableTab("docs/b.md") == .right && m.paneOfMovableTab(console[0]) == .middle && m.paneOfMovableTab("Project") == nil, "each tab's strip")

    // duo2 view tab-move
    func cli(_ args: [String]) -> (ok: Bool, out: String) {
        var r: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()))) { r = $0 }
        return (r?.ok ?? false, r?.output ?? "")
    }
    var r = cli(["view tab-move", "right", "docs/a.md"])
    check(r.ok && m.openDocuments == ["docs/c.md", "docs/a.md", "docs/b.md"], "verb: right, by path (\(r.out))")
    r = cli(["view tab-move", "1", "docs/b.md"])
    check(r.ok && m.openDocuments.first == "docs/b.md" && r.out.contains("place 1 of 3"), "verb: to place 1 (\(r.out))")
    r = cli(["view tab-move", "left", "docs/b.md"])
    check(!r.ok && r.out.contains("already the first"), "verb: refuses past the end, saying why (\(r.out))")
    r = cli(["view tab-move", "left", "Project"])
    check(!r.ok, "verb: Project doesn't move")
    m.activate(.middle, focus: false)
    m.consoleTab = m.consoleTabKeys(inProject: project)[1]
    let sel = m.consoleTab!
    r = cli(["view tab-move", "left"])
    check(r.ok && m.consoleTabKeys(inProject: project).first == sel, "verb: the active pane's selected tab by default (\(r.out))")
    r = cli(["view tab-move", "9"])
    check(!r.ok && r.out.contains("place is 1 to"), "verb: a place off the strip is refused")

    // Closing a tab selects its left neighbour in the strip's order (F-347)
    check(TabOrder.neighbour(closing: "c", in: ["a", "b", "c", "d"]) == "b" && TabOrder.neighbour(closing: "a", in: ["a", "b"]) == "b" && TabOrder.neighbour(closing: "a", in: ["a"]) == nil, "neighbour: the left one, the new first, none")
    for i in 1...6 { m.shellTabs[project, default: []].append("shell:chk\(i)") }
    var strip = m.consoleTabKeys(inProject: project)
    let mid = strip[strip.count - 4]
    m.consoleTab = mid
    m.closeShell(mid)
    check(m.consoleTab == strip[strip.count - 5], "closing a tab in the middle of the shells selects its left neighbour, not the first session")
    strip = m.consoleTabKeys(inProject: project)
    m.consoleTab = strip[0]
    m.closeShell(strip.first { $0.hasPrefix("shell:chk") }!)
    check(m.consoleTab == strip[0], "closing a tab that isn't selected leaves the selection")
    m.shellTabs[project] = nil

    // Restore keeps a moved console order, by session id
    var s = RestoreState.Project(folder: "/x", sessions: ["s2", "s1"], consoleTab: nil, documents: [], rightTab: nil, tabOrder: ["s2", "s1"])
    let data = try JSONEncoder().encode(s)
    s = try JSONDecoder().decode(RestoreState.Project.self, from: data)
    check(s.tabOrder == ["s2", "s1"], "restore: the order is written and read back")
    let old = try JSONDecoder().decode(RestoreState.Project.self, from: Data(#"{"folder":"/x","sessions":[],"documents":[]}"#.utf8))
    check(old.tabOrder == nil, "restore: a file from before it reads with no order")
}
