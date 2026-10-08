import AppKit
import DuoSearch
import SwiftUI
import WebKit

/// A Word document in the right pane (DL-162; target docx-handoff `viewer`, `markup`, `fallback`):
/// drawn by the vendored @file-viewer/docx (`Vendor/docx-viewer`) in a web view, read only, at the
/// pane's width and never paginated, with Duo's review layer over it (per-person colours, comment
/// cards, the label above a change, the four markup views). The page, the renderer and the
/// document's bytes come through the `duo-docx:` scheme: nothing is loaded from the network, and
/// nothing in this path opens the .docx for writing: the bytes are read once per draw and handed
/// to the page.
///
/// The web view's size never follows the document's height (the frame is the pane's, F-225,
/// F-226), nothing in the page watches layout, and a viewer that isn't on screen is dormant: no
/// timer, no redraw until it is shown again.
@MainActor
public final class DocxViewer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public enum State: Equatable { case loading, ready, failed(String) }

    /// The Markup menu's choices (W4), kept per document while Duo runs.
    public struct Markup: Equatable, Sendable {
        /// `all`, `simple`, `none` or `original`.
        public var mode = "all"
        public var comments = true
        /// Off: a resolved comment is one folded line (a click opens it); on: every one is open.
        public var resolved = false
        /// Only this person's marks; nil shows everyone.
        public var person: String?
        public init() {}
        public static let modes = ["all", "simple", "none", "original"]
        var json: [String: Any] { ["mode": mode, "comments": comments, "resolved": resolved, "person": person as Any] }
    }
    public struct Person: Equatable, Sendable {
        public var name: String
        /// 1 to 5: `reviewAuthor<n>`, in the order people first appear, then repeating.
        public var colour: Int
        /// Their tracked changes and comments.
        public var count: Int
    }
    public struct Comment: Equatable, Sendable {
        public var id: String, author: String, date: String, text: String, paragraph: String
        public var resolved: Bool, reply: Bool
    }

    public let webView: DuoWebView
    public private(set) var url: URL?
    public private(set) var state: State = .loading
    public private(set) var people: [Person] = []
    public private(set) var changeCount = 0
    public private(set) var comments: [Comment] = []
    /// Why Duo can't draw the document, and whether Claude can read it all the same.
    public private(set) var claudeCanRead = false
    public var markup = Markup() { didSet { if markup != oldValue { markupChanged() } } }
    /// Milliseconds from asking the page to draw to its saying it had (the long-document check).
    public private(set) var drawMillis = 0
    /// How many times the document has been drawn (asked of the page) since Duo started.
    public private(set) var draws = 0
    /// How many times the web view's frame changed size since the document opened (the layout-loop check).
    public private(set) var frameChanges = 0
    public var picked: SendFormat.Element?
    public var pickedViewRect: CGRect?
    public var picking = false
    public var onChange: (() -> Void)?
    private var outlineCache: (stamp: Date?, paragraphs: [Docx.Paragraph])?
    /// What the page's content security policy blocked (logged; checks expect none).
    public private(set) var blocked: [String] = []
    let resources: URL
    private var markupByDocument: [String: Markup] = [:]
    private var loaded = false
    private var pending: (() -> Void)?
    private var waiters: [() -> Void] = []
    private var stamp: Date?
    private var timer: Timer?
    private var deadline: Timer?
    private var drawStarted: Date?
    private var dormant = false
    private var stale = false
    private var lastFrame = CGSize.zero

    static let scheme = "duo-docx"
    /// How long the page may take before the viewer gives up and shows Quick Look.
    static let drawLimit: TimeInterval = 30
    /// Where the page is when there's no app bundle around it (checks run from the checkout).
    nonisolated(unsafe) public static var defaultResources: URL?

    /// `resources` holds `docx.html`, `docx.js`, `docx-preview.mjs` and `jszip.mjs`: the app's
    /// `Resources/docx`, or `Vendor/docx-viewer` in a checkout (checks).
    public init(resources: URL? = nil) {
        self.resources = resources ?? Self.defaultResources ?? Bundle.main.resourceURL?.appending(path: "docx") ?? URL(fileURLWithPath: "/nonexistent")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let proxy = SchemeProxy()
        config.setURLSchemeHandler(proxy, forURLScheme: Self.scheme)
        config.userContentController.addUserScript(WKUserScript(source: EditorController.tokenCSS(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: Self.reviewCSS(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        proxy.owner = self
        webView.configuration.userContentController.add(self, name: "duoDocx")
        webView.navigationDelegate = self
        webView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: webView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.webView.frame.size != self.lastFrame else { return }
                self.lastFrame = self.webView.frame.size
                self.frameChanges += 1
            }
        }
        loadPage()
    }

    private func loadPage() {
        loaded = false
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://app/docx.html")!))
    }

    /// The review colours as CSS variables on the page (docx-viewer-handoff: `reviewAuthor1…5`,
    /// `commentHighlight`), from the generated tokens.
    static func reviewCSS() -> String {
        func hex(_ c: NSColor) -> String {
            let s = c.usingColorSpace(.sRGB) ?? c
            return String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
        }
        let authors = [DuoNSColor.reviewAuthor1, DuoNSColor.reviewAuthor2, DuoNSColor.reviewAuthor3, DuoNSColor.reviewAuthor4, DuoNSColor.reviewAuthor5]
        var js = authors.enumerated().map { "s.setProperty('--duo-review-author-\($0.offset + 1)', '\(hex($0.element))');" }.joined(separator: " ")
        js += " s.setProperty('--duo-comment-highlight', '\(hex(DuoNSColor.commentHighlight))');"
        return "(() => { const s = document.documentElement.style; \(js) })();"
    }

    // MARK: Opening

    /// Shows a document with the markup it last had. One that can't be drawn (a password,
    /// damage, the old format, the renderer failing) is `.failed` with why, in the user's words.
    public func open(_ file: URL) {
        guard file.standardizedFileURL != url?.standardizedFileURL else { return }
        url = file
        markup = markupByDocument[Self.key(file)] ?? Markup()
        frameChanges = 0
        load(scroll: 0)
        startWatching()
    }

    /// Draws the file again, keeping the place (Duo also does this when the file changes).
    public func reload() {
        guard state == .ready, !dormant else { return load(scroll: 0) }
        webView.callAsyncJavaScript("return __duo.scroll()", arguments: [:], in: nil, in: .page) { [weak self] r in
            MainActor.assumeIsolated { if case .success(let v) = r { self?.load(scroll: (v as? Double) ?? 0) } else { self?.load(scroll: 0) } }
        }
    }

    private func load(scroll: Double) {
        guard let file = url else { return }
        stamp = Self.modified(file)
        stale = false
        picked = nil; picking = false; outlineCache = nil
        people = []; comments = []; changeCount = 0
        if let why = Self.problem(file) {
            claudeCanRead = false
            state = .failed(why); onChange?(); settle(); return
        }
        state = .loading
        onChange?()
        drawStarted = Date()
        draws += 1
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(withTimeInterval: Self.drawLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timedOut() }
        }
        let name = file.lastPathComponent
        let cfg = markup.json
        let run = { [weak self] in
            guard let self else { return }
            self.webView.callAsyncJavaScript("return __duo.open(n, v, c, y)",
                                             arguments: ["n": name, "v": Int(Date().timeIntervalSince1970 * 1000), "c": cfg, "y": scroll],
                                             in: nil, in: .page, completionHandler: nil)
        }
        if loaded { run() } else { pending = run }
    }

    /// The page took too long (a document that makes the renderer work for minutes): stop it by
    /// loading the page afresh, and show Quick Look.
    private func timedOut() {
        guard state == .loading else { return }
        DuoLog.write("docx: \(url?.lastPathComponent ?? "?") took more than \(Int(Self.drawLimit)) s to draw")
        state = .failed("it took too long to draw")
        claudeCanRead = url.map { Docx.readability($0) == nil } ?? false
        loadPage()
        settle(); onChange?()
    }

    /// Why a document can't be drawn, decided before trying: an encrypted .docx is an OLE file
    /// (Office's password), a damaged one's zip or document part won't read, and a .doc is the old
    /// format. Nothing here opens the file for writing.
    nonisolated public static func problem(_ file: URL) -> String? {
        if file.pathExtension.lowercased() == "doc" { return Docx.Failure.oldFormat.description }
        return Docx.readability(file)?.description
    }

    /// The Quick Look notice's second sentence applies when Claude can't read the document either.
    public var failureExtra: String? { claudeCanRead ? nil : "Claude can’t read it either." }

    // MARK: Markup (W4)

    private func markupChanged() {
        if let u = url { markupByDocument[Self.key(u)] = markup }
        guard state == .ready else { return onChange?() ?? () }
        webView.callAsyncJavaScript("return __duo.markup(c)", arguments: ["c": markup.json], in: nil, in: .page, completionHandler: nil)
        onChange?()
    }

    /// The markup a document has now, by file (the verb reads it for a document that isn't showing).
    public func markup(for file: URL) -> Markup { markupByDocument[Self.key(file)] ?? Markup() }
    static func key(_ u: URL) -> String { u.standardizedFileURL.path }

    /// A change under the pointer, as a capture needs it: its id or a bit of its text.
    public func hover(_ what: String) {
        webView.callAsyncJavaScript("return __duo.hover(w)", arguments: ["w": what], in: nil, in: .page, completionHandler: nil)
    }

    /// The picker's dashed outline on a paragraph or comment, as if the pointer were over it (captures).
    public func hoverPicker(_ selector: String) {
        if !picking { startPicking() }
        webView.callAsyncJavaScript("return __duo.hoverPara(s)", arguments: ["s": selector], in: nil, in: .page, completionHandler: nil)
    }

    /// Calls `then` once the document is drawn or has failed (for `duo2` and checks).
    public func whenSettled(_ then: @escaping () -> Void) {
        if state != .loading { then() } else { waiters.append(then) }
    }

    /// The paragraphs the renderer drew, by `data-office-target` (checks compare them with the outline).
    public func drawnParagraphs(_ done: @escaping @MainActor ([[String: Any]]) -> Void) {
        webView.callAsyncJavaScript("return __duo.paragraphs()", arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { done(v as? [[String: Any]] ?? []) } else { done([]) }
        }
    }

    /// What the page measured: how many sections it holds and its height, and how many times its
    /// layout changed since it drew (a loop would make this grow).
    public func pageStats(_ done: @escaping @MainActor ([String: Any]) -> Void) {
        webView.callAsyncJavaScript("return __duo.stats()", arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { done(v as? [String: Any] ?? [:]) } else { done([:]) }
        }
    }

    // MARK: Watching, and sleeping while not on screen

    private func startWatching() {
        timer?.invalidate()
        guard !dormant else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.url, self.webView.window != nil else { return }
                if Self.modified(url) != self.stamp { self.reload() }
            }
        }
    }

    /// The pane stopped showing the document: no more polling the file.
    public func sleep() {
        dormant = true
        timer?.invalidate(); timer = nil
    }

    /// The pane shows it again: it redraws if the file changed meanwhile.
    public func wake() {
        guard dormant else { return }
        dormant = false
        startWatching()
        if let url, Self.modified(url) != stamp { reload() }
    }

    nonisolated public static func modified(_ u: URL) -> Date? { try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    // MARK: The page's messages

    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "loaded":
            loaded = true
            pending?(); pending = nil
            return
        case "ready":
            deadline?.invalidate()
            if state == .loading {
                drawMillis = Int((drawStarted.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
                people = (body["people"] as? [[String: Any]] ?? []).map { Person(name: $0["name"] as? String ?? "", colour: $0["colour"] as? Int ?? 1, count: $0["count"] as? Int ?? 0) }
                changeCount = body["changes"] as? Int ?? 0
                comments = (body["comments"] as? [[String: Any]] ?? []).map {
                    Comment(id: $0["id"] as? String ?? "", author: $0["author"] as? String ?? "", date: $0["date"] as? String ?? "", text: $0["text"] as? String ?? "",
                            paragraph: $0["paragraph"] as? String ?? "", resolved: $0["resolved"] as? Bool ?? false, reply: $0["reply"] as? Bool ?? false)
                }
                state = .ready
                settle()
            }
        case "failed":
            deadline?.invalidate()
            DuoLog.write("docx: the renderer couldn't draw \(url?.lastPathComponent ?? "?"): \(body["reason"] as? String ?? "")")
            claudeCanRead = url.map { Docx.readability($0) == nil } ?? false
            state = .failed("it uses something the viewer can’t read")
            settle()
        case "picked", "pickEnded":
            handlePageMessage(message)
            return
        case "blocked":
            let what = body["what"] as? String ?? ""
            blocked.append(what)
            DuoLog.write("docx: the page's policy blocked \(what)")
            return
        default: return
        }
        onChange?()
    }

    private func settle() {
        let w = waiters
        waiters = []
        w.forEach { $0() }
    }

    // MARK: The duo-docx: scheme (the page, its scripts, the document)

    fileprivate func serve(_ task: WKURLSchemeTask) {
        guard let u = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let name = u.lastPathComponent
        let file: URL?
        let type: String
        switch name {
        case "docx.html": file = resources.appending(path: name); type = "text/html"
        case "docx.js", "docx-preview.mjs", "jszip.mjs": file = resources.appending(path: name); type = "text/javascript"
        case "doc.docx": file = url; type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default: file = nil; type = "text/plain"
        }
        guard let file, let data = try? Data(contentsOf: file, options: .mappedIfSafe) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        task.didReceive(HTTPURLResponse(url: u, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"])!)
        task.didReceive(data)
        task.didFinish()
    }

    // MARK: Navigation: only Duo's own page

    public func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { return decisionHandler(.cancel) }
        if target.scheme == Self.scheme || target.scheme == "about" { return decisionHandler(.allow) }
        // A link in a document opens in the browser or mail; nothing else a document names is opened.
        if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(target.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(target) }
        decisionHandler(.cancel)
    }

    /// The page itself didn't load (the app's copy is missing): say so rather than "Drawing…" forever.
    public func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError error: Error) {
        DuoLog.write("docx: the viewer's page didn't load: \(error.localizedDescription)")
        deadline?.invalidate()
        state = .failed("Duo’s viewer didn’t load")
        settle(); onChange?()
    }
}

