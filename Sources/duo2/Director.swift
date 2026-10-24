import DuoControl
import DuoSearch
import Foundation

// The parts of `duo2 director` that run in the director's own process (DL-193, DL-199): what this
// client can do (only readable from the caller's side), `guide` and `watch`, and every verb with
// Duo closed (DL-231): directing needs Claude's beacons, the registry and the task notes, not Duo.

/// What the calling session can do, as JSON for the app (`--caps`).
/// `login` also asks `claude auth status` (status and start only: `watch` asks every few seconds).
func directorCaps(login: Bool = false) -> String {
    var caps = ClientCaps.probe(env: ProcessInfo.processInfo.environment, cwd: FileManager.default.currentDirectoryPath)
    if login { caps.cliLogin = ClientCaps.cliLogin(env: ProcessInfo.processInfo.environment) }
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    return (try? enc.encode(caps)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
}

// MARK: - With Duo closed (DL-231)

/// The verb's answer when the app can't be reached, or nil for a verb that needs it.
func runOffline(_ id: ActionID, _ rest: [String]) -> Int32? {
    switch id {
    case .directorStatus: return directorStatusOffline(rest)
    case .directorStart: return directorStartOffline(rest)
    case .directorSend: return directorSendOffline(rest)
    case .directorRetire: return directorRetireOffline(rest)
    case .sessionShow: return sessionShowOffline(rest)
    default: return nil
    }
}

func offlineFail(_ why: String) -> Int32 { FileHandle.standardError.write(Data("duo2: \(why)\n".utf8)); return 1 }

func isoNow(_ d: Date = Date()) -> String {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = .current
    return f.string(from: d)
}

struct OfflineFailure: Error { var why: String }

/// Where a director stands with Duo closed: the project and Home from the folder, the registry
/// (pending background workers linked first), the caller's role and its beacon-read facts.
struct OfflineDirector {
    var caps: ClientCaps
    var me: String?
    var project: URL
    /// Home above the project, if any.
    var above: URL?
    /// Home: the one above, else the one Duo was given (a project outside it).
    var home: URL?
    var reg: DirectorRegistry
    var role: DirectorRegistry.Role
    /// This director's name: the registry's when it's current, else its own (`claude -n`), else the fixed one.
    var name: String
    var beacons: [DirectorOffline.LiveSession] = []

    init(_ inv: Invocation, login: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        let cwd = FileManager.default.currentDirectoryPath
        if let s = inv.flags["caps"], let c = try? JSONDecoder().decode(ClientCaps.self, from: Data(s.utf8)) { caps = c }
        else {
            caps = ClientCaps.probe(env: env, cwd: cwd)
            if login { caps.cliLogin = ClientCaps.cliLogin(env: env) }
        }
        me = env["CLAUDE_CODE_SESSION_ID"] ?? caps.sessionId
        var from = URL(fileURLWithPath: cwd)
        if let p = inv.flags["project"] {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else {
                throw OfflineFailure(why: "--project \(p) needs Duo, which knows projects by name. With Duo closed, run it from the project's folder (or pass the folder).")
            }
            from = URL(fileURLWithPath: p)
        }
        let (project, above) = DirectorPlace.resolve(from: from)
        self.project = project; self.above = above
        home = above ?? DirectorPlace.configuredHome()
        reg = DirectorRegistry.load(project: project)
        role = reg.role(sessionId: me)
        name = (role == .current ? reg.current?.name : nil) ?? (caps.name?.hasPrefix("director-") == true ? caps.name! : Director.name(project: project.lastPathComponent))
        refresh()
    }

    var projectName: String { project.lastPathComponent }

    /// Reads the beacons and links pending background workers whose session has appeared, noting each in its task.
    mutating func refresh() {
        beacons = DirectorOffline.beacons()
        let linked = DirectorOffline.linkPending(&reg, beacons: beacons)
        guard !linked.isEmpty else { return }
        try? reg.save(project: project)
        for w in linked { progress(w.task, "Worker \(w.session.prefix(8)) (\(w.name ?? "")) started in the background.") }
    }

    func log(_ event: String, task: String? = nil, worker: String? = nil, rung: String? = nil, _ detail: String? = nil) {
        DirectorLog.append(DirectorEvent(at: isoNow(), director: name, event: event, task: task, worker: worker, rung: rung, detail: detail), project: project)
    }

    /// A Progress line in a task's note (Duo isn't there to write it).
    func progress(_ task: String, _ line: String) {
        guard DirectorRegistry.isTaskPath(task) else { return }
        let url = project.appending(path: task)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? Data(DirectorOffline.appendProgress(text, line).utf8).write(to: url, options: .atomic)
    }

    func tasks() -> [DirectorOffline.Task] {
        DirectorOffline.tasks(project: project, director: reg.current?.name ?? name, reg: reg, beacons: beacons)
    }

    /// The refusal for a director that was replaced: stand down.
    func standDown() -> String? {
        guard case .replaced(let by) = role else { return nil }
        log("standdown", by.map { "replaced by \($0.name)" })
        return "You were replaced as \(projectName)'s director\(by.map { " by \($0.name) (since \($0.since))" } ?? ""). Stand down: say so to the user and stop directing."
    }

    /// A task by path, file name, title or a unique start of one.
    func findTask(_ t: String) -> (path: String, title: String)? {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: project.appending(path: "tasks").path)) ?? []).filter { $0.lowercased().hasSuffix(".md") }.sorted()
        var want = t.hasPrefix("tasks/") ? String(t.dropFirst(6)) : t
        if want.lowercased().hasSuffix(".md") { want = String(want.dropLast(3)) }
        let entries = files.map { f -> (stem: String, title: String) in
            let stem = String(f.dropLast(3))
            let text = (try? String(contentsOf: project.appending(path: "tasks/\(f)"), encoding: .utf8)) ?? ""
            return (stem, DirectorOffline.title(of: text, stem: stem))
        }
        let hit = entries.first { $0.stem == want } ?? entries.first { $0.title.lowercased() == want.lowercased() }
            ?? { let m = entries.filter { $0.stem.hasPrefix(want.lowercased()) }; return m.count == 1 ? m[0] : nil }()
        return hit.map { ("tasks/\($0.stem).md", $0.title) }
    }
}

