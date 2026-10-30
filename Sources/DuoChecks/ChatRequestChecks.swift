import DuoControl
import DuoKit
import Foundation

// F-419: a question on screen before chat has read its request. On 2.1.284 the hooks arrive in time
// (PermissionRequest 13 ms after PreToolUse); what lost the request was Duo's feed not having read
// it: a feed behind its timer, a turn whose prompt fell out of the 256 KB window read at attach, a
// PermissionRequest line lost. F-420: the `/` menu's mirror garbled Claude's prompt when typed fast.

@MainActor func chatRequestChecks() throws {
    print("chat mode: a question's request, however late the feed reads it (F-419)")
    let q2 = spikeScreen("ask-2.1.284/q2-long-after-answer-60x53.txt")
    let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
    let question = "Should the importer read the whole export file into memory first (simpler, fine for small files) or stream it row by row (more code; safer for large exports from older accounts)?"
    let input = #"{"questions":[{"question":"\#(question)","header":"Importer","multiSelect":false,"options":[{"label":"Read it whole","description":"Simpler; fine below a few MB"},{"label":"Stream rows","description":"More code; handles any size"}]}]}"#

    // 2.1.284 at 60 columns: the question drawn with a bar, wrapped, its parentheses and semicolon.
    do {
        let s = ChatScreenReader.read(q2, cols: 60)
        check(s.kind == .question && s.question == question && ChatScreenReader.wellFormed(s), "2.1.284's long question at 60 columns reads whole (\(s.kind), \(s.question ?? "nil"))")
        let q1 = ChatScreenReader.read(spikeScreen("ask-2.1.284/q1-60x53.txt"), cols: 60)
        check(q1.kind == .question && q1.question == "Which database should we use?", "and its first, short question")
    }

    let cfg = FileManager.default.temporaryDirectory.appending(path: "duo-request-\(UUID().uuidString.prefix(8))")
    let cwdDir = cfg.appending(path: "work")
    try FileManager.default.createDirectory(at: cwdDir, withIntermediateDirectories: true)
    let was = getenv("CLAUDE_CONFIG_DIR").map { String(cString: $0) }
    setenv("CLAUDE_CONFIG_DIR", cfg.path, 1)
    defer {
        if let was { setenv("CLAUDE_CONFIG_DIR", was, 1) } else { unsetenv("CLAUDE_CONFIG_DIR") }
        try? FileManager.default.removeItem(at: cfg)
    }
    func event(_ name: String, _ extra: String = "", at: Double = Date().timeIntervalSince1970) -> String {
        #"{"at":\#(String(format: "%.3f", at)),"e":{"session_id":"s","hook_event_name":"\#(name)"\#(extra)}}"#
    }
    let ask = #","tool_name":"AskUserQuestion","tool_input":\#(input)"#
    func eventsFile(_ sid: String, _ lines: [String]) throws -> URL {
        let url = HookEvents.file(for: sid)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func append(_ url: URL, _ line: String) throws {
        let h = try FileHandle(forWritingTo: url); defer { try? h.close() }
        try h.seekToEnd(); h.write(Data((line + "\n").utf8))
    }

    // The feed hasn't read the PermissionRequest when the grace runs out (its timer behind a stall, or
    // off screen): chat reads the hooks then, and the card comes up instead of the terminal.
    do {
        let sid = "req-late-\(UUID().uuidString.prefix(8))"
        let url = try eventsFile(sid, [event("SessionStart"), event("UserPromptSubmit", #","prompt":"go""#)])
        let tui = FakeTUI(idleText)
        tui.cols = 60
        let c = ChatSession(key: sid, mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion("2.1.284")
        c.attach(tui)
        c.follow(sessionId: sid, cwd: cwdDir.path)
        spin(0.4)
        c.feedStop()   // a feed that won't tick again before the grace runs out
        try append(url, event("PreToolUse", ask + #","tool_use_id":"t2""#).replacingOccurrences(of: "PreToolUse", with: "Notification"))
        try append(url, event("PermissionRequest", ask))
        tui.show(q2)
        spin(ChatSession.requestGrace + 0.4)
        check(c.fallback == nil && c.cardUp && c.pendingRequest?.tool == "AskUserQuestion",
              "a request the feed hadn't read is read when the grace runs out: the card, no fallback (\(c.lastFallback?.rule ?? "none"))")
    }

    // Still no request after reading: the terminal, and the report says what the feed had read.
    do {
        let sid = "req-none-\(UUID().uuidString.prefix(8))"
        _ = try eventsFile(sid, [event("SessionStart"), event("UserPromptSubmit", #","prompt":"go""#)])
        let tui = FakeTUI(idleText)
        let c = ChatSession(key: sid, mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion("2.1.284")
        c.attach(tui)
        c.follow(sessionId: sid, cwd: cwdDir.path)
        spin(0.4)
        tui.show(q2)
        spin(ChatSession.requestGrace + 0.4)
        let r = c.debugReport()
        check(c.lastFallback?.rule == "dialog-request-mismatch" && r.contains("request pending: none") && r.contains("hooks: last event UserPromptSubmit"),
              "no request at all: the terminal, and the report names the last hook read")
        c.feedStop()
    }

    // A long turn: its prompt is out of the last 256 KB of events when chat opens, but the question
    // it's waiting on is in it.
    do {
        let sid = "req-window-\(UUID().uuidString.prefix(8))"
        let chunk = String(repeating: "streamed text ", count: 60)
        var lines = [event("SessionStart"), event("UserPromptSubmit", #","prompt":"go""#)]
        for i in 0..<400 { lines.append(event("MessageDisplay", #","message_id":"m\#(i)","delta":"\#(chunk)","final":false"#)) }
        lines.append(event("PreToolUse", ask + #","tool_use_id":"t1""#).replacingOccurrences(of: "PreToolUse", with: "Notification"))
        lines.append(event("PermissionRequest", ask))
        let url = try eventsFile(sid, lines)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let c = ChatSession(key: sid, mode: .chat)
        c.persistsFallbackLog = false
        c.follow(sessionId: sid, cwd: cwdDir.path)
        check(size > 256 * 1024 && c.pendingRequest?.tool == "AskUserQuestion" && c.askedQuestions.first?["question"] as? String == question,
              "a turn longer than the window read at attach: its question's request is still found (\(size / 1024) KB)")
        c.feedStop()
        // Answered before chat opened: no request is owed.
        let sid2 = "req-answered-\(UUID().uuidString.prefix(8))"
        _ = try eventsFile(sid2, Array(lines.dropFirst(2)) + [event("PostToolUse", #","tool_name":"AskUserQuestion""#)])
        let d = ChatSession(key: sid2, mode: .chat)
        d.follow(sessionId: sid2, cwd: cwdDir.path)
        check(d.pendingRequest == nil, "one answered before chat opened is not")
        d.feedStop()
    }

    // The PermissionRequest line lost (two hooks writing at once can merge lines, C-27): the question's
    // PreToolUse carries the same input.
    do {
        let c = ChatSession(key: "req-pre", mode: .chat)
        let e = try JSONSerialization.jsonObject(with: Data(#"{"hook_event_name":"PreToolUse","tool_use_id":"t9","tool_name":"AskUserQuestion","tool_input":\#(input)}"#.utf8)) as! ChatJSON
        ChatIngest.hook(e, at: Date().timeIntervalSince1970, into: c.log, chat: c)
        check(c.pendingRequest?.tool == "AskUserQuestion" && c.askedQuestions.count == 1, "a question's PreToolUse alone gives chat its request")
    }

    // The log's summary: how often each rule trips, most first.
    do {
        func rec(_ rule: String) -> ChatFallbackLog.Record {
            let line = #"{"at":"2026-10-29T10:00:00Z","rule":"\#(rule)","message":"m","kind":"question","sig":"q","evidence":[],"cliVersion":"2.1.284","trust":"newer","hooks":"last event Stop 0.2 s ago","duo":"dev","session":"s","rows":53,"cols":60,"footer":false,"dialog":true,"mods":[],"screenHash":"h","nearRows":[]}"#
            let url = cfg.appending(path: "rec-\(rule).jsonl")
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
            return ChatFallbackLog.read(from: url)[0]
        }
        let r = ChatFallbackLog.report([rec("unknown-screen"), rec("dialog-request-mismatch"), rec("unknown-screen")])
        check(r.contains("By rule: unknown-screen 2, dialog-request-mismatch 1") && r.contains("(request: none; last event Stop 0.2 s ago)"),
              "duo2 session chat why --log counts each rule and says what the feed had read")
        let old = #"{"at":"2026-10-28T10:00:00Z","rule":"unknown-screen","message":"m","kind":"unknown","sig":"unknown","evidence":[],"trust":"newer","duo":"0.2.21 (1117)","session":"s","rows":53,"cols":60,"footer":true,"dialog":false,"mods":[],"screenHash":"h","nearRows":[]}"#
        let url = cfg.appending(path: "old-log.jsonl")
        try (old + "\n").write(to: url, atomically: true, encoding: .utf8)
        check(ChatFallbackLog.read(from: url).count == 1, "a log line written by 0.2.21 still reads")
    }

    print("chat mode: Claude Code 2.1.284, the version work pins now (F-435)")
    do {
        // The dialog tour on the real 2.1.284 against the mock, in manual mode (Spikes/chat-mode/scenario-tour-2.1.284.json).
        let expect: [(String, ChatScreen.Kind)] = [("01-markdown", .idle), ("02-bash-permission", .permission), ("03-edit-permission", .permission),
            ("04-question", .question), ("05-multi", .question), ("06-review", .questionReview), ("07-agent", .idle), ("08-plan-mode", .idle),
            ("09-plan", .plan), ("10-streaming", .busy), ("11-interrupted", .idle), ("12-unknown-model-picker", .picker)]   // the retry screen wasn't reached
        let read = expect.map { ($0.0, $0.1, ChatScreenReader.read(spikeScreen("tour-2.1.284/\($0.0).txt"))) }
        let wrong = read.filter { $0.2.kind != $0.1 }.map { "\($0.0): \($0.2.kind)" }
        check(wrong.isEmpty, "each 2.1.284 screen reads as its kind (\(wrong))")
        let broken = read.filter { !ChatScreenReader.wellFormed($0.2) }.map(\.0)
        check(broken.isEmpty, "and every dialog reads whole, so chat answers it (\(broken))")
        check(ChatSignatures.trust(for: "2.1.284") == .verified && ChatSignatures.table(for: "2.1.284").verified, "2.1.284 is a verified version")
        check(read[1].2.options.count == 4 && read[1].2.options.last?.label == "No" && read[8].2.options.first?.label.hasPrefix("Yes, and use auto mode") == true
              && read[7].2.mode == .plan && read[0].2.mode == .manual, "2.1.284's own words: the Bash permission's four options, plan approval's auto mode, the modes")
    }

    print("chat mode: the `/` menu on 2.1.284, with skills of the work Mac's shape (F-420)")
    do {
        let dir = "slash-2.1.284/"
        let m = ChatScreenReader.read(spikeScreen(dir + "menu-ask-60x53.txt"), cols: 60)
        check(m.kind == .idle && m.input == "/ask" && m.commands.map(\.name) == ["/ask-data", "/ask-docs", "/ask-nodesc"],
              "2.1.284 at 60 columns: the menu above the box, descriptions wrapped (\(m.commands.map(\.name)))")
        check(m.commands.first?.description == "Answer questions about the", "a wrapped description keeps its first row")
        let w = ChatScreenReader.read(spikeScreen(dir + "menu-ask-100x40.txt"), cols: 100)
        check(w.commands.map(\.name) == ["/ask-data", "/ask-hint", "/ask-yaml", "/ask-docs", "/ask-empty"] && w.mode == .auto,
              "at 100: user and project skills, an argument hint, a folded description, an empty one (\(w.commands.map(\.name)))")
        let one = ChatScreenReader.read(spikeScreen(dir + "menu-ask-data-60x53.txt"), cols: 60)
        check(one.input == "/ask-data" && one.commands.map(\.name) == ["/ask-data"], "the whole name typed: its one row")
        let now = ChatScreenReader.read(spikeScreen(dir + "menu-ask-60x53-2.1.311.txt"), cols: 60)
        check(now.commands.map(\.name) == ["/ask-data", "/ask-docs", "/ask-nodesc"], "2.1.311 draws them indented further: the same rows (\(now.commands.map(\.name)))")
    }

    // Typed fast, the composer's field mirrors each keystroke, unawaited: the TUI's prompt must end up
    // holding the text, not each mirror's edit of a prompt it read before the last one landed.
    do {
        let tui = FakeTUI(spikeScreen("slash-2.1.284/menu-ask-60x53.txt").replacingOccurrences(of: "❯\u{a0}/ask", with: "❯\u{a0}"))   // 2.1.284 puts a no-break space after ❯
        var prompt = ""
        let base = tui.text
        tui.react = { k, t in
            if k == ChatKey.backspace.bytes { if !prompt.isEmpty { prompt.removeLast() } } else { prompt += k }
            // The TUI repaints a moment after each key, as the real one does.
            let p = prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { t.show(base.replacingOccurrences(of: "❯\u{a0}\n", with: "❯\u{a0}\(p)\n")) }
        }
        let c = ChatSession(key: "slash-fast", mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion("2.1.284")
        c.attach(tui)
        for n in 1...9 { let t = String("/ask-data".prefix(n)); Task { await c.mirrorSlash(t) }; spin(0.03) }
        spin(2.5)
        check(prompt == "/ask-data", "nine mirrors typed fast leave Claude's prompt holding /ask-data (\(prompt.debugDescription), keys \(tui.keys.map(\.debugDescription)))")
        for n in (4...8).reversed() { let t = String("/ask-data".prefix(n)); Task { await c.mirrorSlash(t) }; spin(0.03) }
        spin(2.5)
        check(prompt == "/ask", "and backspaced fast, /ask (\(prompt.debugDescription))")
    }

    print("chat mode: `/` while Claude works (Q-329)")
    do {
        let inline = ChatScreenReader.read(spikeScreen("slash-2.1.296-inline/menu-tri.txt"))
        // 2.1.284 drops "esc to interrupt" from its footer while the menu is up, though the menu is above the box.
        let busy284 = ChatScreenReader.read(spikeScreen("slash-2.1.284/busy-long-100x34.txt"))
        let menu284 = ChatScreenReader.read(spikeScreen("slash-2.1.284/menu-ask-busy-100x34.txt"))
        check(busy284.kind == .busy && menu284.kind == .idle && menu284.commands.first?.name == "/ask-data",
              "2.1.284 mid-turn: busy, then with `/ask` typed the busy row is gone (\(busy284.kind) → \(menu284.kind))")
        let k = ChatSession(key: "slash-busy-284", mode: .chat)
        k.apply(busy284)
        k.apply(menu284)
        check(k.screen.kind == .busy && k.screen.mode == .auto, "chat keeps the turn busy, and its mode, while the menu is up (\(k.screen.kind))")
        // A running turn, then 2.1.296's inline menu hides its busy row: still busy, nothing ends the reply.
        let busy = ChatScreenReader.read(spikeScreen("tour-2.1.284/10-streaming.txt"))
        let c = ChatSession(key: "slash-busy", mode: .chat)
        c.persistsFallbackLog = false
        c.apply(busy)
        c.apply(inline)
        check(busy.kind == .busy && c.screen.kind == .busy && !c.screen.commands.isEmpty, "a menu over the busy row keeps the turn busy (\(c.screen.kind))")
        c.apply(ChatScreenReader.read(spikeScreen("slash-2.1.296-inline/idle.txt")))
        check(c.screen.kind == .idle, "and the prompt back without it reads idle again")
        let idle = ChatSession(key: "slash-idle", mode: .chat)
        idle.apply(ChatScreenReader.read(spikeScreen("slash-2.1.296-inline/idle.txt")))
        idle.apply(inline)
        check(idle.screen.kind == .idle, "the same menu at an idle prompt stays idle")
        // Typed while busy: the TUI's prompt gets it, as in the terminal.
        let tui = FakeTUI(spikeScreen("tour-2.1.284/10-streaming.txt"))
        let m = ChatSession(key: "slash-busy-mirror", mode: .chat)
        m.persistsFallbackLog = false
        m.setVersion("2.1.284")
        m.attach(tui)
        Task { await m.mirrorSlash("/ask") }
        spin(1.3)
        check(m.screen.kind == .busy && tui.keys == ["/ask"], "`/ask` typed while Claude works goes to Claude's prompt (\(tui.keys))")
    }
}
