import AppKit
import DuoControl
import Foundation

/// `duo2 director status|start|send|retire` (DL-193 to DL-205): the exact parts of the duo-director
/// skill. The caller's abilities come from its own side (`--caps`, `ClientCaps`); who directs a
/// project is `.duo/director.json` (DL-200); every step is a line in `.duo/director-log.jsonl`
/// and, for a task, in its note's `## Progress` (DL-194, DL-199). Where the user's yes is needed
/// (taking on their task or session, handing a worker back), Duo asks them itself, with the same
/// confirm sheet merges use; a director's word is never the yes.
extension AppModel {
    /// One worker as `status` and `watch` see it.
    struct DirectedTask {
        var note: TaskNote
        var text: String
        var modified: Double
        var worker: Fixture.Session?
        var facts: WorkerFacts?
        var stateWord: String
        /// A worker the director started in the background that hasn't appeared yet: its name.
        var pendingName: String?
        /// Counts against the cap (DL-201): an unfinished task whose worker runs, or hasn't started yet.
        var holdsSlot: Bool {
            Director.holdsSlot(status: note.status, archived: note.archived) && (pendingName != nil || (facts.map { $0.run != .stopped } ?? false))
        }
    }

    func directorVerb(_ id: ActionID, _ inv: Invocation, _ req: ControlRequest, _ done: @escaping @MainActor (Reply) -> Void) {
        var caps = inv.flags["caps"].flatMap { try? JSONDecoder().decode(ClientCaps.self, from: Data($0.utf8)) } ?? ClientCaps()
        caps.sessionId = req.session ?? caps.sessionId   // the caller, as the control plane knows it
        // The project is the one the caller runs in (or --project): the folder DirectorPlace finds
        // from its working folder (as duo2 does with Duo closed), else the Duo folder holding it;
        // never a guess from what's on screen.
        let place = req.cwd.map { DirectorPlace.resolve(from: URL(fileURLWithPath: $0)).project.realPath }
        let byPlace = place.flatMap { pl in liveFolders.first { $0.value.realPath == pl }?.key }
        guard let pname = inv.flags["project"] ?? byPlace ?? projectFor(cwd: req.cwd)?.name else {
            return done(.fail("Duo doesn't know \(req.cwd ?? "this folder") as a project or folder: run it from the project's folder, or pass --project <name> (`duo2 projects` lists them)."))
        }
        guard let p = project(named: pname), let folder = liveFolders[p.name] else { return done(.fail("no project '\(pname)'")) }
        let me = req.session ?? caps.sessionId
        var reg = DirectorRegistry.load(project: folder)
        let role = reg.role(sessionId: me)
        let mine = reg.current.flatMap { role == .current ? $0.name : nil }
            ?? (caps.name?.hasPrefix("director-") == true ? caps.name! : Director.name(project: p.name))
        let now = Self.isoNow()
        func log(_ event: String, task: String? = nil, worker: String? = nil, rung: String? = nil, _ detail: String? = nil) {
            DirectorLog.append(DirectorEvent(at: now, director: mine, event: event, task: task, worker: worker, rung: rung, detail: detail), project: folder)
        }
        func standDown() -> Reply? {
            guard case .replaced(let by) = role else { return nil }
            log("standdown", by.map { "replaced by \($0.name)" })
            return .fail("You were replaced as \(p.name)'s director\(by.map { " by \($0.name) (since \($0.since))" } ?? ""). Stand down: say so to the user and stop directing.")
        }

        switch id {
        case .directorStatus:
            done(directorStatus(p, folder: folder, reg: reg, role: role, director: mine, caps: caps))

        case .directorStart:
            if caps.projects { return done(.fail("This is a Claude Code Projects session: the Duo director starts nothing here (DL-203).")) }
            if let r = standDown() { return done(r) }
            if case .other(let c) = role {
                guard inv.has("take-over") else {
                    log("refused", "\(p.name) is directed by \(c.name)")
                    return done(.fail("\(p.name) is directed by \(c.name) (session \(c.sessionId.prefix(8)), since \(c.since)). Ask the user; with their go-ahead, --take-over replaces it."))
                }
            }
            guard let me else { return done(.fail("not run from a Claude session (no session id), so there's no director to record")) }
            // The user's yes comes first, before anything is written (so a no leaves nothing behind).
            let ask = inv.has("adopt") ? adoptQuestion(p, folder: folder, inv: inv, director: mine, caller: me) : nil
            let go: @MainActor (Bool) -> Void = { [weak self] allowed in
                guard let self else { return }
                if ask != nil, !allowed {
                    log("refused", task: inv[0], worker: inv.flags["worker"], "the user said no in Duo")
                    return done(.fail("The user said not now in Duo, so it stays theirs (DL-200)."))
                }
                if role != .current {
                    let took = reg.current
                    reg.adopt(name: mine, sessionId: me, at: now)
                    try? reg.save(project: folder)
                    log(took == nil ? "adopt" : "takeover", took.map { "replaced \($0.name)\($0.name == mine ? " (the same name: this director resumed)" : "")" })
                }
                // `start --take-over` alone: only the take-over (a resumed director whose id moved, P3).
                if inv[0] == nil, inv.flags["title"] == nil {
                    return done(inv.has("take-over") ? .ok("You're \(p.name)'s director now, as \(mine).") : .fail("usage: \(ActionID.directorStart.action.usage)"))
                }
                done(self.directorStart(p, folder: folder, inv: inv, director: mine, caps: caps, adoptAllowed: ask != nil && allowed, log: log))
            }
            if let ask { confirm(title: ask.title, detail: ask.detail, button: "Allow", then: go) } else { go(true) }

        case .directorSend:
            if let r = standDown() { return done(r) }
            guard role == .current else { return done(.fail("You're not \(p.name)'s director\(reg.current.map { " (\($0.name) is)" } ?? ""): `duo2 director start` makes you its director.")) }
            directorSend(p, folder: folder, inv: inv, director: mine, caps: caps, log: log, done: done)

        case .directorRetire:
            if let r = standDown() { return done(r) }
            guard role == .current, let gone = reg.retire(at: now) else { return done(.fail("You're not \(p.name)'s director, so there's nothing to retire.")) }
            try? reg.save(project: folder)
            log("retire")
            done(.ok("\(gone.name) is retired as \(p.name)'s director. Its workers stay on their tasks until a new director takes over (`duo2 director start --take-over`)."))

        default:
            done(.fail("`duo2 \(id.rawValue)` runs in duo2, not the app"))
        }
    }

