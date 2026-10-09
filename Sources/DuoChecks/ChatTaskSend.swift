import DuoControl
import DuoKit
import Foundation

// A session started under a task has the task's path drafted in Claude's prompt (DL-112). Sending from
// chat's composer must carry the path and the words, on both hand-overs (Ctrl+G and paste), and a
// refusal must keep the words in the composer (F-254). Real `claude` TUI against the spike's mock API:
// no tokens. Several versions at once: DUO_TASKSEND_CLAUDE="/path/claude,/other/claude".
//
//   DUO_SUPPORT_DIR=/tmp/duo-ts DUO_CHECKS=task-send swift run DuoChecks

@MainActor func chatTaskSendChecks() throws {
    let spike = repoRoot().appending(path: "Spikes/chat-mode")
    guard let node = which("node") else { print("task-send: needs node on PATH; skipped"); return }
    guard ProcessInfo.processInfo.environment["DUO_SUPPORT_DIR"] != nil else { print("task-send: set DUO_SUPPORT_DIR to a scratch folder"); failures += 1; return }
    let claudes = ProcessInfo.processInfo.environment["DUO_TASKSEND_CLAUDE"].map { $0.split(separator: ",").map(String.init) } ?? [which("claude")].compactMap { $0 }
    for (i, claude) in claudes.enumerated() {
        let version = run(claude, ["--version"]).split(separator: " ").first.map(String.init)
        print("task send: a task's drafted path and your words, against Claude Code \(version ?? "?") and the mock API")
        let dir = "/tmp/duo-ts-\(i)"
        try? FileManager.default.removeItem(atPath: dir)
        _ = run("/bin/zsh", [spike.appending(path: "scratch.sh").path, dir])
        let port = freePort() ?? (18865 + i)
        let mock = Process()
        mock.executableURL = URL(fileURLWithPath: node)
        mock.arguments = [spike.appending(path: "mock.mjs").path]
        mock.environment = ProcessInfo.processInfo.environment.merging(["MOCK_PORT": "\(port)", "MOCK_CWD": dir + "/ws", "MOCK_LOG": dir + "/mock.log"]) { $1 }
        mock.standardOutput = FileHandle.nullDevice; mock.standardError = FileHandle.nullDevice
        try mock.run()
        defer { mock.terminate() }
        var up = false
        for _ in 0..<40 where !up {
            spin(0.15)
            up = run("/usr/bin/curl", ["-s", "-o", "/dev/null", "-m", "1", "-w", "%{http_code}", "http://127.0.0.1:\(port)/"]).count == 3
        }
        guard up, mock.isRunning else { check(false, "the mock API answers on port \(port)"); continue }
        try taskSendCases(dir: dir, port: port, claude: claude, version: version)
    }
}

