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

    // A folded fork thread (DL-250, Geoff): ⌘-click or a ⇧ range takes in the original and every fork, the thread
    // unfolds, and ⌘-click then takes any one out.
    do {
        var t = SessionSelection()
        let tOrder = ["x", "orig", "y"]
        let threads = ["orig": ["orig", "fork1", "fork2"]]
        t.click("orig", .command, list: "T", order: tOrder)
        check(t.takeInThreads(threads) == ["orig"] && t.keys == ["orig", "fork1", "fork2"], "⌘-click on a folded thread selects the original and every fork")
        t.click("fork1", .command, list: "T", order: ["x", "orig", "fork1", "fork2", "y"])
        check(t.keys == ["orig", "fork2"], "then ⌘-click takes one out, as for any row")
        var r = SessionSelection()
        r.click("x", .plain, list: "T", order: tOrder)
        r.click("y", .shift, list: "T", order: tOrder)
        r.takeInThreads(threads)
        check(Set(r.keys) == ["x", "orig", "fork1", "fork2", "y"], "a ⇧ range across a folded thread takes in all its sessions")
        var u = SessionSelection()
        u.click("x", .command, list: "T", order: tOrder)
        check(u.takeInThreads(threads).isEmpty && u.keys == ["x"], "a thread outside the selection stays as it is")

        let m = AppModel(fixture: base)
        m.selectionOrders["T"] = tOrder
        m.selectionThreads["T"] = ["orig": (fold: "p/thread/orig", members: ["orig", "fork1", "fork2"])]
        var opened = 0
        m.sessionRowClicked("orig", .command, list: "T") { opened += 1 }
        check(opened == 0 && m.expandedGroups.contains("p/thread/orig") && Set(m.sessionSelection.keys) == ["orig", "fork1", "fork2"],
              "in the pane the thread unfolds, nothing opens, and all its sessions are selected")
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

    // Geoff, 2026-10-29: "can you delete the parent and keep a child fork?" A /branch fork is its own transcript, holding
    // a copy of the parent's messages and `forkedFrom` naming it. Delete the parent: the fork's file is untouched and it
    // stays listed, as a plain session (no thread, no "Fork of"). scripts/check-fork-parent-delete.sh proves the CLI side.
    do {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/tmp/duo-fp-\(UUID().uuidString.prefix(8))")
        let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "forky")
        for d in [support, config.appending(path: "projects"), proj] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try? Data("# forky\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
        let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR", "DUO_AUTOCONFIRM"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
        setenv("DUO_SUPPORT_DIR", support.path, 1); setenv("CLAUDE_CONFIG_DIR", config.path, 1); setenv("DUO_AUTOCONFIRM", "1", 1)
        defer {
            for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
            try? fm.removeItem(at: root)
        }
        let parent = "cccccccc-0000-4000-8000-000000000001", fork = "cccccccc-0000-4000-8000-000000000002"
        let bucket = config.appending(path: "projects/" + ClaudeStorage.encode(proj.path))
        try? fm.createDirectory(at: bucket, withIntermediateDirectories: true)
        func line(_ sid: String, _ type: String, _ uuid: String, _ parentUuid: String?, _ text: String, _ ts: String, forked: Bool) -> String {
            var r: [String: Any] = ["type": type, "uuid": uuid, "sessionId": sid, "cwd": proj.path, "timestamp": ts,
                                    "message": ["role": type, "content": text]]
            r["parentUuid"] = parentUuid ?? NSNull()
            if forked { r["forkedFrom"] = ["sessionId": parent, "messageUuid": "u-a1"] }
            return String(data: try! JSONSerialization.data(withJSONObject: r), encoding: .utf8)! + "\n"
        }
        let shared = [("user", "u-u1", nil as String?, "Plan the launch", "2026-10-29T10:00:00Z"), ("assistant", "u-a1", "u-u1", "Here's a plan", "2026-10-29T10:00:05Z")]
        let parentText = shared.map { line(parent, $0.0, $0.1, $0.2, $0.3, $0.4, forked: false) }.joined()
        let forkText = shared.map { line(fork, $0.0, $0.1, $0.2, $0.3, $0.4, forked: true) }.joined()
            + line(fork, "user", "u-u2", "u-a1", "Now the email", "2026-10-29T10:05:00Z", forked: true)
        let pURL = bucket.appending(path: "\(parent).jsonl"), fURL = bucket.appending(path: "\(fork).jsonl")
        try? Data(parentText.utf8).write(to: pURL); try? Data(forkText.utf8).write(to: fURL)
        func snapshot(_ ids: [String]) -> (Fixture, [String: URL]) {
            var c = LiveSnapshot.Context(root: nil)
            c.includeHistory = false
            c.historyOverride = ids.map { (id: $0, transcript: bucket.appending(path: "\($0).jsonl"), cwd: proj.path) }
            let (f, folders, _) = LiveSnapshot.build(c, beacons: [])
            return (f, folders)
        }
        let (before, folders) = snapshot([parent, fork])
        let f0 = before.sessions.first { $0.sessionId == fork }
        let rows0 = SidebarRow.rows(for: "forky", in: before)
        check(f0?.forkParent == parent && f0?.forkOf != nil && rows0.count == 1 && { if case .thread(2, _) = rows0[0].kind { return true } else { return false } }(),
              "before: the fork names its parent (forkedFrom) and the two are one thread")
        let m = AppModel(fixture: before)
        m.terminalsMode = .live
        m.liveFolders = folders
        let pKey = before.sessions.first { $0.sessionId == parent }!.tabKey
        var said = ""
        m.deleteSession(pKey) { r in said = "\(r)" }
        check(!fm.fileExists(atPath: pURL.path) && (try? String(contentsOf: fURL, encoding: .utf8)) == forkText,
              "deleting the parent leaves the fork's transcript byte for byte, its copy of the parent's messages included (\(said.prefix(60)))")
        let (after, _) = snapshot([fork])
        let f1 = after.sessions.first { $0.sessionId == fork }
        let rows1 = SidebarRow.rows(for: "forky", in: after)
        check(f1 != nil && f1?.forkOf == nil && rows1.count == 1 && rows1[0].kind == .session,
              "after: the fork is still listed, as a plain session row (no thread, no Fork of)")
        let m2 = AppModel(fixture: after)
        check(m2.forkParentName(of: f1!.tabKey) == nil, "its console tab names no parent")
    }
}
