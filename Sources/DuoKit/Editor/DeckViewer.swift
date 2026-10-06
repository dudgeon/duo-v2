import AppKit
import DuoSearch
import SwiftUI
import WebKit

/// A PowerPoint deck in the right pane (ENH-12, DL-121, DL-125; target pptx-handoff): drawn by the
/// vendored pptx-renderer (`Vendor/pptx-renderer`) in a web view, read only, redrawn when the file
/// changes. Duo and Claude know the slide on screen; the picker selects a shape by its OOXML id, so
/// what the user picks and `duo2 slide shapes` name the same shape. The page, the renderer and the
/// deck's bytes come through the `duo-deck:` scheme: nothing is loaded from the network.
@MainActor
public final class DeckViewer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public enum State: Equatable { case loading, ready, failed(String) }

    public let webView: DuoWebView
    public private(set) var url: URL?
    public private(set) var state: State = .loading
    /// The slide on screen (from 1), and how many there are.
    public private(set) var slide = 0
    public private(set) var count = 0
    /// The slide's size in slide pixels (96 per inch), for the box Claude is given.
    public private(set) var slideSize = CGSize(width: 1280, height: 720)
    public var picked: SendFormat.Element?
    public var pickedViewRect: CGRect?
    public var picking = false
    public var onChange: (() -> Void)?
    /// What the page's content security policy blocked (logged; checks expect none).
    public private(set) var blocked: [String] = []
    let resources: URL
    private var loaded = false
    private var pending: (() -> Void)?
    private var waiters: [() -> Void] = []
    private var stamp: Date?
    private var timer: Timer?

    static let scheme = "duo-deck"
    /// Where the page is when there's no app bundle around it (checks run from the checkout).
    nonisolated(unsafe) public static var defaultResources: URL?

    /// `resources` holds `deck.html`, `deck.js` and `pptx-renderer.js`: the app's
    /// `Resources/deck`, or `Vendor/pptx-renderer` in a checkout (checks).
    public init(resources: URL? = nil) {
        self.resources = resources ?? Self.defaultResources ?? Bundle.main.resourceURL?.appending(path: "deck") ?? URL(fileURLWithPath: "/nonexistent")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let proxy = SchemeProxy()
        config.setURLSchemeHandler(proxy, forURLScheme: Self.scheme)
        config.userContentController.addUserScript(WKUserScript(source: EditorController.tokenCSS(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        proxy.owner = self
        webView.configuration.userContentController.add(self, name: "duoDeck")
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://app/deck.html")!))
    }

    /// Shows a deck at `slide` (the first by default). A deck the renderer can't open, or that
    /// isn't a deck (password-protected, damaged), is `.failed` with why, in the user's words.
    public func open(_ file: URL, slide: Int = 1) {
        guard file.standardizedFileURL != url?.standardizedFileURL else { return }
        url = file
        load(slide: slide)
        startWatching()
    }

    /// Draws the file again, keeping the slide (Duo also does this when the file changes).
    public func reload() { load(slide: max(slide, 1)) }

    private func load(slide start: Int) {
        guard let file = url else { return }
        picked = nil; picking = false; count = 0; slide = 0
        stamp = Self.modified(file)
        if let why = Self.problem(file) {
            state = .failed(why); onChange?(); return
        }
        state = .loading
        onChange?()
        let name = file.lastPathComponent
        let run = { [weak self] in
            guard let self else { return }
            self.webView.callAsyncJavaScript("return __duo.open(n, s, v)", arguments: ["n": name, "s": start, "v": Int(Date().timeIntervalSince1970 * 1000)],
                                             in: nil, in: .page, completionHandler: nil)
        }
        if loaded { run() } else { pending = run }
    }

    /// Why a deck can't be drawn before trying: an encrypted .pptx is an OLE file, not a zip
    /// (that is how Office saves a password), and one whose zip or slide list won't read is damaged.
    nonisolated static func problem(_ file: URL) -> String? {
        guard let h = FileHandle(forReadingAtPath: file.path) else { return "Duo can’t read the file" }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 8)) ?? Data()
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return "it’s protected with a password" }
        if (try? Pptx.outline(file, slide: 0)) == nil { return "it’s damaged, or isn’t a PowerPoint deck" }
        return nil
    }

    /// Scrolls to a slide (from 1), as ‹ › and `duo2 slide go` do.
    public func go(_ n: Int) {
        guard state == .ready, count > 0 else { return }
        let to = max(1, min(count, n))
        slide = to   // at once, so a second ‹ › or `slide go next` counts from here; the page confirms
        webView.callAsyncJavaScript("return __duo.go(n)", arguments: ["n": to], in: nil, in: .page, completionHandler: nil)
        onChange?()
    }

    /// The picker's dashed outline on a shape, as if the pointer were over it (captures, B).
    public func hover(_ selector: String) {
        if !picking { startPicking() }
        webView.callAsyncJavaScript("return __duo.hover(s)", arguments: ["s": selector], in: nil, in: .page, completionHandler: nil)
    }

    /// Calls `then` once the deck is drawn or has failed (for `duo2` and checks).
    public func whenSettled(_ then: @escaping () -> Void) {
        if state != .loading { then() } else { waiters.append(then) }
    }

    /// Every shape the renderer drew: slide, id, name, type, groups (checks compare them with
    /// `Pptx.outline`).
    public func drawnShapes(_ done: @escaping @MainActor ([[String: Any]]) -> Void) {
        webView.callAsyncJavaScript("return __duo.shapes()", arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { done(v as? [[String: Any]] ?? []) } else { done([]) }
        }
    }

    // MARK: Watching

    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.url, self.webView.window != nil, !self.picking else { return }
                let now = Self.modified(url)
                if now != self.stamp { self.reload() }
            }
        }
    }

    nonisolated static func modified(_ u: URL) -> Date? { try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    // MARK: The page's messages

    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "loaded":
            loaded = true
            pending?(); pending = nil
            return
        case "ready":
            count = body["count"] as? Int ?? 0
            slide = body["slide"] as? Int ?? 1
            if let w = body["width"] as? Double, let h = body["height"] as? Double, w > 0, h > 0 { slideSize = CGSize(width: w, height: h) }
            state = .ready
            settle()
        case "failed":
            DuoLog.write("deck: the renderer couldn't draw \(url?.lastPathComponent ?? "?"): \(body["reason"] as? String ?? "")")
            state = .failed("it uses something the viewer can’t read")
            settle()
        case "slide":
            slide = body["slide"] as? Int ?? slide
        case "blocked":
            let what = body["what"] as? String ?? ""
            blocked.append(what)
            DuoLog.write("deck: the page's policy blocked \(what)")
            return
        case "picked", "pickEnded":
            handlePageMessage(message)
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

    // MARK: The duo-deck: scheme (the page, its scripts, the deck)

    fileprivate func serve(_ task: WKURLSchemeTask) {
        guard let u = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let name = u.lastPathComponent
        let file: URL?
        let type: String
        switch name {
        case "deck.html": file = resources.appending(path: name); type = "text/html"
        case "deck.js", "pptx-renderer.js": file = resources.appending(path: name); type = "text/javascript"
        case "deck.pptx": file = url; type = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
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
        // A link on a slide opens in the browser or mail; nothing else a deck names is opened.
        if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(target.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(target) }
        decisionHandler(.cancel)
    }

    /// The page itself didn't load (the app's copy is missing): say so rather than "Drawing…" forever.
    public func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError error: Error) {
        DuoLog.write("deck: the viewer's page didn't load: \(error.localizedDescription)")
        state = .failed("Duo’s viewer didn’t load")
        settle(); onChange?()
    }

    public var pageURL: URL? { url }
    public var world: WKContentWorld { .page }

    /// The picked shape, as the bar and Claude describe it.
    public var pickedShape: SendFormat.Shape? { picked.flatMap(shape) }

    /// A shape the page described (picked, or named by `<slide>/<id>`), with the deck's size.
    public func shape(_ e: SendFormat.Element) -> SendFormat.Shape? {
        guard let s = Int(e.attributes["slide"] ?? ""), let id = Int(e.attributes["id"] ?? "") else { return nil }
        return SendFormat.Shape(slide: s, count: count, id: id, name: e.label, type: e.attributes["type"] ?? "shape", groups: e.trail,
                                text: e.text, box: e.rect.map { Int($0) }, slideSize: [Int(slideSize.width.rounded()), Int(slideSize.height.rounded())])
    }
}

extension DeckViewer: PageHost {}

/// Holds the scheme handler weakly: WebKit keeps the handler for the view's life, which would
/// otherwise keep the viewer too.
private final class SchemeProxy: NSObject, WKURLSchemeHandler {
    weak var owner: DeckViewer?
    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        MainActor.assumeIsolated { if let owner { owner.serve(task) } else { task.didFailWithError(URLError(.cancelled)) } }
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}
