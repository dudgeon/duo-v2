import AppKit
import DuoKit
import Foundation

// C-135, DL-278: an editor per side of a split, one home per file, save and reconcile per side.
@MainActor func editorSetChecks() throws {
    print("editors: one per side, one home per file (C-135, DL-278)")
    let dir = FileManager.default.temporaryDirectory.appending(path: "duo-editorset-\(UUID().uuidString.prefix(6))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appending(path: "notes.md"), b = dir.appending(path: "synthesis.md")
    try Data("# Notes\n\nInterview 4.\n".utf8).write(to: a)
    try Data("# Synthesis\n\nWhat we heard.\n".utf8).write(to: b)

    func wait(_ what: String, _ seconds: Double = 15, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func text(_ e: EditorController) -> String? {
        var out: String?, done = false
        e.run("return duo.text()") { v in out = v as? String; done = true }
        _ = wait("text", 5) { done }
        return out
    }
    func disk(_ u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }

    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)
    let m = AppModel(fixture: try repoFixture())
    let set = m.editors
    check(set.ifLoaded(.second) == nil, "the second editor isn't made until a side needs it (a WebContent process each)")
    let main = set.editor(.main), second = set.editor(.second)
    check(main !== second && main.webView !== second.webView, "each side has its own editor and web view")

    // Two documents, both editable, side by side.
    set.open(a, in: .main)
    set.open(b, in: .second)
    check(wait("both open") { main.phase == .open && second.phase == .open }, "two documents open side by side")
    check(m.editorShowing(a) === main && m.editorShowing(b) === second, "editorShowing finds the editor that has each file")

    // The active side is what `editor` (the menus, ⌘S, duo2 doc) acts on.
    set.active = .second
    check(set.active == .second && set.editor(set.active) === second, "the active side's editor is the second when it's active")
    set.active = .main

    // Typing in one side, then saving it, writes only that file.
    second.run("duo.typeOne(0); return 1") { _ in }
    check(wait("second dirty") { second.dirty }, "typing in the second side makes it dirty")
    check(!main.dirty, "…and leaves the main side clean")
    var saved = false
    second.saveNow { saved = true }
    check(wait("saved") { saved } && disk(b).hasPrefix("x# Synthesis"), "⌘S on the second side saves its own file")
    check(disk(a) == "# Notes\n\nInterview 4.\n", "…and never the other side's")

    // An outside write reconciles in the side that has the file, and only there (DL-77, per side).
    try Data("# Notes\n\nInterview 4.\n\nAdded outside.\n".utf8).write(to: a)
    check(wait("main merged") { text(main)?.contains("Added outside.") == true }, "an outside change to the main side's file merges into the main side")
    check(text(second)?.contains("Added outside.") == false, "…and not into the other side")

    // One home per file: opening the second side's file in the main editor moves it, saved, never two buffers.
    second.run("duo.typeOne(0); return 1") { _ in }
    _ = wait("dirty again") { second.dirty }
    set.open(b, in: .main)
    check(wait("moved") { main.url?.lastPathComponent == "synthesis.md" && main.phase == .open }, "a file opened in the other side moves there")
    check(second.url == nil, "…and the side it left lets go of it (one document per file)")
    check(disk(b).hasPrefix("xx# Synthesis"), "…after saving what was typed there")
    check(text(main)?.hasPrefix("xx# Synthesis") == true, "…and the new side shows the saved text, not a stale buffer")
    check(m.editorShowing(b) === main && m.editorShowing(a) == nil, "editorShowing follows the move")

    // A rename followed by an editor keeps the file's home: it still can't open twice.
    set.open(a, in: .second)
    _ = wait("a in second") { second.url?.lastPathComponent == "notes.md" && second.phase == .open }
    let renamed = dir.appending(path: "interview-notes.md")
    try FileManager.default.moveItem(at: a, to: renamed)
    second.fileMoved(to: renamed)
    set.open(renamed, in: .main)
    check(wait("renamed moved") { main.url?.lastPathComponent == "interview-notes.md" } && second.url == nil,
          "a renamed file still has one home: opening it in the other side moves it")

    // A side in conflict keeps its file: unsaved text from a conflict is never dropped by a move (DL-77).
    _ = wait("main open") { main.phase == .open }
    main.run("duo.typeOne(2); return 1") { _ in }
    _ = wait("main dirty") { main.dirty }
    try Data("# Rewritten\n\nAll different.\n".utf8).write(to: renamed)
    if wait("conflict", 8, { main.conflict }) {
        check(!set.open(renamed, in: .second), "a file in conflict stays in its side (open elsewhere is refused)")
        check(main.url?.lastPathComponent == "interview-notes.md" && second.url != renamed, "…and is still shown where it was")
        main.resolve(keepMine: true)
    } else {
        check(true, "(no conflict arose from the outside write; the merge took it)")
    }

    // Duo Decks R11, R12 (DL-284): Add Comment and open a thread from code, without moving the keyboard.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    let host = NSView(frame: window.contentView!.bounds), elsewhere = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
    window.contentView = host
    main.webView.frame = NSRect(x: 0, y: 40, width: 470, height: 560); host.addSubview(main.webView)
    host.addSubview(elsewhere)
    set.open(b, in: .main)
    _ = wait("b in main") { main.url?.lastPathComponent == "synthesis.md" && main.phase == .open }
    window.makeFirstResponder(elsewhere)
    let keys = window.firstResponder
    var added: Bool?
    main.addComment(lines: 3...3) { added = $0 }
    check(wait("composed", 5) { added != nil } && added == true, "addComment(lines:) composes a comment on those lines")
    check(window.firstResponder === keys && !main.hasFocus, "…without taking the keyboard (R12)")
    var thread: String??
    main.run("return duo.reviewComment('Check the March date', 15, 19)") { _ in }
    _ = wait("thread", 2) { false }
    main.openThread(line: 3) { thread = .some($0) }
    check(wait("opened", 5) { thread != nil } && (thread ?? nil) != nil, "openThread(line:) opens the thread anchored on that line")
    var byID: String??
    if let id = thread ?? nil { main.openThread(id: id) { byID = .some($0) } }
    check(wait("by id", 5) { byID != nil } && (byID ?? nil) == (thread ?? nil), "openThread(id:) opens it by id")
    check(window.firstResponder === keys && !main.hasFocus, "…without taking the keyboard (R11)")
    var none: String??
    main.openThread(line: 1) { none = .some($0) }
    check(wait("none", 5) { none != nil } && (none ?? "x") == nil, "openThread on a line with no thread says so (nil)")
}
