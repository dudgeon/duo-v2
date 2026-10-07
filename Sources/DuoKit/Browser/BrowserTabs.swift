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
/// tab says so and offers to allow the site or open it in the system browser. It has a browser's
/// basics (DL-124): uploads, downloads, print, popups that keep their opener, and page zoom.
@MainActor @Observable
public final class WebTab: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate, PageHost {
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
    /// The tab whose page opened this one (window.open, target=_blank): its web view came from
    /// the opener's createWebViewWith, so window.opener and postMessage work (DL-124).
    public let opener: String?
    /// The page's zoom (pageZoom), remembered per site.
    public private(set) var zoom = 1.0
    /// The last download that finished or failed in this tab, for its notice.
    public var download: DownloadRecord?
    /// A download in progress, for its notice (DL-132 h): its name, bytes so far and in all
    /// (`total` is 0 when the server doesn't say).
    public struct RunningDownload: Equatable {
        public var name: String; public var done: Int64; public var total: Int64
        public init(name: String, done: Int64, total: Int64) { self.name = name; self.done = done; self.total = total }
        /// "2.1 of 8.4 MB", both in the total's unit.
        public var count: String {
            let units: [(Double, String)] = [(1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
            let (d, u) = units.first { Double(total) >= $0.0 } ?? (1, "bytes")
            return u == "bytes" ? "\(done) of \(total) bytes" : String(format: "%.1f of %.1f %@", Double(done) / d, Double(total) / d, u)
        }
    }
    public var running: RunningDownload?
    @ObservationIgnored private var active: (download: WKDownload, dest: URL)?
    @ObservationIgnored private var progressTimer: Timer?
    /// Links to other sites from a page, when they aren't allowed here: the model sends them out.
    @ObservationIgnored var onLinkOut: ((URL) -> Void)?
    /// A page opened a window: the model makes its tab around the web view WebKit configured.
    @ObservationIgnored var onPopup: ((WKWebViewConfiguration) -> WebTab?)?
    /// The page called window.close().
    @ObservationIgnored var onClose: (() -> Void)?
    /// Told when a download ends, so `duo2 browser downloads` can list it.
    @ObservationIgnored var onDownload: ((DownloadRecord) -> Void)?
    /// Files `duo2 browser upload` chose: the next file chooser takes them instead of the panel.
    @ObservationIgnored var pendingUpload: [URL]?
    /// What the file chooser took of them (one, when the input takes one).
    @ObservationIgnored var uploaded: [URL] = []
    @ObservationIgnored private var downloads: [ObjectIdentifier: URL] = [:]
    // The element picker and selection (LR-44), shared with local HTML (PageHost).
    public var picked: SendFormat.Element?
    @ObservationIgnored public var pickedViewRect: CGRect?
    public var picking = false
    @ObservationIgnored public var onChange: (() -> Void)?
    public var pageURL: URL? { webView.url }
    /// Duo's script runs apart from the site's own scripts, which can't see or imitate it.
    public var world: WKContentWorld { .defaultClient }
    public func reload() { webView.reload() }
    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "duoPrint" { return printPage() }
        handlePageMessage(message)
    }

    /// The site's zoom levels, shared by every tab.
    static var zoomStore = ZoomStore()

