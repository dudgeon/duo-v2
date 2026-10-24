import AppKit
import DuoControl
import Foundation

/// DL-199: Duo carries a director's messages where sessions can't message each other. This is new
/// ground: Duo presses Enter for a director, so every way in goes through `SubmitGuard` (fed from
/// the note and `.duo/director.json`, never assumed) and the screen check below, and every send is
/// logged with its rung and noted in the task's Progress.
extension AppModel {
    func directorSend(_ p: Fixture.Project, folder: URL, inv: Invocation, director: String, caps: ClientCaps,
                      log: @escaping (String, String?, String?, String?, String?) -> Void, done: @escaping @MainActor (Reply) -> Void) {
        if let target = inv.flags["director"] {
            guard p.isHome == true else { return done(.fail("--director is for Home's director asking a project's (DL-197); run it from Home.")) }
            return sendToDirector(target, message: inv.text, from: director, log: log, done: done)
        }
        guard let t = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(ActionID.directorSend.action.usage)")) }
        let message = inv.positional.dropFirst().joined(separator: " ")
        guard let hit = findTask(t, project: p.name) else { return done(.fail("no task '\(t)' in \(p.name)")) }
        let text = (try? String(contentsOf: folder.appending(path: hit.path), encoding: .utf8)) ?? ""
        let directedBy = DirectorNotes.directedBy(text)
        guard directedBy == director else {
            log("refused", hit.path, nil, nil, directedBy.map { "directed by another director (\($0))" } ?? "not a directed task")
            return done(.fail(directedBy.map { "\(hit.title) is directed by \($0), not you." } ?? "\(hit.title) has no directed_by:, so its sessions are the user's: never task them (DL-200)."))
        }
        let reg = DirectorRegistry.load(project: folder)
        guard let w = reg.worker(task: hit.path), !w.pending, let worker = fixture.sessions.first(where: { $0.sessionId == w.session }), let sid = worker.sessionId else {
            if reg.worker(task: hit.path)?.pending == true { return done(.fail("\(hit.title)'s worker hasn't started yet (it's linked when a session named \(reg.worker(task: hit.path)?.name ?? "?") appears).")) }
            return done(.fail("\(hit.title) has no worker of yours: `duo2 director start \(hit.path)` starts one."))
        }
        let send: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let facts = self.workerFacts(worker, paused: false)
            let rung = SendLadder.choose(director: caps, worker: facts, duoRunning: true)
            self.carry(rung, message: message, task: hit.path, project: p.name, folder: folder, worker: worker, facts: facts, director: director,
                       directedBy: directedBy, onTask: true, log: log, done: done)
        }
        // DL-200's pause: the user took the worker over (a turn of theirs in its transcript since the
        // director's last message). Only the user lifts it, in Duo: --handed-back makes Duo ask them.
        guard let since = takenOver(worker, folder: folder, director: director, reg: reg).map({ Self.isoNow($0) }) else { return send() }
        guard inv.has("handed-back") else {
            log("refused", hit.path, sid, nil, "paused: the user typed into the worker")
            return done(.fail("The user typed into this worker (\(since)), so you're paused there (DL-200). With --handed-back, Duo asks them whether to hand it back to you, and sends only if they do."))
        }
        confirm(title: "Hand “\(worker.name)” back to \(director)?",
                detail: "You typed in this session, so \(director) has been holding off. It wants to send:\n\n“\(message.prefix(300))”",
                button: "Hand Back") { yes in
            guard yes else {
                log("refused", hit.path, sid, nil, "the user kept it paused")
                return done(.fail("The user kept it paused, in Duo: don't send it. Ask them what they want instead."))
            }
            var r = DirectorRegistry.load(project: folder)
            r.handedBack[sid] = Self.isoNow()
            try? r.save(project: folder)
            log("handback", hit.path, sid, nil, "the user handed it back in Duo")
            send()
        }
    }

    /// Takes one rung. When Duo's guards refuse before anything was typed, `refused` decides (the
    /// queue's own delivery leaves the message where it is); by default it joins the queue. Text
    /// Duo typed but didn't send stays in the prompt for the user and is never queued as well.
    func carry(_ rung: SendRung, message: String, task: String, project: String, folder: URL, worker: Fixture.Session, facts: WorkerFacts,
               director: String, directedBy: String?, onTask: Bool,
               log: @escaping (String, String?, String?, String?, String?) -> Void, done: @escaping @MainActor (Reply) -> Void,
               refused: (@MainActor (_ why: String, _ typed: Bool) -> Void)? = nil) {
        let sid = worker.sessionId ?? worker.tabKey
        // What Duo delivers carries the director's tag, so the worker's transcript tells it from the user's turns.
        let tagged = Director.tag(director) + message
        func queue(_ why: String? = nil) {
            if let refused { return refused(why ?? "not now", false) }
            self.queue(message, task: task, folder: folder, project: project, why: why, log: log, done: done)
        }
        func delivered(_ how: String) {
            editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Sent to the worker (\(how)): \(message.prefix(300))")))
            log("send", task, sid, rung.rawValue, how)
        }
        switch rung {
        case .message:
            // Duo can't call SendMessage for the director: log that it was handed over, never "delivered" (F-342).
            editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Handed to the director to send (SendMessage; not confirmed delivered, and held if the permission modes differ): \(message.prefix(300))")))
            log("handed", task, sid, rung.rawValue, "handed to the director to send")
            done(.ok("Send it yourself: SendMessage(to: \"\(facts.peerName ?? sid)\"). Logged and noted in Progress as handed to you, not delivered. Messages between sessions in different permission modes are held and can expire unseen: the worker's last message and task note are the channel back, so read them rather than wait.", ["task": task, "worker": sid, "rung": rung.rawValue]))
        case .resumeBackground, .headless:
            guard let claude = ClaudeLocator.resolve() else { return queue("no claude to run") }
            // `--` ends the options: a message starting with "-" is never read as a flag.
            // A worker resumed in the background comes back reachable from the user's phone (DL-230).
            let name = DirectorRegistry.load(project: folder).worker(task: task)?.name
            let rc = rung == .resumeBackground && ClientCaps.probe(env: [:], cwd: nil).remoteControl == .yes ? name.map { ["--remote-control", $0] } ?? [] : []
            let args = (rung == .headless ? ["-p", "--resume", sid] : ["--bg", "--resume", sid] + rc) + ["--", tagged]
            let cwd = workerCwd(worker, folder: folder)
            let runLog = folder.appending(path: ".duo/director-runs/\(sid.prefix(8))-\(Int(Date().timeIntervalSince1970)).log")
            let how = rung == .headless ? "a headless turn" : "resumed in the background"
            let started = Self.runDetached(claude, args, cwd: cwd, log: runLog) { [weak self] status in
                guard let self else { return }
                if status == 0 {
                    delivered(how)
                } else {
                    log("refused", task, sid, rung.rawValue, "exit \(status); see \(runLog.path)")
                    self.editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Not delivered (\(how) ended with \(status); its output is in .duo/director-runs/): \(message.prefix(200))")))
                }
            }
            if let why = started { log("refused", task, sid, rung.rawValue, why); return queue(why) }
            done(.ok(rung == .headless
                     ? "The worker had stopped: it's taking a headless turn with your message, in its own folder. It's logged as sent when the turn ends well; read the answer with `duo2 session show \(sid)`."
                     : "The worker had stopped: it's resuming in the background with your message. It's logged as sent once it has started.",
                     ["task": task, "worker": sid, "rung": rung.rawValue]))
        case .duoSubmit:
            guardedSubmit(key: worker.tabKey, message: tagged, directedBy: directedBy, director: director, onTask: onTask) { refusal, typed in
                if let refusal {
                    if refused == nil || typed { log("refused", task, sid, rung.rawValue, refusal) }
                    if typed {
                        // Typed but not sent: the text stays in the prompt for the user, so it isn't queued too.
                        self.editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Typed into the worker's prompt but not sent (\(refusal)); left there for the user: \(message.prefix(200))")))
                        if let refused { return refused(refusal, true) }
                        return done(.ok("Not sent: \(refusal). Duo's text is left in the worker's prompt for the user to send or clear, so it isn't queued.", ["task": task, "rung": "left-in-prompt"]))
                    }
                    queue(refusal)
                } else {
                    delivered("Duo typed it and pressed Enter")
                    done(.ok("Delivered: Duo typed it into the worker and pressed Enter.", ["task": task, "worker": sid, "rung": rung.rawValue]))
                }
            }
        case .duoResume:
            if let why = resumeWithPrompt(worker, prompt: tagged, folder: folder) { log("refused", task, sid, rung.rawValue, why); return queue(why) }
            delivered("reopened in Duo with it")
            done(.ok("The worker had stopped: Duo reopened it with your message as its next prompt.", ["task": task, "worker": sid, "rung": rung.rawValue]))
        case .queued:
            queue()
        case .askUser:
            log("send", task, sid, rung.rawValue, "no route")
            done(.ok("Duo can't reach this worker now: ask the user to pass it on to session \(sid.prefix(8)).", ["task": task, "worker": sid, "rung": rung.rawValue]))
        }
    }

    func queue(_ message: String, task: String, folder: URL, project: String, why: String?,
               log: (String, String?, String?, String?, String?) -> Void, done: @MainActor (Reply) -> Void) {
        var reg = DirectorRegistry.load(project: folder)
        reg.pending.append(.init(task: task, message: message, at: Self.isoNow()))
        try? reg.save(project: folder)
        editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Waiting to go when the worker is next idle\(why.map { " (\($0))" } ?? ""): \(message.prefix(300))")))
        log("send", task, nil, SendRung.queued.rawValue, why)
        done(.ok("Queued\(why.map { " (\($0))" } ?? ""): Duo sends it when the worker is next idle, and it's noted in Progress.", ["task": task, "rung": SendRung.queued.rawValue]))
    }

    /// Home asking a project's director (DL-197): Duo types it into that director when it's idle.
    /// The target must be the session that project's `.duo/director.json` names now.
    func sendToDirector(_ project: String, message: String, from: String, log: @escaping (String, String?, String?, String?, String?) -> Void,
                        done: @escaping @MainActor (Reply) -> Void) {
        guard let p = self.project(named: project), let folder = liveFolders[p.name], let d = DirectorRegistry.load(project: folder).current else {
            return done(.fail("\(project) has no director: direct its work yourself (DL-197)."))
        }
        guard !message.isEmpty, let s = fixture.sessions.first(where: { $0.sessionId == d.sessionId }) else {
            return done(.fail("\(d.name) isn't a session Duo knows (\(d.sessionId.prefix(8))); ask the user to pass it on."))
        }
        let msg = "From \(from): \(message)"
        let isTheirs = DirectorRegistry.load(project: folder).current?.sessionId == s.sessionId
        guardedSubmit(key: s.tabKey, message: msg, directedBy: d.name, director: d.name, onTask: isTheirs) { refusal, typed in
            log("send", nil, d.sessionId, refusal == nil ? SendRung.duoSubmit.rawValue : SendRung.askUser.rawValue, refusal.map { "to \(d.name): \($0)" } ?? "to \(d.name)")
            if refusal == nil { return done(.ok("Delivered to \(d.name).")) }
            done(.ok("\(d.name) can't take it now (\(refusal!))\(typed ? "; Duo's text is left in its prompt" : ""): try again later, or use SendMessage(to: \"\(d.name)\") if you have it."))
        }
    }

    // MARK: The guarded Enter

    /// What the screen check reads from a worker's terminal: Claude at its prompt, and the prompt's text.
    public struct PromptRead: Equatable { public var idle: Bool; public var input: String
        public init(idle: Bool, input: String) { self.idle = idle; self.input = input } }

    /// Reads a live terminal's screen as chat mode does (the model chip's reader, DL-168).
    func readPrompt(_ t: TerminalSession) -> PromptRead {
        let term = LiveChatTerminal(t.view)
        let version = ClaudeLocator.resolve().flatMap { ClaudeVersion.cached($0) ?? nil }
        let s = ChatScreenReader.read(lines: term.screenLines(), cols: term.columns, table: ChatSignatures.table(for: version).table)
        return PromptRead(idle: s.kind == .idle, input: (s.input ?? "").trimmingCharacters(in: .whitespaces))
    }

    /// Types `message` into an idle worker and presses Enter, only if every guard holds (SubmitGuard),
    /// before typing and again before Enter. `then(nil, true)` once sent; else why not, and whether
    /// Duo had already typed (that text is left in the prompt). `directedBy` and `onTask` are the
    /// real state (the note's `directed_by:`, `.duo/director.json`'s worker), so the guards bite.
    /// Hooks for the checks: `submitHooks` replaces the terminal reads and writes.
    public func guardedSubmit(key: String, message: String, directedBy: String?, director: String, onTask: Bool,
                       then: @escaping @MainActor (_ refusal: String?, _ typed: Bool) -> Void) {
        let io = submitHooks ?? liveSubmitIO(key)
        guard let io else { return then("it isn't running in Duo", false) }
        let read0 = io.read()
        let before = SubmitGuard.Facts(directedBy: directedBy, director: director, onTask: onTask, idle: io.beaconIdle() && read0.idle,
                                       promptEmpty: read0.input.isEmpty, lastUserKey: UserTyping.lastKey(key), now: Date())
        if let why = SubmitGuard.refusal(before) { return then(why, false) }
        let typedAt = UserTyping.lastKey(key)
        io.type(TerminalSession.bracketed(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + io.settle) {
            MainActor.assumeIsolated {
                let read = io.read()
                // The prompt must now hold the message (as typed, not some other text), Claude must
                // still be idle, and the user mustn't have typed in between.
                let shown = read.input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let want = String(SendFormat.clean(message).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(24))
                guard UserTyping.lastKey(key) == typedAt else { return then("the user typed there while Duo was typing", true) }
                guard io.beaconIdle(), read.idle else { return then("Claude stopped being idle while Duo typed", true) }
                guard !want.isEmpty, shown.hasPrefix(want) || shown.contains(want) || read.input.contains("[Pasted text") else {
                    return then("the prompt didn't show the message after typing", true)
                }
                io.type("\r")
                then(nil, true)
            }
        }
    }

    /// The terminal side of a guarded submit.
    public struct SubmitIO {
        public var read: @MainActor () -> PromptRead
        public var beaconIdle: @MainActor () -> Bool
        public var type: @MainActor (String) -> Void
        public var settle: TimeInterval = 0.35
        public init(read: @escaping @MainActor () -> PromptRead, beaconIdle: @escaping @MainActor () -> Bool, type: @escaping @MainActor (String) -> Void, settle: TimeInterval = 0.35) {
            self.read = read; self.beaconIdle = beaconIdle; self.type = type; self.settle = settle
        }
    }

    func liveSubmitIO(_ key: String) -> SubmitIO? {
        guard let t = terminals.existing(key), t.isLiveClaude else { return nil }
        return SubmitIO(read: { [weak self] in self?.readPrompt(t) ?? PromptRead(idle: false, input: "?") },
                        beaconIdle: { t.notReadyReason == nil && Beacon.readAll().contains { $0.pid == t.view.process?.shellPid && $0.status == "idle" } },
                        type: { t.view.send(txt: $0) })
    }

    /// Reopens a stopped worker in its tab with `prompt` as its next message
    /// (`claude --resume <id> -- <prompt>`), in its own folder, without showing it or taking the
    /// keyboard. Nil, or why not.
    func resumeWithPrompt(_ s: Fixture.Session, prompt: String, folder: URL) -> String? {
        guard let id = s.sessionId else { return "no session id" }
        if liveElsewhere.contains(id) || s.liveProcess == true { return "it's running" }
        if let t = terminals.existing(s.tabKey) {
            if t.isLiveClaude { return "it's running in Duo" }
            terminals.forget(s.tabKey)
            endedRevision += 1
        }
        let cwd = workerCwd(s, folder: folder)
        guard ClaudeStorage.transcript(sessionId: id, cwd: cwd) != nil else { return "its transcript is gone" }
        parkedTabs.remove(s.tabKey)
        _ = terminals.session(s.tabKey, command: .resumeClaude(sessionID: id, remoteControl: s.remoteControl, prompt: prompt), cwd: cwd)
        return nil
    }

    /// Where a worker runs: its terminal's folder, else the folder its transcript is filed under
    /// (a worktree, after any /cd), else the project's.
    func workerCwd(_ s: Fixture.Session, folder: URL) -> String {
        if let c = cwd(of: s.tabKey) { return c }
        if let id = s.sessionId, let t = ClaudeStorage.transcript(sessionId: id, cwd: folder.path), let c = ClaudeStorage.filedCwd(t),
           FileManager.default.fileExists(atPath: c) { return c }
        return folder.path
    }

    /// Starts `claude` with `args` in `cwd`, not waited on (a headless turn, a background resume).
    /// Its output goes to `log`; `onExit` gets its status on the main actor. Nil, or why it didn't start.
    public static func runDetached(_ program: String, _ args: [String], cwd: String, log: URL,
                            onExit: @escaping @MainActor (Int32) -> Void) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: program)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("DUO_") || k == "CLAUDECODE" || k.hasPrefix("CLAUDE_CODE_SESSION") { env.removeValue(forKey: k) }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        pruneRuns(beside: log)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let out = try? FileHandle(forWritingTo: log)
        p.standardOutput = out ?? FileHandle.nullDevice
        p.standardError = out ?? FileHandle.nullDevice
        p.terminationHandler = { proc in
            let status = proc.terminationStatus
            try? out?.close()
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status) } }
        }
        do { try p.run() } catch { return error.localizedDescription }
        return nil
    }

    /// Keeps the newest few run logs per worker in `.duo/director-runs/` (named `<id8>-<time>.log`).
    public static let runsKept = 5
    public static func pruneRuns(beside log: URL) {
        let dir = log.deletingLastPathComponent(), prefix = String(log.lastPathComponent.prefix(9))
        let fm = FileManager.default
        let mine = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(prefix) && $0.hasSuffix(".log") }.sorted()
        for old in mine.dropLast(runsKept - 1) { try? fm.removeItem(at: dir.appending(path: old)) }
    }

    /// Takes workers whose task is done, dropped, archived or gone off the registry, links pending
    /// background workers whose session has appeared, and expires pending ones that never did.
    func pruneDirectorWorkers(_ folder: URL) {
        var reg = DirectorRegistry.load(project: folder)
        let before = reg
        let iso = ISO8601DateFormatter()
        // A worker started in the background is linked when a session with its name appears.
        var linked: [DirectorRegistry.Worker] = []
        let beacons = reg.workers.contains(where: \.pending) ? Beacon.readAll() : []
        for b in beacons { if let n = b.name, let w = reg.link(pendingNamed: n, to: b.sessionId) { linked.append(w) } }
        reg.workers.removeAll { w in
            guard DirectorRegistry.isTaskPath(w.task), let text = try? String(contentsOf: folder.appending(path: w.task), encoding: .utf8) else { return true }
            let n = TaskNotes.parse(text, path: w.task)
            if n.archived || ["done", "dropped"].contains((n.status ?? "").lowercased()) { return true }
            // One that never appeared frees its slot.
            if w.pending, let since = iso.date(from: w.since), Date().timeIntervalSince(since) > Director.pendingLasts { return true }
            return false
        }
        // Hand-backs go with their workers.
        let live = Set(reg.workers.map(\.session))
        reg.handedBack = reg.handedBack.filter { live.contains($0.key) }
        if reg != before { try? reg.save(project: folder) }
        if let project = liveFolders.first(where: { $0.value == folder })?.key {
            for w in linked where reg.workers.contains(w) {
                _ = editTaskNote(project, w.task, .addSession(link: TaskNotes.link(title: w.name ?? w.session, id: w.session)))
                _ = editTaskNote(project, w.task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Worker \(w.session.prefix(8)) (\(w.name ?? "")) started in the background.")))
            }
        }
    }

    // MARK: The queue

    /// Delivers messages waiting for idle workers (each refresh). A message whose worker is gone,
    /// or whose task no longer names its director, is dropped with a Progress line; one naming a
    /// path outside `tasks/` is dropped untouched.
    public func deliverDirectorMessages() {
        for (project, folder) in liveFolders {
            guard FileManager.default.fileExists(atPath: DirectorRegistry.file(project: folder).path) else { continue }
            pruneDirectorWorkers(folder)
            let reg = DirectorRegistry.load(project: folder)
            guard let first = reg.pending.first, let director = reg.current?.name, !deliveringDirector.contains(project) else { continue }
            let drop: (String) -> Void = { [weak self] why in
                var r = DirectorRegistry.load(project: folder)
                r.pending.removeAll { $0 == first }
                try? r.save(project: folder)
                self?.editTaskNote(project, first.task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Not delivered (\(why)): \(first.message.prefix(200))")))
                DirectorLog.append(DirectorEvent(at: Self.isoNow(), director: director, event: "dropped", task: first.task, detail: why), project: folder)
            }
            guard DirectorRegistry.isTaskPath(first.task) else { drop("not a note in tasks/"); continue }
            guard let t = directedTasks(project, folder: folder, director: director).first(where: { $0.note.path == first.task }) else { drop("the task isn't this director's any more"); continue }
            guard let w = t.worker, let f = t.facts else { drop("no worker"); continue }
            if f.userTyping { continue }   // paused until the user hands it back (DL-200)
            let rung = SendLadder.choose(director: ClientCaps(), worker: f, duoRunning: true)
            guard rung != .queued, rung != .askUser else { continue }
            deliveringDirector.insert(project)
            let onTask = reg.worker(task: first.task)?.session == w.sessionId
            carry(rung, message: first.message, task: first.task, project: project, folder: folder, worker: w, facts: f, director: director,
                  directedBy: DirectorNotes.directedBy(t.text), onTask: onTask,
                  log: { e, task, worker, rung, detail in
                      DirectorLog.append(DirectorEvent(at: Self.isoNow(), director: director, event: e == "send" && rung != SendRung.queued.rawValue ? "delivered" : e,
                                                       task: task, worker: worker, rung: rung, detail: detail), project: folder)
                  }, done: { [weak self] _ in
                      self?.deliveringDirector.remove(project)
                      var now = DirectorRegistry.load(project: folder)
                      if let i = now.pending.firstIndex(of: first) { now.pending.remove(at: i) }
                      try? now.save(project: folder)
                  }, refused: { [weak self] _, typed in
                      self?.deliveringDirector.remove(project)
                      // Typed but not sent: the text is in the prompt now, so this copy goes.
                      if typed {
                          var now = DirectorRegistry.load(project: folder)
                          if let i = now.pending.firstIndex(of: first) { now.pending.remove(at: i) }
                          try? now.save(project: folder)
                      }
                      // Otherwise (the prompt has text, Claude got busy) it stays first in line.
                  })
        }
    }
}
