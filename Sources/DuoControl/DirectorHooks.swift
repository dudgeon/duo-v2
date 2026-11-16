import Foundation

// The worker and director Stop hooks (DL-342 (2), (3); Q-570, Q-571). `duo2 hook stop` runs at the end of
// every turn of a session that has it (a background worker gets it from `duo2 director start` through
// `claude --bg --settings`; a session Duo starts gets it in its own settings file). It says one thing, once
// per turn (`stop_hook_active`), as `additionalContext`, and never blocks:
//   - a worker whose turn the user drove, or that ends on a question or an offer, and that hasn't reported
//     to its director this turn: report it (`duo2 director report`);
//   - a director with workers in flight or a check_by ahead and no wake armed (no cron, wakeup or Monitor):
//     arm one before it stops.
// Any other session, or anything it can't read, gets nothing. Where hooks are off, the worker skill's rule and
// status's red lines do the same job (F-709). Checked on 2.1.284 with a real background turn (F-710).

public enum DirectorStopHook {
    /// What the hook prints for `payload` (the Stop input), or nil for nothing.
    public static func output(_ payload: [String: Any], claudeDir: URL = LegacyDuo.claudeDir, now: Date = Date()) -> String? {
        guard payload["stop_hook_active"] as? Bool != true, let sid = payload["session_id"] as? String, !sid.isEmpty,
              let cwd = payload["cwd"] as? String, !cwd.isEmpty else { return nil }
        let (project, _) = DirectorPlace.resolve(from: URL(fileURLWithPath: cwd))
        let reg = DirectorRegistry.load(project: project)
        let director = reg.current?.name ?? Director.name(project: project.lastPathComponent)
        let text: String?
        if reg.current?.sessionId == sid {
            text = directorReminder(project: project, director: director, reg: reg, payload: payload, claudeDir: claudeDir, now: now)
        } else {
            text = workerReminder(project: project, director: director, reg: reg, session: sid, payload: payload, claudeDir: claudeDir)
        }
        guard let text else { return nil }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "Stop", "additionalContext": text]]
        return (try? JSONSerialization.data(withJSONObject: out)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// A reply that ends on a question or an offer: a `?` at its end, or "if you agree", "shall I", "want me to", "I'll pass this".
    public static func endsOnAsk(_ text: String?) -> Bool {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        if t.hasSuffix("?") { return true }
        let tail = String(t.suffix(300))
        return tail.range(of: #"(?i)\b(if you agree|if you'd like|if you want|shall i|should i|want me to|would you like|let me know|i['’]ll pass this|say the word|your call)\b"#,
                          options: .regularExpression) != nil
    }

    static func workerReminder(project: URL, director: String, reg: DirectorRegistry, session: String, payload: [String: Any], claudeDir: URL) -> String? {
        let w = reg.workers.first { $0.session == session }
        let transcriptURL = (payload["transcript_path"] as? String).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? DirectorOffline.transcript(sessionId: session, claudeDir: claudeDir)
        guard let url = transcriptURL, let turn = DirectorTranscript.turnEnd(url, director: director) else { return nil }
        guard w != nil || turn.tagged else { return nil }   // not this director's worker
        let userDrove = turn.lastUserTurn != nil
        let asks = endsOnAsk(payload["last_assistant_message"] as? String) || endsOnAsk(turn.lastText)
        guard (userDrove || asks), !turn.reportedSince else { return nil }
        let target = w.map { project.appending(path: $0.task).path } ?? "session"
        let why = userDrove ? "The user drove this turn" : "This turn ends on a question or an offer"
        return "\(why), and it hasn't reached \(director). Before you stop, report it: "
            + "duo2 director report \(Director.shellQuote(target)) \"Asked: … Decided: … Waiting on: <whom> for <what>.\" "
            + "Then wake \(director) with SendMessage as its output says (not needed when nothing waits on anyone). "
            + "If duo2 can't run, send the same with SendMessage(to: \"\(director)\"). Then end your turn as you were going to. (Duo's worker Stop hook; it asks once per turn.)"
    }

    static func directorReminder(project: URL, director: String, reg: DirectorRegistry, payload: [String: Any], claudeDir: URL, now: Date) -> String? {
        let crons = (payload["session_crons"] as? [Any]) ?? []
        let tasks = (payload["background_tasks"] as? [[String: Any]]) ?? []
        // A Monitor, a shell watch or a wakeup will wake it: nothing to say.
        guard crons.isEmpty, !tasks.contains(where: { ["monitor", "shell", "workflow"].contains(($0["type"] as? String) ?? "") }) else { return nil }
        let notes = DirectorOffline.tasks(project: project, director: director, reg: reg, beacons: DirectorOffline.beacons(claudeDir: claudeDir), claudeDir: claudeDir, now: now)
        let running = notes.filter(\.running)
        let ahead = notes.filter { Director.unfinished(status: $0.status, archived: false) }.compactMap { t -> Date? in
            let text = (try? String(contentsOf: project.appending(path: t.path), encoding: .utf8)) ?? ""
            return CheckBy.parse(Director.frontmatter("check_by", in: text)).flatMap { $0 > now ? $0 : nil }
        }.min()
        guard !running.isEmpty || ahead != nil else { return nil }
        var what: [String] = []
        if !running.isEmpty { what.append(running.count == 1 ? "a worker in flight" : "\(running.count) workers in flight") }
        if let ahead { what.append("a check_by at \(CheckBy.display(ahead))") }
        return "Before you stop: you have \(what.joined(separator: " and ")), and no wake is armed (no cron, wakeup or Monitor in this session). "
            + "Arm one (ScheduleWakeup for \(ahead.map(CheckBy.display) ?? "your next look"), or Monitor on duo2 director watch), or say to the user why you don't need one. "
            + "Workers' reports wait in the inbox either way. (Duo's director Stop hook: a reminder, once per turn; it never blocks.)"
    }

    /// StopFailure (an API error ended the turn): a worker's failure goes into its director's inbox, so it isn't lost. Returns what it wrote.
    @discardableResult
    public static func recordFailure(_ payload: [String: Any], now: Date = Date()) -> InboxItem? {
        guard let sid = payload["session_id"] as? String, let cwd = payload["cwd"] as? String else { return nil }
        let (project, _) = DirectorPlace.resolve(from: URL(fileURLWithPath: cwd))
        let reg = DirectorRegistry.load(project: project)
        guard reg.current?.sessionId != sid, let w = reg.workers.first(where: { $0.session == sid }) else { return nil }
        let error = [payload["error"] as? String, payload["error_details"] as? String].compactMap { $0 }.joined(separator: ": ")
        return try? DirectorReport.record(target: project.appending(path: w.task).path,
                                          text: "The worker's turn ended on an API error (\(error.isEmpty ? "unknown" : error)). Waiting on: you, to resume it or ask the user.",
                                          cwd: project, session: sid, name: w.name, now: now).item
    }

    /// The `--settings` JSON a background worker starts with: Stop and StopFailure call `duo2 hook stop`.
    public static func workerSettings(duo2: String) -> String {
        let cmd = Director.shellQuote(duo2) + " hook stop"
        let h: [String: Any] = ["hooks": [["type": "command", "command": cmd, "timeout": 15]]]
        // The report itself is pre-approved: Auto's classifier denied it as "unsanctioned communication" when the
        // user had only been offered the hand-off (F-711). Only this verb; everything else asks as usual.
        let s: [String: Any] = ["hooks": ["Stop": [h], "StopFailure": [h]], "permissions": ["allow": ["Bash(duo2 director report:*)"]]]
        return (try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