    /// A popup passes WebKit's configuration (`createWebViewWith`), which ties its web view to the
    /// opener's; it gets its own scripts, so the picker and print talk to this tab.
    init(id: String, configuration: WKWebViewConfiguration? = nil, opener: String? = nil) {
        self.id = id
        self.opener = opener
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            // Tabs stay signed in to their sites, except in an isolated copy of Duo: the default store
            // belongs to the app's bundle id, not its support folder, so it would be the user's (C-32).
            config.websiteDataStore = SupportFolder.isIsolated ? .nonPersistent() : .default()
        }
        config.userContentController = WKUserContentController()
        config.userContentController.addUserScript(WKUserScript(source: HTMLPicker.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        // window.print() does nothing in a WKWebView: the page's print asks Duo instead (DL-124).
        config.userContentController.addUserScript(WKUserScript(source: "window.print = function () { window.webkit.messageHandlers.duoPrint.postMessage(1) };",
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        let view = BrowserWebView(frame: .zero, configuration: config)
        webView = view
        super.init()
        config.userContentController.add(self, contentWorld: .defaultClient, name: "duoPage")
        config.userContentController.add(self, contentWorld: .page, name: "duoPrint")
        view.onZoomKey = { [weak self] key in
            guard let self else { return }
            self.zoom(key == "0" ? 1.0 : key == "-" ? ZoomStore.zoomOut(self.zoom) : ZoomStore.zoomIn(self.zoom))
        }
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
            return decisionHandler(action.shouldPerformDownload ? .download : .allow)
        }
        if action.navigationType == .linkActivated { onLinkOut?(target) } else { blocked = target; address = target.absoluteString; title = target.host ?? title }
        decisionHandler(.cancel)
    }

    /// An attachment, or a type WebKit can't show, is downloaded rather than shown (DL-124).
    public func webView(_ w: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(!response.canShowMIMEType || disposition.hasPrefix("attachment") ? .download : .allow)
    }

    public func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    public func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    public func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { refresh() }
    public func webView(_ w: WKWebView, didCommit n: WKNavigation!) { refresh(); applySiteZoom() }
    public func webView(_ w: WKWebView, didFinish n: WKNavigation!) { refresh() }
    public func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { refresh() }
    public func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { refresh() }

    /// window.open and target=_blank open a tab beside this one, around the web view WebKit
    /// configured, so the page keeps its opener (DL-124). A link to a site that isn't allowed
    /// opens in the system browser, as any other link does (DL-3).
    public func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url, !["about", "blob", "data", ""].contains(u.scheme ?? ""), !AllowedSites.allows(u) {
            onLinkOut?(u)
            return nil
        }
        return onPopup?(c)?.webView
    }

    public func webViewDidClose(_ w: WKWebView) { onClose?() }

    // MARK: Uploads

    /// `<input type=file>`: the native open panel, with multiple selection and folders where the
    /// page asks (DL-124). Files chosen by `duo2 browser upload` answer it without a panel.
    public func webView(_ w: WKWebView, runOpenPanelWith p: WKOpenPanelParameters, initiatedByFrame f: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        if let files = pendingUpload {
            pendingUpload = nil
            uploaded = p.allowsMultipleSelection ? files : Array(files.prefix(1))
            return completionHandler(uploaded)
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = p.allowsMultipleSelection
        panel.canChooseDirectories = p.allowsDirectories
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        guard let window = w.window else { return completionHandler(panel.runModal() == .OK ? panel.urls : nil) }
        panel.beginSheetModal(for: window) { r in MainActor.assumeIsolated { completionHandler(r == .OK ? panel.urls : nil) } }
    }

    // MARK: Downloads

    public func download(_ d: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        let folder = DownloadNaming.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = DownloadNaming.unique(suggestedFilename, in: folder)
        downloads[ObjectIdentifier(d)] = dest
        download = nil
        active = (d, dest)
        running = RunningDownload(name: dest.lastPathComponent, done: 0, total: max(0, response.expectedContentLength))
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let (d, _) = self.active, var r = self.running else { return }
                r.done = d.progress.completedUnitCount
                if d.progress.totalUnitCount > 0 { r.total = d.progress.totalUnitCount }
                if r != self.running { self.running = r }
            }
        }
        completionHandler(dest)
    }

    /// The running download's Cancel (`duo2 browser downloads --cancel`): stops it and takes the
    /// partial file away; no failure notice follows.
    public func cancelDownload() {
        guard let (d, dest) = active else { return }
        downloads.removeValue(forKey: ObjectIdentifier(d))
        stopRunning()
        d.cancel { _ in MainActor.assumeIsolated { try? FileManager.default.removeItem(at: dest) } }
    }

    private func stopRunning() {
        progressTimer?.invalidate(); progressTimer = nil
        active = nil
        running = nil
    }

    public func downloadDidFinish(_ d: WKDownload) {
        guard let dest = downloads.removeValue(forKey: ObjectIdentifier(d)) else { return }
        finish(DownloadRecord(file: dest, error: nil, tab: id))
    }

    public func download(_ d: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // A cancelled download has already left (cancelDownload).
        if active == nil || active?.download !== d, downloads[ObjectIdentifier(d)] == nil { return }
        let dest = downloads.removeValue(forKey: ObjectIdentifier(d)) ?? DownloadNaming.folder.appending(path: d.originalRequest?.url?.lastPathComponent ?? "download")
        finish(DownloadRecord(file: dest, error: error.localizedDescription, tab: id))
    }

