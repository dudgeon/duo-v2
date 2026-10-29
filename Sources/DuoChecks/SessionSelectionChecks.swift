import DuoKit
import Foundation

/// Selecting several sessions (DL-247, session-multiselect-handoff): the clicks, the runs a fill joins, the menu's
/// counts, and Delete n Sessions… touching nothing outside the selection.
@MainActor func sessionSelectionChecks(_ base: Fixture) {
    print("select several sessions: ⇧ ranges, ⌘ toggles, nothing opens, delete only what's selected (DL-247)")
    let b = SessionSelection.breaker
    let order = ["a", "b", b, "c", "d", "e"]
    var s = SessionSelection()

    check(s.click("a", .plain, list: "L", order: order) && s.isEmpty && s.anchor == "a", "a plain click opens, selects nothing and anchors")
    check(!s.click("d", .shift, list: "L", order: order) && s.keys == ["a", "b", "c", "d"], "⇧-click selects anchor to row on screen, skipping a row that isn't a session")
    s.click("b", .shift, list: "L", order: order)
    check(s.keys == ["a", "b"], "a new ⇧-click replaces the last ⇧ range, as in Finder")
    check(!s.click("e", .command, list: "L", order: order) && s.keys == ["a", "b", "e"] && s.anchor == "e", "⌘-click adds a row and anchors it")
    s.click("c", .shift, list: "L", order: order)
    check(Set(s.keys) == ["a", "b", "c", "d", "e"], "⇧ after ⌘ keeps what was selected and adds the range from the ⌘ row")
    s.click("b", .command, list: "L", order: order)
    check(!s.contains("b") && s.count == 4, "⌘-click on a selected row takes it out")
    check(s.run("a", order: order) == .single && s.run("c", order: order) == .top && s.run("d", order: order) == .middle
          && s.run("e", order: order) == .bottom && s.run("b", order: order) == .none, "neighbouring selected rows join; ends are rounded; unselected rows have no fill")
    s.click("a", .plain, list: "L", order: order)
    check(s.isEmpty, "a plain click clears the selection")
    s.click("c", .command, list: "L", order: order)
    s.click("x", .command, list: "M", order: ["x"])
    check(s.keys == ["x"] && s.list == "M", "a click in another list starts over")
    var fresh = SessionSelection()
    fresh.click("d", .shift, list: "L", order: order)
    check(fresh.keys == ["d"] && fresh.anchor == "d", "⇧-click with no anchor selects that row alone")
    fresh.click("zz", .plain, list: "L", order: order)
    fresh.click("e", .shift, list: "L", order: order)
    check(fresh.keys == ["e"], "an anchor no longer showing ranges from nowhere: the row alone")
    fresh.selectAll(list: "L", order: order)
    check(fresh.keys == ["a", "b", "c", "d", "e"], "⌘A selects every session row showing, never a breaker")
    fresh.keepOnly(["a", "e"])
    check(fresh.keys == ["a", "e"], "sessions that left the list leave the selection")
    fresh.clear()
    check(fresh.isEmpty, "Esc clears")

    // The app: a modified click never opens or resumes, parked sessions included (Geoff: "without them opening if parked").
    do {
        let m = AppModel(fixture: base)
        m.selectionOrders["L"] = order
        var opened: [String] = []
        m.sessionRowClicked("a", .plain, list: "L") { opened.append("a") }
        m.sessionRowClicked("d", .shift, list: "L") { opened.append("d") }
        m.sessionRowClicked("e", .command, list: "L") { opened.append("e") }
        check(opened == ["a"] && Set(m.sessionSelection.keys) == ["a", "b", "c", "d", "e"],
              "⇧- and ⌘-click select without opening; only the plain click opened")
        check(m.selectionRun("d", list: "L") == .middle && m.selectionRun("d", list: "other") == .none, "a row's fill is its own list's")
    }

    // Delete n Sessions…: parked, live and archived sessions mixed; only the selected ones that can go, go.
    do {
        let root = URL(fileURLWithPath: "/tmp/duo-ms-\(UUID().uuidString.prefix(8))")
        let fm = FileManager.default
        let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p")
        for d in [support, config.appending(path: "projects"), config.appending(path: "sessions"), proj] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try? Data("# p\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
        let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR", "DUO_AUTOCONFIRM"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
        setenv("DUO_SUPPORT_DIR", support.path, 1)
        setenv("CLAUDE_CONFIG_DIR", config.path, 1)
        setenv("DUO_AUTOCONFIRM", "1", 1)
        defer {
            for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
            try? fm.removeItem(at: root)
        }
        func id(_ n: Int) -> String { "bbbbbbbb-0000-4000-8000-00000000000\(n)" }
        let names = ["Parked one", "Parked two", "Live one", "Archived one", "Kept one"]
        let bucket = config.appending(path: "projects/" + ClaudeStorage.encode(proj.path))
        try? fm.createDirectory(at: bucket, withIntermediateDirectories: true)
        for (i, _) in names.enumerated() {
            try? Data("{\"type\":\"user\",\"cwd\":\"\(proj.path)\",\"sessionId\":\"\(id(i))\"}\n".utf8).write(to: bucket.appending(path: "\(id(i)).jsonl"))
        }
        // The live one runs outside Duo: its beacon names a running process (this one).
        try? Data(#"{"pid":\#(getpid()),"sessionId":"\#(id(2))","cwd":"\#(proj.path)","status":"busy"}"#.utf8).write(to: config.appending(path: "sessions/\(getpid()).json"))
        func session(_ i: Int, _ state: SessionState) -> Fixture.Session {
            try! JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: ["name": names[i], "project": "multi", "state": state.rawValue, "wait": "1h", "sessionId": id(i)]))
        }
        var fx = base
        fx.projects.append(try! JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "multi", "topic": "Platform", "path": proj.path, "goal": "g"])))
        fx.sessions += [session(0, .idle), session(1, .idle), session(2, .working), session(4, .idle)]
        fx.archivedSessions = (fx.archivedSessions ?? []) + [session(3, .idle)]
        let m = AppModel(fixture: fx)
        m.terminalsMode = .live
        m.liveFolders["multi"] = proj
        m.liveElsewhere = [id(2)]
        DuoState.update { $0.archivedSessions = [id(3)] }
        func onDisk(_ i: Int) -> Bool { fm.fileExists(atPath: bucket.appending(path: "\(id(i)).jsonl").path) }

        let keys = [0, 2, 3].map { i in (fx.sessions + (fx.archivedSessions ?? [])).first { $0.sessionId == id(i) }!.tabKey }
        let counts = m.selectionCounts(keys.compactMap { k in (m.fixture.sessions + (m.fixture.archivedSessions ?? [])).first { $0.tabKey == k } })
        check(counts.archive.count == 1 && counts.unarchive.count == 1, "the menu counts what each item will do: Archive 1 (not the running one), Unarchive 1")

        var said = ""
        m.deleteSessions(keys) { r in if case .success(let t) = r { said = t } else if case .failure(let e) = r { said = "failed: \(e)" } }
        check(!onDisk(0) && !onDisk(3), "Delete n Sessions… deletes the parked and the archived session selected (\(said))")
        check(onDisk(2) && said.contains("Live one"), "a selected session running outside Duo is left out, and named")
        check(onDisk(1) && onDisk(4), "a session outside the selection is never touched")
        check(!DuoState.load().archivedSessions.contains(id(3)), "the deleted archived session leaves Duo's archive list")
    }
}