/// `duo2 director status` with Duo closed: the same report the app gives, read from the registry,
/// the beacons and the task notes.
func directorStatusOffline(_ rest: [String]) -> Int32 {
    let inv = Invocation(rest)
    let d: OfflineDirector
    do { d = try OfflineDirector(inv, login: true) } catch let e as OfflineFailure { return offlineFail(e.why) } catch { return offlineFail("\(error)") }
    let p = d.projectName
    print("Duo isn't running. Directing doesn't need it; Duo only carries messages where sessions can't message each other (DL-231).")
    print("Project: \(p) (\(d.project.path)).")
    let installed = (try? String(contentsOf: Installer.directorSkillFile, encoding: .utf8)) ?? (try? String(contentsOf: Installer.directorAliasFile, encoding: .utf8))
    if let note = DirectorSkill.versionNote(installed: installed) { print(note) }
    switch d.role {
    case .current: print("You're \(p)'s director, \(d.name).")
    case .replaced(let by): print("You were replaced as \(p)'s director\(by.map { " by \($0.name)" } ?? ""): stand down, say so, and stop.")
    case .other(let c):
        print(c.name == d.caps.name
            ? "\(p)'s director is named \(c.name), like you, but runs as session \(c.sessionId.prefix(8)). If you are that director, resumed with a new id, `duo2 director start --take-over` records you; otherwise another session has your name: ask the user."
            : "\(p) is directed by \(c.name) (session \(c.sessionId.prefix(8)), since \(c.since)), not you. Ask the user before taking over (`duo2 director start --take-over`).")
    case .none:
        print("Nobody directs \(p) yet. `duo2 director start` makes you its director, as \(d.name)\(d.caps.name == d.name ? "" : " (start as `claude -n \(d.name)` so the name survives restarts)").")
    }
    if d.caps.projects { print("This is a Claude Code Projects session: start nothing here (DL-203).") }
    let home = d.home
    // In Home: the projects inside it that have their own director (DL-197), two levels down.
    let inHome = home.map { $0.path == d.project.path } ?? false
    print(home.map { "Home: \($0.path)\(d.above == nil ? " (Duo's Home; this project is outside it)" : "")." } ?? "No Home: no HOME.md above this folder, and Duo has none set.")
    if let home, inHome {
        let directed = projectDirectors(in: home)
        print(directed.isEmpty ? "No project here has its own director: you may direct work in any of them." : "Projects with their own director (ask it, never touch its workers): " + directed.map { "\($0.0) (\($0.1))" }.joined(separator: ", "))
    }
    let tasks = d.tasks()
    print("Workers: \(tasks.filter(\.running).count) running.")
    for t in tasks {
        var l = "  \(t.path)  \(t.title) (\(t.status ?? "open"))  "
        if let s = t.session {
            l += "\(t.state), \(t.place), session \(s.prefix(8))"
            if let q = t.question { l += ": \(q)" }
            if t.userTyping { l += " · the user took it over (typed there since your last message): you're paused there until they hand it back" }
        } else if let n = t.pendingName { l += "starting in the background as \(n)" }
        else { l += "no worker" }
        print(l)
    }
    if !d.reg.pending.isEmpty { print("Waiting to be delivered: " + d.reg.pending.map { "\($0.task) (since \($0.at))" }.joined(separator: ", ")) }
    print("Rules (the project's win where they disagree):")
    for s in DirectorRules.sources(project: d.project, home: home) { print("  - " + s.report) }
    if home == nil { print("  - No Home: rules for every director live in Home's HOME.md. Offer to set one up (`duo2 home set <folder>`), or keep a rule in this project (DL-207).") }
    print("This client:")
    for l in d.caps.lines { print("  " + l) }
    return 0
}

/// The projects inside Home that have their own director, two levels down: (folder, director name).
func projectDirectors(in home: URL) -> [(String, String)] {
    let fm = FileManager.default
    let kids = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
    let folders = kids + kids.filter { !ProtectedFolders.paths.contains($0.standardizedFileURL.path) }.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] }
    return folders.compactMap { f in DirectorRegistry.load(project: f).current.map { (String(f.path.dropFirst(home.path.count + 1)), $0.name) } }.sorted { $0.0 < $1.0 }
}

/// `duo2 director start` with Duo closed. No flag starts a worker in the background (`claude --bg`,
/// with Remote Control), as with Duo: the registry records it as pending under the name the command
/// carries, and whoever looks next (`status`, `watch`, Duo) links it by that name. `--suggest` and
/// `--no-worker` need no worker. What asks the user in Duo (`--worker`, `--adopt`) or starts there
/// (`--in-duo`) needs Duo running.
func directorStartOffline(_ rest: [String]) -> Int32 {
    let inv = Invocation(rest)
    for (flag, why) in [("worker", "it asks the user in Duo"), ("adopt", "it asks the user in Duo"), ("in-duo", "it starts the worker in Duo")] where inv.has(flag) {
        return offlineFail("--\(flag) needs Duo running: \(why). Without it, `duo2 director start` starts a background worker, which needs no Duo.")
    }
    let takeOverOnly = inv.has("take-over") && inv.flags["title"] == nil && inv[0] == nil
    guard takeOverOnly || inv.flags["title"] != nil || inv[0] != nil else { return offlineFail("usage: \(ActionID.directorStart.action.usage)") }
    var d: OfflineDirector
    do { d = try OfflineDirector(inv, login: !takeOverOnly) } catch let e as OfflineFailure { return offlineFail(e.why) } catch { return offlineFail("\(error)") }
    guard let me = d.me else { return offlineFail("not run from a Claude session (no session id), so there's no director to record") }
    if d.caps.projects { return offlineFail("This is a Claude Code Projects session: the Duo director starts nothing here (DL-203).") }
    if let r = d.standDown() { return offlineFail(r) }
    let p = d.projectName
    if case .other(let c) = d.role, !inv.has("take-over") {
        d.log("refused", "\(p) is directed by \(c.name)")
        if c.name == d.caps.name { return offlineFail("\(p)'s director is recorded as \(c.name), your name, under another session id (\(c.sessionId.prefix(8))): you were resumed or moved to a new one. Add --take-over to record yourself (§10); no Duo needed.") }
        return offlineFail("\(p) is directed by \(c.name) (session \(c.sessionId.prefix(8)), since \(c.since)). Ask the user; with their go-ahead, --take-over replaces it.")
    }
    if takeOverOnly && d.role == .current { print("You're already this project's director."); return 0 }
    let now = isoNow()
    func record() -> Bool {
        guard d.role != .current else { return true }
        let took = d.reg.current
        d.reg.adopt(name: d.name, sessionId: me, at: now)
        do { try d.reg.save(project: d.project) } catch { _ = offlineFail("couldn't write \(DirectorRegistry.file(project: d.project).path): \(error.localizedDescription)"); return false }
        d.log(took == nil ? "adopt" : "takeover", took.map { "replaced \($0.name)\($0.name == d.name ? " (the same name: this director resumed)" : ""); Duo closed" } ?? "Duo closed")
        return true
    }
    if takeOverOnly {
        // A director resumed or moved under a new session id (§10): record it, nothing else.
        guard record() else { return 1 }
        print("Recorded you as \(p)'s director, \(d.name). Its workers stay on their tasks.")
        return 0
    }

    let suggest = inv.has("suggest"), noWorker = inv.has("no-worker") && !suggest
    // Refusals that write nothing come first: a worker needs background sessions and a logged-in CLI.
    if !suggest && !noWorker {
        if d.caps.background == .no { return offlineFail("Background sessions are off for this client (agent view is disabled), so `duo2 director start` can't start a worker with Duo closed. Ask the user, or open Duo.") }
        if let why = Director.backgroundRefusal(d.caps) { d.log("refused", task: inv[0], why); return offlineFail(why) }
    }
    var path: String
    var made = false
    let fm = FileManager.default
    if let title = inv.flags["title"] {
        // A new task: the note is the director's own, written here as it would by hand.
        guard let request = inv.flags["request"], !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return offlineFail("a new task needs --request with the user's words, exactly (for long or quoted words: --request --stdin)")
        }
        guard record() else { return 1 }
        var slug = Director.slugFor(title), n = 2
        while fm.fileExists(atPath: d.project.appending(path: "tasks/\(slug).md").path) { slug = Director.slugFor(title) + "-\(n)"; n += 1 }
        path = "tasks/\(slug).md"
        let text = Director.newNote(title: title, request: request, doneWhen: inv.flags["done-when"], director: d.name, status: suggest ? "suggested" : "in-progress")
        do {
            try fm.createDirectory(at: d.project.appending(path: "tasks"), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: d.project.appending(path: path), options: .withoutOverwriting)
        } catch { return offlineFail("couldn't write \(path): \(error.localizedDescription)") }
        made = true
    } else {
        guard let t = inv[0], let hit = d.findTask(t) else { return offlineFail("no task '\(inv[0] ?? "")' in \(p) (tasks/*.md). Write it first (## Request, done_when:, directed_by:, ## Progress), or give --title and --request and duo2 writes it.") }
        path = hit.path
        let url = d.project.appending(path: path)
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let by = Director.frontmatter("directed_by", in: text) else {
            d.log("refused", task: path, "the user's task (no directed_by:)")
            return offlineFail("\(hit.title) has no directed_by:, so it's the user's (DL-200). `--adopt` needs Duo running: it asks the user in Duo.")
        }
        guard by == d.name else {
            d.log("refused", task: path, "directed by another director (\(by))")
            return offlineFail("\(hit.title) is directed by \(by), not you: never task another director's worker (DL-200).")
        }
        guard record() else { return 1 }
        if suggest { text = DirectorOffline.setting("status", "suggested", in: text) }
        if let dw = inv.flags["done-when"] { text = DirectorOffline.setting("done_when", DirectorOffline.quoted(dw), in: text) }
        try? Data(text.utf8).write(to: url, options: .atomic)
    }
    func noteStatus() -> String? { (try? String(contentsOf: d.project.appending(path: path), encoding: .utf8)).flatMap { Director.frontmatter("status", in: $0) } }
    func setStatus(_ s: String) {
        let url = d.project.appending(path: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? Data(DirectorOffline.setting("status", s, in: text).utf8).write(to: url, options: .atomic)
    }

    if noWorker {
        // Organising work the director does itself (DL-208): a task, no worker, no slot.
        if !made { setStatus("in-progress") }
        d.progress(path, "Taken by \(d.name) itself (organising work).")
        d.log("start", task: path, "no worker")
        print("\(path) is yours to do yourself (no worker), directed by \(d.name). Propose the plan, then act on the user's yes.")
        return 0
    }
    if suggest {
        d.log("start", task: path, "suggested")
        print("\(made ? "Filed" : "Marked") \(path) as suggested, directed by \(d.name). Nothing started: start it when the user says go (`duo2 director start \(path)`).")
        return 0
    }

    // `claude --bg` picks its own session id (F-318), so the worker is recorded under the name the
    // command carries, and linked when a session with that name appears.
    let (worker, cmd) = Director.backgroundStart(folder: d.project, task: path, director: d.name, remoteControl: d.caps.remoteControl == .yes)
    d.reg.setWorker(task: path, session: "", at: now, adopted: false, name: worker)
    do { try d.reg.save(project: d.project) } catch { return offlineFail("couldn't write \(DirectorRegistry.file(project: d.project).path): \(error.localizedDescription)") }
    let status = noteStatus()
    if status == nil || status == "open" || status == "suggested" { setStatus("in-progress") }
    d.progress(path, "Worker \(worker) to start in the background.")
    d.log("start", task: path, "background, Duo closed, as \(worker)")
    print("Run this; the worker is linked by its name, \(worker), as soon as it starts (`duo2 director status` or `watch` does it; no link step):\n  \(cmd)")
    return 0
}

/// `duo2 director send` with Duo closed: the same refusals and ladder as the app, minus the rungs
/// that need Duo. A message that can only wait for Duo isn't queued: nothing would deliver it.
func directorSendOffline(_ rest: [String]) -> Int32 {
    let inv = Invocation(rest)
    var d: OfflineDirector
    do { d = try OfflineDirector(inv) } catch let e as OfflineFailure { return offlineFail(e.why) } catch { return offlineFail("\(error)") }
    if let r = d.standDown() { return offlineFail(r) }
    guard d.role == .current else { return offlineFail("You're not \(d.projectName)'s director\(d.reg.current.map { " (\($0.name) is)" } ?? ""): `duo2 director start` makes you its director.") }
    if let target = inv.flags["director"] { return sendToDirectorOffline(d, target, message: inv.text) }
    guard let t = inv[0], inv.positional.count > 1 else { return offlineFail("usage: \(ActionID.directorSend.action.usage)") }
    let message = inv.positional.dropFirst().joined(separator: " ")
    guard let hit = d.findTask(t) else { return offlineFail("no task '\(t)' in \(d.projectName)") }
    let text = (try? String(contentsOf: d.project.appending(path: hit.path), encoding: .utf8)) ?? ""
    let by = Director.frontmatter("directed_by", in: text)
    guard by == d.name else {
        d.log("refused", task: hit.path, by.map { "directed by another director (\($0))" } ?? "not a directed task")
        return offlineFail(by.map { "\(hit.title) is directed by \($0), not you." } ?? "\(hit.title) has no directed_by:, so its sessions are the user's: never task them (DL-200).")
    }
    guard let w = d.reg.worker(task: hit.path), !w.pending else {
        if let w = d.reg.worker(task: hit.path) { return offlineFail("\(hit.title)'s worker hasn't started yet (it's linked when a session named \(w.name ?? "?") appears).") }
        return offlineFail("\(hit.title) has no worker of yours: `duo2 director start \(hit.path)` starts one.")
    }
    let sid = w.session
    // DL-200's pause: the user took the worker over. Only the user lifts it, in the director's own session.
    if let typed = DirectorOffline.userTurn(sessionId: sid, director: d.name, reg: d.reg) {
        guard inv.has("handed-back") else {
            d.log("refused", task: hit.path, worker: sid, "paused: the user typed into the worker")
            return offlineFail("The user typed into this worker (\(isoNow(typed))), so you're paused there (DL-200). Ask the user in your own session; if they tell you to carry on, send again with --handed-back.")
        }
        d.reg.handedBack[sid] = isoNow()
        try? d.reg.save(project: d.project)
        d.log("handback", task: hit.path, worker: sid, "the user said so in the director's session")
    }
    let beacon = d.beacons.first { $0.sessionId == sid }
    let run: WorkerFacts.Run = beacon.map { $0.status == "busy" ? .working : $0.status == "waiting" ? .needsYou : .idle } ?? .stopped
    let facts = WorkerFacts(place: .background, run: run, peerName: beacon?.peerName, userTyping: false)
    let rung = SendLadder.choose(director: d.caps, worker: facts, duoRunning: false)
    let tagged = Director.tag(d.name) + message

    switch rung {
    case .message:
        // duo2 can't call SendMessage for the director: log that it was handed over, never "delivered" (F-342).
        d.progress(hit.path, "Handed to the director to send (SendMessage; not confirmed delivered, and held if the permission modes differ): \(message.prefix(300))")
        d.log("handed", task: hit.path, worker: sid, rung: rung.rawValue, "handed to the director to send")
        print("Send it yourself: SendMessage(to: \"\(facts.peerName ?? sid)\"). Logged and noted in Progress as handed to you, not delivered. Messages between sessions in different permission modes are held and can expire unseen: the worker's last message and task note are the channel back, so read them rather than wait.")
        return 0
    case .resumeBackground, .headless:
        let env = ProcessInfo.processInfo.environment
        guard let claude = findClaude(env) else { return offlineFail("no claude to run (not on PATH, nor in ~/.local/bin or ~/.claude/local).") }
        if rung == .resumeBackground {
            var caps = d.caps
            caps.cliLogin = ClientCaps.cliLogin(env: env)
            if let why = Director.backgroundRefusal(caps) { d.log("refused", task: hit.path, worker: sid, rung: rung.rawValue, why); return offlineFail(why) }
        }
        // `--` ends the options: a message starting with "-" is never read as a flag.
        // A worker resumed in the background comes back reachable from the user's phone (DL-230).
        let rc = rung == .resumeBackground && d.caps.remoteControl == .yes ? w.name.map { ["--remote-control", $0] } ?? [] : []
        let args = (rung == .headless ? ["-p", "--resume", sid] : ["--bg", "--resume", sid] + rc) + ["--", tagged]
        let cwd = DirectorOffline.transcript(sessionId: sid).flatMap(DirectorOffline.filedCwd).flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil } ?? d.project.path
        let log = d.project.appending(path: ".duo/director-runs/\(sid.prefix(8))-\(Int(Date().timeIntervalSince1970)).log")
        let how = rung == .headless ? "a headless turn" : "resumed in the background"
        let ran = runClaudeDetached(claude, args, cwd: cwd, log: log, wait: rung == .headless ? nil : 60)
        if let why = ran.error { d.log("refused", task: hit.path, worker: sid, rung: rung.rawValue, why); return offlineFail("couldn't run claude: \(why)") }
        if rung == .headless {
            d.progress(hit.path, "Sent to the worker (a headless turn): \(message.prefix(300))")
            d.log("send", task: hit.path, worker: sid, rung: rung.rawValue, how)
            print("The worker had stopped: it's taking a headless turn with your message, in its own folder, and keeps going after this command ends (output: \(log.path)). Read the answer with `duo2 session show \(sid)` once it's done.")
            return 0
        }
        guard let status = ran.status else {
            d.progress(hit.path, "Sent to the worker (\(how); not confirmed after 60 s, see .duo/director-runs/): \(message.prefix(300))")
            d.log("send", task: hit.path, worker: sid, rung: rung.rawValue, "\(how); not confirmed after 60 s")
            print("The worker had stopped: claude is still resuming it with your message after 60 s, so it isn't confirmed. Its output is going to \(log.path); read it, and `duo2 session show \(sid)`.")
            return 0
        }
        guard status == 0 else {
            d.log("refused", task: hit.path, worker: sid, rung: rung.rawValue, "exit \(status); see \(log.path)")
            d.progress(hit.path, "Not delivered (\(how) ended with \(status); its output is in .duo/director-runs/): \(message.prefix(200))")
            return offlineFail("claude ended with status \(status) resuming the worker, so the message wasn't delivered. Its output is in \(log.path).")
        }
        d.progress(hit.path, "Sent to the worker (\(how)): \(message.prefix(300))")
        d.log("send", task: hit.path, worker: sid, rung: rung.rawValue, how)
        print("The worker had stopped: it's resuming in the background with your message. Read what it answers with `duo2 session show \(sid)`, or `duo2 director watch`.")
        return 0
    case .queued:
        // A busy worker that can't take messages: waiting needs Duo to deliver it, and it isn't running.
        d.log("refused", task: hit.path, worker: sid, rung: rung.rawValue, "busy, no messaging, Duo closed")
        return offlineFail("It's busy and can't take messages, and Duo isn't running to hold it: send again when it's stopped, or open Duo.")
    default:
        d.log("send", task: hit.path, worker: sid, rung: SendRung.askUser.rawValue, "no route")
        print("Duo can't reach this worker now: ask the user to pass it on to session \(sid.prefix(8)).")
        return 0
    }
}

