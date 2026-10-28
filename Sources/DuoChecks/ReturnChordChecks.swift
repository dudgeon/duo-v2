import AppKit
import DuoKit

/// DL-241: one Return-chord table for chat and terminal. What SwiftTerm sends for each chord, in the
/// two modes Claude Code leaves it in, against what Claude Code reads those bytes as (measured, F-392).
@MainActor func returnChordChecks() throws {
    print("return chords: chat composer and terminal (DL-241, F-392)")
    typealias A = ComposerReturn
    func act(_ code: UInt16, _ m: NSEvent.ModifierFlags, _ c: Character? = nil) -> A? { A.action(keyCode: code, modifiers: m, charBeforeCaret: c) }
    for code: UInt16 in [36, 76] {
        let k = code == 76 ? "keypad " : ""
        check(act(code, []) == .send, "\(k)↩ sends")
        check(act(code, [], "a") == .send, "\(k)↩ after other text sends")
        check(act(code, [], "\\") == .backslashNewline, "\(k)↩ after a backslash replaces it with a new line")
        check(act(code, [.shift], "\\") == .newline, "\(k)⇧↩ after a backslash is a plain new line")
        check(act(code, [.shift]) == .newline, "\(k)⇧↩ is a new line")
        check(act(code, [.option]) == .newline, "\(k)⌥↩ is a new line")
        check(act(code, [.shift, .option]) == .newline, "\(k)⇧⌥↩ is a new line")
        check(act(code, [.command]) == .send, "\(k)⌘↩ sends")
        check(act(code, [.control]) == .sendNow, "\(k)⌃↩ sends now")
        check(act(code, [.capsLock]) == .send, "\(k)↩ with caps lock only sends")
    }
    check(act(0, []) == nil && act(48, [.shift]) == nil, "other keys are not Return chords")

    check(!ChatSession.hasSendNow(cliVersion: nil), "send now needs a known version")
    for (v, want) in [("2.1.219", false), ("2.1.274", false), ("2.1.275", true), ("2.1.284", true), ("2.1.311", true), ("2.2.0", true)] {
        check(ChatSession.hasSendNow(cliVersion: v) == want, "send now on Claude Code \(v): \(want)")
    }
    check(ChatKey.sendNow.bytes == "\u{18}\u{13}", "send now is Ctrl+X Ctrl+S")

    // What Claude Code reads each byte string as, measured on 2.1.219 and on 2.1.284 / 2.1.311 (F-392).
    enum Read: String { case send, newline, ignored, sendNow = "send now", nothing }
    func reads(_ bytes: [UInt8], modern: Bool) -> Read {
        switch bytes {
        case [0x0d]: return .send
        case [0x1b, 0x0d], [0x0a]: return .newline
        case Array("\u{1b}[13;2u".utf8), Array("\u{1b}[13;3u".utf8), Array("\u{1b}[106;5u".utf8): return .newline
        case Array("\u{1b}[13;5u".utf8): return modern ? .sendNow : .ignored
        case Array("\u{1b}[13;9u".utf8): return .send
        case [0x18, 0x13]: return modern ? .sendNow : .nothing
        default: return .nothing
        }
    }
    // SwiftTerm hands a key's bytes to the pty (not to a delegate), so each terminal runs a raw `cat` into a file.
    var sinks: [ObjectIdentifier: String] = [:]
    func sent(_ v: GuardedTerminalView, _ code: UInt16, _ m: NSEvent.ModifierFlags, _ chars: String) -> [UInt8] {
        let path = sinks[ObjectIdentifier(v)]!
        let before = (try? Data(contentsOf: URL(fileURLWithPath: path)))?.count ?? 0
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: m, timestamp: 0, windowNumber: 0, context: nil,
                                 characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        if let b = TerminalKeys.bytes(keyCode: code, modifiers: m, enhanced: !v.keyboardEnhancementFlags.isEmpty) { v.send(b) } else { v.keyDown(with: e) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return Array(((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()).dropFirst(before))
    }
    func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
    let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    // Never shown or ordered front: AppKit's key handling needs a window to interpret events in.
    func terminal() -> GuardedTerminalView {
        let v = GuardedTerminalView(frame: frame)
        let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        w.isReleasedWhenClosed = false
        w.contentView = v
        _ = w.makeFirstResponder(v)
        windows.append(w)
        let path = NSTemporaryDirectory() + "duo-return-chords-\(UUID().uuidString.prefix(8))"
        v.startProcess(executable: "/bin/sh", args: ["-c", "stty raw -echo; exec cat > \(path)"], environment: nil, execName: nil)
        sinks[ObjectIdentifier(v)] = path
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        return v
    }
    var windows: [NSWindow] = []
    defer { windows.removeAll(); for (_, p) in sinks { try? FileManager.default.removeItem(atPath: p) } }
    let legacy = terminal()   // 2.1.219 never pushes the kitty flags
    let kitty = terminal()    // 2.1.284 and 2.1.311 push CSI > 5 u
    kitty.feed(text: "\u{1b}[>5u")
    check(legacy.keyboardEnhancementFlags.isEmpty && !kitty.keyboardEnhancementFlags.isEmpty, "the two terminals are in the two modes")
    let esc = "\u{1b}"
    // chord, key code, modifiers, characters, legacy bytes, kitty bytes, what Claude Code does
    let table: [(String, UInt16, NSEvent.ModifierFlags, String, [UInt8], [UInt8], Read)] = [
        ("↩", 36, [], "\r", [0x0d], [0x0d], .send),
        ("⇧↩", 36, [.shift], "\r", [0x1b, 0x0d], Array("\(esc)[13;2u".utf8), .newline),
        ("⌥↩", 36, [.option], "\r", [0x1b, 0x0d], Array("\(esc)[13;3u".utf8), .newline),
        ("⌃↩", 36, [.control], "\r", [0x0d], Array("\(esc)[13;5u".utf8), .sendNow),
        ("⌘↩", 36, [.command], "\r", [0x0d], Array("\(esc)[13;9u".utf8), .send),
        ("⌃J", 38, [.control], "\n", [0x0a], Array("\(esc)[106;5u".utf8), .newline),
    ]
    for (name, code, m, chars, old, new, meaning) in table {
        let a = sent(legacy, code, m, chars), b = sent(kitty, code, m, chars)
        check(a == old, "\(name) without the kitty protocol sends \(hex(old)) (got \(hex(a)))")
        check(b == new, "\(name) with the kitty protocol sends \(hex(new)) (got \(hex(b)))")
        // 2.1.219 has no send now: ⌃↩ is a plain CR there, which sends.
        let want219: Read = name == "⌃↩" ? .send : meaning
        check(reads(a, modern: false) == want219, "\(name) on 2.1.219 is read as \(want219.rawValue)")
        check(reads(b, modern: true) == meaning, "\(name) on 2.1.284 / 2.1.311 is read as \(meaning.rawValue)")
    }
    check(reads(Array("\(esc)[13;5u".utf8), modern: false) == .ignored && reads([0x18, 0x13], modern: false) == .nothing, "2.1.219 ignores CSI 13;5u and Ctrl+X Ctrl+S")
    check(reads([0x18, 0x13], modern: true) == .sendNow, "2.1.284 and later read Ctrl+X Ctrl+S as send now")
}
