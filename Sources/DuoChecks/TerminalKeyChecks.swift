import AppKit
import DuoKit

/// GitHub #4 (ENH-67, LR-16): ⇧↩ is a soft newline when Claude hasn't asked for the kitty keyboard
/// protocol (2.1.219), ⌘⌫ deletes to the line start, and plain Return is never remapped.
@MainActor func terminalKeyChecks() throws {
    print("terminal keys: ⇧↩ and ⌘⌫ (GitHub #4, ENH-67)")
    typealias K = TerminalKeys
    check(K.bytes(keyCode: 36, modifiers: [.shift], enhanced: false) == [0x1b, 0x0d], "⇧↩ sends ESC CR without the kitty protocol (2.1.219)")
    check(K.bytes(keyCode: 36, modifiers: [.shift], enhanced: true) == nil, "⇧↩ is left to SwiftTerm's Shift+Enter report with the protocol on")
    check(K.bytes(keyCode: 36, modifiers: [], enhanced: false) == nil, "plain Return is never remapped (LR-16)")
    check(K.bytes(keyCode: 36, modifiers: [], enhanced: true) == nil, "plain Return is never remapped with the protocol on")
    check(K.bytes(keyCode: 36, modifiers: [.command], enhanced: false) == [0x0d], "⌘↩ sends CR without the kitty protocol (DL-241; SwiftTerm sends nothing)")
    check(K.bytes(keyCode: 36, modifiers: [.command], enhanced: true) == nil, "⌘↩ is left to SwiftTerm's Super+Enter report with the protocol on")
    check(K.bytes(keyCode: 36, modifiers: [.shift, .option], enhanced: false) == nil, "⌥⇧↩ is not ⇧↩")
    check(K.bytes(keyCode: 51, modifiers: [.command], enhanced: false) == [0x15], "⌘⌫ sends ^U")
    check(K.bytes(keyCode: 51, modifiers: [.command], enhanced: true) == [0x15], "⌘⌫ sends ^U with the protocol on")
    check(K.bytes(keyCode: 51, modifiers: [.option], enhanced: false) == nil, "⌥⌫ is SwiftTerm's (ESC DEL)")
    check(K.bytes(keyCode: 51, modifiers: [], enhanced: false) == nil, "plain Delete is untouched")

    let v = GuardedTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    check(v.keyboardEnhancementFlags.isEmpty, "a fresh terminal has no keyboard-enhancement flags")
    v.feed(text: "\u{1b}[>1u")
    check(!v.keyboardEnhancementFlags.isEmpty, "a program pushing the kitty flags (CSI > 1 u) turns them on")
}