    private func finish(_ r: DownloadRecord) {
        stopRunning()
        download = r
        onDownload?(r)
    }

    // MARK: Print and zoom

    /// ⌘P, File › Print…, the page's window.print() and `duo2 browser print`: the print panel on
    /// the window. `pdf` saves to a file with no panel; a scripted run (DUO_AUTOCONFIRM) always does.
    /// It runs as a sheet either way: WebKit's print view paginates without end under a plain
    /// run(), so the window is required (F-118). `done` gets the PDF, when one was asked for.
    public func printPage(pdf: URL? = nil, _ done: (@MainActor (URL?) -> Void)? = nil) {
        guard let window = webView.window else { done?(nil); return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        var target = pdf
        if target == nil, Env.autoconfirm {
            target = DuoPaths.support.appending(path: "print-\(id.replacingOccurrences(of: ":", with: "-")).pdf")
        }
        if let target {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = target
        }
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = target == nil
        op.showsProgressPanel = false
        // WebKit's print view has no size until it's given one; without it nothing prints.
        op.view?.frame = webView.bounds
        printDone = { ok in done?(ok ? target : nil) }
        op.runModal(for: window, delegate: self, didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @ObservationIgnored private var printDone: ((Bool) -> Void)?

    /// AppKit calls this on the print operation's own thread when there's no panel.
    @objc nonisolated private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let d = self?.printDone
                self?.printDone = nil
                d?(success)
            }
        }
    }

    /// Sets the page's zoom and remembers it for the site (⌘+ ⌘- ⌘0, `duo2 browser zoom`).
    public func zoom(_ level: Double) {
        let z = min(max(level, ZoomStore.range.lowerBound), ZoomStore.range.upperBound)
        zoom = z
        webView.pageZoom = z
        Self.zoomStore.set(z, for: webView.url)
    }

