import DuoControl
import DuoKit
import Foundation

// Chat mode's checks (DL-118 to DL-120): the screen reader against the spike's real TUI screens,
// the AskUserQuestion driver against a scripted TUI, and the log built from recorded hooks and
// transcripts. `DUO_CHECKS=chat swift run DuoChecks` runs these alone.

/// A captured TUI screen from the spike (Claude Code 2.1.291).
func spikeScreen(_ name: String) -> String {
    (try? String(contentsOf: repoRoot().appending(path: "Spikes/chat-mode/screens/\(name)"), encoding: .utf8)) ?? ""
}

/// A scripted TUI: shows whatever screen it's given and logs the keys it receives.
@MainActor final class FakeTUI: ChatTerminal {
    var text: String
    var keys: [String] = []
    var cols = 100
    var output: (@MainActor () -> Void)?
    /// What a key does to the screen, for the answering checks.
    var react: ((String, FakeTUI) -> Void)?
    init(_ text: String) { self.text = text }
    func screenLines() -> [String] { text.components(separatedBy: "\n") }
    var columns: Int { cols }
    func sendKeys(_ k: String) { keys.append(k); react?(k, self) }
    func onOutput(_ f: @escaping @MainActor () -> Void) { output = f }
    func show(_ t: String) { text = t; output?() }
}

