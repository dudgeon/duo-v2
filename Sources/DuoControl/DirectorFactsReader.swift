import Foundation

// Reading the facts the red lines are computed from (DL-319): task notes, the registry, Claude's
// beacons and transcripts, the director log, the Claude desktop app's scheduled-task records. All of
// it is readable with Duo closed, and `duo2` and the app call the same functions, so `director status`
// has one implementation of the report (the design doc, §2). Foundation only.

// MARK: - Dates in notes

/// A task note's `## Progress`: the dates on its lines, and which of them are `Checked:` lines.
public enum DirectorProgress {
    public struct Dates: Equatable, Sendable {
        /// The latest date on any dated line.
        public var lastProgress: Date?
        /// The latest date on a line whose text after the date starts `Checked:` or `Checked (routine):`.
        public var lastChecked: Date?
        public init(lastProgress: Date? = nil, lastChecked: Date? = nil) { self.lastProgress = lastProgress; self.lastChecked = lastChecked }
    }

    static let line = try! NSRegularExpression(pattern: #"^\s*[-*+]\s+(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?(?!\d)(.*)$"#)

    /// A line is `- YYYY-MM-DD` or `- YYYY-MM-DD HH:mm`, local time. A day-only date counts as the end
    /// of that day and a minute-precise one as the end of that minute, so a `Checked:` line never reads
    /// as older than the report it was written after. Lines outside `## Progress` are ignored.
    public static func parse(_ text: String, calendar: Calendar = .current) -> Dates {
        var d = Dates()
        guard let body = Director.section("Progress", in: text) else { return d }
        for l in body.components(separatedBy: "\n") {
            let ns = l as NSString
            guard let m = line.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { continue }
            func n(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
            guard let y = n(1), let mo = n(2), let day = n(3), let at = date(y, mo, day, n(4), n(5), calendar: calendar) else { continue }
            if d.lastProgress.map({ at > $0 }) ?? true { d.lastProgress = at }
            let rest = ns.substring(with: m.range(at: 6)).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("Checked:") || rest.hasPrefix("Checked (routine):"), d.lastChecked.map({ at > $0 }) ?? true { d.lastChecked = at }
        }
        return d
    }

    /// The end of a day (no hour) or of a minute, or nil for a date that doesn't exist.
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int?, _ mi: Int?, calendar: Calendar) -> Date? {
        var c = DateComponents(year: y, month: mo, day: d)
        if let h, let mi { c.hour = h; c.minute = mi }
        guard let start = calendar.date(from: c) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        guard back.year == y, back.month == mo, back.day == d, h == nil || back.hour == h, mi == nil || back.minute == mi else { return nil }
        return h == nil ? calendar.date(byAdding: .day, value: 1, to: start) : start.addingTimeInterval(60)
    }
}

/// `check_by:` (when the director will next look), and `--next` (when it says it will).
public enum CheckBy {
    /// What `--next` accepts, for the refusal.
    public static let accepted = "30m, 2h or 3d from now, a date or time (2026-11-09, 2026-11-09T14:30 or a full ISO time), or none"

