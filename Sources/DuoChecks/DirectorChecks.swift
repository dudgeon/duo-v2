import DuoControl
import DuoKit
import Foundation

// The duo-director skill's exact parts (DL-193 to DL-206): the registry, log, rules, what a client
// can do, the send ladder, every guard on Duo pressing Enter (DL-199), the note conventions, the
// skill's install, and the verbs end to end against stand-in claudes (never a real one).
@MainActor func directorChecks() throws {
    print("director: names, cap, sections (DL-200, DL-201)")
    check(Director.name(project: "Duo v2") == "director-duo-v2" && Director.name(project: "Café notes") == "director-cafe-notes", "a director's fixed name is director-<project slug>")
    check(Director.cap(directorSection: nil) == 3 && Director.cap(directorSection: "- Max workers: 5") == 5 && Director.cap(directorSection: "max_workers = 1") == 1
          && Director.cap(directorSection: "max workers: 0") == 3 && Director.cap(directorSection: "work in pairs") == 3, "the cap is 3 unless ## Director says max workers: N (N > 0)")
    let brief = "# P\n\n## Goal\nship\n\n## Director\nmax workers: 2\nask before publishing\n\n## Decisions\n- 2026-10-14 x\n"
    check(Director.section("Director", in: brief) == "max workers: 2\nask before publishing" && Director.section("Missing", in: brief) == nil, "a ## section's body, up to the next heading")
    check(Director.holdsSlot(status: "in-progress", archived: false) && Director.holdsSlot(status: nil, archived: false) && Director.holdsSlot(status: "waiting", archived: false)
          && !Director.holdsSlot(status: "suggested", archived: false) && !Director.holdsSlot(status: "Done", archived: false) && !Director.holdsSlot(status: "dropped", archived: false)
          && !Director.holdsSlot(status: "in-progress", archived: true), "unfinished tasks hold a worker slot; suggested, done, dropped and archived don't")

    print("director: .duo/director.json (DL-200)")
    do {
        var r = DirectorRegistry()
        check(r.role(sessionId: "a") == .none, "no director yet")
        r.adopt(name: "director-p", sessionId: "a", at: "t1")
        check(r.role(sessionId: "a") == .current && r.retired.isEmpty, "the first director is current")
        check(r.role(sessionId: "zz") == .other(r.current!) && r.role(sessionId: nil) == .other(r.current!), "by id alone: another session with the same name is someone else (a name proves nothing)")
        r.adopt(name: "director-p", sessionId: "a2", at: "t2")
        check(r.current?.sessionId == "a2" && r.retired.isEmpty && r.role(sessionId: "a2") == .current, "--take-over by the same name (a resumed director, P3) moves the id, retiring nothing")
        r.adopt(name: "director-p2", sessionId: "b", at: "t3")
        check(r.current?.name == "director-p2" && r.retired.last?.name == "director-p" && r.retired.last?.replacedBy == "director-p2" && r.retired.last?.until == "t3", "a take-over retires the old director, replaced by the new")
        check(r.role(sessionId: "a2") == .replaced(by: r.current), "the replaced director, woken, learns it was replaced and by whom")
        r.setWorker(task: "tasks/x.md", session: "w1", at: "t", adopted: false)
        r.setWorker(task: "tasks/x.md", session: "w2", at: "t", adopted: true)
        check(r.workers.count == 1 && r.worker(task: "tasks/x.md")?.session == "w2" && r.worker(task: "tasks/x.md")?.adopted == true, "one worker per task: a new one replaces the old")
        let gone = r.retire(at: "t4")
        check(gone?.name == "director-p2" && r.current == nil && r.retired.count == 2, "retire stands the current director down")
        let old = try JSONDecoder().decode(DirectorRegistry.self, from: Data("{\"current\":{\"name\":\"d\",\"sessionId\":\"s\",\"since\":\"t\"}}".utf8))
        check(old.current?.name == "d" && old.workers.isEmpty && old.handedBack.isEmpty && old.pending.isEmpty, "a director.json missing newer keys still reads")
        r.handedBack = ["w2": "t5"]
        let dir = FileManager.default.temporaryDirectory.appending(path: "dreg-\(UUID().uuidString.prefix(6))")
        r.pending = [.init(task: "tasks/a.md", message: "hi", at: "t5")]
        try r.save(project: dir)
        check(DirectorRegistry.load(project: dir) == r && FileManager.default.fileExists(atPath: dir.appending(path: ".duo/director.json").path), "it round-trips through .duo/director.json")
        try? FileManager.default.removeItem(at: dir)
    }

    print("director: the log the metrics come from")
    do {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlog-\(UUID().uuidString.prefix(6))")
        for e in [DirectorEvent(at: "t", director: "d", event: "start", task: "tasks/a.md"),
                  DirectorEvent(at: "t", director: "d", event: "send", task: "tasks/a.md", rung: "duo-submit"),
                  DirectorEvent(at: "t", director: "d", event: "send", task: "tasks/a.md", rung: "queued"),
                  DirectorEvent(at: "t", director: "d", event: "send", task: "tasks/a.md", rung: "duo-submit"),
                  DirectorEvent(at: "t", director: "d", event: "refused", task: "tasks/b.md", detail: "directed by another director (x)"),
                  DirectorEvent(at: "t", director: "d", event: "takeover")] { DirectorLog.append(e, project: dir) }
        let events = DirectorLog.read(project: dir)
        let m = DirectorLog.metrics(events)
        check(events.count == 6 && m.sends == ["duo-submit": 2, "queued": 1] && m.starts == 1 && m.refusals == 1 && m.wrongAddress == 1 && m.takeovers == 1,
              "every line parses, and the rung of each send, refusals, wrong addresses and take-overs count from it")
        try? FileManager.default.removeItem(at: dir)
    }

    print("director: where the rules are (DL-207: Home's HOME.md, then the project's PROJECT.md)")
    do {
        let root = FileManager.default.temporaryDirectory.appending(path: "drules-\(UUID().uuidString.prefix(6))")
        let proj = root.appending(path: "p")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try Data(brief.utf8).write(to: proj.appending(path: "PROJECT.md"))
        try Data("# Home\n\n## Projects\n".utf8).write(to: root.appending(path: "HOME.md"))
        let s = DirectorRules.sources(project: proj, home: root)
        check(s.count == 2 && s[0].path.hasSuffix("/HOME.md") && s[1].path.hasSuffix("/p/PROJECT.md") && s[0].precedence < s[1].precedence && s[1].exists && !s[0].exists,
              "Home's ## Director for every director, then the project's, which wins inside it")
        check(DirectorRules.text(s[1]) == "max workers: 2\nask before publishing" && DirectorRules.text(s[0]) == nil, "a source's text is its ## Director section")
        check(DirectorRules.sources(project: root, home: root).count == 1 && DirectorRules.sources(project: proj, home: nil).map(\.precedence) == [1],
              "in Home itself, one source; with no Home, only the project's")
        let bare = root.appending(path: "bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let none = DirectorRules.sources(project: bare, home: root)
        check(none[1].fileExists == false && none[1].line.contains("no PROJECT.md yet") && none[0].fileExists && !none[0].exists && none[0].line.contains("no ## Director section yet"),
              "status tells no file (offer Make a Project) from a file with no Director section")
        let skill = DirectorSkill.text()
        check(!skill.contains("duo-director.md") && skill.contains("HOME.md") && skill.contains("duo2 director status"), "the skill keeps no rules of its own: Home's and the project's files")

        // Which project, which Home: from the folder alone, the same with Duo running or not.
        let tree = FileManager.default.temporaryDirectory.appending(path: "dplace-\(UUID().uuidString.prefix(6))"), fm = FileManager.default
        defer { try? fm.removeItem(at: tree) }
        let H = tree.appending(path: "Home"), alpha = H.appending(path: "alpha"), deep = alpha.appending(path: "docs/notes"), loose = H.appending(path: "loose/sub")
        for d in [deep, loose] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data("# above Home\n".utf8).write(to: tree.appending(path: "PROJECT.md"))
        try Data("# Home\n".utf8).write(to: H.appending(path: "HOME.md"))
        try Data("# alpha\n".utf8).write(to: alpha.appending(path: "PROJECT.md"))
        func at(_ u: URL) -> (String, String?) { let r = DirectorPlace.resolve(from: u); return (r.project.path, r.home?.path) }
        check(at(deep) == (alpha.path, H.path), "deep in a project: the nearest PROJECT.md, and Home above it")
        check(at(loose) == (loose.path, H.path), "in Home with no PROJECT.md above: that folder is the project (none yet), Home above it")
        check(at(H) == (H.path, H.path), "in Home itself: Home's director")
        check(at(tree) == (tree.path, nil), "outside any Home: the folder's own PROJECT.md, no Home")
        check(DirectorPlace.resolve(from: alpha).home?.path == H.path && at(loose).0 != tree.path, "a PROJECT.md above Home never counts as the project")
    }

    print("director: what the calling client can do")
    do {
        let root = FileManager.default.temporaryDirectory.appending(path: "dcaps-\(UUID().uuidString.prefix(6))")
        let cfg = root.appending(path: "cfg"), cwd = root.appending(path: "w"), fm = FileManager.default
        try fm.createDirectory(at: cfg.appending(path: "sessions"), withIntermediateDirectories: true)
        try fm.createDirectory(at: cwd.appending(path: ".claude"), withIntermediateDirectories: true)
        func write(_ j: Any, _ url: URL) throws { try JSONSerialization.data(withJSONObject: j).write(to: url) }
        try write(["pid": 4242, "sessionId": "s1", "version": "2.1.299", "name": "director-p", "peerFeatures": ["notify_idle"], "messagingSocketPath": "/tmp/x.sock", "bridgeSessionId": "session_x"],
                  cfg.appending(path: "sessions/4242.json"))
        try write(["cachedGrowthBookFeatures": ["tengu_amber_sentinel": true]], cfg.appending(path: ".claude.json"))
        let env = ["CLAUDE_PID": "4242", "CLAUDE_CODE_SESSION_ID": "s1", "CLAUDE_CONFIG_DIR": cfg.path, "DUO_SESSION_ID": "s1"]
        let managed = root.appending(path: "managed.json").path
        var c = ClientCaps.probe(env: env, cwd: cwd.path, claudeDir: cfg, managed: managed, home: root)
        check(c.version == "2.1.299" && c.name == "director-p" && c.messaging == .yes && c.remoteControlOn && c.inDuo && c.monitor == .yes
              && c.hooks == .yes && c.background == .yes && c.backgroundResume == .yes && !c.projects, "the current CLI in Duo: everything on (\(c.lines.joined(separator: " ")))")
        try write(["pid": 4242, "sessionId": "s1", "version": "2.1.219", "name": "duo-v2-ab"], cfg.appending(path: "sessions/4242.json"))
        try write(["disableAllHooks": true, "permissions": ["deny": ["Monitor"]]], cfg.appending(path: "settings.json"))
        try write(["disableRemoteControl": true, "disableAgentView": true], URL(fileURLWithPath: managed))
        c = ClientCaps.probe(env: env, cwd: cwd.path, claudeDir: cfg, managed: managed, home: root)
        check(c.version == "2.1.219" && c.messaging == .no && c.hooks == .no && c.monitor == .no && c.remoteControl == .no && c.background == .no && c.backgroundResume == .no,
              "the work Mac's shape: no messaging, hooks off, Monitor denied, no Remote Control or background (managed settings count)")
        try fm.removeItem(atPath: managed)
        try write(["crossSessionInbound": "refuse"], cwd.appending(path: ".claude/settings.local.json"))
        try write([String: Any](), cfg.appending(path: "settings.json"))
        try write(["cachedGrowthBookFeatures": ["tengu_amber_sentinel": false]], cfg.appending(path: ".claude.json"))
        try write(["pid": 4242, "sessionId": "s1", "version": "2.1.290", "peerFeatures": ["notify_idle"]], cfg.appending(path: "sessions/4242.json"))
        c = ClientCaps.probe(env: env.merging(["CLAUDE_CODE_PROJECTS_SESSION": "1"]) { $1 }, cwd: cwd.path, claudeDir: cfg, managed: managed, home: root)
        check(c.messaging == .no && c.monitor == .no && c.backgroundResume == .yes && c.projects, "a project's crossSessionInbound: refuse, the account without Monitor's flag (F-310), and a Projects session")
        c = ClientCaps.probe(env: ["CLAUDE_CODE_SESSION_ID": "nope", "CLAUDE_CONFIG_DIR": cfg.path], cwd: nil, claudeDir: cfg, managed: managed, home: root)
        check(c.version == nil && c.messaging == .unknown && c.monitor == .no && !c.notes.isEmpty, "no beacon: version and messaging unknown, and it says so")
        check(VersionOrder.atLeast("2.1.285", "2.1.285") && VersionOrder.atLeast("2.1.299", "2.1.285") && !VersionOrder.atLeast("2.1.219", "2.1.285") && VersionOrder.atLeast("2.2.0", "2.1.300"), "versions compare by number")
        try? fm.removeItem(at: root)
    }

    print("director: the send ladder (DL-199)")
    do {
        var full = ClientCaps(); full.messaging = .yes; full.backgroundResume = .yes
        var old = ClientCaps(); old.messaging = .no; old.backgroundResume = .no
        let L = SendLadder.choose
        check(L(full, WorkerFacts(place: .duo, run: .idle, peerName: "w1"), true) == .message && L(full, WorkerFacts(place: .background, run: .working, peerName: "w1"), true) == .message,
              "messaging first, where both sides have it")
        check(L(full, WorkerFacts(place: .duo, run: .idle), true) == .duoSubmit, "a worker without messaging, idle in Duo: Duo submits it")
        check(L(full, WorkerFacts(place: .background, run: .stopped, peerName: "w1"), true) == .resumeBackground && L(old, WorkerFacts(place: .background, run: .stopped), true) == .headless,
              "a stopped background worker: resumed with it (2.1.285+), else a headless turn")
        check(L(old, WorkerFacts(place: .duo, run: .stopped), true) == .duoResume && L(old, WorkerFacts(place: .duo, run: .stopped), false) == .askUser, "a stopped worker in Duo: reopened with it, while Duo runs")
        check(L(old, WorkerFacts(place: .duo, run: .working), true) == .queued && L(old, WorkerFacts(place: .duo, run: .needsYou), true) == .queued
              && L(old, WorkerFacts(place: .background, run: .working), true) == .queued, "a busy worker without messaging: it waits for the next idle")
        check(L(old, WorkerFacts(place: .duo, run: .idle, userTyping: true), true) == .queued, "never Duo's Enter into a worker the user is typing in")
        check(L(old, WorkerFacts(place: .unknown, run: .idle), true) == .askUser, "nothing reaches it: ask the user")
    }

    print("director: when Duo may press Enter (DL-199)")
    do {
        let now = Date()
        func f(_ change: (inout SubmitGuard.Facts) -> Void = { _ in }) -> SubmitGuard.Facts {
            var x = SubmitGuard.Facts(directedBy: "director-p", director: "director-p", onTask: true, idle: true, promptEmpty: true, lastUserKey: nil, now: now)
            change(&x); return x
        }
        check(SubmitGuard.refusal(f()) == nil, "every guard holds: Duo may submit")
        check(SubmitGuard.refusal(f { $0.directedBy = nil })?.contains("user's") == true && SubmitGuard.refusal(f { $0.directedBy = "  " }) != nil, "a task with no directed_by: is the user's")
        check(SubmitGuard.refusal(f { $0.directedBy = "director-q" })?.contains("another director") == true, "another director's task: no")
        check(SubmitGuard.refusal(f { $0.onTask = false }) != nil, "a session that isn't on the task: no")
        check(SubmitGuard.refusal(f { $0.idle = false })?.contains("idle") == true, "Claude not idle: no")
        check(SubmitGuard.refusal(f { $0.promptEmpty = false })?.contains("typed in its prompt") == true, "text in the prompt: no")
        check(SubmitGuard.refusal(f { $0.lastUserKey = now.addingTimeInterval(-30) })?.contains("typed there") == true
              && SubmitGuard.refusal(f { $0.lastUserKey = now.addingTimeInterval(-SubmitGuard.quietSeconds - 1) }) == nil,
              "the user typed there in the last 2 minutes: no; longer ago: yes")
    }

    print("director: has the user taken a worker over? (DL-200, from its transcript)")
    do {
        let tag = Director.tag("director-p")
        func line(_ text: String?, origin: String? = nil, meta: Bool = false, toolResult: Bool = false, at: String = "2026-10-15T10:00:00.000Z") -> String {
            var e: [String: Any] = ["type": "user", "timestamp": at]
            if meta { e["isMeta"] = true }
            if let origin { e["origin"] = ["kind": origin] }
            e["message"] = ["role": "user", "content": toolResult ? [["type": "tool_result", "content": "Allowed"]] as Any : (text ?? "") as Any]
            return String(decoding: try! JSONSerialization.data(withJSONObject: e), as: UTF8.self)
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "dtr-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func since(_ lines: [String]) throws -> Date? {
            let f = dir.appending(path: "t.jsonl")
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: f)
            return DirectorTranscript.userTurnSinceDirector(f, tag: tag)
        }
        let brief = line(tag + "You're the worker on the task", origin: "human")
        check(try since([brief]) == nil, "only the director's tagged brief: not taken over")
        check(try since([brief, line(nil, toolResult: true), line("<task-notification>x</task-notification>", origin: "task-notification"),
                         line("Another Claude session sent a message", origin: "peer", meta: true), line("Base directory for this skill", meta: true)]) == nil,
              "answers to prompts, task notifications, peer messages and meta entries aren't the user's")
        let typed = try since([brief, line("let me look at this myself", origin: "human", at: "2026-10-15T10:05:00.000Z")])
        check(typed == ISO8601DateFormatter().date(from: "2026-10-15T10:05:00Z"), "a human turn after the brief: taken over, at that turn's time")
        check(try since([brief, line("let me look", origin: "human"), line(tag + "Next step: the totals", origin: "human")]) == nil,
              "the director's next tagged message comes after it: the user's turn is behind it")
        check(try since([brief, line("an older client: no origin")]) != nil && (try since([brief, line("<command-name>/model</command-name>")])) == nil,
              "with no origin field (older clients): plain text is the user's, a <…> notice isn't")
    }

    print("director: task note conventions (DL-194)")
    do {
        let date = ISO8601DateFormatter().date(from: "2026-10-14T09:41:00Z")!
        let note = DirectorNotes.newNote(title: "One-page brief", request: "Draft a one-page brief from these three notes.\nDon't send it to anyone.",
                                         doneWhen: "a one-page brief in tasks/one-page-brief/", director: "director-p", status: "in-progress",
                                         links: [], template: Templates.baseTask, date: date)
        let t = TaskNotes.parse(note, path: "tasks/x.md")
        check(t.title == "One-page brief" && t.status == "in-progress" && DirectorNotes.directedBy(note) == "director-p" && DirectorNotes.doneWhen(note) == "a one-page brief in tasks/one-page-brief/",
              "a new directed task: title, status, directed_by:, done_when:")
        check(note.contains("## Request\n\nDraft a one-page brief from these three notes.\nDon't send it to anyone.\n") && note.contains("## Progress\n\n- 2026-10-14 "),
              "## Request holds the user's words exactly; ## Progress starts with a dated line")
        let s = DirectorNotes.newNote(title: "x", request: "y", doneWhen: nil, director: "d", status: DirectorNotes.suggested, links: [], template: Templates.baseTask)
        check(TaskNotes.parse(s, path: "x.md").status == "suggested" && DirectorNotes.doneWhen(s) == nil, "proposed work is status: suggested (DL-150 shows it as a column)")
        let user = "---\ntitle: Mine\nstatus: open\n---\n# Mine\n\nMy notes.\n\n## Progress\n\n- 2026-10-01 started\n\n## Later\n\nkeep me\n"
        let a = DirectorNotes.appending("- 2026-10-14 09:00 sent", toSection: "Progress", in: user)
        check(a == "---\ntitle: Mine\nstatus: open\n---\n# Mine\n\nMy notes.\n\n## Progress\n\n- 2026-10-01 started\n- 2026-10-14 09:00 sent\n\n## Later\n\nkeep me\n",
              "a Progress line goes after the section's last line; nothing else moves")
        let b = DirectorNotes.appending("- x", toSection: "Progress", in: "---\ntitle: T\n---\n# T\n\nbody\n")
        check(b == "---\ntitle: T\n---\n# T\n\nbody\n\n## Progress\n\n- x\n", "no Progress yet: the section is added at the end")
        let c = DirectorNotes.appending("- x", toSection: "Progress", in: "---\ntitle: T\n---\n# T\n\n## Progress\n")
        check(c == "---\ntitle: T\n---\n# T\n\n## Progress\n\n- x\n", "an empty Progress takes its first line under a blank one")
        check(TaskNotes.apply(.setKey("directed_by", "director-p"), to: user)?.contains("status: open\ndirected_by: director-p\n---") == true
              && TaskNotes.apply(.setKey("directed_by", "director-p"), to: TaskNotes.apply(.setKey("directed_by", "director-p"), to: user)!) == nil,
              "setting directed_by: touches only that key, and setting it again changes nothing")
        check(DirectorNotes.progressLine("two\nlines", date: date).hasSuffix(" two lines") && DirectorNotes.workerPrompt(path: "tasks/x.md", director: "director-p").contains("@tasks/x.md"),
              "a Progress line stays one line; a worker's brief points at its note")
    }

    print("director: the duo-director skill (DL-193)")
    do {
        let source = (try? String(contentsOf: repoRoot().appending(path: "skills/duo-director/SKILL.md"), encoding: .utf8)) ?? ""
        let skill = DirectorSkill.text()
        check(!source.isEmpty && skill == source.replacingOccurrences(of: "{{FORMAT}}", with: "\(DirectorSkill.format)"),
              "DirectorSkillText.swift is skills/duo-director/SKILL.md (run scripts/gen-director-skill.py)")
        check(skill.hasPrefix("---\nname: duo-director\n") && !skill.contains("\nname: director\n"), "it's named duo-director, so it never hides a project's own director skill")
        for verb in ["status", "start", "send", "retire", "guide", "watch"] { check(skill.contains("duo2 director \(verb)"), "the skill uses `duo2 director \(verb)`") }
        let verbs = Set(skill.matches(of: /duo2 ([a-z-]+(?: [a-z-]+)?)/).map { String($0.1) })
        let unknown = verbs.filter { v in DuoAction.resolve(v.split(separator: " ").map(String.init)) == nil && !DuoAction.all.contains { $0.verb.hasPrefix(v + " ") } }
        check(unknown.isEmpty, "every duo2 verb the skill names exists (\(unknown.sorted()))")

        let saved = Installer.testRoot
        let root = FileManager.default.temporaryDirectory.appending(path: "dskill-\(UUID().uuidString.prefix(6))")
        Installer.testRoot = root
        defer { Installer.testRoot = saved; try? FileManager.default.removeItem(at: root) }
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        let r1 = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        let file = Installer.directorSkillFile
        check(file.path.hasSuffix("claude/skills/duo-director/SKILL.md") && (try? String(contentsOf: file, encoding: .utf8)) == skill && r1.lines.contains("Director skill: written."),
              "install writes ~/.claude/skills/duo-director/SKILL.md")
        check(Installer.status(cli: nil).contains { $0.hasPrefix("Director skill: current") }, "doctor says it's current")
        try Data((skill + "\nmy own line\n").utf8).write(to: file)
        let r2 = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        check(r2.lines.contains("Director skill: edited by you, left alone.") && ((try? String(contentsOf: file, encoding: .utf8))?.hasSuffix("my own line\n") ?? false),
              "an edited skill is left alone (fork-on-edit)")
        check(Installer.status(cli: nil).contains { $0.hasPrefix("Director skill: edited by you") }, "and doctor says so")
        let u1 = Installer.uninstall()
        check(u1.lines.contains { $0.hasPrefix("Left ") && $0.contains("duo-director") } && FileManager.default.fileExists(atPath: file.path), "uninstall leaves the edited one")
        try FileManager.default.removeItem(at: file)
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        _ = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        let u2 = Installer.uninstall()
        check(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path) && u2.lines.contains { $0.contains("skills/duo-director") }, "and removes Duo's own")
        check(Installer.plannedItems(cli: "/x").contains { $0.what == "Write the duo-director skill" }, "the install question lists it")

        // A skill the user already had, before Duo ever wrote one: theirs, never claimed or removed.
        let fm = FileManager.default
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\nname: duo-director\n---\nmy own director\n".utf8).write(to: file)
        let r3 = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        check(r3.lines.contains { $0.contains("was there before Duo's") } && (try? String(contentsOf: file, encoding: .utf8))?.contains("my own director") == true
              && Installer.manifest().directorSkillHash == nil, "a skill that was there first is left alone and not recorded as Duo's")
        _ = Installer.uninstall()
        check((try? String(contentsOf: file, encoding: .utf8))?.contains("my own director") == true, "so uninstall leaves it")
        try fm.removeItem(at: file.deletingLastPathComponent())
        // The duo2 skill follows the same rule.
        try fm.createDirectory(at: Installer.skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("my own duo2 notes\n".utf8).write(to: Installer.skillFile)
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        _ = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        _ = Installer.uninstall()
        check((try? String(contentsOf: Installer.skillFile, encoding: .utf8)) == "my own duo2 notes\n", "the duo2 skill too: one that was there first survives install and uninstall")
        try fm.removeItem(at: Installer.skillFile.deletingLastPathComponent())
        // Uninstall removes Duo's SKILL.md only, and the folder only when it's empty.
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        _ = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        let extra = file.deletingLastPathComponent().appending(path: "notes.md")
        try Data("mine".utf8).write(to: extra)
        _ = Installer.uninstall()
        check(!fm.fileExists(atPath: file.path) && fm.fileExists(atPath: extra.path), "uninstall takes Duo's SKILL.md and leaves the user's other files in the folder")
        try fm.removeItem(at: file.deletingLastPathComponent())
        // A linked skill folder is the user's arrangement: never written through or removed.
        let elsewhere = root.appending(path: "elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: file.deletingLastPathComponent(), withDestinationURL: elsewhere)
        Installer.recordConsent(true, cli: "/x/Duo.app/Contents/Helpers/duo2")
        let r4 = Installer.install(cli: "/x/Duo.app/Contents/Helpers/duo2")
        _ = Installer.uninstall()
        check(r4.lines.contains { $0.contains("is a link") } && (try? fm.contentsOfDirectory(atPath: elsewhere.path))?.isEmpty == true
              && (try? fm.destinationOfSymbolicLink(atPath: file.deletingLastPathComponent().path)) != nil,
              "a linked skill folder: nothing written through it, and the link stays")
    }

    try directorEndToEnd()
}

/// The verbs through the control plane, on a live model with stand-in claudes that record their
/// arguments; the terminal side of Duo's Enter is a scripted screen.
@MainActor private func directorEndToEnd() throws {
    print("director: the verbs end to end (stand-in claude)")
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-dir-\(UUID().uuidString.prefix(8))")
    let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p")
    let log = root.appending(path: "claude.log")
    for d in [support, config, proj.appending(path: "tasks")] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try Data("# p\n\n## Director\nmax workers: 2\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
    try Data("---\ntitle: Theirs\nstatus: open\n---\n# Theirs\n\nThe user's own task.\n".utf8).write(to: proj.appending(path: "tasks/theirs.md"))
    let script = """
    #!/usr/bin/python3
    import os, sys, json
    a = sys.argv[1:]
    if a == ["--version"]: print("2.1.219 (Claude Code)"); sys.exit(0)
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
    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "dirproj", "topic": "Platform", "path": proj.path, "goal": "g"])))
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["dirproj"] = proj
    defer {
        for s in m.fixture.sessions { m.terminals.existing(s.tabKey)?.terminate() }
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        ClaudeLocator.forget()
        UserTyping.reset()
        try? fm.removeItem(at: root)
    }
    func wait(_ what: () -> Bool) { let until = Date().addingTimeInterval(8); while !what(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } }
    func caps(_ name: String?) -> String {
        var c = ClientCaps(); c.name = name; c.messaging = .no; c.version = "2.1.219"; c.backgroundResume = .no; c.monitor = .no
        return String(decoding: try! JSONEncoder().encode(c), as: UTF8.self)
    }
    func run(_ verb: String, _ args: [String], as session: String, name: String? = nil) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: verb, args: args + ["--caps", caps(name)], session: session, cwd: proj.path)) { out = $0 }
        wait { out != nil }
        return out ?? ControlResponse(ok: false, output: "no answer")
    }
    /// A verb that makes Duo ask the user: waits for Duo's question, answers it with `answer` (as the
    /// user would click), then waits for the verb's reply.
    func runAnswering(_ verb: String, _ args: [String], as session: String, name: String? = nil, answer: String) -> (ControlResponse, String?) {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: verb, args: args + ["--caps", caps(name)], session: session, cwd: proj.path)) { out = $0 }
        wait { SheetCenter.shared.current != nil || out != nil }
        let asked = SheetCenter.shared.current?.title
        if let q = SheetCenter.shared.current, let c = q.choices.first(where: { $0.label == answer }) { SheetCenter.shared.answer(c) }
        wait { out != nil }
        return (out ?? ControlResponse(ok: false, output: "no answer"), asked)
    }
    func note(_ path: String) -> String { (try? String(contentsOf: proj.appending(path: path), encoding: .utf8)) ?? "" }
    func setState(_ id: String, _ state: SessionState) { if let i = m.fixture.sessions.firstIndex(where: { $0.sessionId == id }) { m.fixture.sessions[i].state = state } }
    func args(_ id: String) -> [String]? {
        let until = Date().addingTimeInterval(8)
        while Date() < until {
            let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n")
            if let l = lines.last(where: { $0.contains(id) }) { return (try? JSONSerialization.jsonObject(with: Data(l.dropFirst(5).utf8))) as? [String] }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }
    let D = "dir-session-1", D2 = "dir-session-2", D3Pre = D

    // status before anyone directs.
    var r = run("director status", ["--json"], as: D, name: "director-dirproj")
    let j0 = (try? JSONSerialization.jsonObject(with: Data(r.output.utf8))) as? [String: Any]
    check(r.ok && j0?["role"] as? String == "none" && j0?["cap"] as? Int == 2 && ((j0?["rules"] as? [[String: Any]])?.last?["path"] as? String)?.hasSuffix("/p/PROJECT.md") == true,
          "status: nobody directs yet; the project's cap is 2; its Director section is listed (\(r.output.prefix(300)))")

    // A folder Duo doesn't know: refused, never a guess from what's on screen.
    var stray: ControlResponse?
    m.open(project: "dirproj")
    m.handle(ControlRequest(token: "", command: "director status", args: ["--caps", caps("director-dirproj")], session: D, cwd: "/private/var/empty")) { stray = $0 }
    wait { stray != nil }
    check(stray?.ok == false && stray?.output.contains("doesn't know") == true, "status from a folder Duo doesn't know is refused, though a project is on screen")

    // start a new task.
    r = run("director start", ["--title", "One-page brief", "--request", "Draft a one-page brief from these three notes.", "--done-when", "a brief exists"], as: D, name: "director-dirproj")
    let brief = note("tasks/one-page-brief.md")
    let w1 = TaskNotes.parse(brief, path: "x").sessionIds.first ?? ""
    check(r.ok && DirectorNotes.directedBy(brief) == "director-dirproj" && brief.contains("## Request\n\nDraft a one-page brief from these three notes.")
          && TaskNotes.parse(brief, path: "x").status == "in-progress" && !w1.isEmpty && brief.contains("## Progress"),
          "start writes the task (directed_by:, Request, Progress), links its worker and sets it in progress (\(r.output))")
    let a1 = args(w1)
    check(a1?.contains("--session-id") == true && a1?.last?.contains("@tasks/one-page-brief.md") == true, "the worker starts in Duo with its task as its brief")
    check(DirectorRegistry.load(project: proj).current?.name == "director-dirproj" && DirectorRegistry.load(project: proj).current?.sessionId == D, "the first start makes it the project's director")

    // never another's task, never the user's.
    r = run("director send", ["theirs", "please do x"], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("user's"), "send refuses a task with no directed_by: (the user's)")
    r = run("director start", ["--title", "Other", "--request", "x"], as: D2, name: "worker-z")
    check(!r.ok && r.output.contains("directed by director-dirproj"), "a second session can't start work in a directed project without --take-over")

    // the cap.
    r = run("director start", ["--title", "Second", "--request", "two"], as: D, name: "director-dirproj")
    check(r.ok, "a second worker fits the cap of 2")
    r = run("director start", ["--title", "Third", "--request", "three"], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("2 of 2") && TaskNotes.parse(note("tasks/third.md"), path: "x").status == "suggested" && TaskNotes.parse(note("tasks/third.md"), path: "x").sessionIds.isEmpty,
          "a third is refused, and its task waits as suggested with no worker")
    r = run("director start", ["--title", "Idea", "--request", "maybe", "--suggest"], as: D, name: "director-dirproj")
    check(r.ok && TaskNotes.parse(note("tasks/idea.md"), path: "x").status == "suggested", "--suggest files proposed work without a worker")
    r = run("director start", ["--title", "File notes from the pricing sync", "--request", "Route these notes.", "--no-worker"], as: D, name: "director-dirproj")
    let filing = TaskNotes.parse(note("tasks/file-notes-from-the-pricing-sync.md"), path: "x")
    check(r.ok && filing.status == "in-progress" && filing.sessionIds.isEmpty && note("tasks/file-notes-from-the-pricing-sync.md").contains("itself (organising work)"),
          "--no-worker: organising work the director does itself, over the cap, with no worker (DL-208)")

    // The user's own tasks and sessions are never a director's without the user's yes, and Duo asks
    // for it itself (DL-200): the director's word is never the yes.
    try Data("# p\n\n## Director\nmax workers: 5\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
    r = run("director start", ["theirs"], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("--adopt") && DirectorNotes.directedBy(note("tasks/theirs.md")) == nil && SheetCenter.shared.current == nil,
          "starting the user's task (no directed_by:): refused, the note untouched, and no question without --adopt")
    let user = m.newSession(in: "dirproj")!   // the user's own session: Duo started it, not the director
    r = run("director start", ["--title", "Pair", "--request", "p", "--worker", user], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("wasn't started by you") && !fm.fileExists(atPath: proj.appending(path: "tasks/pair.md").path),
          "--worker with the user's session: refused without --adopt, before anything is written")
    var (ra, asked) = runAnswering("director start", ["--title", "Pair", "--request", "p", "--worker", user, "--adopt"], as: D, name: "director-dirproj", answer: "Cancel")
    check(asked?.contains("take this on") == true && !ra.ok && ra.output.contains("not now") && !fm.fileExists(atPath: proj.appending(path: "tasks/pair.md").path),
          "--adopt: Duo asks the user; on Cancel nothing is written and it stays theirs")
    (ra, asked) = runAnswering("director start", ["--title", "Pair", "--request", "p", "--worker", user, "--adopt"], as: D, name: "director-dirproj", answer: "Allow")
    check(ra.ok && DirectorRegistry.load(project: proj).worker(task: "tasks/pair.md")?.adopted == true && DirectorRegistry.load(project: proj).worker(task: "tasks/pair.md")?.session == user,
          "on Allow the session becomes the task's worker, recorded as adopted (\(ra.output.prefix(100)))")
    r = run("director start", ["pair", "--worker", D], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("that's you"), "a director can't be its own worker")
    (ra, _) = runAnswering("director start", ["theirs", "--adopt", "--no-worker"], as: D, name: "director-dirproj", answer: "Allow")
    let theirs = note("tasks/theirs.md")
    check(ra.ok && theirs.contains("directed_by: \"director-dirproj\"") && DirectorRegistry.load(project: proj).worker(task: "tasks/theirs.md") == nil,
          "adopting the user's task with --no-worker, on the user's Allow: directed_by: is set (quoted) and its linked sessions don't become workers")
    try Data("---\ntitle: Linked\nstatus: in-progress\ndirected_by: \"director-dirproj\"\nsessions:\n  - \"[mine](duo2://session/\(user))\"\n---\n# Linked\n".utf8).write(to: proj.appending(path: "tasks/linked.md"))
    r = run("director send", ["linked", "hello"], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("no worker of yours"), "a session a directed note merely links isn't a worker: send refuses")
    var guardRefusal: String?
    m.submitHooks = AppModel.SubmitIO(read: { AppModel.PromptRead(idle: true, input: "") }, beaconIdle: { true }, type: { _ in }, settle: 0.01)
    m.guardedSubmit(key: user, message: "x", directedBy: "director-dirproj", director: "director-dirproj", onTask: false) { why, _ in guardRefusal = why }
    wait { guardRefusal != nil }
    check(guardRefusal?.contains("isn't on the task") == true, "the guard's onTask is real: a session that isn't the task's worker is refused")
    m.submitHooks = nil

    // Duo's Enter, through a scripted screen.
    typealias PromptRead = AppModel.PromptRead
    var screen = PromptRead(idle: true, input: "")
    var typed: [String] = []
    var beaconIdle = true
    m.submitHooks = AppModel.SubmitIO(read: { screen }, beaconIdle: { beaconIdle }, type: { s in
        typed.append(s)
        if s != "\r" { screen.input = String(SendFormat.clean(s.replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: ""))) }
    }, settle: 0.05)
    setState(w1, .idle)
    r = run("director send", ["one-page-brief", "Use the second note as the outline."], as: D, name: "director-dirproj")
    check(r.ok && r.output.hasPrefix("Delivered") && typed.count == 2 && typed[0].hasPrefix("\u{1b}[200~[director-dirproj] Use the second note") && typed[1] == "\r",
          "an idle worker on your task: Duo types the message, sees it in the prompt, then presses Enter (\(r.output))")
    check(note("tasks/one-page-brief.md").contains("Sent to the worker (Duo typed it and pressed Enter): Use the second note as the outline."), "the send is noted in Progress")

    typed = []; screen = PromptRead(idle: true, input: "half a thought")
    r = run("director send", ["one-page-brief", "Another thing."], as: D, name: "director-dirproj")
    check(r.ok && r.output.hasPrefix("Queued") && typed.isEmpty && DirectorRegistry.load(project: proj).pending.count == 1,
          "text in the worker's prompt: nothing typed, the message waits (\(r.output))")
    screen = PromptRead(idle: false, input: "")
    m.deliverDirectorMessages(); wait { false || !typed.isEmpty }
    check(typed.isEmpty && DirectorRegistry.load(project: proj).pending.count == 1, "still busy at the next refresh: it keeps waiting, untouched")
    screen = PromptRead(idle: true, input: ""); typed = []
    m.deliverDirectorMessages(); wait { typed.count == 2 }
    check(typed.count == 2 && typed[1] == "\r" && DirectorRegistry.load(project: proj).pending.isEmpty, "idle and empty at the next refresh: delivered, and the queue is empty")

    // The user takes the worker over (a turn of theirs in its transcript): the director is paused
    // there until the user hands it back in Duo (DL-200). It holds across restarts by nature.
    let wBucket = config.appending(path: "projects").appending(path: ClaudeStorage.encode(proj.resolvingSymlinksInPath().path))
    try fm.createDirectory(at: wBucket, withIntermediateDirectories: true)
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    func turn(_ text: String, origin: String, at: Date) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "user", "timestamp": iso.string(from: at), "sessionId": w1,
            "cwd": proj.resolvingSymlinksInPath().path, "origin": ["kind": origin], "message": ["role": "user", "content": text]]), as: UTF8.self)
    }
    func transcript(_ lines: [String]) throws { try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: wBucket.appending(path: w1 + ".jsonl")) }
    let briefLine = turn(Director.tag("director-dirproj") + "You're the worker on the task", origin: "human", at: Date().addingTimeInterval(-600))
    try transcript([briefLine])
    func statusWorker() -> [String: Any]? {
        let s = run("director status", ["--json"], as: D, name: "director-dirproj")
        return (((try? JSONSerialization.jsonObject(with: Data(s.output.utf8))) as? [String: Any])?["workers"] as? [[String: Any]])?.first { $0["task"] as? String == "tasks/one-page-brief.md" }
    }
    check(statusWorker()?["userTyping"] as? Bool == false && statusWorker()?["userTurnAt"] == nil, "only the director's brief in its transcript: not taken over")
    try transcript([briefLine, turn("<task-notification>done</task-notification>", origin: "task-notification", at: Date().addingTimeInterval(-500))])
    check(statusWorker()?["userTyping"] as? Bool == false, "a task notification isn't the user")
    try transcript([briefLine, turn("let me look at this myself", origin: "human", at: Date().addingTimeInterval(-300))])
    let sw = statusWorker()
    check(sw?["userTyping"] as? Bool == true && sw?["userTurnAt"] != nil, "a turn the user typed (in Duo, from the phone, anywhere): status says it was taken over, and when")
    typed = []
    r = run("director send", ["one-page-brief", "Ping."], as: D, name: "director-dirproj")
    check(!r.ok && r.output.contains("paused") && r.output.contains("--handed-back") && typed.isEmpty, "the director is paused there, and is told how to ask")
    (ra, asked) = runAnswering("director send", ["one-page-brief", "Ping.", "--handed-back"], as: D, name: "director-dirproj", answer: "Cancel")
    check(asked?.hasPrefix("Hand ") == true && !ra.ok && ra.output.contains("kept it paused") && typed.isEmpty,
          "--handed-back: Duo asks the user; on Cancel nothing is sent and the pause stays")
    screen = PromptRead(idle: true, input: "")
    m.submitHooks?.type = { s in typed.append(s); if s != "\r" { screen.input = String(SendFormat.clean(s.replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: ""))) } }
    typed = []
    (ra, _) = runAnswering("director send", ["one-page-brief", "Ping.", "--handed-back"], as: D, name: "director-dirproj", answer: "Hand Back")
    check(ra.ok && ra.output.hasPrefix("Delivered") && typed.first?.contains("[director-dirproj] Ping.") == true && typed.last == "\r"
          && DirectorRegistry.load(project: proj).handedBack[w1] != nil && statusWorker()?["userTyping"] as? Bool == false,
          "on Hand Back the message goes, tagged as the director's, and the earlier turn no longer pauses it (\(ra.output))")
    try transcript([briefLine, turn("let me look at this myself", origin: "human", at: Date().addingTimeInterval(-300)),
                    turn("one more thing from me", origin: "human", at: Date().addingTimeInterval(60))])
    check(statusWorker()?["userTyping"] as? Bool == true, "a new turn of the user's after the hand-back pauses it again")
    try transcript([briefLine])

    // Typed but not sent: left in the prompt for the user, and never queued as well.
    UserTyping.reset()
    var reg = DirectorRegistry.load(project: proj); reg.pending = []; try reg.save(project: proj)
    typed = []; screen = PromptRead(idle: true, input: "")
    m.submitHooks?.type = { s in typed.append(s); if s != "\r" { screen.input = "Late"; UserTyping.note(w1) } }
    r = run("director send", ["one-page-brief", "Late message."], as: D, name: "director-dirproj")
    check(typed.count == 1 && !typed.contains("\r") && r.output.contains("left in the worker's prompt") && DirectorRegistry.load(project: proj).pending.isEmpty,
          "the user typed while Duo typed: no Enter, the text stays in the prompt, nothing queued (\(r.output))")
    UserTyping.reset(); reg = DirectorRegistry.load(project: proj); reg.pending = []; try reg.save(project: proj)
    typed = []; screen = PromptRead(idle: true, input: "")
    m.submitHooks?.type = { s in typed.append(s); if s != "\r" { screen.input = "something else entirely" } }
    r = run("director send", ["one-page-brief", "Check the totals."], as: D, name: "director-dirproj")
    check(typed.count == 1 && r.output.contains("didn't show") && DirectorRegistry.load(project: proj).pending.isEmpty, "the prompt doesn't show the message: no Enter, not queued")
    typed = []; screen = PromptRead(idle: true, input: "")
    m.submitHooks?.type = { s in typed.append(s); if s != "\r" { screen.input = "Check"; beaconIdle = false } }
    r = run("director send", ["one-page-brief", "Check the totals."], as: D, name: "director-dirproj")
    check(typed.count == 1 && r.output.contains("stopped being idle"), "Claude stops being idle while Duo types: no Enter")
    beaconIdle = true
    reg = DirectorRegistry.load(project: proj); reg.pending = []; try reg.save(project: proj)
    m.submitHooks = nil

    // A stopped worker in Duo is reopened with the message as its next prompt, after `--`.
    func active() -> Int { (((try? JSONSerialization.jsonObject(with: Data(run("director status", ["--json"], as: D, name: "director-dirproj").output.utf8))) as? [String: Any])?["active"] as? Int) ?? -1 }
    let activeBefore = active()
    m.terminals.existing(w1)?.terminate()
    wait { m.terminals.existing(w1)?.exited != false }
    check(activeBefore > 0 && active() == activeBefore - 1, "a stopped worker frees its slot: the cap counts running workers (\(activeBefore) then \(active()))")
    let bucket = config.appending(path: "projects").appending(path: ClaudeStorage.encode(proj.resolvingSymlinksInPath().path))
    try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
    try Data("{\"type\":\"user\",\"cwd\":\"\(proj.resolvingSymlinksInPath().path)\",\"sessionId\":\"\(w1)\"}\n".utf8).write(to: bucket.appending(path: w1 + ".jsonl"))
    r = run("director send", ["one-page-brief", "-p looks like a flag"], as: D, name: "director-dirproj")
    wait { (args(w1) ?? []).contains("--resume") }
    let resumed = args(w1) ?? []
    check(r.ok && r.output.contains("reopened") && resumed.contains("--resume") && resumed.suffix(2) == ["--", "[director-dirproj] -p looks like a flag"],
          "a stopped worker in Duo: reopened with the message as its next prompt, after -- (\(resumed.suffix(2)))")

    // A headless turn: it runs in its own folder, its output is kept, and its status comes back.
    let runLog = root.appending(path: "run.log")
    var exit: Int32 = -1
    let started = AppModel.runDetached("/bin/sh", ["-c", "pwd; echo \"$@\"; exit 3", "sh", "--", "-x message"], cwd: support.path, log: runLog) { exit = $0 }
    wait { exit != -1 }
    let out = (try? String(contentsOf: runLog, encoding: .utf8)) ?? ""
    check(started == nil && exit == 3 && out.contains(support.resolvingSymlinksInPath().lastPathComponent) && out.contains("-- -x message"),
          "runDetached runs in the given folder, keeps the output, and reports the exit status (\(exit))")

    // A worker the director starts in the background: pending under a name unique to the start, and
    // linked by Duo when a session with that name appears (claude --bg ignores --session-id, F-318).
    r = run("director start", ["--title", "Bg job", "--request", "b", "--background"], as: D3Pre, name: "director-dirproj")
    let bgWorker = DirectorRegistry.load(project: proj).worker(task: "tasks/bg-job.md")
    check(r.ok && bgWorker?.pending == true && bgWorker?.name?.hasPrefix("bg-job-") == true && r.output.contains("-n '\(bgWorker?.name ?? "?")'")
          && !r.output.contains("--session-id") && r.output.contains("-- '"),
          "start --background prints a claude --bg command named for this start, and records the worker as pending")
    r = run("director status", [], as: D3Pre, name: "director-dirproj")
    check(r.output.contains("starting in the background as \(bgWorker?.name ?? "?")"), "status shows it as starting")
    // Claude starts it: its beacon carries that name and Claude's own id.
    let bgId = "b9b9b9b9-0000-4000-8000-000000000001"
    try Data("{\"pid\": \(getpid()), \"sessionId\": \"\(bgId)\", \"cwd\": \"\(proj.path)\", \"status\": \"idle\", \"name\": \"\(bgWorker?.name ?? "?")\"}".utf8)
        .write(to: config.appending(path: "sessions/\(getpid()).json"))
    m.deliverDirectorMessages()   // a refresh
    let linked = DirectorRegistry.load(project: proj).worker(task: "tasks/bg-job.md")
    check(linked?.session == bgId && linked?.pending == false && linked?.adopted == false && note("tasks/bg-job.md").contains(bgId),
          "at the next refresh Duo links it by its name: no link step, no --adopt, and the note links the session")
    try? fm.removeItem(at: config.appending(path: "sessions/\(getpid()).json"))
    // Pending workers hold their slot until they appear, or for 30 minutes.
    let slots = active()   // running and pending workers, as the cap counts them
    try Data("# p\n\n## Director\nmax workers: \(slots + 1)\n".utf8).write(to: proj.appending(path: "PROJECT.md"))
    r = run("director start", ["--title", "Bg two", "--request", "b2", "--background"], as: D3Pre, name: "director-dirproj")
    check(r.ok, "a background start fits the last slot (\(slots + 1))")
    r = run("director start", ["--title", "Bg three", "--request", "b3", "--background"], as: D3Pre, name: "director-dirproj")
    check(!r.ok && r.output.contains("of \(slots + 1)"), "the next is refused: a pending worker still holds its slot (\(r.output.prefix(80)))")
    var reg2 = DirectorRegistry.load(project: proj)
    if let i = reg2.workers.firstIndex(where: { $0.task == "tasks/bg-two.md" }) { reg2.workers[i].since = "2026-01-01T00:00:00Z" }
    try reg2.save(project: proj)
    m.deliverDirectorMessages()
    check(DirectorRegistry.load(project: proj).worker(task: "tasks/bg-two.md") == nil, "a pending worker that never appears frees its slot after 30 minutes")
    try Data("# p\n\n## Director\nmax workers: 5\n".utf8).write(to: proj.appending(path: "PROJECT.md"))

    // Done or archived tasks lose their worker entry; old run logs are pruned.
    try Data(note("tasks/bg-job.md").replacingOccurrences(of: "status: in-progress", with: "status: done").utf8).write(to: proj.appending(path: "tasks/bg-job.md"))
    m.deliverDirectorMessages()
    check(DirectorRegistry.load(project: proj).worker(task: "tasks/bg-job.md") == nil && DirectorRegistry.load(project: proj).worker(task: "tasks/one-page-brief.md") != nil,
          "a done task's worker entry is removed at the next refresh; others stay")
    let runs = root.appending(path: "runs")
    try fm.createDirectory(at: runs, withIntermediateDirectories: true)
    for i in 1...7 { try Data().write(to: runs.appending(path: "abcdef12-\(1000 + i).log")) }
    try Data().write(to: runs.appending(path: "99999999-1.log"))
    AppModel.pruneRuns(beside: runs.appending(path: "abcdef12-2000.log"))
    let left = (try? fm.contentsOfDirectory(atPath: runs.path).sorted()) ?? []
    check(left == ["99999999-1.log", "abcdef12-1004.log", "abcdef12-1005.log", "abcdef12-1006.log", "abcdef12-1007.log"],
          "a new run log keeps the newest \(AppModel.runsKept - 1) old ones of that worker, and other workers' alone (\(left))")

    // Paths from director.json stay in tasks/.
    check(DirectorRegistry.isTaskPath("tasks/a.md") && !DirectorRegistry.isTaskPath("../../a.md") && !DirectorRegistry.isTaskPath("tasks/../../a.md")
          && !DirectorRegistry.isTaskPath("tasks/sub/a.md") && !DirectorRegistry.isTaskPath("/etc/a.md"), "only notes directly in tasks/ count")
    let outside = root.appending(path: "escaped.md")
    try Data("---\ntitle: x\n---\n".utf8).write(to: outside)
    reg = DirectorRegistry.load(project: proj); reg.pending = [.init(task: "tasks/../../escaped.md", message: "x", at: "t")]; try reg.save(project: proj)
    m.deliverDirectorMessages()
    check(DirectorRegistry.load(project: proj).pending.isEmpty && (try? String(contentsOf: outside, encoding: .utf8)) == "---\ntitle: x\n---\n",
          "a pending message naming a path outside tasks/ is dropped, and nothing outside is written")

    // The same name is not the same director: only --take-over moves the registry.
    let D3 = "dir-session-3"
    r = run("director status", ["--json"], as: D3, name: "director-dirproj")
    check(((try? JSONSerialization.jsonObject(with: Data(r.output.utf8))) as? [String: Any])?["role"] as? String == "other"
          && DirectorRegistry.load(project: proj).current?.sessionId == D,
          "a session with the director's name sees another director, and status never moves the registry")
    r = run("director send", ["one-page-brief", "x"], as: D3, name: "director-dirproj")
    check(!r.ok && DirectorRegistry.load(project: proj).current?.sessionId == D, "nor does send")
    r = run("director start", ["--take-over"], as: D3, name: "director-dirproj")
    check(r.ok && DirectorRegistry.load(project: proj).current?.sessionId == D3 && DirectorRegistry.load(project: proj).retired.isEmpty,
          "start --take-over alone records a resumed director (same name, new id), retiring nobody")

    // Take-over by another director, and the replaced one standing down.
    r = run("director start", ["--title", "Mine now", "--request", "x", "--suggest", "--take-over"], as: D2, name: "director-new")
    check(r.ok && DirectorRegistry.load(project: proj).current?.name == "director-new" && DirectorRegistry.load(project: proj).retired.last?.name == "director-dirproj", "--take-over replaces the director")
    r = run("director send", ["one-page-brief", "x"], as: D3, name: "director-dirproj")
    check(!r.ok && r.output.contains("replaced") && r.output.contains("director-new"), "the replaced director is told to stand down, and by whom")
    r = run("director status", ["--json"], as: D3, name: "director-dirproj")
    check(((try? JSONSerialization.jsonObject(with: Data(r.output.utf8))) as? [String: Any])?["role"] as? String == "replaced", "status says so too")
    r = run("director send", ["one-page-brief", "x"], as: D2, name: "director-new")
    check(!r.ok && r.output.contains("directed by director-dirproj"), "the new director can't task the old one's workers until their tasks name it")
    r = run("director retire", [], as: D2, name: "director-new")
    check(r.ok && DirectorRegistry.load(project: proj).current == nil, "retire")

    let metrics = DirectorLog.metrics(DirectorLog.read(project: proj))
    check(metrics.starts >= 3 && metrics.takeovers >= 1 && (metrics.sends["duo-submit"] ?? 0) >= 1 && (metrics.sends["queued"] ?? 0) >= 1 && metrics.refusals >= 3,
          "the log has every step (\(metrics))")
}
