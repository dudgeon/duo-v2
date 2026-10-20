import DuoControl
import DuoKit
import Foundation

// Make a Project's interview (DL-223), end to end with a stand-in claude that records its arguments:
// the starter PROJECT.md is written first, then a session starts with the interview as its first
// message, from the buttons, New Project's "Start a Claude session in it" and duo2. Never a real claude.
@MainActor func projectInterviewChecks() throws {
    print("Make a Project interviews you (DL-223)")
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-pi-\(UUID().uuidString.prefix(8))")
    let support = root.appending(path: "s"), config = root.appending(path: "c"), home = root.appending(path: "h")
    let log = root.appending(path: "claude.log")
    for d in [support, config, home] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
    for d in ["Reading", "Garden", "Quiet", "Notes"] { try fm.createDirectory(at: home.appending(path: d), withIntermediateDirectories: true) }

    // Logs its arguments, writes an idle beacon and waits.
    let claude = root.appending(path: "claude")
    try Data("""
    #!/usr/bin/python3
    import os, sys, json
    a = sys.argv[1:]
    if a == ["--version"]: print("2.1.292 (Claude Code)"); sys.exit(0)
    if a == ["--help"]: print("Options:"); sys.exit(0)
    open("\(log.path)", "a").write("ARGS " + json.dumps(a) + "\\n")
    sid = a[a.index("--session-id") + 1]
    d = os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "sessions"); os.makedirs(d, exist_ok=True)
    json.dump({"pid": os.getpid(), "sessionId": sid, "cwd": os.getcwd(), "status": "idle"}, open(os.path.join(d, "%d.json" % os.getpid()), "w"))
    while os.read(0, 4096): pass
    """.utf8).write(to: claude)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

    let saved = ["DUO_SUPPORT_DIR", "CLAUDE_CONFIG_DIR"].map { k in (k, ProcessInfo.processInfo.environment[k]) }
    setenv("DUO_SUPPORT_DIR", support.path, 1)
    setenv("CLAUDE_CONFIG_DIR", config.path, 1)
    DuoState.update { $0.claudePath = claude.path }
    ClaudeLocator.forget()
    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "Quiet", "kind": "folder", "goal": "", "topic": "", "path": home.appending(path: "Quiet").path])))
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "Notes", "kind": "folder", "goal": "", "topic": "", "path": home.appending(path: "Notes").path])))
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveRoot = home
    var undos: [String] = []
    m.undoRecorder = { name, _ in undos.append(name) }
    for d in ["Reading", "Garden", "Quiet", "Notes"] { m.liveFolders[d] = home.appending(path: d) }
    defer {
        for s in m.fixture.sessions { m.terminals.existing(s.tabKey)?.terminate() }
        for (k, v) in saved { if let v { setenv(k, v, 1) } else { unsetenv(k) } }
        ClaudeLocator.forget()
        try? fm.removeItem(at: root)
    }
    func duo2(_ args: String...) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()), cwd: home.path)) { out = $0 }
        let until = Date().addingTimeInterval(10)
        while out == nil, Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return out ?? ControlResponse(ok: false, output: "timed out")
    }
    func argsFor(_ id: String) -> [String] {
        let until = Date().addingTimeInterval(10)
        while Date() < until {
            let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n")
            if let l = lines.first(where: { $0.contains(id) }) {
                return (try? JSONSerialization.jsonObject(with: Data(l.dropFirst(5).utf8))) as? [String] ?? []
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return []
    }
    func file(_ folder: String) -> String { (try? String(contentsOf: home.appending(path: "\(folder)/PROJECT.md"), encoding: .utf8)) ?? "" }
    func indexed(_ folder: String, _ id: String) -> Bool { SessionIndex.load(project: home.appending(path: folder)).sessions.contains { $0.sessionId == id } }

    // The message: the whole instruction, in the open.
    let p = ProjectInterview.prompt(title: "Reading list")
    check(p.contains("Reading list") && p.contains("PROJECT.md") && !p.hasPrefix("-"), "the first message names the project and its PROJECT.md, and can't be read as a flag")
    check(["Look around this folder", "three to five", "one at a time", "`goal`", "`next`", "Why", "Done when", "checkboxes", "Log"].allSatisfy(p.contains),
          "it asks Claude to look first, ask a few questions one at a time, and fill goal, next, Why, Done when and a Log line")
    check(p.contains("leave `status`, `health`") && p.contains("don't change any other file") && p.contains("valid YAML"),
          "it leaves status, health and every other file alone, and keeps the properties Obsidian-readable")

    // A button: the template first, then the session with the interview as its first message.
    m.lastInterview = nil
    check(m.makeProject(folder: home.appending(path: "Reading"), title: "Reading list") == nil && undos == ["Make Project"], "Make a Project succeeds, as one undo step")
    let id1 = m.lastInterview ?? ""
    let a1 = argsFor(id1)
    check(file("Reading").contains("type: project") && file("Reading").contains("Reading list"), "PROJECT.md is the template, written before Claude starts (so it's a project at once and Undo works)")
    check(!id1.isEmpty && a1.contains("--session-id") && a1.last == ProjectInterview.prompt(title: "Reading list"),
          "a session starts in the folder with the interview sent as its first message (\(a1.last?.prefix(40) ?? "none"))")
    check(indexed("Reading", id1), "the interview session is in the project's session index")
    check(!a1.contains("--model") && a1.filter { $0 == "--append-system-prompt" }.count == 1,
          "Duo chooses no model, and adds no hidden instruction beyond its usual primer")

    // New Project's "Make this folder the project" with Start a Claude session off: no interview.
    m.lastInterview = "stale"
    check(m.makeProject(folder: home.appending(path: "Garden"), interview: false) == nil && m.lastInterview == nil && file("Garden").contains("type: project"),
          "with the session off, the file is written and no session starts")

    // duo2 project make: interviews by default, --json gives the session; --no-interview doesn't.
    let r = duo2("project", "make", "Quiet", "--json")
    let j = (try? JSONSerialization.jsonObject(with: Data(r.output.utf8))) as? [String: Any] ?? [:]
    let id2 = j["session"] as? String ?? ""
    check(r.ok && !id2.isEmpty && argsFor(id2).last == ProjectInterview.prompt(title: "Quiet"), "duo2 project make starts the interview and names its session (\(r.output.prefix(80)))")
    let r2 = duo2("project", "make", "Notes", "--no-interview")
    check(r2.ok && !r2.output.contains("interviewing") && m.lastInterview == nil && file("Notes").contains("type: project"),
          "duo2 project make --no-interview writes the file without a session (\(r2.output.prefix(80)))")

    // New Project (a new folder) with Start a Claude session in it.
    m.lastInterview = nil
    check(m.createProject(named: "Atlas", moving: [], startSession: true) == nil, "New Project succeeds")
    let id3 = m.lastInterview ?? ""
    check(!id3.isEmpty && argsFor(id3).last == ProjectInterview.prompt(title: "Atlas") && file("Atlas").contains("type: project"),
          "New Project's Start a Claude session in it is the interview, after the template")
}