    /// A page that loads takes its site's remembered zoom.
    private func applySiteZoom() {
        let z = Self.zoomStore.level(for: webView.url)
        if abs(z - webView.pageZoom) > 0.001 { webView.pageZoom = z }
        zoom = z
    }
}

/// A browser tab's web view: ⌘+ (or ⌘=), ⌘- and ⌘0 zoom the page while it has the keyboard
/// (DL-124). The View menu has the same items; handling them here also takes ⌘= without ⇧.
final class BrowserWebView: DuoWebView {
    var onZoomKey: ((String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .numericPad, .function, .capsLock])
        if mods == .command, let key = event.charactersIgnoringModifiers, ["=", "+", "-", "0"].contains(key),
           let r = window?.firstResponder as? NSView, r === self || r.isDescendant(of: self) {
            onZoomKey?(key == "=" ? "+" : key)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A download a browser tab saved, or failed to.
public struct DownloadRecord: Sendable, Equatable {
    public var file: URL
    public var error: String?
    public var tab: String
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
        rightCollapsedProject = false   // DL-129
        if let url { tab.load(url) } else { tab.focusRequest += 1 }
        return id
    }

    /// A page opened a window (DL-124): a tab right after its opener, around the web view WebKit
    /// configured, in the opener's project. It shows at once, as a browser shows a popup.
    func newPopupTab(from opener: WebTab, configuration: WKWebViewConfiguration) -> WebTab? {
        guard let project = openDocumentsByProject.first(where: { $0.value.contains(opener.id) })?.key else { return nil }
        let id = "web:" + UUID().uuidString.prefix(8).lowercased()
        let tab = WebTab(id: id, configuration: configuration, opener: opener.id)
        wireWebTab(tab)
        webTabs[id] = tab
        var docs = openDocumentsByProject[project] ?? []
        docs.insert(id, at: PopupPlacement.index(in: docs, opener: opener.id, openers: webTabs.compactMapValues(\.opener)))
        openDocumentsByProject[project] = docs
        if currentProject?.name == project { rightTab = id }
        return tab
    }

    /// Closes a browser tab in whichever project holds it (window.close() can come from a tab
    /// that isn't on screen); a popup hands the pane back to its opener.
    public func closeWebTab(_ id: String) {
        guard let project = openDocumentsByProject.first(where: { $0.value.contains(id) })?.key else { webTabs.removeValue(forKey: id); return }
        let docs = openDocumentsByProject[project] ?? []
        let next = PopupPlacement.after(closing: id, in: docs, openers: webTabs.compactMapValues(\.opener))
        openDocumentsByProject[project] = docs.filter { $0 != id }
        webTabs.removeValue(forKey: id)
        if currentProject?.name == project, rightTab == id { rightTab = next ?? "Project" }
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
        if let path = rightTab, Self.isDeck(path) { return deckViewerIfLoaded }
        return nil
    }

    /// A browser tab gets what local HTML has: links out, the picker bar, focus for Send
    /// Selection, and the right-click Send / Select Element items.
    func wireWebTab(_ tab: WebTab) {
        tab.onLinkOut = { [weak self] u in self?.openLink(u.absoluteString) }
        tab.onPopup = { [weak self, weak tab] config in
            guard let self, let tab else { return nil }
            return self.newPopupTab(from: tab, configuration: config)
        }
        tab.onClose = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.closeWebTab(tab.id)
        }
        tab.onDownload = { [weak self] r in self?.downloads.append(r) }
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
                if abs(tab.zoom - 1) > 0.001 {
                    // The page's zoom, as Safari shows it in its address field; a click is Actual Size.
                    // A stand-in until it's designed (Q-66).
                    Button { tab.zoom(1.0) } label: { Text(ZoomStore.percent(tab.zoom)).duoText(.body).foregroundStyle(DuoColor.text2) }
                        .buttonStyle(.plain)
                        .fixedSize()   // never truncates; the address gives way (DL-129)
                        .help("Actual Size (⌘0)")
                        .accessibilityLabel("Zoom \(ZoomStore.percent(tab.zoom)), reset to actual size")
                }
                barItem("safari", "Open in Browser", enabled: tab.url != nil) { if let u = tab.url { NSWorkspace.shared.open(u) } }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            DuoColor.rule.frame(height: 1)
            if let d = tab.download { DownloadNotice(tab: tab, record: d).transition(.notice) }
            else if let r = tab.running { RunningDownloadNotice(tab: tab, running: r).transition(.notice) }
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
        .modifier(NoticeMotion(key: tab.download != nil || tab.running != nil ? "download" : nil))
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

/// A download running (DL-132 h, standins2-handoff q66-downloading): in the notice's place under
/// the browser bar, "Downloading report.pdf…", the converting bar's progress line, "2.1 of 8.4 MB"
/// and Cancel. With no size from the server the line moves and there's no count.
struct RunningDownloadNotice: View {
    let tab: WebTab
    let running: WebTab.RunningDownload

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.gapGlyphToLabel) {
            Text("Downloading \(running.name)…").duoText(.body)
            HStack(spacing: DuoSpace.gapCardToCard) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DuoColor.rule)
                        if running.total > 0 {
                            Capsule().fill(DuoColor.text2).frame(width: g.size.width * min(1, Double(running.done) / Double(running.total)))
                        } else {
                            TimelineView(.animation(paused: MotionSettings.shared.reduce)) { t in
                                let phase = MotionSettings.shared.reduce ? 0 : t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
                                Capsule().fill(DuoColor.text2).frame(width: g.size.width * 0.3).offset(x: g.size.width * 0.7 * phase)
                            }
                        }
                    }
                }
                .frame(height: 4)
                if running.total > 0 { Text(running.count).duoText(.body).foregroundStyle(DuoColor.text2).fixedSize() }
                Button("Cancel") { tab.cancelDownload() }.buttonStyle(.duo)
            }
        }
        .padding(.vertical, DuoMetric.noticePaddingY)
        .padding(.horizontal, DuoMetric.noticePaddingX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.ground)
        .overlay(alignment: .bottom) { DuoColor.rule.frame(height: DuoMetric.borderHairline) }
        .accessibilityElement(children: .combine)
    }
}

/// A download that finished or failed, in S3-4's notice bar under the browser bar (DL-124; place
/// and words kept by DL-132 h).
struct DownloadNotice: View {
    let tab: WebTab
    let record: DownloadRecord

