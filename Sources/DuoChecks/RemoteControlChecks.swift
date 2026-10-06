import DuoControl
import DuoKit
import Foundation

// `duo2 session new --remote-control [name]` (DL-128, F-127), end to end with stand-in claudes that
// record their arguments: never a real claude, never a real Remote Control session.
@MainActor func remoteControlChecks() throws {
    print("Remote Control: session new --remote-control, the version gate, kept on resume (DL-128)")
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-rc-\(UUID().uuidString.prefix(8))")
    let support = root.appending(path: "s"), config = root.appending(path: "c"), proj = root.appending(path: "p")
    let log = root.appending(path: "claude.log")
    for d in [support, config, proj] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    try Data("# rc\n".utf8).write(to: proj.appending(path: "PROJECT.md"))

    // A stand-in that answers --version and --help as `version` and `help`, and otherwise logs its
    // arguments, writes an idle beacon and waits.
    func standIn(_ name: String, version: String, help: String) throws -> String {
        let url = root.appending(path: name)
        let script = """
        #!/usr/bin/python3
        import os, sys, json
        a = sys.argv[1:]
        if a == ["--version"]: print("\(version) (Claude Code)"); sys.exit(0)
        if a == ["--help"]: print(\(String(reflecting: help))); sys.exit(0)
        open("\(log.path)", "a").write("ARGS " + json.dumps(a) + "\\n")
        sid = a[a.index("--session-id") + 1] if "--session-id" in a else a[a.index("--resume") + 1]
        d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "sessions"); os.makedirs(d, exist_ok=True)
        json.dump({"pid": os.getpid(), "sessionId": sid, "cwd": os.getcwd(), "status": "idle"}, open(os.path.join(d, "%d.json" % os.getpid()), "w"))
        while os.read(0, 4096): pass
        """
        try Data(script.utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
    let current = try standIn("claude-new", version: "2.1.292",
                              help: "Options:\n  --remote-control [name]   Start an interactive session with Remote Control enabled (optionally named)\n")
    let old = try standIn("claude-old", version: "2.1.100", help: "Options:\n  --resume [value]   Resume a conversation\n")

    let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    setenv("CLAUDE_CONFIG_DIR", config.path, 1)
    var models: [AppModel] = []
    defer {
        for m in models { for s in m.fixture.sessions { m.terminals.existing(s.tabKey)?.terminate() } }
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        ClaudeLocator.forget()
        try? fm.removeItem(at: root)
    }
    func use(_ claude: String) {
        DuoState.update { $0.claudePath = claude }
        ClaudeLocator.forget()
    }

    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "rcproj", "topic": "Platform", "path": proj.path, "goal": "g"])))
    func model(_ fixture: Fixture) -> AppModel {
        let m = AppModel(fixture: fixture)
        m.terminalsMode = .live
        m.liveFolders["rcproj"] = proj
        m.open(project: "rcproj")
        models.append(m)
        return m
    }
    let m = model(fx)
    func duo2(_ m: AppModel, _ args: String...) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()), cwd: proj.path)) { out = $0 }
        let until = Date().addingTimeInterval(10)
        while out == nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return out ?? ControlResponse(ok: false, output: "timed out")
    }
    func json(_ r: ControlResponse) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(r.output.utf8))) as? [String: Any] ?? [:]
    }
    // The arguments the stand-in was started with for a session, waiting for it to log them.
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
    func remote(_ args: [String]) -> String? {
        args.firstIndex(of: "--remote-control").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }
    func indexed(_ id: String) -> SessionIndex.Entry? { SessionIndex.load(project: proj).sessions.first { $0.sessionId == id } }

    // The flag parses with a name, without one, and before another flag.
    check(Invocation(["--remote-control"]).flags["remote-control"] == "" && Invocation(["--remote-control", "phone"]).flags["remote-control"] == "phone"
          && Invocation(["--remote-control", "--prompt", "hi"]).flags == ["remote-control": "", "prompt": "hi"],
          "--remote-control takes an optional name, and never swallows the next flag")

    use(current)
    check(RemoteControl.supported(current) && !RemoteControl.supported(old), "the gate: a claude whose --help lists --remote-control takes it; one without doesn't")

    // Present, default name.
    let r1 = duo2(m, "session", "new", "--remote-control", "--json")
    let j1 = json(r1), id1 = j1["id"] as? String ?? ""
    let want1 = "rcproj \(id1.prefix(8))"
    let a1 = argsFor(id1)
    check(r1.ok && j1["remoteControl"] as? String == want1, "session new --remote-control names it by project and short id (\(j1["remoteControl"] ?? "none"))")
    check(remote(a1) == want1 && a1.contains("--session-id"), "claude is started with --remote-control \"\(want1)\" (\(a1.filter { !$0.hasPrefix("Duo") && $0.count < 80 }))")
    check(indexed(id1)?.remoteControl == want1, "the session index remembers it")

    // Present, named, with a prompt after it.
    let r2 = duo2(m, "session", "new", "--remote-control", "Geoff's phone", "--prompt", "hello")
    let id2 = String(r2.output.split(separator: " ").dropFirst(2).first ?? "")
    let a2 = argsFor(id2)
    check(r2.output.contains("Remote Control is on as \"Geoff's phone\"") && remote(a2) == "Geoff's phone" && a2.last == "hello",
          "a name is passed as given, and the prompt still goes last (\(r2.output))")
    let r2b = duo2(m, "session", "new", "--remote-control", "--prompt", "hi", "--json")
    let id2b = json(r2b)["id"] as? String ?? ""
    let a2b = argsFor(id2b)
    check(remote(a2b) == "rcproj \(id2b.prefix(8))" && a2b.last == "hi", "--remote-control before --prompt: the default name, and the prompt kept")

    // Absent.
    let r3 = duo2(m, "session", "new", "--json")
    let id3 = json(r3)["id"] as? String ?? ""
    let a3 = argsFor(id3)
    check(!a3.isEmpty && !a3.contains("--remote-control") && indexed(id3)?.remoteControl == nil, "without the flag, claude gets no --remote-control and nothing is remembered")

    // Reported by session show and sessions --json.
    let list = (try? JSONSerialization.jsonObject(with: Data(duo2(m, "sessions", "--project", "rcproj", "--json").output.utf8))) as? [[String: Any]] ?? []
    let byId = Dictionary(list.compactMap { s in (s["id"] as? String).map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
    check(byId[id1]?["remoteControl"] as? String == want1 && byId[id3]?["remoteControl"] is NSNull, "sessions --json: the name for a Remote Control session, null for the others")
    check(duo2(m, "session", "show", id1).output.contains("Remote Control: on, as \"\(want1)\"") && duo2(m, "session", "show", id3).output.contains("Remote Control: off"),
          "session show says whether it was started with Remote Control")
    check(json(duo2(m, "session", "show", id1, "--json"))["remoteControl"] as? String == want1, "session show --json carries the name")

    // Kept on resume: close it, give it a transcript so it resumes rather than restarts, and reopen
    // it in a fresh model (a Duo restart restoring it, LR-58) whose session list doesn't carry the name.
    m.closeSession(id1)
    let until = Date().addingTimeInterval(5)
    while m.terminals.existing(id1) != nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let bucket = config.appending(path: "projects").appending(path: ClaudeStorage.encode(proj.resolvingSymlinksInPath().path))
    try fm.createDirectory(at: bucket, withIntermediateDirectories: true)
    try Data("{\"type\":\"user\",\"cwd\":\"\(proj.resolvingSymlinksInPath().path)\",\"sessionId\":\"\(id1)\"}\n".utf8).write(to: bucket.appending(path: id1 + ".jsonl"))
    var fx2 = fx
    fx2.sessions.append(try JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: ["name": "Restored", "project": "rcproj", "state": "idle", "sessionId": id1])))
    let m2 = model(fx2)
    let t = m2.terminal(project: "rcproj", session: id1)
    let a4 = argsFor(id1)
    check(t != nil && a4.contains("--resume") && remote(a4) == want1, "a resume after a restart passes --remote-control \"\(want1)\" again (\(a4.contains("--resume") ? "resumed" : "not resumed"))")
    // duo2 session open resumes the same way (it shows the tab; the console asks for the terminal).
    m2.closeSession(id1)
    let until2 = Date().addingTimeInterval(5)
    while m2.terminals.existing(id1) != nil, Date() < until2 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    check(duo2(m2, "session", "open", id1).ok && m2.terminal(project: "rcproj", session: id1) != nil && remote(argsFor(id1)) == want1, "session open keeps Remote Control on too")
    m.closeSession(id3)
    let until3 = Date().addingTimeInterval(5)
    while m.terminals.existing(id3) != nil, Date() < until3 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let a3resume = m.terminal(project: "rcproj", session: id3) != nil ? argsFor(id3) : []
    check(!a3resume.isEmpty && !a3resume.contains("--remote-control"), "a session started without it starts again without it")

    // The gate on an old claude: starts without, and says so.
    use(old)
    let r5 = duo2(m, "session", "new", "--remote-control", "--json")
    let j5 = json(r5), id5 = j5["id"] as? String ?? ""
    let a5 = argsFor(id5)
    check(r5.ok && !a5.isEmpty && !a5.contains("--remote-control"), "an old claude: the session starts without --remote-control")
    check((j5["remoteControlUnavailable"] as? String)?.contains("Claude Code 2.1.100 doesn't take --remote-control") == true && j5["remoteControl"] == nil,
          "and the reply says so (\(j5["remoteControlUnavailable"] ?? "nothing"))")
    check(indexed(id5)?.remoteControl == nil, "nothing is remembered for it")
    let r5text = duo2(m, "session", "new", "--remote-control")
    check(r5text.output.contains("started without Remote Control"), "the plain reply says so too")
}
