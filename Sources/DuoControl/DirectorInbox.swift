import Foundation

// The director's inbox (DL-342 (1), Q-569): workers report with `duo2 director report <task> "<text>"`,
// which appends one line to `<project>/.duo/director-inbox.jsonl` in the main checkout. The inbox is the
// source of truth; a SendMessage to the director is only the doorbell, so a report survives Duo being
// closed, a client with no messaging, a permission-class hold (F-421) and the director restarting or
// compacting. `duo2 director status` shows each task's unread reports as an R1 red line until the
// director records a check after them. It's per project (Geoff, 2026-11-15: "should likely be per
// project, not global"); a director the user names as overseer may read another project's (`overseer:`
// in that project's `_PROJECT.md` or in Home's `_HOME.md`).

/// One report in a project's inbox.
public struct InboxItem: Codable, Equatable, Sendable {
    /// ISO-8601, when it was written.
    public var at: String
    /// The director it's for (the note's `directed_by:`).
    public var director: String
    /// `tasks/<file>.md`, or `session:<id>` for a session with no task.
    public var task: String
    /// The reporting session's id, when it was run from one.
    public var session: String?
    /// The reporting session's name, when it has one.
    public var from: String?
    public var text: String

    public init(at: String, director: String, task: String, session: String? = nil, from: String? = nil, text: String) {
        self.at = at; self.director = director; self.task = task; self.session = session; self.from = from; self.text = text
    }

    public var date: Date? { DirectorTranscript.parseDate(at) }
}

public enum DirectorInbox {
    /// What `report` refuses empty text with.
    public static let emptyRefusal = "a report needs its text: what you did or what the user asked, what was decided, and what waits on whom"
    /// How much of a report status quotes.
    public static let quoted = 160

    public static func file(project: URL) -> URL { project.appending(path: ".duo/director-inbox.jsonl") }