/// Holds the scheme handler weakly: WebKit keeps the handler for the view's life, which would
/// otherwise keep the viewer too.
private final class SchemeProxy: NSObject, WKURLSchemeHandler {
    weak var owner: DocxViewer?
    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        MainActor.assumeIsolated { if let owner { owner.serve(task) } else { task.didFailWithError(URLError(.cancelled)) } }
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}

extension DocxViewer: PageHost {
    public var pageURL: URL? { url }
    public var world: WKContentWorld { .page }

    /// The document's paragraphs from the file (`Docx.outline`), read once per version of the file.
    public func paragraphs() -> [Docx.Paragraph] {
        guard let url else { return [] }
        let stamp = Self.modified(url)
        if let c = outlineCache, c.stamp == stamp { return c.paragraphs }
        let p = (try? Docx.outline(url)) ?? []
        outlineCache = (stamp, p)
        return p
    }

    /// The paragraph the picker holds (a picked comment's is the one it's on).
    public var pickedParagraph: Docx.Paragraph? {
        guard let id = picked?.attributes["paraId"] else { return nil }
        return paragraphs().first { $0.id == id }
    }

    /// A picked comment's thread (its root id), or nil for a paragraph.
    public var pickedThread: String? {
        guard picked?.attributes["kind"] == "comment", let c = picked?.attributes["comment"], let p = pickedParagraph else { return nil }
        return p.comments.first { $0.id == c }?.thread ?? c
    }

    public var pickedKind: String { picked?.attributes["kind"] ?? "paragraph" }
}
