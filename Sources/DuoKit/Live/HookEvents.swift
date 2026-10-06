import DuoControl
import Foundation

/// Where Duo keeps its own state: `~/Library/Application Support/Duo/` (Q-13 default).
/// `SupportFolder` decides (`DUO_SUPPORT_DIR`, F-74; a temporary folder for scripted runs, F-89).
public enum DuoPaths {
    public static var support: URL {
        SupportFolder.duo
    }
    public static var events: URL { support.appending(path: "events") }
    public static var state: URL { support.appending(path: "state.json") }
}

/// Claude Code hooks for sessions Duo starts (findings F-23). Each session gets its own
/// `--settings` file whose hooks append the payload to `events/<id>.jsonl`, one line per event:
/// `{"at": <epoch seconds>, "e": <payload>}`. Nothing global is touched (LR-55). Hook commands
/// print nothing, so they never answer a permission prompt on the user's behalf.
public enum HookEvents {
    static let names = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    public static func file(for sessionId: String, in dir: URL = DuoPaths.events) -> URL {
        dir.appending(path: "\(sessionId).jsonl")
    }

    /// Writes (or rewrites) the session's settings file and returns its path.
    public static func settingsFile(for sessionId: String, in dir: URL = DuoPaths.events, cli: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let folder = dir.path.replacingOccurrences(of: "'", with: "'\\''")
        // One printf per event, so an event is (nearly always) one write; the reader skips any
        // line that doesn't parse. `tr` folds pretty-printed payloads onto one line (newlines
        // inside JSON strings are already escaped). Events go to the file of the payload's
        // session_id: `/clear` and `/resume` change the session inside one process (F-29).
        let command = #"p=$(tr -d '\n'); i=$(printf %s "$p" | sed -n 's/^{ *"session_id" *: *"\([0-9A-Za-z-]*\)".*/\1/p'); "#
            + #"printf '{"at":%s,"e":%s}\n' "$(date +%s)" "$p" >> '"# + folder + #"'/"${i:-"# + sessionId + #"}.jsonl""#
        let hook: [String: Any] = ["hooks": [["type": "command", "command": command]]]
        var hooks: [String: Any] = Dictionary(uniqueKeysWithValues: names.map { ($0, [hook]) })
        // Claude's own file edits on a document open in Duo go through the editor, so the user
        // sees them highlighted and nothing writes under their unsaved text (DL-78). The hook
        // answers only for open documents; anything else passes straight through.
        if let cli {
            let q = "'" + cli.replacingOccurrences(of: "'", with: "'\\''") + "'"
            hooks["PreToolUse"] = [["matcher": "Edit|MultiEdit|Write", "hooks": [["type": "command", "command": q + " hook pre-edit", "timeout": 15]]]]
        }
        var settings: [String: Any] = ["hooks": hooks]
        // Lets duo2 reach Duo from inside Claude's sandbox: this one socket only (DL-43, F-29).
        // A no-op when the user's sandbox is off.
        settings["sandbox"] = ["network": ["allowUnixSockets": [ControlEndpoint.defaultSocket]]]
        // Duo's own CLI reads and navigates; it needs no approval. Irreversible commands, when
        // they exist, ask for consent in the app (LR-57).
        settings["permissions"] = ["allow": ["Bash(duo2:*)"]]
        let url = dir.appending(path: "\(sessionId).settings.json")
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        return url
    }

    public struct Event: Sendable, Equatable {
        public var at: Double
        public var name: String
        public var toolName: String?
        public var question: String?
        public var options: [String]?
        public var command: String?
        public var filePath: String?
        public var lastMessage: String?
    }

    /// The last `maxBytes` of a session's events (bounded read, LR-9).
    public static func read(_ sessionId: String, in dir: URL = DuoPaths.events, maxBytes: Int = 256 * 1024) -> [Event] {
        guard let h = try? FileHandle(forReadingFrom: file(for: sessionId, in: dir)) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if start > 0, !lines.isEmpty { lines.removeFirst() }  // probably cut mid-line
        return lines.compactMap { parse(Data($0)) }
    }

