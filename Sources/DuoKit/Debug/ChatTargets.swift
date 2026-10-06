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
                                            "question-other", "question-review", "question-previews", "question-chat-decline", "composer", "status", "fallback"]
    nonisolated public static let screens = boards.map { "chat-" + $0 }

    public static func folder(_ board: String) -> URL? {
        if let r = Bundle.main.url(forResource: "chat-fixtures", withExtension: nil) { return r.appending(path: board) }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appending(path: "docs/design/chat-mode-handoff/fixture-chat/\(board)")
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
        chat.setVersion(meta["version"] as? String ?? "2.1.291")
        ChatRecording.play(dir, into: chat, now: meta["now"] as? String)
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
        if let text = try? String(contentsOf: dir.appending(path: "screen.txt"), encoding: .utf8) {
            chat.fixtureScreenText = text
            chat.apply(ChatScreenReader.read(text, table: chat.signatures))
        }
    }
}
