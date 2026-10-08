import DuoControl
import DuoKit
import Foundation

// Chat mode under the real CLI login (F-105's test, on Duo's code): the user's own `claude` and
// login (no API key, no ANTHROPIC_BASE_URL, the default config), Haiku, a throwaway folder in /tmp,
// hooks only through the per-session --settings file in a scratch support folder. A few turns of
// each kind, all through ChatSession. Spends a few Haiku turns.
//
//   DUO_SUPPORT_DIR=/tmp/duo-chat-realsup DUO_CHECKS=chat-real swift run DuoChecks
//
// The session's id goes to /tmp/duo-chat-real/session-ids.txt, to archive afterwards.

@MainActor func chatRealChecks() throws {
    guard let claude = which("claude") else { print("chat-real: no claude"); return }
    let version = run(claude, ["--version"]).split(separator: " ").first.map(String.init)
    print("chat mode, real login: Claude Code \(version ?? "?"), Haiku, /tmp/duo-chat-real (F-105)")
    let root = "/tmp/duo-chat-real"
    try? FileManager.default.removeItem(atPath: root + "/ws")
    try FileManager.default.createDirectory(atPath: root + "/ws", withIntermediateDirectories: true)
    try "# Notes\n\nFirst line.\n".write(toFile: root + "/ws/notes.md", atomically: true, encoding: .utf8)
    let ws = URL(fileURLWithPath: root + "/ws").resolvingSymlinksInPath().path
    let id = UUID().uuidString.lowercased()
    let ids = root + "/session-ids.txt"
    let prior = (try? String(contentsOfFile: ids, encoding: .utf8)) ?? ""
    try (prior + id + "\n").write(toFile: ids, atomically: true, encoding: .utf8)
    let settings = try HookEvents.settingsFile(for: id, chatEvents: true)
    let bin = repoRoot().appending(path: ".build/out/Products/Debug/duo2").path
    let composeDir = root + "/compose"
    // The user's environment, minus anything that would point claude at a key or another server.
    var env = ProcessInfo.processInfo.environment.filter { k, _ in !(k == "CLAUDECODE" || (k.hasPrefix("CLAUDE_") && k != "CLAUDE_CONFIG_DIR")) }
    for k in ["ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "DUO_SOCKET", "DUO_TOKEN"] { env.removeValue(forKey: k) }
    env["TERM"] = "xterm-256color"
    env["DUO_SESSION_ID"] = id
    env["EDITOR"] = ChatComposer.editorCommand(cli: bin)
    env["VISUAL"] = env["EDITOR"]
    env[ChatCompose.dirVariable] = composeDir
    env[ChatCompose.userEditor] = "/usr/bin/true"
    let tui = HeadlessTUI(cols: 100, rows: 34)
    tui.process.startProcess(executable: claude, args: ["--session-id", id, "--settings", settings.path, "--model", TestModel.model(environment: ProcessInfo.processInfo.environment, isolated: true, bundleID: nil)!],
                             environment: env.map { "\($0.key)=\($0.value)" }, execName: nil, currentDirectory: ws)
    defer { tui.process.terminate() }
    let chat = ChatSession(key: id, mode: .chat)
    chat.setVersion(version)
    chat.attach(tui)
    chat.composeDir = URL(fileURLWithPath: composeDir)
    chat.follow(sessionId: id, cwd: ws)
    func until(_ s: TimeInterval, _ f: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(s)
        while Date() < end { if f() { return true }; spin(0.2) }
        return f()
    }
    func await_<T>(_ f: @escaping () async -> T) -> T? {
        var r: T?
        Task { r = await f() }
        _ = until(60) { r != nil }
        return r
    }
    let idle = { until(120) { chat.reread().kind == .idle } }
    func dump(_ name: String) { try? tui.screenLines().joined(separator: "\n").write(toFile: "\(root)/screen-\(name).txt", atomically: true, encoding: .utf8) }
    func say(_ text: String) -> Bool {
        _ = idle()
        let r = await_ { await chat.send(text) }
        if r?.ok != true { print("    (send refused: \(r?.why ?? "no reply"))"); chat.fallback = nil }
        return r?.ok == true
    }

    // 1. The trust prompt: a screen chat mode can't show. It falls back, the user answers it in the
    //    terminal, and chat comes back by itself.
    _ = until(30) { chat.reread().kind != .starting }
    spin(1.5)
    if chat.reread().kind == .unknown {
        check(chat.fallback == .unknownScreen, "the trust prompt reads as unknown and shows the terminal")
        dump("trust")
        tui.sendKeys("\r")
        _ = until(30) { chat.reread().kind == .idle }
        spin(0.6)
        check(chat.showsChat && chat.fallback == nil, "answered in the terminal, chat comes back by itself")
    } else {
        print("    (no trust prompt: \(chat.screen.kind))")
    }
    check(idle(), "the prompt is up (\(chat.screen.kind))")

    // DUO_CHAT_REAL_ONLY=interrupt: just the last step.
    let onlyInterrupt = ProcessInfo.processInfo.environment["DUO_CHAT_REAL_ONLY"] == "interrupt"
    if !onlyInterrupt {
    // 2. Markdown, sent from the composer, streamed.
    check(say("Reply in Markdown only: a level-2 heading 'Plan', then a two-column table with two rows, then a three-item bullet list. Keep it short."),
          "a message sent from the composer through Ctrl+G")
    _ = idle(); spin(3)
    let texts = chat.log.items.compactMap { i -> ChatTurn? in if case .claude(let t) = i { return t } else { return nil } }.last?.segments.compactMap { s -> String? in
        if case .text(let x) = s { return x.markdown } else { return nil } } ?? []
    check(chat.log.streams && texts.count == 1 && texts[0].contains("|") && texts[0].contains("#"),
          "the reply streamed through MessageDisplay and shows once, as Markdown (\(texts.count) block, streamed \(chat.log.streams))")
    dump("markdown")

    // 3. A Bash permission, answered Yes from its card.
    _ = say("Use the Bash tool to run exactly this command: echo chat-mode-ok > ok.txt")
    if until(90, { chat.reread().kind == .permission && chat.cardUp }) {
        dump("bash")
        let s = chat.screen
        check(s.options.first?.label == "Yes" && chat.pendingRequest?.tool == "Bash", "the Bash card: Claude Code's own labels (\(s.options.map(\.label)))")
        let r = await_ { await chat.answerOption(1, label: "Yes", sig: s.sig) }
        _ = idle(); spin(1)
        check(r?.ok == true && FileManager.default.fileExists(atPath: ws + "/ok.txt"), "Yes from the card: the command ran")
    } else { check(false, "a Bash permission appeared (\(chat.screen.kind), \(chat.pendingRequest?.tool ?? "no request"))"); dump("bash-missing") }

    // 4. An edit permission, answered Yes.
    _ = say("Use the Edit tool to change the text 'First line.' to 'First line, edited.' in notes.md. Do nothing else.")
    if until(90, { chat.reread().kind == .permission && chat.cardUp && chat.pendingRequest?.tool == "Edit" }) {
        dump("edit")
        let s = chat.screen
        let r = await_ { await chat.answerOption(1, label: s.options.first?.label ?? "Yes", sig: s.sig) }
        _ = idle(); spin(1)
        let text = (try? String(contentsOfFile: ws + "/notes.md", encoding: .utf8)) ?? ""
        check(r?.ok == true && text.contains("First line, edited."), "an edit, Yes from its card: the file changed")
        check(chat.log.steps.last { $0.name == "Edit" }?.diff?.isEmpty == false, "the edit's step has its diff")
    } else { check(false, "an edit permission appeared (\(chat.screen.kind))"); dump("edit-missing") }

    // 5. AskUserQuestion: a multi-select, then a single-select answered with Other; the review page.
    _ = say("Use the AskUserQuestion tool to ask me exactly two questions in one call. First: header 'Platforms', question 'Which platforms should ship first?', multiSelect true, options 'macOS', 'iOS', 'Web'. Second: header 'Timing', question 'When should it ship?', multiSelect false, options 'This week', 'Next month'. Then tell me my answers in one line.")
    if until(120, { chat.reread().kind == .question && chat.cardUp }) {
        dump("ask")
        var steps: [ChatAskIntent] = [.toggle("macOS"), .toggle("Web"), .next, .other("After the beta")]
        var ok = true
        for st in steps {
            let r = await_ { await chat.ask(st, sig: chat.reread().sig) }
            if r?.ok != true { ok = false; print("    (ask \(st) refused: \(r?.why ?? "-"))"); dump("ask-refused"); break }
            spin(0.5)
        }
        if ok, until(10, { chat.reread().kind == .questionReview }) {
            dump("ask-review")
            ok = await_ { await chat.ask(.submit, sig: chat.reread().sig) }?.ok == true
        }
        steps = []
        _ = idle(); spin(2)
        let answers = lastAnswer(ClaudeStorage.transcript(sessionId: id, cwd: ws), after: 0)?.answers ?? [:]
        check(ok && answers["Which platforms should ship first?"] == "macOS, Web" && answers["When should it ship?"] == "After the beta",
              "AskUserQuestion answered from the card: Claude received exactly what was clicked (\(answers))")
    } else { check(false, "a question appeared (\(chat.screen.kind))"); dump("ask-missing") }

    // 6. Plan mode: feedback with option 3, then Cancel.
    _ = idle()
    for _ in 0..<4 where chat.reread().mode != .plan { _ = await_ { await chat.cycleMode() }; spin(0.4) }
    check(chat.screen.mode == .plan, "plan mode from the mode chip")
    _ = say("Plan how to add a third line, 'Third line.', to notes.md. Keep the plan to three steps.")
    if until(150, { chat.reread().kind == .plan && chat.cardUp }) {
        dump("plan")
        check((chat.planText ?? "").count > 20, "the plan card has the whole plan from the request")
        let r = await_ { await chat.planFeedback("Also add a fourth line, 'Fourth line.'", sig: chat.screen.sig) }
        check(r?.ok == true, "plan feedback sent from option 3's field")
        if until(150, { chat.reread().kind == .plan && chat.cardUp && (chat.planText ?? "").lowercased().contains("fourth") }) {
            check(true, "Claude revised the plan with the feedback")
            dump("plan-revised")
            _ = await_ { await chat.cancelDialog(sig: chat.screen.sig) }
        } else { check(false, "a revised plan (\(chat.screen.kind))"); tui.sendKeys("\u{1b}") }
    } else { check(false, "a plan dialog appeared (\(chat.screen.kind))"); dump("plan-missing") }
    _ = idle()
    for _ in 0..<4 where chat.reread().mode != .manual { _ = await_ { await chat.cycleMode() }; spin(0.4) }

    }

    // 7. An interrupt while Claude writes.
    _ = say("Count from 1 to 300 in words (one, two, three …), one number per line. Write all of them now, with no other text.")
    if until(90, { chat.log.writing || chat.screen.kind == .busy && chat.log.streams }) {
        spin(1.5)
        _ = await_ { await chat.interrupt() }
        _ = until(15) { chat.reread().kind == .idle }
        spin(0.6)
        dump("interrupted")
        let interrupted: Bool = { if case .interrupted? = chat.log.items.last { return true }; return false }()
        _ = until(10) { if case .interrupted? = chat.log.items.last { return true }; return false }
        let ended: Bool = { if case .interrupted? = chat.log.items.last { return true }; return false }()
        check((interrupted || ended) && !chat.log.writing && chat.reread().kind == .idle,
              "Stop: Claude Code stopped, and the chat ends the reply with Interrupted (screen said interrupted: \(chat.screen.interrupted))")
    } else { check(false, "the long reply started streaming") }
    check(chat.fallback == nil && chat.showsChat, "chat is still showing at the end")
    print("  session \(id) (archive with: duo2 session archive \(id))")
}
