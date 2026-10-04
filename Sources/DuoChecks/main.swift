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
    check(DuoCommand.allCases.map { "\($0.shortcut.key.character)\($0.shortcut.modifiers.rawValue)" }.count == Set(DuoCommand.allCases.map { "\($0.shortcut.key.character)\($0.shortcut.modifiers.rawValue)" }).count, "no two commands share a chord")

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
    let (snap, folders, _) = LiveSnapshot.build(.init(root: lw), beacons: [live])
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
    check(LiveSnapshot.build(.init(root: lw), beacons: [live, quiet]).0.counts.idle == 0, "a running, quiet session isn't counted as resumable")
    // `/cd`: a filed session running in another project's folder is listed there and moves (F-32).
    let other = lw.appending(path: "growth/onboarding")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try "---\ngoal: x\n---\n".write(to: other.appending(path: "PROJECT.md"), atomically: true, encoding: .utf8)
    let moved = Beacon(pid: 1, sessionId: "aaaa-filed", cwd: other.path, name: nil, status: "idle", waitingFor: nil,
                       statusUpdatedAt: nil, entrypoint: "cli", kind: nil)
    let (snap2, _, moves) = LiveSnapshot.build(.init(root: lw), beacons: [moved])
    check(snap2.sessions.first { $0.sessionId == "aaaa-filed" }?.project == "onboarding"
          && moves.map(\.sessionId) == ["aaaa-filed"] && moves.first?.to.lastPathComponent == "onboarding",
          "a session moved with /cd is listed in its new project, and its entry moves")
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
        let cov = try reader.coverage()
        check(cov.first?.complete == true && cov.first?.known == stats.files, "coverage reported")
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

    print("launch options")
    let o = LaunchOptions(arguments: ["Duo", "--state", "flow-zoom-3", "--capture", "/tmp/x.png", "--left", "collapsed"])
    check(o.state == .flowZoom3 && o.capturePath == "/tmp/x.png" && o.collapseLeft && o.capturing, "flags parse")

    print("tokens")
    check(DuoTextStyle.body.spec.size == 13 && DuoTextStyle.body.spec.lineHeight == 20, "body 13/20")
    check(DuoTextStyle.sectionLabel.spec.uppercase && DuoTextStyle.sectionLabel.spec.tracking == 0.66, "section label caps +0.66")
    check(DuoMetric.paneOverviewHome == 340 && DuoMetric.paneProjectRight == 460, "pane widths")
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
