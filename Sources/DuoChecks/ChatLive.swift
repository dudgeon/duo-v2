import DuoControl
import DuoKit
import Foundation
import SwiftTerm

// The spike's end-to-end AskUserQuestion test (Spikes/chat-mode/asktest.mjs, F-106), ported to Duo's
// own code: the real `claude` TUI runs in a headless SwiftTerm terminal against the spike's mock
// Messages API (no credentials, no tokens, a scratch CLAUDE_CONFIG_DIR), with Duo's per-session
// hooks; ChatSession reads its screen and hooks and answers with intents, and each case checks
// what Claude received (the transcript's toolUseResult) against what was clicked.
//
//   DUO_SUPPORT_DIR=/tmp/duo-chat-live DUO_CHECKS=chat-live swift run DuoChecks
//
// Needs node and claude on PATH. Runs at 100×34, 60×34 and 80×20, as asktest.sh did.

/// A terminal with no view: the PTY's bytes go into SwiftTerm's own Terminal.
@MainActor final class HeadlessTUI: ChatTerminal, LocalProcessDelegate {
    let term: Terminal
    var process: LocalProcess!
    let cols: Int, rows: Int
    var output: (@MainActor () -> Void)?
    var exited = false

    init(cols: Int, rows: Int) {
        self.cols = cols; self.rows = rows
        var o = TerminalOptions.default
        o.cols = cols; o.rows = rows
        term = Terminal(delegate: HeadlessTUI.Sink.shared, options: o)
        process = LocalProcess(delegate: self, dispatchQueue: .main)
        HeadlessTUI.Sink.shared.process = process
    }

    /// Answers terminal queries (cursor position, device attributes) back into the PTY.
    final class Sink: TerminalDelegate {
        nonisolated(unsafe) static let shared = Sink()
        nonisolated(unsafe) var process: LocalProcess?
        func send(source: Terminal, data: ArraySlice<UInt8>) { process?.send(data: data) }
        func showCursor(source: Terminal) {}
        func hideCursor(source: Terminal) {}
        func setTerminalTitle(source: Terminal, title: String) {}
        func setTerminalIconTitle(source: Terminal, title: String) {}
        func windowCommand(source: Terminal, command: Terminal.WindowManipulationCommand) -> [UInt8]? { nil }
        func sizeChanged(source: Terminal) {}
        func bufferActivated(source: Terminal) {}
        func bell(source: Terminal) {}
        func selectionChanged(source: Terminal) {}
        func isProcessTrusted(source: Terminal) -> Bool { true }
        func mouseModeChanged(source: Terminal) {}
        func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {}
        func hostCurrentDirectoryUpdated(source: Terminal) {}
        func hostCurrentDocumentUpdated(source: Terminal) {}
        func colorChanged(source: Terminal, idx: Int?) {}
        func setForegroundColor(source: Terminal, color: SwiftTerm.Color) {}
        func setBackgroundColor(source: Terminal, color: SwiftTerm.Color) {}
        func setCursorColor(source: Terminal, color: SwiftTerm.Color?) {}
        func getColors(source: Terminal) -> (foreground: SwiftTerm.Color, background: SwiftTerm.Color) { (SwiftTerm.Color(red: 65535, green: 65535, blue: 65535), SwiftTerm.Color(red: 0, green: 0, blue: 0)) }
        func iTermContent(source: Terminal, content: ArraySlice<UInt8>) {}
        func clipboardCopy(source: Terminal, content: Data) {}
    }

    // LocalProcessDelegate
    nonisolated func processTerminated(_ source: LocalProcess, exitCode: Int32?) { MainActor.assumeIsolated { exited = true } }
    nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { term.feed(buffer: slice); output?() }
    }
    nonisolated func getWindowSize() -> winsize {
        MainActor.assumeIsolated { winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0) }
    }

    // ChatTerminal
    func screenLines() -> [String] { (0..<rows).map { term.getLine(row: $0)?.translateToString(trimRight: true) ?? "" } }
    var columns: Int { cols }
    func sendKeys(_ text: String) { process.send(data: Array(text.utf8)[...]) }
    func onOutput(_ f: @escaping @MainActor () -> Void) { output = f }
}

