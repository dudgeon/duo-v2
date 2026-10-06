import Foundation

/// What a session attributed to a task is told about it (DL-116). A session is attributed when a
/// task note's `sessions:` list links it (DL-93). Duo's hooks add a few lines to Claude's context:
/// at SessionStart (startup, resume, clear, compact) the task(s) in full; at UserPromptSubmit
/// only what changed since Duo last told it (linked, unlinked, renamed, moved, status, archived),
/// once. `duo2 session task` prints the same at any time. Tasks are found from the notes at the
/// moment of asking, never cached: a rename moves the note (C-24).
public enum TaskContext {
    /// One task a session belongs to, as last told (stored per session, compared on each prompt).
    public struct Entry: Codable, Sendable, Equatable {
        public var project: String
        /// The project folder, absolute.
        public var folder: String
        /// Relative to the project folder: `tasks/exec-review-prep.md`.
        public var path: String
        public var title: String
        public var status: String?
        /// The note's stable `id:`, once Copy Link has written one.
        public var id: String?
        public var archived: Bool

        public init(project: String, folder: String, path: String, title: String, status: String? = nil, id: String? = nil, archived: Bool = false) {
            self.project = project; self.folder = folder; self.path = path; self.title = title
            self.status = status; self.id = id; self.archived = archived
        }

        var file: String { (folder as NSString).appendingPathComponent(path) }
    }

