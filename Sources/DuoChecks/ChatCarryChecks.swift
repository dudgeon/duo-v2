import DuoControl
import DuoKit
import Foundation

// ENH-292, F-485: the composer's unsent words follow the session into the terminal, by hand or by a fallback, and come
// back to the composer on returning. A scripted TUI on 2.1.284's idle screen plays `duo2 compose`'s part. Text is invented.

@MainActor func chatCarryChecks() throws {
    print("chat mode: the composer's words carried into Claude's prompt on leaving chat (ENH-292, F-485)")
    let idle = spikeScreen("tour-2.1.284/01-markdown.txt")
    func screen(_ p: String) -> String {
        idle.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) == "❯" ? "❯\u{a0}" + p : $0 }.joined(separator: "\n")
    }
    let question = spikeScreen("tour-2.1.291/05-multi.txt")

    /// A chat on a scripted TUI whose prompt holds `prompt`. `editor`: Ctrl+G hands over (2.1.269 on); else paste mode.
    func rig(prompt: String = "", editor: Bool = true) -> (ChatSession, FakeTUI, () -> String, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-carry-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var held = prompt
        let tui = FakeTUI(screen(prompt))
        let c = ChatSession(key: "carry-\(UUID().uuidString.prefix(6))", mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion(editor ? "2.1.311" : "2.1.219")
        c.attach(tui)
        if editor { c.composeDir = dir }
        tui.react = { [key = c.key] k, t in
            if k == ChatKey.ctrlG.bytes {
                // As duo2 compose does: a peek copies the prompt out; a hand-over replaces it only over the basis it names.
                let hf = ChatCompose.handoverFile(dir, key)
                guard let data = try? Data(contentsOf: hf), let h = try? JSONDecoder().decode(ChatCompose.Handover.self, from: data) else { return }
                try? FileManager.default.removeItem(at: hf)
                if h.peek { try? held.write(to: ChatCompose.peekFile(dir, key), atomically: true, encoding: .utf8) }
                else if ChatCompose.same(held, h.basis) { held = h.text }
                else { try? held.write(to: ChatCompose.refusedFile(dir, key), atomically: true, encoding: .utf8) }
                t.show(screen(held))
            } else if k.hasPrefix("\u{1b}[200~") {
                held += k.replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: "")
                t.show(screen(held))
            } else if k == " " {
                held += " "; t.show(screen(held))
            } else if k == ChatKey.backspace.bytes {
                held = String(held.dropLast()); t.show(screen(held))
            }
        }
        _ = c.reread()
        return (c, tui, { held }, dir)
    }
    func settle(_ c: ChatSession, _ until: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(4)
        while Date() < end, !until() { spin(0.05) }
        spin(0.2)
    }
    func returns(_ tui: FakeTUI) -> Int { tui.keys.filter { $0 == "\r" }.count }

    // Terminal chosen by hand (the toggle, its key, duo2 session chat off): the words go into Claude's empty prompt.
    do {
        let (c, tui, prompt, dir) = rig()
        c.ui.composer = "line one of a draft\nand its second line"
        c.mode = .terminal
        settle(c) { prompt() == "line one of a draft\nand its second line" }
        check(prompt() == "line one of a draft\nand its second line" && c.ui.composer.isEmpty && returns(tui) == 0,
              "Terminal chosen: the draft, both lines, is in Claude's prompt through Ctrl+G; no Return; the composer let go (\(prompt().debugDescription))")
        tui.keys = []
        c.mode = .terminal
        settle(c)
        check(tui.keys.isEmpty, "choosing Terminal again carries nothing twice")
        // Back to chat: the composer opens on Claude's prompt, with an edit made in the terminal.
        tui.react?("\u{1b}[200~ (edited)\u{1b}[201~", tui)
        c.mode = .chat
        settle(c) { !c.ui.composer.isEmpty }
        check(c.ui.composer == "line one of a draft\nand its second line (edited)" && c.ui.composerBasis == c.ui.composer,
              "back in chat the composer holds Claude's prompt again, the terminal's edit included (\(c.ui.composer.debugDescription))")
        try? FileManager.default.removeItem(at: dir)
    }

    // A fallback: the same, and the bar still says why.
    do {
        let (c, tui, prompt, dir) = rig()
        c.ui.composer = "dictated words, mid-sentence"
        c.fallBack(.automatic("Chat mode can’t show this screen, so here’s the terminal."), rule: "unknown-screen")
        settle(c) { prompt() == "dictated words, mid-sentence" }
        check(prompt() == "dictated words, mid-sentence" && returns(tui) == 0 && c.fallback != nil, "a fallback carries the words, no Return")
        try? FileManager.default.removeItem(at: dir)
    }

    // Claude's prompt already holds words chat didn't show: they stay, ahead of the composer's.
    do {
        let (c, _, prompt, dir) = rig(prompt: "typed in the terminal earlier")
        c.ui.composer = "and the composer's words"
        c.mode = .terminal
        settle(c) { prompt().contains("composer") }
        check(prompt() == "typed in the terminal earlier and the composer's words", "a prompt holding other words keeps them, the composer's after (\(prompt().debugDescription))")
        try? FileManager.default.removeItem(at: dir)
    }

    // The composer opened on Claude's prompt and edited it: its version replaces the prompt.
    do {
        let (c, _, prompt, dir) = rig(prompt: "first draft")
        c.ui.composerBasis = "first draft"
        c.ui.composer = "first draft, finished in chat"
        c.mode = .terminal
        settle(c) { prompt().contains("finished") }
        check(prompt() == "first draft, finished in chat", "an edit of Claude's own prompt replaces it, nothing doubled (\(prompt().debugDescription))")
        try? FileManager.default.removeItem(at: dir)
    }

    // A question up at the switch: nothing is typed into it; the words go in when the prompt is back.
    do {
        let (c, tui, prompt, dir) = rig()
        c.ui.composer = "held through a question"
        tui.text = question
        _ = c.reread()
        tui.keys = []
        c.mode = .terminal
        settle(c)
        check(tui.keys.isEmpty && c.ui.composer == "held through a question", "a question on screen: no key reaches it, the words stay in the composer")
        tui.show(screen(""))
        settle(c) { prompt() == "held through a question" }
        check(prompt() == "held through a question" && returns(tui) == 0, "the prompt back: the words go in then (\(prompt().debugDescription))")
        try? FileManager.default.removeItem(at: dir)
    }

    // A refused send (Claude's prompt changed under chat, F-449) falls back: the words are kept, the prompt's ahead.
    do {
        let (c, tui, prompt, dir) = rig(prompt: "words chat never saw")
        c.ui.composerBasis = ""
        c.ui.composer = "a message"
        var r: ChatAnswerResult?
        Task { r = await c.send("a message") }
        settle(c) { r != nil && prompt().contains("a message") }
        check(r?.ok == false && c.fallback != nil && prompt() == "words chat never saw a message" && returns(tui) == 0,
              "a refused send: the terminal, and the words in Claude's prompt after what it held, unsent (\(prompt().debugDescription))")
        try? FileManager.default.removeItem(at: dir)
    }

    // Paste mode (below 2.1.269, as on 2.1.219): one bracketed paste, never Return.
    do {
        let (c, tui, prompt, dir) = rig(editor: false)
        c.ui.composer = "pasted on the way out"
        c.mode = .terminal
        settle(c) { prompt() == "pasted on the way out" }
        check(prompt() == "pasted on the way out" && tui.keys.contains("\u{1b}[200~pasted on the way out\u{1b}[201~") && returns(tui) == 0,
              "paste mode: a bracketed paste into the empty prompt, no Return (\(tui.keys.map(\.debugDescription)))")
        try? FileManager.default.removeItem(at: dir)
    }

    // Nothing in the composer: nothing sent at all.
    do {
        let (c, tui, _, dir) = rig()
        tui.keys = []
        c.mode = .terminal
        settle(c)
        check(tui.keys.isEmpty, "an empty composer sends no keys on leaving chat")
        try? FileManager.default.removeItem(at: dir)
    }

    check(ChatSession.holds("x  the words\nhere y", "the words here") && !ChatSession.holds("", "") , "a prompt that already holds the words is left alone")
}
