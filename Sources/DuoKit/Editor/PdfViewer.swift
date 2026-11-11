import AppKit
import DuoControl
import DuoSearch
import Observation
import PDFKit

/// A PDF in the right pane (DL-332): PDFKit's `PDFView` drawing the file read only, one page after another, with the
/// pages' own colours in dark too (DL-224). The controller owns the view and tells the bar and `duo2 pdf …` what is on
/// screen: the page, the zoom, the selection, the find. It reloads the file when it changes on disk (a comment written
/// by Duo, `.duoPdfChanged`, or another program), keeping the page and the zoom. PDFKit never saves the file (DL-335).
@MainActor @Observable
public final class PdfViewer: NSObject {
    public enum State: Equatable { case loading, ready, failed(String) }

    @ObservationIgnored public let pdfView: DuoPdfView
    public private(set) var url: URL?
    public private(set) var state: State = .loading
    /// The page on screen (from 1) and how many there are.
    public private(set) var page = 0
    public private(set) var count = 0
    /// The scale (1 is 100%), and whether it is fitting the pane's width.
    public private(set) var scale = 1.0
    public private(set) var fitting = true
    /// The selected text and the pages it covers (from 1), empty when nothing is selected.
    public private(set) var selectionText = ""
    public private(set) var selectionPages: ClosedRange<Int>?
    /// The find field and the matches it found.
    public var findText = ""
    public private(set) var matchCount = 0
    public private(set) var matchIndex = 0
    /// The comment threads, read from the file after each load (DL-335).
    public private(set) var threads: [PdfComments.Thread] = []
    /// The comment margin beside the pages (Geoff, 2026-11-10: built as Markdown review's margin, `PdfMargin`): on unless hidden.
    public var commentsShown = true { didSet { if oldValue != commentsShown { if !commentsShown { cancelCompose() }; pushMargin() } } }
    /// "n closed · Show": closed threads drawn as one line each in the margin.
    public var showClosed = false { didSet { if oldValue != showClosed { pushMargin() } } }
    /// The margin's page (the cards are Markdown's, `cards.js`).
    @ObservationIgnored public let margin = PdfMargin()
    /// A comment being composed in the margin: the selection it will be on, kept when the selection clears.
    public struct Composing: Equatable { public var page: Int; public var quads: [CGRect]; public var text: String }
    public private(set) var composing: Composing?
    /// The pane's width (the margin goes narrow under 420, as Markdown's does) and who comments.
    @ObservationIgnored public var paneWidth: CGFloat = 1000 { didSet { if oldValue != paneWidth { pushMargin() } } }
    @ObservationIgnored public var reviewer = NSUserName()
    /// Told when the selection starts or ends (the model's keyboard focus for Send Selection).
    @ObservationIgnored public var onSelection: ((Bool) -> Void)?

    @ObservationIgnored private var matches: [PDFSelection] = []
    @ObservationIgnored private var matched = ""
    @ObservationIgnored private var stamp: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var dormant = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var scrollObserver: NSObjectProtocol?
    @ObservationIgnored private weak var observedClip: NSClipView?
    @ObservationIgnored private var pushPending = false

    public override init() {
        pdfView = DuoPdfView(frame: .zero)
        super.init()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 5
        let nc = NotificationCenter.default
        func watch(_ name: Notification.Name, _ object: Any?, _ body: @escaping @MainActor (PdfViewer, String?) -> Void) {
            observers.append(nc.addObserver(forName: name, object: object, queue: .main) { [weak self] n in
                let path = n.userInfo?["path"] as? String
                MainActor.assumeIsolated { if let self { body(self, path) } }
            })
        }
        watch(.PDFViewPageChanged, pdfView) { v, _ in v.syncPage() }
        watch(.PDFViewScaleChanged, pdfView) { v, _ in v.syncScale(); v.pushMargin() }
        watch(.PDFViewVisiblePagesChanged, pdfView) { v, _ in v.pushMargin() }
        pdfView.postsFrameChangedNotifications = true
        watch(NSView.frameDidChangeNotification, pdfView) { v, _ in v.pushMargin() }
        pdfView.onClick = { [weak self] point in self?.clicked(at: point) }
        watch(.PDFViewSelectionChanged, pdfView) { v, _ in v.syncSelection() }
        watch(.duoPdfChanged, nil) { v, p in
            if let p, p == v.url?.path { v.reload() }
        }
        watch(DuoScheme.didChange, nil) { v, _ in v.pdfView.paint() }
    }

    // MARK: Opening