/// Home's director asking a project's with Duo closed (DL-197): messaging if both ends have it, else the user.
func sendToDirectorOffline(_ d: OfflineDirector, _ target: String, message: String) -> Int32 {
    guard let home = d.home, home.standardizedFileURL.path == d.project.standardizedFileURL.path else {
        return offlineFail("--director is for Home's director asking a project's (DL-197); run it from Home.")
    }
    guard !message.isEmpty else { return offlineFail("usage: \(ActionID.directorSend.action.usage)") }
    guard let folder = projectDirectors(in: home).first(where: { $0.0 == target || URL(fileURLWithPath: $0.0).lastPathComponent == target }).map({ home.appending(path: $0.0) }),
          let cur = DirectorRegistry.load(project: folder).current else {
        return offlineFail("\(target) has no director: direct its work yourself (DL-197).")
    }
    if d.caps.messaging == .yes, let peer = d.beacons.first(where: { $0.sessionId == cur.sessionId })?.peerName {
        d.log("handed", worker: cur.sessionId, rung: SendRung.message.rawValue, "to \(cur.name)")
        print("Send it yourself: SendMessage(to: \"\(peer)\") with \"From \(d.name): \(message)\". Logged as handed to you, not delivered.")
    } else {
        d.log("send", worker: cur.sessionId, rung: SendRung.askUser.rawValue, "to \(cur.name): no live session with messaging")
        print("\(cur.name) isn't a live session you can message (Duo isn't running to carry it): ask the user to pass it on.")
    }
    return 0
}