    /// Every task whose note links any of `sessionIds`, read from disk now, in project then path order.
    public static func entries(for sessionIds: [String], folders: [String: URL]) -> [Entry] {
        let ids = Set(sessionIds.map { $0.lowercased() })
        var out: [Entry] = []
        for (project, folder) in folders.sorted(by: { $0.key < $1.key }) {
            let dir = folder.appending(path: "tasks")
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in files.filter({ $0.pathExtension.lowercased() == "md" }).sorted(by: { $0.path < $1.path }) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let note = TaskNotes.parse(text, path: "tasks/" + url.lastPathComponent)
                guard note.sessionIds.contains(where: ids.contains) else { continue }
                out.append(Entry(project: project, folder: folder.path, path: note.path, title: note.title, status: note.status,
                                 id: note.id?.isEmpty == false ? note.id : nil, archived: note.archived))
            }
        }
        return out
    }

    // MARK: What Claude reads

    /// At SessionStart, and for `duo2 session task`: the task(s) in full. Nil with no task.
    public static func atStart(_ now: [Entry], cwd: String?) -> String? {
        now.isEmpty ? nil : "Duo: " + listing(now, cwd: cwd)
    }

    /// At UserPromptSubmit: what changed since `told` (nil: never told, so say it all), once.
    /// Nil when nothing changed.
    public static func onPrompt(_ now: [Entry], told: [Entry]?, cwd: String?) -> String? {
        guard let told else { return atStart(now, cwd: cwd) }
        guard now != told else { return nil }
        let lines = changes(from: told, to: now, cwd: cwd)
        let after = now.isEmpty ? "This session has no task now." : listing(now, cwd: cwd)
        return "Duo: " + (lines + [after]).joined(separator: "\n")
    }

    /// `duo2 session task` with no task.
    public static let none = "This session isn't attributed to any task. (A task note's `sessions:` list links the sessions that are; see `duo2 tasks`.)"

    static func listing(_ tasks: [Entry], cwd: String?) -> String {
        let manage = "Duo manages the `sessions:` list in the frontmatter; leave it as it is."
        let check = "Check this any time with `duo2 session task`."
        if tasks.count == 1, let t = tasks.first {
            return "This session is attributed to the task \(quoted(t.title)) (\(facts(t))).\n"
                + "Its note, \(show(t, cwd: cwd)), is the task's brief: read it before working on the task, and record progress and decisions there. \(manage)\n"
                + check
        }
        return "This session is attributed to \(tasks.count) tasks:\n"
            + tasks.map { "- \(quoted($0.title)) (\(facts($0))): \(show($0, cwd: cwd))" }.joined(separator: "\n") + "\n"
            + "Each note is its task's brief: read it before working on that task, and record progress and decisions there. \(manage)\n"
            + check
    }

    static func facts(_ t: Entry) -> String {
        (["status: \(t.status ?? "open")"] + (t.archived ? ["archived"] : []) + (t.id.map { ["id: \($0)"] } ?? [])).joined(separator: ", ")
    }

    static func quoted(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }

    /// The note's path relative to Claude's folder when it's inside it, otherwise absolute.
    static func show(_ t: Entry, cwd: String?) -> String {
        let file = (t.file as NSString).standardizingPath
        if let cwd, !cwd.isEmpty {
            let base = (cwd as NSString).standardizingPath
            if file.hasPrefix(base + "/") { return String(file.dropFirst(base.count + 1)) }
        }
        return file
    }

    /// One sentence per difference. Tasks pair up by `id:`, then by note; a lone task that went and
    /// a lone one that came (in one project, or overall) are one task renamed or moved: its note follows its title (C-24).
    static func changes(from told: [Entry], to now: [Entry], cwd: String?) -> [String] {
        var gone = told, came: [Entry] = [], pairs: [(Entry, Entry)] = []
        for n in now {
            if let i = gone.firstIndex(where: { o in (o.id != nil && o.id == n.id) || (o.folder == n.folder && o.path == n.path) }) {
                pairs.append((gone.remove(at: i), n))
            } else { came.append(n) }
        }
        for n in came {
            let same = gone.indices.filter { gone[$0].project == n.project }
            if same.count == 1, came.filter({ $0.project == n.project }).count == 1 {
                pairs.append((gone.remove(at: same[0]), n))
                came.removeAll { $0 == n }
            }
        }
        // Moved to another project (Move to Project) without an id: the one that went is the one that came.
        if gone.count == 1, came.count == 1 { pairs.append((gone.removeFirst(), came.removeFirst())) }
        var lines: [String] = []
        for (o, n) in pairs where o != n {
            if o.title != n.title { lines.append("The task \(quoted(o.title)) was renamed \(quoted(n.title)).") }
            if o.project != n.project { lines.append("The task \(quoted(n.title)) moved to the project \(n.project); its note is now \(show(n, cwd: cwd)).") }
            else if o.file != n.file { lines.append("Its note moved from \(show(o, cwd: cwd)) to \(show(n, cwd: cwd)).") }
            if o.status != n.status { lines.append("The task \(quoted(n.title)) is now \(n.status ?? "open") (was \(o.status ?? "open")).") }
            if o.archived != n.archived { lines.append("The task \(quoted(n.title)) was \(n.archived ? "archived" : "taken out of the archive").") }
            if o.id != n.id, o.id == nil, n.id != nil, lines.isEmpty { lines.append("The task \(quoted(n.title)) now has the id \(n.id!).") }
        }
        lines += came.map { "This session was added to the task \(quoted($0.title))." }
        lines += gone.map { "This session was removed from the task \(quoted($0.title)) (\(show($0, cwd: cwd)))." }
        return lines
    }

    // MARK: What Duo last told each session

    public static func toldFile(_ sessionId: String, in dir: URL = DuoPaths.events) -> URL {
        dir.appending(path: "\(sessionId).task.json")
    }

    /// Nil when Duo has never told this session about tasks (or it predates DL-116).
    public static func told(_ sessionId: String, in dir: URL = DuoPaths.events) -> [Entry]? {
        (try? Data(contentsOf: toldFile(sessionId, in: dir))).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }
    }

    public static func record(_ entries: [Entry], for sessionId: String, in dir: URL = DuoPaths.events) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: toldFile(sessionId, in: dir), options: .atomic)
    }

    /// A hook's answer: the text to add to Claude's context (empty for none), recording what was told.
    /// `event` is `start` (SessionStart) or `prompt` (UserPromptSubmit).
    public static func hook(_ event: String, sessionId: String, now: [Entry], cwd: String?, in dir: URL = DuoPaths.events) -> String {
        let text: String?
        if event == "start" {
            text = atStart(now, cwd: cwd)
        } else {
            let before = told(sessionId, in: dir)
            text = before == nil && now.isEmpty ? nil : onPrompt(now, told: before, cwd: cwd)
            if before == now { return "" }
        }
        record(now, for: sessionId, in: dir)
        return text ?? ""
    }
}
