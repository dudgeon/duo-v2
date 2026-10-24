import Foundation

/// The director's exact parts (DL-193 to DL-205), Foundation only, so `duo2`, the app and the checks
/// share them: who directs a project (`.duo/director.json`, DL-200), the log every `duo2 director`
/// verb writes (the metrics in `docs/research/director-product.md` are counted from it), where the
/// rules are (DL-193), what the calling client can do, the ladder `send` walks (DL-199), and the
/// guards on Duo pressing Enter for a director (DL-199).
public enum Director {
    /// A director's fixed name (DL-200): `director-<project>`, given with `claude -n`, which survives
    /// restarts where a derived name doesn't (P3).
    public static func name(project: String) -> String { "director-" + slug(project) }

    /// What starts every message a director's worker gets through Duo (its brief, each send), so the
    /// worker's transcript tells the director's turns from the user's (DL-200's pause).
    public static func tag(_ director: String) -> String { "[\(director)] " }

    /// The brief a new worker starts with: what the task is and how to report. Its words come from
    /// the note, which the worker reads; nothing here decides for the user. `note` is the note's
    /// absolute path: a worker that moves into a git work tree (where `tasks/` may not exist, or be
    /// ignored) still finds it.
    public static func workerPrompt(note: String, director: String) -> String {
        tag(director) + """
        You're the worker on the task whose note is \(note), directed by \(director). Read its ## Request and done_when: first; \
        don't decide anything the Request says you mustn't, and ask in this session if something only the user can answer comes up. \
        As you go, append dated one-line updates under the note's ## Progress; if you can't write to the note, put those lines in your report. \
        When you're done or stuck, end your turn with your report as your last message: what you did, what you checked and how, \
        and any other work you noticed (as suggestions, not done).
        """
    }

    /// A background worker's start (DL-201): a name unique to this start (`claude --bg` picks its own
    /// session id, F-318, so the name is how Duo links it) and the command the director runs.
    /// With `remoteControl`, the worker comes up reachable from the user's phone under the same
    /// name (DL-230): a director the user drives from their phone can't ask for it afterwards.
    public static func backgroundStart(folder: URL, task path: String, director: String, remoteControl: Bool = false) -> (name: String, command: String) {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let name = String(slug(stem).prefix(36)) + "-" + UUID().uuidString.lowercased().prefix(6)
        let rc = remoteControl ? " --remote-control \(shellQuote(name))" : ""
        return (name, "cd \(shellQuote(folder.path)) && claude --bg\(rc) -n \(shellQuote(name)) -- \(shellQuote(workerPrompt(note: folder.appending(path: path).path, director: director)))")
    }

    /// Why a background start can't go ahead, or nil. A logged-out CLI starts a worker that dies on
    /// "Login expired", and a director that sees that goes looking for another way to start one
    /// (F-365): say so before anything starts.
    public static func backgroundRefusal(_ caps: ClientCaps) -> String? {
        caps.cliLogin == .no ? "Claude's CLI is logged out on this Mac, so a background worker would die on \"Login expired\". "
            + "Ask the user to run `claude auth login` on this Mac, then start it again. Don't start the worker another way (DL-230)." : nil
    }