    static func isoNow(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = .current
        return f.string(from: d)
    }

    /// What Duo asks the user before a director takes on something of theirs (`--adopt`): their task
    /// (no `directed_by:`), or their session as a worker. Nil when nothing of theirs is involved.
    func adoptQuestion(_ p: Fixture.Project, folder: URL, inv: Invocation, director: String, caller: String) -> (title: String, detail: String)? {
        var theirs: [String] = []
        var taskPath: String?
        if inv.flags["title"] == nil, let t = inv[0], let hit = findTask(t, project: p.name) {
            taskPath = hit.path
            let text = (try? String(contentsOf: folder.appending(path: hit.path), encoding: .utf8)) ?? ""
            if DirectorNotes.directedBy(text) == nil { theirs.append("• the task “\(hit.title)” (\(hit.path)), which has no directed_by:") }
        }
        if let w = inv.flags["worker"], let s = findSession(w, in: nil), let id = s.sessionId, id != caller,
           !startedBy(director, id, task: taskPath ?? "", folder: folder) {
            theirs.append("• the session “\(s.name)”, as its worker: \(director) would message it, and Duo would press Enter in it when it's idle")
        }
        guard !theirs.isEmpty else { return nil }
        return ("Let \(director) take this on?",
                "\(director) asks to direct something of yours:\n\n" + theirs.joined(separator: "\n") + "\n\nUntil you allow it, it stays yours. You can take it back later by removing directed_by: from the task's note.")
    }

