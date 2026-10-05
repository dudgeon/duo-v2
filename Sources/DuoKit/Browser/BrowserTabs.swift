import AppKit
import SwiftUI
import WebKit

/// Sites allowed in Duo's own browser tabs (DL-3): local-only by default, so everything else opens
/// in the system browser unless its host is on this list. The list is a plain file the user can
/// edit, one host per line (`#` comments); a host also allows its subdomains.
public enum AllowedSites {
    public static var file: URL { DuoPaths.support.appending(path: "allowed-sites.txt") }

    public static func load(_ url: URL = file) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n")
            .map { $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    public static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.isFileURL }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) || host.hasSuffix(".localhost")
    }

    public static func allows(_ url: URL, list: [String]? = nil) -> Bool {
        if url.isFileURL || isLocal(url) { return true }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return false }
        return (list ?? load()).contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Adds a host (without `www.`), keeping the file's own lines and comments.
    @discardableResult
    public static func add(_ host: String, to url: URL = file) -> Bool {
        let h = host.lowercased().hasPrefix("www.") ? String(host.lowercased().dropFirst(4)) : host.lowercased()
        guard !h.isEmpty, !load(url).contains(h) else { return false }
        var text = (try? String(contentsOf: url, encoding: .utf8))
            ?? "# Sites Duo opens in its own browser tabs (DL-3). One host per line; a host allows its subdomains.\n"
        if !text.hasSuffix("\n") { text += "\n" }
        text += h + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// What the address field means: a URL, a bare host, or localhost:port.
    public static func url(from typed: String) -> URL? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if let u = URL(string: t), let scheme = u.scheme, ["http", "https", "file"].contains(scheme.lowercased()) { return u }
        if t.hasPrefix("localhost") || t.hasPrefix("127.0.0.1") { return URL(string: "http://" + t) }
        guard t.contains(".") else { return nil }
        return URL(string: "https://" + t)
    }
}

/// One browser tab in the right pane (Phase K, ENH-8): its own web view with the default website
/// data store, so sites stay signed in. Pages from sites not on the allow list aren't loaded; the
/// tab says so and offers to allow the site or open it in the system browser.
@MainActor @Observable
public final class WebTab: NSObject, WKNavigationDelegate, WKUIDelegate {
    public let id: String
    @ObservationIgnored public let webView: DuoWebView
    public var title = "New Tab"
    public var address = ""
    public var blocked: URL?
    public var canGoBack = false
    public var canGoForward = false
    public var loading = false
    /// Asks the address field for the keyboard (⌥⌘T on an empty tab, ⌘L).
    public var focusRequest = 0
    /// Links to other sites from a page, when they aren't allowed here: the model sends them out.
    @ObservationIgnored var onLinkOut: ((URL) -> Void)?

    init(id: String) {
        self.id = id
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // The title and history arrive after navigation callbacks sometimes: watch them directly.
        observations = [
            webView.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
    }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    public var url: URL? { webView.url ?? blocked }

    /// Loads what was typed or a URL; a site not on the list is shown as blocked, not loaded.
    public func go(_ typed: String) {
        guard let u = AllowedSites.url(from: typed) else { address = typed; return }
        load(u)
    }

    public func load(_ u: URL) {
        address = u.absoluteString
        if AllowedSites.allows(u) {
            blocked = nil
            if u.isFileURL { webView.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent()) } else { webView.load(URLRequest(url: u)) }
        } else {
            blocked = u
            title = u.host ?? u.absoluteString
        }
    }

    public func allowBlockedSite() {
        guard let u = blocked, let host = u.host else { return }
        AllowedSites.add(host)
        load(u)
    }

    private func refresh() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        loading = webView.isLoading
        if let t = webView.title, !t.isEmpty { title = t }
        if let u = webView.url, blocked == nil { address = u.absoluteString }
    }

    public func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let target = action.request.url else { return decisionHandler(.cancel) }
        // Frames inside an allowed page load as the page wants; only where the tab goes is checked.
        if action.targetFrame?.isMainFrame == false || target.scheme == "about" || target.scheme == "blob" || target.scheme == "data" || AllowedSites.allows(target) {
            return decisionHandler(.allow)
        }
        if action.navigationType == .linkActivated { onLinkOut?(target) } else { blocked = target; address = target.absoluteString; title = target.host ?? title }
        decisionHandler(.cancel)
    }

    public func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { refresh() }
    public func webView(_ w: WKWebView, didCommit n: WKNavigation!) { refresh() }
    public func webView(_ w: WKWebView, didFinish n: WKNavigation!) { refresh() }
    public func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { refresh() }
    public func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { refresh() }

    /// target=_blank and window.open load in this tab (one page per tab).
    public func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { load(u) }
        return nil
    }
}