    /// A note's `check_by:` value: `yyyy-MM-dd'T'HH:mm:ss`, `yyyy-MM-dd'T'HH:mm` or `yyyy-MM-dd HH:mm`
    /// (local), full ISO-8601 with an offset, or `yyyy-MM-dd` (the end of that day). Empty or anything
    /// else is nil.
    public static func parse(_ raw: String?, calendar: Calendar = .current) -> Date? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let m = s.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/) {
            return DirectorProgress.date(Int(m.1)!, Int(m.2)!, Int(m.3)!, nil, nil, calendar: calendar)
        }
        if let m = s.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/) {
            var c = DateComponents(year: Int(m.1)!, month: Int(m.2)!, day: Int(m.3)!, hour: Int(m.4)!, minute: Int(m.5)!, second: m.6.map { Int($0)! } ?? 0)
            c.timeZone = calendar.timeZone
            guard let d = calendar.date(from: c) else { return nil }
            let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            guard back.year == c.year, back.month == c.month, back.day == c.day, back.hour == c.hour, back.minute == c.minute, back.second == c.second else { return nil }
            return d
        }
        return DirectorTranscript.parseDate(s)
    }

    /// What Duo writes: `yyyy-MM-dd'T'HH:mm:ss`, local and unquoted (Obsidian's datetime format).
    public static func format(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }

    /// `2026-11-09 14:30`, for the verbs' output.
    public static func display(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    public enum NextLook: Equatable, Sendable {
        case none
        case at(Date)
    }

    public struct NextError: Error, CustomStringConvertible, Equatable {
        public var description: String
    }

    /// `--next`: `30m`, `2h`, `3d` (from `now`), any `check_by` form, or `none`. Anything else is an error.
    public static func parseNext(_ raw: String, now: Date, calendar: Calendar = .current) throws -> NextLook {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.lowercased() == "none" { return .none }
        if let m = s.lowercased().wholeMatch(of: /(\d+)([mhd])/), let n = Int(m.1), n >= 1 {
            let unit: TimeInterval = m.2 == "m" ? 60 : m.2 == "h" ? 3600 : 86400
            return .at(now.addingTimeInterval(Double(n) * unit))
        }
        if let d = parse(s, calendar: calendar) { return .at(d) }
        throw NextError(description: "--next takes \(accepted); '\(raw)' is none of those")
    }
}

// MARK: - The check verb's parts, shared by duo2 and the app

public enum DirectorCheck {
    public static let emptyRefusal = "a check needs what you verified and the evidence"
    /// The evidence's first characters, as the log keeps them.
    public static let detailLength = 200

    /// `job:<id>`'s id, or nil for a task.
    public static func jobID(_ target: String) -> String? {
        target.hasPrefix("job:") ? String(target.dropFirst(4)).trimmingCharacters(in: .whitespaces) : nil
    }

    /// `session:<id>`'s id (a session the registry doesn't know, Q-562), or nil.
    public static func sessionID(_ target: String) -> String? {
        target.hasPrefix("session:") ? String(target.dropFirst(8)).trimmingCharacters(in: .whitespaces) : nil
    }

    /// The Progress line's text: `Checked: <evidence>`, or `Checked (routine): <evidence>`.
    public static func progressText(evidence: String, routine: Bool) -> String { (routine ? "Checked (routine): " : "Checked: ") + evidence }

    public static func logDetail(_ evidence: String) -> String { String(evidence.prefix(detailLength)) }

    /// Where check_by goes after a check: `--next` if given; else a day on, unless the task is done or
    /// dropped. nil means the key is cleared (`--next none`, or a finished task).
    public static func checkBy(next: CheckBy.NextLook?, status: String?, now: Date) -> Date? {
        switch next {
        case .none?: return nil
        case .at(let d)?: return d
        case nil:
            let s = (status ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return s == "done" || s == "dropped" ? nil : now.addingTimeInterval(24 * 3600)
        }
    }

    /// Where check_by goes when a worker (or the director itself) starts on a task: `--next` if given, else two hours on.
    public static func startCheckBy(next: CheckBy.NextLook?, now: Date) -> Date? {
        switch next {
        case .none?: return nil
        case .at(let d)?: return d
        case nil: return now.addingTimeInterval(2 * 3600)
        }
    }

    public static func output(_ target: String, nextLook: Date?) -> String {
        "Checked \(target). " + (nextLook.map { "Next look by \(CheckBy.display($0))." } ?? "No next look set.")
    }
}

// MARK: - Duo's health

/// R8's Duo facts. Never read in a test context: a scripted run asks nothing about the user's own Duo.
public enum DuoHealthReader {
    public static let bundleID = "com.dudgeon.duo"

