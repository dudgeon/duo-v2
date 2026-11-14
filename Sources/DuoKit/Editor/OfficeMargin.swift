import AppKit
import DuoControl
import DuoSearch
import Observation

/// The comment margin beside a Word or PowerPoint file (DL-337; Geoff, 2026-11-10 and 11): Markdown review's margin, the one the PDF
/// viewer uses too (`SideMargin`, Vendor/codemirror/src/side-margin.js, over `Cards`), in a small page of its own. The viewer's page
/// says where each thread's anchor is (`y`) and how far it is scrolled; this class sends the margin its threads, read from the file's
/// own comment parts (`OfficeComments`), and the margin's actions come back to the model (`AppModel+OfficeMargin`), which writes the
/// file through the same calls `duo2 comment …` makes.
@MainActor @Observable
public final class OfficeMargin {
    @ObservationIgnored public let margin: PdfMargin
    /// Comments are on unless the Markup menu hides them.
    public var commentsShown = true { didSet { if oldValue != commentsShown { if !commentsShown { cancelCompose() }; push() } } }
    /// "n closed · Show": closed threads drawn folded.
    public var showClosed = false { didSet { if oldValue != showClosed { push(); onShowClosed?(showClosed) } } }
    /// Observed: the viewers' bars change under 420 (Review ⌄ in place of ‹ ›).
    public var paneWidth: CGFloat = 1000 { didSet { if oldValue != paneWidth { push() } } }
    @ObservationIgnored public private(set) var threads: [OfficeComments.Thread] = []
    @ObservationIgnored public var reviewer = NSUserName()
    /// The margin replaces the cards the Word page draws under paragraphs (DL-337); DuoChecks turns this off to check that older layer's logic.
    @ObservationIgnored public var replacesPageCards = true

    /// What the host (the viewer) provides.
    @ObservationIgnored public var fileURL: () -> URL? = { nil }
    /// Where each thread's anchor is, in the page's coordinates: `[{ id, y }]`.
    @ObservationIgnored public var queryAnchors: (@escaping ([[String: Any]]) -> Void) -> Void = { $0([]) }
    /// The selection a new comment would be on: its `--at` candidates (tried in order) and its y.
    @ObservationIgnored public var querySelection: (@escaping (Selection?) -> Void) -> Void = { $0(nil) }
    /// Lights a thread's anchor in the page (the active card's), nil for none.
    @ObservationIgnored public var lightAnchor: (String?) -> Void = { _ in }
    /// A card under the pointer: its anchor takes the active fill until the pointer leaves.
    @ObservationIgnored public var hoverAnchor: (String?) -> Void = { _ in }
    @ObservationIgnored public var onShowClosed: ((Bool) -> Void)?
    /// Scrolls the page so an anchor at `y` is in view.
    @ObservationIgnored public var scrollTo: (Double) -> Void = { _ in }
    /// The viewer draws what each thread is on (PowerPoint: text highlighted, a shape outlined, the slide's number boxed).
    @ObservationIgnored public var threadsChanged: ([OfficeComments.Thread]) -> Void = { _ in }

    public struct Selection { public var at: [String]; public var y: Double; public var text: String
        public init(at: [String], y: Double, text: String) { self.at = at; self.y = y; self.text = text } }
    /// A comment being composed: where it will go.
    @ObservationIgnored public private(set) var composing: Selection?

    /// A thread made just now: its card becomes the active one as soon as the margin has it and the page has its anchor.
    @ObservationIgnored public var pendingActive: String?
    @ObservationIgnored private var scrollTop: Double = 0
    @ObservationIgnored private var pushPending = false
    @ObservationIgnored private var lastY: [String: Double] = [:]

    public init(kind: String) { margin = PdfMargin(kind: kind) }

    // MARK: The threads

    /// Reads the file's threads again and tells the margin.
    public func refresh() {
        guard let u = fileURL() else { threads = []; push(); return }
        threads = (try? OfficeComments.threads(u)) ?? []
        threadsChanged(threads)
        push()
    }

