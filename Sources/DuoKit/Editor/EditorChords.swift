import AppKit
import SwiftUI
import WebKit

/// The chords the editor page must not handle itself (DL-167 step 6, LR-60): every ⌘ chord in the
/// command registry, because Duo's menus own them (Bold, Save, Close Tab, Send Selection, …) and a
/// CodeMirror binding for the same key would run twice or instead. Generated from `DuoCommand`, so a
/// chord added to the registry reaches the page with no second list to keep (this replaces the
/// hand-kept `DUO_CHORDS` in duo-editor.js). The page reads `window.__duoChords`, injected at
/// document start; key names are CodeMirror's, modifiers in any order (the page normalises both sides).
public enum EditorChords {
    /// Registry chords the page keeps because CodeMirror's own binding is the one wanted while the
    /// editor has the keyboard, and the menu item is not enabled there: ⌘↑ is "go to the start of the
    /// document" (All Projects needs no editor), ⌘L is "select line" (Focus Address needs a browser tab).
    public static let keptByEditor: Set<DuoCommand> = [.allProjects, .focusAddress]

    /// CodeMirror's name for a chord, or nil if it carries no ⌘ (⌃Tab is handled by the pane key monitor).
    public static func keyName(_ s: KeyboardShortcut) -> String? {
        guard s.modifiers.contains(.command) else { return nil }
        let key: String
        switch s.key {
        case .upArrow: key = "ArrowUp"
        case .downArrow: key = "ArrowDown"
        case .leftArrow: key = "ArrowLeft"
        case .rightArrow: key = "ArrowRight"
        case .return: key = "Enter"
        case .tab: key = "Tab"
        case .escape: key = "Escape"
        case .space: key = "Space"
        default: key = String(s.key.character).lowercased()
        }
        var parts: [String] = []
        if s.modifiers.contains(.control) { parts.append("Ctrl") }
        if s.modifiers.contains(.option) { parts.append("Alt") }
        if s.modifiers.contains(.shift) { parts.append("Shift") }
        parts.append("Mod")
        return (parts + [key]).joined(separator: "-")
    }

    /// The set the page filters out of its keymaps.
    public static var keys: [String] {
        DuoCommand.allCases.filter { !keptByEditor.contains($0) }.compactMap { $0.shortcut.flatMap(keyName) }
    }

    /// The user script that hands the set to the page before it loads.
    public static func script() -> String {
        let json = (try? JSONSerialization.data(withJSONObject: keys.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "window.__duoChords = \(json);"
    }
}

/// Whether a responder is a view inside a web view (the editor's, a browser tab's): WebKit's first
/// responder is an inner content view, never the `WKWebView` itself, so `is WKWebView` and class
/// names miss it (F-249). The responder chain says where a key is going.
@MainActor func isInsideWebView(_ r: NSResponder?) -> Bool {
    var v = r as? NSView
    while let x = v { if x is WKWebView { return true }; v = x.superview }
    return false
}