    /// Duo reached from duo2: running and reachable (the app's own path never spawns a process).
    public static func reachable(env: [String: String] = ProcessInfo.processInfo.environment) -> DirectorFacts.DuoHealth {
        DirectorFacts.DuoHealth(running: true, reachable: true, cpu: nil, lastUpdateCheck: lastUpdateCheck(env: env))
    }

    /// duo2 couldn't reach Duo: is a Duo running anyway (a second instance, an old build)? nil in a test
    /// context or on a scratch home, where the Duo that `ps` shows isn't what the run is about.
    public static func unreachable(env: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval = 2) -> DirectorFacts.DuoHealth? {
        if Isolation.isStrict(env) || Isolation.scratchHome(env) { return nil }
        let found = duoProcesses(psOutput(timeout: timeout) ?? "")
        return DirectorFacts.DuoHealth(running: !found.isEmpty, reachable: false, cpu: found.map { $0.cpu }.max(), lastUpdateCheck: lastUpdateCheck(env: env))
    }

    /// The Duo.app processes in `ps -axo pcpu=,comm=` output: the installed app's, never a build or a work tree's.
    public static func duoProcesses(_ ps: String) -> [(cpu: Double, path: String)] {
        ps.split(separator: "\n").compactMap { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(where: { $0 == " " || $0 == "\t" }), let cpu = Double(t[..<sp]) else { return nil }
            let path = t[sp...].trimmingCharacters(in: .whitespaces)
            guard path.hasSuffix("/Duo.app/Contents/MacOS/Duo"), !path.contains("/build/"), !path.contains("/.claude/worktrees/") else { return nil }
            return (cpu, path)
        }
    }

    /// Sparkle's last check, from Duo's preferences (nil when never, or in a test context).
    static func lastUpdateCheck(env: [String: String]) -> Date? {
        if Isolation.isStrict(env) || Isolation.scratchHome(env) { return nil }
        return CFPreferencesCopyAppValue("SULastCheckTime" as CFString, bundleID as CFString) as? Date
    }

    /// `ps`'s output, with a hard stop. It goes to a file, not a pipe: a full pipe would stall `ps` until the timeout.
    static func psOutput(timeout: TimeInterval) -> String? {
        let fm = FileManager.default
        let file = fm.temporaryDirectory.appending(path: "duo-ps-\(UUID().uuidString.prefix(8)).txt")
        guard fm.createFile(atPath: file.path, contents: nil), let out = try? FileHandle(forWritingTo: file) else { return nil }
        defer { try? fm.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pcpu=,comm="]
        p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { try? out.close(); return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(10_000) }
        if p.isRunning { p.terminate(); try? out.close(); return nil }
        try? out.close()
        return try? String(contentsOf: file, encoding: .utf8)
    }
}

// MARK: - The facts

public enum DirectorFactsReader {
    /// Whether the report applies to a caller: the project's director, a session that could become it
    /// (nobody directs), or the director resumed under a new session id. Not a director that was
    /// replaced, nor one working in another director's project.
    /// `overseers` are the directors the user named to read this project's (DL-342, `DirectorInbox.overseers`).
    public static func applies(role: DirectorRegistry.Role, callerName: String?, overseers: [String] = []) -> Bool {
        switch role {
        case .current, .none: return true
        case .other(let c): return callerName != nil && (c.name == callerName || overseers.contains(callerName!))
        case .replaced: return false
        }
    }

    /// The installed director skill against this Duo, as `status` words it (nil when they match).
    public static func skillNote() -> String? {
        let installed = (try? String(contentsOf: Installer.directorSkillFile, encoding: .utf8)) ?? (try? String(contentsOf: Installer.directorAliasFile, encoding: .utf8))
        return DirectorSkill.versionNote(installed: installed)
    }

