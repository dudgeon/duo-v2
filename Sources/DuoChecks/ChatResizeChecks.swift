import DuoControl
import DuoKit
import Foundation
import SwiftTerm

// F-449, Geoff's voice test (Duo Dev, 2.1.311): a refused hand-over put the terminal up, and the terminal, last drawn
// wider while chat showed, narrowed to the pane. SwiftTerm keeps a row's cells past the new width, so the screen chat
// judged held both widths, read "fewer than two rules", and was unknown. Text here is invented.

@MainActor func chatResizeChecks() throws {
    print("chat mode: a terminal that narrows, and a hand-over onto a prompt that emptied (F-449)")

    // SwiftTerm itself: narrowed from 87 to 42 columns, a row still holds what was past column 42.
    do {
        var o = TerminalOptions.default
        o.cols = 87; o.rows = 6
        let t = Terminal(delegate: HeadlessTUI.Sink.shared, options: o)
        // The alternate screen, where a full-screen TUI draws: it has no scrollback, so SwiftTerm never reflows (or trims) it.
        t.feed(text: "\u{1b}[?1049h" + String(repeating: "─", count: 87) + "\r\n" + "A line of text drawn when the pane was wide, long enough to pass column forty-two.\r\n")
        t.resize(cols: 42, rows: 6)
        // The cells past the width, read off the row itself: what the view's row text (`end: -1`) hands chat.
        let raw = (0..<2).map { r -> String in
            guard let line = t.getLine(row: r) else { return "" }
            return String((0..<line.count).map { line[$0].getCharacter() }).replacingOccurrences(of: "\u{0}", with: " ").chatTrimmedEnd
        }
        check(raw[0].count > 42 && raw[1].count > 42, "SwiftTerm narrowed to 42 keeps the cells past it on the alternate screen (\(raw.map(\.count)))")
        let cut = raw.map { ChatScreenReader.clip($0, cols: 42) }
        check(cut.allSatisfy { $0.count <= 42 } && cut[0] == String(repeating: "─", count: 42), "clipped, each row is what the screen shows")
        check(ChatScreenReader.clip("界界界界", cols: 5) == "界界" && ChatScreenReader.clip("ab", cols: 42) == "ab", "a wide glyph counts as two cells")
    }

    // The reader on such a screen: 2.1.284's idle prompt at 42 columns, with an earlier, wider drawing's tails.
    do {
        let wide = "This is old text from the wider drawing, still in the buffer"
        var rows: [String] = []
        for l in spikeScreen("tour-2.1.284/01-markdown.txt").components(separatedBy: "\n").suffix(14) {
            let narrow = String(l.prefix(42))
            rows.append(narrow.isEmpty ? "" : narrow.padding(toLength: 42, withPad: " ", startingAt: 0) + wide)
        }
        // The box: its top rule with old text after it, the prompt, its bottom rule drawn wider before.
        let box = rows.lastIndex { $0.hasPrefix("❯") } ?? rows.count - 2
        rows[box - 1] = String(repeating: "─", count: 42) + "recaps from the wide drawing)…"
        rows[box + 1] = String(repeating: "─", count: 87)
        let raw = ChatScreenReader.read(lines: rows, cols: 42)
        let cut = ChatScreenReader.read(lines: rows.map { ChatScreenReader.clip($0, cols: 42) }, cols: 42)
        check(raw.kind == .unknown, "read whole, the two widths make an unknown screen (the field's verdict: \(raw.kind))")
        check(cut.kind == .idle && cut.input == "", "clipped to the terminal's width it is Claude's idle prompt (\(cut.kind))")
    }

    // The hand-over: chat expected words Claude's prompt no longer held, and it is empty. Nothing is there to keep, so the
    // text goes onto it (no fallback); a prompt holding other words is still never overwritten.
    func handover(held: String) -> (ChatSession, FakeTUI, ChatAnswerResult?) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "duo-handover-\(UUID().uuidString.prefix(6))")
        let idle = spikeScreen("tour-2.1.284/01-markdown.txt")
        // The prompt row is `❯`, a no-break space and padding: it holds `p` instead.
        func prompt(_ p: String) -> String {
            idle.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) == "❯" ? "❯\u{a0}" + p : $0 }.joined(separator: "\n")
        }
        let tui = FakeTUI(idle)
        let c = ChatSession(key: "handover-\(UUID().uuidString.prefix(6))", mode: .chat)
        c.persistsFallbackLog = false
        c.setVersion("2.1.311")
        c.attach(tui)
        c.composeDir = dir
        c.ui.composerBasis = "words chat last saw in Claude's prompt"
        var turns = 0
        tui.react = { [key = c.key] k, t in
            guard k == ChatKey.ctrlG.bytes else { return }
            turns += 1
            // As duo2 compose does: the hand-over file is used once; Claude's prompt is what the TUI hands the editor.
            let hf = ChatCompose.handoverFile(dir, key)
            guard let data = try? Data(contentsOf: hf), let h = try? JSONDecoder().decode(ChatCompose.Handover.self, from: data) else { return }
            try? FileManager.default.removeItem(at: hf)
            if ChatCompose.same(held, h.basis) {
                t.show(prompt(h.text))
            } else {
                try? held.write(to: ChatCompose.refusedFile(dir, key), atomically: true, encoding: .utf8)
                t.show(prompt(held))
            }
        }
        var r: ChatAnswerResult?
        Task { r = await c.send("try the switch once more") }
        let end = Date().addingTimeInterval(8)
        while r == nil, Date() < end { spin(0.05) }
        try? FileManager.default.removeItem(at: dir)
        return (c, tui, r)
    }
    do {
        let (c, tui, r) = handover(held: "")
        let gs = tui.keys.filter { $0 == ChatKey.ctrlG.bytes }.count
        check(r?.ok == true && gs == 2 && c.fallback == nil && tui.keys.last == ChatKey.enter.bytes,
              "Claude's prompt emptied since chat read it: handed over again onto the empty prompt and sent, no terminal (\(r?.why ?? "ok"), Ctrl+G ×\(gs))")
        let (k, ktui, kr) = handover(held: "words typed in the terminal")
        check(kr?.ok == false && ktui.keys.filter { $0 == ChatKey.ctrlG.bytes }.count == 1 && kr?.why?.contains("words typed in the terminal") == true && k.fallback != nil,
              "a prompt holding other words is never overwritten: refused once, as before")
    }
}

private extension String {
    var chatTrimmedEnd: String { replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
}