@MainActor func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func chatChecks() throws {
    print("chat mode: reading the TUI screen (2.1.291, F-104, F-105, F-106)")
    do {
        let idle = ChatScreenReader.read(spikeScreen("tour-2.1.291/01-markdown.txt"))
        check(idle.kind == .idle && idle.input == "" && idle.mode == .manual, "idle input box, empty, manual mode (\(idle.kind) \(idle.input.debugDescription))")
        let bash = ChatScreenReader.read(spikeScreen("10-bash-perm.txt"), cols: 100)
        check(bash.kind == .permission && bash.kindLabel == "Bash command" && bash.title == "Do you want to proceed?", "a Bash permission, titled from the screen")
        check(bash.options.map(\.n) == [1, 2, 3] && bash.options[0].label == "Yes" && bash.options[2].label == "No", "its options, numbered, verbatim")
        check(bash.options[1].label.hasPrefix("Yes, and always allow access to /private/tmp/") && bash.options[1].label.hasSuffix("from this project"),
              "a wrapped label is joined whole (\(bash.options.dropFirst().first?.label ?? "-"))")
        check(bash.amend && bash.options[0].cursor && !bash.options[1].cursor, "Tab to amend seen; the cursor row read")
        let edit = ChatScreenReader.read(spikeScreen("tour-2.1.291/03-edit-permission.txt"))
        check(edit.kind == .permission && edit.options.count == 3 && edit.options[1].label.contains("accept edits"), "an edit permission's own wording (\(edit.options.dropFirst().first?.label ?? "-"))")
        let plan = ChatScreenReader.read(spikeScreen("tour-2.1.291/09-plan.txt"))
        check(plan.kind == .plan && plan.options.map(\.label) == ["Yes, auto-accept edits", "Yes, manually approve edits", "Tell Claude what to change"],
              "plan approval's three options (\(plan.options.map(\.label)))")
        let multi = ChatScreenReader.read(spikeScreen("tour-2.1.291/05-multi.txt"))
        check(multi.kind == .question && multi.multi && multi.question == "Which platforms should we ship?", "a multi-select question")
        check(multi.tabs.map(\.label) == ["Platforms", "Timing", "Submit"] && multi.options.map(\.label) == ["macOS", "iOS", "Web"],
              "its tabs and options (\(multi.tabs.map(\.label)) \(multi.options.map(\.label)))")
        check(multi.other?.value == "" && multi.rows.contains { $0.kind == .next } && multi.rows.last?.kind == .chat, "Type something (empty), Next, Chat about this")
        check(multi.options.first?.note == "Native", "descriptions kept as notes")
        let review = ChatScreenReader.read(spikeScreen("tour-2.1.291/06-review.txt"))
        check(review.kind == .questionReview && review.options.map(\.label) == ["Submit answers", "Cancel"], "the review page")
        check(ChatScreenReader.read(spikeScreen("tour-2.1.291/12-unknown-model-picker.txt")).kind == .unknown, "/model reads as unknown: the terminal")
        check(ChatScreenReader.read(spikeScreen("real-cli-login-2.1.291/01-trust-folder-unknown.txt")).kind == .unknown, "the trust prompt reads as unknown")
        check(ChatScreenReader.read(spikeScreen("unknown-api-key-prompt.txt")).kind == .unknown, "the API-key prompt reads as unknown")
        let named = ChatScreenReader.read(spikeScreen("real-cli-login-2.1.291/08-named-rule-was-unknown.txt"))
        check(named.kind == .busy, "a named session's rule still reads (busy) (\(named.kind))")
        let retry = ChatScreenReader.read(spikeScreen("tour-2.1.291/13-retrying.txt"))
        check(retry.kind == .busy && retry.status?.contains("Retrying in 4s · attempt 4/10") == true, "the retry status line (\(retry.status ?? "-"))")
        let interrupted = ChatScreenReader.read(spikeScreen("tour-2.1.291/11-interrupted.txt"))
        check(interrupted.kind == .idle && interrupted.interrupted, "Interrupted · What should Claude do instead?")
        let mode = ChatScreenReader.read(spikeScreen("tour-2.1.291/08-plan-mode.txt"))
        check(mode.mode == .plan, "plan mode from the footer (\(mode.mode.map(\.rawValue) ?? "-"))")
        let typed = ChatScreenReader.read(spikeScreen("ask-2.1.291/single-other-typed.txt"))
        check(typed.kind == .question && typed.other?.value?.isEmpty == false, "text typed into Type something (\(typed.other?.value ?? "-"))")
        let prev = ChatScreenReader.read(spikeScreen("ask-2.1.291/preview.txt"))
        check(prev.kind == .question && prev.preview && prev.other == nil, "the preview layout: no free-text row")
        let long = ChatScreenReader.read(spikeScreen("ask-2.1.291/long-wrapped.txt"))
        check(long.kind == .question && (long.question?.count ?? 0) > 60, "a long wrapped question is read whole (\(long.question ?? "-"))")
        let placeholder = ChatScreenReader.read(spikeScreen("tour-2.1.291/01-markdown.txt").replacingOccurrences(of: "❯  \n", with: "❯ Try \"fix lint errors\"\n"))
        check(placeholder.input == "", "the input's placeholder is not typed text (F-108)")
        check(ChatSignatures.table(for: "2.1.291").verified && !ChatSignatures.table(for: "2.1.219").verified && !ChatSignatures.table(for: "2.1.300").verified,
              "only the verified version answers dialogs; 2.1.219 and newer CLIs render only")
    }

    print("chat mode: falling back to the terminal (spike's fallback rules, DL-118 §3)")
    do {
        let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
        let tui = FakeTUI(idleText)
        let c = ChatSession(key: "s1", mode: .chat)
        c.attach(tui)
        check(c.showsChat && c.screen.kind == .idle, "chat shows at the prompt")
        tui.show(spikeScreen("tour-2.1.291/12-unknown-model-picker.txt")); spin(0.15)
        check(c.showsChat, "an unknown screen waits out the grace period (a blank flash isn't a reason)")
        spin(0.6)
        check(!c.showsChat && c.fallback == .unknownScreen, "unknown for 500 ms: the terminal, with why")
        tui.show(idleText); spin(0.15)
        check(c.showsChat && c.fallback == nil, "back at the prompt: chat returns by itself")
        tui.show(spikeScreen("tour-2.1.291/12-unknown-model-picker.txt")); spin(0.1)
        tui.show(idleText); spin(0.6)
        check(c.showsChat, "a brief unknown never falls back")
        c.mode = .terminal
        tui.show(idleText); spin(0.15)
        check(!c.showsChat && c.fallback == nil, "chosen terminal stays the terminal")
        let old = ChatSession(key: "s2", mode: .chat)
        old.setVersion("2.1.219")
        old.attach(FakeTUI(spikeScreen("10-bash-perm.txt")))
        check(!old.showsChat && old.fallback?.message.contains("2.1.219") == true, "a dialog on an unverified CLI (2.1.219) goes to the terminal")
        let hand = ChatSession(key: "s3", mode: .chat)
        let t3 = FakeTUI(spikeScreen("10-bash-perm.txt")); hand.attach(t3)
        hand.fallBack(.handedOver("Amend Claude’s request here, then press Return. Chat comes back after."))
        check(!hand.showsChat, "Amend in Terminal hands over")
        t3.show(idleText); spin(0.15)
        check(hand.showsChat, "and chat comes back after")
        check(tui.keys.isEmpty && t3.keys.isEmpty, "switching and falling back sent nothing to the session")
        var p = ChatPrefs()
        check(p.mode(for: "new") == .terminal, "a new session opens in the terminal until chat is used (DL-120)")
        p.set(.chat, for: "a")
        check(p.mode(for: "new") == .chat && p.mode(for: "a") == .chat, "then in the mode used last (DL-119 §5)")
        p.set(.terminal, for: "b")
        check(p.mode(for: "a") == .chat && p.mode(for: "new") == .terminal, "each session keeps its own")
    }

    print("chat mode: Markdown (handoff `text`)")
    do {
        let md = "## Refund flows\n\nBoth flows are in `docs/flows.md:42`.\nA second line.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n1. One\n2. Two\n   - nested\n\n```swift\nlet x = 1\n```\n\n> quoted\n\n---\n- **P2**, ops lead"
        let b = ChatMarkdown.parse(md)
        check(b.first == .heading(level: 2, text: "Refund flows"), "a heading")
        check(b.dropFirst().first == .paragraph("Both flows are in `docs/flows.md:42`.\nA second line."), "soft breaks stay breaks, as the TUI shows them")
        check(b.contains(.table(header: ["A", "B"], rows: [["1", "2"]])), "a table")
        if case .list(true, 1, let items)? = b.first(where: { if case .list(true, _, _) = $0 { return true }; return false }) {
            check(items.count == 2 && items[1].contains { if case .list(false, _, _) = $0 { return true }; return false }, "a numbered list with a nested bullet list")
        } else { check(false, "a numbered list") }
        check(b.contains(.code(language: "swift", text: "let x = 1")) && b.contains(.quote([.paragraph("quoted")])) && b.contains(.rule), "code, quote, rule")
        check(b.last == .list(ordered: false, start: 1, items: [[.paragraph("**P2**, ops lead")]]), "bullets stay bullets")
        let a = ChatMarkdown.inline("See `docs/refunds/flows.md:42`, notes.md and https://stripe.com/docs/refunds.")
        let links = a.runs.compactMap(\.link)
        check(links.contains { $0.scheme == "duo-file" && $0.path == "docs/refunds/flows.md" && $0.query == "line=42" }, "a path with :line is a link that opens at the line")
        check(links.contains { $0.scheme == "duo-file" && $0.path == "notes.md" }, "a bare file name with a known extension is a link")
        check(links.contains { $0.absoluteString == "https://stripe.com/docs/refunds" }, "a bare URL is a link, without its full stop")
        check(ChatMarkdown.inline("Version 2.1.291 is e.g. fine").runs.compactMap(\.link).isEmpty, "version numbers and e.g. aren't files")
    }

    print("chat mode: the log from hooks and the transcript (F-103, F-105)")
    do {
        let log = ChatLog()
        log.cwd = "/w"
        ChatIngest.hook(["hook_event_name": "UserPromptSubmit", "prompt": "Fix it", "source": "user"], at: 1, into: log)
        ChatIngest.record(["type": "user", "message": ["content": "Fix it"], "origin": ["kind": "human"]], into: log)
        check(log.items.count == 1, "a prompt seen by the hook and the transcript shows once")
        for (i, l) in ["# Done\n", "\n", "All **fixed**.\n"].enumerated() {
            ChatIngest.hook(["hook_event_name": "MessageDisplay", "message_id": "m1", "index": i, "final": i == 2, "delta": l], at: 2, into: log)
        }
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "text", "text": "# Done\n\nAll **fixed**."]]]], into: log)
        if case .claude(let t)? = log.items.last {
            check(t.segments.count == 1, "streamed text and its transcript block show once (\(t.segments.count))")
        } else { check(false, "a Claude card") }
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "t1", "name": "Edit", "input": ["file_path": "/w/a.md", "old_string": "x", "new_string": "y\nz"]]]]], into: log)
        ChatIngest.hook(["hook_event_name": "PreToolUse", "tool_use_id": "t1", "tool_name": "Edit", "tool_input": ["file_path": "/w/a.md", "old_string": "x", "new_string": "y\nz"]], at: 3, into: log)
        check(log.steps.count == 1 && log.steps[0].object == "a.md" && log.steps[0].adds == 2 && log.steps[0].dels == 1, "a tool call shows once, its path relative, +2 −1")
        let chat = ChatSession(key: "k", mode: .chat)
        ChatIngest.hook(["hook_event_name": "PermissionRequest", "tool_name": "Edit", "tool_input": ["file_path": "/w/a.md", "old_string": "x", "new_string": "y\nz"]], at: 4, into: log, chat: chat)
        check(log.steps[0].status == .needsYou && chat.pendingRequest?.tool == "Edit", "a permission request marks its step (matched by input: it has no tool_use_id)")
        ChatIngest.hook(["hook_event_name": "PostToolUse", "tool_use_id": "t1", "tool_name": "Edit", "tool_input": [:], "tool_response": ["structuredPatch": [["oldStart": 7, "newStart": 7, "lines": [" a", "-x", "+y", "+z"]]]]], at: 5, into: log)
        check(log.steps[0].status == .done && log.steps[0].diff?.map(\.number) == [7, 8, 8, 9], "the patch gives the diff its line numbers")
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "t2", "name": "Bash", "input": ["command": "rg x old/"]]]]], into: log)
        ChatIngest.record(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "t2", "is_error": true, "content": "Exit code 2\nrg: old/: No such file"]]]], into: log)
        check(log.step("t2")?.status == .failed(exit: 2) && log.step("t2")?.error == "rg: old/: No such file", "a failed command: its exit code and error")
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "t3", "name": "AskUserQuestion", "input": [:]]]]], into: log)
        ChatIngest.record(["type": "user", "toolDenialKind": "user-rejected", "message": ["content": [["type": "tool_result", "tool_use_id": "t3", "is_error": true, "content": "declined"]]]], into: log)
        if case .answer(let n)? = log.items.last { check(n.text == "You declined Claude’s questions", "a declined question, which fires no hook, comes from the transcript (F-106)") }
        else { check(false, "a declined question is shown") }
        ChatIngest.hook(["hook_event_name": "UserPromptSubmit", "prompt": "<task-notification>done</task-notification>", "source": "system"], at: 6, into: log)
        if case .note(let n)? = log.items.last { check(n.text == "Background task reported back", "an injected prompt is a quiet line, not your bubble") } else { check(false, "injected prompt") }
        ChatIngest.hook(["hook_event_name": "UserPromptSubmit", "prompt": "Write more", "source": "user"], at: 7, into: log)
        ChatIngest.hook(["hook_event_name": "MessageDisplay", "message_id": "m2", "index": 0, "final": false, "delta": "Line one\n"], at: 8, into: log)
        check(log.writing, "a reply streaming is being written")
        log.endStreaming(interrupted: true)
        if case .interrupted? = log.items.last, !log.writing { check(true, "an interrupt (no hook) ends the reply, from the screen (F-105)") } else { check(false, "interrupt") }
        ChatIngest.record(["type": "user", "message": ["content": [["type": "text", "text": "[Request interrupted by user]"]]]], into: log)
        check(!log.items.contains { if case .you(let y) = $0 { return y.text.hasPrefix("[Request interrupted") } else { return false } },
              "the transcript's interrupt record is not your message")
        ChatIngest.record(["type": "system", "subtype": "compact_boundary"], into: log)
        if case .divider? = log.items.last { check(true, "compaction is a divider") } else { check(false, "compaction") }
        let q = ChatLog()
        q.sent("Also check Android", time: nil, queued: true)
        if case .you(let y)? = q.items.last { check(y.queued, "a message sent while Claude works shows as Queued") } else { check(false, "queued bubble") }
        ChatIngest.hook(["hook_event_name": "UserPromptSubmit", "prompt": "Also check Android", "source": "user"], at: 1, into: q)
        if case .you(let y)? = q.items.last, q.items.count == 1 { check(!y.queued, "until Claude Code takes it (its prompt hook): then it's yours, once") } else { check(false, "queued taken") }
        let o = ChatLog()
        ChatIngest.hook(["hook_event_name": "UserPromptSubmit", "prompt": "Run it", "source": "user"], at: 1, into: o)
        ChatIngest.hook(["hook_event_name": "PreToolUse", "tool_use_id": "b1", "tool_name": "Bash", "tool_input": ["command": "echo hi"]], at: 2, into: o)
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "text", "text": "Running a command."]]]], into: o)
        ChatIngest.record(["type": "assistant", "message": ["content": [["type": "tool_use", "id": "b1", "name": "Bash", "input": ["command": "echo hi"]]]]], into: o)
        if case .claude(let t)? = o.items.last, case .text? = t.segments.first, t.segments.count == 2 { check(true, "text Claude wrote before a tool shows before it, though the tool's hook came first") }
        else { check(false, "text before tool order") }
        check(ChatIngest.lines(Data("{\"a\":1}\n{\"b\":2}{\"c\":\n{\"d\":4}\n".utf8)).count == 2, "merged hook lines are skipped, the rest read")
        var recs: [ChatJSON] = []
        for i in 0..<120 { recs.append(["type": "user", "message": ["content": "p\(i)"]]); recs.append(["type": "assistant", "message": ["content": [["type": "text", "text": "r\(i)"]]]]) }
        check(ChatFeedProbe.start(recs, turns: 50) == 140, "a long history opens on its last 50 turns (Q-56c)")
    }

    print("chat mode: hook events (DL-118)")
    do {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-chat-hooks-\(UUID().uuidString)")
        let plain = try HookEvents.settingsFile(for: "a", in: dir, cli: "/x/duo2")
        let chat = try HookEvents.settingsFile(for: "b", in: dir, cli: "/x/duo2", chatEvents: true)
        let h0 = (try JSONSerialization.jsonObject(with: Data(contentsOf: plain)) as? [String: Any])?["hooks"] as? [String: Any] ?? [:]
        let h1 = (try JSONSerialization.jsonObject(with: Data(contentsOf: chat)) as? [String: Any])?["hooks"] as? [String: Any] ?? [:]
        check(h0["MessageDisplay"] == nil && h1["MessageDisplay"] != nil && h1["PostToolUseFailure"] != nil && h1["SubagentStart"] != nil,
              "chat mode's events only for a CLI that has them")
        let pre = h1["PreToolUse"] as? [[String: Any]] ?? []
        check(pre.count == 2 && pre.contains { $0["matcher"] == nil } && pre.contains { $0["matcher"] as? String == "Edit|MultiEdit|Write" },
              "PreToolUse logs every tool beside the pre-edit hook, never instead of it")
        let ctx = ((h1["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        check(ctx.contains { $0.hasSuffix("hook context") }, "SessionStart keeps duo2 hook context")
        let cmd = (((h1["MessageDisplay"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) ?? ""
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", cmd]
        let inPipe = Pipe(), outPipe = Pipe(); p.standardInput = inPipe; p.standardOutput = outPipe
        try p.run(); inPipe.fileHandleForWriting.write(Data(#"{"session_id":"b","hook_event_name":"MessageDisplay","delta":"x"}"#.utf8)); try inPipe.fileHandleForWriting.close(); p.waitUntilExit()
        check(outPipe.fileHandleForReading.readDataToEndOfFile().isEmpty, "the MessageDisplay hook prints nothing (it would change what the TUI shows)")
        let line = (try? String(contentsOf: dir.appending(path: "b.jsonl"), encoding: .utf8)) ?? ""
        let obj = ChatIngest.lines(Data(line.utf8)).first
        check(obj?["at"] is NSNumber && (obj?["e"] as? ChatJSON)?["delta"] as? String == "x", "and writes one whole line with a fractional time (\(line.prefix(30)))")
        try? FileManager.default.removeItem(at: dir)
    }

    print("chat mode: the composer's hand-over, duo2 compose (F-104, F-112)")
    do {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-compose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prompt = dir.appending(path: "claude-prompt-abc.md")
        try "".write(to: prompt, atomically: true, encoding: .utf8)
        try ChatCompose.leave(.init(text: "Hello\nthere", basis: ""), in: dir, session: "s")
        check(ChatCompose.take(file: prompt, dir: dir, session: "s") == .handedOver && (try? String(contentsOf: prompt, encoding: .utf8)) == "Hello\nthere",
              "Claude's prompt file takes the composer's text, multi-line, exactly")
        check(!FileManager.default.fileExists(atPath: ChatCompose.handoverFile(dir, "s").path), "a hand-over is used once")
        check(ChatCompose.take(file: prompt, dir: dir, session: "s") == .notOurs, "with nothing handed over, Ctrl+G in the terminal opens the user's own editor")
        try "typed in the terminal".write(to: prompt, atomically: true, encoding: .utf8)
        try ChatCompose.leave(.init(text: "mine", basis: ""), in: dir, session: "s")
        check(ChatCompose.take(file: prompt, dir: dir, session: "s") == .refused && (try? String(contentsOf: prompt, encoding: .utf8)) == "typed in the terminal",
              "a prompt that changed in the terminal is left alone (nothing lost)")
        try ChatCompose.leave(.init(text: "x", basis: ""), in: dir, session: "s")
        check(ChatCompose.take(file: dir.appending(path: "COMMIT_EDITMSG"), dir: dir, session: "s") == .notOurs,
              "anything but Claude's prompt (git commit from Claude's Bash) goes to the user's editor")
        check(ChatCompose.userEditorCommand(["DUO_USER_VISUAL": "code -w", "DUO_USER_EDITOR": "vim"]) == "code -w" && ChatCompose.userEditorCommand([:]) == "vi",
              "the user's VISUAL, then EDITOR, as they were")
        check(ChatComposer.editorCommand(cli: "/Applications/Duo.app/Contents/Helpers/duo2") == "/Applications/Duo.app/Contents/Helpers/duo2 compose"
              && ChatComposer.editorCommand(cli: "/Users/x/Duo copy.app/duo2") == nil, "EDITOR unquoted (Claude splits it without a shell); a path with a space pastes instead")
        try? FileManager.default.removeItem(at: dir)
    }

    print("chat mode: EDITOR in Duo's sessions, for everything that isn't the composer (F-112)")
    do {
        let bin = repoRoot().appending(path: ".build/out/Products/Debug/duo2").path
        let tmp = URL(fileURLWithPath: "/tmp/duo-edcheck-\(UUID().uuidString.prefix(8))")
        let spaced = tmp.appending(path: "My Editors")
        try FileManager.default.createDirectory(at: spaced, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // A stand-in editor that records its arguments.
        func standIn(_ dir: URL, _ name: String) throws -> String {
            let f = dir.appending(path: name)
            try "#!/bin/sh\necho \"$@\" > '\(tmp.path)/ran-\(name).txt'\n".write(to: f, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path)
            return f.path
        }
        func helper(_ env: [String: String], _ file: String) -> Int32 {
            let p = Process(); p.executableURL = URL(fileURLWithPath: bin); p.arguments = ["compose", file]
            p.environment = env; p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return -1 }
            p.waitUntilExit(); return p.terminationStatus
        }
        let base = ["PATH": tmp.path + ":/usr/bin:/bin", "DUO_SESSION_ID": "s", ChatCompose.dirVariable: tmp.appending(path: "compose").path]
        _ = try standIn(tmp, "vi")
        let msg = tmp.appending(path: "COMMIT_EDITMSG").path
        _ = helper(base, msg)
        check((try? String(contentsOf: tmp.appending(path: "ran-vi.txt"), encoding: .utf8))?.contains("COMMIT_EDITMSG") == true,
              "(a) no EDITOR or VISUAL of the user's: the helper opens vi, as git would have")
        let subl = try standIn(spaced, "subl")
        _ = helper(base.merging([ChatCompose.userEditor: "'\(subl)' -w"]) { $1 }, msg)
        check((try? String(contentsOf: tmp.appending(path: "ran-subl.txt"), encoding: .utf8))?.hasPrefix("-w ") == true,
              "(b) the user's EDITOR with arguments and a space in its path (quoted, as git needs it) still runs, with its arguments")
        _ = try standIn(tmp, "code")
        _ = helper(base.merging([ChatCompose.userEditor: "vim", ChatCompose.userVisual: "code --wait"]) { $1 }, msg)
        check((try? String(contentsOf: tmp.appending(path: "ran-code.txt"), encoding: .utf8))?.hasPrefix("--wait ") == true, "(b) VISUAL wins over EDITOR, as for git")
        let saved = ChildEnvironment.cliDirectory
        ChildEnvironment.cliDirectory = "/Applications/Duo.app/Contents/Helpers"
        let shell = ChildEnvironment.make(sessionID: nil), claude = ChildEnvironment.make(sessionID: "abc")
        ChildEnvironment.cliDirectory = saved
        let userEditor = ProcessInfo.processInfo.environment["EDITOR"]
        check(shell.first { $0.hasPrefix("EDITOR=") }.map { String($0.dropFirst(7)) } == userEditor && !shell.contains { $0.hasPrefix(ChatCompose.dirVariable) },
              "(c) a plain shell tab keeps the user's EDITOR; only Claude sessions get the helper")
        check(claude.contains("EDITOR=/Applications/Duo.app/Contents/Helpers/duo2 compose") && claude.contains("VISUAL=/Applications/Duo.app/Contents/Helpers/duo2 compose"),
              "(c) Claude sessions do")
        // (d) git commit from Claude's Bash: no terminal, no hand-over, the real vi.
        let repo = tmp.appending(path: "repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let git = Process(); git.executableURL = URL(fileURLWithPath: "/bin/sh")
        git.arguments = ["-c", "cd '\(repo.path)' && git init -q && echo a > a && git add a && perl -e 'alarm 15; exec @ARGV' git commit -q"]
        git.environment = ["PATH": "/usr/bin:/bin", "HOME": tmp.path, "GIT_CONFIG_GLOBAL": "/dev/null", "EDITOR": "\(bin) compose", "VISUAL": "\(bin) compose",
                           "DUO_SESSION_ID": "s", ChatCompose.dirVariable: tmp.appending(path: "compose").path]
        git.standardInput = FileHandle.nullDevice; git.standardOutput = FileHandle.nullDevice; git.standardError = FileHandle.nullDevice
        let t0 = Date()
        try git.run(); git.waitUntilExit()
        let took = Date().timeIntervalSince(t0)
        check(git.terminationStatus != 0 && git.terminationReason == .exit && took < 10,
              "(d) git commit from Claude's Bash (no terminal, no hand-over) ends at once as it would without Duo: vi fails, git stops (\(String(format: "%.1f", took)) s)")
    }

    print("chat mode: duo2 session chat (DL-71, Q-53)")
    do {
        let m = AppModel(fixture: try repoFixture())
        ChatTargets.apply("chat-text", to: m)
        func cli(_ args: [String]) -> (ok: Bool, out: String) {
            var r: ControlResponse?
            m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()))) { r = $0 }
            return (r?.ok ?? false, r?.output ?? "")
        }
        let tab = m.consoleTab ?? ""
        let status = cli(["session", "chat"])
        check(status.ok && status.out.contains("chat mode, showing chat"), "status: the session on screen, its mode and what shows (\(status.out))")
        check(cli(["session", "chat", "off"]).ok && m.chat(for: tab)?.showsChat == false, "off: the terminal")
        check(cli(["session", "chat", "toggle"]).ok && m.chat(for: tab)?.showsChat == true, "toggle: back to chat")
        check(cli(["session", "chat", "PRD v2 edits", "off"]).ok && m.chat(for: tab)?.mode == .terminal, "a session by name")
        let answer = cli(["session", "chat", "answer", "1"])
        check(!answer.ok, "answer with no dialog waiting refuses, sending nothing (\(answer.out))")
        check(cli(["session", "chat", "--default", "chat"]).ok && m.chats.prefs.fixedDefault == .chat && cli(["session", "chat", "--default", "last"]).ok && m.chats.prefs.fixedDefault == nil,
              "--default chat|terminal|last")
        check(!cli(["session", "chat", "nobody", "on"]).ok, "an unknown session is refused")
        m.chats.setDefault(nil)
    }

    print("chat mode: ⌘[ / ⌘] between your messages (DL-119 §4, Q-54)")
    do {
        let c = ChatSession(key: "k", mode: .chat)
        for t in ["one", "two", "three"] { c.log.sent(t, time: nil, queued: false); c.log.textBlock("reply to \(t)", time: nil) }
        let ids = c.log.yourMessageIDs
        c.stepYourMessages(-1)
        check(c.revealRequest == ids[2], "⌘[ from the bottom: your latest message")
        c.stepYourMessages(-1); c.stepYourMessages(-1); c.stepYourMessages(-1)
        check(c.revealRequest == ids[0], "and back to your first, no further")
        c.stepYourMessages(1)
        check(c.revealRequest == ids[1], "⌘] forward")
    }

    print("chat mode: a claude that hangs on --version never freezes a session start (C-34)")
    do {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-hang-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let hang = dir.appending(path: "claude")
        try "#!/bin/sh\nsleep 600\n".write(to: hang, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hang.path)
        ClaudeVersion.forget()
        var t0 = Date()
        let v = ClaudeVersion.known(hang.path)
        let first = Date().timeIntervalSince(t0)
        check(v == nil && first < ClaudeVersion.timeout + 1.5, "a hung claude --version is ended after \(Int(ClaudeVersion.timeout)) s: the version is unknown (\(String(format: "%.1f", first)) s)")
        t0 = Date()
        _ = ClaudeVersion.known(hang.path)
        check(Date().timeIntervalSince(t0) < 0.2, "and asked once: the next session start doesn't wait again")
        let hooks = HookEvents.self
        let settings = try hooks.settingsFile(for: "h", in: dir, chatEvents: v.flatMap(ChatVersion.init).map { $0 >= ChatVersion.messageDisplay } ?? false)
        let h = (try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])?["hooks"] as? [String: Any] ?? [:]
        check(h["MessageDisplay"] == nil && h["Stop"] != nil, "with the version unknown, chat mode's hooks are off and Duo's own stay on")
        let ok = dir.appending(path: "claude-ok")
        try "#!/bin/sh\necho '2.1.291 (Claude Code)'\n".write(to: ok, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ok.path)
        check(ClaudeVersion.known(ok.path) == "2.1.291", "a working claude still answers")
        ClaudeVersion.forget()
    }
}
