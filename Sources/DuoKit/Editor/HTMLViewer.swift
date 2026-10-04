import AppKit
import SwiftUI
import WebKit

/// Local HTML in the right pane (v1 "local HTML viewing", DL-67): read-only, reloaded when the
/// file or its neighbours change, links to other sites open in the browser (local-only by
/// default, DL-3). The page can send its selection, or a picked element, to Claude (DL-67–DL-70).
@MainActor
public final class HTMLViewer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: DuoWebView
    public private(set) var url: URL?
    /// The element the picker froze, waiting for Send or Cancel.
    public private(set) var picked: SendFormat.Element?
    private var pickedViewRect: CGRect?
    public private(set) var picking = false
    /// Called when picking state changes (the native bar shows and hides).
    var onChange: (() -> Void)?
    private var root: URL?
    private var stamp: Date?
    private var timer: Timer?

    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: HTMLPicker.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "duoPage")
        webView.navigationDelegate = self
    }

    /// Shows a file; `root` is the folder the page may read (its project).
    public func open(_ file: URL, root: URL) {
        guard file.standardizedFileURL != url?.standardizedFileURL else { return }
        url = file
        self.root = root
        picked = nil
        picking = false
        stamp = Self.newest(around: file)
        webView.loadFileURL(file, allowingReadAccessTo: root)
        startWatching()
        onChange?()
    }

    public func reload() { webView.reload() }

    // MARK: Watching

    /// Polls once a second while a page is open: the page's own file, and the styles, scripts and
    /// images next to it, so editing any of them shows straight away.
    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.url, self.webView.window != nil else { return }
                let now = Self.newest(around: url)
                if now != self.stamp, !self.picking { self.stamp = now; self.webView.reload() }
            }
        }
    }

    static func newest(around file: URL) -> Date? {
        let dir = file.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let watched = names.filter { ["html", "htm", "css", "js", "svg", "png", "jpg", "jpeg", "gif", "webp", "json"].contains($0.pathExtension.lowercased()) }
        return (watched + [file]).compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    // MARK: Navigation

    public func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { return decisionHandler(.cancel) }
        if target.isFileURL, let root, target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) {
            return decisionHandler(.allow)
        }
        if target.scheme == "about" { return decisionHandler(.allow) }
        // Anything else leaves Duo: the browser in the right pane comes later (Phase K).
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(target) }
        decisionHandler(.cancel)
    }

    // MARK: The page's selection and the picker

    /// The page's selection (text and images), or nil when nothing is selected.
    public func selection(_ done: @escaping @MainActor ([String: Any]?) -> Void) {
        webView.callAsyncJavaScript("return window.__duo ? __duo.selection() : null", arguments: [:], in: nil, in: .page) { r in
            if case .success(let v) = r { done(v as? [String: Any]) } else { done(nil) }
        }
    }

    public func startPicking() {
        picked = nil
        picking = true
        webView.evaluateJavaScript("window.__duo && __duo.start()")
        webView.window?.makeFirstResponder(webView)
        onChange?()
    }

    public func stopPicking() {
        picked = nil
        picking = false
        webView.evaluateJavaScript("window.__duo && __duo.stop()")
        onChange?()
    }

    /// Pick another element after one was frozen.
    public func pickAgain() {
        picked = nil
        webView.evaluateJavaScript("window.__duo && __duo.unfreeze()")
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
            self.webView.callAsyncJavaScript("window.__duo && (__duo.start(), __duo.freeze(s))", arguments: ["s": selector], in: nil, in: .page, completionHandler: nil)
            self.onChange?()
            done?(true)
        }
    }

    /// Describes the element a CSS selector names (for `duo2`), without the picker.
    public func describe(selector: String, _ done: @escaping @MainActor (SendFormat.Element?, CGRect?) -> Void) {
        webView.callAsyncJavaScript("return window.__duo ? __duo.describe(s) : null", arguments: ["s": selector], in: nil, in: .page) { r in
            guard case .success(let v) = r, let d = v as? [String: Any] else { return done(nil, nil) }
            done(Self.element(d), Self.viewRect(d))
        }
    }

    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "picked":
            guard let d = body["element"] as? [String: Any] else { return }
            picked = Self.element(d)
            pickedViewRect = Self.viewRect(d)
        case "pickEnded":
            picked = nil
            picking = false
        default: return
        }
        onChange?()
    }

    /// Saves a picture of the element (the outline hidden) as a PNG Claude can read, and returns
    /// its path. The page coordinates are the view's: WKWebView is flipped like the page.
    public func screenshot(rect: CGRect?, _ done: @escaping @MainActor (String?) -> Void) {
        guard let rect = rect ?? pickedViewRect, rect.width >= 1, rect.height >= 1 else { return done(nil) }
        webView.evaluateJavaScript("window.__duo && __duo.hideOutline()") { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return done(nil) }
                let config = WKSnapshotConfiguration()
                config.rect = rect.intersection(self.webView.bounds)
                self.webView.takeSnapshot(with: config) { image, _ in
                    MainActor.assumeIsolated {
                        self.webView.evaluateJavaScript("window.__duo && __duo.showOutline()")
                        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) else { return done(nil) }
                        let dir = DuoPaths.support.appending(path: "context")
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        let f = DateFormatter()
                        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
                        let file = dir.appending(path: "element-\(f.string(from: Date())).png")
                        do { try png.write(to: file); done(file.path) } catch { done(nil) }
                    }
                }
            }
        }
    }

    static func element(_ d: [String: Any]) -> SendFormat.Element? {
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        return try? JSONDecoder().decode(SendFormat.Element.self, from: data)
    }

    static func viewRect(_ d: [String: Any]) -> CGRect? {
        guard let r = d["viewRect"] as? [Double], r.count == 4 else { return nil }
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }
}

