import AppKit
import SwiftUI
import WebKit

/// The document editor (Phase I; stack rec #8–9): CodeMirror 6 live preview in one WKWebView
/// that every document shares (research §1). Text is the only truth: files are read and written
/// byte for byte (LR-30), saves are atomic and only when changed (LR-35), outside changes merge
/// three-way and never clobber unsaved work (LR-31, LR-32; F-34).
@MainActor
public final class EditorController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: DuoWebView
    public private(set) var url: URL?
    public private(set) var readOnlyReason: String?
    public private(set) var lastEvent: String = "idle"   // for the harness and logs
    /// An outside change overlapped unsaved edits. Autosave pauses until it's resolved (LR-32):
    /// saving now would overwrite the other writer's change on disk. The banner is Q-20.
    public private(set) var conflict = false
    public private(set) var dirty = false
    private var pageReady = false
    private var pending: (() -> Void)?
    private var diskBytes = Data()                       // what's on disk as far as we know
    private var watcher: DispatchSourceFileSystemObject?
    private var saveTask: Task<Void, Never>?

    public override init() {
        // Check spelling while typing unless the user turned it off (WebKit reads this default).
        UserDefaults.standard.register(defaults: ["WebContinuousSpellCheckingEnabled": true, "WebGrammarCheckingEnabled": false])
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.writingToolsBehavior = .complete  // full Writing Tools in the editor, where the system offers them
        webView = EditorWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(self, name: "duo")  // the view copied `config`
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: Self.tokenCSS(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if let dir = Bundle.main.resourceURL?.appending(path: "editor"),
           FileManager.default.fileExists(atPath: dir.appending(path: "editor.html").path) {
            webView.loadFileURL(dir.appending(path: "editor.html"), allowingReadAccessTo: dir)
        }
    }

    /// Duo's tokens as CSS variables (no raw hex anywhere: values come from `DuoNSColor`).
    static func tokenCSS() -> String {
        func hex(_ c: NSColor) -> String {
            let s = c.usingColorSpace(.sRGB) ?? c
            return String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
        }
        let vars = [("pane", DuoNSColor.pane), ("text", DuoNSColor.text), ("text2", DuoNSColor.text2), ("selected", DuoNSColor.selected),
                    ("rule", DuoNSColor.rule), ("control-edge", DuoNSColor.controlEdge)]
            .map { "--duo-\($0.0): \(hex($0.1));" }.joined(separator: " ")
        let css = ":root { \(vars) --duo-radius-card: \(Int(DuoMetric.radiusCard))px; }"
        return "document.documentElement.setAttribute('style', \(String(reflecting: css)).replace(/^:root \\{ | \\}$/g, ''));"
    }

    public func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        pageReady = true
        pending?(); pending = nil
    }

    /// Shows a file. The current document is saved first if it changed.
    public func open(_ file: URL) {
        guard file != url else { return }
        saveNow()
        dirty = false
        url = file
        readOnlyReason = nil
        let go: () -> Void = { [weak self] in self?.load(file) }
        if pageReady { go() } else { pending = go }
    }

    private func load(_ file: URL) {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            readOnlyReason = "can't read the file"; lastEvent = "unreadable"; return
        }
        diskBytes = data
        guard let text = String(data: data, encoding: .utf8), Data(text.utf8) == data else {
            // Not valid UTF-8: showing it would mean rewriting it on save (LR-30).
            readOnlyReason = "not UTF-8"
            lastEvent = "read-only"
            return
        }
        webView.callAsyncJavaScript("const r = duo.create(t); duo.markSaved(); return r", arguments: ["t": text], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            if case .success(let info) = result, let d = info as? [String: Any], (d["mixedLineEndings"] as? Bool) == true {
                self.readOnlyReason = "mixed line endings"
            }
            self.lastEvent = self.readOnlyReason == nil ? "opened" : "read-only"
        }
        watch(file)
    }

    // MARK: Saving

    public func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: Any], body["kind"] as? String == "selection" else { return }
        dirty = body["dirty"] as? Bool == true
        guard dirty else { return }
        // Autosave a second after the last change (no "Save?" prompts; files are the truth).
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the buffer if it differs from disk: temp file, then rename (LR-35).
    public func saveNow(completion: (@MainActor () -> Void)? = nil) {
        guard let file = url, readOnlyReason == nil else { completion?(); return }
        if conflict { lastEvent = "save paused: conflict"; completion?(); return }
        // Nothing typed since the last save: nothing to write (opening a file never writes it).
        guard dirty else { completion?(); return }
        // Capture the file and its baseline now: switching documents loads the next file before
        // this save's text comes back, and comparing against *its* bytes rewrote this file (F-44).
        let baseline = diskBytes
        webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String else { completion?(); return }
            let data = Data(text.utf8)
            let stillOpen = self.url == file
            if data != baseline {
                do {
                    let tmp = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).duo-\(UUID().uuidString.prefix(8))")
                    try data.write(to: tmp)
                    _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
                    self.lastEvent = "saved"
                    if stillOpen {
                        self.diskBytes = data
                        self.dirty = false
                        self.webView.evaluateJavaScript("duo.markSaved()")
                        self.watch(file)  // the rename replaced the inode we were watching
                    }
                } catch {
                    self.lastEvent = "save failed: \(error.localizedDescription)"
                }
            }
            completion?()
        }
    }

    // MARK: Outside changes

    private func watch(_ file: URL) {
        watcher?.cancel()
        let fd = Darwin.open(file.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.diskChanged() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func diskChanged() {
        guard let file = url else { return }
        // Editors that save by rename leave us watching the old file: re-arm on the new one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.url == file else { return }
                self.watch(file)
                guard let data = FileManager.default.contents(atPath: file.path), data != self.diskBytes,
                      let text = String(data: data, encoding: .utf8) else { return }
                self.diskBytes = data
                self.conflict = false
                self.webView.callAsyncJavaScript("return duo.external(d)", arguments: ["d": text], in: nil, in: .page) { result in
                    if case .success(let v) = result, let r = (v as? [String: Any])?["result"] as? String {
                        // A conflict keeps the user's text; its banner isn't designed yet (§13, Q-20).
                        self.conflict = r == "conflict"
                        if r == "same" { self.dirty = false }
                        self.lastEvent = "outside change: \(r)"
                    }
                }
            }
        }
    }

    /// The editor holds keyboard focus (for menu validation, LR-60).
    public var hasFocus: Bool {
        guard let responder = webView.window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    /// The open file was renamed or moved on purpose: follow it, no reload.
    public func fileMoved(to newURL: URL) {
        url = newURL
        watch(newURL)
    }

    /// The open file is gone (moved to the Trash): stop watching and never save it again.
    public func closeFile() {
        watcher?.cancel(); watcher = nil
        saveTask?.cancel()
        url = nil
        dirty = false; conflict = false
    }

    /// What `duo2 doc-status` reports (LR-34).
    public func status(of file: URL) -> String {
        guard let url, url.standardizedFileURL.resolvingSymlinksInPath() == file.standardizedFileURL.resolvingSymlinksInPath() else {
            return "not open in Duo"
        }
        if conflict { return "open in Duo, in conflict: your change on disk and unsaved edits overlap; Duo won't save over it" }
        if readOnlyReason != nil { return "open in Duo, read-only (\(readOnlyReason!))" }
        return dirty ? "open in Duo with unsaved edits: write anyway and Duo merges, or wait a second for its autosave" : "open in Duo, saved"
    }

    public func run(_ js: String, _ args: [String: Any] = [:], done: @escaping @MainActor (Any?) -> Void) {
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { result in
            if case .success(let v) = result { done(v) } else { done(nil) }
        }
    }
}