    public func clear() { activeID = nil; threads = []; composing = nil; push() }

    /// `{ id, closed, y, comments }`: what the margin page takes (as `PdfViewer.marginThreads`).
    func marginThreads(_ y: [String: Double]) -> [[String: Any]] {
        threads.map { t in
            var comments: [[String: Any]] = t.items.map {
                ["author": Review.signatureName($0.author), "date": $0.date.count >= 10 ? String($0.date.prefix(10)) : "", "text": $0.text, "closing": false]
            }
            if t.resolved { comments.append(["author": "", "date": "", "text": "", "closing": true]) }
            return ["id": t.id, "closed": t.resolved, "y": y[t.id] ?? lastY[t.id] ?? 0, "comments": comments]
        }
    }

    /// Sends the margin its threads, the pane's width and the scroll (coalesced).
    public func push() {
        guard !pushPending else { return }
        pushPending = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.pushNow() } }
    }

    private func pushNow() {
        pushPending = false
        let live = commentsShown
        guard live, !threads.isEmpty || composing != nil else {
            margin.setState(threads: [], paneWidth: paneWidth, showClosed: showClosed, reviewer: Review.signatureName(reviewer)); return
        }
        queryAnchors { [weak self] anchors in
            guard let self else { return }
            var y: [String: Double] = [:]
            for a in anchors { if let id = a["id"] as? String, let v = a["y"] as? Double { y[id] = v } }
            self.lastY = y
            self.margin.setState(threads: self.marginThreads(y), paneWidth: self.paneWidth, showClosed: self.showClosed, reviewer: Review.signatureName(self.reviewer))
            self.margin.setScroll(CGFloat(self.scrollTop))
            if let c = self.composing { self.margin.moveComposer(y: CGFloat(c.y)) }
            if let id = self.pendingActive, y[id] != nil, self.threads.contains(where: { $0.id == id }) {
                self.pendingActive = nil
                self.margin.activate(id)
                self.lightAnchor(id)
            }
        }
    }

    /// ‹ › and `duo2 doc review next|previous`: the next or previous comment in the file, in reading order (closed ones only when shown).
    /// Returns where it landed ("n of m") or nil when there is nothing to step to.
    @discardableResult
    public func step(_ d: Int) -> String? {
        let shown = threads.filter { !$0.resolved || showClosed }.sorted { (lastY[$0.id] ?? 0) < (lastY[$1.id] ?? 0) }
        guard !shown.isEmpty, commentsShown else { return nil }
        let at = shown.firstIndex { $0.id == activeID }
        let next = at.map { ($0 + d + shown.count) % shown.count } ?? (d > 0 ? 0 : shown.count - 1)
        let t = shown[next]
        activeID = t.id
        margin.activate(t.id)
        lightAnchor(t.id)
        scrollTo(max(0, (lastY[t.id] ?? 0) - 80))
        return "comment \(next + 1) of \(shown.count): #\(t.id)"
    }
    @ObservationIgnored public var activeID: String?

    public func scrolled(_ y: Double) { scrollTop = y; margin.setScroll(CGFloat(y)) }

    // MARK: Composing

    /// Add Comment: the composer opens in the margin level with the selection (nothing selected: the host's `whole`, the slide).
    @discardableResult
    public func compose(whole: Selection? = nil, done: @escaping (Bool) -> Void = { _ in }) -> Bool {
        querySelection { [weak self] sel in
            guard let self, let at = sel ?? whole else { done(false); return }
            self.commentsShown = true
            self.composing = at
            self.pushNow()
            self.margin.compose(y: CGFloat(at.y))
            done(true)
        }
        return true
    }

    public func cancelCompose() {
        guard composing != nil else { return }
        composing = nil
        margin.closeComposer()
    }

    /// The composer posted: done with the selection.
    public func composed() { composing = nil; margin.closeComposer() }
}
