import DuoKit
import DuoSearch
import Foundation
import WebKit

/// The two viewers' pages with the margin on (DL-337): where each thread's anchor is, what is lit, what is selected, and that the
/// cards under paragraphs give way to the margin.
@MainActor func officeMarginChecks() throws {
    print("the Word and PowerPoint pages: anchors for the margin (DL-337)")
    _ = NSApplication.shared
    let root = repoRoot()
    let scratch = FileManager.default.temporaryDirectory.appending(path: "duo-office-margin-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    func spin(_ seconds: Double, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    func run(_ web: WKWebView, _ body: String) -> Any? {
        var out: Any??
        web.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { r in if case .success(let v) = r { out = .some(v) } else { out = .some(nil) } }
        spin(20) { out != nil }
        return out ?? nil
    }

    // Word
    let docx = scratch.appending(path: "Review.docx")
    try FileManager.default.copyItem(at: root.appending(path: "docs/design/docx-viewer-handoff/fixture/markup/Word markup.docx"), to: docx)
    let wv = DocxViewer(resources: root.appending(path: "Vendor/docx-viewer"))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = wv.webView
    wv.open(docx)
    spin(40) { wv.state == .ready }
    check(wv.state == .ready, "the Word fixture draws")
    spin(3) { !wv.office.threads.isEmpty }
    check(wv.office.threads.count >= 5, "the margin has the file's threads once the document is drawn (\(wv.office.threads.count))")
    let anchors = run(wv.webView, "return __duo.anchors()") as? [[String: Any]] ?? []
    check(anchors.count == wv.office.threads.count && anchors.allSatisfy { ($0["y"] as? Double ?? 0) > 0 }, "every thread has an anchor y in the page (\(anchors.count))")
    check(anchors.first { $0["id"] as? String == "c0" }?["found"] as? Bool == true, "…and the commented text is found for the first")
    check(run(wv.webView, "return document.body.classList.contains('margin') && getComputedStyle(document.querySelector('.duo-card')).display") as? String == "none", "with the margin on, the cards under paragraphs are not drawn")
    _ = run(wv.webView, "return __duo.setActive('c0')")
    check((run(wv.webView, "return document.querySelectorAll('mark.duo-comment.duo-active').length") as? Int ?? 0) > 0, "the active card's text is lit")
    _ = run(wv.webView, "return __duo.setActive(null)")
    check(run(wv.webView, "return document.querySelectorAll('mark.duo-comment.duo-active').length") as? Int == 0, "…and is not lit when no card is active")
    let none = run(wv.webView, "return __duo.selection()")
    check(none == nil || none is NSNull, "nothing is selected: no selection")
    _ = run(wv.webView, "const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); for (let n; (n = w.nextNode());) { const i = n.data.indexOf('beans'); if (i >= 0) { const r = document.createRange(); r.setStart(n, i); r.setEnd(n, i + 5); getSelection().removeAllRanges(); getSelection().addRange(r); break; } } return true")
    var picked: OfficeMargin.Selection?
    wv.office.querySelection { picked = $0 }
    spin(10) { picked != nil }
    check(picked?.text == "beans" && picked?.at.first == "beans" && picked?.at.last?.hasPrefix("para:") == true && (picked?.y ?? 0) > 0, "a selected word is a comment's --at: the text, then its paragraph (\(picked?.at ?? []))")

    // PowerPoint
    let pptx = scratch.appending(path: "Deck.pptx")
    try FileManager.default.copyItem(at: root.appending(path: "docs/design/duo-decks-study/samples/import/grower-update.pptx"), to: pptx)
    let shape = try Pptx.outline(pptx, slide: 4).first!.shapes.first { ($0.text ?? "").count > 1 && $0.type == "shape" }!
    _ = try OfficeComments.add(pptx, at: "4/\(shape.id)", author: "morgan-editor", text: "About this box")
    _ = try OfficeComments.add(pptx, at: "2", author: "dana-writer", text: "About the slide")
    let dv = DeckViewer(resources: root.appending(path: "Vendor/pptx-renderer"))
    let dwin = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
    dwin.contentView = dv.webView
    dv.open(pptx)
    spin(40) { dv.state == .ready }
    check(dv.state == .ready, "the deck draws")
    spin(3) { dv.office.threads.count >= 3 }
    check(dv.office.threads.contains { $0.anchorKind == "shape" && $0.slide == 4 } && dv.office.threads.contains { $0.anchorKind == "slide" && $0.slide == 2 }, "the margin has the deck's threads with their slides and anchors")
    let danchors = run(dv.webView, "return __duo.anchors()") as? [[String: Any]] ?? []
    check(danchors.count == dv.office.threads.count && danchors.filter { $0["found"] as? Bool == true }.count >= 2, "every thread has a place on the page; the shape's and the slide's are found (\(danchors.count))")
    check(run(dv.webView, "return document.querySelectorAll('.duo-anchor').length") as? Int == 1 && (run(dv.webView, "return document.querySelectorAll('.deck-number.duo-anchor-slide').length") as? Int ?? 0) >= 1,
          "a shape comment outlines its shape and a slide comment boxes the slide's number")
    let shapeID = dv.office.threads.first { $0.anchorKind == "shape" }?.id ?? ""
    _ = run(dv.webView, "return __duo.setActive('\(shapeID)')")
    check(run(dv.webView, "return document.querySelectorAll('.duo-anchor.duo-active').length") as? Int == 1, "the active card lights its shape")
    var whole: OfficeMargin.Selection?
    dv.office.querySelection { whole = $0 }
    spin(10) { whole != nil }
    check(whole?.at.count == 1 && Int(whole?.at.first ?? "") != nil, "nothing selected in a deck: Add Comment is on the whole slide (\(whole?.at ?? []))")
    _ = run(dv.webView, "return __duo.marginSet([])")
    check(run(dv.webView, "return document.querySelectorAll('.duo-anchor, .duo-anchor-slide').length") as? Int == 0, "an emptied margin leaves no anchors on the page")
}
