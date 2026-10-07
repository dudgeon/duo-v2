import Foundation

/// The chat-mode-handoff boards as window states (`--state chat-<board>`), each drawn from a
/// recording in `docs/design/chat-mode-handoff/fixture-chat/<board>/` (bundled as
/// `Resources/chat-fixtures`): `meta.json` (mode, fallback, CLI version, tabs), and optionally
/// `events.jsonl` (hook payloads, as Duo's hooks write them), `transcript.jsonl` (Claude's
/// transcript lines) and `screen.txt` (the TUI's screen). The same readers as a live session read
/// them, so the targets exercise the real pipeline. `scripts/check-chat.sh` captures and compares.
@MainActor
public enum ChatTargets {
    nonisolated public static let boards = ["window", "toggle", "text", "tools", "permission-edit", "permission-bash", "plan", "question-multi",
                                            "question-other", "question-review", "question-previews", "question-chat-decline", "composer", "status", "fallback",
                                            // chat-polish-handoff (DL-135): runs folded, and the candidates folded with them.
                                            "polish-collapsed", "polish-expanded", "polish-needs-you", "polish-output", "polish-edits", "polish-thinking",
                                            "polish-agents", "polish-todos", "polish-tools", "polish-failed", "polish-paste"]
    nonisolated public static let screens = boards.map { "chat-" + $0 }

    public static func folder(_ board: String) -> URL? {
        if let r = Bundle.main.url(forResource: "chat-fixtures", withExtension: nil) { return r.appending(path: board) }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let handoff = board.hasPrefix("polish-") ? "chat-polish-handoff" : "chat-mode-handoff"
        for _ in 0..<6 {
            let c = dir.appending(path: "docs/design/\(handoff)/fixture-chat/\(board)")
            if FileManager.default.fileExists(atPath: c.path) { return c }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    public static func apply(_ screen: String, to model: AppModel) {
        let board = String(screen.dropFirst("chat-".count))
        TargetState.project.apply(to: model)
        guard let dir = folder(board) else { return }
        let meta = (try? Data(contentsOf: dir.appending(path: "meta.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let tab = meta["tab"] as? String ?? "PRD v2 edits"
        model.consoleTab = tab
        // Tabs the board draws: its sessions' states, and any shells.
        for (name, state) in meta["states"] as? [String: String] ?? [:] {
            if let i = model.fixture.sessions.firstIndex(where: { $0.name == name }), let st = SessionState(rawValue: state) { model.fixture.sessions[i].state = st }
        }
        if let shells = meta["shells"] as? [String], let project = model.currentProject?.name {
            let keys = shells.map { AppModel.shellPrefix + $0 }
            for (k, n) in zip(keys, shells) { model.shellTitles[k] = n }
            model.shellTabs[project] = keys
        }
        let chat = ChatSession(key: tab, mode: ChatViewMode(rawValue: meta["mode"] as? String ?? "chat") ?? .chat)
        chat.lastDeclined = meta["lastDeclined"] as? String
        if meta["focusComposer"] as? Bool == true { chat.focusComposer += 1 }
        // Files a card reads (an edit's line numbers, a plan), as the board's project has them.
        let files = meta["files"] as? [String: String] ?? [:]
        chat.readFile = { files[$0] }
        chat.answersToReplay = (meta["answers"] as? [[String: String]] ?? []).compactMap { a in
            guard let at = a["at"].flatMap({ ChatIngest.iso.date(from: $0) }), let text = a["text"] else { return nil }
            return (at, text)
        }
        chat.setVersion(meta["version"] as? String ?? "2.1.291")
        ChatRecording.play(dir, into: chat, now: meta["now"] as? String)
        for id in meta["toggled"] as? [String] ?? [] { chat.ui.toggled.insert(id) }
        for id in meta["openRuns"] as? [String] ?? [] { chat.ui.openRuns.insert(id) }
        if let d = meta["drafts"] as? [String: String] {
            chat.ui.planFeedback = d["plan"] ?? ""
            chat.ui.notes = d["notes"] ?? ""
            chat.ui.composer = d["composer"] ?? ""
        }
        // An interrupted reply ends on the screen, not a hook (F-105): the busy → idle the TUI drew.
        if meta["interruptAfterPlay"] as? Bool == true { chat.log.endStreaming(interrupted: true) }
        if let f = meta["fallback"] as? [String: String] {
            chat.fallback = ChatFallback(kind: f["kind"] == "handedOver" ? .handedOver : .automatic, message: f["message"] ?? ChatFallback.unknownScreen.message)
        }
        model.fixtureChats[tab] = chat
    }
}

/// Plays a recording into a chat: the transcript, then the hooks, then the screen.
@MainActor
public enum ChatRecording {
    public static func play(_ dir: URL, into chat: ChatSession, now: String? = nil) {
        // Board times are the boards' own (9:41): read and shown in UTC, whatever the Mac's zone.
        ChatWho.clock.timeZone = TimeZone(identifier: "UTC")
        if let now, let d = ChatIngest.iso.date(from: now) ?? ISO8601DateFormatter().date(from: now) { chat.fixedNow = d }
        chat.log.cwd = "/Users/pm/work/payments/checkout-redesign"
        // Both sources, in the order things happened (a transcript line before a hook at the same moment).
        let t = (try? Data(contentsOf: dir.appending(path: "transcript.jsonl"))).map(ChatIngest.lines) ?? []
        let e = (try? Data(contentsOf: dir.appending(path: "events.jsonl"))).map(ChatIngest.lines) ?? []
        var all: [(at: Double, n: Int, hook: Bool, obj: ChatJSON)] = []
        for (n, r) in t.enumerated() {
            all.append(((r["timestamp"] as? String).flatMap { ChatIngest.iso.date(from: $0) }?.timeIntervalSince1970 ?? 0, n, false, r))
        }
        for (n, r) in e.enumerated() { all.append(((r["at"] as? NSNumber)?.doubleValue ?? 0, t.count + n, true, r)) }
        // Answers the card itself writes (`You chose …`), at the moment they were given.
        for (n, a) in chat.answersToReplay.enumerated() { all.append((a.at.timeIntervalSince1970, t.count + e.count + n, true, ["answer": a.text])) }
        for x in all.sorted(by: { ($0.at, $0.n) < ($1.at, $1.n) }) {
            if let text = x.obj["answer"] as? String { chat.log.answer(text, time: Date(timeIntervalSince1970: x.at)); continue }
            if x.hook, let p = x.obj["e"] as? ChatJSON { ChatIngest.hook(p, at: x.at, into: chat.log, chat: chat) }
            else if !x.hook { ChatIngest.record(x.obj, into: chat.log, chat: chat) }
        }
        if let text = try? String(contentsOf: dir.appending(path: "screen.txt"), encoding: .utf8) {
            chat.fixtureScreenText = text
            chat.apply(ChatScreenReader.read(text, table: chat.signatures))
        }
    }
}
