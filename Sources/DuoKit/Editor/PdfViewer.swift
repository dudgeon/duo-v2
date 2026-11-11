import AppKit
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
    /// The stand-in comments panel (Q-496), off until asked for.
    public var commentsOpen = false
    /// Told when the selection starts or ends (the model's keyboard focus for Send Selection).
    @ObservationIgnored public var onSelection: ((Bool) -> Void)?

    @ObservationIgnored private var matches: [PDFSelection] = []
    @ObservationIgnored private var matched = ""
    @ObservationIgnored private var stamp: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var dormant = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

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
        watch(.PDFViewScaleChanged, pdfView) { v, _ in v.syncScale() }
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
        load(page: max(page, 1), scale: fitting ? nil : scale)
    }

    private func load(page start: Int, scale keep: Double?) {
        guard let file = url else { return }
        stamp = Self.modified(file)
        guard let doc = PDFDocument(url: file) else {
            pdfView.document = nil
            state = .failed("it’s damaged, or isn’t a PDF"); page = 0; count = 0; threads = []; return
        }
        if doc.isLocked {
            pdfView.document = nil
            state = .failed("it’s protected with a password"); page = 0; count = 0; threads = []; return
        }
        pdfView.clearSelection()
        pdfView.document = doc
        count = doc.pageCount
        if let keep { pdfView.autoScales = false; pdfView.scaleFactor = keep } else { pdfView.autoScales = true }
        threads = (try? AppModel.pdfThreads(file)) ?? []
        matches = []; matchCount = 0; matchIndex = 0; matched = ""
        state = .ready
        let to = max(1, min(count, start))
        if let p = doc.page(at: to - 1) { pdfView.go(to: PDFDestination(page: p, at: CGPoint(x: 0, y: p.bounds(for: .cropBox).maxY))) }
        page = to
        syncScale()
        syncSelection()
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

    /// Scrolls to a thread's page and outlines where it is (the stand-in panel's Go to).
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
        if let u = url { threads = (try? AppModel.pdfThreads(u)) ?? [] }
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