    static func parse(_ line: Data) -> Event? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let at = (obj["at"] as? NSNumber)?.doubleValue,
              let e = obj["e"] as? [String: Any],
              let name = e["hook_event_name"] as? String else { return nil }
        let input = e["tool_input"] as? [String: Any]
        let q = (input?["questions"] as? [[String: Any]])?.first
        return Event(at: at, name: name,
                     toolName: e["tool_name"] as? String,
                     question: q?["question"] as? String,
                     options: (q?["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String },
                     command: input?["command"] as? String,
                     filePath: (input?["file_path"] ?? input?["notebook_path"]) as? String,
                     lastMessage: e["last_assistant_message"] as? String)
    }

    /// What the hooks say about a session right now.
    public struct Summary: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case pending, stopped }
        public var kind: Kind
        public var at: Double
        public var reason: Attention.Reason
        public var question: String?
        public var options: [String]?
        public var message: String?
    }

    /// A permission request (AskUserQuestion included) not yet followed by its tool running, a
    /// new prompt or the turn ending is pending. Otherwise the last `Stop` of the latest turn.
    public static func summarize(_ events: [Event]) -> Summary? {
        var pending: Summary?
        var stopped: Summary?
        for e in events {
            switch e.name {
            case "PermissionRequest":
                if e.toolName == "AskUserQuestion" {
                    pending = Summary(kind: .pending, at: e.at, reason: .question, question: e.question, options: e.options)
                } else {
                    let file = e.filePath.map { ($0 as NSString).lastPathComponent }
                    let what = e.command.map { "`\($0)`" } ?? [e.toolName, file.map { "to \($0)" }].compactMap { $0 }.joined(separator: " ").nonEmpty ?? "a tool"
                    pending = Summary(kind: .pending, at: e.at, reason: .permission, question: "Allow \(what)?")
                }
            case "PostToolUse", "SessionStart", "SessionEnd":
                // A resumed session keeps its finished turn: only a new prompt clears it.
                pending = nil
            case "UserPromptSubmit":
                pending = nil
                stopped = nil
            case "Stop":
                pending = nil
                let m = e.lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                let asks = m?.hasSuffix("?") == true
                stopped = Summary(kind: .stopped, at: e.at, reason: asks ? .question : .blocked,
                                  question: asks ? m.flatMap(lastParagraph) : nil, message: m)
            default: break
            }
        }
        return pending ?? stopped
    }

    static func lastParagraph(_ s: String) -> String {
        let paras = s.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return paras.last ?? s
    }

    /// First line of a message, for a ready-for-review card's summary.
    public static func headline(_ s: String?) -> String? {
        guard let line = s?.split(separator: "\n").first.map(String.init) else { return nil }
        let t = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*- ").union(.whitespaces))
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        return t.count > 140 ? String(t.prefix(139)) + "…" : t
    }
}

extension Attention {
    /// The state of a live session from its beacon and, for sessions Duo started, its hooks
    /// (handoff §2.2; F-23). `seenAt` is Duo's "seen" mark (§10): a finished turn is ready for
    /// review until you look at the session.
    public static func live(beacon: Beacon, hooks: HookEvents.Summary?, seenAt: Double?)
        -> (state: SessionState, question: String?, options: [String]?, summary: String?, since: Double?) {
        let updated = beacon.statusUpdatedAt
        switch beacon.status {
        case "busy":
            return (.working, nil, nil, nil, updated)
        case "waiting":
            let h = hooks?.kind == .pending ? hooks : nil
            let fallback = beacon.waitingFor == "permission prompt" ? "Waiting for permission" : "Waiting for your answer"
            return (.needsYou, h?.question ?? fallback, h?.options, nil, h.map { $0.at * 1000 } ?? updated)
        default:
            guard let h = hooks, h.kind == .stopped else { return (.idle, nil, nil, nil, updated) }
            if h.reason == .question { return (.needsYou, h.question, nil, nil, h.at * 1000) }
            if let seenAt, seenAt >= h.at { return (.idle, nil, nil, nil, updated) }
            return (.readyForReview, nil, nil, HookEvents.headline(h.message), h.at * 1000)
        }
    }
}