/// `duo2 director retire` with Duo closed.
func directorRetireOffline(_ rest: [String]) -> Int32 {
    var d: OfflineDirector
    do { d = try OfflineDirector(Invocation(rest)) } catch let e as OfflineFailure { return offlineFail(e.why) } catch { return offlineFail("\(error)") }
    if let r = d.standDown() { return offlineFail(r) }
    guard d.role == .current, let gone = d.reg.retire(at: isoNow()) else { return offlineFail("You're not \(d.projectName)'s director, so there's nothing to retire.") }
    do { try d.reg.save(project: d.project) } catch { return offlineFail("couldn't write \(DirectorRegistry.file(project: d.project).path): \(error.localizedDescription)") }
    d.log("retire")
    print("\(gone.name) is retired as \(d.projectName)'s director. Its workers stay on their tasks until a new director takes over (`duo2 director start --take-over`).")
    return 0
}

/// `duo2 session show <id>` with Duo closed: what Claude's own files say. A director reads a
/// worker's report this way (its last message).
func sessionShowOffline(_ rest: [String]) -> Int32 {
    guard let given = Invocation(rest)[0] else { return offlineFail("usage: \(ActionID.sessionShow.action.usage)") }
    let beacons = DirectorOffline.beacons()
    guard let id = DirectorOffline.fullId(given, beacons: beacons) else { return offlineFail("Duo isn't running, and no session '\(given)' is live or has a transcript here.") }
    let b = beacons.first { $0.sessionId == id }
    let state = b.map { $0.status == "busy" ? "working" : $0.status == "waiting" ? "needs-you" : "idle" } ?? "stopped"
    print("Session \(id)\(b?.name.map { " (\($0))" } ?? ""): \(state)\(b.map { ", running in \($0.cwd)" } ?? "").")
    print("Duo isn't running, so this is what Claude's files hold, not Duo's view.")
    guard let t = DirectorOffline.transcript(sessionId: id) else { print("No transcript found."); return 0 }
    print("Transcript: \(t.path)")
    if let last = DirectorOffline.lastAssistantText(t) { print("Last assistant message:\n\(last)") } else { print("It hasn't said anything yet.") }
    return 0
}