/// One AskUserQuestion case: a prompt for the mock, the intents a card would send, and what Claude must receive.
struct AskCase {
    let name: String
    let prompt: String
    let steps: [(ChatAskIntent, stale: Bool)]
    var answers: [String: String]?
    var declined = false
    var notes: String?
    var refused = 0
}

@MainActor func chatLiveChecks() throws {
    let spike = repoRoot().appending(path: "Spikes/chat-mode")
    guard let claude = which("claude"), let node = which("node") else { print("chat-live: needs claude and node on PATH; skipped"); return }
    guard ProcessInfo.processInfo.environment["DUO_SUPPORT_DIR"] != nil else { print("chat-live: set DUO_SUPPORT_DIR to a scratch folder"); failures += 1; return }
    let version = run(claude, ["--version"]).split(separator: " ").first.map(String.init)
    print("chat mode, live: AskUserQuestion end to end against Claude Code \(version ?? "?") and the mock API (F-106)")
    let only = ProcessInfo.processInfo.environment["DUO_CHAT_LIVE_SIZES"].map { $0.split(separator: ",").map(String.init) }
    for (i, size) in [(100, 34), (60, 34), (80, 20)].enumerated() where only?.contains("\(size.0)x\(size.1)") ?? true {
        print("  — \(size.0)×\(size.1)")
        let dir = "/tmp/duo-chat-live-\(size.0)x\(size.1)"
        try? FileManager.default.removeItem(atPath: dir)
        _ = run("/bin/zsh", [spike.appending(path: "scratch.sh").path, dir])
        // A free port of its own: other sessions run the spike's mock on 8765 (seen while testing).
        let port = freePort() ?? (18765 + i)
        let mock = Process()
        mock.executableURL = URL(fileURLWithPath: node)
        mock.arguments = [spike.appending(path: "mock.mjs").path]
        mock.environment = ProcessInfo.processInfo.environment.merging(["MOCK_PORT": "\(port)", "MOCK_CWD": dir + "/ws", "MOCK_LOG": dir + "/mock.log"]) { $1 }
        mock.standardOutput = FileHandle.nullDevice; mock.standardError = FileHandle.nullDevice
        try mock.run()
        defer { mock.terminate() }
        // Wait until it answers: a port the last run still holds would otherwise fail every case.
        var up = false
        for _ in 0..<40 where !up {
            spin(0.15)
            up = run("/usr/bin/curl", ["-s", "-o", "/dev/null", "-m", "1", "-w", "%{http_code}", "http://127.0.0.1:\(port)/"]).count == 3
        }
        guard up, mock.isRunning else { check(false, "the mock API answers on port \(port)"); continue }
        try askCases(size: size, dir: dir, port: port, claude: claude, version: version)
    }
}

