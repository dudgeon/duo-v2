import AppKit
import DuoControl
import Foundation

/// DL-199: Duo carries a director's messages where sessions can't message each other. This is new
/// ground: Duo presses Enter for a director, so every way in goes through `SubmitGuard` and the
/// screen check below, and every send is logged with its rung and noted in the task's Progress.
extension AppModel {
    func directorSend(_ p: Fixture.Project, folder: URL, inv: Invocation, director: String, caps: ClientCaps,
                      log: @escaping (String, String?, String?, String?, String?) -> Void, done: @escaping @MainActor (Reply) -> Void) {
        if let target = inv.flags["director"] {
            return sendToDirector(target, message: inv.text, from: director, log: log, done: done)
        }
        guard let t = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(ActionID.directorSend.action.usage)")) }
        let message = inv.positional.dropFirst().joined(separator: " ")
        guard let hit = findTask(t, project: p.name) else { return done(.fail("no task '\(t)' in \(p.name)")) }
        let text = (try? String(contentsOf: folder.appending(path: hit.path), encoding: .utf8)) ?? ""
        guard DirectorNotes.directedBy(text) == director else {
            let by = DirectorNotes.directedBy(text)
            log("refused", hit.path, nil, nil, by.map { "directed by another director (\($0))" } ?? "not a directed task")
            return done(.fail(by.map { "\(hit.title) is directed by \($0), not you." } ?? "\(hit.title) has no directed_by:, so its sessions are the user's: never task them (DL-200)."))
        }
        guard let worker = directedTasks(p.name, folder: folder, director: director).first(where: { $0.note.path == hit.path })?.worker,
              let sid = worker.sessionId else {
            return done(.fail("\(hit.title) has no worker yet: `duo2 director start \(hit.path)`."))
        }
        if inv.has("handed-back") { UserTyping.noteDirectorSend(worker.tabKey) }
        let facts = workerFacts(worker)
        if facts.userTyping {
            log("refused", hit.path, sid, nil, "the user typed into the worker")
            return done(.fail("The user typed into this worker since your last message, so you're paused there (DL-200). Ask them; if they hand it back, send again with --handed-back."))
        }
        let rung = SendLadder.choose(director: caps, worker: facts, duoRunning: true)
        carry(rung, message: message, task: hit.path, project: p.name, folder: folder, worker: worker, facts: facts, director: director, log: log, done: done)
    }

