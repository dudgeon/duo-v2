import AppKit
import DuoControl
import DuoKit
import DuoSearch
import Foundation
import PDFKit

// DL-332, DL-333, DL-335: the PDF viewer (page, zoom, find, selection), the stand-in comments panel (Q-496), and a PDF on one side of a split (Q-497).

@MainActor func pdfViewerChecks(scratch: URL) throws {
    print("the PDF viewer: page, zoom, find, selection, comments panel, split (DL-332, DL-333, DL-335)")
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
    let m = AppModel(fixture: fx)
    m.terminalsMode = .live
    m.liveFolders["reading"] = proj
    m.open(project: "reading")
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

    // pdf find: selects the match, steps, wraps; the selection is what Send Selection sends
    let f1 = duo2("pdf", "find", "turquoise")
    check(f1.output == "Match 1 of 1 on page 1." && v.page == 1, "`pdf find turquoise`: one match, on page 1 (\(f1.output))")
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

    // The comments panel
    check(duo2("pdf", "comments-panel").output.contains("hidden") && !v.commentsOpen, "the comments panel is off by default")
    check(duo2("pdf", "comments-panel", "show").output.contains("showing") && v.commentsOpen && duo2("pdf", "comments-panel", "hide").output.contains("hidden") && !v.commentsOpen, "`pdf comments-panel show|hide` toggles it")

    // Add Comment on a selection: the sheet asks for the text, then the same write `comment add` makes; the viewer reloads
    check(v.select(text: "turquoise walrus") && v.selectionQuads()?.page == 1 && (v.selectionQuads()?.quads.count ?? 0) >= 1, "a selection gives the page and its lines' rectangles for a comment")
    let before = SheetCenter.shared.queue.count
    let pageBefore = v.page
    m.askPdfComment(v)
    guard let q = SheetCenter.shared.current, q.field != nil, SheetCenter.shared.queue.count == before + 1 else { check(false, "Add Comment asks for the text in a Duo sheet"); return }
    check(q.title == "Add a comment" && q.choices.map(\.label) == ["Cancel", "Add Comment"], "Add Comment asks for the text in a Duo sheet (SheetCenter), never an alert")
    q.field?.text = "@claude is this the right phrase?"
    SheetCenter.shared.answer(q.choices[1])
    check(wait { v.threads.count == 1 }, "…and the comment is written; the viewer reloaded and lists the thread")
    let th = v.threads.first
    check(th?.page == 1 && th?.kind == "Highlight" && (th?.anchor ?? "").contains("turquoise"), "…a Highlight on page 1 over the selected text (\(th?.anchor ?? "nil"))")
    check(duo2("comment", "list", "paper.pdf").output.contains("is this the right phrase?"), "`duo2 comment list` reads what the panel wrote")
    check(m.pdfSendState(v, thread: th?.id ?? "") == "Not sent", "a thread that names @claude shows its send state: Not sent")
    check(v.page == pageBefore && v.count == 4, "the reload kept the page (\(v.page))")
    let tid = th?.id ?? "c1"
    m.setPdfThreadClosed(v, thread: tid, closed: true)
    check(wait { v.threads.first?.resolved == true }, "Close Thread marks it Closed (a hidden Completed reply, DL-335)")
    m.setPdfThreadClosed(v, thread: tid, closed: false)
    check(wait { v.threads.first?.resolved == false }, "Reopen opens it again")
    let b2 = SheetCenter.shared.queue.count
    m.askPdfDelete(v, thread: tid)
    check(SheetCenter.shared.queue.count == b2 + 1 && SheetCenter.shared.current?.title == "Delete this thread?", "Delete Thread asks first, in a Duo sheet")
    if let d = SheetCenter.shared.current { SheetCenter.shared.answer(d.choices[0]) }   // Cancel
    check(v.threads.count == 1, "…and Cancel keeps it")
    m.askPdfReply(v, thread: tid)
    if let r = SheetCenter.shared.current, r.field != nil { r.field?.text = "A reply"; SheetCenter.shared.answer(r.choices[1]) }
    check(wait { v.threads.first?.items.count == 2 }, "Reply asks for the text, then appends the reply")
    v.show(v.threads[0])
    check(v.pdfView.highlightedSelections?.isEmpty == false, "Go to Thread outlines where the thread is")

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
    let labels = ["Comments", "Reply", "Close Thread", "Reopen", "Delete Thread", "Go to Thread", "Add Comment", "Previous Page", "Next Page", "Zoom In", "Zoom Out", "Fit", "Send to Claude"]
    check(labels.allSatisfy { l in DuoAction.all.contains { $0.ui.contains(l) } }, "every control in the bar and the panel names a verb in the registry")
}
