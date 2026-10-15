import DuoControl
import DuoSearch
import Foundation

// The parts of `duo2 director` that run in the director's own process (DL-193, DL-199): what this
// client can do (only readable from the caller's side), `guide` and `watch`.

/// What the calling session can do, as JSON for the app (`--caps`).
func directorCaps() -> String {
    let caps = ClientCaps.probe(env: ProcessInfo.processInfo.environment, cwd: FileManager.default.currentDirectoryPath)
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    return (try? enc.encode(caps)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
}

/// `duo2 director status` when Duo isn't running: what can be known without it. The project and
/// Home come from the folder alone (`DirectorPlace`), the same rule the app uses first.
func directorStatusOffline() -> Int32 {
    let env = ProcessInfo.processInfo.environment
    let caps = ClientCaps.probe(env: env, cwd: FileManager.default.currentDirectoryPath)
    print("Duo isn't running, so workers' states and the task board are unknown (start Duo, or ask the user).")
    let (project, above) = DirectorPlace.resolve(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let home = above ?? DirectorPlace.configuredHome()   // a project outside Home: the Home Duo was given
    let reg = DirectorRegistry.load(project: project)
    print("Project: \(project.lastPathComponent) (\(project.path)). Director: \(reg.current.map { "\($0.name) (\($0.sessionId.prefix(8)))" } ?? "none").")
    print(home.map { "Home: \($0.path)\(above == nil ? " (Duo's Home; this project is outside it)" : "")." } ?? "No Home: no HOME.md above this folder, and Duo has none set.")
    // In Home: the projects inside it that have their own director (DL-197), two levels down.
    if let home, home.path == project.path {
        let fm = FileManager.default
        let kids = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
        let folders = kids + kids.filter { !ProtectedFolders.paths.contains($0.standardizedFileURL.path) }.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] }
        let directed = folders.compactMap { f in DirectorRegistry.load(project: f).current.map { "\(f.path.dropFirst(home.path.count + 1)) (\($0.name))" } }.sorted()
        print(directed.isEmpty ? "No project here has its own director." : "Projects with their own director (ask it, never touch its workers): " + directed.joined(separator: ", "))
    }
    print("Rules (the project's win where they disagree):")
    for s in DirectorRules.sources(project: project, home: home) { print("  - " + s.line) }
    if home == nil { print("  - No Home: rules for every director live in Home's HOME.md. Offer to set one up (`duo2 home set <folder>`), or keep a rule in this project (DL-207).") }
    print("This client:")
    for l in caps.lines { print("  " + l) }
    return 0
}

/// `duo2 director start <task> --background` with Duo closed: the one start that needs no Duo. It
/// records the worker as pending in `.duo/director.json` under the name it prints, and Duo links it
/// by that name when it next runs, so a worker started by hand never becomes "the user's". The task
/// note is the director's to have written; its Progress line too.
func directorStartOffline(_ rest: [String]) -> Int32 {
    func no(_ why: String) -> Int32 { FileHandle.standardError.write(Data("duo2: \(why)\n".utf8)); return 1 }
    let inv = Invocation(rest)
    let env = ProcessInfo.processInfo.environment
    guard inv.has("background"), inv.flags["title"] == nil, let t = inv[0] else {
        return no("Duo isn't running. With Duo closed only `duo2 director start <task> --background` works, for a task note you've written; start Duo for the rest.")
    }
    guard let me = env["CLAUDE_CODE_SESSION_ID"] else { return no("not run from a Claude session (no session id), so there's no director to record") }
    let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let caps = ClientCaps.probe(env: env, cwd: here.path)
    let (project, _) = DirectorPlace.resolve(from: here)
    let path = t.hasPrefix("tasks/") ? (t.hasSuffix(".md") ? t : t + ".md") : "tasks/" + (t.hasSuffix(".md") ? t : t + ".md")
    guard DirectorRegistry.isTaskPath(path), let text = try? String(contentsOf: project.appending(path: path), encoding: .utf8) else {
        return no("no task note \(path) in \(project.path): write it first (## Request, done_when:, directed_by:, ## Progress)")
    }
    var reg = DirectorRegistry.load(project: project)
    let role = reg.role(sessionId: me)
    if case .replaced(let by) = role { return no("You were replaced as this project's director\(by.map { " by \($0.name)" } ?? ""). Stand down: say so to the user and stop directing.") }
    if case .other(let c) = role, !inv.has("take-over") { return no("this project is directed by \(c.name). Ask the user; with their go-ahead, --take-over replaces it.") }
    let name = (role == .current ? reg.current?.name : nil) ?? (caps.name?.hasPrefix("director-") == true ? caps.name! : Director.name(project: project.lastPathComponent))
    guard let by = Director.frontmatter("directed_by", in: text) else {
        return no("\(path) has no directed_by:, so it's the user's (DL-200). With Duo running, --adopt asks them.")
    }
    guard by == name else { return no("\(path) is directed by \(by), not you: never task another director's worker (DL-200).") }
    // The cap (DL-201): running workers and pending ones on unfinished tasks.
    let brief = (try? String(contentsOf: project.appending(path: "PROJECT.md"), encoding: .utf8)) ?? ""
    let cap = Director.cap(directorSection: Director.section("Director", in: brief))
    let live = liveSessionIds()
    let iso = ISO8601DateFormatter()
    let busy = reg.workers.filter { w in
        guard w.task != path, let note = try? String(contentsOf: project.appending(path: w.task), encoding: .utf8),
              Director.holdsSlot(status: Director.frontmatter("status", in: note), archived: Director.frontmatter("archived", in: note) == "true") else { return false }
        if w.pending { return iso.date(from: w.since).map { Date().timeIntervalSince($0) <= Director.pendingLasts } ?? false }
        return live.contains(w.session)
    }
    guard busy.count < cap else { return no("You have \(busy.count) of \(cap) workers running (\(busy.map(\.task).joined(separator: ", "))). Mark \(path) status: suggested and start it when one finishes.") }
    let now = iso.string(from: Date())
    if role != .current { reg.adopt(name: name, sessionId: me, at: now) }
    let (worker, cmd) = Director.backgroundStart(folder: project, task: path, director: name)
    reg.setWorker(task: path, session: "", at: now, adopted: false, name: worker)
    do { try reg.save(project: project) } catch { return no("couldn't write \(DirectorRegistry.file(project: project).path): \(error.localizedDescription)") }
    DirectorLog.append(DirectorEvent(at: now, director: name, event: "start", task: path, detail: "background, Duo closed, as \(worker)"), project: project)
    print("Duo isn't running: add the Progress line to \(path) yourself (\"Worker \(worker) to start in the background\"). Run this; Duo links the worker by its name, \(worker), when it next runs:\n  \(cmd)")
    return 0
}

/// Session ids of Claude processes running now, from their session files.
func liveSessionIds() -> Set<String> {
    let dir = LegacyDuo.claudeDir.appending(path: "sessions")
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return Set(files.filter { $0.pathExtension == "json" }.compactMap { url -> String? in
        guard let j = (try? Data(contentsOf: url)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
              let pid = j["pid"] as? Int, kill(pid_t(pid), 0) == 0 else { return nil }
        return j["sessionId"] as? String
    })
}

/// `duo2 director watch`: polls Duo for this director's workers and prints one line per change,
/// for Monitor (each line wakes the director, F-310). Runs until killed.
func runDirectorWatch(_ rest: [String]) -> Int32 {
    let inv = Invocation(rest)
    let every = max(1, Double(inv.flags["every"] ?? "5") ?? 5)
    let env = ProcessInfo.processInfo.environment
    var last: [String: String] = [:]
    var first = true
    var away = false
    setvbuf(stdout, nil, _IOLBF, 0)
    while true {
        var args = ["--json", "--caps", directorCaps()]
        if let p = inv.flags["project"] { args += ["--project", p] }
        if let (endpoint, source) = ControlEndpoint.discover(),
           let r = try? ControlClient.send(ControlRequest(token: endpoint.token, command: "director status", args: args,
                                                          session: env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"],
                                                          cwd: FileManager.default.currentDirectoryPath), via: endpoint, source: source, timeout: 15),
           r.ok, let data = r.output.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if away { print("Duo is back."); away = false }
            if let role = j["role"] as? String, role == "replaced" {
                print("You were replaced as this project's director\((j["replacedBy"] as? String).map { " by \($0)" } ?? ""): stand down.")
            }
            let workers = (j["workers"] as? [[String: Any]]) ?? []
            var now: [String: String] = [:]
            for w in workers {
                let task = w["task"] as? String ?? "?"
                let sig = "\(w["state"] as? String ?? "?")|\(w["noteModified"] as? Double ?? 0)|\(w["userTyping"] as? Bool ?? false)"
                now[task] = sig
                guard !first, let was = last[task] else { continue }
                if was != sig { print(watchLine(w, was: was)) }
            }
            if !first { for (task, _) in last where now[task] == nil { print("\(task): no longer yours (done, archived or handed over).") } }
            last = now
            first = false
        } else if !away {
            print("Duo isn't reachable: watching resumes when it is.")
            away = true
        }
        Thread.sleep(forTimeInterval: every)
    }
}

func watchLine(_ w: [String: Any], was: String) -> String {
    let task = w["task"] as? String ?? "?"
    let title = w["title"] as? String ?? task
    let state = w["state"] as? String ?? "?"
    let parts = was.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let prior = parts.first ?? ""
    if (w["userTyping"] as? Bool ?? false), parts.count > 2, parts[2] != "true" {
        return "\(title) (\(task)): the user typed in its worker, so you're paused there (DL-200). Don't stop or archive it; ask them before sending."
    }
    if prior != state {
        switch state {
        case "idle", "review": return "\(title) (\(task)): its worker finished a turn. Read its report: duo2 session show \(w["session"] as? String ?? "")"
        case "needs-you": return "\(title) (\(task)): its worker needs the user\((w["question"] as? String).map { ": \($0)" } ?? "")."
        case "working": return "\(title) (\(task)): its worker is working."
        case "stopped": return "\(title) (\(task)): its worker stopped."
        default: return "\(title) (\(task)): its worker is \(state)."
        }
    }
    return "\(title) (\(task)): its task note changed."
}
