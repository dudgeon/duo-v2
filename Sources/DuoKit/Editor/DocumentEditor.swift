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
    /// Notifies like the other bar states: a read-only reason left from a file that vanished mid-switch
    /// kept its bar over the next document, which open() had already cleared (F-262).
    public private(set) var readOnlyReason: String? { didSet { if oldValue != readOnlyReason { onStateChange?() } } }
    public private(set) var lastEvent: String = "idle"   // for the harness and logs
    // MARK: Lifecycle (DL-167 step 5)
    //
    // One document lifecycle, and one generation token. `phase` says what the document on screen is;
    // `generation` changes every time the document on screen changes (a different file shown, or
    // closed). Every asynchronous reply (a save's text, a merge, a load, a watcher's settle) captures
    // the generation when it starts and is dropped by design if it changed, instead of asking
    // `self.url == file`, which cannot tell A from A shown again after B (F-44, F-52, F-263).

    /// What the document on screen is.
    public enum Phase: Equatable {
        case closed      // no document
        case opening     // chosen; its bytes are not in the page yet (the page may still be loading): nothing may save
        case open        // in the page; saves and merges run
        case conflict    // an outside change overlapped unsaved edits (LR-32); autosave pauses
        case removed     // gone from disk (DL-77); the buffer stays and autosave pauses
    }
    public private(set) var phase: Phase = .closed {
        didSet { if (oldValue == .conflict) != (phase == .conflict) || (oldValue == .removed) != (phase == .removed) { onStateChange?() } }
    }
    /// Changes whenever the document on screen changes; see above.
    private(set) var generation = 0
    /// An outside change overlapped unsaved edits. Autosave pauses until it's resolved (LR-32):
    /// saving now would overwrite the other writer's change on disk. The banner is Q-20.
    public var conflict: Bool { phase == .conflict }
    public private(set) var dirty = false
    /// When the user last changed the text: a task's note moves to its new name only once typing pauses (C-24).
    public private(set) var lastTyped = Date.distantPast
    private var pageReady = false
    /// Whether the editor page has finished loading (scripted captures report it).
    public var isPageReady: Bool { pageReady }
    private var pending: (() -> Void)?
    /// The document asked for while the one on screen merges an outside write before its save
    /// (BUG-085 in legacy Duo): the latest ask wins.
    private var switchingTo: URL?
    private var diskBytes = Data()                       // what's on disk as far as we know
    private var watcher: DispatchSourceFileSystemObject?
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var settle: DispatchWorkItem?
    private var saveTask: Task<Void, Never>?
    /// The file is gone from disk (deleted or moved outside Duo). The buffer stays; autosave
    /// pauses so Duo doesn't quietly recreate a file someone removed (DL-77).
    public var removedOnDisk: Bool { phase == .removed }
    /// Renamed or moved on disk by something else; Duo followed it (S3-4). The new path, until dismissed.
    public var renamedTo: String? { didSet { if oldValue != renamedTo { onStateChange?() } } }
    /// Called when Duo follows a rename it saw on disk: old file, new file.
    var onRenamed: ((URL, URL) -> Void)?
    private var fileFD: Int32 = -1
    /// Called when conflict or removed-on-disk changes (the bars under the document redraw).
    var onStateChange: (() -> Void)?
    /// A link clicked in the document (DL-87): its target as written.
    var onOpenLink: ((String) -> Void)?
    /// The properties block's controls (S2-5): `propertyMenu` (status popup), `propertyAdd` (+ Add).
    var onPropertyAction: ((String, [String: Any]) -> Void)?
    private var noteContext = ""
    /// Whether a file is a template, and which kind (DL-146): its placeholders show as chips.
    var templateKindFor: ((URL) -> String?)?
    /// A template's Preview is showing (board A2): the filled file, read-only. The document under
    /// it is untouched; saves still save the document, never the preview.
    public private(set) var previewing = false { didSet { if oldValue != previewing { onStateChange?() } } }
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
    public static func tokenCSS() -> String {
        func hex(_ c: NSColor) -> String {
            let s = c.usingColorSpace(.sRGB) ?? c
            return String(format: "#%02X%02X%02X", Int(round(s.redComponent * 255)), Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
        }
        let vars = [("pane", DuoNSColor.pane), ("text", DuoNSColor.text), ("text2", DuoNSColor.text2), ("selected", DuoNSColor.selected),
                    ("rule", DuoNSColor.rule), ("control-edge", DuoNSColor.controlEdge), ("ground", DuoNSColor.ground), ("needs-you", DuoNSColor.needsYou)]
            .map { "--duo-\($0.0): \(hex($0.1));" }.joined(separator: " ")
        // Motion (DL-130): Claude's highlight fading in and out, in ms (zero with Reduce Motion).
        // The deck (same token script): a slide change's scroll and the picker outline's glide.
        let motion = [("highlight-in", DuoMotionToken.highlightIn), ("highlight-out", .highlightOut), ("slide", .slide), ("outline", .outline)]
            .map { "--duo-motion-\($0.0)-ms: \(Int(($0.1.duration * 1000).rounded()));" }.joined(separator: " ")
        let css = ":root { \(vars) --duo-radius-card: \(Int(DuoMetric.radiusCard))px; --duo-heading-above: \(Int(DuoSpace.gapAboveDocumentHeading))px; \(motion) }"
        return "document.documentElement.setAttribute('style', \(String(reflecting: css)).replace(/^:root \\{ | \\}$/g, ''));"
    }

    public func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        pageReady = true
        pending?(); pending = nil
        if !noteContext.isEmpty { webView.evaluateJavaScript("window.__ctx = \(noteContext); window.duo && duo.setContext(window.__ctx)") }
    }

    /// Shows a file. The current document is saved first if it changed; one in conflict, or
    /// removed on disk, keeps its unsaved text in memory until it's shown again.
    public func open(_ file: URL) {
        if switchingTo != nil { switchingTo = file; return }
        guard file != url else { return }
        // Never a file that isn't text (C-26): the right pane shows it another way, and nothing
        // (a `duo2 doc` verb included) can load its bytes here as text.
        if FileKind.isBinary(file) { DuoLog.write("editor: not opening \(file.lastPathComponent): it isn't text"); return }
        if let leaving = url, readOnlyReason == nil, dirty, !conflict, !removedOnDisk, !FileKind.isBinary(file),
           let now = FileManager.default.contents(atPath: leaving.path), now != diskBytes {
            // An outside write the watcher hasn't delivered yet. Merge it into this document and
            // save before switching: the merge needs this document's text in the page, and
            // loading the next one first threw the typing away (legacy BUG-085).
            switchingTo = file
            reconcile(leaving) { [weak self] in
                guard let self else { return }
                if self.conflict { self.finishSwitch() } else { self.saveNow { [weak self] in self?.finishSwitch() } }
            }
            return
        }
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
        generation += 1
        phase = .opening
        renamedTo = nil
        previewing = false
        url = file
        readOnlyReason = nil
        let go: () -> Void = { [weak self] in self?.load(file) }
        if pageReady { go() } else { pending = go }
    }

    private func finishSwitch() {
        guard let next = switchingTo else { return }
        switchingTo = nil
        open(next)
    }

    /// Ends a conflict (DL-77). Mine: the user's text is saved over the file (the file's version
    /// is in history). Theirs: the file's version replaces the user's text (theirs is in history).
    public func resolve(keepMine: Bool, done: (@MainActor (Bool) -> Void)? = nil) {
        guard conflict, let file = url, case let gen = generation, let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else { done?(false); return }
        if keepMine {
            FileHistory.snapshot(file, data, source: "resolve-mine")
            diskBytes = data
            webView.callAsyncJavaScript("duo.setBaseText(b); duo.markConflict(null); return 1", arguments: ["b": text], in: nil, in: .page) { [weak self] _ in
                guard let self, self.generation == gen else { done?(false); return }
                self.phase = .open
                self.dirty = true
                self.lastEvent = "kept mine"
                self.saveNow { done?(true) }
            }
        } else {
            webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] r in
                guard let self, self.generation == gen else { done?(false); return }
                if case .success(let t) = r, let t = t as? String { FileHistory.snapshot(file, Data(t.utf8), source: "resolve-theirs") }
                self.diskBytes = data
                self.webView.callAsyncJavaScript("const r = duo.create(t); duo.markSaved(); return r", arguments: ["t": text], in: nil, in: .page) { _ in
                    guard self.generation == gen else { done?(false); return }
                    self.phase = .open
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
        let gen = generation
        webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { [weak self] r in
            guard let self, self.generation == gen, case .success(let t) = r, let t = t as? String else { done?(false); return }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(t.utf8).write(to: file, options: .withoutOverwriting)
                self.diskBytes = Data(t.utf8)
                self.phase = .open
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
        let gen = generation
        guard url == file else { return }
        // diskBytes is set below, in this same turn: from here on a save compares with this file.
        defer { if phase == .opening { phase = .open } }
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
            webView.callAsyncJavaScript("window.__folded = f; const r = duo.create(t); duo.setBaseText(b); return r", arguments: ["t": k.text, "b": baseText, "f": Self.folded(file)], in: nil, in: .page) { [weak self] _ in
                guard let self, self.generation == gen else { return }
                self.lastEvent = "reopened with unsaved edits"
                self.applyTemplateMode(file)
                self.reconcile(file)
            }
            watch(file)
            return
        }
        webView.callAsyncJavaScript("window.__folded = f; const r = duo.create(t); duo.markSaved(); return r", arguments: ["t": text, "f": Self.folded(file)], in: nil, in: .page) { [weak self] result in
            guard let self, self.generation == gen else { return }
            if case .success(let info) = result, let d = info as? [String: Any], (d["mixedLineEndings"] as? Bool) == true {
                self.readOnlyReason = "mixed line endings"
            }
            self.applyTemplateMode(file)
            self.lastEvent = self.readOnlyReason == nil ? "opened" : "read-only"
        }
        watch(file)
    }

    /// An image beside the document, as a data URL (10 MB at most), or nil if it isn't there.
    func imageDataURL(_ src: String) -> String? {
        guard let doc = url else { return nil }
        let rel = src.removingPercentEncoding ?? src
        let file = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : doc.deletingLastPathComponent().appending(path: rel).standardizedFileURL
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 10_000_000,
              let data = FileManager.default.contents(atPath: file.path) else { return nil }
        let type: String
        switch file.pathExtension.lowercased() {
        case "png": type = "image/png"
        case "jpg", "jpeg": type = "image/jpeg"
        case "gif": type = "image/gif"
        case "webp": type = "image/webp"
        case "svg": type = "image/svg+xml"
        case "heic": type = "image/heic"
        default: return nil
        }
        return "data:\(type);base64," + data.base64EncodedString()
    }

    /// A picture pasted or dropped in the editor (LR-39): written beside the document under a
    /// fresh name, then linked on its own line at the caret or drop point.
    func savePastedImage(_ body: [String: Any]) {
        guard let doc = url, readOnlyReason == nil,
              let mime = body["mime"] as? String, let ext = ImagePaste.fileExtension(mime: mime),
              let b64 = body["data"] as? String, let data = Data(base64Encoded: b64), data.count < 25_000_000 else { return }
        let dir = doc.deletingLastPathComponent(), fm = FileManager.default
        let name = ImagePaste.fileName(docStem: doc.deletingPathExtension().lastPathComponent, date: Date(), ext: ext) {
            fm.fileExists(atPath: dir.appending(path: $0).path)
        }
        do { try data.write(to: dir.appending(path: name), options: .atomic) } catch { lastEvent = "image not saved: \(error.localizedDescription)"; return }
        let id = body["id"] as? Int ?? -1
        webView.callAsyncJavaScript("return duo.insertImage(m, i)", arguments: ["m": ImagePaste.link(fileName: name), "i": id], in: nil, in: .page) { _ in }
        lastEvent = "image saved: \(name)"
    }

    /// Whether this document's properties block was left folded.
    static func folded(_ file: URL) -> Bool { DuoState.load().foldedProperties.contains(file.standardizedFileURL.path) }

    /// Remembers the fold, per document (frontmatter-handoff §2).
    func rememberFold(_ folded: Bool) {
        guard let path = url?.standardizedFileURL.path else { return }
        DuoState.update { s in
            s.foldedProperties.removeAll { $0 == path }
            if folded { s.foldedProperties.append(path) }
        }
    }

    /// What the properties block shows about the note's sessions (S2-5): JSON, sent when it changes.
    public func setNoteContext(_ json: String) {
        guard json != noteContext else { return }
        noteContext = json
        guard pageReady else { return }
        webView.evaluateJavaScript("window.__ctx = \(json); window.duo && duo.setContext(window.__ctx)")
    }

    // MARK: Saving

    public func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        if let body = m.body as? [String: Any], body["kind"] as? String == "openLink", let link = body["url"] as? String {
            onOpenLink?(link); return
        }
        if let body = m.body as? [String: Any], body["kind"] as? String == "image", let id = body["id"] as? Int, let src = body["src"] as? String {
            // An image in the document (S3-5): the page can't read the project, so Duo hands it over.
            webView.callAsyncJavaScript("return duo.imageLoaded(i, u)", arguments: ["i": id, "u": imageDataURL(src) ?? NSNull()], in: nil, in: .page) { _ in }
            return
        }
        if let body = m.body as? [String: Any], body["kind"] as? String == "pasteImage" {
            savePastedImage(body); return
        }
        if let body = m.body as? [String: Any], body["kind"] as? String == "tableMenu" {
            tableMenu(body["menu"] as? String ?? "", at: NSPoint(x: body["x"] as? Double ?? 0, y: (body["y"] as? Double ?? 0) + 2)); return
        }
        if let body = m.body as? [String: Any], body["kind"] as? String == "noteEdit" {
            // The properties block's own controls (the references field) ask Swift to write (DL-167 step 4).
            let link = body["link"] as? String ?? "", target = body["target"] as? String ?? ""
            switch body["op"] as? String {
            case "addReference": applyNoteEdit(.addReference(link: link))
            case "removeReference": applyNoteEdit(.removeReference(target: target))
            case "addSession": applyNoteEdit(.addSession(link: link))
            case "status": applyNoteEdit(.status(body["status"] as? String, completed: body["completed"] as? String))
            default: break
            }
            return
        }
        if let body = m.body as? [String: Any], let kind = body["kind"] as? String, kind.hasPrefix("property") {
            onPropertyAction?(kind, body); return
        }
        guard let body = m.body as? [String: Any], body["kind"] as? String == "selection" else { return }
        // A report from a page state that is no longer on screen (the page tags reports with the document it shows).
        if let doc = body["doc"] as? String, let shown = url?.standardizedFileURL.path, doc != shown { return }
        let count = body["claudeChanges"] as? Int ?? 0, atCaret = body["atClaudeChange"] as? Bool == true, table = body["inTable"] as? Bool == true
        if count != claudeChanges || atCaret != atClaudeChange || table != inTable {
            claudeChanges = count; atClaudeChange = atCaret; inTable = table; onStateChange?()
        }
        dirty = body["dirty"] as? Bool == true
        guard dirty else { return }
        lastTyped = Date()
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
        switch phase {
        case .closed, .opening: completion?(); return   // nothing of this file is in the page yet
        case .conflict: lastEvent = "save paused: conflict"; completion?(); return
        case .removed: lastEvent = "save paused: removed on disk"; completion?(); return
        case .open: break
        }
        let gen = generation
        if let now = FileManager.default.contents(atPath: file.path), now != diskBytes {
            // An outside write the watcher hasn't delivered yet: merge first, then save.
            reconcile(file) { [weak self] in
                guard let self, self.generation == gen, !self.conflict else { completion?(); return }
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
            let stillOpen = self.generation == gen   // else another document is on screen now, even if it is this file again
            // Last look before writing: an outside write that landed while the text came back.
            if let now = FileManager.default.contents(atPath: file.path), now != baseline {
                if stillOpen {
                    self.reconcile(file) { [weak self] in
                        guard let self, self.generation == gen, !self.conflict else { completion?(); return }
                        self.saveNow(completion: completion)
                    }
                } else if data != baseline {
                    // Switched away while the text came back, and the file changed meanwhile:
                    // never write blind over it. Keep the text; it merges when the file is shown again.
                    self.kept[file] = (text, baseline, false)
                    self.lastEvent = "kept unsaved edits: \(file.lastPathComponent) changed on disk"
                }
                if !stillOpen { completion?() }
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
        fileFD = fd
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
        let gen = generation
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == gen else { return }
                // Renamed or moved by something else: the open descriptor knows where it went.
                // Follow it, unless it went to the Trash (then it reads as removed).
                if !FileManager.default.fileExists(atPath: file.path), self.fileFD >= 0 {
                    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                    if fcntl(self.fileFD, F_GETPATH, &buf) != -1 {
                        let now = URL(fileURLWithPath: String(cString: buf))
                        if now.path != file.resolvingSymlinksInPath().path, !now.path.contains("/.Trash/"),
                           FileManager.default.fileExists(atPath: now.path) {
                            self.fileMoved(to: now)
                            self.renamedTo = now.path
                            self.lastEvent = "renamed on disk"
                            self.onRenamed?(file, now)
                            return
                        }
                    }
                }
                self.watch(file)          // re-arm on the current inode (or the file's return)
                self.reconcile(file)
            }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Brings what's on disk into the editor: merged by line with unsaved edits, or a conflict
    /// (DL-77). A missing file marks the document removed on disk; its return clears that.
    // MARK: Templates (DL-146)

    /// Placeholder chips and the template's look on, for a template file; off for any other.
    func applyTemplateMode(_ file: URL) {
        let kind = templateKindFor?(file)
        webView.callAsyncJavaScript("return duo.setTemplate(t)", arguments: ["t": kind.map { ["kind": $0] as Any } ?? NSNull()], in: nil, in: .page, completionHandler: nil)
    }

    /// Preview (board A2): shows `text`, read-only, over the template.
    public func startPreview(_ text: String, done: (@MainActor () -> Void)? = nil) {
        previewing = true
        run("return duo.preview(t)", ["t": text]) { _ in done?() }
    }

    /// Back to the template, as it was.
    public func endPreview(done: (@MainActor () -> Void)? = nil) {
        guard previewing else { done?(); return }
        previewing = false
        run("return duo.endPreview()") { _ in done?() }
    }

    /// A property or list edit to the open task note (DL-167 step 4). The text comes from Swift's
    /// writers (`TaskNotes.apply`) and lands as one plain, undoable change that keeps the caret, not
    /// highlighted as Claude's. The page applies it only if the document is still the text Swift
    /// worked from (typing in between asks for another go).
    public func applyNoteEdit(_ edit: TaskNotes.NoteEdit, attempts: Int = 3, done: (@MainActor (Bool) -> Void)? = nil) {
        guard readOnlyReason == nil, phase == .open || phase == .conflict || phase == .removed else { done?(false); return }
        let gen = generation
        run("return duo.text()") { [weak self] v in
            guard let self, self.generation == gen, let text = v as? String else { done?(false); return }
            guard let new = TaskNotes.apply(edit, to: text) else { done?(false); return }
            self.run("return duo.applyPlain(b, t)", ["b": text, "t": new]) { [weak self] ok in
                guard let self, self.generation == gen else { done?(false); return }
                if ok as? Bool == true { done?(true) }
                else if attempts > 1 { self.applyNoteEdit(edit, attempts: attempts - 1, done: done) }
                else { self.lastEvent = "note edit not applied: the text kept changing"; done?(false) }
            }
        }
    }

    /// The template bar's Insert ▾: text typed at the caret, as the user would type it.
    public func insertAtCaret(_ text: String) {
        run("return duo.insertAtCaret(t)", ["t": text]) { _ in }
    }

    /// The template the editor shows now, as text (the document, never the preview).
    public func currentText(_ done: @escaping @MainActor (String?) -> Void) {
        run("return duo.text()") { v in done(v as? String) }
    }

    private func reconcile(_ file: URL, then: (@MainActor () -> Void)? = nil) {
        if previewing { endPreview() }   // the document takes the change, not the preview
        let gen = generation
        guard phase != .opening, phase != .closed else { then?(); return }
        guard let data = FileManager.default.contents(atPath: file.path) else {
            if !FileManager.default.fileExists(atPath: file.path), phase == .open {
                phase = .removed
                lastEvent = "removed on disk"
                FileHistory.snapshot(file, diskBytes, source: "removed")
            }
            then?(); return
        }
        if phase == .removed { phase = .open; lastEvent = "back on disk" }
        guard data != diskBytes else { then?(); return }
        guard let text = String(data: data, encoding: .utf8) else {
            // Rewritten as something that isn't UTF-8: show nothing new, save nothing over it.
            readOnlyReason = "changed on disk to text that isn't UTF-8"
            lastEvent = "read-only"; then?(); return
        }
        webView.callAsyncJavaScript("return duo.external(d)", arguments: ["d": text], in: nil, in: .page) { [weak self] result in
            guard let self, self.generation == gen else { then?(); return }
            if case .success(let v) = result, let r = (v as? [String: Any])?["result"] as? String {
                if r == "conflict" {
                    // Keep the user's text and the base it was edited from; disk stays as is.
                    // Both sides go to history first; the bar for choosing is a stub (Q-20).
                    self.conflictLines = ((v as? [String: Any])?["lines"] as? [[Int]]) ?? []
                    FileHistory.snapshot(file, data, source: "conflict-theirs")
                    self.webView.callAsyncJavaScript("return duo.text()", arguments: [:], in: nil, in: .page) { r in
                        if case .success(let t) = r, let t = t as? String { FileHistory.snapshot(file, Data(t.utf8), source: "conflict-mine") }
                    }
                    self.phase = .conflict
                    self.webView.callAsyncJavaScript("return duo.markConflict(l)", arguments: ["l": self.conflictLines], in: nil, in: .page) { _ in }
                } else {
                    self.diskBytes = data
                    if self.phase == .conflict { self.phase = .open }
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
        if let old = url, kept[old] != nil { kept[newURL] = kept.removeValue(forKey: old) }
        url = newURL
        watch(newURL)
        reconcile(newURL)   // anything written just before the move (a rename's new title) comes in
    }

    /// The open file is gone (moved to the Trash): stop watching and never save it again.
    public func closeFile() {
        watcher?.cancel(); watcher = nil
        folderWatcher?.cancel(); folderWatcher = nil
        if let u = url { kept[u] = nil }
        saveTask?.cancel()
        url = nil
        generation += 1
        phase = .closed
        dirty = false
    }

    /// Whether a document left while in conflict is waiting with its unsaved text (S3-4: its tab says so).
    public func keptInConflict(_ file: URL) -> Bool { kept[file]?.conflict == true }

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

    /// + New task: once `path` is the open document, its heading's name is selected and the editor
    /// has the keyboard, so typing names the task (`title:` follows the heading).
    public func selectHeading(path: String, tries: Int = 20) {
        let retry = { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self.selectHeading(path: path, tries: tries - 1) } } }
        guard url?.path.hasSuffix("/" + path) == true else { if tries > 0 { retry() }; return }
        run("return window.duo && duo.selectHeading ? duo.selectHeading() : false") { [weak self] ok in
            guard let self else { return }
            if (ok as? Bool) == true { self.webView.window?.makeFirstResponder(self.webView) } else if tries > 0 { retry() }
        }
    }

    /// Claude's changes still highlighted (ENH-4), and whether the caret is in one.
    public private(set) var claudeChanges = 0
    public private(set) var atClaudeChange = false
    /// The caret is in a table: Format › Table's row and column items apply (DL-113).
    public private(set) var inTable = false

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

extension EditorController {
    /// The table bar's Align ▾ and Delete ▾ (DL-113): the system's menu under the button, with
    /// the same items as Format › Table.
    func tableMenu(_ which: String, at point: NSPoint) {
        let menu = NSMenu()
        let items: [(String, String)] = which == "align"
            ? [("Left", "tableAlignLeft"), ("Center", "tableAlignCenter"), ("Right", "tableAlignRight")]
            : [("Delete Row", "tableDeleteRow"), ("Delete Column", "tableDeleteColumn")]
        for (title, name) in items {
            menu.addItem(ActionMenuItem(title) { [weak self] in self?.run("duo.exec(f); return 1", ["f": name]) { _ in } })  // action: doc table
        }
        menu.popUp(positioning: nil, at: point, in: webView)
    }
}
