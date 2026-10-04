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
    public private(set) var conflict = false { didSet { if oldValue != conflict { onStateChange?() } } }
    public private(set) var dirty = false
    private var pageReady = false
    private var pending: (() -> Void)?
    private var diskBytes = Data()                       // what's on disk as far as we know
    private var watcher: DispatchSourceFileSystemObject?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var settle: DispatchWorkItem?
    private var saveTask: Task<Void, Never>?
    /// The file is gone from disk (deleted or moved outside Duo). The buffer stays; autosave
    /// pauses so Duo doesn't quietly recreate a file someone removed (DL-77).
    public private(set) var removedOnDisk = false { didSet { if oldValue != removedOnDisk { onStateChange?() } } }
    /// Called when conflict or removed-on-disk changes (the bars under the document redraw).
    var onStateChange: (() -> Void)?
    /// Lines of the last conflict (1-based, in the base), for the bar and `duo2 doc status`.
    public private(set) var conflictLines: [[Int]] = []
    /// Unsaved text of documents left while in conflict or removed, kept until they're shown
    /// again (DL-77: nothing is dropped when you look away).
    private var kept: [URL: (text: String, base: Data, conflict: Bool)] = [:]

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

    /// Shows a file. The current document is saved first if it changed; one in conflict, or
    /// removed on disk, keeps its unsaved text in memory until it's shown again.
    public func open(_ file: URL) {
        guard file != url else { return }
        if let leaving = url, readOnlyReason == nil, dirty, conflict || removedOnDisk {
            let base = diskBytes, wasConflict = conflict
            // Runs before the next document's text is loaded: the page runs scripts in order.
            webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] r in
                if case .success(let v) = r, let text = v as? String { self?.kept[leaving] = (text, base, wasConflict) }
            }
        } else {
            saveNow(force: true)
        }
        dirty = false
        conflict = false
        removedOnDisk = false
        url = file
        readOnlyReason = nil
        let go: () -> Void = { [weak self] in self?.load(file) }
        if pageReady { go() } else { pending = go }
    }

    /// Ends a conflict (DL-77). Mine: the user's text is saved over the file (the file's version
    /// is in history). Theirs: the file's version replaces the user's text (theirs is in history).
    public func resolve(keepMine: Bool, done: (@MainActor (Bool) -> Void)? = nil) {
        guard conflict, let file = url, let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else { done?(false); return }
        if keepMine {
            FileHistory.snapshot(file, data, source: "resolve-mine")
            diskBytes = data
            webView.callAsyncJavaScript("duo.setBaseText(b); return 1", arguments: ["b": text], in: nil, in: .page) { [weak self] _ in
                guard let self else { return }
                self.conflict = false
                self.dirty = true
                self.lastEvent = "kept mine"
                self.saveNow { done?(true) }
            }
        } else {
            webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] r in
                guard let self else { return }
                if case .success(let t) = r, let t = t as? String { FileHistory.snapshot(file, Data(t.utf8), source: "resolve-theirs") }
                self.diskBytes = data
                self.webView.callAsyncJavaScript("const r = duo.create(t); duo.markSaved(); return r", arguments: ["t": text], in: nil, in: .page) { _ in
                    self.conflict = false
                    self.dirty = false
                    self.lastEvent = "took theirs"
                    done?(true)
                }
            }
        }
    }

    /// The file was removed on disk: write the user's text back to where it was.
    public func recreate(done: (@MainActor (Bool) -> Void)? = nil) {
        guard removedOnDisk, let file = url else { done?(false); return }
        webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] r in
            guard let self, case .success(let t) = r, let t = t as? String else { done?(false); return }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(t.utf8).write(to: file, options: .withoutOverwriting)
                self.diskBytes = Data(t.utf8)
                self.removedOnDisk = false
                self.dirty = false
                self.webView.evaluateJavaScript("duo.markSaved()")
                self.watch(file)
                self.lastEvent = "recreated"
                done?(true)
            } catch { done?(false) }
        }
    }

    /// Shows text that will never be saved (a file that isn't UTF-8, or can't be read).
    private func showReadOnly(_ text: String) {
        webView.callAsyncJavaScript("const r = duo.create(t); duo.markSaved(); duo.setReadOnly(true); return r", arguments: ["t": text], in: nil, in: .page, completionHandler: nil)
    }

    /// Saves now if it safely can (quit, closing the window). Calls back when done.
    public func flush(_ done: @escaping @MainActor () -> Void) {
        saveTask?.cancel()
        saveNow(force: true, completion: done)
    }

    private func load(_ file: URL) {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            readOnlyReason = "can't read the file"; lastEvent = "unreadable"
            showReadOnly("")
            return
        }
        diskBytes = data
        FileHistory.snapshot(file, data, source: "open")
        guard let text = String(data: data, encoding: .utf8), Data(text.utf8) == data else {
            // Not valid UTF-8: shown as best decoded, read-only, never saved (LR-30). Leaving
            // the editor alone showed the previous document under this one's tab.
            readOnlyReason = "not UTF-8"
            lastEvent = "read-only"
            showReadOnly(String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) ?? "")
            watch(file)
            return
        }
        if let k = kept.removeValue(forKey: file), let baseText = String(data: k.base, encoding: .utf8) {
            // Back to a document left with unsaved text: show that text over the base it was
            // edited from, then reconcile with what's on disk now (it may merge cleanly now).
            diskBytes = k.base
            dirty = true
            webView.callAsyncJavaScript("const r = duo.create(t); duo.setBaseText(b); return r", arguments: ["t": k.text, "b": baseText], in: nil, in: .page) { [weak self] _ in
                guard let self else { return }
                self.lastEvent = "reopened with unsaved edits"
                self.reconcile(file)
            }
            watch(file)
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
        let count = body["claudeChanges"] as? Int ?? 0, atCaret = body["atClaudeChange"] as? Bool == true
        if count != claudeChanges || atCaret != atClaudeChange { claudeChanges = count; atClaudeChange = atCaret; onStateChange?() }
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

    /// Writes the buffer if it differs from disk: temp file, then rename (LR-35). Never blind
    /// (DL-77): if the file changed on disk since Duo last read it, that change is merged in
    /// first, and a conflict stops the save.
    /// `force`: compare the text with the file even if the editor hasn't reported unsaved changes
    /// yet (quit, closing a tab): the report trails fast typing, and a quit right after typing
    /// lost the last word (F-52).
    public func saveNow(force: Bool = false, completion: (@MainActor () -> Void)? = nil) {
        guard let file = url, readOnlyReason == nil else { completion?(); return }
        if conflict { lastEvent = "save paused: conflict"; completion?(); return }
        if removedOnDisk { lastEvent = "save paused: removed on disk"; completion?(); return }
        if let now = FileManager.default.contents(atPath: file.path), now != diskBytes {
            // An outside write the watcher hasn't delivered yet: merge first, then save.
            reconcile(file) { [weak self] in
                guard let self, !self.conflict, self.url == file else { completion?(); return }
                self.saveNow(completion: completion)
            }
            return
        }
        // Nothing typed since the last save: nothing to write (opening a file never writes it).
        guard dirty || force else { completion?(); return }
        // Capture the file and its baseline now: switching documents loads the next file before
        // this save's text comes back, and comparing against *its* bytes rewrote this file (F-44).
        let baseline = diskBytes
        webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String else { completion?(); return }
            let data = Data(text.utf8)
            let stillOpen = self.url == file
            // Last look before writing: an outside write that landed while the text came back.
            if let now = FileManager.default.contents(atPath: file.path), now != baseline, stillOpen {
                self.reconcile(file) { [weak self] in
                    guard let self, !self.conflict else { completion?(); return }
                    self.saveNow(completion: completion)
                }
                return
            }
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

    /// Watches the file and its folder (LR-36): editors that save by writing a new file and
    /// renaming it over the old one replace the inode, which only the folder sees. Events settle
    /// for 150 ms; then the file is read and compared by content with what Duo last read or
    /// wrote, so Duo's own saves never look like outside changes.
    private func watch(_ file: URL) {
        watcher?.cancel(); watcher = nil
        folderWatcher?.cancel(); folderWatcher = nil
        let real = file.resolvingSymlinksInPath()
        let fd = Darwin.open(real.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.diskChanged() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            watcher = src
        }
        let dfd = Darwin.open(real.deletingLastPathComponent().path, O_EVTONLY)
        if dfd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dfd, eventMask: [.write, .rename, .delete], queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.diskChanged() } }
            src.setCancelHandler { close(dfd) }
            src.resume()
            folderWatcher = src
        }
    }

    private func diskChanged() {
        guard let file = url else { return }
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.url == file else { return }
                self.watch(file)          // re-arm on the current inode (or the file's return)
                self.reconcile(file)
            }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Brings what's on disk into the editor: merged by line with unsaved edits, or a conflict
    /// (DL-77). A missing file marks the document removed on disk; its return clears that.
    private func reconcile(_ file: URL, then: (@MainActor () -> Void)? = nil) {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            if !FileManager.default.fileExists(atPath: file.path), !removedOnDisk {
                removedOnDisk = true
                lastEvent = "removed on disk"
                FileHistory.snapshot(file, diskBytes, source: "removed")
            }
            then?(); return
        }
        if removedOnDisk { removedOnDisk = false; lastEvent = "back on disk" }
        guard data != diskBytes else { then?(); return }
        guard let text = String(data: data, encoding: .utf8) else {
            // Rewritten as something that isn't UTF-8: show nothing new, save nothing over it.
            readOnlyReason = "changed on disk to text that isn't UTF-8"
            lastEvent = "read-only"; then?(); return
        }
        webView.callAsyncJavaScript("return duo.external(d)", arguments: ["d": text], in: nil, in: .page) { [weak self] result in
            guard let self, self.url == file else { then?(); return }
            if case .success(let v) = result, let r = (v as? [String: Any])?["result"] as? String {
                if r == "conflict" {
                    // Keep the user's text and the base it was edited from; disk stays as is.
                    // Both sides go to history first; the bar for choosing is a stub (Q-20).
                    self.conflictLines = ((v as? [String: Any])?["lines"] as? [[Int]]) ?? []
                    FileHistory.snapshot(file, data, source: "conflict-theirs")
                    self.webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { r in
                        if case .success(let t) = r, let t = t as? String { FileHistory.snapshot(file, Data(t.utf8), source: "conflict-mine") }
                    }
                    self.conflict = true
                } else {
                    self.diskBytes = data
                    self.conflict = false
                    if r == "same" || r == "applied" { self.dirty = r == "applied" ? self.dirty : false }
                }
                self.lastEvent = "outside change: \(r)"
            }
            then?()
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
        folderWatcher?.cancel(); folderWatcher = nil
        if let u = url { kept[u] = nil }
        saveTask?.cancel()
        url = nil
        dirty = false; conflict = false; removedOnDisk = false
    }

    /// What `duo2 doc-status` reports (LR-34).
    public func status(of file: URL) -> String {
        guard let url, url.standardizedFileURL.resolvingSymlinksInPath() == file.standardizedFileURL.resolvingSymlinksInPath() else {
            return "not open in Duo"
        }
        if conflict {
            let where_ = conflictLines.map { $0[0] == $0[1] ? "line \($0[0])" : "lines \($0[0])–\($0[1])" }.joined(separator: ", ")
            return "open in Duo, in conflict\(where_.isEmpty ? "" : " at \(where_)"): an outside change and the user's unsaved edits touch the same lines; Duo saves neither over the other until the user chooses (Keep Mine or Use Theirs, or `duo2 doc resolve mine|theirs` if they ask you to). Both versions are in history."
        }
        if removedOnDisk { return "open in Duo, but removed on disk; the user's text is kept" }
        if readOnlyReason != nil { return "open in Duo, read-only (\(readOnlyReason!))" }
        let how = "The user has it open: change it with `duo2 doc edit --stdin` (your Edit tool's JSON) or `duo2 doc replace`, so they see the change highlighted; don't write the file."
        return (dirty ? "open in Duo with unsaved edits. " : "open in Duo, saved. ") + how
    }

    /// Outlines the lines a search result matched once `path` is the open document
    /// (search-open-file): `L40–58 · from search`, matched words semibold.
    public func revealFromSearch(path: String, lines: ClosedRange<Int>, words: [String], tries: Int = 20) {
        let ready = url?.path.hasSuffix("/" + path) == true || url?.path == path
        guard ready else {
            if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.revealFromSearch(path: path, lines: lines, words: words, tries: tries - 1) } } }
            return
        }
        let label = (lines.count > 1 ? "L\(lines.lowerBound)–\(lines.upperBound)" : "L\(lines.lowerBound)") + " · from search"
        run("return window.duo && duo.revealFromSearch ? duo.revealFromSearch(a, b, label, words) : false",
            ["a": lines.lowerBound, "b": lines.upperBound, "label": label, "words": words]) { ok in
            if (ok as? Bool) != true, tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.revealFromSearch(path: path, lines: lines, words: words, tries: tries - 1) } }
            }
        }
    }

    /// Claude's changes still highlighted (ENH-4), and whether the caret is in one.
    public private(set) var claudeChanges = 0
    public private(set) var atClaudeChange = false

    /// Puts back what Claude's change at the caret replaced (ENH-4).
    public func revertAtCaret(_ done: (@MainActor (Int) -> Void)? = nil) {
        run("return duo.revertAt()") { v in done?((v as? Int) ?? 0) }
    }

    /// Puts back everything Claude changed since your last edit (ENH-4).
    public func revertAll(_ done: (@MainActor (Int) -> Void)? = nil) {
        run("return duo.revertAll()") { v in done?((v as? Int) ?? 0) }
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