    /// Takes one rung. When Duo's guards refuse, `refused` decides (the queue's own delivery leaves
    /// the message where it is); by default it joins the queue.
    func carry(_ rung: SendRung, message: String, task: String, project: String, folder: URL, worker: Fixture.Session, facts: WorkerFacts,
               director: String, log: @escaping (String, String?, String?, String?, String?) -> Void, done: @escaping @MainActor (Reply) -> Void,
               refused: (@MainActor (String) -> Void)? = nil) {
        let sid = worker.sessionId ?? worker.tabKey
        func queue(_ why: String? = nil) {
            if let refused { return refused(why ?? "not now") }
            self.queue(message, task: task, folder: folder, project: project, why: why, log: log, done: done)
        }
        func sent(_ how: String, _ reply: String) {
            UserTyping.noteDirectorSend(worker.tabKey)
            editTaskNote(project, task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Sent to the worker (\(how)): \(message.prefix(300))")))
            log("send", task, sid, rung.rawValue, how)
            done(.ok(reply, ["task": task, "worker": sid, "rung": rung.rawValue]))
        }
        switch rung {
        case .message:
            sent("SendMessage", "Send it yourself: SendMessage(to: \"\(facts.peerName ?? sid)\"). Logged and noted in Progress.")
        case .resumeBackground, .headless:
            guard let claude = ClaudeLocator.resolve() else { return queue() }
            let args = rung == .headless ? ["-p", "--resume", sid, message] : ["--bg", "--resume", sid, message]
            if let why = Self.runDetached(claude, args, cwd: folder.path) { log("refused", task, sid, rung.rawValue, why); return queue(why) }
            sent(rung == .headless ? "a headless turn" : "resumed in the background", rung == .headless
                 ? "The worker had stopped: it's taking a headless turn with your message (claude -p --resume). Read its answer with `duo2 session show \(sid)`."
                 : "The worker had stopped: it's resumed in the background with your message.")
        case .duoSubmit:
            guardedSubmit(key: worker.tabKey, message: message, directedBy: director, director: director, onTask: true) { refusal in
                if let refusal {
                    if refused == nil { log("refused", task, sid, rung.rawValue, refusal) }
                    queue(refusal)
                } else {
                    sent("Duo typed it and pressed Enter", "Delivered: Duo typed it into the worker and pressed Enter.")
                }
            }
        case .duoResume:
            if let why = resumeWithPrompt(worker, prompt: message, folder: folder) { log("refused", task, sid, rung.rawValue, why); return queue(why) }
            sent("reopened in Duo with it", "The worker had stopped: Duo reopened it with your message as its next prompt.")
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
    func sendToDirector(_ project: String, message: String, from: String, log: @escaping (String, String?, String?, String?, String?) -> Void,
                        done: @escaping @MainActor (Reply) -> Void) {
        guard let p = self.project(named: project), let folder = liveFolders[p.name], let d = DirectorRegistry.load(project: folder).current else {
            return done(.fail("\(project) has no director: direct its work yourself (DL-197)."))
        }
        guard !message.isEmpty, let s = fixture.sessions.first(where: { $0.sessionId == d.sessionId }) else {
            return done(.fail("\(d.name) isn't a session Duo knows (\(d.sessionId.prefix(8))); ask the user to pass it on."))
        }
        let msg = "From \(from): \(message)"
        guardedSubmit(key: s.tabKey, message: msg, directedBy: from, director: from, onTask: true) { refusal in
            log("send", nil, d.sessionId, refusal == nil ? SendRung.duoSubmit.rawValue : SendRung.askUser.rawValue, refusal.map { "to \(d.name): \($0)" } ?? "to \(d.name)")
            done(refusal == nil ? .ok("Delivered to \(d.name).") : .ok("\(d.name) can't take it now (\(refusal!)): try again later, or use SendMessage(to: \"\(d.name)\") if you have it."))
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
    /// before typing and again before Enter. `then(nil)` once sent; else why not. Hooks for the checks:
    /// `submitHooks` replaces the terminal reads and writes.
    func guardedSubmit(key: String, message: String, directedBy: String?, director: String, onTask: Bool,
                       then: @escaping @MainActor (String?) -> Void) {
        let io = submitHooks ?? liveSubmitIO(key)
        guard let io else { return then("it isn't running in Duo") }
        func facts(_ read: PromptRead) -> SubmitGuard.Facts {
            SubmitGuard.Facts(directedBy: directedBy, director: director, onTask: onTask, idle: io.beaconIdle() && read.idle,
                              promptEmpty: read.input.isEmpty, lastUserKey: UserTyping.lastKey(key), now: Date())
        }
        if let why = SubmitGuard.refusal(facts(io.read())) { return then(why) }
        let typedAt = UserTyping.lastKey(key)
        io.type(TerminalSession.bracketed(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + io.settle) {
            MainActor.assumeIsolated {
                let read = io.read()
                // The prompt must now hold the message (as typed, not some other text), Claude must
                // still be idle, and the user mustn't have typed in between.
                let shown = read.input.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let want = String(SendFormat.clean(message).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(24))
                guard UserTyping.lastKey(key) == typedAt else { return then("the user typed there while Duo was typing; left in the prompt, not sent") }
                guard io.beaconIdle(), read.idle else { return then("Claude stopped being idle while Duo typed; left in the prompt, not sent") }
                guard !want.isEmpty, shown.hasPrefix(want) || shown.contains(want) || read.input.contains("[Pasted text") else {
                    return then("the prompt didn't show the message after typing; left there, not sent")
                }
                io.type("\r")
                then(nil)
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

    /// Reopens a stopped worker in its tab with `prompt` as its next message (`claude --resume <id> <prompt>`),
    /// without showing it or taking the keyboard. Nil, or why not.
    func resumeWithPrompt(_ s: Fixture.Session, prompt: String, folder: URL) -> String? {
        guard let id = s.sessionId else { return "no session id" }
        if liveElsewhere.contains(id) || s.liveProcess == true { return "it's running" }
        if let t = terminals.existing(s.tabKey) {
            if t.isLiveClaude { return "it's running in Duo" }
            terminals.forget(s.tabKey)
            endedRevision += 1
        }
        guard ClaudeStorage.transcript(sessionId: id, cwd: folder.path) != nil else { return "its transcript is gone" }
        parkedTabs.remove(s.tabKey)
        _ = terminals.session(s.tabKey, command: .resumeClaude(sessionID: id, remoteControl: s.remoteControl, prompt: prompt), cwd: folder.path)
        return nil
    }

    /// Starts `claude` with `args` in `cwd`, not waited on (a headless turn, a background resume).
    static func runDetached(_ program: String, _ args: [String], cwd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: program)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("DUO_") || k == "CLAUDECODE" || k.hasPrefix("CLAUDE_CODE_SESSION") { env.removeValue(forKey: k) }
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return error.localizedDescription }
        return nil
    }

    // MARK: The queue

    /// Delivers messages waiting for idle workers (each refresh). A message whose worker is gone,
    /// or whose task no longer names its director, is dropped with a Progress line.
    public func deliverDirectorMessages() {
        for (project, folder) in liveFolders {
            guard FileManager.default.fileExists(atPath: DirectorRegistry.file(project: folder).path) else { continue }
            let reg = DirectorRegistry.load(project: folder)
            guard let first = reg.pending.first, let director = reg.current?.name, !deliveringDirector.contains(project) else { continue }
            let drop: (String) -> Void = { [weak self] why in
                var r = DirectorRegistry.load(project: folder)
                r.pending.removeAll { $0 == first }
                try? r.save(project: folder)
                self?.editTaskNote(project, first.task, .appendLine(section: "Progress", line: DirectorNotes.progressLine("Not delivered (\(why)): \(first.message.prefix(200))")))
                DirectorLog.append(DirectorEvent(at: Self.isoNow(), director: director, event: "dropped", task: first.task, detail: why), project: folder)
            }
            guard let t = directedTasks(project, folder: folder, director: director).first(where: { $0.note.path == first.task }) else { drop("the task isn't this director's any more"); continue }
            guard let w = t.worker, let f = t.facts else { drop("no worker"); continue }
            if f.userTyping { continue }   // paused until the user hands it back (DL-200)
            let rung = SendLadder.choose(director: ClientCaps(), worker: f, duoRunning: true)
            guard rung != .queued, rung != .askUser else { continue }
            deliveringDirector.insert(project)
            carry(rung, message: first.message, task: first.task, project: project, folder: folder, worker: w, facts: f, director: director,
                  log: { e, task, worker, rung, detail in
                      DirectorLog.append(DirectorEvent(at: Self.isoNow(), director: director, event: e == "send" && rung != SendRung.queued.rawValue ? "delivered" : e,
                                                       task: task, worker: worker, rung: rung, detail: detail), project: folder)
                  }, done: { [weak self] _ in
                      self?.deliveringDirector.remove(project)
                      var now = DirectorRegistry.load(project: folder)
                      if let i = now.pending.firstIndex(of: first) { now.pending.remove(at: i) }
                      try? now.save(project: folder)
                  }, refused: { [weak self] _ in
                      // Not now (the prompt has text, Claude got busy): it stays first in line.
                      self?.deliveringDirector.remove(project)
                  })
        }
    }
}
