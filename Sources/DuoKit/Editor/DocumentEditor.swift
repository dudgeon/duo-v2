import AppKit
import SwiftUI
import WebKit

/// The document editor (Phase I; stack rec #8–9): CodeMirror 6 live preview in one WKWebView
/// that every document shares (research §1). Text is the only truth: files are read and written
/// byte for byte (LR-30), saves are atomic and only when changed (LR-35), outside changes merge
/// three-way and never clobber unsaved work (LR-31, LR-32; F-34).
@MainActor
public final class EditorController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: WKWebView
    public private(set) var url: URL?
    public private(set) var readOnlyReason: String?
    public private(set) var lastEvent: String = "idle"   // for the harness and logs
    private var pageReady = false
    private var pending: (() -> Void)?
    private var diskBytes = Data()                       // what's on disk as far as we know
    private var watcher: DispatchSourceFileSystemObject?
    private var saveTask: Task<Void, Never>?

    public override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
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
        guard let body = m.body as? [String: Any], body["kind"] as? String == "selection", body["dirty"] as? Bool == true else { return }
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
        webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String else { completion?(); return }
            let data = Data(text.utf8)
            if data != self.diskBytes {
                do {
                    let tmp = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).duo-\(UUID().uuidString.prefix(8))")
                    try data.write(to: tmp)
                    _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
                    self.diskBytes = data
                    self.lastEvent = "saved"
                    self.webView.evaluateJavaScript("duo.markSaved()")
                    self.watch(file)  // the rename replaced the inode we were watching
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
                self.webView.callAsyncJavaScript("return duo.external(d)", arguments: ["d": text], in: nil, in: .page) { result in
                    if case .success(let v) = result, let r = (v as? [String: Any])?["result"] as? String {
                        // A conflict keeps the user's text; its banner isn't designed yet (§13, Q-20).
                        self.lastEvent = "outside change: \(r)"
                    }
                }
            }
        }
    }

    public func run(_ js: String, _ args: [String: Any] = [:], done: @escaping @MainActor (Any?) -> Void) {
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { result in
            if case .success(let v) = result { done(v) } else { done(nil) }
        }
    }
}

/// The right pane's document view: the shared editor web view, re-parented like terminals.
struct DocumentEditorView: NSViewRepresentable {
    let editor: EditorController
    let file: URL

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ host: NSView, context: Context) {
        let web = editor.webView
        if web.superview !== host {
            web.removeFromSuperview()
            web.frame = host.bounds
            web.autoresizingMask = [.width, .height]
            host.addSubview(web)
        }
        editor.open(file)
    }
}