    /// Shows a PDF at its first page (or `page`). A file PDFKit can't open, or that needs a password, is `.failed` with why.
    public func open(_ file: URL, page start: Int = 1) {
        guard file.standardizedFileURL != url?.standardizedFileURL else { return }
        url = file
        findText = ""; clearFind()
        load(page: start, scale: nil)
        startWatching()
    }

    /// Reads the file again, keeping the page and the zoom (Duo also does this when the file changes).
    public func reload() {
        guard url != nil else { return }
        // Where the top of the window was, so a comment written to the file doesn't jump the view to the top of its page.
        var spot: (index: Int, point: CGPoint)?
        if let doc = pdfView.document, let d = pdfView.currentDestination, let p = d.page { spot = (doc.index(for: p), d.point) }
        load(page: max(page, 1), scale: fitting ? nil : scale, position: spot)
    }

    private func load(page start: Int, scale keep: Double?, position: (index: Int, point: CGPoint)? = nil) {
        guard let file = url else { return }
        stamp = Self.modified(file)
        guard let doc = PDFDocument(url: file) else {
            pdfView.document = nil
            state = .failed("it’s damaged, or isn’t a PDF"); page = 0; count = 0; threads = []; pushMargin(); return
        }
        if doc.isLocked {
            pdfView.document = nil
            state = .failed("it’s protected with a password"); page = 0; count = 0; threads = []; pushMargin(); return
        }
        pdfView.clearSelection()
        pdfView.document = doc
        count = doc.pageCount
        if let keep { pdfView.autoScales = false; pdfView.scaleFactor = keep } else { pdfView.autoScales = true }
        threads = (try? AppModel.pdfThreads(file)) ?? []
        matches = []; matchCount = 0; matchIndex = 0; matched = ""
        state = .ready
        let to = max(1, min(count, start))
        if let position, position.index < doc.pageCount, let p = doc.page(at: position.index) {
            pdfView.go(to: PDFDestination(page: p, at: position.point))
        } else if let p = doc.page(at: to - 1) { pdfView.go(to: PDFDestination(page: p, at: CGPoint(x: 0, y: p.bounds(for: .cropBox).maxY))) }
        page = to
        syncScale()
        syncSelection()
        pushMargin()
        // PDFKit lays the pages out a moment after the document is set: the highlights' places are read again then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in MainActor.assumeIsolated { self?.pushMargin() } }
    }

    // MARK: Moving and zooming

    /// Goes to a page (from 1), as ‹ › and `duo2 pdf page` do. Returns the page it went to.
    @discardableResult
    public func go(_ n: Int) -> Int {
        guard state == .ready, count > 0, let doc = pdfView.document else { return page }
        let to = max(1, min(count, n))
        if let p = doc.page(at: to - 1) { pdfView.go(to: PDFDestination(page: p, at: CGPoint(x: 0, y: p.bounds(for: .cropBox).maxY))) }
        page = to   // at once, so a second ‹ › counts from here; PDFKit confirms
        return to
    }

    /// Zoom steps by a quarter (25% to 500%).
    public func zoomIn() { setScale(scale * 1.25) }
    public func zoomOut() { setScale(scale / 1.25) }
    public func setScale(_ s: Double) {
        guard state == .ready else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = CGFloat(max(0.25, min(5, s)))
        syncScale()
    }
    /// Fits the pane's width again.
    public func fit() {
        guard state == .ready else { return }
        pdfView.autoScales = true
        syncScale()
    }

    // MARK: Finding

    /// Finds the match after the selection (or the first); the same text again steps on. Selects it and scrolls to it.
    @discardableResult
    public func find(_ text: String, backwards: Bool = false) -> (index: Int, of: Int, page: Int)? {
        guard state == .ready, let doc = pdfView.document else { return nil }
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { clearFind(); return nil }
        if q != matched {
            matches = doc.findString(q, withOptions: [.caseInsensitive])
            matched = q
            matchIndex = 0
            for m in matches { m.color = NSColor.findHighlightColor }
            pdfView.highlightedSelections = matches.isEmpty ? nil : matches
            matchCount = matches.count
            guard !matches.isEmpty else { return nil }
            // Start at the first match on or after the page on screen.
            matchIndex = matches.firstIndex { m in (m.pages.first.map { doc.index(for: $0) + 1 } ?? 1) >= page } ?? 0
        } else {
            guard !matches.isEmpty else { return nil }
            matchIndex = (matchIndex + (backwards ? matches.count - 1 : 1)) % matches.count
        }
        let m = matches[matchIndex]
        pdfView.setCurrentSelection(m, animate: true)
        pdfView.go(to: m)
        syncPage(); syncSelection()
        return (matchIndex + 1, matches.count, m.pages.first.map { doc.index(for: $0) + 1 } ?? page)
    }

