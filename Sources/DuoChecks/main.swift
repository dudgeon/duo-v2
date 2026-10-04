import DuoControl
import DuoKit
import DuoSearch
import Foundation

// Plain assertions, run with `swift run DuoChecks`. Exit status is the number of failures.

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func check(_ condition: @autoclosure () throws -> Bool, _ name: String, line: Int = #line) {
    do {
        if try condition() { passes += 1; print("  ✔ \(name)") }
        else { failures += 1; print("  ✘ \(name)  (line \(line))") }
    } catch {
        failures += 1; print("  ✘ \(name): \(error)  (line \(line))")
    }
}

func repoFixture() throws -> Fixture {
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { dir.deleteLastPathComponent() }
    return try Fixture.load(from: dir.appending(path: "docs/design/build-handoff/fixture.json"))
}

@MainActor func run() throws {
    let f = try repoFixture()

    print("fixture")
    check(f.topics == ["Payments", "Growth", "Platform"], "topics decode")
    check(f.home?.name == "home", "home project")
    check(f.sessions.count == 11, "eleven sessions")
    check(f.needsYou.map(\.name) == ["Morning triage", "Copy review pass 2", "PRD v2 edits"], "needs-you longest wait first")

    print("ordering")
    check(WaitTime("1h") > WaitTime("12m") && WaitTime("3d") > WaitTime("1h") && WaitTime("now") < WaitTime("4m"), "wait times")
    check(SessionState.allCases.sorted() == [.needsYou, .readyForReview, .working, .idle, .resolved], "states most urgent first")

    print("target states")
    let project = AppModel(fixture: f)
    TargetState.project.apply(to: project)
    check(project.needsYouElsewhere.count == 2, "chip counts only other projects (2 need you)")
    let zoom4 = AppModel(fixture: f)
    TargetState.flowZoom4.apply(to: zoom4)
    check(zoom4.fixture.counts.needsYou == 2 && zoom4.fixture.counts.working == 5, "flow-zoom-4 counts: 2 need you, 5 working")
    check(zoom4.fixture.needsYou.map(\.name) == ["Morning triage", "PRD v2 edits"], "flow-zoom-4 action column one card shorter")
    check(zoom4.selectedActionSession == "checkout-redesign/PRD v2 edits", "flow-zoom-4 selection")

    print("navigation")
    let nav = AppModel(fixture: f)
    TargetState.overview.apply(to: nav)
    nav.open(project: "checkout-redesign")
    check(nav.altitude == .project("checkout-redesign"), "tile opens the project")
    check(nav.consoleTab == "PRD v2 edits" && nav.rightTab == "docs/prd-v2.md", "opens on the session that needs you and its document [P]")
    check(nav.selectedSidebarItem == "PRD v2" && nav.expandedGroups.contains("PRD v2"), "its group is selected and expanded")
    check(nav.needsYouElsewhere.count == 2, "chip: 2 need you elsewhere")
    nav.togglePeek()
    check(nav.peekOpen && nav.peekSelection == "home/Morning triage", "peek opens on the longest wait")
    nav.movePeekSelection(by: 1)
    check(nav.peekSelection == "onboarding-v3/Copy review pass 2", "down arrow moves the peek selection")
    nav.movePeekSelection(by: 5)
    check(nav.peekSelection == "onboarding-v3/Copy review pass 2", "selection stops at the last card")
    nav.jumpToPeekSelection()
    check(nav.altitude == .project("onboarding-v3") && nav.consoleTab == "Copy review pass 2" && !nav.peekOpen, "cmd-return jumps into that project on that session")
    nav.zoomOut()
    check(nav.altitude == .allProjects && nav.selectedActionSession == "onboarding-v3/Copy review pass 2", "zooming out selects the session last in (flow-zoom-4)")
    nav.open(project: "checkout-redesign")
    nav.goHome()
    check(nav.altitude == .allProjects && nav.homeTab == "Morning triage" && nav.focusHomeRequest == 1, "shift-cmd-H: All projects, Home terminal focused")
    let tiles = AppModel(fixture: f)
    tiles.moveTileFocus(dx: 0, dy: 0)
    check(tiles.focusedTile == "checkout-redesign", "first arrow focuses the first tile")
    tiles.moveTileFocus(dx: 0, dy: 1)
    check(tiles.focusedTile == "refunds-api-spec", "down moves within a topic column")
    tiles.moveTileFocus(dx: 1, dy: 0)
    check(tiles.focusedTile == "pricing-experiment-q4", "right moves to the next topic, nearest row")
    tiles.moveTileFocus(dx: 1, dy: 0)
    check(tiles.focusedTile == "api-deprecations", "right clamps to the last row of a shorter column")
    let chords = DuoCommand.allCases.compactMap(\.shortcut).map { "\($0.key.character)\($0.modifiers.rawValue)" }
    check(chords.count == Set(chords).count, "no two commands share a chord")

    print("claude storage")
    check(ClaudeStorage.encode("/Users/geoff/repos/duo-v2") == "-Users-geoff-repos-duo-v2", "encode: slashes")
    check(ClaudeStorage.encode("/w/a.b_c d") == "-w-a-b-c-d", "encode: dots, underscores, spaces")
    check(ClaudeStorage.encode("/w/ünï-côde") == "-w--n--c-de", "encode: non-ASCII one dash per code point")
    let long = "/Users/geoff/" + String(repeating: "deep-folder/", count: 40)
    check(ClaudeStorage.encode(long).count > 200 && ClaudeStorage.encode(long).hasPrefix(String(ClaudeStorage.encode(String(long.prefix(300))).prefix(200)) + "-"), "encode: over 200 chars truncates and hashes")
    let cal = ClaudeStorage.calibrate()
    print("    calibration against ~/.claude/projects: \(cal.matched)/\(cal.checked) folders match, \(cal.collisions) collisions, \(cal.mismatches.count) mismatches")
    for m in cal.mismatches.prefix(5) { print("      ✘ \(m.folder) ← \(m.cwd) encodes to \(m.encoded)") }
    check(cal.ok, "encoder self-calibration on this machine")

    print("frontmatter")
    let fm = Frontmatter.parse("---\r\ntype: project\r\ntitle: \"Checkout, redesign\"\r\ntags: [a, \"b, c\"]\r\nwaiting_on:\r\n  - Priya\r\n  - \"[Legal](../people/legal.md)\"\r\n# a comment\r\nhealth: on-track\r\n---\r\nBody text\r\n")
    check(fm.string("type") == "project" && fm.string("title") == "Checkout, redesign", "scalars, quoted with a comma, CRLF")
    check(fm.list("tags") == ["a", "b, c"], "inline list with a quoted comma")
    check(fm.list("waiting_on") == ["Priya", "[Legal](../people/legal.md)"], "block list, quoted markdown link")
    check(fm.body == "Body text\n", "body after the fence")
    check(Frontmatter.parse("No frontmatter\n").values.isEmpty, "no fence: no values, no failure")

    print("project discovery")
    let ws = FileManager.default.temporaryDirectory.appending(path: "duo-checks-\(UUID().uuidString)")
    func write(_ rel: String, _ text: String) throws {
        let u = ws.appending(path: rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    try write("payments/checkout-redesign/PROJECT.md", "---\ntype: project\ngoal: Cut guest-checkout abandonment 15% by Q1\nhealth: on-track\nnext: Exec review Oct 14\n---\n")
    try write("payments/checkout-redesign/docs/inner/PROJECT.md", "---\ngoal: nested, ignored\n---\n")
    try write("growth/onboarding-v3/PROJECT.md", "---\ngoal: Lift day-7 activation to 40%\nhealth: at-risk\n---\n")
    try write("home/HOME.md", "---\ntype: home\ngoal: Triage\n---\n")
    try write("old-home/HOME.md", "---\ntype: home\n---\n")
    try write("node_modules/x/PROJECT.md", "---\n---\n")
    let found = ProjectDiscovery.scan(root: ws)
    check(found.map(\.project.name) == ["checkout-redesign", "onboarding-v3", "home", "old-home"].sorted { a, b in
        found.first { $0.project.name == a }!.folder.path < found.first { $0.project.name == b }!.folder.path }, "finds projects and homes, skips nested and node_modules")
    let checkout = found.first { $0.project.name == "checkout-redesign" }?.project
    check(checkout?.topic == "Payments" && checkout?.health == "On track" && checkout?.next == "Exec review Oct 14", "topic from parent folder, health label, next")
    let homes = ProjectDiscovery.chooseHome(found, remembered: ws.appending(path: "home").path)
    check(homes.home?.project.name == "home" && homes.contested, "two HOME.md: the remembered one wins, flagged as contested (DL-42)")
    try? FileManager.default.removeItem(at: ws)

    print("attention")
    func beacon(_ status: String, _ waiting: String? = nil) -> Beacon {
        Beacon(pid: 1, sessionId: "s", cwd: "/", name: nil, status: status, waitingFor: waiting, statusUpdatedAt: nil, entrypoint: nil, kind: nil)
    }
    check(Attention.state(for: beacon("waiting", "input needed")) == (.needsYou, .question), "waiting for input: needs you, question")
    check(Attention.state(for: beacon("waiting", "permission prompt")) == (.needsYou, .permission), "waiting for permission: needs you, permission")
    check(Attention.state(for: beacon("busy")).0 == .working, "busy: working")
    check(Attention.state(for: beacon("idle"), lastStopMessage: "Move saved cards into scope?").0 == .needsYou, "idle after a question: needs you")
    check(Attention.state(for: beacon("idle"), lastStopMessage: "Done.").0 == .idle, "idle after a statement: idle")
    let now = Date(timeIntervalSince1970: 10_000)
    check(Attention.waitText(since: 9_990_000, now: now) == "now" && Attention.waitText(since: 9_760_000, now: now) == "4m", "wait text")
    check(!Beacon.readAll().isEmpty, "reads live beacons on this machine")

    print("session index and live snapshot")
    let lw = FileManager.default.temporaryDirectory.appending(path: "duo-live-\(UUID().uuidString)")
    let proj = lw.appending(path: "payments/checkout-redesign")
    try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
    try "---\ngoal: \"Cut abandonment\"\nhealth: at-risk\n---\n".write(to: proj.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: lw.appending(path: "home"), withIntermediateDirectories: true)
    try "# Home\n".write(to: lw.appending(path: "home/HOME.md"), atomically: true, encoding: .utf8)
    var idx = SessionIndex()
    idx.sessions = [.init(sessionId: "aaaa-filed"), .init(sessionId: "bbbb-archived")]
    idx.sessions[1].archived = true
    idx.groups = [.init(name: "PRD v2", sessions: ["aaaa-filed", "cccc-live"])]
    try idx.save(project: proj)
    let saved = try Data(contentsOf: SessionIndex.url(for: proj))
    let mtime = try FileManager.default.attributesOfItem(atPath: SessionIndex.url(for: proj).path)[.modificationDate] as? Date
    Thread.sleep(forTimeInterval: 0.02)
    try idx.save(project: proj)
    let mtime2 = try FileManager.default.attributesOfItem(atPath: SessionIndex.url(for: proj).path)[.modificationDate] as? Date
    check(SessionIndex.load(project: proj) == idx, "index round-trips")
    check(mtime == mtime2 && String(decoding: saved, as: UTF8.self).hasSuffix("}\n"), "byte-equal index isn't rewritten (LDI-39)")
    check(SessionIndex.load(project: lw) == SessionIndex(), "missing index reads as empty")
    let live = Beacon(pid: 1, sessionId: "cccc-live", cwd: proj.appending(path: "docs").path, name: "PRD v2 edits",
                      status: "waiting", waitingFor: "input needed", statusUpdatedAt: Date().timeIntervalSince1970 * 1000 - 240_000,
                      entrypoint: "cli", kind: nil, nameSource: "user")
    let (snap, folders, _) = LiveSnapshot.build(noHistory(lw), beacons: [live])
    let ss = snap.sessions(inProject: "checkout-redesign")
    check(ss.map(\.sessionId) == ["aaaa-filed", "cccc-live"], "filed sessions plus live ones attributed by cwd; archived hidden")
    check(ss.last?.name == "PRD v2 edits" && ss.last?.state == .needsYou && ss.last?.wait == "4m", "beacon gives name, state, wait")
    check(snap.projects.first { $0.name == "checkout-redesign" }?.health == "At risk"
          && snap.projects.first { $0.name == "checkout-redesign" }?.topic == "Payments", "project from PROJECT.md: health, topic")
    check(snap.projects.first { $0.isHome == true }?.name == "home" && folders["home"] != nil, "Home from HOME.md")
    check(snap.groups.first?.sessions == ["New session", "PRD v2 edits"], "groups resolve ids to names; never-used session is New session")
    check(snap.counts.needsYou == 1 && snap.counts.idle == 1, "counts")
    let quiet = Beacon(pid: 1, sessionId: "aaaa-filed", cwd: proj.path, name: nil, status: "idle", waitingFor: nil,
                       statusUpdatedAt: nil, entrypoint: "cli", kind: nil)
    check(LiveSnapshot.build(noHistory(lw), beacons: [live, quiet]).0.counts.idle == 0, "a running, quiet session isn't counted as resumable")
    // `/cd`: a filed session running in another project's folder is listed there and moves (F-32).
    let other = lw.appending(path: "growth/onboarding")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try "---\ngoal: x\n---\n".write(to: other.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)
    let moved = Beacon(pid: 1, sessionId: "aaaa-filed", cwd: other.path, name: nil, status: "idle", waitingFor: nil,
                       statusUpdatedAt: nil, entrypoint: "cli", kind: nil)
    let (snap2, _, moves) = LiveSnapshot.build(noHistory(lw), beacons: [moved])
    check(snap2.sessions.first { $0.sessionId == "aaaa-filed" }?.project == "onboarding"
          && moves.map(\.sessionId) == ["aaaa-filed"] && moves.first?.to.lastPathComponent == "onboarding",
          "a session moved with /cd is listed in its new project, and its entry moves")
    // DL-59, DL-63, DL-64: history in place, folder projects, sticky user moves.
    let scratchFolder = lw.appending(path: "scratch")
    try FileManager.default.createDirectory(at: scratchFolder, withIntermediateDirectories: true)
    try "# notes".write(to: scratchFolder.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
    let fakeT = lw.appending(path: "fake.jsonl")
    try "{}".write(to: fakeT, atomically: true, encoding: .utf8)
    var hctx = noHistory(lw)
    hctx.historyOverride = [(id: "hist-in-project", transcript: fakeT, cwd: proj.path),
                            (id: "hist-orphan", transcript: fakeT, cwd: scratchFolder.path)]
    let (hs, hfolders, _) = LiveSnapshot.build(hctx, beacons: [])
    check(hs.sessions.first { $0.sessionId == "hist-in-project" }?.project == "checkout-redesign", "a past session in a project's folder is listed there (DL-59)")
    let orphanProject = hs.projects.first { $0.name == "scratch" }
    check(orphanProject?.isFolderOnly == true && orphanProject?.hasClaudeMD == true && hfolders["scratch"] != nil
          && hs.sessions.first { $0.sessionId == "hist-orphan" }?.project == "scratch", "a session from a non-project folder makes a folder entry, CLAUDE.md noted (DL-63)")
    var moveIdx = SessionIndex.load(project: proj)
    moveIdx.sessions.append(.init(sessionId: "hist-orphan", provenance: "moved-by-user:scratch"))
    try moveIdx.save(project: proj)
    let (ms, _, mmoves) = LiveSnapshot.build(hctx, beacons: [])
    check(ms.sessions.first { $0.sessionId == "hist-orphan" }?.project == "checkout-redesign" && !mmoves.contains { $0.sessionId == "hist-orphan" }
          && !ms.projects.contains { $0.name == "scratch" }, "a session the user moved stays where it was filed (DL-64)")
    try? FileManager.default.removeItem(at: lw)

    print("hooks")
    let ev = FileManager.default.temporaryDirectory.appending(path: "duo-ev-\(UUID().uuidString)")
    let settings = try HookEvents.settingsFile(for: "s1", in: ev)
    let sj = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any]
    let stopCmd = (((sj?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
    check(stopCmd != nil, "settings file has a Stop hook command")
    let allowed = ((sj?["sandbox"] as? [String: Any])?["network"] as? [String: Any])?["allowUnixSockets"] as? [String]
    check(allowed == [ControlEndpoint.defaultSocket], "settings allow exactly Duo's socket in the sandbox (DL-43)")
    // Run the real hook command the way Claude does: payload on stdin, pretty-printed.
    func fire(_ payload: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", stopCmd!]
        let pin = Pipe(); p.standardInput = pin; let out = Pipe(); p.standardOutput = out
        try? p.run(); pin.fileHandleForWriting.write(Data(payload.utf8)); try? pin.fileHandleForWriting.close(); p.waitUntilExit()
        check(out.fileHandleForReading.readDataToEndOfFile().isEmpty, "hook prints nothing (never answers a prompt)")
    }
    fire("{\n  \"hook_event_name\": \"UserPromptSubmit\", \"prompt\": \"hi\"\n}")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Move saved cards into scope?","options":[{"label":"Yes"},{"label":"No"}]}]}}"#)
    var events = HookEvents.read("s1", in: ev)
    check(events.count == 2 && events[0].name == "UserPromptSubmit", "events append one per line, pretty payloads folded")
    var sum = HookEvents.summarize(events)
    check(sum?.kind == .pending && sum?.question == "Move saved cards into scope?" && sum?.options == ["Yes", "No"], "pending AskUserQuestion carries the verbatim question")
    fire(#"{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion"}"#)
    fire(###"{"hook_event_name":"Stop","last_assistant_message":"## Drafted the PRD section\nDetails…"}"###)
    events = HookEvents.read("s1", in: ev)
    sum = HookEvents.summarize(events)
    check(sum?.kind == .stopped && sum?.reason == .blocked, "answered, then the turn ended")
    func b(_ status: String, _ w: String? = nil) -> Beacon {
        Beacon(pid: 1, sessionId: "s1", cwd: "/", name: nil, status: status, waitingFor: w, statusUpdatedAt: 1000, entrypoint: nil, kind: nil)
    }
    fire(#"{"hook_event_name":"SessionStart","source":"resume"}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.kind == .stopped, "resuming keeps the finished turn")
    let r = Attention.live(beacon: b("idle"), hooks: sum, seenAt: nil)
    check(r.state == .readyForReview && r.summary == "Drafted the PRD section", "finished turn: ready for review, headline as summary")
    check(Attention.live(beacon: b("idle"), hooks: sum, seenAt: sum!.at + 1).state == .idle, "seen after the turn: idle")
    check(HookEvents.headline("You prefer **red**.") == "You prefer red.", "summary drops bold markers")
    check(Attention.live(beacon: b("busy"), hooks: sum, seenAt: nil).state == .working, "busy beats hooks")
    check(Attention.live(beacon: b("waiting", "permission prompt"), hooks: nil, seenAt: nil).question == "Waiting for permission", "waiting without hooks: generic line")
    fire(#"{"hook_event_name":"UserPromptSubmit","prompt":"next"}"#)
    fire(#"{"hook_event_name":"Stop","last_assistant_message":"Done.\n\nShould I also update the FAQ?"}"#)
    let asked = Attention.live(beacon: b("idle"), hooks: HookEvents.summarize(HookEvents.read("s1", in: ev)), seenAt: nil)
    check(asked.state == .needsYou && asked.question == "Should I also update the FAQ?", "turn ending in a question: needs you, last paragraph")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git push"}}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.question == "Allow `git push`?", "permission prompt names the command")
    fire(#"{"hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"/x/refunds-note.md","content":"…"}}"#)
    check(HookEvents.summarize(HookEvents.read("s1", in: ev))?.question == "Allow Write to refunds-note.md?", "file permission names the file")
    fire(#"{"session_id":"s2-cleared","hook_event_name":"UserPromptSubmit","tool_input":{"note":"{\"session_id\": \"decoy\"}"}}"#)
    check(HookEvents.read("s2-cleared", in: ev).count == 1 && HookEvents.read("decoy", in: ev).isEmpty,
          "events follow the payload's session_id (/clear), first key only")
    let store = TerminalStore()
    _ = store.session("old-id", command: .shell, cwd: NSTemporaryDirectory())
    store.rekey("old-id", to: "new-id")
    check(store.existing("old-id") == nil && store.existing("new-id")?.key == "new-id", "terminal re-keys to the new session id")
    store.terminateAll()
    try? FileManager.default.removeItem(at: ev)

    print("titles")
    func rec(_ json: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any] }
    let prompt = rec(#"{"type":"user","message":{"role":"user","content":"<system-reminder>ignore me</system-reminder>  Draft the   refunds FAQ for support"}}"#)
    let meta = rec(#"{"type":"user","isMeta":true,"message":{"content":"Caveat: local commands"}}"#)
    let slash = rec(#"{"type":"user","message":{"content":"<command-name>/review</command-name><command-args></command-args>"}}"#)
    let ai = rec(#"{"type":"ai-title","aiTitle":"Refunds FAQ draft"}"#)
    let custom = rec(#"{"type":"custom-title","customTitle":"FAQ v2"}"#)
    check(SessionTitles.title(head: [meta, prompt], tail: []) == "Draft the refunds FAQ for support", "first prompt, wrapper tags stripped, meta skipped")
    check(SessionTitles.title(head: [slash, prompt], tail: []) == "/review", "slash command beats the prompt")
    check(SessionTitles.title(head: [prompt, ai], tail: []) == "Refunds FAQ draft", "AI title beats the prompt")
    check(SessionTitles.title(head: [prompt, ai], tail: [custom]) == "FAQ v2", "custom title beats all")
    check(SessionTitles.clean(String(repeating: "word ", count: 30))?.hasSuffix("word…") == true, "long prompts shorten on a word")
    let tdir = FileManager.default.temporaryDirectory.appending(path: "duo-t-\(UUID().uuidString).jsonl")
    let big = String(repeating: #"{"type":"assistant","message":{"content":"x"}}"# + "\n", count: 9000)
    try (#"{"type":"user","message":{"content":"Plan the launch"}}"# + "\n" + big + #"{"type":"ai-title","aiTitle":"Launch plan"}"# + "\n").write(to: tdir, atomically: true, encoding: .utf8)
    check(SessionTitles.title(transcript: tdir) == "Launch plan", "bounded head + tail read finds a late AI title")
    try? FileManager.default.removeItem(at: tdir)

    if let bench = ProcessInfo.processInfo.environment["DUO_BENCH"] {
        let root = URL(fileURLWithPath: bench)
        let beacons = Beacon.readAll()
        var times: [Double] = []
        for _ in 0..<5 {
            let t0 = Date()
            let (snap, _, _) = LiveSnapshot.build(.init(root: root, events: DuoPaths.events), beacons: beacons)
            times.append(Date().timeIntervalSince(t0) * 1000)
            if times.count == 1 { print("bench: \(snap.projects.count) projects, \(snap.sessions.count) sessions, \(beacons.count) beacons") }
        }
        let t0 = Date(); _ = Beacon.readAll(); let tb = Date().timeIntervalSince(t0) * 1000
        print("bench: build ms \(times.map { String(format: "%.1f", $0) }), beacons ms \(String(format: "%.1f", tb))")
    }

    print("fork lineage")
    func msg(_ uuid: String, _ parent: String?, _ ts: String, _ type: String = "user") -> [String: Any] {
        var d: [String: Any] = ["uuid": uuid, "timestamp": ts, "type": type]
        if let parent { d["parentUuid"] = parent }
        return d
    }
    // A: u1 → a1 → u2 → a2. B forks A after a1. C forks A after a2. D forks B.
    // Each file starts with a queue record stamped at the session's own start (as Claude writes).
    func start(_ ts: String) -> [String: Any] { ["type": "queue-operation", "timestamp": ts] }
    let msgsA = [msg("u1", nil, "t01"), msg("a1", "u1", "t02", "assistant"), msg("u2", "a1", "t03"), msg("a2", "u2", "t04", "assistant")]
    let A = [start("t00")] + msgsA
    let B = [start("t05")] + Array(msgsA.prefix(2)) + [msg("b1", "a1", "t05"), msg("b2", "b1", "t06", "assistant")]
    let C = [start("t07")] + msgsA + [msg("c1", "a2", "t07")]
    let D = [start("t08")] + Array(B.dropFirst()) + [msg("d1", "b2", "t08")]
    let recs = ["A": A, "B": B, "C": C, "D": D]
    let infos = recs.map { ForkLineage.info(sessionId: $0.key, records: $0.value) }
    check(Set(infos.map(\.root)) == ["u1"], "a thread shares its first user uuid")
    let parents = ForkLineage.parents(infos, records: recs)
    check(parents == ["B": "A", "C": "A", "D": "B"], "parents from fork points, including a fork of a fork")

    if let dir = ProcessInfo.processInfo.environment["DUO_LINEAGE"] {
        let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
        var recs: [String: [[String: Any]]] = [:]
        for f in files where f.pathExtension == "jsonl" {
            recs[String(f.deletingPathExtension().lastPathComponent.prefix(8))] = (try? String(contentsOf: f, encoding: .utf8))?
                .split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? []
        }
        let infos = recs.map { ForkLineage.info(sessionId: $0.key, records: $0.value) }
        print("lineage: roots \(Set(infos.compactMap(\.root)).count), parents \(ForkLineage.parents(infos, records: recs))")
    }

    print("search: pieces")
    check(GitIgnore_ignored("build/out.txt", rules: "build/\n*.log\n!keep.log\n/root-only.md\ndocs/**/draft*.md"), "gitignore: directory pattern")
    check(GitIgnore_ignored("a/b/x.txt", rules: "*.txt") && !GitIgnore_ignored("keep.txt", rules: "*.txt\n!keep.txt"), "gitignore: glob and negation")
    check(GitIgnore_ignored("docs/a/b/draft-1.md", rules: "docs/**/draft*.md") && !GitIgnore_ignored("other/draft.md", rules: "/draft.md"), "gitignore: ** and anchored")
    check(Secrets.isDenied("/p/.env.local") && Secrets.isDenied("/p/id_ed25519") && Secrets.isDenied("/p/cert.pem") && !Secrets.isDenied("/p/notes.md"), "secret files denied")
    let redacted = Secrets.redact("key AKIAABCDEFGHIJKLMNOP and sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123 and ghp_abcdefghijklmnopqrstuvwxyz0123456789 password: hunter2hunter2")
    check(!redacted.contains("AKIA") && !redacted.contains("sk-ant") && !redacted.contains("ghp_") && !redacted.contains("hunter2"), "secrets redacted before storing")
    check(SearchIndex.literal(in: "\"exponential backoff\"") == "exponential backoff" && SearchIndex.literal(in: "retry_request") == "retry_request"
          && SearchIndex.literal(in: "camelCaseName") == "camelCaseName" && SearchIndex.literal(in: "why are tides") == nil, "exact-match detection")
    let fts = SearchIndex.ftsQuery("retry OR backoff* NEAR(x) -y", exact: false) ?? ""
    check(fts.components(separatedBy: " OR ").allSatisfy { $0.hasPrefix("\"") && $0.hasSuffix("\"") }, "every FTS term is quoted, so query syntax can't break it")

    // Golden set (SRCH § 12, the POC's), through Duo's own chunker and index, when the model is here.
    let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Spikes/S13CoreML/out/bge-small-fp16.mlpackage")
    let vocabURL = pkg.deletingLastPathComponent().deletingLastPathComponent().appending(path: "hf/bge-small/vocab.txt")
    let poc = FileManager.default.homeDirectoryForCurrentUser.appending(path: "repos/smol-sim-search/tests/fixtures")
    if FileManager.default.fileExists(atPath: pkg.path), FileManager.default.fileExists(atPath: poc.path) {
        print("search: golden set (POC fixtures)")
        let scratch = FileManager.default.temporaryDirectory.appending(path: "duo-search-\(UUID().uuidString)")
        setenv("DUO_SEARCH_ROOT", scratch.path, 1)
        SearchSetup.registerExtractors()
        let proj = scratch.appending(path: "work/fx")
        try FileManager.default.createDirectory(at: proj.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: poc, to: proj)
        let t0 = Date()
        let compiled: URL = try blocking { try await Embedder.install(package: pkg, vocab: vocabURL) }
        let indexer = try Embedder(modelAt: compiled, vocab: SearchPaths.vocab, use: .indexing)
        let index = try SearchIndex(readOnly: false)
        let stats: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        print("  indexed \(stats.files) files, \(stats.chunks) chunks in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        let reader = try SearchIndex(readOnly: true)
        let queryEmbedder = try Embedder(use: .query)
        let golden = [("why are there two high tides every day", "docs/tides.md"),
                      ("feeding a sourdough starter with flour and water", "docs/sourdough.md"),
                      ("horizontal pod autoscaler adds replicas", "docs/kubernetes.md"),
                      ("retry a request with exponential backoff", "code/http_retry.py"),
                      ("customer credit card charged twice", "data/tickets.jsonl"),
                      ("magma erupts from a volcano", "papers/volcanoes.pdf"),
                      ("growing tomato seedlings in sunlight", "notes/garden.txt")]
        var top1 = 0
        for (q, want) in golden {
            let hits = try reader.search(SearchQuery(text: q), embedder: queryEmbedder)
            if hits.first?.path.hasSuffix(want) == true { top1 += 1 } else { print("    \(q) → \(hits.first?.title ?? "-")") }
        }
        check(top1 == golden.count, "golden top-1 \(top1)/\(golden.count) through Duo's index")
        // A small, unrelated file in the current project mustn't outrank the strong match (FR-7.4.3).
        try "---\ngoal: \"Lift day-7 activation to 40%\"\n---\n# onboarding\n".write(to: scratch.appending(path: "work/onb/PROJECT.md").creatingParent(), atomically: true, encoding: .utf8)
        _ = try blocking { try await index.indexProject("onb", root: scratch.appending(path: "work/onb"), embedder: indexer) }
        var boosted = SearchQuery(text: "why are there two high tides every day"); boosted.currentProject = "onb"
        check(try reader.search(boosted, embedder: queryEmbedder).first?.path.hasSuffix("docs/tides.md") == true,
              "the current-project boost doesn't crowd out a strong match elsewhere")
        let again: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        check(again.changed == 0 && again.embedded == 0, "re-index with nothing changed embeds nothing")
        try FileManager.default.moveItem(at: proj.appending(path: "docs/tides.md"), to: proj.appending(path: "notes/tides-moved.md"))
        let moved: IndexStats = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        check(moved.changed == 1 && moved.removed == 1 && moved.embedded == 0, "a moved file reuses its vectors (FR-7.3.5)")
        var q = SearchQuery(text: "exponential backoff"); q.exactOnly = true
        let ex = try reader.search(q, embedder: nil)
        check(!ex.isEmpty && ex.allSatisfy { $0.matched.contains("exact") }, "exact-only mode returns literal matches only")
        var sim = SearchQuery(text: ""); sim.similarTo = proj.appending(path: "notes/moon-notes.md").resolvingSymlinksInPath().path
        let similar = try reader.search(sim, embedder: nil)
        check(similar.first?.path.hasSuffix("tides-moved.md") == true && !similar.contains { $0.path.hasSuffix("moon-notes.md") },
              "find similar: the copied article's source comes first, the item itself is left out")
        // Same passage in two files: shown once, with the other place listed (FR-7.4.5).
        try FileManager.default.copyItem(at: proj.appending(path: "docs/sourdough.md"), to: proj.appending(path: "notes/sourdough-copy.md"))
        _ = try blocking { try await index.indexProject("fx", root: proj, embedder: indexer) }
        let dup = try reader.search(SearchQuery(text: "feeding a sourdough starter with flour and water"), embedder: queryEmbedder)
        check(dup.filter { $0.path.contains("sourdough") }.count == 1 && dup.first?.alsoIn.count == 1, "identical content shown once, other place listed")
        let cov = try reader.coverage()
        check(cov.first?.complete == true && (cov.first?.known ?? 0) >= stats.files, "coverage reported")
        // Sessions (SRCH L7, FR-7.1.3-5, L17): conversation text only, by turn, attributed by cwd.
        let claudeProjects = scratch.appending(path: "claude-projects")
        let bucket = claudeProjects.appending(path: "-work-fx")
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        let lines = [
            #"{"type":"user","cwd":"\#(proj.path)","message":{"role":"user","content":"Why do spring tides happen at new moon?"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"SECRET THOUGHT"},{"type":"text","text":"Because the Sun and Moon line up and their pulls add."}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"grep TOOLCALL"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"TOOLOUTPUT"}]}}"#,
            #"{"type":"user","message":{"content":"Now draft the quarterly pricing readout outline."}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Outline: goals, results, decision."}]}}"#,
            #"{"type":"ai-title","aiTitle":"Tides and pricing"}"#, "{not json",
        ]
        try lines.joined(separator: "\n").write(to: bucket.appending(path: "11111111-aaaa.jsonl"), atomically: true, encoding: .utf8)
        try #"{"type":"user","cwd":"/elsewhere","message":{"content":"Unrelated chat about lunch"}}"#.write(to: bucket.appending(path: "22222222-bbbb.jsonl"), atomically: true, encoding: .utf8)
        let ss: IndexStats = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer) }
        check(ss.changed == 2, "two transcripts indexed")
        var sq = SearchQuery(text: "why spring tides at new moon"); sq.kinds = ["session"]
        let sh = try reader.search(sq, embedder: queryEmbedder)
        check(sh.first?.title == "Tides and pricing" && sh.first?.project == "fx" && sh.first?.locator == "turn 1", "session found by meaning, titled, attributed, at its turn")
        var pq = SearchQuery(text: "quarterly pricing readout outline"); pq.kinds = ["session"]
        check(try reader.search(pq, embedder: queryEmbedder).first?.locator == "turn 2", "second turn located")
        for leak in ["SECRET THOUGHT", "TOOLCALL", "TOOLOUTPUT"] {
            var lq = SearchQuery(text: leak); lq.exactOnly = true
            check(try reader.search(lq, embedder: nil).isEmpty, "\(leak.lowercased()) not indexed (conversation text only)")
        }
        var uq = SearchQuery(text: "lunch"); uq.kinds = ["session"]
        check(try reader.search(uq, embedder: queryEmbedder).first?.project == SearchIndex.unfiled, "a session outside every project is Unfiled")
        try FileManager.default.removeItem(at: bucket.appending(path: "22222222-bbbb.jsonl"))
        let swept: IndexStats = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer) }
        // DL-49: a purged session kept by Duo's archive stays findable, marked archived.
        let archivedCopy = scratch.appending(path: "archive/33333333-cccc.jsonl")
        try FileManager.default.createDirectory(at: archivedCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"type":"user","cwd":"\#(proj.path)","message":{"content":"Draft the lighthouse keeper rota for winter"}}"#.write(to: archivedCopy, atomically: true, encoding: .utf8)
        _ = try blocking { try await index.indexSessions(projects: ["fx": proj], claudeProjects: claudeProjects, embedder: indexer,
                                                         archived: [(id: "33333333-cccc", copy: archivedCopy, cwd: proj.path)]) }
        var aq = SearchQuery(text: "lighthouse keeper rota"); aq.kinds = ["session"]
        let ah = try reader.search(aq, embedder: queryEmbedder).first
        check(ah?.archived == true && ah?.project == "fx", "a purged session is found from Duo's archive, marked archived (DL-49)")
        let afterSweep = try reader.search(uq, embedder: nil)
        check(swept.removed == 1 && afterSweep.allSatisfy { $0.project != SearchIndex.unfiled }, "a deleted transcript leaves the index (L17)")
        unsetenv("DUO_SEARCH_ROOT")
        try? FileManager.default.removeItem(at: scratch)
    }

    print("legacy duo (DL-39)")
    let lg = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: lg.appending(path: "skills/duo"), withIntermediateDirectories: true)
    let lgSettings = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"a","_duo":"managed-v3"}]},{"hooks":[{"type":"command","command":"mine"}]}]},"model":"opus"}"#
    let lgMD = "# Mine\n\nKeep this.\n\n<!-- duo:managed-v3 -->\nDuo\n<!-- duo:end -->\n\nAnd this.\n"
    try lgSettings.write(to: lg.appending(path: "settings.json"), atomically: true, encoding: .utf8)
    try lgMD.write(to: lg.appending(path: "CLAUDE.md"), atomically: true, encoding: .utf8)
    check(LegacyDuo.detect(in: lg).count == 3, "detects legacy hooks, block and skill")
    let lgBackup = try LegacyDuo.disable(in: lg, backupRoot: lg.appending(path: "backups"))
    let mdAfter = try String(contentsOf: lg.appending(path: "CLAUDE.md"), encoding: .utf8)
    let setAfter = try String(contentsOf: lg.appending(path: "settings.json"), encoding: .utf8)
    check(LegacyDuo.detect(in: lg).isEmpty && mdAfter == "# Mine\n\nKeep this.\n\nAnd this.\n" && setAfter.contains("mine") && setAfter.contains("opus"),
          "disable removes only legacy's parts")
    try LegacyDuo.restore(from: lgBackup)
    check(try String(contentsOf: lg.appending(path: "CLAUDE.md"), encoding: .utf8) == lgMD
          && (try String(contentsOf: lg.appending(path: "settings.json"), encoding: .utf8)) == lgSettings
          && FileManager.default.fileExists(atPath: lg.appending(path: "skills/duo").path), "restore puts everything back exactly")
    try? FileManager.default.removeItem(at: lg)

    print("retention (DL-44, DL-47)")
    let ar = FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID().uuidString)")
    setenv("DUO_ARCHIVE_ROOT", ar.appending(path: "archive").path, 1)
    let bucketDir = ar.appending(path: "claude/projects/-work-p")
    try FileManager.default.createDirectory(at: bucketDir.appending(path: "s-old/tool-results"), withIntermediateDirectories: true)
    let oldT = bucketDir.appending(path: "s-old.jsonl"), freshT = bucketDir.appending(path: "s-new.jsonl")
    try #"{"type":"user","cwd":"/work/p","message":{"content":"Plan the readout"}}"#.write(to: oldT, atomically: true, encoding: .utf8)
    try #"{"type":"user","cwd":"/work/p","message":{"content":"Fresh one"}}"#.write(to: freshT, atomically: true, encoding: .utf8)
    try "big output".write(to: bucketDir.appending(path: "s-old/tool-results/r1.txt"), atomically: true, encoding: .utf8)
    let keepNow = Date()
    for u in [oldT, bucketDir.appending(path: "s-old/tool-results/r1.txt"), bucketDir.appending(path: "s-old/tool-results"), bucketDir.appending(path: "s-old")] {
        try FileManager.default.setAttributes([.modificationDate: keepNow.addingTimeInterval(-25 * 86_400)], ofItemAtPath: u.path)
    }
    check(try SessionArchive.sync([("s-old", oldT), ("s-new", freshT)]) == 2 && FileManager.default.fileExists(atPath: SessionArchive.copyURL("s-old").path), "listed transcripts are copied to Duo's archive")
    check(try SessionArchive.sync([("s-old", oldT), ("s-new", freshT)]) == 0, "unchanged transcripts aren't copied again")
    let refreshed = SessionArchive.keepAlive([oldT, freshT], periodDays: 30, now: keepNow)
    let oldMod = try FileManager.default.attributesOfItem(atPath: oldT.path)[.modificationDate] as! Date
    let freshMod = try FileManager.default.attributesOfItem(atPath: freshT.path)[.modificationDate] as! Date
    check(refreshed == 4 && abs(oldMod.timeIntervalSince(keepNow.addingTimeInterval(-15 * 86_400))) < 2 && keepNow.timeIntervalSince(freshMod) < 60,
          "keep-alive moves a quiet session to half the period ago (with its sidecars), leaves fresh ones alone")
    check(SessionArchive.carryOnPrompt("s-old")?.contains(SessionArchive.copyURL("s-old").path) == true, "carry-on prompt points at the archived transcript")
    check(FileManager.default.fileExists(atPath: SessionArchive.sidecarURL("s-old").appending(path: "tool-results/r1.txt").path),
          "the sidecar folder is archived too (DL-48)")
    unsetenv("DUO_ARCHIVE_ROOT")
    try? FileManager.default.removeItem(at: ar)

    print("threads and groups (DL-24, Phase G)")
    do {
        check(LiveSnapshot.threads(["PRD v2 edits", "quick q about tax rules", "Interview synth"], in: f.sessions)
              == [["Interview synth", "PRD v2 edits"], ["quick q about tax rules"]], "a group's threads: fork families, parent first")
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-threads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ lines: [String]) -> URL {
            let u = dir.appending(path: name + ".jsonl"); try? (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8); return u
        }
        func rec(_ type: String, _ uuid: String, _ parent: String?, _ t: String) -> String {
            #"{"type":"\#(type)","uuid":"\#(uuid)","parentUuid":\#(parent.map { "\"\($0)\"" } ?? "null"),"timestamp":"\#(t)"}"#
        }
        let parent = write("p", [#"{"type":"mode","timestamp":"2026-10-04T10:00:00Z"}"#, rec("user", "u1", nil, "2026-10-04T10:00:01Z"),
                                 rec("assistant", "u2", "u1", "2026-10-04T10:00:02Z"), rec("user", "u3", "u2", "2026-10-04T10:00:03Z")])
        let fork = write("f", [#"{"type":"mode","timestamp":"2026-10-04T11:00:00Z"}"#, rec("user", "u1", nil, "2026-10-04T10:00:01Z"),
                               rec("assistant", "u2", "u1", "2026-10-04T10:00:02Z"), rec("user", "u9", "u2", "2026-10-04T11:00:05Z")])
        let other = write("o", [rec("user", "x1", nil, "2026-10-04T09:00:00Z")])
        let cache = ThreadCache()
        let pairs: [(id: String, transcript: URL)] = [("p", parent), ("f", fork), ("o", other)]
        check(cache.parents(pairs) == ["f": "p"], "a fork's parent from shared uuids and its fork point (S11)")
        let h = try FileHandle(forWritingTo: fork); try h.seekToEnd(); try h.write(contentsOf: Data((rec("assistant", "u10", "u9", "2026-10-04T11:00:06Z") + "\n").utf8)); try h.close()
        check(cache.parents(pairs) == ["f": "p"], "a growing transcript is read on from where it stopped")
        try? FileManager.default.removeItem(at: dir)
    }

    print("inventory and evidence (CONS FR-7.1, 7.8, 7.10; DL-41)")
    do {
        let h = FileManager.default.homeDirectoryForCurrentUser.path
        check(Inventory.candidateHome(["\(h)/w/a/x.md", "\(h)/w/a/b/y.md"], cwd: h) == "\(h)/w/a", "candidate home: the deepest folder holding every edit")
        check(Inventory.candidateHome(["\(h)/w/a/x.md", "\(h)/v/y.md"], cwd: h) == nil, "disjoint edits under the cwd: no home")
        check(Inventory.candidateHome(["/tmp/x", "\(h)/.claude/projects/p", "\(h)/w/a/x.md"], cwd: h) == "\(h)/w/a", "system, temp and ~/.claude paths don't count")
        check(Inventory.candidateHome([], cwd: h) == nil, "nothing edited: no home")
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-inv-\(UUID().uuidString)")
        let claude = dir.appending(path: "claude")
        func bucket(_ name: String, _ id: String, _ lines: [String]) throws -> URL {
            let d = claude.appending(path: "projects/\(name)"); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let u = d.appending(path: "\(id).jsonl"); try (lines.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8); return u
        }
        let t = try bucket("-x-junk", "s1", [
            #"{"type":"user","cwd":"/x/junk","uuid":"a","timestamp":"2026-09-01T10:00:00.000Z","message":{"content":"go"}}"#,
            #"{"type":"assistant","timestamp":"2026-09-01T10:01:00.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/w/a/one.md"}},{"type":"tool_use","name":"Read","input":{"file_path":"/x/w/read-only.md"}}]}}"#,
            #"{"type":"file-history-snapshot","snapshot":{"trackedFileBackups":{"/x/w/a/b/two.md":{}}}}"#,
            #"{"type":"user","timestamp":"2026-09-01T10:02:00.000Z","toolUseResult":{"type":"create","filePath":"/x/w/a/three.md"}}"#])
        let e = Inventory.evidence(t, cwd: "/x/junk")
        check(Set(e.edited) == ["/x/w/a/one.md", "/x/w/a/b/two.md", "/x/w/a/three.md"], "edits from the editing tools, file-history and results; reads don't count")
        check(e.candidateHome == "/x/w/a", "that session's candidate home")
        _ = try bucket("-x-junk", "s2", [#"{"type":"user","cwd":"/x/other","uuid":"b","timestamp":"2026-09-05T10:00:00.000Z","message":{"content":"go"}}"#])
        _ = try bucket("-x-copy", "s1", [#"{"type":"user","cwd":"/x/junk","uuid":"a","timestamp":"2026-09-01T10:00:00.000Z","message":{"content":"go"}}"#])
        let r = Inventory.build(claudeDir: claude, now: ISO8601DateFormatter().date(from: "2026-10-04T00:00:00Z")!, periodDays: 30)
        check(r.buckets.first { $0.folder == "-x-junk" }?.collision == true, "a folder holding sessions from two cwds is a collision (FR-7.8.2)")
        check(r.duplicates["s1"]?.count == 2, "the same id in two folders is a duplicate (FR-7.8.1)")
        check(r.buckets.first { $0.folder == "-x-junk" }?.cwdMissing == true, "folders whose cwds are all gone are flagged")
        func ev(_ id: String, _ from: String, _ to: String) -> Inventory.Evidence {
            let f = ISO8601DateFormatter()
            return .init(sessionId: id, title: nil, first: f.date(from: from), last: f.date(from: to), edited: [], candidateHome: nil, partial: false)
        }
        let c = Inventory.clusters([ev("a", "2026-09-01T00:00:00Z", "2026-09-01T02:00:00Z"), ev("b", "2026-09-03T02:00:00Z", "2026-09-03T03:00:00Z"),
                                    ev("c", "2026-09-05T03:00:01Z", "2026-09-05T04:00:00Z")])
        check(c.map { $0.map(\.sessionId) } == [["a", "b"], ["c"]], "date clusters split at a 48-hour gap (FR-7.10.4)")
        try? FileManager.default.removeItem(at: dir)
    }

    print("migrator (CONS §6.3, §7.4, §7.5; DL-41) on a throwaway Claude config")
    do {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "duo-mig-\(UUID().uuidString)").resolvingSymlinksInPath()
        let claude = root.appending(path: "claude"), work = root.appending(path: "work")
        let a = work.appending(path: "a").path, b = work.appending(path: "b").path
        try fm.createDirectory(atPath: a + "/sub", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: b, withIntermediateDirectories: true)
        func session(_ id: String, cwd: String) throws -> URL {
            let d = claude.appending(path: "projects/" + ClaudeStorage.encode(cwd)); try fm.createDirectory(at: d, withIntermediateDirectories: true)
            let u = d.appending(path: "\(id).jsonl")
            try (#"{"type":"user","cwd":"\#(cwd)","uuid":"u-\#(id)","sessionId":"\#(id)","message":{"content":"hi"}}"# + "\n").write(to: u, atomically: true, encoding: .utf8)
            try fm.createDirectory(at: d.appending(path: id), withIntermediateDirectories: true)
            try "tool output".write(to: d.appending(path: "\(id)/tool.txt"), atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000)], ofItemAtPath: u.path)
            return u
        }
        let s1 = try session("s1", cwd: a), original = try Data(contentsOf: s1)
        _ = try session("s2", cwd: a + "/sub")
        let m = Migrator(claudeDir: claude, journalDir: root.appending(path: "migrations"))
        let plan = try m.planRelocate("s1", to: b)
        let done = try m.apply(plan)
        let moved = claude.appending(path: "projects/\(ClaudeStorage.encode(b))/s1.jsonl")
        let text = (try? String(contentsOf: moved, encoding: .utf8)) ?? ""
        check(done.state == .committed && !fm.fileExists(atPath: s1.path) && fm.fileExists(atPath: moved.deletingLastPathComponent().appending(path: "s1/tool.txt").path),
              "relocate moves the transcript and its sidecar folder, as /cd does")
        check(text.hasPrefix(String(decoding: original, as: UTF8.self)) && text.contains(#""relocatedCwd":"\#(b)""#) && text.hasSuffix("}\n"),
              "history untouched; one relocated record appended, last (R1, FR-7.4.3)")
        check((try? fm.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date)?.timeIntervalSince1970 == 1_790_000_000, "the mtime is kept, so Claude's cleanup clock is unchanged")
        try m.undo(done)
        check((try? Data(contentsOf: s1)) == original && !fm.fileExists(atPath: moved.path), "undo puts it back byte for byte")
        check((try? m.planRelocate("s1", to: b, live: ["s1"])) == nil, "a running session is refused")
        _ = try session("s1", cwd: b)   // the same id already in the target
        check((try? m.planRelocate("s1", to: b)) == nil, "a same-id transcript in the target stops the plan (FR-7.4.4)")
        try fm.removeItem(at: claude.appending(path: "projects/\(ClaudeStorage.encode(b))"))
        let dest = work.appending(path: "moved").path
        let move = try m.apply(try m.planFolderMove(a, to: dest))
        let sub2 = claude.appending(path: "projects/\(ClaudeStorage.encode(dest + "/sub"))/s2.jsonl")
        check(move.state == .committed && fm.fileExists(atPath: dest + "/sub") && fm.fileExists(atPath: sub2.path)
              && ((try? String(contentsOf: sub2, encoding: .utf8)) ?? "").contains(#""relocatedCwd":"\#(dest)/sub""#),
              "a folder move renames the folder and relocates every session under it to the mapped path (FR-7.5.4)")
        try m.undo(move)
        check(fm.fileExists(atPath: a + "/sub") && !fm.fileExists(atPath: dest) && (try? Data(contentsOf: s1)) == original, "and undo puts the folder and every transcript back")
        var stuck = try m.planRelocate("s1", to: b); stuck.state = .applying; try m.save(stuck)
        check((try? m.apply(try m.planRelocate("s2", to: b))) == nil, "an interrupted migration blocks new ones until it's completed or undone (FR-7.8.4)")
        try m.undo(stuck)
        try fm.createDirectory(at: claude.appending(path: "projects/-wrong-name"), withIntermediateDirectories: true)
        try fm.copyItem(at: s1, to: claude.appending(path: "projects/-wrong-name/x.jsonl"))
        check(m.calibrationProblem() != nil && (try? m.apply(try m.planRelocate("s2", to: b))) == nil, "a folder name Duo can't reproduce stops every physical operation (§6.3 5)")
        try? fm.removeItem(at: root)
    }

    print("surfaces slice 1 (DB-1 to DB-4)")
    do {
        // Saturday 3 Oct 2026, 12:00: this week began Sunday 27 Sep (or Monday 28, by locale).
        let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
        func r(_ n: String, _ days: Int) -> IdleRow { IdleRow(id: n, name: n, project: "p", age: "\(days)d", seconds: days * 86_400) }
        let b = AppModel.idleBuckets([r("a", 1), r("b", 9), r("c", 40)], now: now)
        check(b.map(\.label) == ["This week", "Last week", "Earlier"] && b.map { $0.rows.count } == [1, 1, 1], "idle list: this week, last week, then a short tail as Earlier")
        let many = (0..<40).map { r("s\($0)", 15 + $0 * 3) }
        check(AppModel.idleBuckets(many, now: now).dropFirst(0).contains { $0.label == "August" }, "a long tail is grouped by month")
        check(ForegroundCommand.arguments(getpid()).first?.hasSuffix("DuoChecks") == true, "a process's argv, for a shell tab's title (DB-4)")
        check(DuoTerminalPalette.ansi.count == 16 && DuoTerminalPalette.ansiIncreaseContrast.count == 16, "the terminal palette has 16 colours and an Increase Contrast set (DB-2)")
    }

    print("search modal (DL-76, DL-79, DL-80)")
    do {
        func hit(_ path: String, _ kind: String, _ start: Int, archived: Bool = false) -> SearchHit {
            let j = #"{"project":"checkout","kind":"\#(kind)","path":"\#(path)","title":"t","locator":"L\#(start)-\#(start + 2)","startLine":\#(start),"endLine":\#(start + 2),"score":1,"matched":["words"],"snippet":"saved cards","alsoIn":[],"archived":\#(archived)}"#
            return try! JSONDecoder().decode(SearchHit.self, from: Data(j.utf8))
        }
        let rows = AppModel.rows([hit("/x/a.md", "file", 40), hit("/x/b.md", "file", 1), hit("/x/a.md", "file", 71), hit("/x/c.jsonl", "session", 3, archived: true)],
                                 words: "saved cards", includeArchived: false, time: .any)
        check(rows.map(\.path) == ["/x/a.md", "/x/b.md"], "one row per item; archived hidden unless asked")
        check(rows.first?.passages.map(\.location) == ["L40–42", "L71–73"], "later hits become the item's passages, with en dashes")
        check(AppModel.rows([hit("/x/c.jsonl", "session", 3, archived: true)], words: "", includeArchived: true, time: .any).first?.archived == true, "Include archived shows them, labelled")
        check(AppModel.queryWords("where did we land on saved cards") == ["where", "did", "land", "saved", "cards"], "matched words skip short ones")
        check(AppModel.queryWords("\"saved cards\"") == ["saved cards"], "a quoted phrase is one matched word")

        let m = AppModel(fixture: f)
        let names = m.nameMatches("prd")
        check(names.first?.kind == .group && names.first?.title == "PRD v2", "Go to: groups before sessions, by name (DL-80)")
        check(names.allSatisfy(\.goTo) && names.contains { $0.title == "PRD v2 edits" }, "Go to: sessions by name")
        check(m.nameMatches("checkout").first?.kind == .project, "Go to: projects first")

        let s = m.search
        s.items = rows + [SearchItem(id: "s", kind: .session, project: "checkout", title: "PRD v2 edits")]
        s.phase = .results; s.sendTargetName = "Morning triage"
        s.move(1, extend: true)
        check(s.multi == [0, 1] && s.returnLabel == "Send 2 to Claude in Morning triage", "⇧↓ selects several; Return sends them (DL-79 c)")
        var archived = SearchItem(id: "a", kind: .session, project: "refunds", title: "Old"); archived.archived = true
        check(s.actions(for: archived).contains { $0.id == .carryOn }, "archived sessions offer Carry on in a new session (DL-47)")
        check(s.actions(for: rows[0]).first { $0.id == .sendToClaude }?.chord == "⌘D", "Send to Claude is ⌘D (DL-79 e)")
        s.isOpen = true; s.menuOpen = true
        m.searchKey(.escape)
        check(s.isOpen && !s.menuOpen, "Esc closes the menu first (DL-79 h)")
        s.similarTo = rows[0]; s.similarReturnsTo = "saved cards"
        m.searchKey(.escape)
        check(s.isOpen && s.similarTo == nil && s.query == "saved cards", "then leaves find similar for the previous search")
        m.searchKey(.escape)
        check(!s.isOpen, "then closes")
    }

    print("launch options")
    let o = LaunchOptions(arguments: ["Duo", "--state", "flow-zoom-3", "--capture", "/tmp/x.png", "--left", "collapsed"])
    check(o.state == .flowZoom3 && o.capturePath == "/tmp/x.png" && o.collapseLeft && o.capturing, "flags parse")

    print("tokens")
    check(DuoTextStyle.body.spec.size == 13 && DuoTextStyle.body.spec.lineHeight == 20, "body 13/20")
    check(DuoTextStyle.sectionLabel.spec.uppercase && DuoTextStyle.sectionLabel.spec.tracking == 0.66, "section label caps +0.66")
    check(DuoMetric.paneOverviewHome == 340 && DuoMetric.paneProjectRight == 460, "pane widths")

    print("cli parity (DL-71, DL-72)")
    check(Set(DuoAction.all.map(\.id)) == Set(ActionID.allCases) && DuoAction.all.count == ActionID.allCases.count, "every action is in the registry once")
    let gaps = parityGaps()
    if !gaps.isEmpty { print("    UI with no verb: " + gaps.joined(separator: "; ")) }
    check(gaps.isEmpty, "every button, menu item, click and drag in the app names a duo2 action (or is listed in Parity.uiOnly)")
    let primerVerbs = DuoAction.primer().matches(of: /`duo2 ([a-z-]+(?: [a-z-]+)?)/).map { String($0.1) }
    check(!primerVerbs.isEmpty && primerVerbs.allSatisfy { DuoAction.resolve($0.split(separator: " ").map(String.init)) != nil }, "the primer names only verbs that exist")
    check(DuoAction.resolve(["file", "rename", "a.md", "b.md"]).map { $0.0.id == .fileRename && $0.rest == ["a.md", "b.md"] } == true, "two-word verbs resolve")
    check(DuoAction.resolve(["doc-status", "x.md"])?.0.id == .docStatus && DuoAction.resolve(["needs-you"])?.0.id == .needsYou, "old spellings resolve")
    let inv = Invocation(["a.md", "--to", "abc", "--new", "--json", "b"])
    check(inv.positional == ["a.md", "b"] && inv.flags["to"] == "abc" && inv.has("new") && inv.json, "flags and positionals parse")
    let reference = try? String(contentsOf: repoRoot().appending(path: "docs/cli/duo2.md"), encoding: .utf8)
    check(reference == DuoAction.markdown(), "docs/cli/duo2.md is current (regenerate: build/Duo.app/Contents/Helpers/duo2 help --markdown > docs/cli/duo2.md)")

    print("install loop (DL-74, DL-75)")
    let iroot = FileManager.default.temporaryDirectory.appending(path: "duo-install-\(UUID().uuidString)")
    Installer.testRoot = iroot
    defer { Installer.testRoot = nil; try? FileManager.default.removeItem(at: iroot) }
    let cli = iroot.appending(path: "Duo.app/Contents/Helpers/duo2").creatingParent()
    FileManager.default.createFile(atPath: cli.path, contents: Data())
    try? FileManager.default.createDirectory(at: Installer.claudeDir, withIntermediateDirectories: true)
    let mine = "# My rules\n\nBe brief.\n\n<!-- duo:managed-v0.13.0 -->\nlegacy\n<!-- duo:end -->\n"
    try? mine.write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    check(Installer.needsConsent(cli: cli.path), "asks before installing anything")
    Installer.recordConsent(false, cli: cli.path)
    Installer.install(cli: cli.path)
    check((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) == mine && !Installer.needsConsent(cli: cli.path), "declined: nothing written, not asked again")
    Installer.recordConsent(true, cli: cli.path)
    Installer.install(cli: cli.path)
    let md1 = (try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? ""
    check(md1.hasPrefix(mine) && md1.contains(Installer.block()) && LegacyDuo.detect(in: Installer.claudeDir).count == 1, "block added after the user's text; legacy's block untouched and still detected as legacy's alone")
    check((try? String(contentsOf: Installer.skillFile, encoding: .utf8)) == Installer.skill(), "skill written")
    check((try? FileManager.default.destinationOfSymbolicLink(atPath: Installer.link.path)) == cli.path, "duo2 linked onto PATH")
    check(Installer.install(cli: cli.path).lines.isEmpty, "a second launch changes nothing")
    let edited = md1.replacingOccurrences(of: "## Duo", with: "## Duo (mine)")
    try? edited.write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    Installer.install(cli: cli.path)
    check((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) == edited, "an edited block is left alone")
    try? md1.replacingOccurrences(of: Installer.block() + "\n", with: "").write(to: Installer.claudeMD, atomically: true, encoding: .utf8)
    Installer.install(cli: cli.path)
    Installer.install(cli: cli.path)
    check(!((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? "").contains("duo2:begin"), "a removed block is never added back")
    Installer.uninstall()
    check(!FileManager.default.fileExists(atPath: Installer.skillFile.path) && (try? FileManager.default.destinationOfSymbolicLink(atPath: Installer.link.path)) == nil
          && ((try? String(contentsOf: Installer.claudeMD, encoding: .utf8)) ?? "").hasPrefix("# My rules"), "uninstall removes exactly what Duo wrote")
    let before = "# Mine\n\n" + Installer.block() + "\n"
    let restored = iroot.appending(path: "restore/CLAUDE.md").creatingParent()
    try? "# Mine\n".write(to: restored, atomically: true, encoding: .utf8)
    Installer.reapplyBlock(ifPresentIn: before, to: restored)
    check(((try? String(contentsOf: restored, encoding: .utf8)) ?? "").contains(Installer.block()), "legacy restore keeps Duo v2's block")
    check(Installer.block().split(separator: " ").count < 110, "the always-on block stays short")

    print("collisions (DL-77, DL-78)")
    let hroot = FileManager.default.temporaryDirectory.appending(path: "duo-history-\(UUID().uuidString)")
    FileHistory.root = hroot
    let doc = URL(fileURLWithPath: "/tmp/some/doc.md")
    FileHistory.snapshot(doc, Data("one".utf8), source: "open")
    FileHistory.snapshot(doc, Data("one".utf8), source: "open")
    FileHistory.snapshot(doc, Data("two".utf8), source: "conflict-theirs")
    let kept = FileHistory.index(doc)
    check(kept.map(\.source) == ["open", "conflict-theirs"] && (try? String(contentsOf: FileHistory.blob(doc, hash: kept[1].hash), encoding: .utf8)) == "two",
          "history keeps each version once, readable")
    try? FileManager.default.removeItem(at: hroot)
    let hookDir = FileManager.default.temporaryDirectory.appending(path: "duo-hooks-\(UUID().uuidString)")
    let withHook = (try? HookEvents.settingsFile(for: "s9", in: hookDir, cli: "/Apps/Duo.app/Contents/Helpers/duo2")).flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let pre = ((withHook?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first
    check(pre?["matcher"] as? String == "Edit|MultiEdit|Write" && ((pre?["hooks"] as? [[String: Any]])?.first?["command"] as? String)?.hasSuffix("duo2' hook pre-edit") == true,
          "Duo's sessions route Edit, MultiEdit and Write through the edit hook")
    let noHook = (try? HookEvents.settingsFile(for: "s10", in: hookDir)).flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    check((noHook?["hooks"] as? [String: Any])?["PreToolUse"] == nil, "no CLI, no edit hook (the primer and the merge still hold)")
    try? FileManager.default.removeItem(at: hookDir)
    check(DuoAction.primer().contains("duo2 doc edit --stdin") && DuoAction.primer().contains("not with Edit, Write or shell redirection"),
          "the primer tells Claude how to edit open documents without the hook")

    print("privacy prompts (F-53)")
    let home = FileManager.default.homeDirectoryForCurrentUser
    check(FileSource.files(in: home).isEmpty, "the home folder is never walked for files")
    check(ProtectedFolders.skip(home.appending(path: "Music"), root: home) == true
          && ProtectedFolders.skip(home.appending(path: "Pictures"), root: home) == true
          && ProtectedFolders.skip(home.appending(path: "Documents"), root: home.appending(path: "Documents")) == false
          && ProtectedFolders.skip(home.appending(path: "repos"), root: home) == false,
          "walks never enter Music, Photos, Documents… unless the project lives inside them")

    print("send to claude (DL-67, DL-68)")
    let hostile = SendFormat.documentSelection("ok\u{1b}[201~rm -rf ~\r\nnext", path: "a\nb.md", fromLine: 1, toLine: 2)
    check(!hostile.contains("\u{1b}") && !hostile.contains("\r") && hostile.hasPrefix("From a b.md, lines 1–2:\n> ok[201~rm -rf ~\n> next"), "control characters can't escape the paste; fields stay on one line")
    check(SendFormat.file("docs/my notes.md") == "@\"docs/my notes.md\" " && SendFormat.file("docs/prd.md") == "@docs/prd.md ", "file references, quoted when they have spaces")
    let el = SendFormat.Element(tag: "button", label: "button#pay", selector: "#pay", trail: ["Checkout", "Payment"], text: "Pay", attributes: ["type": "submit"],
                                styles: ["color": "red"], rect: [1, 2, 30, 40], html: "<button>```</button>", url: "file:///x.html", title: "T")
    let ep = SendFormat.element(el, path: "x.html", screenshot: "/tmp/e.png")
    check(ep.contains("````html\n<button>```</button>\n````") && ep.contains("under: Checkout › Payment") && ep.contains("screenshot: /tmp/e.png"), "element payload: fence outgrows backticks, trail, screenshot")
    check(SendFormat.documentSelection(String(repeating: "x", count: 9000), path: "a", fromLine: 1, toLine: 1).count < SendFormat.cap + 100, "payloads are capped")

}

do { try MainActor.assumeIsolated { try run() } } catch { print("✘ setup: \(error)"); failures += 1 }
print("\(passes) passed, \(failures) failed")
exit(Int32(failures))


/// Runs async work from the synchronous checks.
func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Task.detached { do { result = .success(try await work()) } catch { result = .failure(error) }; sem.signal() }
    sem.wait()
    return try result.get()
}

/// .gitignore rules from text, applied to one path (checks only).
func GitIgnore_ignored(_ rel: String, rules text: String) -> Bool {
    let dir = FileManager.default.temporaryDirectory.appending(path: "gi-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? text.write(to: dir.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Lay the path out on disk and ask FileSource whether it would be indexed.
    let file = dir.appending(path: rel)
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "x".write(to: file, atomically: true, encoding: .utf8)
    return !FileSource.files(in: dir).contains { $0.relative == rel }
}

extension URL {
    /// Creates the parent folder and returns self (checks only).
    func creatingParent() -> URL {
        try? FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}

/// A snapshot context that ignores this Mac's real Claude history.
func noHistory(_ root: URL) -> LiveSnapshot.Context {
    var c = LiveSnapshot.Context(root: root)
    c.includeHistory = false
    return c
}


func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// Labels and clicks in the app's views that aren't tied to an action (DL-71). Buttons, menus and
/// menu items are matched by label against the registry's `ui` and `Parity.uiOnly`; clicks and
/// drags (`.onActivate {`, `.onDrag`, `.onDrop`) must say `// action: <verb>` on the same line.
func parityGaps() -> [String] {
    let known = Set(DuoAction.all.flatMap(\.ui)).union(Parity.uiOnly.keys)
    var gaps: [String] = []
    for c in DuoCommand.allCases where !known.contains(c.title) { gaps.append("menu \(c.title)") }
    let dir = repoRoot().appending(path: "Sources/DuoKit")
    let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    for file in files where !file.path.contains("/Debug/") {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let l = String(line)
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            for m in l.matches(of: /(?:Button|Menu|ActionMenuItem)\("((?:[^"\\]|\\.)+)"/) {
                let label = String(m.1).replacing(/\\\([^)]*\)/, with: "").replacing(/\s+/, with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :"))
                if !known.contains(label) { gaps.append("\(file.lastPathComponent):\(n + 1) \"\(label)\"") }
            }
            if l.contains(".onActivate {") || l.contains(".onDrag {") || l.contains(".onDrag(") || l.contains(".onDrop(") {
                if let m = l.firstMatch(of: /\/\/ action: ([a-z -]+)/), DuoAction.resolve(String(m.1).trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)) != nil
                    || l.contains("// not an action:") { continue }
                gaps.append("\(file.lastPathComponent):\(n + 1) click or drag without `// action: <verb>`")
            }
        }
    }
    return gaps
}
