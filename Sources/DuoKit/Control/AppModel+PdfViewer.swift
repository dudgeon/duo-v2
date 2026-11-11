import AppKit
import DuoControl
import DuoSearch
import Foundation
import PDFKit

// The PDF viewer's model side (DL-332, DL-333, DL-335): which PDF is on screen, Send Selection, `duo2 pdf …`, and the comment
// margin's actions (Q-496: the Markdown review margin beside the pages), which write through the same `PdfComments` calls
// `duo2 comment …` makes and send a comment that names @claude when it is posted, as Markdown does (DL-236 10A).
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
                + [ActionMenuItem("Add Comment") { self.composePdfComment(v) }]
        }
        v.margin.onAction = { [weak self, weak v] op, body in
            guard let self, let v else { return }
            self.pdfMarginAction(v, op, body)
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
            case "show": v.commentsShown = true
            case "hide": v.commentsShown = false
            case nil: break
            default: return done(.fail("usage: \(id.action.usage)"))
            }
            if let c = inv.flags["show-closed"] {
                switch c.lowercased() {
                case "on", "yes", "true", "": v.showClosed = true
                case "off", "no", "false": v.showClosed = false
                default: return done(.fail("--show-closed takes on or off"))
                }
            }
            let closed = v.threads.filter(\.resolved).count
            done(.ok("The comment margin is \(v.commentsShown ? "showing" : "hidden"); \(v.threads.count - closed) open threads, \(closed) closed (closed comments \(v.showClosed ? "shown" : "hidden")).",
                     ["showing": v.commentsShown, "threads": v.threads.count, "closed": closed, "showClosed": v.showClosed]))
        default: done(.fail("not a pdf verb"))
        }
    }

    // MARK: The comment margin (Q-496)

    private var pdfAuthor: String { NSUserName() }

    /// Writes through `PdfComments` as `duo2 comment …` does, tells the viewers, and says why if it can't.
    @discardableResult
    private func pdfWrite(_ url: URL, _ body: () throws -> PdfComments.Written) -> PdfComments.Written? {
        do { let w = try body(); Self.pdfChanged(url); return w } catch { info("\(error)"); return nil }
    }

    /// Add Comment (the bar, ⌘⌥M, the right-click menu): the composer opens in the margin level with the selection, the same card
    /// as Markdown's with the `@` menu (nothing is asked in a sheet).
    public func composePdfComment(_ v: PdfViewer) {
        guard v.compose() else { return }
        pushPdfReviewState()
    }

    /// The composer's Post: the call `comment add` makes, with the selection's page and rectangles; a comment that names @claude
    /// goes to a session now (DL-236 10A), as in Markdown. Returns the thread's id.
    @discardableResult
    public func postPdfComment(_ v: PdfViewer, text: String) -> String? {
        guard let url = v.url, let c = v.composing else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        v.composed()
        guard let w = pdfWrite(url, { try PdfComments.add(url, page: c.page, quads: c.quads, point: nil, author: pdfAuthor, text: text, backups: Self.pdfBackups) }) else { return nil }
        v.margin.activate(w.id)
        if Self.namesClaude(text) { sendPdfThread(v, thread: w.id) }
        return w.id
    }

    /// A reply from the active card: written to the file, and sent when it names @claude.
    @discardableResult
    public func replyPdfThread(_ v: PdfViewer, thread: String, text: String) -> Bool {
        guard let url = v.url else { return false }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, pdfWrite(url, { try PdfComments.reply(url, to: thread, author: pdfAuthor, text: text, backups: Self.pdfBackups) }) != nil else { return false }
        if Self.namesClaude(text) { sendPdfThread(v, thread: thread) }
        return true
    }

    public func setPdfThreadClosed(_ v: PdfViewer, thread: String, closed: Bool) {
        guard let url = v.url else { return }
        pdfWrite(url) { try PdfComments.resolve(url, thread: thread, resolved: closed, author: pdfAuthor, backups: Self.pdfBackups) }
    }

    /// Delete on the active card, as Markdown's: at once. (The original is kept in Duo's support folder first, `PDF backups`.)
    public func deletePdfThread(_ v: PdfViewer, thread: String) {
        guard let url = v.url else { return }
        pdfWrite(url) { try PdfComments.delete(url, thread: thread, backups: Self.pdfBackups) }
    }

    static func namesClaude(_ text: String) -> Bool { text.range(of: #"@claude\b"#, options: [.regularExpression, .caseInsensitive]) != nil }

    /// What the margin page reported.
    func pdfMarginAction(_ v: PdfViewer, _ op: String, _ body: [String: Any]) {
        let id = body["id"] as? String
        switch op {
        case "post": postPdfComment(v, text: body["text"] as? String ?? "")
        case "cancel": v.cancelCompose()
        case "reply": if let id { replyPdfThread(v, thread: id, text: body["text"] as? String ?? "") }
        case "close": if let id { setPdfThreadClosed(v, thread: id, closed: true) }
        case "reopen": if let id { setPdfThreadClosed(v, thread: id, closed: false) }
        case "delete": if let id { deletePdfThread(v, thread: id) }
        case "showClosed": v.showClosed = body["value"] as? Bool ?? false
        case "escaped": v.pdfView.window?.makeFirstResponder(v.pdfView)
        case "send", "retry": if let id { sendPdfThread(v, thread: id) }
        case "pill": pdfPillMenu(v, thread: id ?? "", x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0)
        case "crashed": pushPdfReviewState(); v.pushMargin()
        default: break
        }
    }

    /// The pill's menu: the sessions of the project, as Markdown's (a thread not sent, or not delivered, goes to the one picked).
    private func pdfPillMenu(_ v: PdfViewer, thread id: String, x: Double, y: Double) {
        guard let url = v.url else { return }
        let sessions = fixture.sessions.filter { $0.sessionId != nil && ($0.project == currentProject?.name) }
        guard !sessions.isEmpty else { return }
        let menu = NSMenu()
        for s in sessions {
            let item = NSMenuItem(title: "\(s.name) · \(reviewSessionStatus(s))", action: nil, keyEquivalent: "")
            item.representedObject = s.tabKey
            menu.addItem(item)
        }
        let delegate = ReviewPillMenu { [weak self, weak v] key in
            guard let self, let s = sessions.first(where: { $0.tabKey == key }) else { return }
            self.bindReviewSession(url, to: s)
            if let d = self.reviewDeliveries[Self.reviewKey(url, id)], d.state == .notDelivered || d.state == .queued {
                self.sendReviewComment(url, thread: id, to: s) { [weak v] _ in v?.refreshThreads() }
            } else { self.pushPdfReviewState() }
        }
        for item in menu.items { item.target = delegate; item.action = #selector(ReviewPillMenu.pick(_:)) }
        reviewPillMenu = delegate
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: v.margin.webView)
    }

    /// `comment send`: the same call, to the session the thread already has or the first guess (the document's last choice, the
    /// last to edit it, the one on screen). With none, the usual Duo question says so; the card stays "Not sent" with Send.
    public func sendPdfThread(_ v: PdfViewer, thread: String) {
        guard let url = v.url else { return }
        sendReviewComment(url, thread: thread) { [weak self, weak v] r in
            v?.refreshThreads()
            self?.pushPdfReviewState()
            if !r.ok { self?.info(r.text) }
        }
    }

    /// The deliveries of the PDF showing, and the first-guess session of the pill, pushed into the margin page (as `pushReviewState`).
    func pushPdfReviewState() {
        guard let v = visiblePdf, let url = v.url else { return }
        let prefix = url.resolvingSymlinksInPath().standardizedFileURL.path + "#"
        var map: [String: Any] = [:]
        for (k, d) in reviewDeliveries where k.hasPrefix(prefix) {
            let s = session(tabKey: d.session)
            map[String(k.dropFirst(prefix.count))] = ["state": d.state.rawValue, "name": d.sessionName, "status": s.map(reviewSessionStatus) ?? "not running",
                                                     "at": Self.clock(d.at), "why": d.why as Any, "session": d.session]
        }
        let first = reviewTarget(url, thread: "")
        let def: [String: Any] = first.map { ["name": $0.name, "status": reviewSessionStatus($0), "session": $0.tabKey] } ?? ["name": "New Session", "status": "", "session": ""]
        v.margin.setDelivery(map, def)
    }

    /// Where a thread's @claude send stands, in the panel's words: nil when it doesn't name @claude.
    public func pdfSendState(_ v: PdfViewer, thread id: String) -> String? {
        guard let url = v.url, let t = (try? Self.pdfReviewThreads(url))?.first(where: { $0.id == id }), t.comments.contains(where: \.mentionsClaude) else { return nil }
        if t.comments.contains(where: { $0.author == "claude" }) { return "Claude replied" }
        guard let d = reviewDeliveries[Self.reviewKey(url, id)] else { return "Not sent" }
        return d.state.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