/// The editor's web view takes the standard Find menu (Edit > Find) and routes it to CodeMirror's
/// own search, which sees the whole document (F-43).
final class EditorWebView: DuoWebView {
    /// Find menu items arrive as `performTextFinderAction:` (NSTextFinder) or the older
    /// `performFindPanelAction:`; both carry the same tags (1 show, 2 next, 3 previous).
    override func performTextFinderAction(_ sender: Any?) { find(sender) }
    @objc func performFindPanelAction(_ sender: Any?) { find(sender) }

    private func find(_ sender: Any?) {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? 1
        callAsyncJavaScript("return duo.findAction(t)", arguments: ["t": tag], in: nil, in: .page, completionHandler: nil)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(performTextFinderAction(_:)) || item.action == #selector(performFindPanelAction(_:)) {
            return [1, 2, 3, 12].contains(item.tag)
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// The right pane's document view: the shared editor web view, re-parented like terminals. The
/// host lays the web view out on every layout pass: attached once at zero size (before the pane
/// has a frame), autoresizing alone left it invisible (F-43).
struct DocumentEditorView: NSViewRepresentable {
    let editor: EditorController
    let file: URL

    func makeNSView(context: Context) -> EditorHost { EditorHost() }

    func updateNSView(_ host: EditorHost, context: Context) {
        host.show(editor.webView)
        editor.open(file)
    }

    final class EditorHost: NSView {
        private weak var current: NSView?

        func show(_ view: NSView) {
            guard current !== view else { return }
            current?.removeFromSuperview()
            view.removeFromSuperview()
            addSubview(view)
            current = view
            needsLayout = true
        }

        override func layout() {
            super.layout()
            current?.frame = bounds
        }
    }
}