    // MARK: Workers

    /// The project's tasks `director` directs (open and suggested; not archived), each with its
    /// worker: the session `.duo/director.json` records for that task, never a session the note
    /// merely links (those are the user's, DL-200).
    func directedTasks(_ project: String, folder: URL, director: String) -> [DirectedTask] {
        let reg = DirectorRegistry.load(project: folder)
        let dir = folder.appending(path: "tasks")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8), DirectorNotes.directedBy(text) == director else { return nil }
            let note = TaskNotes.parse(text, path: "tasks/" + url.lastPathComponent)
            guard !note.archived else { return nil }
            let mod = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast).timeIntervalSince1970
            let w = reg.worker(task: note.path)
            let worker = w.flatMap { w in w.pending ? nil : self.fixture.sessions.first { $0.sessionId == w.session } }
            let facts = worker.map { workerFacts($0, paused: takenOver($0, folder: folder, director: director, reg: reg) != nil) }
            let word = facts.map { $0.run == .stopped ? "stopped" : stateWord(worker!.state) } ?? (w?.pending == true ? "starting" : "no worker")
            return DirectedTask(note: note, text: text, modified: mod, worker: worker, facts: facts, stateWord: word, pendingName: w?.pending == true ? w?.name : nil)
        }
    }

    /// Where a worker runs and whether it's running, from Duo's terminal and Claude's beacon (F-311).
    /// When the user took the worker over (DL-200): a turn of theirs in its transcript after the
    /// director's last message and after they last handed it back. Nil when the director may send.
    func takenOver(_ s: Fixture.Session, folder: URL, director: String, reg: DirectorRegistry) -> Date? {
        guard let id = s.sessionId, let t = ClaudeStorage.transcript(sessionId: id, cwd: cwd(of: s.tabKey) ?? folder.path),
              let typed = DirectorTranscript.userTurnSinceDirector(t, tag: Director.tag(director)) else { return nil }
        if let back = reg.handedBack[id].flatMap({ ISO8601DateFormatter().date(from: $0) }), typed <= back { return nil }
        return typed
    }

    /// `paused`: the user took it over (`takenOver`).
    func workerFacts(_ s: Fixture.Session, paused: Bool = false) -> WorkerFacts {
        let t = terminals.existing(s.tabKey)
        let runningHere = t?.isLiveClaude == true
        let runningElsewhere = !runningHere && s.liveProcess == true
        let place: WorkerFacts.Where
        if t != nil || runningHere { place = .duo }
        else if runningElsewhere { place = .background }
        else {
            // Stopped: Duo started it (and reopens it in a tab), or it ran outside Duo.
            let folder = liveFolders[s.project]
            let entry = folder.flatMap { f in SessionIndex.load(project: f).sessions.first { $0.sessionId == s.sessionId } }
            place = entry?.provenance.hasPrefix("created-by-duo") == true || entry?.provenance.hasPrefix("directed-by:") == true ? .duo : .background
        }
        let run: WorkerFacts.Run
        if !runningHere && !runningElsewhere { run = .stopped }
        else { run = s.state == .working ? .working : s.state == .needsYou ? .needsYou : .idle }
        let beacon = Beacon.readAll().first { $0.sessionId == s.sessionId }
        return WorkerFacts(place: place, run: run, peerName: beacon?.peerName, userTyping: paused)
    }

    func directorStatus(_ p: Fixture.Project, folder: URL, reg: DirectorRegistry, role: DirectorRegistry.Role, director: String, caps: ClientCaps) -> Reply {
        var lines: [String] = []
        var j: [String: Any] = ["project": p.name, "folder": folder.path, "director": director]
        lines.append("Project: \(p.name) (\(folder.path)).")
        switch role {
        case .current: lines.append("You're \(p.name)'s director, \(director)."); j["role"] = "current"
        case .replaced(let by):
            lines.append("You were replaced as \(p.name)'s director\(by.map { " by \($0.name)" } ?? ""): stand down, say so, and stop.")
            j["role"] = "replaced"; j["replacedBy"] = by?.name
        case .other(let c):
            lines.append(c.name == caps.name
                ? "\(p.name)'s director is named \(c.name), like you, but runs as session \(c.sessionId.prefix(8)). If you are that director, resumed with a new id, `duo2 director start --take-over` records you; otherwise another session has your name: ask the user."
                : "\(p.name) is directed by \(c.name) (session \(c.sessionId.prefix(8)), since \(c.since)), not you. Ask the user before taking over (`duo2 director start --take-over`).")
            j["role"] = "other"; j["current"] = c.name
        case .none:
            lines.append("Nobody directs \(p.name) yet. `duo2 director start` makes you its director, as \(director)\(caps.name == director ? "" : " (start as `claude -n \(director)` so the name survives restarts)").")
            j["role"] = "none"
        }
        if caps.projects { lines.append("This is a Claude Code Projects session: start nothing here (DL-203).") }

        let tasks = directedTasks(p.name, folder: folder, director: reg.current?.name ?? director)
        let brief = (try? String(contentsOf: folder.appending(path: "PROJECT.md"), encoding: .utf8)) ?? ""
        let cap = Director.cap(directorSection: Director.section("Director", in: brief))
        let active = tasks.filter(\.holdsSlot)
        lines.append("Workers: \(active.count) of \(cap).")
        for t in tasks {
            var l = "  \(t.note.path)  \(t.note.title) (\(t.note.status ?? "open"))  "
            if let w = t.worker, let f = t.facts {
                l += "\(t.stateWord), \(f.place.rawValue), session \(w.sessionId?.prefix(8) ?? "?")"
                if let q = w.question { l += ": \(q)" }
                if f.userTyping { l += " · the user took it over (typed there since your last message): you're paused there until they hand it back" }
            } else if let n = t.pendingName { l += "starting in the background as \(n)" }
            else { l += "no worker" }
            lines.append(l)
        }
        let pending = reg.pending
        if !pending.isEmpty { lines.append("Waiting to be delivered: " + pending.map { "\($0.task) (since \($0.at))" }.joined(separator: ", ")) }
        j["workers"] = tasks.map { t -> [String: Any] in
            var w: [String: Any] = ["task": t.note.path, "title": t.note.title, "status": t.note.status ?? "open", "state": t.stateWord, "noteModified": t.modified]
            if let s = t.worker { w["session"] = s.sessionId ?? ""; if let q = s.question { w["question"] = q } }
            if let f = t.facts { w["place"] = f.place.rawValue; w["userTyping"] = f.userTyping; if let n = f.peerName { w["peer"] = n } }
            // The user's last turn there since the director's last message (DL-200): an overlay's
            // "never stop or archive a session the user is in" reads it too.
            if let s = t.worker, let at = takenOver(s, folder: folder, director: reg.current?.name ?? director, reg: reg) { w["userTurnAt"] = Self.isoNow(at) }
            if let n = t.pendingName { w["starting"] = n }
            return w
        }
        j["cap"] = cap
        j["active"] = active.count
        j["pending"] = pending.count

        // Home sees every project's director (DL-197).
        if p.isHome == true {
            let others = liveFolders.filter { $0.key != p.name }.compactMap { name, f in DirectorRegistry.load(project: f).current.map { (name, $0) } }.sorted { $0.0 < $1.0 }
            lines.append(others.isEmpty ? "No project has its own director: you may direct work in any of them." :
                "Projects with their own director (ask it, never touch its workers): " + others.map { "\($0.0) (\($0.1.name))" }.joined(separator: ", "))
            j["projectDirectors"] = Dictionary(uniqueKeysWithValues: others.map { ($0.0, $0.1.name) })
        }

        let home = homeFolder ?? DirectorPlace.resolve(from: folder).home
        lines.append("Rules (the project's win where they disagree):")
        let rules = DirectorRules.sources(project: folder, home: home)
        lines += rules.map { "  - " + $0.report }
        if home == nil { lines.append("  - No Home yet: rules for every director live in Home's HOME.md. Offer to set one up (`duo2 home set <folder>`), or keep a rule in this project (DL-207).") }
        j["rules"] = rules.map { ["label": $0.label, "path": $0.path, "section": $0.section, "exists": $0.exists, "fileExists": $0.fileExists, "text": DirectorRules.text($0) ?? ""] }
        j["home"] = home?.path ?? ""
        lines.append("This client:")
        lines += caps.lines.map { "  " + $0 }
        j["client"] = ["version": caps.version ?? "", "messaging": caps.messaging.rawValue, "background": caps.background.rawValue,
                       "remoteControl": caps.remoteControl.rawValue, "hooks": caps.hooks.rawValue, "monitor": caps.monitor.rawValue,
                       "inDuo": caps.inDuo, "projects": caps.projects]
        return .ok(lines.joined(separator: "\n"), j)
    }

    // MARK: start

    /// `adoptAllowed`: the user said yes in Duo to what `adoptQuestion` asked.
    func directorStart(_ p: Fixture.Project, folder: URL, inv: Invocation, director: String, caps: ClientCaps, adoptAllowed: Bool,
                       log: (String, String?, String?, String?, String?) -> Void) -> Reply {
        let fm = FileManager.default
        let theirs = "Ask them; with --adopt, Duo asks them itself and goes ahead only if they allow it."
        // Refusals that write nothing come first.
        if let w = inv.flags["worker"] {
            if w == caps.sessionId { return .fail("that's you: a director isn't its own worker") }
            guard let s = findSession(w, in: nil), let id = s.sessionId else { return .fail("no session '\(w)'") }
            let task = inv.flags["title"] == nil ? inv[0].flatMap { findTask($0, project: p.name)?.path } ?? "" : ""
            if let why = workerRefusal(id, task: task, folder: folder, caller: caps.sessionId) { log("refused", task, id, nil, why); return .fail(why) }
            if !startedBy(director, id, task: task, folder: folder), !adoptAllowed {
                log("refused", task, id, nil, "the user's session")
                return .fail("“\(s.name)” wasn't started by you, so it's the user's (DL-200). \(theirs)")
            }
        }
        var path: String
        var made = false
        if let title = inv.flags["title"] {
            guard let request = inv.flags["request"], !request.trimmingCharacters(in: .whitespaces).isEmpty else {
                return .fail("a new task needs --request with the user's words, exactly")
            }
            let dir = folder.appending(path: "tasks")
            var slug = TaskNotes.slug(title), n = 2
            while fm.fileExists(atPath: dir.appending(path: "\(slug).md").path) { slug = TaskNotes.slug(title) + "-\(n)"; n += 1 }
            path = "tasks/\(slug).md"
            let text = DirectorNotes.newNote(title: title, request: request, doneWhen: inv.flags["done-when"], director: director,
                                             status: inv.has("suggest") ? DirectorNotes.suggested : "in-progress", links: [],
                                             template: Templates.text(.task, project: folder, home: homeFolder).text)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: folder.appending(path: path), options: .withoutOverwriting)
            } catch { return .fail("couldn't write \(path): \(error.localizedDescription)") }
            made = true
        } else {
            guard let t = inv[0] else { return .fail("usage: \(ActionID.directorStart.action.usage)") }
            guard let hit = findTask(t, project: p.name) else { return .fail("no task '\(t)' in \(p.name)") }
            path = hit.path
            let text = (try? String(contentsOf: folder.appending(path: path), encoding: .utf8)) ?? ""
            if let by = DirectorNotes.directedBy(text), by != director {
                log("refused", path, nil, nil, "directed by another director (\(by))")
                return .fail("\(hit.title) is directed by \(by), not you: never task another director's worker (DL-200).")
            }
            if DirectorNotes.directedBy(text) == nil {
                // A task with no directed_by: is the user's (DL-200): only on their yes, given in Duo.
                guard adoptAllowed else {
                    log("refused", path, nil, nil, "the user's task (no directed_by:)")
                    return .fail("\(hit.title) has no directed_by:, so it's the user's (DL-200). \(theirs)")
                }
                _ = editTaskNote(p.name, path, .setKey("directed_by", TaskNotes.quoted(director)))
            }
            if inv.has("suggest") { _ = editTaskNote(p.name, path, .setKey("status", DirectorNotes.suggested)) }
            if let d = inv.flags["done-when"] { _ = editTaskNote(p.name, path, .setKey("done_when", TaskNotes.quoted(d))) }
        }
        refreshLive()
        if inv.has("no-worker"), !inv.has("suggest") {
            // Organising work the director does itself (DL-208): a task, no worker, no slot.
            if !made { _ = editTaskNote(p.name, path, .setKey("status", "in-progress")) }
            _ = editTaskNote(p.name, path, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Taken by \(director) itself (organising work).")))
            log("start", path, nil, nil, "no worker")
            return .ok("\(path) is yours to do yourself (no worker), directed by \(director). Propose the plan, then act on the user's yes.", ["task": path])
        }
        if inv.has("suggest") {
            log("start", path, nil, nil, "suggested")
            return .ok("\(made ? "Filed" : "Marked") \(path) as suggested, directed by \(director). Nothing started: start it when the user says go (`duo2 director start \(path)`).",
                       ["task": path, "status": DirectorNotes.suggested])
        }

        // The cap (DL-201): workers running on unfinished tasks, this one aside, plus ones started
        // in the background that haven't appeared yet. A worker stopped after its work (waiting
        // on the user's sign-off) frees its slot.
        let brief = (try? String(contentsOf: folder.appending(path: "PROJECT.md"), encoding: .utf8)) ?? ""
        let cap = Director.cap(directorSection: Director.section("Director", in: brief))
        let busy = directedTasks(p.name, folder: folder, director: director).filter { $0.note.path != path && $0.holdsSlot }
        if busy.count >= cap {
            _ = editTaskNote(p.name, path, .setKey("status", DirectorNotes.suggested))
            _ = editTaskNote(p.name, path, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Not started: \(busy.count) of \(cap) workers busy, so it waits as suggested.")))
            log("refused", path, nil, nil, "cap \(cap)")
            return .fail("You have \(busy.count) of \(cap) workers (\(busy.map(\.note.path).joined(separator: ", "))). \(path) is filed as suggested; start it when one finishes. The project's ## Director can change the cap (max workers: N).")
        }

        func inProgress() {
            let status = TaskNotes.parse((try? String(contentsOf: folder.appending(path: path), encoding: .utf8)) ?? "", path: path).status
            if status == nil || status == "open" || status == DirectorNotes.suggested { _ = editTaskNote(p.name, path, .setKey("status", "in-progress")) }
        }
        // The worker.
        let sid: String
        var how: String
        var adopted = false
        if let w = inv.flags["worker"], let s = findSession(w, in: nil), let id = s.sessionId {
            adopted = !startedBy(director, id, task: path, folder: folder)
            sid = id; how = adopted ? "adopted \(s.name) (the user allowed it in Duo)" : "linked \(s.name)"
        } else if inv.has("background") {
            // The director runs the command itself (its own flags, Remote Control, its model).
            // `claude --bg` picks its own session id (it ignores --session-id), so the worker is
            // recorded by a name unique to this start; Duo links it when a session with that name
            // appears, with no link step and no --adopt (F-318).
            let (name, cmd) = Director.backgroundStart(folder: folder, task: path, director: director)
            var reg = DirectorRegistry.load(project: folder)
            reg.setWorker(task: path, session: "", at: Self.isoNow(), adopted: false, name: name)
            try? reg.save(project: folder)
            inProgress()
            _ = editTaskNote(p.name, path, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Worker \(name) to start in the background.")))
            log("start", path, nil, nil, "background, as \(name)")
            return .ok("Run this; Duo links the worker by its name, \(name), as soon as it starts (no link step):\n  \(cmd)",
                       ["task": path, "command": cmd, "name": name])
        } else {
            guard let id = newSession(in: p.name, prompt: Director.workerPrompt(note: folder.appending(path: path).path, director: director), provenance: "directed-by:\(director)") else {
                return .fail("couldn't start a worker in \(p.name) (is Duo running on live folders?)")
            }
            sid = id; how = "started in Duo"
        }
        recordWorker(sid, task: path, project: p.name, folder: folder, adopted: adopted, how: how)
        inProgress()
        log("start", path, sid, nil, how)
        refreshLive()
        return .ok("\(path): worker \(sid) \(how), directed by \(director). Hear back with Monitor on `duo2 director watch` (or `duo2 director status`).",
                   ["task": path, "worker": sid, "director": director])
    }

    /// Records `sid` as `task`'s worker: the registry, the note's link and a Progress line.
    func recordWorker(_ sid: String, task: String, project: String, folder: URL, adopted: Bool, how: String) {
        let title = fixture.sessions.first { $0.sessionId == sid }?.name ?? sid
        var reg = DirectorRegistry.load(project: folder)
        reg.setWorker(task: task, session: sid, at: Self.isoNow(), adopted: adopted)
        try? reg.save(project: folder)
        _ = editTaskNote(project, task, .addSession(link: TaskNotes.link(title: title, id: sid)))
        _ = editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Worker \(sid.prefix(8)) \(how).")))
    }

    /// Why `id` can't be this director's worker on `task`, or nil (DL-200): never the director
    /// itself, a project's director, or another task's worker.
    func workerRefusal(_ id: String, task: String, folder: URL, caller: String?) -> String? {
        if id == caller { return "that's you: a director isn't its own worker" }
        if liveFolders.values.contains(where: { DirectorRegistry.load(project: $0).current?.sessionId == id }) { return "that session is a project's director, not a worker" }
        let reg = DirectorRegistry.load(project: folder)
        if let w = reg.workers.first(where: { $0.session == id && $0.task != task }) { return "that session is already the worker on \(w.task): one worker per task (DL-201)" }
        return nil
    }

    /// Whether this director started `id`: Duo started it for the director (index provenance
    /// `directed-by:<director>`), or it's already recorded as this task's worker.
    func startedBy(_ director: String, _ id: String, task: String, folder: URL) -> Bool {
        if liveFolders.values.contains(where: { f in SessionIndex.load(project: f).sessions.contains { $0.sessionId == id && $0.provenance == "directed-by:\(director)" } }) { return true }
        guard let w = DirectorRegistry.load(project: folder).worker(task: task) else { return false }
        return w.session == id && !w.adopted
    }



    /// A director's edit to a task note: through the editor's buffer when the note is open there
    /// (as Status ▸ does, DL-13), else on disk. Nil, or why not.
    @discardableResult
    func editTaskNote(_ project: String, _ path: String, _ edit: TaskNotes.NoteEdit) -> String? {
        guard DirectorRegistry.isTaskPath(path) else { return "\(path) isn't a note in tasks/" }
        guard let folder = liveFolders[project] else { return "no project '\(project)'" }
        let file = folder.appending(path: path)
        if let e = editorIfLoaded, e.url?.standardizedFileURL == file.standardizedFileURL {
            e.applyNoteEdit(edit)
            return nil
        }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "\(path) isn't readable" }
        guard let new = TaskNotes.apply(edit, to: text) else { return nil }
        do { try Data(new.utf8).write(to: file, options: .atomic) } catch { return error.localizedDescription }
        return nil
    }
}
