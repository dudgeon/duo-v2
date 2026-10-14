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

/// `duo2 director status` when Duo isn't running: what can be known without it.
func directorStatusOffline() -> Int32 {
    let env = ProcessInfo.processInfo.environment
    let caps = ClientCaps.probe(env: env, cwd: FileManager.default.currentDirectoryPath)
    print("Duo isn't running, so workers' states and the task board are unknown (start Duo, or ask the user).")
    let project = nearestProject(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    if let project {
        let reg = DirectorRegistry.load(project: project)
        print("Project: \(project.lastPathComponent). Director: \(reg.current.map { "\($0.name) (\($0.sessionId.prefix(8)))" } ?? "none").")
        // In Home: the projects inside it that have their own director (DL-197), two levels down.
        if FileManager.default.fileExists(atPath: project.appending(path: "HOME.md").path) {
            let fm = FileManager.default
            let kids = ((try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            let folders = kids + kids.filter { !ProtectedFolders.paths.contains($0.standardizedFileURL.path) }.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] }
            let directed = folders.compactMap { f in DirectorRegistry.load(project: f).current.map { "\(f.path.dropFirst(project.path.count + 1)) (\($0.name))" } }.sorted()
            print(directed.isEmpty ? "No project here has its own director." : "Projects with their own director (ask it, never touch its workers): " + directed.joined(separator: ", "))
        }
    }
    print("Rules:")
    print("  - your rules for every director: Home's HOME.md (## Director); Duo names Home when it runs")
    for s in DirectorRules.sources(project: project, home: nil) {
        print("  - \(s.label): \(s.path) (## \(s.section))\(s.exists ? "" : " (none yet)")")
    }
    print("This client:")
    for l in caps.lines { print("  " + l) }
    return 0
}

/// The project folder holding `dir`: the nearest ancestor with a PROJECT.md, else `dir` itself.
func nearestProject(from dir: URL) -> URL? {
    var d = dir.standardizedFileURL
    while d.path != "/" {
        if FileManager.default.fileExists(atPath: d.appending(path: "PROJECT.md").path) { return d }
        d = d.deletingLastPathComponent()
    }
    return dir
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
                let sig = "\(w["state"] as? String ?? "?")|\(w["noteModified"] as? Double ?? 0)"
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
    let prior = String(was.split(separator: "|").first ?? "")
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