extension AppModel {
    /// File › New Browser Tab (⌥⌘T), right-click + › New Browser Tab, links to allowed sites, and
    /// `duo2 browser open`. Opens in the project on screen (Home's at All projects).
    @discardableResult
    public func newBrowserTab(_ url: URL? = nil) -> String? {
        if currentProject == nil, let home = fixture.home?.name { open(project: home) }
        guard let project = currentProject?.name else { info("Open a project first: browser tabs sit in its right pane."); return nil }
        let id = "web:" + UUID().uuidString.prefix(8).lowercased()
        let tab = WebTab(id: id)
        tab.onLinkOut = { [weak self] u in self?.openLink(u.absoluteString) }
        webTabs[id] = tab
        openDocumentsByProject[project, default: []].append(id)
        rightTab = id
        if let url { tab.load(url) } else { tab.focusRequest += 1 }
        return id
    }

    /// ⌘L in a browser tab: the address field takes the keyboard.
    public func focusAddressField() {
        guard let id = rightTab, let tab = webTabs[id] else { return }
        tab.focusRequest += 1
    }

    public var visibleWebTab: WebTab? { rightTab.flatMap { webTabs[$0] } }
}

/// The browser tab's page with a plain bar above it (stand-in look until DB-20 is designed).
struct BrowserTabView: View {
    @Environment(AppModel.self) private var model
    let tab: WebTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                barItem("chevron.left", "Back", enabled: tab.canGoBack) { tab.webView.goBack() }
                barItem("chevron.right", "Forward", enabled: tab.canGoForward) { tab.webView.goForward() }
                barItem(tab.loading ? "xmark" : "arrow.clockwise", tab.loading ? "Stop" : "Reload", enabled: tab.blocked == nil) {
                    if tab.loading { tab.webView.stopLoading() } else { tab.webView.reload() }
                }
                AddressField(tab: tab).frame(height: 22)
                barItem("safari", "Open in Browser", enabled: tab.url != nil) { if let u = tab.url { NSWorkspace.shared.open(u) } }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            DuoColor.rule.frame(height: 1)
            if let blocked = tab.blocked {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(blocked.host ?? blocked.absoluteString) isn't on your allowed sites").duoText(.bodyEmphasis)
                    Text("Duo opens other sites in your browser unless you allow them here. Allowed sites stay signed in, and their pages can be sent to Claude.")
                        .duoText(.body).foregroundStyle(DuoColor.text2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        let allow = "Allow \(blocked.host ?? "This Site")"
                        Button(allow) { tab.allowBlockedSite() }.buttonStyle(.duo)
                        Button("Open in Browser") { NSWorkspace.shared.open(blocked) }.buttonStyle(.duo)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                WebTabHost(tab: tab)
            }
        }
    }

    private func barItem(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
            .buttonStyle(.plain)
            .foregroundStyle(enabled ? DuoColor.text : DuoColor.text2.opacity(0.5))
            .disabled(!enabled)
            .help(label)
            .accessibilityLabel(label)
    }
}

struct WebTabHost: NSViewRepresentable {
    let tab: WebTab
    func makeNSView(context: Context) -> DocumentEditorView.EditorHost { DocumentEditorView.EditorHost() }
    func updateNSView(_ host: DocumentEditorView.EditorHost, context: Context) { host.show(tab.webView) }
}

/// The address field: Return loads; it takes the keyboard when the tab asks (new tab, ⌘L).
struct AddressField: NSViewRepresentable {
    let tab: WebTab

    final class Field: NSTextField {
        var lastFocus = 0
        func takeFocus(tries: Int = 8) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let w = self.window else { return }
                if self.currentEditor() == nil { w.makeFirstResponder(self); self.currentEditor()?.selectAll(nil) }
                if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.takeFocus(tries: tries - 1) } }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var tab: WebTab
        init(tab: WebTab) { self.tab = tab }
        func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                MainActor.assumeIsolated { tab.go(c.stringValue) ; c.window?.makeFirstResponder(tab.webView) }
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    func makeNSView(context: Context) -> Field {
        let f = Field()
        f.placeholderString = "Address"
        f.font = .systemFont(ofSize: 12)
        f.bezelStyle = .roundedBezel
        f.lineBreakMode = .byTruncatingMiddle
        f.cell?.isScrollable = true
        f.delegate = context.coordinator
        f.setAccessibilityLabel("Address")
        return f
    }

    func updateNSView(_ f: Field, context: Context) {
        context.coordinator.tab = tab
        if f.currentEditor() == nil, f.stringValue != tab.address { f.stringValue = tab.address }
        if tab.focusRequest != f.lastFocus { f.lastFocus = tab.focusRequest; f.takeFocus() }
    }
}
