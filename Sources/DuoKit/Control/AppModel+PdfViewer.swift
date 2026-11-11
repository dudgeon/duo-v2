import DuoControl
import DuoSearch
import Foundation
import PDFKit

// The PDF viewer's model side (DL-332, DL-333, DL-335): which PDF is on screen, Send Selection, `duo2 pdf …`, and the stand-in
// comment panel's actions (Q-496), which write through the same `PdfComments` calls `duo2 comment …` makes.
extension AppModel {
    /// PDFs open in the PDF viewer (DL-332); Quick Look is its fallback.
    public static func isPdfViewable(_ path: String) -> Bool { (path as NSString).pathExtension.lowercased() == "pdf" }

    func wirePdfViewer(_ v: PdfViewer) {
        v.onSelection = { [weak self] has in
            guard let self else { return }
            if has { self.webFocus = .pdf } else if self.webFocus == .pdf { self.webFocus = .none }
        }
        v.pdfView.extraMenuItems = { [weak self, weak v] in
            guard let self, let v, self.terminalsMode == .live, !v.selectionText.isEmpty else { return [] }
            return self.sendMenuItems("Selection") { done in done(self.pdfSelectionPayload()) }
                + [ActionMenuItem("Add Comment") { self.askPdfComment(v) }]
        }
    }

    /// The PDF on screen: the right pane's tab, or the PDF side of a split (DL-333).
    public var visiblePdf: PdfViewer? {
        guard let v = pdfViewerIfLoaded, v.url != nil, let path = rightTab else { return nil }
        if Self.isPdfViewable(path) { return v }
        if let t = splitTab(path), let w = t.with, Self.isPdfViewable(w) { return v }
        return nil
    }

    /// The selection as Send Selection puts it in a prompt, nil when the PDF has none.
    func pdfSelectionPayload() -> String? {
        guard let v = visiblePdf, let u = v.url else { return nil }
        return v.selectionPayload(path: displayPath(u))
    }

    // MARK: duo2 pdf …