/// `claude` as the caller would run it: on PATH, else where Claude installs itself.
func findClaude(_ env: [String: String]) -> String? {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init) + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
    return dirs.map { "\($0)/claude" }.first { fm.isExecutableFile(atPath: $0) }
}

/// Runs `claude` for a director in `cwd`, with Duo's and the calling session's variables stripped and
/// its output in `log`. `wait` seconds for it to end (status nil if it hasn't), or not at all: it
/// then runs on after duo2 exits. `error` is why it didn't start.
func runClaudeDetached(_ claude: String, _ args: [String], cwd: String, log: URL, wait: TimeInterval?) -> (error: String?, status: Int32?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: claude)
    p.arguments = args
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    p.environment = DirectorOffline.runEnvironment(ProcessInfo.processInfo.environment)
    p.standardInput = FileHandle.nullDevice
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    DirectorOffline.pruneRuns(beside: log)
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let out = try? FileHandle(forWritingTo: log)
    p.standardOutput = out ?? FileHandle.nullDevice
    p.standardError = out ?? FileHandle.nullDevice
    do { try p.run() } catch { return (error.localizedDescription, nil) }
    guard let wait else { return (nil, nil) }
    let deadline = Date().addingTimeInterval(wait)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    return (nil, p.isRunning ? nil : p.terminationStatus)
}