@MainActor func askCases(size: (Int, Int), dir: String, port: Int, claude: String, version: String?) throws {
    let id = UUID().uuidString.lowercased()
    // The composer's helper (F-112): this build's duo2 as Claude's external editor.
    let bin = repoRoot().appending(path: ".build/out/Products/Debug/duo2").path
    let composeDir = dir + "/compose"
    let settings = try HookEvents.settingsFile(for: id, chatEvents: true)
    let ws = dir + "/ws"
    let env = ["HOME=\(NSHomeDirectory())", "PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")", "TERM=xterm-256color", "LANG=en_US.UTF-8",
               "CLAUDE_CONFIG_DIR=\(dir)/cfg", "ANTHROPIC_BASE_URL=http://127.0.0.1:\(port)", "ANTHROPIC_API_KEY=sk-ant-mock-key-0000000000000000000",
               "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1", "DISABLE_AUTOUPDATER=1",
               "DUO_SESSION_ID=\(id)", "EDITOR=\(ProcessInfo.processInfo.environment["DUO_CHAT_LIVE_EDITOR"] ?? ChatComposer.editorCommand(cli: bin) ?? "")", "VISUAL=\(ProcessInfo.processInfo.environment["DUO_CHAT_LIVE_EDITOR"] ?? ChatComposer.editorCommand(cli: bin) ?? "")",
               "\(ChatCompose.dirVariable)=\(composeDir)", "\(ChatCompose.userEditor)=/usr/bin/true"]
    let tui = HeadlessTUI(cols: size.0, rows: size.1)
    setenv("CLAUDE_CONFIG_DIR", dir + "/cfg", 1)   // where ChatFeed finds the transcript
    tui.process.startProcess(executable: claude, args: ["--session-id", id, "--settings", settings.path, "--model", TestModel.model(environment: ProcessInfo.processInfo.environment, isolated: true, bundleID: nil)!],
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
    let idle = { until(30) { chat.reread().kind == .idle } }
    check(idle(), "the TUI reaches its prompt (\(chat.screen.kind))")
    let cases: [AskCase] = [
        AskCase(name: "single: pick", prompt: "ask1", steps: [(.pick("SQLite"), false)], answers: ["Which database should we use?": "SQLite"]),
        AskCase(name: "single: Other text", prompt: "ask1", steps: [(.other("DuckDB"), false)], answers: ["Which database should we use?": "DuckDB"]),
        AskCase(name: "multi: two ticks", prompt: "askmulti1", steps: [(.toggle("Lint"), false), (.toggle("Build"), false), (.next, false), (.submit, false)],
                answers: ["Which checks should run on every commit?": "Lint, Build"]),
        AskCase(name: "multi: untick", prompt: "askmulti1", steps: [(.toggle("Lint"), false), (.toggle("Unit tests"), false), (.toggle("Lint"), false), (.next, false), (.submit, false)],
                answers: ["Which checks should run on every commit?": "Unit tests"]),
        AskCase(name: "multi: tick + Other", prompt: "askmulti1", steps: [(.toggle("Type check"), false), (.other("Docs build"), false), (.next, false), (.submit, false)],
                answers: ["Which checks should run on every commit?": "Type check, Docs build"]),
        AskCase(name: "four questions, back and change", prompt: "ask4", steps: [
            (.pick("AppKit"), false), (.toggle("General"), false), (.toggle("Advanced"), false), (.next, false), (.pick("Keychain"), false),
            (.tab(0), false), (.pick("SwiftUI (Recommended)"), false), (.tab(3), false), (.toggle("macOS"), false), (.other("watchOS"), false), (.next, false), (.submit, false)],
            answers: ["Which framework should the settings page use?": "SwiftUI (Recommended)", "Which sections should it have?": "General, Advanced",
                      "Where should settings be stored?": "Keychain", "Which platforms need it first?": "macOS, watchOS"]),
        AskCase(name: "long, wrapped labels", prompt: "asklong", steps: [(.pick("Copy, verify, then delete"), false)],
                answers: ["This question is deliberately long so that it wraps across more than one line of the terminal at its usual width: which migration strategy should we use for the existing sessions folder?": "Copy, verify, then delete"]),
        AskCase(name: "preview: pick", prompt: "askpreview", steps: [(.pick("Compact"), false)], answers: ["Which layout should the card use?": "Compact"]),
        AskCase(name: "preview: notes", prompt: "askpreview", steps: [(.notes("Side by side", "keep it short"), false)], answers: ["Which layout should the card use?": "Side by side"], notes: "keep it short"),
        AskCase(name: "chat about this", prompt: "ask1", steps: [(.chat, false)], declined: true),
        AskCase(name: "decline (Esc)", prompt: "askmulti1", steps: [(.decline, false)], declined: true),
        AskCase(name: "review: cancel", prompt: "askmulti1", steps: [(.toggle("Build"), false), (.next, false), (.cancelReview, false)], declined: true),
        AskCase(name: "stale card is refused", prompt: "ask1", steps: [(.pick("SQLite"), true), (.pick("Postgres"), false)], answers: ["Which database should we use?": "Postgres"], refused: 1),
    ]
    let only = ProcessInfo.processInfo.environment["DUO_CHAT_LIVE_CASES"]
    for c in cases where only.map({ c.name.contains($0) }) ?? true {
        let transcript = ClaudeStorage.transcript(sessionId: id, cwd: ws)
        let before = transcript.flatMap { try? Data(contentsOf: $0) }?.count ?? 0
        tui.sendKeys("\u{1b}[200~SCENARIO:\(c.prompt)\u{1b}[201~"); spin(0.2); tui.sendKeys("\r")
        guard until(20, { chat.reread().kind == .question && chat.pendingRequest?.tool == "AskUserQuestion" }) else {
            check(false, "\(c.name): the question appears (\(chat.screen.kind))"); tui.sendKeys("\u{1b}"); _ = idle(); continue
        }
        spin(0.3)
        var refused = 0, error: String?
        for (intent, stale) in c.steps {
            var r: ChatAnswerResult?
            let sig = stale ? "q:Some older question?" : chat.reread().sig
            Task { r = await chat.ask(intent, sig: sig) }
            _ = until(20) { r != nil }
            if r?.ok != true {
                refused += 1
                if !stale {
                    error = "\(intent): \(r?.why ?? "no reply")"
                    try? (tui.screenLines().joined(separator: "\n") + "\n---\n\(chat.screen)\n---\n\(chat.askedQuestions)").write(toFile: "\(dir)/refused-\(c.name.replacingOccurrences(of: " ", with: "_")).txt", atomically: true, encoding: .utf8)
                    break
                }
            }
            chat.fallback = nil
            spin(0.35)
        }
        _ = idle(); spin(0.6)
        let got = lastAnswer(transcript ?? ClaudeStorage.transcript(sessionId: id, cwd: ws), after: before)
        var ok = error == nil && got != nil
        if ok, let want = c.answers { ok = got?.answers == want }
        if ok, c.declined { ok = got?.declined == true }
        if ok, let n = c.notes { ok = got?.notes.contains(n) == true }
        if ok { ok = refused == c.refused }
        check(ok, "\(c.name)" + (ok ? "" : "  (\(error ?? "") got \(String(describing: got)))"))
        if chat.reread().kind != .idle { tui.sendKeys("\u{1b}"); _ = idle() }
    }
    guard only == nil || only == "none", size.0 == 100 else { return }

    // A streamed reply: MessageDisplay draws it as it comes; the transcript's block matches it.
    prompt("md")
    let streamed = until(20) { chat.log.streams && chat.log.writing }
    _ = idle(); spin(2.5)
    let texts = chat.log.items.compactMap { item -> [ChatText]? in
        guard case .claude(let t) = item else { return nil }
        return t.segments.compactMap { if case .text(let x) = $0 { return x } else { return nil } }
    }.last ?? []
    check(streamed, "MessageDisplay streams the reply while it's written")
    check(texts.count == 1 && texts[0].markdown.contains("## Results") && !texts[0].streaming,
          "the streamed reply shows once, whole, after the transcript catches up (\(texts.count) text blocks)")

    func prompt(_ p: String) { tui.sendKeys("\u{1b}[200~SCENARIO:\(p)\u{1b}[201~"); spin(0.2); tui.sendKeys("\r") }
    func await_<T>(_ f: @escaping () async -> T) -> T? {
        var r: T?
        Task { r = await f() }
        _ = until(20) { r != nil }
        return r
    }
    // The composer (F-104, F-112): Claude's own prompt, handed over through Ctrl+G.
    func lastPrompt(after offset: Int) -> String? {
        guard let url = ClaudeStorage.transcript(sessionId: id, cwd: ws), let data = try? Data(contentsOf: url), data.count > offset else { return nil }
        return data.suffix(from: offset).split(separator: UInt8(ascii: "\n")).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            .last { $0["type"] as? String == "user" && ($0["message"] as? [String: Any])?["content"] is String }
            .flatMap { ($0["message"] as? [String: Any])?["content"] as? String }
    }
    func transcriptSize() -> Int { ClaudeStorage.transcript(sessionId: id, cwd: ws).flatMap { try? Data(contentsOf: $0) }?.count ?? 0 }
    _ = idle()
    var from = transcriptSize()
    let sent = await_ { await chat.send("Hello from the composer, **in Markdown**. SCENARIO:hello") }
    _ = idle(); spin(1)
    check(sent?.ok == true && lastPrompt(after: from) == "Hello from the composer, **in Markdown**. SCENARIO:hello",
          "the composer's text reached Claude through Ctrl+G and duo2 compose (\(sent?.why ?? "ok"))")
    check(chat.log.items.filter { if case .you(let y) = $0 { return y.text.contains("Hello from the composer") } else { return false } }.count == 1,
          "and shows once, matched to its echo")
    tui.sendKeys("half-typed in the terminal"); spin(0.6)
    let carried = await_ { await chat.peekPrompt() } ?? nil
    spin(0.3)
    check(carried == "half-typed in the terminal" && chat.reread().input == "half-typed in the terminal",
          "Claude's real prompt is read through Ctrl+G and left as it was (\(carried ?? "-"))")
    chat.ui.composerBasis = carried
    from = transcriptSize()
    let finished = await_ { await chat.send("half-typed in the terminal, finished here SCENARIO:hello") }
    _ = idle(); spin(1)
    check(finished?.ok == true && lastPrompt(after: from) == "half-typed in the terminal, finished here SCENARIO:hello", "carried over and finished in the composer")
    tui.sendKeys("typed in the terminal meanwhile"); spin(0.6)
    chat.ui.composerBasis = ""
    from = transcriptSize()
    let stale = await_ { await chat.send("This must not replace it") }
    chat.fallback = nil
    spin(0.5)
    check(stale?.ok == false && chat.reread().input == "typed in the terminal meanwhile" && lastPrompt(after: from) == nil,
          "a prompt changed in the terminal is never overwritten; nothing sent (\(stale?.why ?? "-"))")
    for _ in 0..<40 { tui.sendKeys("\u{7f}") }; spin(0.5)
    tui.sendKeys("left in the terminal "); spin(0.5)
    chat.ui.composerBasis = nil
    from = transcriptSize()
    let peeked = await_ { await chat.send("left in the terminal, then sent from chat SCENARIO:hello") }
    _ = idle(); spin(1)
    check(peeked?.ok == true && lastPrompt(after: from) == "left in the terminal, then sent from chat SCENARIO:hello",
          "with no basis known, sending asks Claude's prompt first and replaces what it holds (\(peeked?.why ?? "ok"))")
    let saved = chat.composeDir
    chat.composeDir = nil
    from = transcriptSize()
    let pasted = await_ { await chat.send("Pasted on send SCENARIO:hello") }
    chat.composeDir = saved
    _ = idle(); spin(1)
    check(pasted?.ok == true && lastPrompt(after: from) == "Pasted on send SCENARIO:hello", "paste-on-send, for older CLIs (\(pasted?.why ?? "ok"))")
    prompt("long")
    _ = until(10) { chat.reread().kind == .busy }
    from = transcriptSize()
    let queued = await_ { await chat.send("Queued while Claude works SCENARIO:hello") }
    let wasBusy = chat.screen.kind == .busy || chat.log.writing
    _ = until(40) { lastPrompt(after: from) == "Queued while Claude works SCENARIO:hello" }
    _ = idle(); spin(1)
    let bubbles = chat.log.items.filter { if case .you(let y) = $0 { return y.text.hasPrefix("Queued while") } else { return false } }.count
    check(queued?.ok == true && wasBusy && bubbles == 1 && lastPrompt(after: from) == "Queued while Claude works SCENARIO:hello",
          "a message sent while Claude works is taken, and shows once (sent busy \(wasBusy), \(bubbles) bubble)")

    // `/` in the composer: Claude Code's own command list, read from its screen.
    _ = idle()
    _ = await_ { await chat.mirrorSlash("/mo") }
    _ = until(5) { !chat.reread().commands.isEmpty }
    let cmds = chat.screen.commands.map(\.name)
    check(cmds.contains("/model"), "`/` shows Claude Code's own commands, filtered as typed (\(cmds.prefix(4)))")
    _ = await_ { await chat.mirrorSlash("") }
    spin(0.4)
    check(chat.reread().input == "", "leaving `/` clears what it typed into Claude's prompt")

    // Permissions and the plan (the tour's dialogs), answered from cards.
    func lastResult(after offset: Int) -> [String: Any]? {
        guard let url = ClaudeStorage.transcript(sessionId: id, cwd: ws), let data = try? Data(contentsOf: url), data.count > offset else { return nil }
        return data.suffix(from: offset).split(separator: UInt8(ascii: "\n")).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            .last { (($0["message"] as? [String: Any])?["content"] as? [[String: Any]])?.contains { $0["type"] as? String == "tool_result" } == true }
    }

    var start = transcriptSize()
    prompt("bash")
    if until(20, { chat.reread().kind == .permission && chat.cardUp }) {
        let s = chat.screen
        check(s.kindLabel == "Bash command" && s.options.first?.label == "Yes" && chat.pendingRequest?.tool == "Bash", "a Bash permission card: the screen's labels, the hook's request")
        let r = await_ { await chat.answerOption(1, label: "Yes", sig: s.sig) }
        _ = idle(); spin(0.8)
        let tr = lastResult(after: start)
        check(r?.ok == true && tr != nil && ((tr?["message"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["is_error"] as? Bool != true,
              "Yes from the card: the command ran (its digit, after re-reading the screen)")
        check(chat.log.steps.last { $0.name == "Bash" }?.status == .done, "the Bash step is done in the chat")
    } else { check(false, "the Bash permission appears (\(chat.screen.kind), request \(chat.pendingRequest?.tool ?? "none"))") }

    start = transcriptSize()
    prompt("read")
    if until(25, { chat.reread().kind == .permission && chat.cardUp }) {
        let s = chat.screen
        check(chat.pendingRequest?.tool == "Edit" && s.options.count == 3, "an edit permission card (\(s.options.map(\.label)))")
        let stale = await_ { await chat.answerOption(1, label: "Yes", sig: "perm:Do you want to delete everything?") }
        chat.fallback = nil
        check(stale?.ok == false && chat.reread().kind == .permission, "a stale card is refused and sends nothing")
        let r = await_ { await chat.answerOption(3, label: s.options[2].label, sig: s.sig) }
        _ = idle(); spin(0.8)
        let tr = lastResult(after: start)
        check(r?.ok == true && tr?["toolDenialKind"] != nil, "No from the card: Claude was refused (\(tr?["toolDenialKind"] ?? "-"))")
    } else { check(false, "the edit permission appears (\(chat.screen.kind))") }

    for _ in 0..<4 where chat.reread().mode != .plan { _ = await_ { await chat.cycleMode() }; spin(0.3) }
    check(chat.screen.mode == .plan, "the mode chip's Shift+Tab reaches plan mode")
    start = transcriptSize()
    prompt("plan")
    if until(30, { chat.reread().kind == .plan && chat.cardUp }) {
        check((chat.planText ?? "").contains("Read the code"), "the plan card has the whole plan, from the request")
        let r = await_ { await chat.planFeedback("Also update the docs", sig: chat.screen.sig) }
        _ = until(30) { [.idle, .busy].contains(chat.reread().kind) }
        spin(1.5)
        let tr = lastResult(after: start)
        check(r?.ok == true && (tr?["userFeedback"] as? String ?? (tr.map { String(describing: $0) } ?? "")).contains("Also update the docs"),
              "option 3 from the card: Claude received the feedback")
        tui.sendKeys("\u{1b}"); _ = idle()
    } else { check(false, "the plan dialog appears (\(chat.screen.kind))") }
}

/// What Claude got back for the last AskUserQuestion after `offset` bytes of the transcript.
func lastAnswer(_ url: URL?, after offset: Int) -> (answers: [String: String], notes: [String], declined: Bool)? {
    guard let url, let data = try? Data(contentsOf: url), data.count > offset else { return nil }
    let records = data.suffix(from: offset).split(separator: UInt8(ascii: "\n")).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    for r in records.reversed() {
        guard r["type"] as? String == "user", let content = (r["message"] as? [String: Any])?["content"] as? [[String: Any]],
              let tr = content.first(where: { $0["type"] as? String == "tool_result" }) else { continue }
        if let res = r["toolUseResult"] as? [String: Any], let a = res["answers"] as? [String: String] {
            let notes = (res["annotations"] as? [String: [String: Any]])?.values.compactMap { $0["notes"] as? String } ?? []
            return (a, notes, false)
        }
        if tr["is_error"] as? Bool == true { return ([:], [], true) }
    }
    return nil
}

func which(_ tool: String) -> String? {
    let out = run("/bin/zsh", ["-lc", "command -v \(tool)"]).trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? nil : out
}

@discardableResult func run(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

/// A TCP port nothing is listening on.
func freePort() -> Int? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 } }
    return bound ? Int(UInt16(bigEndian: addr.sin_port)) : nil
}