    public func clearFind() {
        matches = []; matched = ""; matchCount = 0; matchIndex = 0
        pdfView.highlightedSelections = nil
    }

    // MARK: Selecting

    /// Selects the first match of `text` (for checks and `Go to`), without moving the find.
    public func select(text: String) -> Bool {
        guard let doc = pdfView.document, let m = doc.findString(text, withOptions: [.caseInsensitive]).first else { return false }
        pdfView.setCurrentSelection(m, animate: false)
        syncSelection()
        return true
    }

    /// The selection's page (the first it covers, from 1) and its lines' rectangles on that page, for a comment.
    public func selectionQuads() -> (page: Int, quads: [CGRect])? {
        guard let sel = pdfView.currentSelection, let doc = pdfView.document else { return nil }
        var first: PDFPage?
        var quads: [CGRect] = []
        for line in sel.selectionsByLine() {
            guard let p = line.pages.first else { continue }
            if first == nil { first = p }
            guard p === first else { continue }   // a comment sits on one page
            let b = line.bounds(for: p)
            if b.width > 0, b.height > 0 { quads.append(b) }
        }
        guard let first, !quads.isEmpty else { return nil }
        return (doc.index(for: first) + 1, quads)
    }

    /// Scrolls to a thread's page and outlines where it is.
    public func show(_ t: PdfComments.Thread) {
        guard let doc = pdfView.document, let p = doc.page(at: t.page - 1) else { return }
        let rect = t.rects.dropFirst().reduce(t.rects.first ?? .zero) { $0.union($1) }
        if rect.isEmpty { go(t.page); return }
        pdfView.go(to: rect.insetBy(dx: -4, dy: -40), on: p)
        let sels = t.rects.compactMap { p.selection(for: $0) }
        for s in sels { s.color = NSColor.findHighlightColor }
        pdfView.highlightedSelections = sels.isEmpty ? nil : sels
        syncPage()
    }

    public func refreshThreads() {
        if let u = url { threads = (try? AppModel.pdfThreads(u)) ?? []; pushMargin() }
    }

    // MARK: The margin (Markdown review's cards beside the pages)

    /// Where a rectangle (page space) sits in the pages' scrolling view, from its top: the card's anchor.
    private func documentY(page n: Int, rects: [CGRect]) -> CGFloat? {
        guard let doc = pdfView.document, let p = doc.page(at: n - 1), let dv = pdfView.documentView else { return nil }
        let boxes = rects.isEmpty ? [CGRect(x: 0, y: p.bounds(for: .cropBox).maxY - 20, width: 20, height: 20)] : rects
        var best: CGFloat?
        for r in boxes {
            let b = pdfView.convert(pdfView.convert(r, from: p), to: dv)
            let y = dv.isFlipped ? b.minY : dv.bounds.height - b.maxY
            best = min(best ?? y, y)
        }
        return best
    }

    /// How far the pages are scrolled.
    private func scrollTop() -> CGFloat {
        guard let dv = pdfView.documentView, let sv = dv.enclosingScrollView else { return 0 }
        let vis = sv.documentVisibleRect
        return dv.isFlipped ? vis.minY : dv.bounds.height - vis.maxY
    }

    /// The threads as the margin page takes them: `{ id, closed, y, comments: [{ author, date, text, closing }] }`.
    func marginThreads() -> [[String: Any]] {
        threads.map { t in
            var comments: [[String: Any]] = t.items.map {
                ["author": Review.signatureName($0.author), "date": $0.date.count >= 10 ? String($0.date.prefix(10)) : "", "text": $0.text, "closing": false]
            }
            if t.resolved { comments.append(["author": "", "date": "", "text": "", "closing": true]) }
            return ["id": t.id, "closed": t.resolved, "y": Double(documentY(page: t.page, rects: t.rects) ?? 0), "comments": comments]
        }
    }

