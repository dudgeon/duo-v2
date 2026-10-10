import AppKit
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
    defer { try? askqFallbackChecks() }
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
        check(ChatScreenReader.read(spikeScreen("tour-2.1.291/12-unknown-model-picker.txt")).kind == .picker, "/model reads as its picker (a card, DL-143)")
        check(ChatScreenReader.read(spikeScreen("slash-2.1.292/help.txt")).kind == .unknown, "/help reads as unknown: the terminal")
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
              "the table names the versions checked dialog by dialog")
        check(ChatSignatures.trust(for: "2.1.293") == .verified && ChatSignatures.trust(for: "2.1.300") == .newer
              && ChatSignatures.trust(for: "2.1.219") == .newer && ChatSignatures.trust(for: "2.1.2") == .newer
              && ChatSignatures.trust(for: "2.0.77") == .unverified && ChatSignatures.trust(for: "3.0.1") == .unverified
              && ChatSignatures.trust(for: nil) == .unverified && ChatSignatures.trust(for: "garbage") == .unverified,
              "DL-145, DL-155: verified versions; any other 2.1.x, older or newer, by its screens; another version or none, not")
    }

    print("chat mode: Claude Code 2.1.219, the version work pins (DL-155, F-208)")
    do {
        // The 2.1.291 tour run on the real 2.1.219 against the mock (Spikes/chat-mode/screens/tour-2.1.219).
        let expect: [(String, ChatScreen.Kind)] = [("01-markdown", .idle), ("02-bash-permission", .permission), ("03-edit-permission", .permission),
            ("04-question", .question), ("05-multi", .question), ("06-review", .questionReview), ("07-agent", .idle), ("08-plan-mode", .idle),
            ("09-plan", .plan), ("10-streaming", .busy), ("11-interrupted", .idle), ("12-unknown-model-picker", .picker), ("13-retrying", .busy)]
        let read = expect.map { ($0.0, $0.1, ChatScreenReader.read(spikeScreen("tour-2.1.219/\($0.0).txt"))) }
        let wrong = read.filter { $0.2.kind != $0.1 }.map { "\($0.0): \($0.2.kind)" }
        check(wrong.isEmpty, "each 2.1.219 screen reads as its kind (\(wrong))")
        let broken = read.filter { !ChatScreenReader.wellFormed($0.2) }.map(\.0)
        check(broken.isEmpty, "and every dialog reads whole, so chat answers it (\(broken))")
        check(read[1].2.options.map(\.label) == ["Yes", "Yes, and always allow access to ws/ from this project", "No"]
              && read[8].2.options.count == 3 && read[7].2.mode == .plan, "2.1.219's own words: a Bash permission's options, plan approval, plan mode")
    }

    print("chat mode: falling back to the terminal (spike's fallback rules, DL-118 §3)")
    do {
        let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
        let tui = FakeTUI(idleText)
        let c = ChatSession(key: "s1", mode: .chat)
        c.attach(tui)
        check(c.showsChat && c.screen.kind == .idle, "chat shows at the prompt")
        tui.show(spikeScreen("slash-2.1.292/help.txt")); spin(0.15)
        check(c.showsChat, "an unknown screen waits out the grace period (a blank flash isn't a reason)")
        spin(0.6)
        check(!c.showsChat && c.fallback == .unknownScreen, "unknown for 500 ms: the terminal, with why")
        tui.show(idleText); spin(0.15)
        check(!c.showsChat && c.fallback == .unknownScreen, "back at the prompt: the terminal stays until Back to Chat (DL-154)")
        c.backToChat()
        tui.show(spikeScreen("slash-2.1.292/help.txt")); spin(0.1)
        tui.show(idleText); spin(0.6)
        check(c.showsChat, "a brief unknown never falls back")
        c.mode = .terminal
        tui.show(idleText); spin(0.15)
        check(!c.showsChat && c.fallback == nil, "chosen terminal stays the terminal")
        // DL-154 (F-208): a screen chat couldn't show leaves the terminal up until Back to Chat, so a
        // screen that keeps changing kind (a sign-in at every resume) can't swap the two.
        let helpText = spikeScreen("slash-2.1.292/help.txt")
        let flip = FakeTUI(idleText)
        let f = ChatSession(key: "s-flip", mode: .chat)
        f.attach(flip)
        for _ in 0..<3 { flip.show(helpText); spin(0.7); flip.show(idleText); spin(0.2) }
        check(!f.showsChat && f.fallback == .unknownScreen, "back at the prompt after a screen chat couldn't show: the terminal stays")
        check(f.fallback?.message.contains("comes back") == false, "and the bar doesn't promise chat comes back by itself")
        f.backToChat()
        check(f.showsChat && f.fallback == nil, "Back to Chat: chat")
        flip.show(""); spin(0.8)
        check(f.showsChat && f.screen.kind == .starting, "a blank screen (a session loading) is still starting: no fallback")
        // ENH-45: a chat off screen is dormant: the TUI repainting reads nothing until it's shown.
        let quiet = FakeTUI(idleText)
        let q = ChatSession(key: "s-dormant", mode: .chat)
        var shown = false
        q.isShown = { shown }
        q.attach(quiet)
        quiet.show(helpText); spin(0.8)
        check(q.screen.kind == .idle && q.showsChat, "off screen, a repaint isn't read (still \(q.screen.kind))")
        shown = true
        q.wake(); spin(0.8)
        check(q.screen.kind == .unknown && !q.showsChat, "shown again, it reads what it skipped at once (\(q.screen.kind))")
        let v = ChatSession(key: "s-version", mode: .chat)
        v.setVersion(nil)
        check(v.versionTrust == .unverified, "a claude that gave no version: unverified, not the verified default")
        let reads = FakeTUI(idleText)
        v.attach(reads)
        v.setVersion(nil)
        check(v.versionTrust == .unverified && v.cliVersion == nil, "asked again with the same answer: unchanged")
        let old = ChatSession(key: "s2", mode: .chat)
        old.setVersion("2.0.77")
        old.attach(FakeTUI(spikeScreen("10-bash-perm.txt")))
        check(!old.showsChat && old.fallback?.message.contains("2.0.77") == true, "a dialog on an unverified CLI (2.0.77) goes to the terminal")
        // DL-155: the work Mac's pinned 2.1.219, its dialog reading whole: answered from chat.
        let pinned = ChatSession(key: "s2-pinned", mode: .chat)
        pinned.setVersion("2.1.219")
        pinned.attach(FakeTUI(spikeScreen("10-bash-perm.txt")))
        check(pinned.versionTrust == .newer && pinned.dialogsVerified && pinned.fallback == nil, "an older 2.1.x (2.1.219) whose dialog reads whole: answered from chat")
        // DL-145: a newer CLI (Claude Code updates itself about daily, C-49) is trusted while its
        // dialog reads like the verified versions'; one that doesn't goes to the terminal.
        let bashPerm = spikeScreen("10-bash-perm.txt")
        let newer = ChatSession(key: "s2b", mode: .chat)
        newer.setVersion("2.1.300")
        newer.attach(FakeTUI(bashPerm))
        check(newer.versionTrust == .newer && newer.dialogsVerified && newer.fallback?.message.contains("2.1.300") != true,
              "a newer CLI whose permission dialog reads like the verified ones': answered from chat")
        let odd = ChatSession(key: "s2c", mode: .chat)
        odd.setVersion("2.1.300")
        odd.attach(FakeTUI(bashPerm.replacingOccurrences(of: " ❯ 1. Yes", with: "   1. Yes")))
        check(odd.screen.kind == .permission && !odd.dialogsVerified && !odd.showsChat && odd.fallback?.message.contains("doesn’t read like") == true,
              "a newer CLI whose dialog reads differently (no cursor row): the terminal, saying why")
        // Every dialog captured from a real TUI (tours, AskUserQuestion shapes, the CLI login) reads whole.
        let screensDir = repoRoot().appending(path: "Spikes/chat-mode/screens")
        var dialogs = 0, whole = 0, broken: [String] = []
        for case let url as URL in FileManager.default.enumerator(at: screensDir, includingPropertiesForKeys: nil) ?? FileManager.default.enumerator(atPath: "/")!
        where url.pathExtension == "txt" {
            let r = ChatScreenReader.read((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            guard [.permission, .plan, .question, .questionReview].contains(r.kind) else { continue }
            dialogs += 1
            if ChatScreenReader.wellFormed(r) { whole += 1 } else { broken.append(url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent) }
        }
        check(dialogs > 20 && broken.isEmpty, "every captured dialog reads whole, so a newer CLI with the same screens is trusted (\(whole)/\(dialogs); \(broken.prefix(4)))")
        let renumbered = ChatSession(key: "s2d", mode: .chat)
        renumbered.setVersion("2.1.300")
        renumbered.attach(FakeTUI(bashPerm.replacingOccurrences(of: " ❯ 1. Yes", with: " ❯ 4. Yes")))
        check(!renumbered.dialogsVerified && !renumbered.showsChat, "options not numbered 1…n: the terminal")
        // DL-164: the verified versions (2.1.291 to 293) are checked too: a dialog that reads whole is
        // answered from chat, one that doesn't goes to the terminal (DL-154, sticky) like any other version.
        func askScreen(_ rows: [String]) -> String {
            ([" ☐ Q", "", "Pick one?", ""] + rows + ["───────────────────────────────────────────────────────────────────────────────────────",
                "  Chat about this", "", "Enter to select · ↑/↓ to navigate · Esc to cancel"]).joined(separator: "\n")
        }
        for version in ["2.1.291", "2.1.292", "2.1.293"] {
            let whole = ChatSession(key: "v-whole-\(version)", mode: .chat)
            whole.setVersion(version)
            whole.attach(FakeTUI(askScreen(["❯ 1. A", "  2. B", "  3. Type something."])))
            check(whole.versionTrust == .verified && whole.screen.kind == .question && whole.dialogsVerified && whole.fallback?.message.contains("doesn’t read like") != true,
                  "\(version): a question that reads whole is still answered from chat")
            let skipped = ChatSession(key: "v-skip-\(version)", mode: .chat)
            skipped.setVersion(version)
            skipped.attach(FakeTUI(bashPerm.replacingOccurrences(of: "   3. No", with: "   4. No")))
            check(skipped.versionTrust == .verified && skipped.screen.kind == .permission && !skipped.dialogsVerified && !skipped.showsChat
                  && skipped.fallback?.message.contains("doesn’t read like") == true,
                  "\(version): a permission dialog with a skipped option number falls back to the terminal, not answered by number")
            let twoAsk = ChatSession(key: "v-ask-cursors-\(version)", mode: .chat)
            twoAsk.setVersion(version)
            twoAsk.attach(FakeTUI(askScreen(["❯ 1. A", "❯ 2. B", "  3. Type something."])))
            check(twoAsk.versionTrust == .verified && twoAsk.screen.kind == .question && !twoAsk.dialogsVerified && !twoAsk.showsChat
                  && twoAsk.fallback?.message.contains("doesn’t read like") == true,
                  "\(version): a question with two cursors falls back to the terminal")
            let twoCursors = ChatSession(key: "v-cursors-\(version)", mode: .chat)
            twoCursors.setVersion(version)
            twoCursors.attach(FakeTUI(bashPerm.replacingOccurrences(of: "   3. No", with: " ❯ 3. No")))
            check(twoCursors.versionTrust == .verified && twoCursors.screen.kind == .permission && !twoCursors.dialogsVerified && !twoCursors.showsChat
                  && twoCursors.fallback?.message.contains("doesn’t read like") == true,
                  "\(version): a permission dialog with two cursors falls back to the terminal")
        }
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

    print("chat mode: slash commands from the composer (2.1.292, F-173, F-174)")
    do {
        let dir = "slash-2.1.292/"
        let menu = ChatScreenReader.read(spikeScreen(dir + "menu-he.txt"))
        check(menu.kind == .idle && menu.input == "/he" && menu.commands.map(\.name) == ["/help", "/theme", "/doctor", "/rewind"],
              "the TUI's / menu under a part-typed command, its own rows (\(menu.commands.map(\.name)))")
        check(menu.commands.first?.selected == true && menu.commands.dropFirst().allSatisfy { !$0.selected }, "its selected row")
        check(ChatScreenReader.read(spikeScreen(dir + "menu-he-down.txt")).commands.first { $0.selected }?.name == "/theme", "↓ moves the TUI's selection")
        let tui = FakeTUI(spikeScreen(dir + "menu-he.txt"))
        let c = ChatSession(key: "slash", mode: .chat)
        c.attach(tui)
        c.ui.composer = "/he"
        check(c.commandMenuShown && c.selectedCommand == "/help", "a part-typed /he: Return runs /help, the selected row, as the TUI does")
        c.ui.composer = "/help me"
        check(!c.commandMenuShown, "a command with arguments: no menu, the text is sent as typed")
        c.ui.composer = "/he"
        Task { await c.moveCommandMenu(.down) }
        spin(0.3)
        check(tui.keys == [ChatKey.down.bytes], "↓ in the composer goes to the TUI's menu")
        // 2.1.219 draws the menu under the input box from column 0, the selected row by colour only.
        let m219 = ChatScreenReader.read(spikeScreen("slash-2.1.219/menu-mo.txt"))
        check(m219.kind == .idle && m219.input == "/mo" && m219.commands.prefix(3).map(\.name) == ["/model", "/mobile", "/memory"] && m219.commands.count == 12,
              "2.1.219's / menu under /mo, rows from column 0 (\(m219.commands.count): \(m219.commands.prefix(3).map(\.name)))")
        check(m219.commands.first?.description == "Set the AI model for Claude Code (currently claude-haiku-5-5)" && m219.commands.allSatisfy { !$0.selected }, "its description; no selected row (colour only)")
        let s219 = ChatScreenReader.read(spikeScreen("slash-2.1.219/menu-slash.txt"))
        check(s219.input == "/" && s219.commands.first?.name == "/add-dir" && s219.commands.allSatisfy { $0.name.hasPrefix("/") && $0.description.first != " " }, "2.1.219's / menu under a bare `/` (\(s219.commands.count) rows)")
        check(ChatScreenReader.read(spikeScreen("tour-2.1.219/01-markdown.txt")).commands.isEmpty, "2.1.219's prompt, rules and footer are no command rows")
        check(ChatScreenReader.read(spikeScreen("tour-2.1.292/01-markdown.txt")).commands.isEmpty, "nor 2.1.292's")
        // 2.1.219's preview question: Return inside the notes field sends "(notes only)"; Esc leaves it with the notes kept.
        let typed = ChatScreenReader.read(spikeScreen("preview-notes-2.1.219/04-typed.txt"), cols: 100)
        let left = ChatScreenReader.read(spikeScreen("preview-notes-2.1.219/05-esc-notes-kept.txt"), cols: 100)
        check(typed.kind == .question && typed.preview && typed.notes == "keep it short" && left.kind == .question && left.preview && left.notes == "keep it short"
              && left.cursor == typed.cursor && left.options[left.cursor].label == "Side by side", "2.1.219: after Esc the notes stay and the cursor is on the chosen option")
        for f in ["help", "usage", "config", "permissions", "resume", "skills", "btw", "sandbox"] {
            check(ChatScreenReader.read(spikeScreen(dir + f + ".txt")).kind == .unknown, "/\(f)'s screen reads as unknown: the terminal")
        }
        let plan = ChatScreenReader.read(spikeScreen(dir + "plan-output.txt"))
        check(plan.kind == .idle && plan.mode == .plan, "/plan prints a line and stays at the prompt, in plan mode")
        check(ChatScreenReader.read(spikeScreen(dir + "rename-output.txt")).kind == .idle, "/rename's name in the input box's rule still reads")
        let marked = ChatSignatures.v2_1_291.terminalCommands
        check(["/help", "/usage", "/btw", "/sandbox"].allSatisfy(marked.contains) && !["/doctor", "/agents", "/mcp", "/context", "/plan", "/model", "/effort"].contains(where: marked.contains),
              "the menu marks what opens in the terminal on 2.1.292")

        // A command that opens a screen while its keys are still going: judged once they've gone.
        let idleText = spikeScreen("tour-2.1.291/01-markdown.txt")
        let t2 = FakeTUI(idleText)
        let s = ChatSession(key: "slash2", mode: .chat)
        s.attach(t2)
        s.sending = true
        t2.show(spikeScreen(dir + "help.txt")); spin(0.7)
        check(s.showsChat, "while keys are going, an unknown screen waits")
        s.sending = false
        spin(0.7)
        check(!s.showsChat && s.fallback == .unknownScreen, "once sent, /help's screen (which never redraws) shows the terminal")
        t2.show(idleText); spin(0.15)
        check(!s.showsChat, "a screen not named as a command you sent stays in the terminal when it closes (DL-154)")
        s.backToChat()
        check(s.showsChat, "until Back to Chat")

        // The transcript's records of a command.
        let log = ChatLog()
        log.sent("/rename notes", time: Date(), queued: false)
        // 2.1.292 records /rename as `system` / `local_command`; others as your message.
        ChatIngest.record(["type": "system", "subtype": "local_command", "content": "<command-name>/rename</command-name>\n            <command-message>rename</command-message>\n            <command-args>notes</command-args>"], into: log)
        ChatIngest.record(["type": "system", "subtype": "local_command", "content": "<local-command-stdout>Session renamed to: notes</local-command-stdout>"], into: log)
        ChatIngest.record(["type": "user", "message": ["content": "<local-command-caveat>The command below was run directly in Claude Code…</local-command-caveat>"]], into: log)
        ChatIngest.record(["type": "user", "message": ["content": "<local-command-stdout>(no content)</local-command-stdout>"]], into: log)
        ChatIngest.record(["type": "user", "message": ["content": "<command-name>/plan</command-name>\n<command-args></command-args>"]], into: log)
        ChatIngest.record(["type": "user", "message": ["content": "<local-command-stdout>Enabled plan mode</local-command-stdout>"]], into: log)
        func shown(_ l: ChatLog) -> [String] {
            l.items.compactMap { i -> String? in
                switch i { case .you(let y): "you: \(y.text)"; case .note(let n): "note: \(n.text)"; case .result(let r): "result: \(r.summary)"; default: nil }
            }
        }
        check(shown(log) == ["you: /rename notes", "result: Session renamed to: notes", "you: /plan", "result: Enabled plan mode"], "the sent command is matched, not doubled; its output its result under it (\(shown(log)))")
        let replay = ChatLog()
        ChatIngest.record(["type": "user", "message": ["content": "<command-message>init is analyzing your codebase…</command-message>\n<command-name>/init</command-name>"]], into: replay)
        ChatIngest.record(["type": "user", "isMeta": true, "message": ["content": "Please analyze this codebase…"]], into: replay)
        check(shown(replay) == ["you: /init"], "a replayed /init shows the command above Claude's reply, not the skill's prompt (\(shown(replay)))")

        // /clear, /branch, /resume: a new id in the same process.
        let store = ChatStore(persist: false)
        store.prefs.set(.terminal, for: "other")   // the mode used last is the terminal
        let old = store.session("before")
        old.mode = .chat
        old.launchId = "before"
        store.rekey("before", to: "after")
        check(store.existing("before") == nil && store.session("after").mode == .chat, "the new session keeps chat, whatever was used last")
        store.prefs.modes["quiet"] = .chat
        store.rekey("quiet", to: "quiet2")
        check(store.prefs.mode(for: "quiet2") == .chat, "a session whose chat was never opened keeps its mode too")
        check(TerminalCommand.newClaude(sessionID: "launch", prompt: nil).launchId == "launch" && TerminalCommand.shell.launchId == nil,
              "the hand-over is named by the id the process started with: duo2 compose knows no other")
    }

    print("chat mode: slash commands as designed (DL-143)")
    do {
        let dir = "slash-2.1.292/"
        // A: what a command prints.
        guard case .line(let one)? = ChatCommandOutput.body("Session renamed to: notes") else { check(false, "one line"); return }
        check(one == "Session renamed to: notes", "one line: a quiet line")
        check(ChatCommandOutput.body("(no content)") == nil && ChatCommandOutput.body("  \n") == nil, "(no content) and nothing: nothing shown")
        if case .block(let lines)? = ChatCommandOutput.body(spikeScreen(dir + "output-style-stdout.txt")) {
            check(lines.first == "Output style: default" && lines.count >= 8, "several lines: an output block, verbatim (\(lines.count) lines)")
        } else { check(false, "/output-style is a block") }
        let raw = spikeScreen(dir + "context-stdout.txt")
        check(raw.contains("\u{1B}[") && !ChatCommandOutput.plain(raw).contains("\u{1B}"), "/context's colour codes are stripped")
        if case .context(let c)? = ChatCommandOutput.body(raw) {
            check(c.model == "Haiku 4.5" && c.modelId == "claude-haiku-4-5-20251001" && c.used == "3k" && c.total == "200k" && c.percent == "1",
                  "/context's model, id and total from its record (\(c.model ?? "-") \(c.used)/\(c.total) \(c.percent)%)")
            check(c.categories.map(\.name) == ["System prompt", "Skills", "Messages", "Free space"] && c.categories.last?.free == true
                  && c.categories.first?.amount == "1.3k" && abs((c.categories.first?.share ?? 0) - 0.7) < 0.001,
                  "its categories in the screen's order, Free space last (\(c.categories.map(\.name)))")
            check(c.skills == "15 skills · 1.6k tokens", "the skills line (\(c.skills ?? "-"))")
        } else { check(false, "/context reads as the box") }
        check(ChatCommandOutput.context("Context Usage\nnothing parseable") == nil, "a /context that doesn't parse isn't drawn as the box (it's a block)")
        let elog = ChatLog()
        ChatIngest.record(["type": "system", "subtype": "local_command", "content": "<command-name>/context</command-name>\n<command-args></command-args>"], into: elog)
        ChatIngest.record(["type": "system", "subtype": "local_command", "content": "<local-command-stdout>" + raw + "</local-command-stdout>"], into: elog)
        if case .result(let r)? = elog.items.last, case .context = r.body { check(true, "replayed, /context is the box again: Claude Code keeps it (Q-107)") } else { check(false, "/context replay") }

        // E: /model's and /effort's screens.
        let model = ChatScreenReader.read(spikeScreen(dir + "model.txt"))
        check(model.kind == .picker && model.picker?.kind == .model, "/model's screen is a picker (\(model.kind))")
        if let p = model.picker {
            check(p.rows.map(\.n) == [1, 2, 3, 4, 5] && p.rows.map(\.name) == ["Default (recommended)", "Opus", "Fable", "Sonnet", "Haiku"],
                  "its rows, numbered, with Claude Code's names (\(p.rows.map(\.name)))")
            check(p.rows[2].note.hasSuffix("tasks · $10/$50 per Mtok") && p.rows[4].selected && p.rows[4].cursor && p.cursor == 4,
                  "a wrapped description joined; ✔ in use; the cursor on it")
            check(p.description.hasPrefix("Switch between Claude models.") && p.footnotes == ["○ Effort not supported for Haiku"], "its description and footnote")
        }
        let effort = ChatScreenReader.read(spikeScreen(dir + "effort.txt"))
        check(effort.kind == .picker && effort.picker?.levels == ["low", "medium", "high", "xhigh", "max"] && effort.picker?.level == 2
              && effort.picker?.ends?.0 == "Faster" && effort.picker?.ends?.1 == "Smarter",
              "/effort: five levels, the ▲ on high, Faster … Smarter (\(effort.picker?.levels ?? []) \(effort.picker?.level ?? -1))")
        check(ChatScreenReader.wellFormed(model) && ChatScreenReader.wellFormed(effort), "both read whole: a newer CLI with these screens gets the card (DL-145)")
        let m293 = ChatScreenReader.read(spikeScreen("tour-2.1.293/12-unknown-model-picker.txt"))
        check(m293.kind == .picker && m293.picker?.rows.count == 6 && m293.picker?.cursor == 5, "2.1.293's longer list reads too (\(m293.picker?.rows.count ?? 0) rows)")

        // E: keys go to the TUI's own cursor, after the check.
        var at = 4
        func modelScreen(_ i: Int) -> String {
            spikeScreen(dir + "model.txt").components(separatedBy: "\n").map { l in
                guard let m = l.firstMatch(of: /^(\s*)(❯ )?(\s*)(\d)\. (.*)$/), let n = Int(m.4) else { return l }
                return String(m.1) + (n == i + 1 ? "❯ " : "  ") + String(m.3) + "\(n). " + String(m.5)
            }.joined(separator: "\n")
        }
        let tui = FakeTUI(modelScreen(at))
        tui.react = { k, t in
            if k == ChatKey.up.bytes { at = max(0, at - 1); t.show(modelScreen(at)) }
            if k == ChatKey.down.bytes { at = min(4, at + 1); t.show(modelScreen(at)) }
        }
        let c = ChatSession(key: "picker", mode: .chat)
        c.attach(tui)
        check(c.pickerUp && c.showsChat, "the /model card is up in chat")
        var moved: ChatAnswerResult?
        Task { moved = await c.pickerMove(to: 2) }
        spin(1.2)
        check(moved?.ok == true && at == 1 && tui.keys == Array(repeating: ChatKey.up.bytes, count: 3), "2 moves the TUI's cursor up three rows; nothing chosen (\(tui.keys.count) keys)")
        var finished: ChatAnswerResult?
        Task { finished = await c.pickerFinish(.sessionOnly) }
        spin(0.5)
        check(finished?.ok == true && tui.keys.last == "s", "This Session Only presses s")
        tui.show(spikeScreen("tour-2.1.291/01-markdown.txt")); spin(0.2)
        var gone: ChatAnswerResult?
        Task { gone = await c.pickerFinish(.confirm) }
        spin(0.5)
        check(gone?.ok == false && tui.keys.last == "s", "once the picker has gone, nothing more is sent")

        // E: the bar names the command you opened.
        check(ChatFallback.command("/permissions").message == "/permissions opens in Claude Code’s own screen. Esc closes it and brings chat back."
              && ChatFallback.command("/usage").message == "/usage shows in Claude Code’s own screen. Esc closes it and brings chat back."
              && ChatFallback.command("/config").message.hasSuffix("Esc clears the search, then closes it."),
              "the named bar's words: opens, shows, and two Escs for /config and /resume")

        // M1: the / menu's name column.
        check(ChatCommandColumn.width(["/model", "/mobile"]) == 122, "short names: the approved 122")
        let mono = NSFont.monospacedSystemFont(ofSize: DuoTextStyle.mono.spec.size, weight: .regular)
        let longest = ("/design:design-critique" as NSString).size(withAttributes: [.font: mono]).width
        check(ChatCommandColumn.width(["/design:design-critique", "/deep-research"]) == ceil(longest + 36),
              "the longest name shown and 36 (the board's 202 in a browser's mono; \(ChatCommandColumn.width(["/design:design-critique"])) in AppKit's)")
        check(ChatCommandColumn.width(["/cowork-plugin-management:cowork-plugin-customizer"]) == 280, "at most 280")
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

    print("chat mode: a long chat opens off the main thread (F-160)")
    do {
        // Every board's recording, replayed off the main thread, gives the log the main thread's replay gives.
        let boards = repoRoot().appending(path: "docs/design/chat-mode-handoff/fixture-chat")
        var same = 0, all = 0
        for b in ((try? FileManager.default.contentsOfDirectory(atPath: boards.path)) ?? []).sorted() {
            guard let data = try? Data(contentsOf: boards.appending(path: "\(b)/transcript.jsonl")) else { continue }
            let recs = ChatIngest.lines(data)
            let main = ChatLog()
            for r in recs { ChatIngest.record(r, into: main) }
            var off: ChatLog?
            Task { off = await ChatFeedProbe.replayOffMain(data) }
            let until = Date().addingTimeInterval(5)
            while off == nil, Date() < until { spin(0.01) }
            all += 1
            if off?.items == main.items { same += 1 } else { print("    differs: \(b)") }
        }
        check(all > 5 && same == all, "every board's transcript replays the same off the main thread (\(same)/\(all))")
        // The log a chat draws asserts it's changed on the main thread; a scratch replay's doesn't.
        check(ChatSession(key: "k", mode: .chat).log.drawn && !ChatLog().drawn, "only the drawn log is held to the main thread")

        // Steps are found by id across turns, after the turn they're in has closed.
        let log = ChatLog()
        log.prompt("one", time: nil, fromHook: false)
        log.toolUse(id: "a", name: "Bash", input: ["command": "ls"], time: nil)
        log.prompt("two", time: nil, fromHook: false)
        log.toolUse(id: "b", name: "Read", input: ["file_path": "/x/y.md"], time: nil)
        log.toolUse(id: "a", name: "Bash", input: ["command": "ls"], time: nil)
        log.toolResult(id: "a", name: nil, input: nil, result: ["stdout": "x\ny"], content: nil, isError: false, time: nil)
        check(log.step("a")?.status == .done && log.step("a")?.output?.count == 3 && log.step("b")?.status == .running,
              "a result reaches its step in an earlier turn; a repeated call adds nothing")
        check(log.steps.map(\.id) == ["a", "b"] && log.items.count == 4, "each step once, in its own turn")

        // Timestamps read by hand agree with the formatter, and odd ones still parse.
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        check(ChatFeedProbe.date("2026-10-06T09:41:07.123Z") == iso.date(from: "2026-10-06T09:41:07.123Z")
              && ChatFeedProbe.date("2026-02-28T23:59:59.5Z") == iso.date(from: "2026-02-28T23:59:59.500Z"), "transcript timestamps, read by hand")
        check(ChatFeedProbe.date("2026-10-06T09:41:07Z") == plain.date(from: "2026-10-06T09:41:07Z") && ChatFeedProbe.date("not a date") == nil,
              "a timestamp without a fraction, and none at all")

        // Markdown is parsed once per text and the copy is the same.
        let md = "## Plan\n\n- one\n- two\n\n```swift\nlet a = 1\n```"
        check(ChatMarkdown.parse(md) == ChatMarkdown.parse(md) && ChatMarkdown.parse(md).count == 3, "a cached parse is the parse")
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
        // A fixed environment for Duo, with and without a user EDITOR: never this process's own, which
        // inside a Duo session already has the compose helper as EDITOR.
        let bare = ["HOME": "/Users/u", "PATH": "/usr/bin:/bin", "SHELL": "/bin/zsh"]
        let withEditor = bare.merging(["EDITOR": "vim", "VISUAL": "code --wait"]) { $1 }
        func value(_ env: [String], _ k: String) -> String? { env.first { $0.hasPrefix(k + "=") }.map { String($0.dropFirst(k.count + 1)) } }
        let shell = ChildEnvironment.make(sessionID: nil, base: withEditor), bareShell = ChildEnvironment.make(sessionID: nil, base: bare)
        let claude = ChildEnvironment.make(sessionID: "abc", base: withEditor), bareClaude = ChildEnvironment.make(sessionID: "abc", base: bare)
        ChildEnvironment.cliDirectory = saved
        check(value(shell, "EDITOR") == "vim" && value(shell, "VISUAL") == "code --wait" && value(bareShell, "EDITOR") == nil
              && !(shell + bareShell).contains { $0.hasPrefix(ChatCompose.dirVariable + "=") },
              "(c) a plain shell tab keeps the user's EDITOR and VISUAL, or has none; only Claude sessions get the helper")
        let helperCmd = "/Applications/Duo.app/Contents/Helpers/duo2 compose"
        check(value(claude, "EDITOR") == helperCmd && value(claude, "VISUAL") == helperCmd && value(bareClaude, "EDITOR") == helperCmd
              && value(claude, ChatCompose.userEditor) == "vim" && value(claude, ChatCompose.userVisual) == "code --wait"
              && value(bareClaude, ChatCompose.userEditor) == nil && value(claude, ChatCompose.dirVariable) != nil,
              "(c) Claude sessions do, and keep the user's EDITOR and VISUAL for the helper to hand on")
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

    print("chat mode: shift+tab cycles Claude Code's modes (F-179)")
    do {
        let base = spikeScreen("tour-2.1.291/01-markdown.txt")
        let footers = ["⏸ manual mode on · ? for shortcuts", "⏵⏵ accept edits on (shift+tab to cycle)", "⏸ plan mode on (shift+tab to cycle)"]
        func screen(_ i: Int) -> String { base.replacingOccurrences(of: #"⏸ manual mode on[^\n]*"#, with: footers[i], options: .regularExpression) }
        check(ChatScreenReader.read(screen(2)).mode == .plan, "the footer's mode is read (plan)")
        check(ChatScreenReader.read(base.replacingOccurrences(of: #"⏸ manual mode on[^\n]*"#, with: "⏵⏵ bypass permissions on (shift+tab to cycle)", options: .regularExpression)).mode == .bypass,
              "bypass permissions, when this claude offers it")
        var at = 0
        let tui = FakeTUI(screen(0))
        tui.react = { k, t in if k == ChatKey.shiftTab.bytes { at = (at + 1) % footers.count; t.show(screen(at)) } }
        let c = ChatSession(key: "modes", mode: .chat)
        c.attach(tui)
        var got: ChatPermissionMode?
        Task { got = await c.cycleMode(to: .plan) }
        spin(1.5)
        check(got == .plan && tui.keys == [ChatKey.shiftTab.bytes, ChatKey.shiftTab.bytes], "a mode by name: shift+tab until the footer shows it (\(tui.keys.count) presses)")
        var none: ChatPermissionMode? = .manual
        Task { none = await c.cycleMode(to: .auto) }
        spin(3)
        check(none == nil && tui.keys.count <= 2 + 6, "a mode this claude's cycle hasn't got: refused after one round, not forever")
    }

    print("chat mode: Return reaches the composer after the idle list (F-178)")
    do {
        let m = AppModel(fixture: try repoFixture())
        m.toggleIdleList()
        check(m.idleOpen && IdleKeys.installed, "the idle list open on All projects takes the keys")
        let project = m.fixture.projects.first { !($0.isHome ?? false) }?.name ?? m.fixture.projects[0].name
        m.open(project: project)
        check(!m.idleOpen && !IdleKeys.installed, "opening a project another way closes it, and its keys go")
        m.idleOpen = true   // as if it had stayed open
        check(!IdleKeys.handle(m, code: 36, flags: [], chars: "\r") && !IdleKeys.handle(m, code: 0, flags: [], chars: "a"),
              "even so, away from All projects Return and letters pass to the composer")
        IdleKeys.remove()
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

    print("chat mode: runs of tool calls fold to one line (DL-135, chat-polish-handoff)")
    do {
        /// A polish board's recording, played as the targets play it; the last Claude turn's rows.
        func rows(_ board: String) -> [ChatCardRow] {
            let c = ChatSession(key: "polish-" + board, mode: .chat)
            ChatRecording.play(repoRoot().appending(path: "docs/design/chat-polish-handoff/fixture-chat/polish-\(board)"), into: c)
            guard case .claude(let t)? = c.log.items.last(where: { if case .claude = $0 { return true } else { return false } }) else { return [] }
            return ChatRuns.blocks(t.segments)
        }
        func lines(_ r: [ChatCardRow]) -> [String] {
            r.compactMap { if case .run(let x) = $0 { return ChatRuns.line(x) } else { return nil } }
        }
        let c1 = rows("collapsed")
        check(lines(c1) == ["Ran 4 shell commands, read 3 files", "Edited 2 files, ran 1 shell command · prd-v2.md, flows.md +6 −3"],
              "a run is one line in the terminal's words, edits named (\(lines(c1)))")
        check(c1.map { if case .text = $0 { "text" } else if case .run = $0 { "run" } else { "other" } } == ["text", "run", "text", "run", "text"],
              "Claude's text between runs stays out of the folds")
        if case .run(let r)? = c1.first(where: { if case .run = $0 { return true } else { return false } }) {
            check(r.id == "run-toolu_c1" && r.steps.count == 5 && r.steps[0].summary == "Run the docs lint", "a run keeps its first step's id; a command keeps Claude's description; reads in a row are one step")
        }
        let ny = rows("needs-you")
        let kinds = ny.map { r -> String in
            switch r { case .run: "run"; case .step(let s): s.status == .needsYou ? "needs-you" : "step"; default: "other" }
        }
        check(kinds == ["run", "needs-you"] && lines(ny) == ["Ran 2 shell commands, read 1 file"], "a step waiting on you is never folded (\(kinds))")
        let th = rows("thinking")
        let thKinds = th.map { r -> String in switch r { case .run: "run"; case .thinking: "thought"; case .text: "text"; default: "other" } }
        check(thKinds == ["run", "thought", "text"], "thinking between calls is inside the run; the last before the text stays a line (\(thKinds))")
        if case .run(let r) = th[0] { check(r.entries.count == 6, "the run holds its three thoughts and three steps (\(r.entries.count))") }
        let ag = rows("agents")
        check(ag.filter { if case .step(let s) = $0 { return s.agent != nil } else { return false } }.count == 2 && lines(ag).isEmpty, "agents keep their own lines")
        let td = rows("todos")
        let todoRows = td.compactMap { r -> ChatToolStep? in if case .todos(let s) = r { return s } else { return nil } }
        check(todoRows.count == 1 && ChatRuns.todoLine(todoRows[0].todos ?? []) == "3 of 5 done", "to-do updates are one line, the latest (\(todoRows.count))")
        check(lines(td) == ["Ran 1 shell command, edited 1 file · prd-v2.md +2 −1"], "and the run around them stays one run (\(lines(td)))")
        check(lines(rows("tools")) == ["Loaded 2 tools, used claude-in-chrome 5 times, sent 1 message"], "MCP and housekeeping tools counted by server and kind (\(lines(rows("tools"))))")
        check(lines(rows("failed")) == ["Ran 4 shell commands · 1 failed"], "a failure is counted on the run's line")
        // While a run is going: the kinds done, then the one still going.
        let log = ChatLog()
        log.toolUse(id: "g1", name: "Grep", input: ["pattern": "saved card"], time: nil)
        log.toolResult(id: "g1", name: "Grep", input: nil, result: ["numFiles": 2], content: nil, isError: false, time: nil)
        log.toolUse(id: "g2", name: "Read", input: ["file_path": "/a.md"], time: nil)
        log.toolResult(id: "g2", name: "Read", input: nil, result: nil, content: "x", isError: false, time: nil)
        log.toolUse(id: "g3", name: "Grep", input: ["pattern": "guest checkout"], time: nil)
        guard case .claude(let turn)? = log.items.last, case .run(let r)? = ChatRuns.blocks(turn.segments).first else { return check(false, "a running run") }
        check(ChatRuns.line(r) == "Searched for 1 pattern, read 1 file, searching for 1 pattern…", "a running run counts up (\(ChatRuns.line(r)))")
    }

    print("chat mode: paste in the composer (images through Claude Code's Ctrl+V)")
    do {
        func board(_ fill: (NSPasteboard) -> Void) -> NSPasteboard { let pb = NSPasteboard.withUniqueName(); pb.clearContents(); fill(pb); return pb }
        let png: Data = {
            let img = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
            return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        }()
        let text = board { $0.setString("hello", forType: .string) }
        let image = board { $0.setData(png, forType: .png) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-paste-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pic = dir.appending(path: "a.png"), doc = dir.appending(path: "b.txt")
        try png.write(to: pic); try Data("x".utf8).write(to: doc)
        let file = board { $0.writeObjects([doc as NSURL]) }
        let pics = board { $0.writeObjects([pic as NSURL, doc as NSURL]) }
        check(!ChatPaste.canPaste(board { _ in }), "paste is off for an empty pasteboard")
        check(ChatPaste.canPaste(text) && ChatPaste.canPaste(image) && ChatPaste.canPaste(file), "paste is on for text, an image and a copied file")
        func shape(_ pb: NSPasteboard) -> String {
            ChatPaste.routes(pb).map { r -> String in switch r { case .text: "text"; case .chip(let u): "chip:" + u.lastPathComponent; case .image(let i): i == nil ? "image?" : "image" } }.joined(separator: ",")
        }
        check(shape(text) == "text" && shape(image) == "image", "text pastes as text, an image alone as the image route (\(shape(text)) \(shape(image)))")
        check(shape(file) == "chip:b.txt" && shape(pics) == "chip:b.txt,image", "a copied file is a chip; an image file goes the image route (\(shape(file)) \(shape(pics)))")
        check(shape(board { $0.setString("a.png", forType: .string); $0.setData(png, forType: .png) }) == "text", "text with an image is text")
        try? FileManager.default.removeItem(at: dir)

        check(ChatKey.ctrlV.bytes == "\u{16}", "Ctrl+V is byte 0x16")
        check(ChatPaste.newToken(before: "", after: "[Image #1] ") == "[Image #1]" && ChatPaste.newToken(before: "[Image #1] ", after: "[Image #1] [Image #2] ") == "[Image #2]"
              && ChatPaste.newToken(before: "[Image #1] hi", after: "[Image #1] hi") == nil && ChatPaste.newToken(before: "[Image #2] ", after: "[Image #3] ") == "[Image #3]", "a new [Image #N] token is read from the prompt before and after")

        let a = ["[Image #1]", "[Image #2]", "[Image #3]"]
        let keepAll = ChatPaste.sendPlan(held: a, kept: a, text: " what are these ")
        check(keepAll == .init(remove: [], keep: a, paste: "what are these") && keepAll.message == "[Image #1] [Image #2] [Image #3] what are these", "send plan: pictures first, a space, then the words (\(keepAll.message))")
        let drop = ChatPaste.sendPlan(held: a, kept: ["[Image #2]"], text: "see only")
        check(drop == .init(remove: ["[Image #1]", "[Image #3]"], keep: ["[Image #2]"], paste: "see only") && drop.message == "[Image #2] see only", "send plan: a removed picture's token is deleted, the rest stay (\(drop))")
        check(ChatPaste.sendPlan(held: a, kept: [], text: "plain").message == "plain" && ChatPaste.sendPlan(held: [], kept: [], text: " ").message.isEmpty
              && ChatPaste.sendPlan(held: ["[Image #4]"], kept: ["[Image #4]"], text: "").message == "[Image #4]", "send plan: no pictures, nothing to send, pictures alone")
        check(ChatPaste.stripTokens("[Image #1] [Image #2]why is this") == "why is this" && ChatPaste.stripTokens("see [Image #1] now") == "see now" && ChatPaste.stripTokens("[Image #1]") == "", "a bubble's text keeps no [Image #N] and no space it leaves (\(ChatPaste.stripTokens("see [Image #1] now")))")
        check(ChatPaste.promptHoldsOnly("[Image #1] [Image #2]", a) && !ChatPaste.promptHoldsOnly("[Image #1] typed", a) && !ChatPaste.promptHoldsOnly("[Image #7]", a), "the prompt may hold only the tokens this composer put there")
        let path = "@tasks/exec-review-prep.md"
        check(ChatPaste.carried(prompt: path + " ", text: "Please summarise.") == path, "a task's drafted path in Claude's prompt is carried ahead of the composer's text (F-254)")
        check(ChatPaste.carried(prompt: path + " [Image #1]", text: "[Image #1] words") == path, "and so is words beside a picture's token, never the token")
        check(ChatPaste.carried(prompt: path, text: path + " Please summarise.").isEmpty, "not when the composer opened on it and already starts with it")
        check(ChatPaste.carried(prompt: "", text: "words").isEmpty && ChatPaste.carried(prompt: "/mo", text: "words").isEmpty && ChatPaste.carried(prompt: "[Image #1]", text: "words").isEmpty, "nothing is carried from an empty prompt, a `/` command or a lone token")
        // F-232: Ctrl+A, Right once per unit from the start up to and including the token, Backspace.
        var units = ChatPaste.units("[Image #1] [Image #2] [Image #3]"), keys: [[ChatKey]] = []
        check(units == ["[Image #1]", " ", "[Image #2]", " ", "[Image #3]"], "a prompt's units: a token is one, no space is assumed after the last")
        for t in ["[Image #1]", "[Image #3]"] {
            let step = ChatPaste.deleteStep(units: units, token: t)!
            keys.append(step.keys); units = step.units
        }
        check(keys == [[.ctrlA, .right, .backspace], [.ctrlA, .right, .right, .right, .right, .backspace]] && units == [" ", "[Image #2]", " "],
              "deleting tokens: Ctrl+A, Right to just after it counted from the start, Backspace (\(keys))")
        check(ChatKey.ctrlA.bytes == "\u{01}" && ChatKey.ctrlE.bytes == "\u{05}", "Ctrl+A and Ctrl+E are bytes 1 and 5")
        check(ChatPaste.deleteStep(units: units, token: "[Image #5]") == nil, "a token the prompt lacks is refused")
    }
    do {
        let log = ChatLog()
        let b64 = Data("png".utf8).base64EncodedString()
        let rec: ChatJSON = ["type": "user", "timestamp": "2026-10-08T10:00:00.000Z", "message": ["role": "user", "content": [
            ["type": "text", "text": "[Image #1]what is this"], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": b64]]]]]
        ChatIngest.record(rec, into: log, lastDeclined: nil)
        guard case .you(let y)? = log.items.last else { return check(false, "a message with an image") }
        check(y.text == "what is this" && y.images.map(\.data) == [Data("png".utf8)] && y.images[0].mediaType == "image/png", "an image block is kept on your message, its token is out of the text")
        // A message sent from the composer: its pictures show at once; the hook's text (with tokens) finds the same bubble.
        let sent = ChatLog()
        sent.sent("why", images: [ChatImage(mediaType: "image/png", data: Data("mine".utf8))], time: nil, queued: false)
        sent.prompt("[Image #1] why", time: nil, fromHook: true)
        guard case .you(let m)? = sent.items.last else { return check(false, "a sent message") }
        check(sent.items.count == 1 && m.images.count == 1 && m.text == "why", "a hook's prompt with tokens finds the bubble sent from the composer")
        ChatIngest.record(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": "[Image #1] why"], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": b64]]]]], into: sent, lastDeclined: nil)
        guard case .you(let m2)? = sent.items.last else { return check(false, "the transcript's echo") }
        check(sent.items.count == 1 && m2.images.map(\.data) == [Data("png".utf8)], "the transcript's own picture replaces the composer's, once")
    }

    print("chat mode: a long paste folds to a block in the composer (chat-paste-handoff `text`)")
    do {
        let lines = { (n: Int) in (1...n).map { "line \($0)" }.joined(separator: "\n") }
        check(!ChatPaste.isLongPaste(lines(12)) && ChatPaste.isLongPaste(lines(13)) && ChatPaste.isLongPaste(lines(12) + "\n"), "over 12 lines folds, 12 doesn't (a trailing newline counts, as K8's rule does)")
        check(!ChatPaste.isLongPaste(String(repeating: "x", count: 5000)), "a long single line is plain text")
        check(ChatPaste.blockLabel(lines(42)) == "42 lines", "a block names its lines (\(ChatPaste.blockLabel(lines(42))))")
        let big = (0..<12_480).map { _ in String(repeating: "x", count: 95) }.joined(separator: "\n")
        check(ChatPaste.blockLabel(big) == "12,480 lines · 1.2 MB", "a big paste adds its size (\(ChatPaste.blockLabel(big)))")
        check(ChatPaste.blockPreview("Review notes, 8 October\n1. Guest checkout keeps it.\n\n2. Saved cards need an account") == "Review notes, 8 October. 1. Guest checkout keeps it. 2. Saved cards need an account", "the preview is the paste's start on one line")
        let t = (["Review notes"] + (1...41).map { "note \($0)" }).joined(separator: "\n"), u = lines(20)
        let ms = ComposerProbe.keystrokeMillis(afterBlock: big)
        print("    a keystroke after a 12,480-line paste: \(String(format: "%.1f", ms)) ms")
        check(ms < 30, "typing after a 12,480-line paste stays responsive (\(String(format: "%.1f", ms)) ms a key)")
        check(ComposerProbe.sent([.block(t)]) == t + "\n", "a collapsed block sends its text, and is a line of its own")
        check(ComposerProbe.sent([.type("Compare: "), .block(t), .type("and why?")]) == "Compare: \n" + t + "\nand why?", "a block between typed text sends its text on lines of its own, as the box shows it")
        check(ComposerProbe.sent([.block(t), .open(0), .edit(0, "edited\ntext")]) == "edited\ntext\n" && ComposerProbe.sent([.block(t), .open(0), .edit(0, "edited"), .fold(0), .type("!")]) == "edited\n!", "an opened block's edits are what's sent, and folding keeps them")
        check(ComposerProbe.sent([.block(t), .type("\n"), .block(u)]) == t + "\n\n" + u + "\n" && ComposerProbe.sent([.block(t), .block(u), .type("x")]) == t + "\n" + u + "\nx", "two blocks, in order")
    }

    chatChipChecks()
}