    var body: some View {
        if let error = record.error {
            NoticeBar(text: "Couldn’t download \(record.file.lastPathComponent): \(error)") {
                Button("OK") { tab.download = nil }.buttonStyle(DefaultSheetButtonStyle())
            }
        } else {
            NoticeBar(text: "Downloaded \(record.file.lastPathComponent) to \(Self.folderName(record.file)).") {
                Button("Open") { NSWorkspace.shared.open(record.file) }.buttonStyle(DefaultSheetButtonStyle())
                Button("Show in Finder") { FileActions.reveal(record.file) }.buttonStyle(.duo)
                Button("OK") { tab.download = nil }.buttonStyle(.duo)
            }
        }
    }

    static func folderName(_ file: URL) -> String {
        let folder = file.deletingLastPathComponent()
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return folder.standardizedFileURL == downloads?.standardizedFileURL ? "Downloads" : AppModel.short(folder.path)
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

    /// Clicks the element a selector names, scrolled into view first; returns what it was. A real
    /// click by default (DL-124): mouse events at the element's centre, which the page sees as
    /// trusted, so apps that ignore element.click() (Google Docs) respond. `synthetic` is the old
    /// element.click(), also used when the tab isn't on screen or the centre is outside the view.
    public func click(selector: String, synthetic: Bool = false, _ done: @escaping @MainActor (String?) -> Void) {
        run("""
            const el = document.querySelector(sel);
            if (!el) return null;
            el.scrollIntoView({block: 'center', inline: 'center'});
            const what = '<' + el.tagName.toLowerCase() + '> ' + (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 80);
            if (synthetic) { el.click(); return {what}; }
            const r = el.getBoundingClientRect();
            return {what, x: r.left + r.width / 2, y: r.top + r.height / 2};
            """, ["sel": selector, "synthetic": synthetic]) { [weak self] v in
            guard let self, let d = v as? [String: Any], let what = d["what"] as? String else { return done(nil) }
            guard !synthetic, let x = d["x"] as? Double, let y = d["y"] as? Double else { return done(what) }
            if self.mouseClick(at: CGPoint(x: x, y: y)) { return done(what) }
            // Off screen: a synthetic click is better than none, and says so.
            self.click(selector: selector, synthetic: true) { w in done(w.map { $0 + " (synthetic: the page isn't on screen)" }) }
        }
    }

    /// Mouse moved, down and up at a point in the page's viewport (CSS pixels), sent to the web
    /// view as the window would send them. False when the point isn't on screen in the view.
    func mouseClick(at css: CGPoint) -> Bool {
        guard let window = webView.window else { return false }
        let scale = webView.pageZoom * webView.magnification
        var p = CGPoint(x: css.x * scale, y: css.y * scale)
        if !webView.isFlipped { p.y = webView.bounds.height - p.y }
        guard webView.bounds.contains(p) else { return false }
        let at = webView.convert(p, to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: type == .mouseMoved ? 0 : 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let move = event(.mouseMoved), let down = event(.leftMouseDown) else { return false }
        webView.mouseMoved(with: move)
        webView.mouseDown(with: down)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { if let up = event(.leftMouseUp) { self?.webView.mouseUp(with: up) } }
        }
        return true
    }

    /// `duo2 browser upload`: the files answer the next file chooser, then the element is clicked
    /// for real, as a person would, so the page's own change handlers run.
    public func upload(selector: String, files: [URL], _ done: @escaping @MainActor (String?, [URL]) -> Void) {
        pendingUpload = files
        uploaded = []
        click(selector: selector) { [weak self] what in
            guard let what else { self?.pendingUpload = nil; return done(nil, []) }
            // Nothing asked for the files (not a file input, or the page blocked it): drop them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    let taken = self?.pendingUpload == nil
                    self?.pendingUpload = nil
                    done(taken ? what : "", self?.uploaded ?? [])
                }
            }
        }
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

