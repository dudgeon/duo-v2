import AppKit
import DuoControl
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
public final class WebTab: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, PageHost {
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
    // The element picker and selection (LR-44), shared with local HTML (PageHost).
    public var picked: SendFormat.Element?
    @ObservationIgnored public var pickedViewRect: CGRect?
    public var picking = false
    @ObservationIgnored public var onChange: (() -> Void)?
    public var pageURL: URL? { webView.url }
    /// Duo's script runs apart from the site's own scripts, which can't see or imitate it.
    public var world: WKContentWorld { .defaultClient }
    public func reload() { webView.reload() }
    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { handlePageMessage(message) }

    init(id: String) {
        self.id = id
        let config = WKWebViewConfiguration()
        // Tabs stay signed in to their sites, except in an isolated copy of Duo: the default store
        // belongs to the app's bundle id, not its support folder, so it would be the user's (C-32).
        config.websiteDataStore = SupportFolder.isIsolated ? .nonPersistent() : .default()
        config.userContentController.addUserScript(WKUserScript(source: HTMLPicker.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        webView = DuoWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, contentWorld: .defaultClient, name: "duoPage")
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
        wireWebTab(tab)
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

    /// The page on screen in the right pane: a browser tab, or local HTML (PageHost).
    public var visiblePage: PageHost? {
        if let w = visibleWebTab { return w }
        if let path = rightTab, ["html", "htm"].contains((path as NSString).pathExtension.lowercased()) { return htmlViewerIfLoaded }
        return nil
    }

    /// A browser tab gets what local HTML has: links out, the picker bar, focus for Send
    /// Selection, and the right-click Send / Select Element items.
    func wireWebTab(_ tab: WebTab) {
        tab.onLinkOut = { [weak self] u in self?.openLink(u.absoluteString) }
        tab.onChange = { [weak self] in self?.pickerRevision += 1 }
        tab.webView.onFocusChange = { [weak self] on in
            guard let self else { return }
            if on { self.webFocus = .html } else if self.webFocus == .html { self.webFocus = .none }
        }
        tab.webView.extraMenuItems = { [weak self, weak tab] hasSelection, onImage in
            guard let self, let tab, self.terminalsMode == .live else { return [] }
            var items: [NSMenuItem] = []
            if hasSelection || onImage {
                items += self.sendMenuItems(hasSelection ? "Selection" : "Image") { done in self.htmlSelectionPayload(done) }
            }
            items.append(ActionMenuItem("Select Element") { tab.startPicking() })
            items.append(ActionMenuItem("Reload Page") { tab.reload() })
            return items
        }
    }
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

/// Page driving for Claude (LR-45) on a browser tab's page, which is always an allowed site or
/// localhost (DL-3). Run in Duo's isolated world: the DOM is shared, the page's scripts aren't.
/// No arbitrary script: read, click, fill, wait and screenshot are the whole surface.
extension WebTab {
    private func run(_ js: String, _ args: [String: Any] = [:], _ done: @escaping @MainActor (Any?) -> Void) {
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: world) { r in
            if case .success(let v) = r { done(v) } else { done(nil) }
        }
    }

    /// The page's text (or one element's), capped, with its title and address.
    public func read(selector: String?, limit: Int = 40_000, _ done: @escaping @MainActor (String?) -> Void) {
        run("""
            const el = sel ? document.querySelector(sel) : document.body;
            if (!el) return null;
            return { title: document.title, url: location.href, text: (el.innerText || el.textContent || '').slice(0, limit) };
            """, ["sel": selector ?? "", "limit": limit]) { v in
            guard let d = v as? [String: Any] else { return done(nil) }
            done("\(d["title"] as? String ?? "")\n\(d["url"] as? String ?? "")\n\n\(d["text"] as? String ?? "")")
        }
    }

    /// Clicks the element a selector names, scrolled into view first; returns what it was.
    public func click(selector: String, _ done: @escaping @MainActor (String?) -> Void) {
        run("""
            const el = document.querySelector(sel);
            if (!el) return null;
            el.scrollIntoView({block: 'center'});
            el.click();
            return '<' + el.tagName.toLowerCase() + '> ' + (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 80);
            """, ["sel": selector]) { done($0 as? String) }
    }

    /// Types a value into an input, textarea or editable element, the way a framework notices.
    public func fill(selector: String, text: String, _ done: @escaping @MainActor (Bool) -> Void) {
        run("""
            const el = document.querySelector(sel);
            if (!el) return false;
            el.focus();
            if (el.isContentEditable) { el.textContent = text; }
            else {
              const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              const set = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
              if (set) set.call(el, text); else el.value = text;
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
            """, ["sel": selector, "text": text]) { done(($0 as? Bool) ?? false) }
    }

    /// Waits for a selector to match, up to `seconds`.
    public func wait(selector: String, seconds: Double, _ done: @escaping @MainActor (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(seconds)
        func poll() {
            run("return !!document.querySelector(sel)", ["sel": selector]) { v in
                if (v as? Bool) == true { return done(true) }
                if Date() > deadline { return done(false) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { poll() } }
            }
        }
        poll()
    }
}

extension AppModel {
    /// The browser tab a page-driving verb acts on: `--tab <id>`, else the one on screen.
    func browserTab(_ inv: Invocation) -> WebTab? {
        if let id = inv.flags["tab"] { return webTabs[id] ?? webTabs["web:" + id] }
        return visibleWebTab
    }

    func browserVerb(_ id: ActionID, _ inv: Invocation, _ done: @escaping @MainActor (Reply) -> Void) {
        if id == .browserTabs {
            let rows = openDocumentsByProject.flatMap { p, docs in docs.compactMap { d in webTabs[d].map { (p, $0) } } }
            return done(.ok(rows.isEmpty ? "No browser tabs." : rows.map { p, t in "\(t.id)  \(p)  \(t.title)  \(t.url?.absoluteString ?? "")\(t.blocked != nil ? "  (not allowed)" : "")" }.joined(separator: "\n"),
                            rows.map { p, t in ["tab": t.id, "project": p, "title": t.title, "url": t.url?.absoluteString ?? "", "allowed": t.blocked == nil] }))
        }
        guard let tab = browserTab(inv) else { return done(.fail("no browser tab is showing (open one with `duo2 browser open <url>`, or pass --tab)")) }
        if tab.blocked != nil, ![.browserGo, .browserClose].contains(id) {
            return done(.fail("\(tab.blocked?.host ?? "this site") isn't on the allow list; the user can allow it in the tab (or `duo2 browser allow`)"))
        }
        switch id {
        case .browserRead:
            tab.read(selector: inv[0]) { t in done(t.map { .ok($0) } ?? .fail(inv[0].map { "nothing matches \($0)" } ?? "the page isn't readable yet")) }
        case .browserClick:
            guard let sel = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            tab.click(selector: sel) { what in done(what.map { .ok("Clicked \($0).") } ?? .fail("nothing matches \(sel)")) }
        case .browserFill:
            guard let sel = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
            tab.fill(selector: sel, text: inv.positional.dropFirst().joined(separator: " ")) { ok in done(ok ? .ok("Filled \(sel).") : .fail("nothing matches \(sel)")) }
        case .browserWait:
            guard let sel = inv[0] else { return done(.fail("usage: \(id.action.usage)")) }
            tab.wait(selector: sel, seconds: inv.flags["timeout"].flatMap(Double.init) ?? 10) { ok in done(ok ? .ok("\(sel) is there.") : .fail("\(sel) didn't appear")) }
        case .browserScreenshot:
            tab.screenshot(rect: nil, whole: true) { path in done(path.map { .ok("Saved the visible page: \($0)", ["path": $0]) } ?? .fail("couldn't take a screenshot")) }
        case .browserGo:
            guard let s = inv[0], let u = AllowedSites.url(from: s) else { return done(.fail("usage: \(id.action.usage)")) }
            tab.load(u)
            done(tab.blocked != nil ? .fail("\(u.host ?? s) isn't on the allow list; the tab offers Allow or Open in Browser") : .ok("Going to \(u.absoluteString)."))
        case .browserBack:
            guard tab.webView.canGoBack else { return done(.fail("nothing to go back to")) }
            tab.webView.goBack(); done(.ok("Back."))
        case .browserForward:
            guard tab.webView.canGoForward else { return done(.fail("nothing to go forward to")) }
            tab.webView.goForward(); done(.ok("Forward."))
        case .browserClose:
            closeDocument(tab.id); done(.ok("Closed \(tab.title)."))
        default: done(.fail("not a browser verb"))
        }
    }
}
