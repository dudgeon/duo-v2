import AppKit
import Observation
import WebKit

/// The margin beside a PDF: Markdown review's margin (Vendor/codemirror/src/margin.js and cards.js) in a small web page of
/// its own (`side-margin.html`), so a PDF's comments look and work as a Markdown document's do (Geoff, 2026-11-10): every open
/// thread a card level with its highlight, always visible, the active card with its reply field, Close and Keep / Delete,
/// closed threads folded into "n closed · Show", a gutter and popover when the pane is narrow, @claude's delivery lines and
/// pill, and the composer card with the `@` menu. The page draws; Swift owns the PDF: it says where each highlight is on the
/// document (`y`) and how far the PDF is scrolled, and the page reports what was done (`pdfMargin` messages).
@MainActor @Observable
public final class PdfMargin: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    @ObservationIgnored public let webView: DuoWebView
    /// How wide the page wants to be (0 with no comments), and how much of that the PDF gives up: a narrow pane's popover
    /// floats over the pages.
    public private(set) var width: CGFloat = 0
    public private(set) var reserve: CGFloat = 0
    /// What the page did: "post", "reply", "close", "reopen", "delete", "send", "retry", "pill", "showClosed", "cancel", "escaped", "active", "error".
    @ObservationIgnored public var onAction: ((String, [String: Any]) -> Void)?
    @ObservationIgnored private var ready = false
    /// The page is up and takes calls.
    public var isReady: Bool { ready }
    @ObservationIgnored private var queued: [String] = []

    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = PdfMarginWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "duo")
        webView.configuration.userContentController.addUserScript(WKUserScript(source: EditorController.tokenCSS(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.configuration.userContentController.addUserScript(WKUserScript(source: "window.duoMarginKind = \"pdfMargin\";", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        // DuoChecks has no app bundle: it names the built page's folder (Vendor/codemirror/dist), as the editor does.
        let override = ProcessInfo.processInfo.environment["DUO_EDITOR_DIR"].map { URL(fileURLWithPath: $0) }
        if let dir = override ?? Bundle.main.resourceURL?.appending(path: "editor"),
           FileManager.default.fileExists(atPath: dir.appending(path: "side-margin.html").path) {
            webView.loadFileURL(dir.appending(path: "side-margin.html"), allowingReadAccessTo: dir)
        }
    }

    public func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: Any], body["kind"] as? String == "pdfMargin", let op = body["op"] as? String else { return }
        switch op {
        case "ready":
            ready = true
            for js in queued { webView.evaluateJavaScript(js, completionHandler: nil) }
            queued = []
        case "width":
            let w = CGFloat((body["w"] as? Double) ?? 0), r = CGFloat((body["reserve"] as? Double) ?? 0)
            if w != width { width = w }
            if r != reserve { reserve = r }
        case "error":
            DuoLog.write("pdf margin: \(body["what"] ?? "?"): \(body["message"] ?? "")")
        default:
            onAction?(op, body)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        DuoLog.write("pdf margin: web content process terminated")
        ready = false
        webView.reload()
        onAction?("crashed", [:])
    }

    // MARK: Telling the page

    /// Runs `duoSideMargin.<call>` once the page is up (calls made before are kept, in order).
    private func call(_ js: String) {
        if ready { webView.evaluateJavaScript(js, completionHandler: nil) } else { queued.append(js) }
    }

    private static func literal(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject([v]), let d = try? JSONSerialization.data(withJSONObject: [v]), let s = String(data: d, encoding: .utf8) else { return "null" }
        return String(s.dropFirst().dropLast())
    }

    /// The threads (see `PdfViewer.marginThreads`), the pane's width and who is commenting.
    public func setState(threads: [[String: Any]], paneWidth: CGFloat, showClosed: Bool, reviewer: String) {
        let s: [String: Any] = ["threads": threads, "paneWidth": Double(paneWidth), "showClosed": showClosed, "reviewer": reviewer]
        call("window.duoSideMargin && duoSideMargin.setState(\(Self.literal(s)))")
    }
    public func setScroll(_ y: CGFloat) { call("window.duoSideMargin && duoSideMargin.setScroll(\(Double(y)))") }
    public func setDelivery(_ map: [String: Any], _ def: [String: Any]) {
        call("window.duoSideMargin && duoSideMargin.setDelivery(\(Self.literal(map)), \(Self.literal(def)))")
    }
    public func compose(y: CGFloat) { call("window.duoSideMargin && duoSideMargin.compose(\(Double(y)))") }
    public func moveComposer(y: CGFloat) { call("window.duoSideMargin && duoSideMargin.moveComposer(\(Double(y)))") }
    public func closeComposer() { call("window.duoSideMargin && duoSideMargin.closeComposer()") }
    public func activate(_ id: String?) { call("window.duoSideMargin && duoSideMargin.activate(\(id.map(Self.literal) ?? "null"))") }

    /// Runs script in the page and hands back its value (for checks and `duo2`).
    public func evaluate(_ js: String, done: @escaping @MainActor (Any?) -> Void) {
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { done(v) } else { done(nil) }
        }
    }
}

/// The margin page's colours follow the appearance, live (DL-224), as the editor's do.
final class PdfMarginWebView: DuoWebView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        evaluateJavaScript(EditorController.tokenCSS(), completionHandler: nil)
    }
}