    public static func report(project: URL, director: String, reg: DirectorRegistry, beacons: [DirectorOffline.LiveSession], caps: ClientCaps,
                              skillNote: String?, duo: DirectorFacts.DuoHealth?, claudeDir: URL = LegacyDuo.claudeDir,
                              appDir: URL? = ClaudeDesktop.directory(), now: Date = Date(), all: Bool = false) -> [RedLine] {
        DirectorRedLines.evaluate(facts(project: project, director: director, reg: reg, beacons: beacons, caps: caps, skillNote: skillNote, duo: duo,
                                        claudeDir: claudeDir, appDir: appDir, now: now), all: all)
    }

    public static func facts(project: URL, director: String, reg: DirectorRegistry, beacons: [DirectorOffline.LiveSession], caps: ClientCaps,
                             skillNote: String?, duo: DirectorFacts.DuoHealth?, claudeDir: URL = LegacyDuo.claudeDir,
                             appDir: URL? = ClaudeDesktop.directory(), now: Date = Date()) -> DirectorFacts {
        let events = DirectorLog.read(project: project, lastBytes: 4 * 1024 * 1024)
        let inbox = DirectorInbox.read(project: project)
        var notes = DirectorOffline.tasks(project: project, director: director, reg: reg, beacons: beacons, claudeDir: claudeDir, now: now)
            .map { note($0, project: project, director: director, reg: reg, inbox: inbox, claudeDir: claudeDir, now: now) }
        notes += workTreeNotes(project: project, director: director)
        let (jobs, unreadable) = ScheduledRuns.read(appDir: appDir, project: project, events: events, now: now)
        var me = self.me(caps: caps, claudeDir: claudeDir)
        me.skillNote = skillNote
        me.duo = duo
        let sessions = unregisteredSessions(project: project, director: director, reg: reg, beacons: beacons, inbox: inbox, events: events,
                                            caller: caps.sessionId, claudeDir: claudeDir, now: now)
        return DirectorFacts(now: now, notes: notes, jobs: jobs, jobsUnreadable: unreadable, me: me, events: events, inbox: inbox, sessions: sessions, director: director)
    }

    // MARK: Notes

    static func note(_ t: DirectorOffline.Task, project: URL, director: String, reg: DirectorRegistry, inbox: [InboxItem], claudeDir: URL, now: Date) -> DirectorFacts.Note {
        let text = (try? String(contentsOf: project.appending(path: t.path), encoding: .utf8)) ?? ""
        let dates = DirectorProgress.parse(text)
        let w = reg.worker(task: t.path)
        let since = w.flatMap { DirectorTranscript.parseDate($0.since) }
        let url = t.session.flatMap { DirectorOffline.transcript(sessionId: $0, claudeDir: claudeDir) }
        let activity = url.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        var turn = url.flatMap { DirectorTranscript.turnEnd($0, director: director) } ?? .init()
        if let typed = turn.lastUserTurn, inbox.contains(where: { $0.task == t.path && ($0.date ?? .distantPast) >= typed }) { turn.reportedSince = true }
        return DirectorFacts.Note(path: t.path, title: t.title, status: t.status, modified: Date(timeIntervalSince1970: t.noteModified),
                                  checkBy: CheckBy.parse(Director.frontmatter("check_by", in: text)), lastProgress: dates.lastProgress, lastChecked: dates.lastChecked,
                                  inWorkTree: false, workerState: t.state, hasWorkerRecord: w != nil,
                                  pendingExpired: w?.pending == true && since.map { now.timeIntervalSince($0) > Director.pendingLasts } == true,
                                  workerName: t.workerName, question: t.question, workerSince: since, workerLastActivity: activity, userTyping: t.userTyping,
                                  turn: turn, session: t.session)
    }

    // MARK: Sessions the registry doesn't know (Q-562)

