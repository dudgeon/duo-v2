import Foundation

// Runs (DL-135, chat-polish-handoff `collapsed`, `expanded`, `mixed`, `needs-you`): every tool call
// between two pieces of Claude's text is one run, folded to one line in the terminal's own words
// (`Ran 4 shell commands`, `Searched for 2 patterns, read 3 files`). Thinking between the calls is
// inside the run; thinking just before Claude's text stays its own line. A step waiting on you and
// an agent are never folded into a run; to-do updates become one `To-dos · 3 of 5 done` line.

/// What Claude's card draws, in order.
public enum ChatCardRow: Identifiable, Equatable, Sendable {
    case text(ChatText)
    case thinking(id: String, seconds: Int?)
    case asked(id: String, questions: [ChatAsked])
    case run(ChatRun)
    /// A step on the thread by itself: one waiting on you, or an agent.
    case step(ChatToolStep)
    /// The turn's to-do list, as the latest update left it.
    case todos(ChatToolStep)

    public var id: String {
        switch self {
        case .text(let t): t.id
        case .thinking(let id, _), .asked(let id, _): id
        case .run(let r): r.id
        case .step(let s): s.id
        case .todos(let s): "todos-" + s.id
        }
    }

    /// Drawn on the dotted thread (runs and the steps beside them).
    var onThread: Bool {
        switch self {
        case .run, .step, .todos: true
        default: false
        }
    }
}

public struct ChatRun: Identifiable, Equatable, Sendable {
    public enum Entry: Equatable, Sendable {
        case step(ChatToolStep)
        case thought(id: String, seconds: Int?)
    }
    /// The first step's id, so the run keeps its open state as steps arrive.
    public var id: String
    public var entries: [Entry]

    public var steps: [ChatToolStep] { entries.compactMap { if case .step(let s) = $0 { return s } else { return nil } } }
    public var running: ChatToolStep? { steps.last { $0.status == .running } }
    public var failed: Int { steps.filter { if case .failed = $0.status { return true } else { return false } }.count }
}

public enum ChatRuns {
    /// A turn's segments as the card draws them.
    public static func blocks(_ segments: [ChatSegment]) -> [ChatCardRow] {
        let all = segments.flatMap { seg -> [ChatToolStep] in if case .tools(_, let s) = seg { return s } else { return [] } }
        let latestTodo = all.last { $0.todos != nil }?.id
        var out: [ChatCardRow] = []
        var pending: [ChatRun.Entry] = []
        var todo: ChatToolStep?

        func isStep(_ e: ChatRun.Entry) -> Bool { if case .step = e { return true } else { return false } }
        func closeRun() {
            if let last = pending.lastIndex(where: isStep), case .step(let first)? = pending.first(where: isStep) {
                out.append(.run(ChatRun(id: "run-" + first.id, entries: grouped(Array(pending[...last])))))
                pending.removeSubrange(...last)
            }
            // The to-do line goes after the run it was in.
            if let t = todo { out.append(.todos(t)); todo = nil }
            // Thinking after the last step belongs to the text that follows.
            for case .thought(let id, let secs) in pending { out.append(.thinking(id: id, seconds: secs)) }
            pending = []
        }

        for seg in segments {
            switch seg {
            case .thinking(let id, let secs, _): pending.append(.thought(id: id, seconds: secs))
            case .tools(_, let steps):
                for s in steps {
                    if s.todos != nil {
                        if s.id == latestTodo { todo = s }   // earlier updates go
                    } else if s.status == .needsYou || s.agent != nil {
                        // Never folded: the thoughts just before it wait for the run that follows.
                        var k = pending.count
                        while k > 0, !isStep(pending[k - 1]) { k -= 1 }
                        let thoughts = Array(pending[k...])
                        pending.removeSubrange(k...)
                        closeRun()
                        out.append(.step(s))
                        pending = thoughts
                    } else {
                        pending.append(.step(s))
                    }
                }
            case .text(let t): closeRun(); out.append(.text(t))
            case .asked(let id, let qs): closeRun(); out.append(.asked(id: id, questions: qs))
            }
        }
        closeRun()
        return out
    }

    /// Reads in a row are one step, `Read a.md, b.md` (handoff `plan`), as the TUI groups them.
    static func grouped(_ entries: [ChatRun.Entry]) -> [ChatRun.Entry] {
        var out: [ChatRun.Entry] = []
        for e in entries {
            if case .step(let s) = e, s.name == "Read", s.status == .done,
               case .step(var g)? = out.last, g.name == "Read", g.status == .done {
                g.object += ", " + s.object
                g.others.append((s.object, s.path))
                g.detail = nil
                g.preview = nil
                out[out.count - 1] = .step(g)
            } else {
                out.append(e)
            }
        }
        return out
    }

    // MARK: The run's line

    /// One part of the line: `ran` `4 shell commands`.
    public struct Clause: Equatable, Sendable {
        public var verb: String
        public var rest: String
        public var running = false
    }