    /// Appends one report, as one write to a file opened for appending (two workers may report at once).
    public static func append(_ item: InboxItem, project: URL) throws {
        let url = file(project: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try enc.encode(item); line.append(UInt8(ascii: "\n"))
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let n = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard n == line.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// The last `lastBytes` of the inbox, oldest first. Lines that don't parse are skipped.
    public static func read(project: URL, lastBytes: Int = 1024 * 1024) -> [InboxItem] {
        guard let h = try? FileHandle(forReadingFrom: file(project: project)) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let from = size > UInt64(lastBytes) ? size - UInt64(lastBytes) : 0
        try? h.seek(toOffset: from)
        var lines = ((try? h.readToEnd()) ?? Data()).split(separator: UInt8(ascii: "\n"))
        if from > 0, !lines.isEmpty { lines.removeFirst() }
        let dec = JSONDecoder()
        return lines.compactMap { try? dec.decode(InboxItem.self, from: Data($0)) }
    }

    /// The reports for `director` with no check on their task at or after them, grouped by task, newest
    /// report last in each group. A check is a `check` event in the log for that task (the app and duo2 both
    /// write one) or, for a note, a `Checked:` Progress line (`lastChecked`, by task path).
    public static func unread(_ items: [InboxItem], director: String, events: [DirectorEvent], lastChecked: [String: Date] = [:]) -> [(task: String, items: [InboxItem])] {
        var checks: [String: Date] = lastChecked
        for e in events where e.event == "check" {
            guard let t = e.task, let d = DirectorTranscript.parseDate(e.at) else { continue }
            if checks[t].map({ d > $0 }) ?? true { checks[t] = d }
        }
        var order: [String] = [], groups: [String: [InboxItem]] = [:]
        for i in items where i.director == director {
            guard let d = i.date else { continue }
            if let c = checks[i.task], c >= d { continue }
            if groups[i.task] == nil { order.append(i.task) }
            groups[i.task, default: []].append(i)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// A report's text cut for a red line: its last `quoted` characters on one line, `…` before a cut.
    public static func quote(_ s: String, limit: Int = quoted) -> String {
        let one = s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > limit ? "…" + one.suffix(limit).trimmingCharacters(in: .whitespaces) : one
    }

    /// What a red line quotes of a report: from its "Waiting on:" when it has one (what the director must act
    /// on), else its start, `quoted` characters at most.
    public static func reportQuote(_ s: String, limit: Int = quoted) -> String {
        let one = s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let from = one.range(of: "Waiting on:", options: .caseInsensitive).map { String(one[$0.lowerBound...]) } ?? one
        return from.count > limit ? from.prefix(limit).trimmingCharacters(in: .whitespaces) + "…" : from
    }

    /// A report says nothing waits on anyone, so the director needn't be woken for it (C-186's volume).
    public static func waitsOnNoOne(_ text: String) -> Bool {
        text.range(of: #"(?i)waiting on:\s*(no one|nobody|none|nothing)"#, options: .regularExpression) != nil
    }

    /// The directors the user named as overseers of `project`: `overseer:` in its `_PROJECT.md`, or in Home's
    /// `_HOME.md` (a global overseer). An overseer's `status --project` shows the project's red lines, its
    /// inbox among them; only the project's own director records checks.
    public static func overseers(project: URL, home: URL?) -> [String] {
        var out: [String] = []
        for f in [DuoFiles.projectFile(in: project), home.flatMap { DuoFiles.homeFile(in: $0) }].compactMap({ $0 }) {
            guard let text = try? String(contentsOf: f, encoding: .utf8), let v = Director.frontmatter("overseer", in: text) else { continue }
            out += v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return out
    }
}

// MARK: - `duo2 director report`, shared by duo2 and the checks

public enum DirectorReport {
    public struct Failure: Error, CustomStringConvertible { public var description: String }

    public struct Done: Equatable {
        public var project: URL
        public var item: InboxItem
        /// The task's note, when the report is about one (a `Reported:` line went into its Progress).
        public var note: URL?
        public var output: String
    }

    /// Records a report: one inbox line in the project (the main checkout, from a work tree too), a
    /// `Reported to …:` Progress line in the task's note, and a `report` event in the log. `target` is a
    /// note's path (absolute, as the worker's brief gives it, or `tasks/<file>.md`, or its file name), or
    /// `session` for a session with no task (reported by `session`, its id).
    public static func record(target: String, text raw: String, cwd: URL, session: String?, name: String?, now: Date = Date()) throws -> Done {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure(description: DirectorInbox.emptyRefusal) }
        let fm = FileManager.default
        var project: URL, task: String, note: URL?
        if target == "session" || target.hasPrefix("session:") {
            let sid = target.hasPrefix("session:") ? String(target.dropFirst(8)) : (session ?? "")
            guard !sid.isEmpty else { throw Failure(description: "`report session` needs to run in a Claude session (no CLAUDE_CODE_SESSION_ID here)") }
            project = DirectorPlace.resolve(from: cwd).project
            task = "session:\(sid)"
        } else {
            var stem = URL(fileURLWithPath: target).lastPathComponent
            if !stem.lowercased().hasSuffix(".md") { stem += ".md" }
            if target.hasPrefix("/") {
                let given = URL(fileURLWithPath: target).standardizedFileURL
                project = DirectorPlace.resolve(from: given.deletingLastPathComponent().deletingLastPathComponent()).project
                let inMain = project.appending(path: "tasks/\(stem)")
                note = fm.fileExists(atPath: inMain.path) ? inMain : given
            } else {
                project = DirectorPlace.resolve(from: cwd).project
                note = project.appending(path: "tasks/\(stem)")
            }
            task = "tasks/\(stem)"
            guard let n = note, fm.fileExists(atPath: n.path) else {
                throw Failure(description: "no task note \(task) in \(project.path). Give the note's path from your brief, or `session` if you have no task.")
            }
        }
        let noteText = note.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let director = noteText.flatMap { Director.frontmatter("directed_by", in: $0) } ?? DirectorRegistry.load(project: project).current?.name
            ?? Director.name(project: project.lastPathComponent)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]; iso.timeZone = .current
        let item = InboxItem(at: iso.string(from: now), director: director, task: task, session: session, from: name, text: text)
        do { try DirectorInbox.append(item, project: project) } catch {
            throw Failure(description: "couldn't write \(DirectorInbox.file(project: project).path) (\(error.localizedDescription)). Send the same report with SendMessage(to: \"\(director)\") instead, and say the inbox write failed.")
        }
        if let note, let t = noteText {
            try? DirectorOffline.write(Data(DirectorOffline.appendProgress(t, "Reported to \(director): \(DirectorInbox.quote(text, limit: 300))", now: now).utf8), to: note)
        }
        DirectorLog.append(DirectorEvent(at: item.at, director: director, event: "report", task: task, worker: session, detail: String(text.prefix(200))), project: project)
        let first = DirectorInbox.quote(text, limit: 120).replacingOccurrences(of: "\"", with: "'")
        let bell = DirectorInbox.waitsOnNoOne(text)
            ? "Nothing waits on anyone, so there's no need to wake \(director): it reads this at its next status."
            : "Now wake \(director) (the inbox is the record; this is only the doorbell): SendMessage(to: \"\(director)\", message: \"\(task): \(first)\"). Without SendMessage, the inbox is enough."
        return Done(project: project, item: item, note: note, output: "Reported to \(director)'s inbox (\(DirectorInbox.file(project: project).path)) for \(task). \(bell)")
    }
}