/// A web view whose right-click menu Duo extends (Send to Claude, Select Element), for the
/// editor and HTML pages alike.
public class DuoWebView: WKWebView {
    /// Items to put at the top of the context menu; `hasSelection` is whether WebKit offered Copy.
    var extraMenuItems: ((_ hasSelection: Bool, _ onImage: Bool) -> [NSMenuItem])?
    /// Told when the keyboard arrives or leaves, so menus that depend on it (Format, Send
    /// Selection) re-validate: reading the first responder when menus last rendered left
    /// Bold and Italic disabled while the editor had focus.
    var onFocusChange: ((Bool) -> Void)?

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.reportFocus() } } }
        return ok
    }

    /// WKWebView hands focus to inner views; ask the window where it really is.
    func reportFocus() {
        guard let r = window?.firstResponder as? NSView else { onFocusChange?(false); return }
        onFocusChange?(r === self || r.isDescendant(of: self))
    }

    public override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        let ids = menu.items.compactMap { $0.identifier?.rawValue }
        let hasSelection = ids.contains("WKMenuItemIdentifierCopy")
        let onImage = ids.contains("WKMenuItemIdentifierCopyImage")
        guard let items = extraMenuItems?(hasSelection, onImage), !items.isEmpty else { return }
        // Duo's Reload Page replaces WebKit's own Reload (they did the same thing, twice).
        for item in menu.items where item.identifier?.rawValue == "WKMenuItemIdentifierReload" { menu.removeItem(item) }
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        menu.insertItem(.separator(), at: items.count)
    }
}

/// An NSMenuItem that runs a closure.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, enabled: Bool = true, _ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("unused") }

    @objc private func fire() { handler() }
}

/// The right pane's view of an HTML file, with the picker's bar when an element is frozen.
struct HTMLViewerView: NSViewRepresentable {
    let viewer: HTMLViewer
    let file: URL
    let root: URL

    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }

    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) {
        host.show(viewer.webView)
        viewer.open(file, root: root)
    }
}
