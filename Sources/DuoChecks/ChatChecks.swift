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
}