    func browserVerb(_ id: ActionID, _ inv: Invocation, cwd: String? = nil, _ done: @escaping @MainActor (Reply) -> Void) {
        if id == .browserTabs {
            let rows = openDocumentsByProject.flatMap { p, docs in docs.compactMap { d in webTabs[d].map { (p, $0) } } }
            func extra(_ t: WebTab) -> String {
                (t.blocked != nil ? "  (not allowed)" : "") + (t.opener.map { "  (opened from \($0))" } ?? "") + (abs(t.zoom - 1) > 0.001 ? "  \(ZoomStore.percent(t.zoom))" : "")
            }
            return done(.ok(rows.isEmpty ? "No browser tabs." : rows.map { p, t in "\(t.id)  \(p)  \(t.title)  \(t.url?.absoluteString ?? "")\(extra(t))" }.joined(separator: "\n"),
                            rows.map { p, t in ["tab": t.id, "project": p, "title": t.title, "url": t.url?.absoluteString ?? "", "allowed": t.blocked == nil,
                                                "opener": t.opener ?? "", "zoom": t.zoom] }))
        }
        if id == .browserDownloads {
            if inv.has("cancel") {
                guard let t = webTabs.values.first(where: { $0.running != nil }), let r = t.running else { return done(.fail("no download is running")) }
                t.cancelDownload()
                return done(.ok("Cancelled \(r.name)."))
            }
            if inv.has("open") {
                let n = inv[0].flatMap(Int.init) ?? downloads.count
                guard downloads.indices.contains(n - 1) else { return done(.fail(downloads.isEmpty ? "no downloads yet" : "no download \(n) (1–\(downloads.count))")) }
                let d = downloads[n - 1]
                guard d.error == nil, FileManager.default.fileExists(atPath: d.file.path) else { return done(.fail("\(d.file.lastPathComponent) isn't there")) }
                NSWorkspace.shared.open(d.file)
                return done(.ok("Opened \(d.file.path)."))
            }
            return done(.ok(downloads.isEmpty ? "No downloads since Duo started. They go to \(DownloadNaming.folder.path)."
                            : downloads.enumerated().map { i, d in "\(i + 1)  \(d.file.path)  \(d.error.map { "failed: \($0)" } ?? "done")  \(d.tab)" }.joined(separator: "\n"),
                            downloads.map { ["file": $0.file.path, "error": $0.error ?? "", "tab": $0.tab] }))
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
            tab.click(selector: sel, synthetic: inv.has("synthetic")) { what in done(what.map { .ok("Clicked \($0).") } ?? .fail("nothing matches \(sel)")) }
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
            closeWebTab(tab.id); done(.ok("Closed \(tab.title)."))
        case .browserZoom:
            guard let arg = inv[0] else { return done(.ok("\(ZoomStore.percent(tab.zoom))", ["zoom": tab.zoom])) }
            guard let z = ZoomStore.parse(arg, current: tab.zoom) else { return done(.fail("usage: \(id.action.usage) (25–500%)")) }
            tab.zoom(z)
            let site = ZoomStore.site(tab.webView.url)
            done(.ok("Zoomed to \(ZoomStore.percent(tab.zoom))\(site.map { ", remembered for \($0)" } ?? "").", ["zoom": tab.zoom]))
        case .browserPrint:
            if let pdf = inv.flags["pdf"] {
                guard !pdf.isEmpty else { return done(.fail("usage: \(id.action.usage)")) }
                let u = URL(fileURLWithPath: (pdf as NSString).expandingTildeInPath, relativeTo: cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }).standardizedFileURL
                return tab.printPage(pdf: u) { saved in
                    done(saved.map { .ok("Saved the page as \($0.path).", ["path": $0.path]) } ?? .fail("couldn't print to \(u.path) (is the tab on screen?)"))
                }
            }
            guard tab.webView.window != nil else { return done(.fail("the tab isn't on screen; show it first (duo2 view tab \(tab.id))")) }
            if Env.autoconfirm {
                return tab.printPage { saved in done(saved.map { .ok("A scripted run: saved the page as \($0.path) instead of showing the print panel.", ["path": $0.path]) } ?? .fail("couldn't print")) }
            }
            tab.printPage()
            done(.ok("The print panel is open on the page, for the user."))
        case .browserUpload:
            guard let sel = inv[0], inv.positional.count > 1 else { return done(.fail("usage: \(id.action.usage)")) }
            let base = cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
            let files = inv.positional.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: base).standardizedFileURL }
            if let missing = files.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) { return done(.fail("no file at \(missing.path)")) }
            tab.upload(selector: sel, files: files) { what, taken in
                guard let what else { return done(.fail("nothing matches \(sel)")) }
                done(what.isEmpty ? .fail("clicked \(sel), but no file chooser opened (is it an <input type=file>, or a button that opens one?)")
                                  : .ok("Chose \(taken.map(\.lastPathComponent).joined(separator: ", ")) for \(what)\(taken.count < files.count ? " (it takes one file)" : "")."))
            }
        default: done(.fail("not a browser verb"))
        }
    }
}