/// Duo's own small state file (Q-13): seen marks now; the registry later (Phase E).
public struct DuoState: Codable, Sendable, Equatable {
    public var seen: [String: Double] = [:]
    /// The Home folder Duo chose (DL-42), so a second HOME.md never silently takes over.
    public var home: String?
    /// "Not Now" on Home's prompt (DL-100): the pane stays collapsed at All projects until a Home is chosen.
    public var homePromptDismissed = false
    /// Documents whose properties block is folded (frontmatter-handoff §2), by path.
    public var foldedProperties: [String] = []
    /// Missing folders the user removed from Duo (DB-8): their sessions stay in Claude's storage.
    public var forgottenFolders: [String] = []
    /// Folders whose Make a Project notice the user said Not Now to (DL-110), by path.
    public var notNowFolders: [String] = []
    /// Legacy Duo's findings the user said Not Now to (asked again when they change), and the last backup (DL-39).
    /// Settings (S3-1): a chosen `claude` (LR-19; nil = found automatically), and notifications (S3-6).
    public var claudePath: String?
    public var notifyNeedsYou = true
    public var dockBadge = true
    public var legacyDismissed: String?
    public var legacyBackup: String?
    /// Home's folder, the container of the user's tracked projects (DL-85), once chosen. Without it
    /// Duo still lists every session (DL-82).
    public var root: String?
    /// A release the user chose not to download from the update notice; not offered again.
    public var skippedUpdate: String?
    /// Answers to the .gitignore offer, by repository root (DL-50).
    public var gitignore: [String: String] = [:]
    /// Folders made projects outside the workspace root (DL-63): discovery includes them.
    public var projects: [String] = []
    /// Projects and folders filed away (ENH-6): out of the map's columns, into its Archived rollup.
    /// Filing only: counts, search and sessions are unchanged. By folder path.
    public var archivedProjects: [String] = []
    /// Sessions filed away (Geoff, 2026-10-04): out of every list and count, kept, still searchable,
    /// shown under their project's Archived fold. By session id.
    public var archivedSessions: [String] = []
    /// The map's order (DL-104): "recent" (the default) or "name".
    public var mapSort: String?
    /// View › Show Hidden Files (DL-105).
    public var showHiddenFiles = false

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seen = try c.decodeIfPresent([String: Double].self, forKey: .seen) ?? [:]
        home = try c.decodeIfPresent(String.self, forKey: .home)
        root = try c.decodeIfPresent(String.self, forKey: .root)
        skippedUpdate = try c.decodeIfPresent(String.self, forKey: .skippedUpdate)
        homePromptDismissed = try c.decodeIfPresent(Bool.self, forKey: .homePromptDismissed) ?? false
        foldedProperties = try c.decodeIfPresent([String].self, forKey: .foldedProperties) ?? []
        forgottenFolders = try c.decodeIfPresent([String].self, forKey: .forgottenFolders) ?? []
        notNowFolders = try c.decodeIfPresent([String].self, forKey: .notNowFolders) ?? []
        legacyDismissed = try c.decodeIfPresent(String.self, forKey: .legacyDismissed)
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath)
        notifyNeedsYou = try c.decodeIfPresent(Bool.self, forKey: .notifyNeedsYou) ?? true
        dockBadge = try c.decodeIfPresent(Bool.self, forKey: .dockBadge) ?? true
        legacyBackup = try c.decodeIfPresent(String.self, forKey: .legacyBackup)
        gitignore = try c.decodeIfPresent([String: String].self, forKey: .gitignore) ?? [:]
        projects = try c.decodeIfPresent([String].self, forKey: .projects) ?? []
        archivedProjects = try c.decodeIfPresent([String].self, forKey: .archivedProjects) ?? []
        archivedSessions = try c.decodeIfPresent([String].self, forKey: .archivedSessions) ?? []
        mapSort = try c.decodeIfPresent(String.self, forKey: .mapSort)
        showHiddenFiles = try c.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
    }

    public static func load(_ url: URL = DuoPaths.state) -> DuoState {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DuoState.self, from: $0) } ?? DuoState()
    }

    /// Read, change, write atomically. Throttled by the caller (once per refresh at most).
    public static func update(_ url: URL = DuoPaths.state, _ change: (inout DuoState) -> Void) {
        var s = load(url)
        let before = s
        change(&s)
        guard s != before, let data = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