@MainActor func taskSendCases(dir: String, port: Int, claude: String, version: String?) throws {
    let id = UUID().uuidString.lowercased()
    let bin = repoRoot().appending(path: ".build/out/Products/Debug/duo2").path
    let composeDir = dir + "/compose"
    let settings = try HookEvents.settingsFile(for: id, chatEvents: true)
    let ws = dir + "/ws"
    let editor = ChatComposer.editorCommand(cli: bin) ?? ""
    let env = ["HOME=\(NSHomeDirectory())", "PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")", "TERM=xterm-256color", "LANG=en_US.UTF-8",
               "CLAUDE_CONFIG_DIR=\(dir)/cfg", "ANTHROPIC_BASE_URL=http://127.0.0.1:\(port)", "ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000",
               "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1", "DISABLE_AUTOUPDATER=1",
               "DUO_SESSION_ID=\(id)", "EDITOR=\(editor)", "VISUAL=\(editor)",
               "\(ChatCompose.dirVariable)=\(composeDir)", "\(ChatCompose.userEditor)=/usr/bin/true"]
    let tui = HeadlessTUI(cols: 100, rows: 34)
    setenv("CLAUDE_CONFIG_DIR", dir + "/cfg", 1)
    tui.process.startProcess(executable: claude, args: ["--session-id", id, "--settings", settings.path, "--model", devModel()],
                             environment: env, execName: nil, currentDirectory: ws)
    defer { tui.process.terminate(); unsetenv("CLAUDE_CONFIG_DIR") }
    let chat = ChatSession(key: id, mode: .chat)
    chat.setVersion(version)
    chat.attach(tui)
    chat.composeDir = URL(fileURLWithPath: composeDir)
    chat.follow(sessionId: id, cwd: URL(fileURLWithPath: ws).resolvingSymlinksInPath().path)
    func until(_ s: TimeInterval, _ f: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(s)
        while Date() < end { if f() { return true }; spin(0.1) }
        return f()
    }
    func await_<T>(_ f: @escaping () async -> T) -> T? {
        var r: T?
        Task { r = await f() }
        _ = until(40) { r != nil }
        return r
    }
    func lastPrompt(after offset: Int) -> String? {
        guard let url = ClaudeStorage.transcript(sessionId: id, cwd: ws), let data = try? Data(contentsOf: url), data.count > offset else { return nil }
        return data.suffix(from: offset).split(separator: UInt8(ascii: "\n")).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            .last { $0["type"] as? String == "user" && ($0["message"] as? [String: Any])?["content"] is String }
            .flatMap { ($0["message"] as? [String: Any])?["content"] as? String }
    }
    func transcriptSize() -> Int { ClaudeStorage.transcript(sessionId: id, cwd: ws).flatMap { try? Data(contentsOf: $0) }?.count ?? 0 }
    func fold(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    let idle = { until(30) { chat.reread().kind == .idle } }
    check(idle(), "the TUI reaches its prompt (\(chat.screen.kind))")

    let draft = TaskNotes.draft(path: "tasks/exec-review-prep.md")
    let words = (1...330).map { "word\($0)" }.joined(separator: " ")   // 2,000+ characters
    let texts: [(String, String)] = [("short", "Please summarise the open risks."), ("long", words), ("multi-line", "First line.\n\nSecond paragraph, with detail.\n- a bullet\n- another")]
    let tag = " SCENARIO:hello"
    let only = ProcessInfo.processInfo.environment["DUO_TASKSEND_ONLY"]
    for (path, useEditor) in [("Ctrl+G hand-over", true), ("paste", false)] where only.map({ path.contains($0) }) ?? true {
        if useEditor && !chat.usesExternalEditor { print("  (\(path) not available on \(version ?? "?"))"); continue }
        for prefilled in useEditor ? [false, true] : [false] {
            for (kind, text) in texts {
                let name = "\(path), \(kind) text, composer \(prefilled ? "shows the draft" : "doesn’t show it")"
                _ = idle()
                chat.composeDir = useEditor ? URL(fileURLWithPath: composeDir) : nil
                chat.fallback = nil
                tui.sendKeys("\u{1b}[200~" + draft + "\u{1b}[201~"); spin(0.8)
                var composer = text + tag
                chat.ui.composerBasis = nil
                if prefilled {
                    let real = await_ { await chat.peekPrompt() } ?? nil
                    chat.ui.composerBasis = real
                    composer = (real ?? "") + " " + text + tag
                }
                let from = transcriptSize()
                let r = await_ { await chat.send(composer) }
                _ = idle(); spin(1)
                let got = lastPrompt(after: from)
                let want = fold(prefilled ? composer : draft + text + tag)
                let ok = r?.ok == true && got.map(fold) == want
                check(ok, "\(name) → Claude gets the path and the words" + (ok ? "" : "  (\(r?.ok == true ? "sent" : "refused: \(r?.why ?? "no reply")"); got \(got.map { String($0.prefix(60)) } ?? "nothing"))"))
                // whatever is left in the prompt
                for _ in 0..<6 where !(chat.reread().input ?? "").isEmpty { tui.sendKeys("\u{3}"); spin(0.6) }
                _ = idle(); spin(0.3)
                chat.fallback = nil
            }
        }
    }
}