    /// Each kind of step in the order it first came; done steps first, then those still running
    /// (`Searched for 1 pattern, read 2 files, searching for 1 pattern…`).
    public static func clauses(_ run: ChatRun) -> [Clause] {
        var done: [(key: String, steps: [ChatToolStep])] = []
        var going: [(key: String, steps: [ChatToolStep])] = []
        for s in run.steps {
            let k = kind(s).key
            if s.status == .running {
                if let i = going.firstIndex(where: { $0.key == k }) { going[i].steps.append(s) } else { going.append((k, [s])) }
            } else {
                if let i = done.firstIndex(where: { $0.key == k }) { done[i].steps.append(s) } else { done.append((k, [s])) }
            }
        }
        var out = done.map { clause($0.steps, running: false) } + going.map { clause($0.steps, running: true) }
        if !out.isEmpty { out[0].verb = out[0].verb.prefix(1).uppercased() + out[0].verb.dropFirst() }
        return out
    }

    /// The line as plain text, for accessibility and the checks.
    public static func line(_ run: ChatRun) -> String {
        var s = clauses(run).map { $0.verb + " " + $0.rest }.joined(separator: ", ")
        if run.running != nil { s += "…" }
        let files = editedFiles(run)
        if !files.isEmpty {
            s += " · " + files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            let (a, d) = editCounts(run)
            if a > 0 { s += " +\(a)" }
            if d > 0 { s += " −\(d)" }
        }
        if run.failed > 0 { s += " · \(run.failed) failed" }
        return s
    }

    struct Kind { var key: String; var past: String; var going: String; var noun: (Int) -> String }

    static func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String { "\(n) " + (n == 1 ? one : many ?? one + "s") }

    static func kind(_ s: ChatToolStep) -> Kind {
        switch s.name {
        case "Bash": return Kind(key: "bash", past: "ran", going: "running") { plural($0, "shell command") }
        case "Read", "NotebookRead": return Kind(key: "read", past: "read", going: "reading") { plural($0, "file") }
        case "Grep", "Glob": return Kind(key: "search", past: "searched for", going: "searching for") { plural($0, "pattern") }
        case "WebSearch": return Kind(key: "web", past: "searched the web for", going: "searching the web for") { plural($0, "query", "queries") }
        case "WebFetch": return Kind(key: "fetch", past: "fetched", going: "fetching") { plural($0, "page") }
        case "Edit", "MultiEdit", "NotebookEdit": return Kind(key: "edit", past: "edited", going: "editing") { plural($0, "file") }
        case "Write": return Kind(key: "write", past: "wrote", going: "writing") { plural($0, "file") }
        case "ToolSearch": return Kind(key: "tools", past: "loaded", going: "loading") { plural($0, "tool") }
        case "Skill": return Kind(key: "skill", past: "loaded", going: "loading") { plural($0, "skill") }
        case "SendMessage": return Kind(key: "send", past: "sent", going: "sending") { plural($0, "message") }
        default:
            // MCP tools by their server (`mcp__claude-in-chrome__navigate`), anything else by name.
            let parts = s.name.components(separatedBy: "__")
            let who = parts.count >= 3 && parts[0] == "mcp" ? parts[1] : s.name
            return Kind(key: "use:" + who, past: "used", going: "using") { n in who + (n == 1 ? " once" : " \(n) times") }
        }
    }

    private static func clause(_ steps: [ChatToolStep], running: Bool) -> Clause {
        let k = kind(steps[0])
        let n: Int
        switch k.key {
        case "edit", "write", "read": n = Set(steps.flatMap { [$0.path ?? $0.object] + $0.others.map { $0.1 ?? $0.0 } }).count
        case "tools": n = steps.map(toolsLoaded).reduce(0, +)
        default: n = steps.count
        }
        return Clause(verb: running ? k.going : k.past, rest: k.noun(n), running: running)
    }

    /// ToolSearch's `select:A,B` loads two tools; a keyword search, one.
    static func toolsLoaded(_ s: ChatToolStep) -> Int {
        guard s.verb == "Load" else { return 1 }
        return max(1, s.object.components(separatedBy: ", ").count)
    }

    /// The files a run edited or wrote, each once, in order.
    public static func editedFiles(_ run: ChatRun) -> [String] {
        var seen: [String] = []
        for s in run.steps where ["Edit", "MultiEdit", "NotebookEdit", "Write"].contains(s.name) {
            let p = s.path ?? s.object
            if !p.isEmpty, !seen.contains(p) { seen.append(p) }
        }
        return seen
    }

    public static func editCounts(_ run: ChatRun) -> (Int, Int) {
        run.steps.filter { ["Edit", "MultiEdit", "NotebookEdit", "Write"].contains($0.name) }
            .reduce((0, 0)) { ($0.0 + ($1.adds ?? 0), $0.1 + ($1.dels ?? 0)) }
    }

    /// `3 of 5 done`.
    public static func todoLine(_ todos: [ChatTodo]) -> String {
        "\(todos.filter { $0.status == .completed }.count) of \(todos.count) done"
    }
}
