import DuoKit
import Foundation

// The model chip and the effort chip (DL-168, chat-model-chip-handoff): the model's name from each source,
// the effort from the screen, "Switch model?" as a card, 2.1.219's /effort, and the click's checks.

/// A screen captured for the chip's research (Claude Code 2.1.296 and 2.1.219).
func chipScreen(_ name: String) -> String {
    (try? String(contentsOf: repoRoot().appending(path: "docs/research/chat-model-chip-screens/\(name)"), encoding: .utf8)) ?? ""
}

/// A captured idle screen with `text` typed at its prompt (Claude Code draws ❯ and a no-break space).
func chipPrompt(_ text: String, screen: String = "idle-2.1.296.txt") -> String {
    chipScreen(screen).components(separatedBy: "\n").map { $0.hasPrefix("❯") ? "❯\u{a0}" + text : $0 }.joined(separator: "\n")
}

@MainActor func chatChipChecks() {
    print("chat mode: the model chip and the effort chip (DL-168)")

    // The name: an id becomes Claude Code's own; anything else shows as given.
    check(ChatModelName.display("claude-opus-5-5") == "Opus 5.5" && ChatModelName.display("claude-sonnet-5") == "Sonnet 5"
          && ChatModelName.display("claude-haiku-4-5-20251001") == "Haiku 4.5" && ChatModelName.display("claude-fable-5-1") == "Fable 5.1",
          "ids become names: Opus 5.5, Sonnet 5, Haiku 4.5, Fable 5.1")
    check(ChatModelName.display("my-gateway/custom-model") == "my-gateway/custom-model" && ChatModelName.display("claude-3-5-sonnet-20241022") == "claude-3-5-sonnet-20241022"
          && ChatModelName.display("Sonnet 5.5") == "Sonnet 5.5" && ChatModelName.display("claude-opus-5-5[1m]") == "Opus 5.5" && ChatModelName.display("<synthetic>") == nil,
          "an id that doesn't fit, or a name, shows as given; a [1m] suffix and a synthetic marker don't count")

    // The /model result line: backticks, ANSI bold, "Kept model as".
    check(ChatModelName.fromResult("Set model to `Sonnet 5.5` for this session only") == "Sonnet 5.5", "2.1.296's result line: backticks off")
    check(ChatModelName.fromResult("Set model to \u{1B}[1mSonnet 5\u{1B}[22m for this session only") == "Sonnet 5", "2.1.219's: ANSI bold off")
    check(ChatModelName.fromResult("Set model to \u{1B}[1mclaude-haiku-5-5\u{1B}[22m") == "Haiku 5.5" && ChatModelName.fromResult("Kept model as `Haiku 5.5`") == "Haiku 5.5",
          "an id in the line becomes a name; Kept model as … reads too")
    check(ChatModelName.fromResult("Set model to Opus 5.5 for this session only") == "Opus 5.5" && ChatModelName.fromResult("Session renamed to: notes") == nil, "no marks: the name runs to “for this session”; other output isn't a model")

    // Newest wins, from the user record, the system record, a reply and SessionStart.
    let log = ChatLog()
    ChatIngest.hook(["hook_event_name": "SessionStart", "model": "claude-opus-5-5"], at: nil, into: log)
    check(log.model == "Opus 5.5", "SessionStart names a new session's model")
    ChatIngest.record(["type": "user", "message": ["role": "user", "content": "<local-command-stdout>Set model to `Sonnet 5.5` for this session only</local-command-stdout>"]], into: log, lastDeclined: nil)
    check(log.model == "Sonnet 5.5", "a /model result in a user record moves the chip before any reply")
    ChatIngest.record(["type": "assistant", "message": ["model": "claude-sonnet-5-5", "content": [["type": "text", "text": "ok"]]]], into: log, lastDeclined: nil)
    check(log.model == "Sonnet 5.5", "a reply of the same model changes nothing")
    ChatIngest.record(["type": "system", "subtype": "local_command", "content": "<local-command-stdout>Kept model as \u{1B}[1mHaiku 4.5\u{1B}[22m</local-command-stdout>"], into: log, lastDeclined: nil)
    check(log.model == "Haiku 4.5", "a result in a system/local_command record counts too")
    ChatIngest.hook(["hook_event_name": "SessionStart", "model": "claude-opus-5-5"], at: nil, into: log)
    check(log.model == "Haiku 4.5", "a SessionStart after the transcript (a resume) doesn't override it")
    ChatIngest.record(["type": "assistant", "message": ["model": "claude-fable-5-1", "content": []]], into: log, lastDeclined: nil)
    check(log.model == "Fable 5.1", "the newest reply wins")

    // The effort, read from the screen.
    let i296 = ChatScreenReader.read(chipScreen("idle-2.1.296.txt")), i219 = ChatScreenReader.read(chipScreen("idle-2.1.219.txt"))
    check(i296.kind == .idle && i296.effort == ChatEffort(glyph: "◐", word: "medium"), "2.1.296's idle screen: ◐ medium (\(i296.effort?.text ?? "-"))")
    check(i219.kind == .idle && i219.effort == ChatEffort(glyph: "●", word: "high"), "2.1.219's idle screen: ● high at the footer's right end (\(i219.effort?.text ?? "-"))")
    check(ChatScreenReader.read(spikeScreen("tour-2.1.291/01-markdown.txt")).effort == nil, "a screen that draws no effort has no chip")

    // Switch model?, on both versions.
    for v in ["2.1.296", "2.1.219"] {
        let s = ChatScreenReader.read(chipScreen("switch-model-\(v).txt"))
        guard let p = s.picker, s.kind == .picker, p.kind == .confirm else { check(false, "\(v): Switch model? is a card (\(s.kind))"); continue }
        let to = v == "2.1.296" ? "Sonnet 5.5" : "Sonnet 5"
        check(p.title == "Switch model?" && p.heading == "Your next response will be slower and use more tokens"
              && p.description == "This conversation is cached for the current model. Switching to \(to) means the full history gets re-read on your next message.",
              "\(v): its heading, then its wrapped lines joined (\(p.description.prefix(50))…)")
        check(p.rows.map(\.n) == [1, 2] && p.rows.map(\.name) == ["Yes, switch to \(to)", "No, go back"] && p.rows[0].cursor && ChatScreenReader.wellFormed(s),
              "\(v): two numbered rows in Claude Code's words; the TUI's ❯ is read, never drawn (\(p.rows.map(\.name)))")
    }

    // /effort on both versions.
    let e296 = ChatScreenReader.read(chipScreen("effort-2.1.296.txt")), e219 = ChatScreenReader.read(chipScreen("effort-2.1.219.txt"))
    check(e296.picker?.levels == ["low", "medium", "high", "xhigh", "max"] && e296.picker?.level == 1 && e296.picker?.sessionOnly == true && ChatScreenReader.wellFormed(e296),
          "2.1.296's /effort: five levels (not “Tab to toggle”), medium, with This Session Only (\(e296.picker?.levels ?? []))")
    check(e219.picker?.levels == ["low", "medium", "high", "xhigh", "max"] && e219.picker?.level == 2 && e219.picker?.sessionOnly == false && ChatScreenReader.wellFormed(e219),
          "2.1.219's /effort: low to max without ultracode, no session-only key (\(e219.picker?.levels ?? []) \(e219.picker?.level ?? -1))")

    // The click: only at an idle prompt that is empty, with the echo checked; never a bubble.
    let tui = FakeTUI(chipScreen("idle-2.1.296.txt"))
    var typed = ""
    tui.react = { k, t in
        if k.hasPrefix("\u{1b}[200~") {
            typed = k.replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: "")
            t.show(chipPrompt(typed))
        } else if k == ChatKey.enter.bytes, !typed.isEmpty {
            t.show(spikeScreen("slash-2.1.292/model.txt"))
        }
    }
    let chat = ChatSession(key: "chip", mode: .chat)
    chat.setVersion("2.1.296")
    chat.attach(tui)
    var r: ChatAnswerResult?
    Task { r = await chat.openPicker(.model) }
    spin(1.0)
    check(r?.ok == true && tui.keys.first == "\u{1b}[200~/model\u{1b}[201~" && tui.keys.last == ChatKey.enter.bytes && chat.log.items.isEmpty,
          "a click sends /model, checks the echo, presses Return, and leaves no bubble (\(tui.keys.count) sends)")
    check(chat.pickerUp && chat.screen.picker?.kind == .model, "and DL-143's card is up")

    let held = FakeTUI(chipPrompt("hello"))
    let c2 = ChatSession(key: "chip2", mode: .chat)
    c2.setVersion("2.1.296")
    c2.attach(held)
    var r2: ChatAnswerResult?
    Task { r2 = await c2.openPicker(.model) }
    spin(0.6)
    check(r2?.ok == false && held.keys.isEmpty, "text in Claude's prompt: nothing is sent (\(r2?.why ?? "-"))")

    let busy = FakeTUI(chipScreen("idle-2.1.296.txt").replacingOccurrences(of: "auto mode on (shift+tab to cycle)", with: "esc to interrupt"))
    let c3 = ChatSession(key: "chip3", mode: .chat)
    c3.setVersion("2.1.296")
    c3.attach(busy)
    var r3: ChatAnswerResult?
    Task { r3 = await c3.openPicker(.effort) }
    spin(0.4)
    check(c3.screen.kind == .busy && r3?.ok == false && busy.keys.isEmpty && c3.screen.effort?.word == "medium" && c3.effort?.word == "medium",
          "while Claude works the chips wait: nothing is sent, and the effort is kept (\(r3?.why ?? "-"))")

    // Switch model?'s number answers, after the check; the same question must still be up.
    let q = FakeTUI(chipScreen("switch-model-2.1.296.txt"))
    q.react = { k, t in if k == "1" { t.show(chipScreen("idle-2.1.296.txt")) } }
    let c4 = ChatSession(key: "chip4", mode: .chat)
    c4.setVersion("2.1.296")
    c4.attach(q)
    check(c4.pickerUp && c4.screen.picker?.kind == .confirm, "Switch model? is up as a card, not the terminal")
    var r4: ChatAnswerResult?
    Task { r4 = await c4.confirmAnswer(1) }
    spin(0.6)
    check(r4?.ok == true && q.keys == ["1"], "1 answers it with its own key and no Return when the TUI took it (\(q.keys))")
    var r5: ChatAnswerResult?
    Task { r5 = await c4.confirmAnswer(1) }
    spin(0.4)
    check(r5?.ok == false && q.keys == ["1"], "once it has gone, nothing more is sent")
}
