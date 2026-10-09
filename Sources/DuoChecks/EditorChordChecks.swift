import DuoKit
import Foundation
import SwiftUI

// DL-167 step 6: the editor page's chord set comes from the command registry, so a new ⌘ chord
// cannot be forgotten, and the key monitors ask the responder chain, never a class name.

@MainActor func editorChordChecks() throws {
    print("the editor's chords come from the registry (DL-167 step 6)")
    let generated = Set(EditorChords.keys)
    var missing: [String] = []
    for c in DuoCommand.allCases {
        guard let s = c.shortcut, let name = EditorChords.keyName(s) else { continue }   // ⌃Tab has no ⌘: the pane key monitor's
        if !generated.contains(name) && !EditorChords.keptByEditor.contains(c) { missing.append("\(c): \(name)") }
    }
    check(missing.isEmpty, "every registry chord with ⌘ is in the generated set or kept by the editor on purpose (\(missing.joined(separator: ", ")))")
    check(EditorChords.keptByEditor.allSatisfy { c in c.shortcut.flatMap(EditorChords.keyName).map { !generated.contains($0) } ?? true },
          "a chord kept by the editor (⌘↑, ⌘L) is not filtered out of the page")
    // The hand-kept list this replaces (DUO_CHORDS), still all there.
    let old = ["Mod-d", "Mod-i", "Mod-b", "Mod-s", "Mod-w", "Mod-n", "Shift-Mod-n", "Mod-k", "Shift-Mod-a", "Shift-Mod-p", "Shift-Mod-h", "Mod-Enter"]
    check(old.allSatisfy(generated.contains), "the old hand-kept DUO_CHORDS are all generated (\(old.filter { !generated.contains($0) }))")
    check(EditorChords.keyName(DuoCommand.bold.shortcut!) == "Mod-b" && EditorChords.keyName(DuoCommand.newFolder.shortcut!) == "Shift-Mod-n"
          && EditorChords.keyName(DuoCommand.jumpToPeekSelection.shortcut!) == "Mod-Enter" && EditorChords.keyName(DuoCommand.nextPane.shortcut!) == "Alt-Mod-ArrowRight",
          "chord names are CodeMirror's: Mod-b, Shift-Mod-n, Mod-Enter, Alt-Mod-ArrowRight")
    check(EditorChords.keyName(DuoCommand.nextTab.shortcut!) == nil, "⌃Tab carries no ⌘ and stays with the pane key monitor")
    check(EditorChords.script().hasPrefix("window.__duoChords = [\"") && EditorChords.script().contains("\"Mod-s\""), "the page gets them as window.__duoChords at document start")
}
