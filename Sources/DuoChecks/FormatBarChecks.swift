import AppKit
import DuoControl
import DuoKit
import Foundation

// DL-266: the Markdown formatting bar (when it shows, the table swap), the paragraph commands, the caret-state report,
// and dictating into a document (one undo per dictation, signed by Suggest Edits, Return then a new line).
@MainActor func formatBarChecks() throws {
    print("markdown formatting bar and dictation into documents (DL-266)")
    typealias L = FormatBarLogic

    // When it shows: a Markdown document has the keyboard; it stays while a menu is open or a dictation runs.
    func shows(keys: Bool = true, md: Bool = true, hidden: Bool = false, source: Bool = false, ro: Bool = false, preview: Bool = false, menu: Bool = false, dict: Bool = false, review: Bool = false) -> Bool {
        L.shows(editorHasKeyboard: keys, isMarkdown: md, hidden: hidden, source: source, readOnly: ro, templatePreview: preview, menuOpen: menu, dictating: dict, reviewPending: review)
    }
    check(shows(), "the bar shows while a Markdown document has the keyboard")
    check(!shows(keys: false), "…and not when the keyboard is elsewhere (the console, the sidebar, another tab)")
    check(shows(keys: false, menu: true) && shows(keys: false, dict: true), "…but stays while one of its menus is open and while a dictation runs")
    check(!shows(md: false) && !shows(ro: true) && !shows(preview: true) && !shows(source: true), "…never on another kind of file, a read-only file, a template's preview or in Source mode")
    check(!shows(hidden: true) && !shows(hidden: true, menu: true, dict: true, review: true), "View › Hide Formatting Bar turns it off")
    // DL-317: pending review keeps the bar without the keyboard, but only on a Markdown document it can show on.
    check(shows(keys: false, review: true), "the bar shows without the keyboard while the document has suggestions, comments or is Suggesting (DL-317)")
    check(!shows(keys: false, review: false) && !shows(keys: false, md: false, review: true) && !shows(keys: false, ro: true, review: true) && !shows(keys: false, source: true, review: true) && !shows(keys: false, preview: true, review: true), "…and not with nothing to review, nor on another kind of file, read-only, Source or a template's preview")

    // The table swap: Style's place goes to + Row, + Column, Align and Delete; they fold into ⋯ under 420.
    check(L.controls(inTable: false, width: 460) == ["style", "bold", "italic", "link", "table", "more", "comment"], "out of a table: Style, B, I, Link, Table, ⋯, then Comment (DL-317)")
    check(L.controls(inTable: false, width: 360, tableInMore: true) == ["style", "bold", "italic", "link", "more", "comment"], "at 360, or reviewing without the keyboard, Insert Table goes into ⋯ (DL-317 §Fit)")
    check(L.tableInMore(width: 360, hasKeyboard: true, reviewPending: false) && L.tableInMore(width: 460, hasKeyboard: false, reviewPending: true) && !L.tableInMore(width: 460, hasKeyboard: true, reviewPending: true) && !L.tableInMore(width: 460, hasKeyboard: true, reviewPending: false), "Insert Table folds at 360, and at 460 only when the bar is there for review alone")
    check(L.modeTitle(suggesting: false) == "Editing" && L.modeTitle(suggesting: true) == "Suggesting", "the mode menu names the mode: Editing or Suggesting")
    check(L.controls(inTable: true, width: 460) == ["bold", "italic", "link", "row", "column", "align", "delete", "comment"], "in a table at 460: B, I, Link, + Row, + Column, Align, Delete, Comment (no Style, as the board draws it)")
    check(L.controls(inTable: true, width: 360) == ["bold", "italic", "link", "row", "column", "more", "comment"], "in a table at 360: Align and Delete fold into ⋯; Comment stays")
    check(!L.controls(inTable: false, width: 360).contains("mic") && !L.controls(inTable: true, width: 360).contains("mic"), "the mic is not a control that folds: it is always the trailing end")
    check(L.styles.map(\.command) == ["body", "heading1", "heading2", "heading3", "quote", "bullet", "numbered", "task", "codeblock"], "Style offers Body, Heading 1–3, Quote, Bulleted List, Numbered List, Task, Code Block")
    check(L.styleTitle("heading2") == "Heading 2" && L.styleTitle("numbered") == "Numbered List" && L.styleTitle("zzz") == "Body", "Style names the paragraph at the caret")
    check(DuoMetric.formatBarHeight == 24 && DuoWebTokens.documentPaddingY == 24, "formatBarHeight is 24 and the document's top padding 24 (the bar sits in the padding)")
    let src = (try? String(contentsOf: repoRoot().appending(path: "Vendor/codemirror/src/duo-editor.js"), encoding: .utf8)) ?? ""
    check(!src.contains("TableBarWidget") && !src.contains("duo-table-bar") && src.contains("scrollMargins"), "the page has no in-document table bar, and keeps a scroll margin for the bar")

    // A live editor: the caret-state report, the paragraph commands, one undo per dictation.
    let fm = FileManager.default
    let root = URL(fileURLWithPath: "/tmp/duo-bar-\(UUID().uuidString.prefix(6))")
    let proj = root.appending(path: "bar-project")
    try fm.createDirectory(at: proj, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let doc = proj.appending(path: "a.md")
    try Data("# Title\n\nplain **bold** text\n\n- one\n- two\n\n> quoted\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\nend\n".utf8).write(to: doc)
    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)
    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "bar-project", "topic": "Research", "path": proj.path, "goal": "g"])))
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["bar-project"] = proj
    m.open(project: "bar-project")
    func wait(_ s: Double = 10, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(s)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func duo2(_ args: String...) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()), session: nil, cwd: proj.path)) { out = $0 }
        _ = wait { out != nil }
        return out ?? ControlResponse(ok: false, output: "no answer")
    }
    func settle(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    func text(_ e: EditorController) -> String { var t = ""; var got = false; e.run("return duo.text()") { t = $0 as? String ?? ""; got = true }; _ = wait { got }; return t }
    func js(_ e: EditorController, _ code: String) -> Any? { var r: Any?; var got = false; e.run(code) { r = $0; got = true }; _ = wait { got }; return r }
    m.openDocument("a.md")
    let e = m.editor
    e.open(doc)
    check(wait { e.phase == .open }, "the document opens in the editor")

    func caret(at needle: String, then: String = "") -> String {
        let t = text(e)
        let at = (t as NSString).range(of: needle).location
        _ = js(e, "duo.select(\(at + 1), \(at + 1)); return 1")
        settle()
        return then
    }
    _ = caret(at: "Title")
    check(wait(5) { e.caretBlock == "heading1" }, "the page reports the paragraph at the caret: Heading 1 (\(e.caretBlock))")
    _ = caret(at: "bold")
    check(wait(5) { e.caretMarks.contains("bold") && e.caretBlock == "body" }, "…the marks over it: Bold on, Body (\(e.caretMarks), \(e.caretBlock))")
    _ = caret(at: "one")
    check(wait(5) { e.caretBlock == "bullet" && e.caretMarks.isEmpty }, "…a bullet (\(e.caretBlock))")
    _ = caret(at: "quoted")
    check(wait(5) { e.caretBlock == "quote" }, "…a quote (\(e.caretBlock))")
    _ = caret(at: "| 1")
    check(wait(5) { e.inTable }, "…the caret in a table (so the bar swaps its controls)")

    // The new commands, one undo step each, through duo2 doc format.
    _ = caret(at: "plain")
    check(duo2("doc", "format", "quote").ok && text(e).contains("> plain **bold** text"), "doc format quote makes the line a quote")
    check(duo2("doc", "format", "bullet").ok && text(e).contains("- plain **bold** text") && !text(e).contains("> plain"), "doc format bullet replaces the quote mark")
    check(duo2("doc", "format", "numbered").ok && text(e).contains("1. plain **bold** text"), "doc format numbered")
    check(duo2("doc", "format", "body").ok && text(e).contains("\nplain **bold** text\n") && !text(e).contains("1. plain"), "doc format body clears the mark")
    check(duo2("doc", "format", "codeblock").ok && text(e).contains("```\nplain **bold** text\n```"), "doc format codeblock fences the line")
    check(duo2("doc", "format", "codeblock").ok && !text(e).contains("```") , "…and again takes the fence off")
    check(!duo2("doc", "format", "nonsense").ok, "an unknown format word is refused")

    // DL-317: Comment, with and without a selection (the bar's button calls reviewAddComment, as ⌥⌘M does).
    func composing() -> Bool { (js(e, "return document.querySelector('.duo-mg-composer') ? 1 : 0") as? Int) == 1 }
    func cancelCompose() { _ = js(e, "const f = document.querySelector('.duo-mg-composer textarea'); if (f) f.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); return 1"); settle() }
    _ = caret(at: "plain")
    _ = js(e, "const t = duo.text(); const a = t.indexOf('plain'); duo.select(a, a + 5); return 1"); settle()
    e.reviewAddComment()
    check(wait(5) { composing() }, "Comment with a selection opens the margin composer")
    cancelCompose()
    check(wait(5) { !composing() }, "…and Esc closes it")
    _ = caret(at: "plain")
    e.reviewAddComment()
    check(wait(5) { composing() }, "Comment with only a caret takes the word at the caret and opens the composer")
    cancelCompose()
    check(DuoAction.byID[.commentAdd] != nil && DuoAction.byID[.docReview] != nil && DuoAction.byID[.docMarkup] != nil && DuoAction.byID[.suggestionAccept] != nil && DuoAction.byID[.suggestionReject] != nil, "comment add, doc review, doc markup and suggestion accept and reject are all still duo2 verbs")

    // View › Hide Formatting Bar and its verb.
    check(duo2("view", "format-bar", "hide").ok && m.formatBarHidden && DuoState.load().formatBarHidden, "view format-bar hide turns it off, remembered")
    check(duo2("view", "format-bar", "show").ok && !m.formatBarHidden, "view format-bar show brings it back")
    DuoState.update { $0.formatBarHidden = false }

    // Dictation: a phrase at a time, one ⌘Z for the lot (Q-346: Return then a new line).
    let target = VoiceTarget.document(doc.path)
    let host = m.voice.host
    check(host != nil && host!.document(target, .begin), "a document with the keyboard can take a dictation")
    _ = js(e, "duo.select(duo.text().length, duo.text().length); return 1")
    settle()
    let before = text(e)
    let depth0 = js(e, "return duo.undoDepth()") as? Int ?? -1
    _ = js(e, "duo.dictEnd(); return duo.dictBegin()")
    for p in ["Who approves async refunds", "over a thousand dollars."] {
        _ = host!.document(target, .phrase(p))
        _ = host!.document(target, .tail("and"))
        settle()
    }
    check(wait(5) { text(e).hasSuffix("end\nWho approves async refunds over a thousand dollars.") || text(e).hasSuffix("endWho approves async refunds over a thousand dollars.") || text(e).hasSuffix("end Who approves async refunds over a thousand dollars.") }, "phrases land at the caret, a space between them")
    _ = host!.document(target, .end)
    settle()
    let depth1 = js(e, "return duo.undoDepth()") as? Int ?? -1
    check(depth1 == depth0 + 1, "the whole dictation is one undo event (\(depth0) → \(depth1))")
    _ = js(e, "duo.undo(); return 1")
    check(wait(5) { text(e) == before }, "one ⌘Z takes out the whole dictation")

    // A click or a key in the document breaks a dictation the page was running.
    var broke = false
    e.onDictationBreak = { broke = true }
    _ = js(e, "return duo.dictBegin()")
    _ = js(e, "duo.insertAtCaret('x'); return 1")
    check(wait(5) { broke } && js(e, "return duo.dictActive()") as? Bool == false, "typing in the document ends the dictation first")

    // Suggest Edits on: the words are one signed insertion.
    m.openDocument("a.md")
    _ = js(e, "duo.select(0, 0); return 1")
    _ = js(e, "duo.dictEnd(); return 1")
    try? Data("---\nsuggest-edits: true\n---\nOne line.\n".utf8).write(to: proj.appending(path: "b.md"))
    m.openDocument("b.md")
    let e2 = m.editor
    e2.open(proj.appending(path: "b.md"))
    check(wait { e2.phase == .open && e2.url?.lastPathComponent == "b.md" }, "a document with Suggest Edits on opens")
    _ = js(e2, "duo.select(duo.text().length - 1, duo.text().length - 1); return duo.dictBegin()")
    let t2 = VoiceTarget.document(proj.appending(path: "b.md").path)
    _ = m.voice.host!.document(t2, .phrase("and more"))
    _ = m.voice.host!.document(t2, .phrase("words"))
    settle()
    let signed = text(e2)
    check(signed.components(separatedBy: "{++").count == 2 && signed.contains("and more words"), "…with Suggest Edits on, the phrases are one signed insertion (\(signed.replacingOccurrences(of: "\n", with: "⏎")))")
    _ = m.voice.host!.document(t2, .end)

    // Routing: ⇧⌘D with a document focused names the document; read-only has no target.
    m.webFocus = .editor
    check(m.voiceFocusTarget == .document(doc.path) || m.voiceFocusTarget == .document(proj.appending(path: "b.md").path), "⇧⌘D with a Markdown document focused goes to the document")
    check(duo2("voice", "status", "--doc").ok, "duo2 voice status --doc names the document")
    m.webFocus = .none
}
