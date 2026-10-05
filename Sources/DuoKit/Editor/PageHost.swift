import AppKit
import WebKit

/// A web page Duo shows in the right pane, local HTML (`HTMLViewer`) or a browser tab (`WebTab`):
/// both get the page's selection, the element picker (LR-44) and element screenshots, so Send to
/// Claude and `duo2 html …` work on either. Duo's picker script runs in `world`: the page's own
/// world for local HTML, an isolated one for other sites, so their scripts can't see or fake it.
@MainActor
public protocol PageHost: AnyObject {
    var webView: DuoWebView { get }
    var pageURL: URL? { get }
    var world: WKContentWorld { get }
    var picked: SendFormat.Element? { get set }
    var pickedViewRect: CGRect? { get set }
    var picking: Bool { get set }
    var onChange: (() -> Void)? { get }
    func reload()
}

extension PageHost {
    /// The page's selection (text and images), or nil when nothing is selected.
    public func selection(_ done: @escaping @MainActor ([String: Any]?) -> Void) {
        webView.callAsyncJavaScript("return window.__duo ? __duo.selection() : null", arguments: [:], in: nil, in: world) { r in
            if case .success(let v) = r { done(v as? [String: Any]) } else { done(nil) }
        }
    }

    public func startPicking() {
        picked = nil
        picking = true
        webView.callAsyncJavaScript("window.__duo && __duo.start()", arguments: [:], in: nil, in: world, completionHandler: nil)
        webView.window?.makeFirstResponder(webView)
        onChange?()
    }

    public func stopPicking() {
        picked = nil
        picking = false
        webView.callAsyncJavaScript("window.__duo && __duo.stop()", arguments: [:], in: nil, in: world, completionHandler: nil)
        onChange?()
    }

    /// Pick another element after one was frozen.
    public func pickAgain() {
        picked = nil
        webView.callAsyncJavaScript("window.__duo && __duo.unfreeze()", arguments: [:], in: nil, in: world, completionHandler: nil)
        onChange?()
    }

    /// Freezes the element a CSS selector names, as if it had been clicked in the picker
    /// (`duo2 html pick`, and checks).
    public func pick(selector: String, _ done: (@MainActor (Bool) -> Void)? = nil) {
        describe(selector: selector) { [weak self] e, rect in
            guard let self, let e else { done?(false); return }
            self.picking = true
            self.picked = e
            self.pickedViewRect = rect
            self.webView.callAsyncJavaScript("window.__duo && (__duo.start(), __duo.freeze(s))", arguments: ["s": selector], in: nil, in: self.world, completionHandler: nil)
            self.onChange?()
            done?(true)
        }
    }

    /// Describes the element a CSS selector names (for `duo2`), without the picker.
    public func describe(selector: String, _ done: @escaping @MainActor (SendFormat.Element?, CGRect?) -> Void) {
        webView.callAsyncJavaScript("return window.__duo ? __duo.describe(s) : null", arguments: ["s": selector], in: nil, in: world) { r in
            guard case .success(let v) = r, let d = v as? [String: Any] else { return done(nil, nil) }
            done(HTMLViewer.element(d), HTMLViewer.viewRect(d))
        }
    }

    /// The picker script's messages: an element frozen, or picking ended.
    func handlePageMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "picked":
            guard let d = body["element"] as? [String: Any] else { return }
            picked = HTMLViewer.element(d)
            pickedViewRect = HTMLViewer.viewRect(d)
        case "pickEnded":
            picked = nil
            picking = false
        default: return
        }
        onChange?()
    }

    /// Saves a picture of the element (the outline hidden), or of the visible page with no rect,
    /// as a PNG Claude can read, and returns its path. The view is flipped like the page.
    public func screenshot(rect: CGRect?, whole: Bool = false, _ done: @escaping @MainActor (String?) -> Void) {
        let target: CGRect
        if whole { target = webView.bounds } else {
            guard let r = rect ?? pickedViewRect, r.width >= 1, r.height >= 1 else { return done(nil) }
            target = r
        }
        webView.callAsyncJavaScript("window.__duo && __duo.hideOutline()", arguments: [:], in: nil, in: world) { [weak self] _ in
            guard let self else { return done(nil) }
            let config = WKSnapshotConfiguration()
            config.rect = target.intersection(self.webView.bounds)
            self.webView.takeSnapshot(with: config) { image, _ in
                MainActor.assumeIsolated {
                    self.webView.callAsyncJavaScript("window.__duo && __duo.showOutline()", arguments: [:], in: nil, in: self.world, completionHandler: nil)
                    guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return done(nil) }
                    let dir = DuoPaths.support.appending(path: "context")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let f = DateFormatter()
                    f.dateFormat = "yyyyMMdd-HHmmss-SSS"
                    let file = dir.appending(path: "\(whole ? "page" : "element")-\(f.string(from: Date())).png")
                    do { try png.write(to: file); done(file.path) } catch { done(nil) }
                }
            }
        }
    }
}

extension HTMLViewer: PageHost {}