    public static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// A new task note for a request, as the director would write it by hand: the request exactly,
    /// `done_when:`, `directed_by:` and a first Progress line. For when Duo isn't running to write
    /// it with the project's task template.
    public static func newNote(title: String, request: String, doneWhen: String?, director: String, status: String, now: Date = Date()) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.locale = Locale(identifier: "en_US_POSIX")
        var fm = "---\ntype: task\ntitle: \(q(title))\nstatus: \(status)\ndirected_by: \(q(director))\ncreated: \(day.string(from: now))\n"
        if let d = doneWhen?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { fm += "done_when: \(q(d))\n" }
        fm += "---\n"
        return fm + "# \(title)\n\n## Request\n\n" + request.trimmingCharacters(in: .newlines) + "\n\n## Progress\n\n- \(f.string(from: now)) Filed by \(director) (Duo closed).\n"
    }

    /// A scalar from a note's frontmatter (quotes dropped), for code without Duo's note parser.
    public static func frontmatter(_ key: String, in text: String) -> String? {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { return nil }
        for line in text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n") where line.hasPrefix(key + ":") {
            let v = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    /// How long a worker started in the background may take to appear before its slot is freed.
    public static let pendingLasts: TimeInterval = 30 * 60

    /// At most this many workers per director (DL-201), unless the project's `## Director` says
    /// `max workers: N`.
    public static let defaultCap = 3

    /// Statuses that hold a worker slot: work started and not finished. `suggested` is proposed work
    /// (DL-194); done, dropped and archived tasks free their slot.
    public static func holdsSlot(status: String?, archived: Bool) -> Bool {
        guard !archived else { return false }
        let s = (status ?? "open").trimmingCharacters(in: .whitespaces).lowercased()
        return !["suggested", "done", "dropped"].contains(s)
    }

    /// The cap a project's `## Director` section sets (`max workers: 5`, `max_workers = 5`), else the default.
    public static func cap(directorSection: String?) -> Int {
        guard let s = directorSection,
              let re = try? NSRegularExpression(pattern: #"max[ _-]?workers\s*[:=]\s*(\d+)"#, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 1), in: s), let n = Int(s[r]), n > 0 else { return defaultCap }
        return n
    }

    /// A `## <heading>` section's body (up to the next heading of the same or higher level), or nil.
    public static func section(_ heading: String, in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## " + heading.lowercased() }) else { return nil }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) ?? lines.endIndex
        return lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A task note's file stem for a title (the same rule as `TaskNotes.slug`, for code without DuoKit).
    public static func slugFor(_ title: String) -> String {
        let out = slug(title); return out == "project" && !title.lowercased().contains("project") ? "task" : String(out.prefix(60))
    }

    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US")).lowercased()
        let out = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "project" : out
    }
}

/// The shared director skill Duo installs as `~/.claude/skills/director/SKILL.md` (DL-193, DL-222),
/// under the duo2 skill's rules (`Installer`), with a stub at the old name `duo-director` for one
/// release. Its source is `skills/duo-director/SKILL.md`, generated into `DirectorSkillText.swift`
/// by `scripts/gen-director-skill.py`.
public enum DirectorSkill {
    /// Bump when the skill's shape changes in a way an older Duo shouldn't overwrite.
    public static let format = 1
    /// Bump when the skill starts needing a `duo2 director` verb or behaviour an older Duo lacks
    /// (F-341): `status` compares the installed skill's revision with the running Duo's.
    public static let revision = 2
    public static func text(name: String = "director") -> String {
        let t = source.replacingOccurrences(of: "{{FORMAT}}", with: "\(format)").replacingOccurrences(of: "{{REVISION}}", with: "\(revision)")
        return name == "director" ? t : t.replacingOccurrences(of: "name: director\n", with: "name: \(name)\n")
    }

    /// The old name's stub (DL-222): points at the real skill, so `/duo-director` keeps working for a release.
    public static func aliasText() -> String {
        """
        ---
        name: duo-director
        description: The old name of the `director` skill. Use the `director` skill: Direct work in a Duo project or across Home (tasks, workers, checking what comes back). Use when the user says "direct", "be the director", "delegate this", or when a session named director-<project> starts or resumes.
        ---

        <!-- Written by the Duo app (duo-director alias, format \(format), revision \(revision)). Duo rewrites this file each release unless you edit it; the next release removes it. -->

        # duo-director is now `director`

        Load the `director` skill (`~/.claude/skills/director/SKILL.md`) and follow it. If that skill isn't available, run `duo2 director guide`: it prints the same text.

        """
    }

    /// The revision a skill file was written with, from its header comment; nil if it has none.
    public static func revision(of text: String) -> Int? {
        guard let r = text.range(of: #"revision (\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[r].dropFirst("revision ".count))
    }

    /// What `duo2 director status` says about the installed skill against this Duo, or nil when they match (F-341).
    public static func versionNote(installed: String?) -> String? {
        guard let installed, let r = revision(of: installed) else { return nil }
        if r > revision {
            return "The installed director skill is newer (revision \(r)) than this Duo (\(revision)): this Duo lacks verbs it names. Tell the user to update Duo (Duo › Check for Updates…), work by hand until then, and check again after each of their messages."
        }
        if r < revision {
            return "The installed director skill is older (revision \(r)) than this Duo (\(revision)); Duo updates it at launch. If your own copy differs from `duo2 director guide`, re-read that."
        }
        return nil
    }
}

// MARK: - Who directs a project (DL-200)

/// `<project>/.duo/director.json`: the current director and the ones it replaced. A replaced
/// director that wakes reads this, stands down and points to the new one.
public struct DirectorRegistry: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var name: String
        public var sessionId: String
        public var since: String
        public var until: String?
        public var replacedBy: String?
        public init(name: String, sessionId: String, since: String, until: String? = nil, replacedBy: String? = nil) {
            self.name = name; self.sessionId = sessionId; self.since = since; self.until = until; self.replacedBy = replacedBy
        }
    }
    public var schema = 1
    public var current: Entry?
    public var retired: [Entry] = []
    /// Messages waiting for a worker to go idle (DL-199's last rung before asking the user).
    public var pending: [Pending] = []

    public struct Pending: Codable, Equatable, Sendable {
        public var task: String
        public var message: String
        public var at: String
        public init(task: String, message: String, at: String) { self.task = task; self.message = message; self.at = at }
    }

    /// The sessions this director may reach, each on one task (DL-200): ones it started, or ones the
    /// user agreed it may adopt. A session not here is the user's, whatever a note's `sessions:` says.
    public var workers: [Worker] = []
    /// When the user handed each worker back (DL-200), by session id: their turns before then no
    /// longer pause its director. The pause itself is read from the worker's transcript.
    public var handedBack: [String: String] = [:]

    public struct Worker: Codable, Equatable, Sendable {
        public var task: String
        public var session: String
        public var since: String
        /// Not started by the director: the user said it may take this session on.
        public var adopted: Bool
        /// The name it was started under (`claude --bg -n <name>`, unique to that start) for one the
        /// director started in the background: Duo links the session with that name when it appears.
        public var name: String?
        /// Started in the background and not seen yet: no session id (F-318).
        public var pending: Bool { session.isEmpty }
        public init(task: String, session: String, since: String, adopted: Bool, name: String? = nil) {
            self.task = task; self.session = session; self.since = since; self.adopted = adopted; self.name = name
        }
    }

    public init() {}

    enum CodingKeys: String, CodingKey { case schema, current, retired, pending, workers, handedBack }

    /// Every key is optional, so a file from an older Duo (or a hand edit) still reads.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        current = try c.decodeIfPresent(Entry.self, forKey: .current)
        retired = try c.decodeIfPresent([Entry].self, forKey: .retired) ?? []
        pending = try c.decodeIfPresent([Pending].self, forKey: .pending) ?? []
        workers = try c.decodeIfPresent([Worker].self, forKey: .workers) ?? []
        handedBack = try c.decodeIfPresent([String: String].self, forKey: .handedBack) ?? [:]
    }

    /// The worker on `task`: its latest one.
    public func worker(task: String) -> Worker? { workers.last { $0.task == task } }

    /// Links a pending background worker to its session, found by the name it was started under.
    /// True if one was linked.
    public mutating func link(pendingNamed name: String, to session: String) -> Worker? {
        guard let i = workers.firstIndex(where: { $0.pending && $0.name == name }) else { return nil }
        workers[i].session = session
        return workers[i]
    }

    /// Records `session` as the worker on `task` (one worker per task: it replaces an earlier one).
    public mutating func setWorker(task: String, session: String, at: String, adopted: Bool, name: String? = nil) {
        workers.removeAll { $0.task == task }
        workers.append(Worker(task: task, session: session, since: at, adopted: adopted, name: name))
    }

    /// A task path the registry may name: a note directly in `tasks/`, nothing that climbs out.
    public static func isTaskPath(_ p: String) -> Bool {
        p.range(of: #"^tasks/[^/\\]+\.md$"#, options: .regularExpression) != nil && !p.contains("..")
    }

    public static func file(project: URL) -> URL { project.appending(path: ".duo/director.json") }

    public static func load(project: URL) -> DirectorRegistry {
        (try? JSONDecoder().decode(DirectorRegistry.self, from: Data(contentsOf: file(project: project)))) ?? DirectorRegistry()
    }

    public func save(project: URL) throws {
        let url = Self.file(project: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public enum Role: Equatable, Sendable {
        /// This session is the project's director.
        case current
        /// It was, and was replaced: stand down and point here.
        case replaced(by: Entry?)
        /// The project has a director, and it isn't this session.
        case other(Entry)
        /// Nobody directs this project.
        case none
    }

    /// What a session is to this project, by its id alone. A name proves nothing (two sessions can
    /// share one): a resumed director whose id moved (P3) is `.other` until it runs
    /// `duo2 director start --take-over`, and `status` never moves the registry.
    public func role(sessionId: String?) -> Role {
        if let c = current, let sessionId, c.sessionId == sessionId { return .current }
        if let sid = sessionId, let r = retired.last(where: { $0.sessionId == sid }) {
            return .replaced(by: current?.name == r.replacedBy ? current : retired.last(where: { $0.name == r.replacedBy }))
        }
        if let c = current { return .other(c) }
        return .none
    }

    /// Records `name`/`sessionId` as the current director (only `start`, and `--take-over` when one
    /// exists). Taking over from another moves it to `retired`, replaced by this one; the same name
    /// with a new id (the director resumed, P3) just moves the id.
    public mutating func adopt(name: String, sessionId: String, at: String) {
        if let c = current {
            if c.sessionId == sessionId, c.name == name { return }
            if c.name == name { current?.sessionId = sessionId; return }
            var old = c; old.until = at; old.replacedBy = name
            retired.append(old)
        }
        current = Entry(name: name, sessionId: sessionId, since: at)
    }

    /// The current director stands down for good (`duo2 director retire`).
    public mutating func retire(at: String) -> Entry? {
        guard var c = current else { return nil }
        c.until = at
        retired.append(c)
        current = nil
        return c
    }
}

// MARK: - The log (the metrics' source)

/// One line of `<project>/.duo/director-log.jsonl`. Every `duo2 director` verb appends what it did;
/// the metrics in director-product.md ("Commitments": decisions asked and answered, the rung each
/// send used, two directors on one worker, wrong addresses, cost per task…) are counted from these.
public struct DirectorEvent: Codable, Equatable, Sendable {
    public var at: String
    public var director: String?
    /// `status`, `start`, `refused`, `send`, `delivered`, `retire`, `takeover`, `standdown`.
    public var event: String
    public var task: String?
    public var worker: String?
    /// For `send` and `delivered`: the ladder rung taken (`SendRung`).
    public var rung: String?
    public var detail: String?

    public init(at: String, director: String?, event: String, task: String? = nil, worker: String? = nil, rung: String? = nil, detail: String? = nil) {
        self.at = at; self.director = director; self.event = event; self.task = task; self.worker = worker; self.rung = rung; self.detail = detail
    }
}

public enum DirectorLog {
    public static func file(project: URL) -> URL { project.appending(path: ".duo/director-log.jsonl") }

    public static func append(_ e: DirectorEvent, project: URL) {
        let url = file(project: project)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        guard var line = try? enc.encode(e) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    public static func read(project: URL) -> [DirectorEvent] {
        guard let text = try? String(contentsOf: file(project: project), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(DirectorEvent.self, from: Data($0.utf8)) }
    }

    /// The counts the doc's measures need that the log alone can answer.
    public struct Metrics: Equatable, Sendable {
        public var sends: [String: Int] = [:]
        public var refusals = 0
        public var starts = 0
        public var takeovers = 0
        public var standdowns = 0
        /// Sends to a worker whose task another director directs: should stay 0.
        public var wrongAddress = 0
    }

    public static func metrics(_ events: [DirectorEvent]) -> Metrics {
        var m = Metrics()
        for e in events {
            switch e.event {
            case "send": m.sends[e.rung ?? "?", default: 0] += 1
            case "refused": m.refusals += 1; if e.detail?.contains("another director") == true { m.wrongAddress += 1 }
            case "start": m.starts += 1
            case "takeover": m.takeovers += 1
            case "standdown": m.standdowns += 1
            default: break
            }
        }
        return m
    }
}

// MARK: - Where the rules are (DL-193, amended by DL-207)

/// The rules a director reads besides `CLAUDE.md` and project skills (DL-207): the user's rules for
/// every director in Home's `HOME.md` under `## Director`, and a project's own in its `PROJECT.md`
/// under `## Director`, which wins inside that project. Duo never writes either; the director
/// proposes additions and writes them only on the user's yes.
public enum DirectorRules {
    public struct Source: Equatable, Sendable {
        /// What it is, for people: "your rules for every director (Home)", "this project's rules".
        public var label: String
        public var path: String
        /// The `## <heading>` inside the file that holds them.
        public var section: String
        /// The file has that section.
        public var exists: Bool
        /// The file itself is there (a project often has no PROJECT.md yet, DL-193).
        public var fileExists: Bool = true
        /// Higher wins: the project's rules beat Home's (DL-207).
        public var precedence: Int
        public init(label: String, path: String, section: String, exists: Bool, precedence: Int, fileExists: Bool = true) {
            self.label = label; self.path = path; self.section = section; self.exists = exists; self.precedence = precedence; self.fileExists = fileExists
        }

        /// One line for `status`: where, and what to do when it's missing.
        public var line: String {
            let file = URL(fileURLWithPath: path).lastPathComponent
            let state = exists ? "" : !fileExists
                ? (file == "PROJECT.md" ? " (no PROJECT.md yet: offer Make a Project, `duo2 project make`)" : " (no \(file) yet)")
                : " (no ## \(section) section yet)"
            return "\(label): \(path) (## \(section))\(state)"
        }

        /// The line plus the section's own text, indented under it: a director reads its rules
        /// from `status` without a separate read (Haiku skipped that read in half the dogfood runs).
        public var report: String {
            guard exists, let text = DirectorRules.text(self), !text.isEmpty else { return line }
            return line + "\n" + text.split(separator: "\n", omittingEmptySubsequences: false).map { "      " + $0 }.joined(separator: "\n")
        }
    }

    public static let section = "Director"

    /// Home's rules, then the project's (none for a project that is Home itself). No Home: only
    /// the project's, and the director offers to set one up (DL-207).
    public static func sources(project: URL?, home: URL?) -> [Source] {
        func source(_ label: String, _ file: URL, _ precedence: Int) -> Source {
            let text = try? String(contentsOf: file, encoding: .utf8)
            return Source(label: label, path: file.path, section: section, exists: text.flatMap { Director.section(section, in: $0) } != nil,
                          precedence: precedence, fileExists: text != nil)
        }
        var out: [Source] = []
        if let home { out.append(source("your rules for every director (Home)", home.appending(path: "HOME.md"), 0)) }
        if let project, project.standardizedFileURL != home?.standardizedFileURL {
            out.append(source("this project's rules", project.appending(path: "PROJECT.md"), 1))
        }
        return out
    }

    /// The text of one source's section, nil if it has none.
    public static func text(_ s: Source) -> String? {
        guard let t = try? String(contentsOf: URL(fileURLWithPath: s.path), encoding: .utf8) else { return nil }
        return Director.section(s.section, in: t)
    }
}

// MARK: - Has the user taken a worker over? (DL-200)

/// Reads the end of a worker's transcript for the user's own turns since the director's last
/// message. A turn counts as the user's when Claude marks it human (`origin.kind`), or, on a client
/// that doesn't mark origins, when it's plain text that isn't a meta entry or a `<…>` notice. Turns
/// that start with the director's tag are the director's; tool results (answers to permission and
/// question prompts), peer messages and task notifications are neither. This sees typing from the
/// phone (Remote Control) and in background workers, which a keystroke in Duo can't.
public enum DirectorTranscript {
    /// When the user last typed in it after the director's last message, or nil.
    public static func userTurnSinceDirector(_ url: URL, tag: String, tailBytes: Int = 512 * 1024) -> Date? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let from = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? h.seek(toOffset: from)
        guard let data = try? h.readToEnd() else { return nil }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        if from > 0, !lines.isEmpty { lines.removeFirst() }   // a partial line
        var lastUser: Date?
        for line in lines {
            guard line.contains("\"user\""), let e = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  e["type"] as? String == "user", let kind = turnKind(e, tag: tag) else { continue }
            switch kind {
            case .director: lastUser = nil
            case .user: lastUser = (e["timestamp"] as? String).flatMap(parseDate) ?? Date.distantPast
            }
        }
        return lastUser
    }

    enum Kind { case user, director }

    static func turnKind(_ e: [String: Any], tag: String) -> Kind? {
        if e["isMeta"] as? Bool == true { return nil }
        let content = (e["message"] as? [String: Any])?["content"]
        let text: String?
        if let s = content as? String { text = s }
        else if let blocks = content as? [[String: Any]] {
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        } else { text = nil }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix(tag.trimmingCharacters(in: .whitespaces)) { return .director }
        if let origin = (e["origin"] as? [String: Any])?["kind"] as? String { return origin == "human" ? .user : nil }
        return t.hasPrefix("<") ? nil : .user
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Which project, which Home

/// Where a director stands, from the folder it runs in alone, the same way with or without Duo
/// running: the project is the nearest folder at or above it with a `PROJECT.md`, not above Home;
/// Home is the nearest folder at or above it with a `HOME.md`. A folder inside Home (or anywhere)
/// with no `PROJECT.md` above it is a project without one yet (DL-193: that's normal), and Home's
/// own folder is Home's project (a Home director, DL-197).
/// A folder inside a git work tree stands for the work tree's main checkout: the director's
/// own check work tree, or a worker's, belongs to the project the main checkout is.
public enum DirectorPlace {
    public static func resolve(from dir: URL) -> (project: URL, home: URL?) {
        if let main = mainCheckout(of: dir) { return resolve(from: main) }
        let fm = FileManager.default
        let start = dir.standardizedFileURL
        var project: URL?, home: URL?
        var d = start
        while true {
            if home == nil, fm.fileExists(atPath: d.appending(path: "HOME.md").path) { home = d }
            if project == nil, home == nil, fm.fileExists(atPath: d.appending(path: "PROJECT.md").path) { project = d }
            let up = d.deletingLastPathComponent().standardizedFileURL
            if up.path == d.path || d.path == "/" { break }
            d = up
        }
        return (project ?? start, home)
    }

    /// The Home Duo was told to use (`duo2 home set`, kept in its `state.json`), for when Duo is
    /// closed and the folder has no `HOME.md` above it (a project outside Home). Nil if none.
    public static func configuredHome() -> URL? {
        guard let data = try? Data(contentsOf: SupportFolder.duo.appending(path: "state.json")),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let path = j["home"] as? String, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// The main checkout when `dir` is inside a linked git work tree (its `.git` is a file reading
    /// `gitdir: <main>/.git/worktrees/<name>`), else nil. Submodules (`.git/modules/…`) stay put.
    public static func mainCheckout(of dir: URL) -> URL? {
        let fm = FileManager.default
        var d = dir.standardizedFileURL
        while true {
            let git = d.appending(path: ".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                guard !isDir.boolValue, let text = try? String(contentsOf: git, encoding: .utf8),
                      let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
                var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                if !gitdir.hasPrefix("/") { gitdir = d.appending(path: gitdir).standardizedFileURL.path }
                guard let r = gitdir.range(of: "/.git/worktrees/") else { return nil }
                return URL(fileURLWithPath: String(gitdir[..<r.lowerBound]))
            }
            let up = d.deletingLastPathComponent().standardizedFileURL
            if up.path == d.path || d.path == "/" { return nil }
            d = up
        }
    }
}

// MARK: - What the calling client can do

/// What the session calling `duo2 director …` can do, read on its side (`duo2` runs in that
/// session's environment): its beacon (`<config>/sessions/<pid>.json`, F-311), its settings files,
/// and Claude's cached account flags. `duo2` sends it to the app with each director verb.
public struct ClientCaps: Codable, Equatable, Sendable {
    public enum Tri: String, Codable, Sendable { case yes, no, unknown }
    public var version: String?
    /// Session-to-session messaging (SendMessage, idle notices): 2.1.224+ with the inbox on.
    public var messaging: Tri = .unknown
    /// `claude --bg` and agents (off with `disableAgentView`).
    public var background: Tri = .unknown
    public var remoteControl: Tri = .unknown
    /// Whether this session is reachable through Remote Control right now.
    public var remoteControlOn = false
    /// Whether Claude's CLI on this Mac is logged in (`claude auth status`), which every `claude --bg`
    /// worker needs. Read only for `status` and `start` (F-365); nil (unknown) otherwise, and from
    /// an older duo2.
    public var cliLogin: Tri?
    public var hooks: Tri = .unknown
    /// Monitor: offered only when the account's flag is on (F-310) and nothing denies it.
    public var monitor: Tri = .unknown
    /// Resuming a stopped background session with a message (2.1.285+).
    public var backgroundResume: Tri = .unknown
    /// This session runs in a Duo terminal.
    public var inDuo = false
    /// A Claude Code Projects session (DL-203): the director starts nothing.
    public var projects = false
    public var sessionId: String?
    public var name: String?
    public var notes: [String] = []

    public init() {}

    /// The managed settings file macOS reads (system-wide, above everything).
    public static let managedSettings = "/Library/Application Support/ClaudeCode/managed-settings.json"

    /// Reads it all. `env` is the caller's environment; `cwd` its folder (for project settings).
    public static func probe(env: [String: String], cwd: String?, claudeDir: URL = LegacyDuo.claudeDir,
                             managed: String = managedSettings, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClientCaps {
        var c = ClientCaps()
        c.sessionId = env["CLAUDE_CODE_SESSION_ID"]
        c.inDuo = env["DUO_SESSION_ID"] != nil
        c.projects = env["CLAUDE_CODE_PROJECTS_SESSION"].map { !$0.isEmpty && $0 != "0" } ?? false

        // The beacon: version, name, messaging, Remote Control.
        var beacon: [String: Any]?
        if let pid = env["CLAUDE_PID"] {
            beacon = json(claudeDir.appending(path: "sessions/\(pid).json"))
        }
        if beacon == nil, let sid = c.sessionId, let files = try? FileManager.default.contentsOfDirectory(at: claudeDir.appending(path: "sessions"), includingPropertiesForKeys: nil) {
            beacon = files.filter { $0.pathExtension == "json" }.lazy.compactMap { json($0) }.first { $0["sessionId"] as? String == sid }
        }
        if let b = beacon {
            c.version = b["version"] as? String
            c.name = b["name"] as? String
            let peer = (b["peerFeatures"] as? [String]) ?? []
            c.messaging = (b["messagingSocketPath"] != nil || !peer.isEmpty) ? .yes : .no
            c.remoteControlOn = b["bridgeSessionId"] != nil
        } else {
            c.notes.append("Couldn't read this session's beacon; its version and messaging are unknown.")
        }
        if env["CLAUDE_CODE_MESSAGING_SOCKET"] != nil { c.messaging = .yes }

        // Settings: managed, user, project, local. A key that turns a feature off anywhere wins (F-311).
        var settings: [[String: Any]] = []
        for url in [URL(fileURLWithPath: managed), claudeDir.appending(path: "settings.json")] + (cwd.map { d in
            [URL(fileURLWithPath: d).appending(path: ".claude/settings.json"), URL(fileURLWithPath: d).appending(path: ".claude/settings.local.json")]
        } ?? []) {
            if let j = json(url) { settings.append(j) }
        }
        func flag(_ k: String) -> Bool { settings.contains { ($0[k] as? Bool) == true } }
        let denied = Set(settings.flatMap { (($0["permissions"] as? [String: Any])?["deny"] as? [String]) ?? [] })
        func refuses(_ k: String) -> Bool { settings.contains { ($0[k] as? String) == "refuse" } }

        c.hooks = flag("disableAllHooks") ? .no : .yes
        c.remoteControl = flag("disableRemoteControl") ? .no : .yes
        c.background = (flag("disableAgentView") || env["CLAUDE_CODE_DISABLE_AGENT_VIEW"].map { !$0.isEmpty && $0 != "0" } == true) ? .no : .yes
        if refuses("crossSessionInbound") || denied.contains("SendMessage") { c.messaging = .no }
        if let v = c.version { c.backgroundResume = VersionOrder.atLeast(v, "2.1.285") ? .yes : .no }
        if c.background == .no { c.backgroundResume = .no }

        // Monitor (F-310): the account flag Claude cached, unless a setting denies the tool.
        let claudeJSON = env["CLAUDE_CONFIG_DIR"] != nil ? claudeDir.appending(path: ".claude.json") : home.appending(path: ".claude.json")
        if denied.contains("Monitor") || denied.contains(where: { $0.hasPrefix("Monitor(") && $0.hasSuffix("*)") }) {
            c.monitor = .no
        } else if let flags = json(claudeJSON)?["cachedGrowthBookFeatures"] as? [String: Any] {
            c.monitor = (flags["tengu_amber_sentinel"] as? Bool) == true ? .yes : .no
        }
        return c
    }

    /// `claude auth status` from the caller's environment: `loggedIn` in its JSON. Unknown when
    /// `claude` isn't found, takes longer than `timeout`, or says something else.
    public static func cliLogin(env: [String: String], timeout: TimeInterval = 10) -> Tri {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["claude", "auth", "status"]
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .unknown }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return .unknown }
        return loginState(out.fileHandleForReading.readDataToEndOfFile())
    }

    /// `loggedIn` from `claude auth status`'s JSON.
    public static func loginState(_ data: Data) -> Tri {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let v = j["loggedIn"] as? Bool else { return .unknown }
        return v ? .yes : .no
    }

    static func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// One line per ability, for `duo2 director status`.
    public var lines: [String] {
        func w(_ t: Tri) -> String { t.rawValue }
        var out = ["Claude Code \(version ?? "(version unknown)")\(name.map { ", named \"\($0)\"" } ?? "")\(inDuo ? ", in Duo" : ", outside Duo")."]
        out.append("Messaging (SendMessage, idle notices): \(w(messaging)). Background sessions: \(w(background)); resuming one with a message: \(w(backgroundResume)).")
        out.append("Remote Control: \(w(remoteControl))\(remoteControlOn ? ", on for this session" : ""). Hooks: \(w(hooks)).")
        out.append("Monitor: \(w(monitor))\(monitor == .yes ? " (wake on `duo2 director watch`)" : monitor == .no ? " (wake with ScheduleWakeup instead)" : " (check your tools; else ScheduleWakeup)").")
        if cliLogin == .no { out.append("CLI login: no. Claude's CLI is logged out on this Mac, so no background worker can start. Ask the user to run `claude auth login` here, and start no worker another way until they have (DL-230).") }
        if projects { out.append("This is a Claude Code Projects session: the Duo director starts nothing here (DL-203).") }
        return out + notes
    }
}

/// Claude Code versions, compared numerically (`2.1.219` < `2.1.285`).
public enum VersionOrder {
    public static func parts(_ v: String) -> [Int] {
        v.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map { $0.split(separator: ".").compactMap { Int($0) } } ?? []
    }
    public static func atLeast(_ v: String, _ min: String) -> Bool {
        let a = parts(v), b = parts(min)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return true
    }
}

// MARK: - The ladder `send` walks (DL-199)

/// The ways to reach a worker, best first (director-product.md, "Commitments").
public enum SendRung: String, Codable, CaseIterable, Sendable {
    /// SendMessage, where both sessions have messaging: the director sends it itself.
    case message
    /// `claude --bg --resume <id> "<message>"` for a stopped background worker (2.1.285+).
    case resumeBackground = "resume-background"
    /// `claude -p --resume <id> "<message>"`: a headless turn for a stopped background worker.
    case headless
    /// Duo types it into the worker's prompt and presses Enter (every `SubmitGuard` holds).
    case duoSubmit = "duo-submit"
    /// Duo reopens a stopped worker in its tab, with the message as its first prompt.
    case duoResume = "duo-resume"
    /// It waits in the task note, and Duo sends it when the worker next goes idle.
    case queued
    /// Nothing works: the director asks the user to pass it on.
    case askUser = "ask-user"
}

/// What `send` knows about a worker.
public struct WorkerFacts: Equatable, Sendable {
    public enum Where: String, Sendable { case duo, background, unknown }
    public enum Run: String, Sendable { case working, idle, needsYou = "needs-you", stopped }
    public var place: Where
    public var run: Run
    /// The worker has messaging (its beacon lists peer features) and a peer name to send to.
    public var peerName: String?
    /// The user typed into it recently, so its director is paused there (DL-200).
    public var userTyping = false
    public init(place: Where, run: Run, peerName: String? = nil, userTyping: Bool = false) {
        self.place = place; self.run = run; self.peerName = peerName; self.userTyping = userTyping
    }
}

public enum SendLadder {
    /// The rung to take now. `duoRunning` is whether the app answered.
    public static func choose(director c: ClientCaps, worker w: WorkerFacts, duoRunning: Bool) -> SendRung {
        if c.messaging == .yes, w.peerName != nil, w.run != .stopped { return .message }
        switch (w.place, w.run) {
        case (.background, .stopped):
            if c.backgroundResume == .yes { return .resumeBackground }
            return .headless
        case (.duo, .stopped):
            return duoRunning ? .duoResume : .askUser
        case (.duo, .idle):
            return duoRunning && !w.userTyping ? .duoSubmit : .queued
        case (.duo, _):
            return duoRunning ? .queued : .askUser
        case (.background, _):
            // A live background worker without messaging: nothing types into it; wait for it to stop.
            return .queued
        default:
            return .askUser
        }
    }
}

// MARK: - When Duo may press Enter for a director (DL-199)

/// Duo submits a director's message into a worker's prompt only when every one of these holds.
/// Each refusal says which, so the director (and the log) know why; DuoChecks proves each one.
public enum SubmitGuard {
    /// How long after the user's last keystroke in a worker Duo keeps out (DL-199 "recently").
    public static let quietSeconds: TimeInterval = 120

    public struct Facts: Equatable, Sendable {
        /// The task's `directed_by:`.
        public var directedBy: String?
        /// The director asking.
        public var director: String
        /// The worker is linked to that task.
        public var onTask: Bool
        /// Claude's state: the beacon says idle, and the screen shows the prompt.
        public var idle: Bool
        /// The prompt holds nothing (a dim suggestion doesn't count, F-108).
        public var promptEmpty: Bool
        /// When the user last typed in this worker's terminal, if ever.
        public var lastUserKey: Date?
        public var now: Date
        public init(directedBy: String?, director: String, onTask: Bool, idle: Bool, promptEmpty: Bool, lastUserKey: Date?, now: Date) {
            self.directedBy = directedBy; self.director = director; self.onTask = onTask; self.idle = idle
            self.promptEmpty = promptEmpty; self.lastUserKey = lastUserKey; self.now = now
        }
    }

    /// Nil when Duo may submit; otherwise why not.
    public static func refusal(_ f: Facts) -> String? {
        guard let by = f.directedBy?.trimmingCharacters(in: .whitespaces), !by.isEmpty else { return "the task has no directed_by:, so its worker is the user's" }
        guard by == f.director else { return "the task is directed by another director (\(by))" }
        guard f.onTask else { return "that session isn't on the task" }
        guard f.idle else { return "Claude isn't idle there" }
        guard f.promptEmpty else { return "something is typed in its prompt" }
        if let k = f.lastUserKey, f.now.timeIntervalSince(k) < quietSeconds {
            return "the user typed there \(Int(f.now.timeIntervalSince(k))) s ago"
        }
        return nil
    }
}