    /// The project's Claude folders: its own, and each git work tree's (a worker that moved into one keeps writing there).
    static func claudeFolders(project: URL, claudeDir: URL) -> [URL] {
        var roots = [project.standardizedFileURL.path]
        let admin = project.appending(path: ".git/worktrees")
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: admin.path)) ?? []).sorted() {
            guard let g = (try? String(contentsOf: admin.appending(path: "\(name)/gitdir"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), g.hasPrefix("/") else { continue }
            roots.append(URL(fileURLWithPath: g).deletingLastPathComponent().standardizedFileURL.path)
        }
        return roots.map { claudeDir.appending(path: "projects/" + encode($0)) }
    }

    /// Claude's folder name for a project path (the same rule as DuoKit's `ClaudeStorage.encode`).
    static func encode(_ path: String) -> String {
        let s = String(path.unicodeScalars.map { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) ? Character($0) : "-" })
        guard s.count > 200 else { return s }
        var h: Int32 = 0
        for u in path.utf16 { h = 31 &* h &+ Int32(u) }
        return String(s.prefix(200)) + "-" + String(abs(Int64(h)), radix: 36)
    }

    /// Every session in the project's Claude folders that changed within `Limits.unregisteredWindow`, isn't a
    /// worker the registry knows, a director's own, or the caller, and either starts with this director's tag
    /// or ends on an offer or promise to it. Each transcript's first 16 KB and last 256 KB are read.
    public static func unregisteredSessions(project: URL, director: String, reg: DirectorRegistry, beacons: [DirectorOffline.LiveSession], inbox: [InboxItem],
                                            events: [DirectorEvent], caller: String?, claudeDir: URL, now: Date) -> [DirectorFacts.Session] {
        let fm = FileManager.default
        var known = Set(reg.workers.map(\.session) + reg.retired.map(\.sessionId))
        if let c = reg.current?.sessionId { known.insert(c) }
        if let caller { known.insert(caller) }
        var out: [DirectorFacts.Session] = [], seen = Set<String>()
        for dir in claudeFolders(project: project, claudeDir: claudeDir) {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in files.sorted(by: { $0.path < $1.path }) where url.pathExtension == "jsonl" {
                let id = url.deletingPathExtension().lastPathComponent
                guard !id.isEmpty, !known.contains(id), seen.insert(id).inserted,
                      let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(mod) <= DirectorRedLines.Limits.unregisteredWindow,
                      var turn = DirectorTranscript.turnEnd(url, director: director, tailBytes: 256 * 1024), let typed = turn.lastUserTurn else { continue }
                let promised = DirectorTranscript.promisesDirector(turn.lastText, director: director)
                guard turn.tagged || promised else { continue }
                if inbox.contains(where: { $0.session == id && ($0.date ?? .distantPast) >= typed }) { turn.reportedSince = true }
                let beacon = beacons.first { $0.sessionId == id }
                let check = events.filter { $0.event == "check" && $0.task == "session:\(id)" }.compactMap { DirectorTranscript.parseDate($0.at) }.max()
                out.append(DirectorFacts.Session(id: id, name: beacon?.name, tagged: turn.tagged, promised: promised, working: beacon?.status == "busy", turn: turn, lastCheck: check))
            }
        }
        return out
    }