    func pdfViewVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        guard let v = visiblePdf else { return done(.fail("no PDF is showing (open one with `duo2 doc open`)")) }
        guard v.state == .ready else {
            if case .failed(let why) = v.state { return done(.fail("Duo can’t draw \(v.url?.lastPathComponent ?? "the PDF"): \(why)")) }
            return done(.fail("the PDF is still being read"))
        }
        let path = v.url.map(displayPath) ?? ""
        switch id {
        case .pdfPage:
            guard let arg = inv[0] else { return done(.ok("Page \(v.page) of \(v.count).", ["file": path, "page": v.page, "count": v.count])) }
            let n = arg == "next" ? v.page + 1 : ["previous", "prev"].contains(arg) ? v.page - 1 : Int(arg)
            guard let n else { return done(.fail("usage: \(id.action.usage)")) }
            let to = v.go(n)
            done(.ok("Page \(to) of \(v.count)." + (to != n ? " (The PDF has \(v.count).)" : ""), ["file": path, "page": to, "count": v.count]))
        case .pdfZoom:
            if let arg = inv[0] {
                switch arg {
                case "in": v.zoomIn()
                case "out": v.zoomOut()
                case "fit": v.fit()
                default:
                    guard let p = Double(arg.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), (25...500).contains(p) else { return done(.fail("usage: \(id.action.usage)")) }
                    v.setScale(p / 100)
                }
            }
            let pct = Int((v.scale * 100).rounded())
            done(.ok("Zoom \(pct)%" + (v.fitting ? " (fitting the width)." : "."), ["percent": pct, "fit": v.fitting]))
        case .pdfFind:
            let q = inv.text
            guard !q.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
            v.findText = q
            guard let r = v.find(q, backwards: inv.has("previous")) else { return done(.fail("“\(q)” isn’t in \(v.url?.lastPathComponent ?? "the PDF")")) }
            done(.ok("Match \(r.index) of \(r.of) on page \(r.page).", ["match": r.index, "matches": r.of, "page": r.page]))
        case .pdfSelection:
            guard let p = pdfSelectionPayload() else { return done(.fail("nothing is selected in the PDF")) }
            done(.ok(p, ["file": path, "page": v.selectionPages?.lowerBound ?? 0, "text": v.selectionText]))
        case .pdfCommentsPanel:
            switch inv[0] {
            case "show": v.commentsOpen = true
            case "hide": v.commentsOpen = false
            case nil: break
            default: return done(.fail("usage: \(id.action.usage)"))
            }
            done(.ok("The comments panel is \(v.commentsOpen ? "showing" : "hidden").", ["showing": v.commentsOpen, "threads": v.threads.count]))
        default: done(.fail("not a pdf verb"))
        }
    }

    // MARK: The stand-in comment panel (Q-496)

    private var pdfAuthor: String { NSUserName() }

    /// Writes through `PdfComments` as `duo2 comment …` does, tells the viewers, and says why if it can't.
    private func pdfWrite(_ url: URL, _ body: () throws -> PdfComments.Written) {
        do { _ = try body(); Self.pdfChanged(url) } catch { info("\(error)") }
    }

    /// Add Comment on the selection (`comment add --at`): asks for the text, then appends a Highlight over the selected lines.
    public func askPdfComment(_ v: PdfViewer) {
        guard let url = v.url, let at = v.selectionQuads() else { return }
        let field = DuoQuestion.Field(label: "Comment", text: "")
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: Add a comment on page \(at.page)\n".utf8)); return }
        SheetCenter.shared.ask(from: self, DuoQuestion(title: "Add a comment", paragraphs: ["On page \(at.page): “\(SendFormat.line(v.selectionText).prefix(120))”. Start with @claude to have it sent to a session."],
                                                      field: field, choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Add Comment", isDefault: true) {
                let text = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.addPdfComment(url, page: at.page, quads: at.quads, text: text)
            },
        ]))
    }

    /// The call `comment add` makes, with a selection's page and rectangles.
    public func addPdfComment(_ url: URL, page: Int, quads: [CGRect], text: String) {
        pdfWrite(url) { try PdfComments.add(url, page: page, quads: quads, point: nil, author: pdfAuthor, text: text, backups: Self.pdfBackups) }
    }

    public func askPdfReply(_ v: PdfViewer, thread: String) {
        guard let url = v.url else { return }
        let field = DuoQuestion.Field(label: "Reply", text: "")
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: Reply to #\(thread)\n".utf8)); return }
        SheetCenter.shared.ask(from: self, DuoQuestion(title: "Reply to #\(thread)", field: field, choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Reply", isDefault: true) {
                let text = field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.pdfWrite(url) { try PdfComments.reply(url, to: thread, author: self.pdfAuthor, text: text, backups: Self.pdfBackups) }
            },
        ]))
    }

    public func setPdfThreadClosed(_ v: PdfViewer, thread: String, closed: Bool) {
        guard let url = v.url else { return }
        pdfWrite(url) { try PdfComments.resolve(url, thread: thread, resolved: closed, author: pdfAuthor, backups: Self.pdfBackups) }
    }

    public func askPdfDelete(_ v: PdfViewer, thread: String) {
        guard let url = v.url else { return }
        if Env.autoconfirm { FileHandle.standardError.write(Data("question: Delete #\(thread)\n".utf8)); return }
        SheetCenter.shared.ask(from: self, DuoQuestion(title: "Delete this thread?", paragraphs: ["The highlight and every comment in #\(thread) are removed from the PDF. A copy of the file is kept in Duo’s support folder."], choices: [
            .init(label: "Cancel", isCancel: true) {},
            .init(label: "Delete", isDefault: true) { self.pdfWrite(url) { try PdfComments.delete(url, thread: thread, backups: Self.pdfBackups) } },
        ]))
    }

    /// `comment send`: the same call, to the session the thread already has or the one on screen.
    public func sendPdfThread(_ v: PdfViewer, thread: String) {
        guard let url = v.url else { return }
        sendReviewComment(url, thread: thread) { [weak self, weak v] r in
            v?.refreshThreads()
            if !r.ok { self?.info(r.text) }
        }
    }

    /// Where a thread's @claude send stands, in the panel's words: nil when it doesn't name @claude.
    public func pdfSendState(_ v: PdfViewer, thread id: String) -> String? {
        guard let url = v.url, let t = (try? Self.pdfReviewThreads(url))?.first(where: { $0.id == id }), t.comments.contains(where: \.mentionsClaude) else { return nil }
        if t.comments.contains(where: { $0.author == "claude" }) { return "Claude replied" }
        guard let d = reviewDeliveries[Self.reviewKey(url, id)] else { return "Not sent" }
        return d.state.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
