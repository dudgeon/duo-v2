import AppKit
import SwiftUI
import WebKit

/// What the pane says about the page under it (F-629, Q-483): the viewer never leaves a page blank in silence.
@MainActor @Observable
public final class HTMLPageNotice {
    public enum Kind: Equatable { case blockedRemote, failed(String) }
    public var kind: Kind?
    var file: URL?
    public init() {}

    public var message: String? {
        switch kind {
        case .blockedRemote?: "This page uses scripts or styles from the web, which Duo’s local pages don’t fetch, so it may show blank or unstyled."
        case .failed(let why)?: "Couldn’t open this page: \(why)."
        case nil: nil
        }
    }
    public var buttonTitle: String { if case .failed? = kind { "Reload" } else { "Open in Browser" } }
}

/// Local HTML in the right pane (v1 "local HTML viewing", DL-67): read-only, reloaded when the
/// file or its neighbours change, links to other sites open in the browser (local-only by
/// default, DL-3). The page can send its selection, or a picked element, to Claude (DL-67–DL-70).
@MainActor
public final class HTMLViewer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: DuoWebView
    public private(set) var url: URL?
    /// The element the picker froze, waiting for Send or Cancel.
    public var picked: SendFormat.Element?
    public var pickedViewRect: CGRect?
    public var picking = false
    /// Called when picking state changes (the native bar shows and hides).
    public var onChange: (() -> Void)?
    /// A link to another site (not a file in the project): the model decides where it opens.
    var onLinkOut: ((URL) -> Void)?
    private var root: URL?
    private var stamp: Date?
    private var timer: Timer?
    /// DL-175: a local page loads nothing remote. WebKit compiles the rules asynchronously, so the
    /// first page waits for them (`open` below); if they fail to compile, pages load without them.
    private var rulesReady = false
    private var afterRules: (() -> Void)?

    /// Blocks every subresource from the network and every remote frame; the page's own files (file:)
    /// and data: URLs are untouched. Links still leave through `decidePolicyFor`. One rule per scheme:
    /// WebKit's url-filter has no `|`, and a list that doesn't compile leaves every page blank.
    public static let remoteBlockRules: String = {
        let subresources = #"["image","style-sheet","script","font","raw","svg-document","media","ping","fetch","websocket","other"]"#
        return "[" + ["^https?://", "^wss?://", "^ftp://"].map { scheme in
            #"{"trigger":{"url-filter":"\#(scheme)","resource-type":\#(subresources)},"action":{"type":"block"}},"#
            + #"{"trigger":{"url-filter":"\#(scheme)","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}"#
        }.joined(separator: ",") + "]"
    }()
    private var dormant = false
    /// The bar over the page: a failed load, or remote scripts the rules blocked.
    public let notice = HTMLPageNotice()
    private var loadStarted: Date?
    private var scanGeneration = 0
    /// The navigation that is the page's own file (only those log "loaded"), and the one that blanks the view.
    private var fileNav: WKNavigation?
    private var blankNav: WKNavigation?
    /// WebKit refused the current load: the bar stays until the next load, whatever the file scan says.
    private var webKitFailed = false
    /// WebKit compiles the rule list in the background; if it hasn't answered in a few seconds, nothing would
    /// load and nothing would say so. Pages still wait for the rules (loading without them would widen DL-175).
    private var rulesTimedOut = false
    static let rulesTimeout: TimeInterval = 5

    /// True when the page's text pulls something from the web that DL-175 blocks and that can leave the page
    /// blank or unstyled: a script, a style sheet (or preloaded one), an @import, or a module import from
    /// http(s). Comments are ignored; canonical and icon links, and plain links, don't count.
    nonisolated public static func loadsRemoteCode(_ html: String) -> Bool {
        let text = html.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: "", options: [.regularExpression])
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has(#"<script\b[^>]*\bsrc\s*=\s*["']?\s*(https?:)?//"#) { return true }
        if has(#"@import\s+(url\(\s*)?["']?\s*(https?:)?//"#) { return true }
        if has(#"\bimport\s*(\(\s*|[^"'()]*?\bfrom\s*)?["']\s*https?://"#) { return true }
        // A <link> counts when it is a style sheet or a preload and its address is remote.
        var rest = text[...]
        while let r = rest.range(of: #"<link\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            let tag = String(rest[r])
            let rel = tag.range(of: #"\brel\s*=\s*["']?([^"'>]*)"#, options: [.regularExpression, .caseInsensitive]).map { String(tag[$0]).lowercased() } ?? ""
            let remote = tag.range(of: #"\bhref\s*=\s*["']?\s*(https?:)?//"#, options: [.regularExpression, .caseInsensitive]) != nil
            if remote, rel.contains("stylesheet") || rel.contains("preload") || rel.contains("modulepreload") { return true }
            rest = rest[r.upperBound...]
        }
        return false
    }

    /// What a look at the file found, made off the main thread.
    struct Scan: Sendable { var unreadable: String?; var remote = false }

    /// Reads at most 4 MB (a page larger than that is scanned by its start) and says why it can't be read.
    nonisolated static func scan(_ file: URL, text: String? = nil) -> Scan {
        if let text { return Scan(unreadable: nil, remote: loadsRemoteCode(String(text.prefix(4 << 20)))) }
        if let why = unreadableReason(file) { return Scan(unreadable: why) }
        guard let h = try? FileHandle(forReadingFrom: file) else { return Scan() }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 4 << 20)) ?? Data()
        return Scan(unreadable: nil, remote: loadsRemoteCode(String(decoding: data, as: UTF8.self)))
    }

    /// Why a file can't be read, said plainly; nil when it reads. A cloud-drive file that isn't downloaded
    /// fails here (or is a dataless stub).
    nonisolated public static func unreadableReason(_ file: URL) -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return "the file isn’t there" }
        if let v = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let st = v.ubiquitousItemDownloadingStatus, st != .current, st != .downloaded {
            return "it is in the cloud and isn’t downloaded to this Mac yet"
        }
        do { let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }; _ = try h.read(upToCount: 1) }
        catch {
            let e = error as NSError
            // Foundation words a refused read as 513 ("permission to save") as often as 257.
            let denied = [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(e.code)
                || (e.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EACCES)
            return denied ? "it can’t be read: this Mac hasn’t given Duo permission to read it" : "it can’t be read (\(e.localizedDescription))"
        }
        return nil
    }

    /// Sets the bar, and logs only when the state changes (typing in split view re-renders every pause).
    private func setNotice(_ kind: HTMLPageNotice.Kind?, file: URL) {
        notice.file = file
        guard notice.kind != kind else { return }
        notice.kind = kind
        switch kind {
        case .failed(let why)?: DuoLog.write("html: failed \(file.path): \(why)")
        case .blockedRemote?: DuoLog.write("html: \(file.path) uses scripts or styles from the web, which local pages don't fetch (DL-175)")
        case nil: DuoLog.write("html: \(file.path): notice cleared")
        }
    }

    /// Looks at the page off the main thread (a cloud placeholder can block a read) while it loads, then sets
    /// the bar. A stale answer, for a page since replaced, is dropped. A file that can't be read blanks the
    /// view, so the page before it is never drawn under the new tab's name (selection and Send read the view).
    private func inspect(_ file: URL, text: String? = nil) {
        scanGeneration += 1
        let generation = scanGeneration
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.scan(file, text: text)
            await MainActor.run { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                if let why = result.unreadable {
                    self.setNotice(.failed(why), file: file)
                    self.blankNav = self.webView.loadHTMLString("", baseURL: nil)
                } else if !self.webKitFailed { self.setNotice(result.remote ? .blockedRemote : nil, file: file) }
            }
        }
    }

    /// Loads the file now (a symlink resolved) and inspects it alongside; `logOpen` for a real open.
    private func loadFile(_ file: URL, root: URL, logOpen: Bool) {
        if logOpen { DuoLog.write("html: open \(file.path)") }
        loadStarted = Date()
        webKitFailed = false
        fileNav = webView.loadFileURL(file.resolvingSymlinksInPath(), allowingReadAccessTo: Self.readRoot(file, root))
        inspect(file)
    }

    /// The bar's button: Reload after a failure, otherwise the page in the person's browser.
    public func noticeAction() {
        guard let file = notice.file else { return }
        if case .failed? = notice.kind { reload() } else { NSWorkspace.shared.open(file) }
    }

    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: HTMLPicker.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = DuoWebView(frame: .zero, configuration: config)
        webView.appearance = NSAppearance(named: .aqua)   // a page keeps its author's colours in dark too (DL-224)
        super.init()
        webView.configuration.userContentController.add(self, name: "duoPage")
        webView.navigationDelegate = self
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "duo-local-page-no-remote", encodedContentRuleList: Self.remoteBlockRules) { [weak self] list, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A list that doesn't compile mustn't blank every page: log it and load pages without it.
                if let list { self.webView.configuration.userContentController.add(list) }
                else { DuoLog.write("html: the remote-content rules didn't compile, so local pages load without them: \(String(describing: error))") }
                if self.rulesTimedOut { DuoLog.write("html: the remote-content rules answered after \(Int(Self.rulesTimeout)) s") }
                self.rulesReady = true
                self.afterRules?(); self.afterRules = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.rulesTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.rulesReady else { return }
                self.rulesTimedOut = true
                DuoLog.write("html: the remote-content rules haven't compiled after \(Int(Self.rulesTimeout)) s; pages wait for them and aren't loaded")
                if let file = self.url { self.setNotice(.failed("Duo’s page rules haven’t finished loading"), file: file) }
            }
        }
    }

    /// The folder WebKit may read for a file: the project's root, or the file's own folder when a link leads out of it.
    nonisolated static func readRoot(_ file: URL, _ root: URL) -> URL {
        let real = file.resolvingSymlinksInPath()
        return inside(real, root) ? root.resolvingSymlinksInPath() : real.deletingLastPathComponent()
    }

    /// Shows a file; `root` is the folder the page may read (its project).
    public func open(_ file: URL, root: URL, force: Bool = false) {
        guard force || file.standardizedFileURL != url?.standardizedFileURL || bufferText != nil else { return }
        bufferText = nil
        url = file
        self.root = root
        picked = nil
        picking = false
        stamp = Self.newest(around: file)
        if notice.file != file { notice.kind = nil }
        notice.file = file
        DuoLog.write("html: open \(file.path)")   // before the rules wait, so a page that never loads still leaves a line
        let load = { [weak self] in
            guard let self, self.rulesReady, self.url == file else { return }
            self.loadFile(file, root: root, logOpen: false)
        }
        if rulesReady { load() } else {
            afterRules = load
            if rulesTimedOut { setNotice(.failed("Duo’s page rules haven’t finished loading"), file: file) }
        }
        startWatching()
        onChange?()
    }

    /// Loads the page again, from disk (a buffer's page too, when one is showing), and looks at it again:
    /// the bar clears when the cause is gone and appears when a change brought one. WebKit's own reload would
    /// reload a blank page after a failure. Used by the Reload button and verb, the watcher and wake().
    public func reload() {
        guard let url, let root else { webView.reload(); return }
        if let text = bufferText { renderBuffer(text, file: url, root: root); return }
        guard rulesReady else { return }
        // A page that is showing is reloaded in place, which keeps the scroll position and a page the person
        // followed a link to; only a blank (a failure, or nothing loaded) loads the tab's file from the start.
        var failedNow = false
        if case .failed? = notice.kind { failedNow = true }
        if let shown = webView.url, shown.isFileURL, !failedNow, !webKitFailed, shown.absoluteString != "about:blank" {
            webKitFailed = false
            loadStarted = Date()
            fileNav = webView.reload()
            inspect(shown)
            return
        }
        loadFile(url, root: root, logOpen: false)
    }

    /// The page drawn from the editor's buffer (split view: the preview renders the unsaved text,
    /// DL-275). Nothing is written; the folder's files load through a base address, which WebKit
    /// may refuse for local files, so relative images can be missing until the editor saves
    /// (the editor autosaves a second after typing, and the page then loads from disk again).
    public func renderBuffer(_ text: String, file: URL, root: URL) {
        if url?.standardizedFileURL != file.standardizedFileURL { url = file; self.root = root; picked = nil; picking = false }
        bufferText = text
        let load = { [weak self] in
            guard let self, self.rulesReady, self.bufferText == text else { return }
            self.fileNav = nil
            self.webKitFailed = false
            self.webView.loadHTMLString(text, baseURL: file.deletingLastPathComponent())
            self.inspect(file, text: text)
        }
        if rulesReady { load() } else { afterRules = load }
        timer?.invalidate(); timer = nil
        onChange?()
    }

    /// The buffer is no longer what the page shows: the next `open` loads the file.
    public func endBuffer() {
        guard bufferText != nil else { return }
        bufferText = nil
        url = nil
    }

    /// The text last drawn from a buffer, nil when the page shows the file.
    public private(set) var bufferText: String?

    // MARK: Watching

    /// Polls once a second while a page is open: the page's own file, and the styles, scripts and
    /// images next to it, so editing any of them shows straight away.
    private func startWatching() {
        timer?.invalidate()
        guard !dormant else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let url = self.url, self.webView.window != nil else { return }
                let now = Self.newest(around: url)
                if now != self.stamp, !self.picking { self.stamp = now; self.reload() }
            }
        }.loose()
    }

    /// The pane stopped showing the page: no more polling its folder (C-83).
    public func sleep() {
        dormant = true
        timer?.invalidate(); timer = nil
    }

    /// The pane shows it again: it reloads if anything changed meanwhile.
    public func wake() {
        guard dormant else { return }
        dormant = false
        startWatching()
        if let url, Self.newest(around: url) != stamp, !picking { stamp = Self.newest(around: url); reload() }
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
        if target.isFileURL, (root.map { Self.inside(target, $0) } ?? false) || (url.map { target.resolvingSymlinksInPath() == $0.resolvingSymlinksInPath() } ?? false) {
            return decisionHandler(.allow)
        }
        if target.scheme == "about" { return decisionHandler(.allow) }
        // Anything else leaves Duo: the browser in the right pane comes later (Phase K).
        if action.navigationType == .linkActivated {
            DuoLog.write("html: link out to \(target.absoluteString)")
            if let out = onLinkOut { out(target) } else { NSWorkspace.shared.open(target) }
        }
        decisionHandler(.cancel)
    }

    /// A file inside the root, whichever way each is spelled: symlinks (a linked project root, /tmp and
    /// /private/tmp) are resolved on both sides before comparing, and the root ends at a folder edge.
    nonisolated public static func inside(_ file: URL, _ root: URL) -> Bool {
        let f = file.resolvingSymlinksInPath().standardizedFileURL.path
        var r = root.resolvingSymlinksInPath().standardizedFileURL.path
        if !r.hasSuffix("/") { r += "/" }
        return f.hasPrefix(r) || f + "/" == r
    }

    /// Only the page's own file logs "loaded": a buffer's render (every pause while typing) and the blank don't.
    public func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        guard n != nil, n === fileNav else { return }
        let ms = loadStarted.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        DuoLog.write("html: loaded \(url?.path ?? "?") in \(ms) ms")
    }

    public func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError error: Error) { if n !== blankNav { failed(error) } }
    public func webView(_ w: WKWebView, didFail n: WKNavigation!, withError error: Error) { if n !== blankNav { failed(error) } }

    public func failed(_ error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain, e.code == NSURLErrorCancelled { return }   // a reload mid-load
        if e.domain == "WebKitErrorDomain", e.code == 102 { return }   // "frame load interrupted": a policy cancelled it
        let why = e.localizedDescription
        DuoLog.write("html: WebKit failed \(url?.path ?? "?"): \(why) [\(e.domain) \(e.code)]")
        if case .failed? = notice.kind { return }   // the file scan already said why, in plainer words
        webKitFailed = true
        notice.kind = .failed(why); notice.file = url
    }

    /// The page's process died (C-81): load it again rather than leave it blank.
    public func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        DuoLog.write("html: web content process terminated")
        picked = nil; picking = false
        if rulesReady, let url, let root { if let text = bufferText { renderBuffer(text, file: url, root: root) } else { loadFile(url, root: root, logOpen: false) } }
        onChange?()
    }

    // MARK: The page's selection and the picker: PageHost (shared with browser tabs)

    public var pageURL: URL? { url }
    public var world: WKContentWorld { .page }

    public func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { handlePageMessage(message) }

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

    /// Every Duo web view says it's the installed Safari, whose engine it is (F-117).
    public override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        configuration.applicationNameForUserAgent = WebUserAgent.applicationName
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) { fatalError("DuoWebView is made in code") }

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
        viewer.wake()
        viewer.open(file, root: root)
    }
}

/// The one-line bar over a page that is blank or half-drawn for a reason (F-629; a stand-in in the
/// trust bar's chat look, Q-483). Reload is `duo2 html reload` (.htmlReload); Open in Browser is UI-only
/// (Parity.uiOnly "Open in Browser (HTML page bar)").
struct HTMLNoticeBar: View {
    let notice: HTMLPageNotice
    let action: () -> Void

    var body: some View {
        if let message = notice.message {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: DuoSpace.gapButtonToButton) {
                    Text(message).duoText(.body).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(action: action) { Text(notice.buttonTitle) }.buttonStyle(.duo).fixedSize()
                }
                .padding(.vertical, DuoMetric.noticePaddingY)
                .padding(.horizontal, DuoMetric.noticePaddingX)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DuoColor.ground)
                DuoColor.rule.frame(height: DuoMetric.borderHairline)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message)
        }
    }
}