    /// Notes this director directs that exist only in a git work tree of the project (a branch's own
    /// `tasks/` folder): each of `<project>/.git/worktrees/*`'s work trees, unfinished notes with no
    /// note of that file name in the main checkout. They have no worker facts.
    static func workTreeNotes(project: URL, director: String) -> [DirectorFacts.Note] {
        let fm = FileManager.default
        let admin = project.appending(path: ".git/worktrees")
        var out: [DirectorFacts.Note] = []
        for name in ((try? fm.contentsOfDirectory(atPath: admin.path)) ?? []).sorted() {
            guard let gitFile = (try? String(contentsOf: admin.appending(path: "\(name)/gitdir"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  gitFile.hasPrefix("/") else { continue }
            let root = URL(fileURLWithPath: gitFile).deletingLastPathComponent()
            let tasks = root.appending(path: "tasks")
            let files = ((try? fm.contentsOfDirectory(at: tasks, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension.lowercased() == "md" && !$0.lastPathComponent.hasPrefix("_") }.sorted { $0.path < $1.path }
            for url in files {
                guard !fm.fileExists(atPath: project.appending(path: "tasks/\(url.lastPathComponent)").path),
                      let text = try? String(contentsOf: url, encoding: .utf8), Director.frontmatter("directed_by", in: text) == director,
                      Director.frontmatter("archived", in: text)?.lowercased() != "true" else { continue }
                let status = Director.frontmatter("status", in: text)
                guard Director.unfinished(status: status, archived: false) else { continue }
                let dates = DirectorProgress.parse(text)
                let base = project.standardizedFileURL.path + "/"
                let rel = url.standardizedFileURL.path.hasPrefix(base) ? String(url.standardizedFileURL.path.dropFirst(base.count)) : url.path
                out.append(DirectorFacts.Note(path: rel, title: DirectorOffline.title(of: text, stem: url.deletingPathExtension().lastPathComponent), status: status,
                                              modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
                                              checkBy: CheckBy.parse(Director.frontmatter("check_by", in: text)), lastProgress: dates.lastProgress,
                                              lastChecked: dates.lastChecked, inWorkTree: true))
            }
        }
        return out
    }

    // MARK: The calling director

    /// Its mode and login from `caps`, and its own transcript's tail: when it last spoke to the user
    /// and when this turn began.
    static func me(caps: ClientCaps, claudeDir: URL) -> DirectorFacts.Me {
        var me = DirectorFacts.Me(permissionMode: caps.permissionMode, cliLoggedOut: caps.cliLogin == .no)
        if let sid = caps.sessionId, let t = DirectorOffline.transcript(sessionId: sid, claudeDir: claudeDir), let read = transcriptTail(t) {
            me.transcriptRead = true
            me.lastToUser = read.lastToUser
            me.turnStartedAt = read.turnStartedAt
        }
        return me
    }

    /// The last 512 KB of a transcript: the last assistant entry with text (or an AskUserQuestion,
    /// PushNotification or SendUserFile call), and the last user entry that isn't meta or a tool result.
    /// Subagents' entries (`isSidechain`) are neither. Nil if the file can't be read.
    public static func transcriptTail(_ url: URL, tailBytes: Int = 512 * 1024) -> (lastToUser: Date?, turnStartedAt: Date?)? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let from = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: from)
        guard let data = try? h.readToEnd() else { return nil }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        if from > 0, !lines.isEmpty { lines.removeFirst() }   // a partial line
        let toUser: Set<String> = ["AskUserQuestion", "PushNotification", "SendUserFile"]
        var spoke: Date?, turn: Date?
        for l in lines {
            let isAssistant = l.contains("\"assistant\""), isUser = l.contains("\"user\"") || l.contains("\"queued_command\"")
            guard isAssistant || isUser, let e = (try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any],
                  e["isSidechain"] as? Bool != true, let at = (e["timestamp"] as? String).flatMap(DirectorTranscript.parseDate) else { continue }
            let content = (e["message"] as? [String: Any])?["content"]
            switch e["type"] as? String {
            case "assistant":
                if let s = content as? String { if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { spoke = at } }
                else if let blocks = content as? [[String: Any]], blocks.contains(where: { b in
                    (b["type"] as? String == "text" && !((b["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || (b["type"] as? String == "tool_use" && toUser.contains((b["name"] as? String) ?? ""))
                }) { spoke = at }
            case "user":
                if e["isMeta"] as? Bool == true { continue }
                if let blocks = content as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "tool_result" }) { continue }
                turn = at
            case "attachment":
                if MidTurnPrompt.text(e) != nil { turn = at }   // typed while a turn ran (C-173, F-638)
            default: break
            }
        }
        return (spoke, turn)
    }
}
