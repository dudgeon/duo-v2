import AppKit
import DuoControl
import DuoKit
import DuoSearch
import Foundation
import PDFKit
import SwiftUI

// DL-332, DL-333, DL-335: the PDF viewer (page, zoom, find, selection), the comment margin, built as Markdown review's (Q-496), and a PDF on one side of a split (Q-497).

@MainActor func pdfViewerChecks(scratch: URL) throws {
    print("the PDF viewer: page, zoom, find, selection, comment margin, split (DL-332, DL-333, DL-335)")
    let fm = FileManager.default
    let proj = scratch.appending(path: "reading")
    try fm.createDirectory(at: proj, withIntermediateDirectories: true)
    cgFixture(proj.appending(path: "paper.pdf"))
    cgFixture(proj.appending(path: "other.pdf"))
    try Data("# Notes\n\nSome notes.\n".utf8).write(to: proj.appending(path: "notes.md"))
    try Data("PK".utf8).write(to: proj.appending(path: "memo.docx"))
    try Data("this is not a pdf".utf8).write(to: proj.appending(path: "broken.pdf"))
    setenv("DUO_EDITOR_DIR", repoRoot().appending(path: "Vendor/codemirror/dist").path, 1)

    var fx = try repoFixture()
    fx.projects.append(try JSONDecoder().decode(Fixture.Project.self, from: JSONSerialization.data(withJSONObject: ["name": "reading", "topic": "Research", "path": proj.path, "goal": "g"])))
    // A session of the project on screen: where an @claude comment goes (it runs outside Duo here, so the send ends "not delivered").
    fx.sessions.append(try JSONDecoder().decode(Fixture.Session.self, from: JSONSerialization.data(withJSONObject: ["name": "Reader", "project": "reading", "state": "idle", "sessionId": "sid-reader-1"])))
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["reading"] = proj
    m.open(project: "reading")
    m.consoleTab = "sid-reader-1"
    func wait(_ s: Double = 5, _ ok: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(s)
        while !ok(), Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return ok()
    }
    func duo2(_ args: String...) -> ControlResponse {
        var out: ControlResponse?
        m.handle(ControlRequest(token: "", command: args[0], args: Array(args.dropFirst()), session: nil, cwd: proj.path)) { out = $0 }
        _ = wait(10) { out != nil }
        return out ?? ControlResponse(ok: false, output: "no answer")
    }

    // The dispatcher: a .pdf goes to the PDF viewer, before Quick Look (a source scan of the right pane's branches).
    let panes = (try? String(contentsOf: repoRoot().appending(path: "Sources/DuoKit/Project/ProjectPanes.swift"), encoding: .utf8)) ?? ""
    let pdfBranch = panes.range(of: "AppModel.isPdfViewable(path), let file = model.liveFile(path)")
    let binaryBranch = panes.range(of: "FileKind.isBinary(file) {\n                // Never the editor")
    check(pdfBranch != nil && binaryBranch != nil && pdfBranch!.lowerBound < binaryBranch!.lowerBound, "the right pane draws a .pdf with the PDF viewer, before the Quick Look branch for other binaries")
    check(AppModel.isPdfViewable("docs/Paper.PDF") && !AppModel.isPdfViewable("notes.md") && !AppModel.isPdfViewable("deck.pptx"), "isPdfViewable: .pdf only")
    check(m.visiblePdf == nil && !duo2("pdf", "page").ok, "no PDF showing: `pdf page` says so")

    m.openDocument("paper.pdf")
    m.rightTab = "paper.pdf"
    let v = m.pdfViewer
    v.open(proj.appending(path: "paper.pdf"))
    check(v.state == .ready && v.count == 4 && v.page == 1 && v.fitting && m.visiblePdf === v, "the viewer opens paper.pdf: ready, 4 pages, page 1, fitting the width")
    check(v.pdfView.displayMode == .singlePageContinuous && v.pdfView.autoScales && v.pdfView.displaysPageBreaks, "…continuous single-page scroll, autoscaled, with page breaks")

    // pdf page
    check(duo2("pdf", "page").output == "Page 1 of 4.", "`pdf page` prints the page")
    check(duo2("pdf", "page", "3").output == "Page 3 of 4." && v.page == 3, "`pdf page 3` goes to page 3")
    check(duo2("pdf", "page", "next").output == "Page 4 of 4." && duo2("pdf", "page", "9").output.hasPrefix("Page 4 of 4."), "`next` counts from there; past the end stops at the last")
    check(duo2("pdf", "page", "previous").output == "Page 3 of 4." && duo2("pdf", "page", "x").ok == false, "`previous` goes back; a word that isn't a page is refused")

    // pdf zoom
    check(duo2("pdf", "zoom", "150").output.hasPrefix("Zoom 150%") && abs(v.scale - 1.5) < 0.001 && !v.fitting, "`pdf zoom 150` sets 150% and stops fitting")
    check(duo2("pdf", "zoom", "in").output.hasPrefix("Zoom 188%") && duo2("pdf", "zoom", "out").output.hasPrefix("Zoom 150%"), "`in` and `out` step by a quarter")
    check(!duo2("pdf", "zoom", "9").ok && !duo2("pdf", "zoom", "9000").ok && !duo2("pdf", "zoom", "big").ok, "a percentage outside 25 to 500, or a word, is refused")
    check(duo2("pdf", "zoom", "fit").output.contains("fitting the width") && v.fitting, "`pdf zoom fit` fits the width again")

    // View > Zoom In / Zoom Out / Actual Size act on the PDF showing (⌘+ ⌘− ⌘0)
    m.webFocus = .none
    check(DuoCommand.zoomIn.isEnabled(in: m) && DuoCommand.zoomOut.isEnabled(in: m) && DuoCommand.actualSize.isEnabled(in: m), "View > Zoom In, Zoom Out and Actual Size are enabled while a PDF is showing")
    _ = duo2("pdf", "zoom", "100")
    DuoCommand.zoomIn.perform(in: m)
    check(abs(v.scale - 1.25) < 0.001 && !v.fitting, "Zoom In steps the PDF a quarter (\(v.scale))")
    DuoCommand.zoomOut.perform(in: m); DuoCommand.zoomOut.perform(in: m)
    check(abs(v.scale - 0.8) < 0.001, "Zoom Out steps it back (\(v.scale))")
    DuoCommand.actualSize.perform(in: m)
    check(abs(v.scale - 1) < 0.001, "Actual Size is 100% (\(v.scale))")
    m.webFocus = .editor
    check(!DuoCommand.zoomIn.isEnabled(in: m), "…and not while the editor has the keyboard")
    m.webFocus = .none
    _ = duo2("pdf", "zoom", "fit")

    // pdf find: selects the match, steps, wraps; the selection is what Send Selection sends
    let f1 = duo2("pdf", "find", "turquoise")
    check(f1.output == "Match 1 of 1 on page 1." && v.page == 1, "`pdf find turquoise`: one match, on page 1 (\(f1.output))")

    // Edit > Add Comment (⌘⌥M) acts on the PDF's selection, as the bar's Add Comment does
    let focusBefore = m.webFocus
    m.webFocus = .pdf
    check(v.selectionQuads() != nil && DuoCommand.addComment.isEnabled(in: m), "Add Comment (⌘⌥M) is enabled with text selected in the PDF")
    check(DuoCommand.addComment.shortcut == KeyboardShortcut("m", modifiers: [.command, .option]), "…on ⌘⌥M")
    m.webFocus = .editor
    check(!DuoCommand.addComment.isEnabled(in: m), "…and not for the PDF while the editor has the keyboard")
    m.webFocus = focusBefore
    let sel1 = duo2("pdf", "selection").output
    check(sel1.hasPrefix("From ") && sel1.hasSuffix("paper.pdf, page 1:\n> turquoise\n"), "`pdf selection` is the match as Send Selection puts it: the file, the page, the quoted text (\(sel1))")
    let f2 = duo2("pdf", "find", "line")
    let total = v.matchCount
    check(f2.output.hasPrefix("Match 1 of \(total) on page") && total > 10, "`pdf find line` finds the matches, case ignored (\(f2.output))")
    check(duo2("pdf", "find", "line").output.hasPrefix("Match 2 of \(total)"), "the same text again steps to the next match")
    check(duo2("pdf", "find", "line", "--previous").output.hasPrefix("Match 1 of \(total)") && duo2("pdf", "find", "line", "--previous").output.hasPrefix("Match \(total) of \(total)"), "--previous steps back and wraps to the last")
    check(!duo2("pdf", "find", "no such words anywhere").ok, "a text that isn't there is refused")
    check(duo2("selection").output.contains("paper.pdf, page"), "`duo2 selection` includes the PDF's selection")
    let sf = SendFormat.pdfSelection("two words", path: "docs/a b.pdf", from: 3, to: 3)
    check(sf == "From docs/a b.pdf, page 3:\n> two words\n", "the send format: From <path>, page N: and the quoted text (\(sf))")
    check(SendFormat.pdfSelection("x", path: "p.pdf", from: 3, to: 4).hasPrefix("From p.pdf, pages 3–4:"), "…pages 3–4 when the selection crosses a page")
    check(m.webFocus == .pdf, "a selection gives the PDF the keyboard for Send Selection (webFocus .pdf)")
    v.pdfView.clearSelection(); v.clearFind()
    check(wait(2) { v.selectionText.isEmpty }, "clearing the selection empties the viewer's selection")
    check(!duo2("pdf", "selection").ok, "no selection: `pdf selection` says nothing is selected")

    // The comment margin: Markdown review's margin beside the pages (Q-496)
    check(duo2("pdf", "comments-panel").output.contains("showing") && v.commentsShown, "the comment margin is on by default: no click shows a comment")
    check(duo2("pdf", "comments-panel", "hide").output.contains("hidden") && !v.commentsShown && duo2("pdf", "comments-panel", "show").output.contains("showing") && v.commentsShown, "`pdf comments-panel show|hide` shows and hides it")
    check(duo2("pdf", "comments-panel", "--show-closed", "on").output.contains("closed comments shown") && v.showClosed && duo2("pdf", "comments-panel", "--show-closed", "off").output.contains("hidden") && !v.showClosed && !duo2("pdf", "comments-panel", "--show-closed", "maybe").ok, "…and `--show-closed on|off` is Show Closed Comments")
    check(wait(10) { v.margin.isReady }, "the margin's page is up")
    func cards() -> [[String: Any]] {
        var out: [[String: Any]] = []
        var got = false
        v.margin.evaluate("return duoSideMargin.dump()") { out = ($0 as? [[String: Any]]) ?? []; got = true }
        _ = wait(5) { got }
        return out
    }
    func text(_ id: String) -> String { cards().first { $0["id"] as? String == id }?["text"] as? String ?? "" }

    // Add Comment on a selection: the composer opens in the margin (no sheet), and Post writes the same thing `comment add` does
    check(v.select(text: "turquoise walrus") && v.selectionQuads()?.page == 1 && (v.selectionQuads()?.quads.count ?? 0) >= 1, "a selection gives the page and its lines' rectangles for a comment")
    let sheetsBefore = SheetCenter.shared.queue.count + (SheetCenter.shared.current == nil ? 0 : 1)
    let pageBefore = v.page
    m.composePdfComment(v)
    check(v.composing?.page == 1 && !(v.composing?.quads.isEmpty ?? true), "Add Comment keeps the selection's page and rectangles for the composer")
    var composing = false
    check(wait { v.margin.evaluate("return duoSideMargin.composing()") { composing = ($0 as? Bool) == true }; RunLoop.main.run(until: Date().addingTimeInterval(0.05)); return composing }, "…and the margin shows the composer card, level with the selection")
    check(cards().contains { $0["id"] as? String == "composer" && ($0["top"] as? Double ?? -1) >= 0 }, "…a card in the margin, not a sheet")
    check(SheetCenter.shared.queue.count + (SheetCenter.shared.current == nil ? 0 : 1) == sheetsBefore, "Add Comment asks nothing in a Duo sheet (the modal is gone)")
    let addPath = repoRoot().appending(path: "Sources/DuoKit/Control/AppModel+PdfViewer.swift")
    let addSource = (try? String(contentsOf: addPath, encoding: .utf8)) ?? ""
    let addFns = addSource.range(of: "public func composePdfComment").flatMap { r in addSource.range(of: "static func namesClaude").map { String(addSource[r.lowerBound..<$0.lowerBound]) } } ?? ""
    check(!addFns.isEmpty && !addFns.contains("SheetCenter") && !addFns.contains("DuoQuestion") && !addSource.contains("func askPdfComment") && !addSource.contains("func askPdfReply") && !addSource.contains("func askPdfDelete"), "source scan: no SheetCenter or DuoQuestion in the add path, and no askPdfComment, askPdfReply or askPdfDelete left")
    let tid = m.postPdfComment(v, text: "@claude is this the right phrase?")
    check(tid != nil && wait { v.threads.count == 1 }, "Post writes the comment; the viewer reloaded and lists the thread (\(tid ?? "nil"))")
    let th = v.threads.first
    check(th?.page == 1 && th?.kind == "Highlight" && (th?.anchor ?? "").contains("turquoise"), "…a Highlight on page 1 over the selected text (\(th?.anchor ?? "nil"))")
    check(duo2("comment", "list", "paper.pdf").output.contains("is this the right phrase?"), "`duo2 comment list` reads what the margin wrote")
    check(v.composing == nil && v.page == pageBefore && v.count == 4, "the composer is done and the reload kept the page (\(v.page))")
    check(wait { text(tid ?? "?").contains("is this the right phrase?") }, "the thread is a card in the margin with no click: its author and text are drawn")
    let key = AppModel.reviewKey(proj.appending(path: "paper.pdf"), tid ?? "c1")
    check(m.reviewDeliveries[key] != nil, "@claude on Post sends it at once: the thread has a delivery (\(m.reviewDeliveries[key].map { "\($0.state.rawValue): \($0.sessionName)" } ?? "none"))")
    check(wait { text(tid ?? "?").contains("Not delivered") }, "…and the card says where it stands, as Markdown's: Not delivered (the fixture session runs outside Duo)")
    check(m.pdfSendState(v, thread: tid ?? "") == "Not Delivered", "the model's send state agrees")
    m.setPdfThreadClosed(v, thread: tid ?? "c1", closed: true)
    check(wait { v.threads.first?.resolved == true }, "Close and Keep marks it closed (a hidden Completed reply, DL-335)")
    check(wait { cards().contains { ($0["text"] as? String ?? "").contains("1 closed") } && !text(tid ?? "?").contains("right phrase") }, "…and it folds into \"1 closed · Show\", as Markdown's does")
    v.margin.activate(nil)
    v.showClosed = true
    check(wait { text(tid ?? "?").hasPrefix("› Closed") }, "Show draws the closed thread as its one folded line")
    v.showClosed = false
    m.setPdfThreadClosed(v, thread: tid ?? "c1", closed: false)
    check(wait { v.threads.first?.resolved == false }, "Reopen opens it again")
    v.margin.activate(nil)
    check(m.replyPdfThread(v, thread: tid ?? "c1", text: "A reply"), "a reply from the card is written")
    check(wait { v.threads.first?.items.count == 2 } && wait { text(tid ?? "?").contains("1 reply") }, "…and the card counts it")
    // Claude's reply (what `duo2 comment reply … --file` writes) appears in the margin without a click
    _ = try? PdfComments.reply(proj.appending(path: "paper.pdf"), to: tid ?? "c1", author: "claude", text: "It is the right phrase.", backups: AppModel.pdfBackups)
    AppModel.pdfChanged(proj.appending(path: "paper.pdf"))
    check(wait { v.threads.first?.items.count == 3 } && wait { text(tid ?? "?").contains("2 replies") }, "Claude's reply is in the thread and counted on the card, with no click")
    check(!text(tid ?? "?").contains("Not delivered"), "…an answered thread drops its delivery line (the pill stays)")
    // The active card (a click on its highlight, or on the card) shows the whole thread with its reply field and Close and Keep / Delete
    v.margin.activate(tid)
    check(wait { let t = text(tid ?? "?"); return t.contains("It is the right phrase.") && t.contains("Close and Keep") && t.contains("Delete") }, "the active card shows every reply with Close and Keep and Delete")
    v.margin.activate(nil)
    // Narrow: under 420 the margin is a gutter of count markers
    v.paneWidth = 380
    check(wait { cards().contains { $0["id"] as? String == tid && ($0["w"] as? Double ?? 0) <= 24 } && v.margin.reserve == 24 }, "a pane under 420 wide draws the gutter: a count marker, 24 wide (Markdown's narrow layout)")
    v.paneWidth = 1000
    check(wait { v.margin.reserve > 100 }, "…and the cards again when it widens")
    // Delete (at once, as Markdown's; the original is kept first)
    m.deletePdfThread(v, thread: tid ?? "c1")
    check(wait { v.threads.isEmpty } && wait { v.margin.width == 0 }, "Delete removes the thread; with no comments the margin gives its width back (\(v.margin.width))")

    // @claude for a PDF outside any project: the same route (the document's choice, the last editor, else the session on screen)
    let loose = scratch.appending(path: "loose-folder")
    try fm.createDirectory(at: loose, withIntermediateDirectories: true)
    cgFixture(loose.appending(path: "loose.pdf"))
    v.open(loose.appending(path: "loose.pdf"))
    check(v.state == .ready && wait { v.select(text: "turquoise walrus") }, "a PDF in a folder that isn't a project opens and has a selection")
    m.composePdfComment(v)
    let lid = m.postPdfComment(v, text: "@claude and this one outside a project?")
    check(lid != nil && wait { v.threads.count == 1 }, "…a comment on it is written")
    let lkey = AppModel.reviewKey(loose.appending(path: "loose.pdf"), lid ?? "c1")
    check(wait { m.reviewDeliveries[lkey] != nil }, "…and @claude on Post is sent from there too: a delivery to the session on screen (\(m.reviewDeliveries[lkey]?.sessionName ?? "none"))")
    v.open(proj.appending(path: "paper.pdf"))
    check(v.state == .ready && v.threads.isEmpty, "back to paper.pdf")
    // A second composer for the next checks
    check(v.select(text: "turquoise walrus"), "select again")
    m.composePdfComment(v)
    check(v.composing != nil, "Add Comment again opens the composer")
    v.cancelCompose()
    check(v.composing == nil && wait { var c = true; v.margin.evaluate("return duoSideMargin.composing()") { c = ($0 as? Bool) == true }; RunLoop.main.run(until: Date().addingTimeInterval(0.05)); return !c }, "Cancel closes it and writes nothing")
    check(duo2("comment", "list", "paper.pdf").output.contains("no comment threads"), "…nothing was written to the file")
    // Go to Thread (an outline) is still the viewer's, used by checks and the margin's click
    _ = try? PdfComments.add(proj.appending(path: "paper.pdf"), page: 1, quads: v.selectionQuads()?.quads ?? [], point: nil, author: "geoff", text: "Go to this", backups: AppModel.pdfBackups)
    AppModel.pdfChanged(proj.appending(path: "paper.pdf"))
    check(wait { v.threads.count == 1 }, "a thread added by another program appears")
    v.show(v.threads[0])
    check(v.pdfView.highlightedSelections?.isEmpty == false, "show(thread) outlines where the thread is")

    // Fallback: a file PDFKit can't open
    v.open(proj.appending(path: "broken.pdf"))
    if case .failed(let why) = v.state { check(why.contains("damaged"), "a damaged PDF is .failed with why (\(why)): Quick Look under a notice") } else { check(false, "a damaged PDF is .failed") }
    check(!duo2("pdf", "page").ok, "…and `pdf page` says Duo can’t draw it")
    v.open(proj.appending(path: "paper.pdf"))
    check(v.state == .ready, "opening a good file again recovers")

    // Split view (DL-333)
    m.openDocument("notes.md"); m.openDocument("other.pdf"); m.openDocument("memo.docx")
    let cands = m.splitCandidates(beside: "paper.pdf")
    check(cands.contains("notes.md") && !cands.contains("other.pdf") && !cands.contains("memo.docx"), "a PDF's Open in Split View offers text documents, not another PDF or a Word file (\(cands))")
    let cands2 = m.splitCandidates(beside: "notes.md")
    check(cands2.contains("paper.pdf") && !cands2.contains("memo.docx"), "a text document's offers PDFs, not Word files (\(cands2))")
    check(!m.openSplitView("paper.pdf", with: "other.pdf") && !m.openSplitView("paper.pdf", with: "memo.docx") && !m.openSplitView("notes.md", with: "memo.docx"), "pdf+pdf, pdf+docx and md+docx are refused")
    check(m.openSplitView("notes.md", with: "paper.pdf"), "Open in Split View: paper.pdf beside notes.md")
    let t = m.showingSplit
    check(t?.isDocPair == true && t?.source == "notes.md" && t?.with == "paper.pdf" && t?.swapped == false && t?.active == .source, "the text document is the source (the editor), the PDF its other side, text active")
    check(m.rightTab == "notes.md" && m.visiblePdf === v && m.activeEditorRef == .main && m.editors.active == .main, "the PDF is on screen as a side; the editor stays the main one")
    check(duo2("pdf", "page", "2").output == "Page 2 of 4.", "`pdf page` works on the PDF side of a split")
    m.setActiveRole(.preview, in: "notes.md")
    check(m.editors.active == .main && t.map { m.splitSideName($0, .preview) } == "paper.pdf", "making the PDF side active leaves the editor alone; the side is named for the file")
    m.separateDocPair("notes.md")
    check(m.splitTabs.isEmpty && m.openDocuments.contains("paper.pdf") && m.openDocuments.contains("notes.md"), "closing the split leaves both as ordinary tabs")
    m.rightTab = "notes.md"
    check(m.openSplitView("paper.pdf", with: "notes.md"), "the other way round: notes.md beside paper.pdf")
    let t2 = m.showingSplit
    check(t2?.source == "notes.md" && t2?.with == "paper.pdf" && t2?.swapped == true && t2?.place(of: .preview) == .left, "…the PDF is asked for on the left, so the pair is swapped: PDF left, text right")
    m.separateDocPair("notes.md")

    // The registry and the parity scan
    for id in [ActionID.pdfPage, .pdfZoom, .pdfFind, .pdfSelection, .pdfCommentsPanel] {
        check(DuoAction.all.contains { $0.id == id && $0.family == .pdf } && AppModel.appVerbs.contains(id), "\(id.rawValue) is a pdf verb the app answers")
    }
    let labels = ["Comments", "Add Comment", "Previous Page", "Next Page", "Zoom In", "Zoom Out", "Fit", "n closed · Show", "Close and Keep", "Post"]
    check(labels.allSatisfy { l in DuoAction.all.contains { $0.ui.contains(l) } }, "every control in the bar and the margin names a verb in the registry")
}