    /// Sends the margin its threads, the pane's width and the scroll (coalesced: PDFKit posts many changes at once).
    func pushMargin() {
        guard !pushPending else { return }
        pushPending = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.pushMarginNow() } }
    }

    private func pushMarginNow() {
        pushPending = false
        bindScroll()
        let live = state == .ready && commentsShown
        margin.setState(threads: live ? marginThreads() : [], paneWidth: paneWidth, showClosed: showClosed, reviewer: Review.signatureName(reviewer))
        margin.setScroll(scrollTop())
        if live, let c = composing, let y = documentY(page: c.page, rects: c.quads) { margin.moveComposer(y: y) }
    }

    /// Follows the pages' scrolling so the cards move with them.
    private func bindScroll() {
        guard let clip = pdfView.documentView?.enclosingScrollView?.contentView, clip !== observedClip else { return }
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        clip.postsBoundsChangedNotifications = true
        observedClip = clip
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.margin.setScroll(self.scrollTop()) } }
        }
    }

    /// Add Comment: opens the composer in the margin level with the selection (Markdown's `composeComment`).
    @discardableResult
    public func compose() -> Bool {
        guard state == .ready, let at = selectionQuads() else { return false }
        commentsShown = true
        composing = Composing(page: at.page, quads: at.quads, text: SendFormat.line(selectionText))
        guard let y = documentY(page: at.page, rects: at.quads) else { return false }
        pushMarginNow()
        margin.compose(y: y)
        return true
    }

    public func cancelCompose() {
        guard composing != nil else { return }
        composing = nil
        margin.closeComposer()
    }

    /// The composer posted: it is done with the selection.
    func composed() { composing = nil; margin.closeComposer() }

    /// A click on a commented highlight opens its card (Markdown's anchor click).
    private func clicked(at point: CGPoint) {
        guard commentsShown, state == .ready, let p = pdfView.page(for: point, nearest: false), let doc = pdfView.document else { return }
        let n = doc.index(for: p) + 1, spot = pdfView.convert(point, to: p)
        if let t = threads.first(where: { $0.page == n && $0.rects.contains { $0.insetBy(dx: -1, dy: -1).contains(spot) } }), !t.resolved || showClosed {
            margin.activate(t.id)
        }
    }

    // MARK: Syncing with PDFKit

    private func syncPage() {
        guard let doc = pdfView.document, let p = pdfView.currentPage else { return }
        let n = doc.index(for: p) + 1
        if n != page { page = n }
    }

    private func syncScale() {
        let s = Double(pdfView.scaleFactor)
        if abs(s - scale) > 0.0001 { scale = s }
        if fitting != pdfView.autoScales { fitting = pdfView.autoScales }
    }

    private func syncSelection() {
        let had = !selectionText.isEmpty
        var text = ""
        var pages: ClosedRange<Int>?
        if let sel = pdfView.currentSelection, let doc = pdfView.document, let s = sel.string {
            text = s.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            let idx = sel.pages.map { doc.index(for: $0) }.filter { $0 != NSNotFound }.map { $0 + 1 }
            if let lo = idx.min(), let hi = idx.max() { pages = lo...hi }
        }
        if text != selectionText { selectionText = text }
        if selectionPages != pages { selectionPages = pages }
        if had != !text.isEmpty { onSelection?(!text.isEmpty) }
    }

    // MARK: Watching

    private func startWatching() {
        timer?.invalidate()
        guard !dormant else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.url, self.pdfView.window != nil else { return }
                let now = Self.modified(url)
                if now != self.stamp { self.reload() }
            }
        }.loose()
    }

    /// The pane stopped showing the PDF: no more polling the file.
    public func sleep() {
        dormant = true
        timer?.invalidate(); timer = nil
    }

    /// The pane shows it again: it reads the file again if it changed meanwhile.
    public func wake() {
        guard dormant else { return }
        dormant = false
        startWatching()
        if let url, Self.modified(url) != stamp { reload() }
    }

    nonisolated static func modified(_ u: URL) -> Date? { try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    // MARK: What Claude is told

    /// `From <path>, page N:` and the quoted text (DL-332), nil when nothing is selected.
    public func selectionPayload(path: String) -> String? {
        guard !selectionText.isEmpty, let pages = selectionPages else { return nil }
        return SendFormat.pdfSelection(selectionText, path: path, from: pages.lowerBound, to: pages.upperBound)
    }
}

/// The PDF view, on the pane's colour (the pages draw their own, DL-224).
public final class DuoPdfView: PDFView {
    /// The right-click menu's extra items (Send Selection, Add Comment), when text is selected.
    var extraMenuItems: (() -> [NSMenuItem])?
    /// A click, in this view's coordinates (a commented highlight opens its card).
    var onClick: ((CGPoint) -> Void)?
    public override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
    }
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let extra = extraMenuItems?() ?? []
        if !extra.isEmpty {
            menu.insertItem(.separator(), at: 0)
            for (i, item) in extra.enumerated() { menu.insertItem(item, at: i) }
        }
        return menu
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); paint() }
    func paint() {
        // Behind the pages: the same `ground` the deck viewer's empty frames sit on.
        backgroundColor = NSColor(DuoColor.ground)
    }
}
