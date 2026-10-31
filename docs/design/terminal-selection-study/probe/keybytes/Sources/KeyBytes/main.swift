import AppKit
import SwiftTerm

// What SwiftTerm (Duo's pinned commit) writes to the pty for each Mac chord, with the kitty flags off
// (2.1.219) and after CSI > 5 u (2.1.284, 2.1.311). Same method as DuoChecks `return-chords`: a raw
// `cat` in the pty, a never-shown borderless window. No main menu here, so ⌘ keys Duo's menus own
// (⌘A ⌘C ⌘X ⌘V ⌘Z) reach the view; in Duo the menu takes them first.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var windows: [NSWindow] = []
func terminal() -> (LocalProcessTerminalView, String) {
    let frame = NSRect(x: 0, y: 0, width: 640, height: 400)
    let v = LocalProcessTerminalView(frame: frame)
    let w = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
    w.isReleasedWhenClosed = false; w.contentView = v; _ = w.makeFirstResponder(v); windows.append(w)
    let path = NSTemporaryDirectory() + "kb-\(UUID().uuidString.prefix(8))"
    v.startProcess(executable: "/bin/sh", args: ["-c", "stty raw -echo; exec cat > \(path)"], environment: nil, execName: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    return (v, path)
}
func fk(_ k: Int) -> String { String(Character(UnicodeScalar(k)!)) }
let L = fk(NSLeftArrowFunctionKey), R = fk(NSRightArrowFunctionKey), U = fk(NSUpArrowFunctionKey), D = fk(NSDownArrowFunctionKey)
let HOME = fk(NSHomeFunctionKey), END = fk(NSEndFunctionKey), PU = fk(NSPageUpFunctionKey), PD = fk(NSPageDownFunctionKey), DEL = fk(NSDeleteFunctionKey)
// name, keyCode, modifiers, characters (with modifiers), charactersIgnoringModifiers
var chords: [(String, UInt16, NSEvent.ModifierFlags, String, String)] = []
let arrowMods: [(String, NSEvent.ModifierFlags)] = [("", []), ("⇧", [.shift]), ("⌥", [.option]), ("⇧⌥", [.shift, .option]),
                                                    ("⌘", [.command]), ("⇧⌘", [.shift, .command]), ("⌃", [.control]), ("⇧⌃", [.shift, .control])]
for (n, code, ch) in [("←", UInt16(123), L), ("→", 124, R), ("↑", 126, U), ("↓", 125, D)] {
    for (mn, m) in arrowMods { chords.append(("\(mn)\(n)", code, m.union([.function, .numericPad]), ch, ch)) }
}
for (n, code, ch) in [("Home", UInt16(115), HOME), ("End", 119, END), ("PgUp", 116, PU), ("PgDn", 121, PD), ("fn⌫ (⌦)", 117, DEL)] {
    for (mn, m) in [("", NSEvent.ModifierFlags()), ("⇧", [.shift]), ("⌥", [.option]), ("⌘", [.command]), ("⌃", [.control])] {
        chords.append(("\(mn)\(n)", code, m.union([.function]), ch, ch))
    }
}
for (mn, m) in [("", NSEvent.ModifierFlags()), ("⌥", [.option]), ("⌘", [.command]), ("⌃", [.control]), ("⇧", [.shift])] {
    chords.append(("\(mn)⌫", 51, m, "\u{7f}", "\u{7f}"))
}
let letterCodes: [Character: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "y": 16, "t": 17,
                                        "o": 31, "p": 35, "k": 40, "n": 45, "e": 14, "u": 32, "w": 13]
for l in "aefbnptodhkyuw" {
    let ctrl = String(Character(UnicodeScalar(UInt8(l.asciiValue! & 0x1f))))
    chords.append(("⌃\(l.uppercased())", letterCodes[l]!, [.control], ctrl, String(l)))
}
for l in "bfd" { chords.append(("⌥\(l.uppercased())", letterCodes[l]!, [.option], "∫", String(l))) }
for l in "azxcv" { chords.append(("⌘\(l.uppercased())", letterCodes[l]!, [.command], String(l), String(l))) }
chords.append(("⇧⌘Z", 6, [.command, .shift], "Z", "z"))
chords.append(("⇧⌘A", 0, [.command, .shift], "A", "a"))

func hex(_ b: [UInt8]) -> String {
    b.map { $0 == 0x1b ? "ESC" : ($0 < 0x20 || $0 == 0x7f) ? String(format: "%02x", $0) : String(UnicodeScalar($0)) }.joined(separator: " ")
}
let (legacy, lp) = terminal()
let (kitty, kp) = terminal()
kitty.feed(text: "\u{1b}[>5u")
print("legacy flags \(legacy.keyboardEnhancementFlags.rawValue) kitty flags \(kitty.keyboardEnhancementFlags.rawValue)")
func sent(_ v: LocalProcessTerminalView, _ path: String, _ c: (String, UInt16, NSEvent.ModifierFlags, String, String)) -> [UInt8] {
    let before = (try? Data(contentsOf: URL(fileURLWithPath: path)))?.count ?? 0
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: c.2, timestamp: 0, windowNumber: v.window!.windowNumber, context: nil,
                             characters: c.3, charactersIgnoringModifiers: c.4, isARepeat: false, keyCode: c.1)!
    v.keyDown(with: e)
    RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    return Array(((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()).dropFirst(before))
}
var rows: [[String: String]] = []
for c in chords {
    let a = sent(legacy, lp, c), b = sent(kitty, kp, c)
    print("\(c.0)\t\(hex(a))\t\(hex(b))")
    rows.append(["chord": c.0, "legacy": String(decoding: a, as: UTF8.self), "kitty": String(decoding: b, as: UTF8.self)])
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "keybytes.json"
try! JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: out))

// With a main menu as Duo's has: Edit's Undo (undo:), Cut (cut:), Select All (selectAll:) and a Format item that
// nobody answers while a terminal has the keyboard (Bold, ⌘B). Does a disabled item's key reach the program?
let menu = NSMenu(); let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); menu.addItem(editItem)
let edit = NSMenu(title: "Edit"); editItem.submenu = edit
edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
edit.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
edit.addItem(withTitle: "Bold", action: Selector(("duoBold:")), keyEquivalent: "b")
app.mainMenu = menu
for c in [("⌘Z", UInt16(6), NSEvent.ModifierFlags.command, "z", "z"), ("⌘X", 7, .command, "x", "x"), ("⌘A", 0, .command, "a", "a"), ("⌘B", 11, .command, "b", "b")] {
    print("with menu \(c.0)\tlegacy \(hex(sent(legacy, lp, c)))\tkitty \(hex(sent(kitty, kp, c)))")
}