/// Session ids of Claude processes running now, from their session files.
func liveSessionIds() -> Set<String> { Set(DirectorOffline.beacons().map(\.sessionId)) }

// MARK: - Watch

/// `duo2 director watch`: polls Duo (or, with Duo closed, Claude's beacons and the task notes) for
/// this director's workers and prints one line per change, for Monitor (each line wakes the
/// director, F-310). Runs until killed.
func runDirectorWatch(_ rest: [String]) -> Int32 {
    let inv = Invocation(rest)
    let every = max(1, Double(inv.flags["every"] ?? "5") ?? 5)
    let env = ProcessInfo.processInfo.environment
    var last: [String: String] = [:]
    var first = true
    var told = ""
    setvbuf(stdout, nil, _IOLBF, 0)
    while true {
        var args = ["--json", "--caps", directorCaps()]
        if let p = inv.flags["project"] { args += ["--project", p] }
        var status: [String: Any]?
        if let (endpoint, source) = ControlEndpoint.discover(),
           let r = try? ControlClient.send(ControlRequest(token: endpoint.token, command: "director status", args: args,
                                                          session: env["CLAUDE_CODE_SESSION_ID"] ?? env["DUO_SESSION_ID"],
                                                          cwd: FileManager.default.currentDirectoryPath), via: endpoint, source: source, timeout: 15),
           r.ok, let data = r.output.data(using: .utf8) {
            status = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        if status == nil {
            do { status = try watchStatusOffline(inv) } catch let e as OfflineFailure {
                if told != e.why { print("Can't watch: \(e.why)"); told = e.why }
            } catch {}
        }
        if let j = status {
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
        }
        Thread.sleep(forTimeInterval: every)
    }
}

/// What `director status --json` says that `watch` reads, with Duo closed: this director's tasks,
/// each with its worker's state. Links pending workers on the way (they'd never show otherwise).
func watchStatusOffline(_ inv: Invocation) throws -> [String: Any] {
    let d = try OfflineDirector(inv)
    var j: [String: Any] = ["workers": watchWorkers(d.tasks())]
    switch d.role {
    case .replaced(let by): j["role"] = "replaced"; j["replacedBy"] = by?.name
    case .current: j["role"] = "current"
    case .other: j["role"] = "other"
    case .none: j["role"] = "none"
    }
    return j
}

/// A director's tasks as `watch` compares them (the keys the app's JSON uses).
func watchWorkers(_ tasks: [DirectorOffline.Task]) -> [[String: Any]] {
    tasks.map { t in
        var w: [String: Any] = ["task": t.path, "title": t.title, "state": t.state, "noteModified": t.noteModified, "userTyping": t.userTyping]
        if let s = t.session { w["session"] = s }
        if let q = t.question { w["question"] = q }
        return w
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
