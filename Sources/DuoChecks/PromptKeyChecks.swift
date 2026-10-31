import AppKit
import DuoKit
import SwiftTerm

/// DL-274: Mac editing keys in Claude's prompt (strategy 1 of docs/design/terminal-selection-study) and clean copies.
/// The screens are Claude Code's as measured in a pty on 2.1.284 and 2.1.311 (F-504); the bytes are read back from a
/// raw `cat` in a real terminal view, as `return-chords` does.
@MainActor func promptKeyChecks() throws {
    print("prompt keys: ⌘↑ ⌘↓ ⌥⌦ ⌘Z in Claude's prompt, and clean copies (DL-274, F-504)")
    typealias K = PromptKey
    check(K.chord(keyCode: 126, modifiers: [.command]) == .toStart, "⌘↑ is the prompt's start")
    check(K.chord(keyCode: 125, modifiers: [.command]) == .toEnd, "⌘↓ is the prompt's end")
    check(K.chord(keyCode: 117, modifiers: [.option]) == .deleteWordForward, "⌥⌦ (⌥fn⌫) deletes a word forward")
    check(K.chord(keyCode: 6, modifiers: [.command]) == .undo, "⌘Z is Claude's undo")
    check(K.chord(keyCode: 126, modifiers: [.command, .function, .numericPad]) == .toStart, "an arrow's own fn and keypad flags don't matter")
    for (code, m, what) in [(UInt16(126), NSEvent.ModifierFlags([.command, .shift]), "⇧⌘↑"), (126, [.command, .option], "⌥⌘↑"), (123, [.command], "⌘←"),
                            (6, [.command, .shift], "⇧⌘Z"), (117, [], "⌦"), (51, [.option], "⌥⌫"), (126, [], "↑")] {
        check(K.chord(keyCode: code, modifiers: m) == nil, "\(what) is left as it is")
    }

    // Screens as Claude draws them at 60 × 30 (the probe's), viewport rows top to bottom.
    let rule = String(repeating: "─", count: 60)
    func screen(_ box: [String], rows: Int = 30, below: [String] = ["  ⏵⏵ auto mode on (shift+tab to cycle)"]) -> [String] {
        let body = ["", "✻ Welcome", "", rule] + box + [rule] + below
        return Array(repeating: "", count: max(0, rows - body.count)) + body
    }
    let three = ["❯ alpha beta gamma", "  delta epsilon zeta", "  eta theta iota"]
    let s3 = screen(three)
    let top = s3.firstIndex(of: "❯ alpha beta gamma")!
    let b = PromptBox.find(rows: s3, cursor: (top + 2, 16))
    check(b?.firstRow == top && b?.lastRow == top + 2 && b?.above == 2 && b?.below == 0, "the box's rows and the caret's place in them")
    check(PromptBox.find(rows: s3, cursor: (top - 2, 0)) == nil, "no box when the caret isn't in it")
    var asked = s3
    asked[top - 2] = "❯ 1. Yes"
    check(PromptBox.find(rows: asked, cursor: (top, 4)) == nil, "no box while a question is up (arrows stay Claude's)")
    // Claude's own pickers, recorded in the pty (F-504): no box, so ⌘↑ does nothing and ⌘↓ ⌥⌦ go on as before.
    let fx = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/prompt-keys")
    for name in ["model-2.1.311", "effort-2.1.311", "model-2.1.284", "effort-2.1.284"] {
        let rows = ((try? String(contentsOf: fx.appendingPathComponent(name + ".txt"), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        check(rows.count > 20 && (0..<rows.count).allSatisfy { r in PromptBox.find(rows: rows, cursor: (r, 4)) == nil },
              "\(name)'s picker: no input box, wherever the cursor is")
    }
    check(b?.full == false, "three rows of 30 is not a full box")
    let ten = (1...10).map { $0 == 1 ? "❯ line \($0)" : "  line \($0)" }
    let s10 = screen(ten)
    check(PromptBox.find(rows: s10, cursor: (s10.firstIndex(of: "❯ line 1")! + 9, 9))?.full == true, "ten rows of 30 is full (it scrolls past rows/2 - 5)")
    let s5at20 = screen(Array(ten.prefix(5)), rows: 20)
    check(PromptBox.find(rows: s5at20, cursor: (s5at20.firstIndex(of: "❯ line 1")!, 2))?.full == true, "five rows of 20 is full")

    let up: [UInt8] = [0x1b, 0x5b, 0x41], down: [UInt8] = [0x1b, 0x5b, 0x42]
    typealias P = PromptKeys
    check(P.bytes(.toStart, box: b, enhanced: true) == up + up + [0x01], "⌘↑: ↑ to the first row, never past it, then ⌃A")
    let b0 = PromptBox.find(rows: s3, cursor: (top, 7))
    check(P.bytes(.toStart, box: b0, enhanced: true) == [0x01], "⌘↑ on the first row: ⌃A only (↑ there recalls the last prompt)")
    check(P.bytes(.toEnd, box: b0, enhanced: true) == down + down + [0x05], "⌘↓: ↓ to the last row, then ⌃E")
    check(P.bytes(.toEnd, box: b, enhanced: false) == [0x05], "⌘↓ on the last row: ⌃E only")
    check(P.bytes(.deleteWordForward, box: b, enhanced: true) == Array("\u{1b}[100;3u".utf8), "⌥⌦ is Alt+D as a CSI u report with the protocol")
    check(P.bytes(.deleteWordForward, box: b, enhanced: false) == [0x1b, 0x64], "⌥⌦ is ESC d without it (2.1.219)")
    check(P.bytes(.undo, box: b, enhanced: true) == [0x1f], "⌘Z is ⌃_, Claude's chat:undo")
    check(P.bytes(.toStart, box: nil, enhanced: true) == [], "⌘↑ with no box (a question, a picker) does nothing, and is not All Projects")
    check(P.bytes(.undo, box: nil, enhanced: true) == [], "⌘Z with no box does nothing, and is not Duo's Undo")
    check(P.bytes(.toEnd, box: nil, enhanced: true) == nil && P.bytes(.deleteWordForward, box: nil, enhanced: true) == nil,
          "⌘↓ and ⌥⌦ with no box are left as they were")

    // A full box, one probe key at a time (F-504: the box scrolls, and ↑ past the first row recalls the last prompt).
    func box(_ rows: [String], caret: Int) -> PromptBox { PromptBox.find(rows: screen(rows), cursor: (screen(rows).firstIndex(of: rows[0])! + caret, 9))! }
    let w31 = (31...40).map { "  line \($0)" }, w22 = (22...31).map { "  line \($0)" }
    func marked(_ r: [String]) -> [String] { ["❯ " + r[0].dropFirst(2)] + r.dropFirst() }
    let atTop = box(marked(w31), caret: 0)
    check(P.next(toStart: true, before: atTop, after: atTop) == .done([0x01]), "nothing changed: no more above and no history, ⌃A")
    let scrolledUp = box(marked(w22), caret: 0)
    check(P.next(toStart: true, before: atTop, after: scrolledUp) == .more([]), "the box scrolled nine rows, caret still on its first row: probe again")
    let recentred = box(marked((26...35).map { "  line \($0)" }), caret: 4)
    check(P.next(toStart: true, before: atTop, after: recentred) == .more(up + up + up + up), "scrolled and re-centred: ↑ to the box's first row again")
    let history = box(["❯ HISTORY NEWEST"], caret: 0)
    check(P.next(toStart: true, before: atTop, after: history) == .history(down), "the last prompt came up: ↓ brings the draft back, caret at its start")
    let atBottom = box(marked(w22), caret: 9)
    check(P.next(toStart: false, before: atBottom, after: atBottom) == .done([0x05]), "⌘↓ in a full box: nothing below, ⌃E")
    check(P.next(toStart: false, before: atBottom, after: box(marked(w31), caret: 5)) == .more(Array(repeating: down, count: 4).flatMap { $0 }),
          "⌘↓: scrolled down, ↓ to the box's last row again")
    check(P.next(toStart: false, before: atBottom, after: history) == .stop, "⌘↓: anything else stops, with nothing sent")
    check(P.next(toStart: true, before: atTop, after: nil) == .stop, "the box gone: stop")

    // Copies, as Claude made them in the pty (OSC 52; F-471), against the screen they came from.
    typealias C = PromptCopy
    check(C.clean("beta gamma\n  delta ep", rows: s3, cols: 60) == "beta gamma\ndelta ep", "a drag over a typed new line: the indent goes")
    check(C.clean("alpha beta gamma\n  delta epsilon zeta\n  eta theta iota", rows: s3, cols: 60) == "alpha beta gamma\ndelta epsilon zeta\neta theta iota",
          "the whole box: three typed lines")
    check(C.clean("  delta epsilon zeta", rows: s3, cols: 60) == "delta epsilon zeta", "a triple click copies a row with its indent: it goes")
    check(C.clean("epsilon", rows: s3, cols: 60) == "epsilon", "a double click is left alone")
    let long1 = "The quick brown fox jumps over the lazy dog while the band plays on, and then it keeps running past the barn, the mill and the river until the sun goes down behind the hills."
    let wrapped = ["❯ The quick brown fox jumps over the lazy dog while the", "  band plays on, and then it keeps running past the barn,",
                   "  the mill and the river until the sun goes down behind", "  the hills.", "  second line"]
    let sw = screen(wrapped)
    check(C.clean(wrapped.map { String($0.dropFirst(2)) }.enumerated().map { $0 == 0 ? $1 : "  " + $1 }.joined(separator: "\n"), rows: sw, cols: 60)
          == long1 + "\nsecond line", "a wrapped line comes back as one line, the typed new line stays")
    let url = "see https://example.com/" + String(repeating: "a", count: 120) + " end"
    let urlRows = ["❯ see https://example.com/" + String(repeating: "a", count: 32), "  " + String(repeating: "a", count: 56), "  " + String(repeating: "a", count: 32) + " end"]
    check(C.clean(urlRows.enumerated().map { $0 == 0 ? String($1.dropFirst(2)) : $1 }.joined(separator: "\n"), rows: screen(urlRows), cols: 60) == url,
          "a word longer than a row is joined with nothing between its pieces")
    let words = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
    let wordRows = ["❯ " + Array(repeating: "word", count: 11).joined(separator: " "), "  " + Array(repeating: "word", count: 11).joined(separator: " "),
                    "  " + Array(repeating: "word", count: 8).joined(separator: " ")]
    check(C.clean(wordRows.enumerated().map { $0 == 0 ? String($1.dropFirst(2)) : $1 }.joined(separator: "\n"), rows: screen(wordRows), cols: 60) == words,
          "words wrapped at the row's width get their space back")
    let cjk = ["❯ " + String(repeating: "日本語", count: 9) + "テ", "  キスト"]
    check(C.clean(String(cjk[0].dropFirst(2)) + "\n" + cjk[1], rows: screen(cjk), cols: 60) == String(repeating: "日本語", count: 9) + "テキスト",
          "wide text is measured in cells: a full row of it is a soft wrap")
    check(C.clean("Some reply text\n  that Claude wrote", rows: s3, cols: 60) == "Some reply text\n  that Claude wrote", "text that isn't the box's is left alone")
    // Q-403, the guess's known gap: a typed new line after a row the next word wouldn't have fitted on reads as a wrap.
    let nearFull = ["❯ " + Array(repeating: "word", count: 11).joined(separator: " "), "  next"]
    check(C.clean(String(nearFull[0].dropFirst(2)) + "\n" + nearFull[1], rows: screen(nearFull), cols: 60)
          == Array(repeating: "word", count: 11).joined(separator: " ") + " next", "known gap (Q-403): a typed new line after a near-full row is joined")

    // Live: a real terminal view, its bytes read back from a raw `cat` (as `return-chords`).
    let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    let path = NSTemporaryDirectory() + "duo-prompt-keys-\(UUID().uuidString.prefix(8))"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let v = GuardedTerminalView(frame: frame)
    let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)   // never shown
    w.isReleasedWhenClosed = false
    w.contentView = v
    _ = w.makeFirstResponder(v)
    v.startProcess(executable: "/bin/sh", args: ["-c", "stty raw -echo; exec cat > \(path)"], environment: nil, execName: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    let dims = v.terminalStateSnapshot().dimensions
    func draw(_ rows: [String], caret: (Int, Int)) {
        let lines = Array(rows.suffix(dims.rows)).map { String($0.prefix(dims.cols)) }
        v.feed(text: "\u{1b}[2J\u{1b}[H" + lines.joined(separator: "\r\n") + "\u{1b}[\(caret.0 + 1);\(caret.1 + 1)H")
    }
    func sent(_ body: () -> Void) -> [UInt8] {
        let before = (try? Data(contentsOf: URL(fileURLWithPath: path)))?.count ?? 0
        body()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return Array(((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()).dropFirst(before))
    }
    let live = screen(three, rows: dims.rows, below: [])
    let liveTop = live.firstIndex(of: "❯ alpha beta gamma")!
    draw(live, caret: (liveTop + 2, 16))
    check(v.promptBox()?.above == 2, "the live view finds the box and the caret")
    check(sent { _ = v.promptKey(.toStart) } == up + up + [0x01], "live: ⌘↑ writes ↑ ↑ ⌃A")
    check(sent { _ = v.promptKey(.undo) } == [0x1f], "live: ⌘Z writes ⌃_")
    draw(live, caret: (liveTop, 4))
    check(sent { _ = v.promptKey(.toEnd) } == down + down + [0x05], "live: ⌘↓ writes ↓ ↓ ⌃E")
    // Through AppKit, as a keypress arrives: the monitor sees it before any menu, only in a Claude terminal.
    func press(_ code: UInt16, _ m: NSEvent.ModifierFlags, _ ch: String) -> [UInt8] {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: m, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                 characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
        return sent { NSApp.sendEvent(e) }
    }
    let upChar = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    v.runsClaude = false
    let shellBytes = press(126, [.command, .function, .numericPad], upChar)
    check(!shellBytes.starts(with: [0x1b, 0x5b, 0x41]) && shellBytes != [0x01], "a shell's ⌘↑ is today's (SwiftTerm's own bytes)")
    v.runsClaude = true
    draw(live, caret: (liveTop + 1, 5))
    check(press(126, [.command, .function, .numericPad], upChar) == up + [0x01], "a Claude terminal's ⌘↑ through AppKit: the prompt's start")

    // OSC 52 from the program, on a private pasteboard (never the user's).
    let pb = NSPasteboard(name: NSPasteboard.Name("duo-checks-\(UUID().uuidString.prefix(8))"))
    defer { pb.releaseGlobally() }
    v.pasteboard = pb
    v.installCopyCleaning()
    draw(live, caret: (liveTop + 2, 16))
    func osc52(_ s: String) { v.feed(text: "\u{1b}]52;c;\(Data(s.utf8).base64EncodedString())\u{07}"); RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    osc52("beta gamma\n  delta ep")
    check(pb.string(forType: .string) == "beta gamma\ndelta ep", "Claude's copy of the prompt lands clean")
    pb.clearContents(); pb.setString("beta gamma\n  delta ep", forType: .string)   // pbcopy's raw copy, after it
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    check(pb.string(forType: .string) == "beta gamma\ndelta ep", "the raw copy arriving after it (pbcopy) is put back clean")
    osc52("Some reply text\n  that Claude wrote")
    check(pb.string(forType: .string) == "Some reply text\n  that Claude wrote", "a copy that isn't the prompt's is left alone")
    v.runsClaude = false
    osc52("beta gamma\n  delta ep")
    check(pb.string(forType: .string) == "beta gamma\n  delta ep", "a shell's copy is never changed")
    v.runsClaude = true
    w.close()
}
