import Foundation

/// What a session is told about its project (ENH-16, F-146), beside its task (DL-116): the
/// project's name and folder, and the goal, health and next step from `PROJECT.md`'s frontmatter,
/// the brief the user sees on the project's tile. Told in full at SessionStart (startup, resume,
/// clear, compact); at UserPromptSubmit only what changed since, once. A project whose `CLAUDE.md`
/// already imports `@PROJECT.md` (the guide's workaround) gets the name and folder only: Claude
/// has read the rest. Read from disk at each hook, never cached.
public enum ProjectContext {
    public struct Brief: Codable, Sendable, Equatable {
        public var name: String
        /// The project folder, absolute.
        public var folder: String
        public var goal: String
        /// The frontmatter's slug (`on-track`); shown in words.
        public var health: String
        public var next: String
        /// The project's `CLAUDE.md` imports `@PROJECT.md`.
        public var imported: Bool

        public init(name: String, folder: String, goal: String = "", health: String = "", next: String = "", imported: Bool = false) {
            self.name = name; self.folder = folder; self.goal = goal; self.health = health; self.next = next; self.imported = imported
        }
    }

    /// The brief of the project in `folder`, read now; nil without a `PROJECT.md`.
    public static func brief(name: String, folder: URL) -> Brief? {
        guard let text = try? String(contentsOf: folder.appending(path: "PROJECT.md"), encoding: .utf8) else { return nil }
        let fm = Frontmatter.parse(text)
        func one(_ k: String) -> String { (fm.string(k) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return Brief(name: name, folder: folder.standardizedFileURL.path, goal: one("goal"), health: one("health"),
                     next: fm.string("next") == nil ? one("milestone") : one("next"), imported: imports(folder))
    }

    /// The project a session belongs to: the one Duo files it under, else the nearest folder at or
    /// above Claude's folder with a `PROJECT.md` (a session in `repo/src` is `repo`'s, DL-82).
    public static func folder(project: String?, cwd: String?, folders: [String: URL]) -> (name: String, folder: URL)? {
        if let project, let f = folders[project], FileManager.default.fileExists(atPath: f.appending(path: "PROJECT.md").path) {
            return (project, f)
        }
        guard let cwd, !cwd.isEmpty, let f = ProjectDiscovery.enclosingProject(URL(fileURLWithPath: cwd)) else { return nil }
        let name = folders.first { $0.value.standardizedFileURL.path == f.standardizedFileURL.path }?.key ?? f.lastPathComponent
        return (name, f)
    }

    /// The project's own `CLAUDE.md` files (F-146: `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`)
    /// import `PROJECT.md` with an `@` line.
    static func imports(_ folder: URL) -> Bool {
        ["CLAUDE.md", ".claude/CLAUDE.md", "CLAUDE.local.md"].contains { name in
            guard let text = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) else { return false }
            return text.range(of: #"(^|\s)@(\./)?PROJECT\.md(?![\w.])"#, options: .regularExpression) != nil
        }
    }

    // MARK: What Claude reads

    /// At SessionStart: the project in full (or only its name, when CLAUDE.md imports the brief).
    public static func atStart(_ b: Brief?) -> String? {
        b.map { "Duo: " + listing($0) }
    }

    /// At UserPromptSubmit: what changed since `told` (nil: never told, so say it all), once.
    public static func onPrompt(_ now: Brief?, told: Brief?) -> String? {
        guard let told else { return atStart(now) }
        guard let now else { return "Duo: This session is no longer in a project with a PROJECT.md (it was in \(quoted(told.name)))." }
        guard !same(now, told) else { return nil }
        if now.folder != told.folder || now.name != told.name {
            return "Duo: This session's project is now \(quoted(now.name)) (was \(quoted(told.name))).\n" + listing(now)
        }
        var lines: [String] = []
        for (label, o, n) in [("goal", told.goal, now.goal), ("health", healthWords(told.health), healthWords(now.health)), ("next step", told.next, now.next)] where o != n {
            lines.append(n.isEmpty ? "The project's \(label) was cleared (was \(quoted(o)))."
                         : o.isEmpty ? "The project's \(label) is now \(quoted(n))."
                         : "The project's \(label) is now \(quoted(n)) (was \(quoted(o))).")
        }
        return "Duo: " + lines.joined(separator: "\n")
    }

    /// Only what Claude was told counts: `imported` changes what's said at start, not the brief.
    static func same(_ a: Brief, _ b: Brief) -> Bool {
        a.name == b.name && a.folder == b.folder && a.goal == b.goal && a.health == b.health && a.next == b.next
    }

    static func listing(_ b: Brief) -> String {
        let head = "This session is in the project \(quoted(b.name)) (\(b.folder))."
        if b.imported { return head + " Its CLAUDE.md imports PROJECT.md, so you already have its goal, health and next step." }
        let facts = [("Goal", b.goal), ("Health", healthWords(b.health)), ("Next step", b.next)].filter { !$0.1.isEmpty }
        // A brand-new PROJECT.md says only `health: on-track`: no brief yet, so no lines.
        guard !b.goal.isEmpty || !b.next.isEmpty else { return head + " Its PROJECT.md has no goal or next step yet." }
        return head + " Its brief, from PROJECT.md (the user sees it on the project's tile in Duo):\n"
            + facts.map { "- \($0.0): \($0.1)" }.joined(separator: "\n")
    }

    /// `on-track` → `on track`.
    static func healthWords(_ slug: String) -> String { slug.replacingOccurrences(of: "-", with: " ") }

    static func quoted(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }

    // MARK: What Duo last told each session

    public static func toldFile(_ sessionId: String, in dir: URL = DuoPaths.events) -> URL {
        dir.appending(path: "\(sessionId).project.json")
    }

    /// `.some(nil)`: told there was no project. Nil: never told (or a session from before ENH-16).
    static func told(_ sessionId: String, in dir: URL) -> Brief?? {
        guard let data = try? Data(contentsOf: toldFile(sessionId, in: dir)) else { return nil }
        return .some(try? JSONDecoder().decode(Brief.self, from: data))
    }

    static func record(_ b: Brief?, for sessionId: String, in dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? (b.flatMap { try? JSONEncoder().encode($0) } ?? Data("null".utf8)).write(to: toldFile(sessionId, in: dir), options: .atomic)
    }

    /// A hook's answer about the project (empty for none), recording what was told.
    /// `event` is `start` (SessionStart) or `prompt` (UserPromptSubmit).
    public static func hook(_ event: String, sessionId: String, now: Brief?, in dir: URL = DuoPaths.events) -> String {
        var text: String?
        if event == "start" {
            text = atStart(now)
        } else {
            switch told(sessionId, in: dir) {
            case nil: text = atStart(now)
            case .some(let before):
                if before == nil && now == nil { return "" }
                if let before, let now, same(before, now) { return "" }
                text = before == nil ? atStart(now) : onPrompt(now, told: before)
            }
        }
        record(now, for: sessionId, in: dir)
        return text ?? ""
    }

    /// The project's lines, then the task's (DL-116), as one additionalContext.
    public static func joined(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
