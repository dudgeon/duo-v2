import AppKit
import Foundation

/// Send to Claude (DL-67–DL-69): puts context into a Claude session's prompt without pressing
/// Enter, so the request can be written around it. The target is the session showing in the
/// console (Home's at All projects), or any running session from the Send to ▸ submenu.
extension AppModel {
    /// A running Claude session that can receive context.
    public struct SendTarget: Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let title: String
        public let project: String
    }

    /// Every Claude session with a live process in Duo, the visible one first.
    public var sendTargets: [SendTarget] {
        let visible = visibleSessionId
        return terminals.all.filter { $0.isLiveClaude && $0.notReadyReason == nil }.map { t in
            let s = fixture.sessions.first { $0.tabKey == t.key }
            return SendTarget(key: t.key, title: s?.name ?? "Session", project: s?.project ?? "")
        }.sorted { a, b in
            if (a.key == visible) != (b.key == visible) { return a.key == visible }
            if a.project != b.project { return a.project.localizedStandardCompare(b.project) == .orderedAscending }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// The visible session, when it can take context; otherwise why not (for the menu item).
    public var sendTarget: Result<SendTarget, SendUnavailable> {
        guard let key = visibleSessionId else { return .failure(.init(reason: "No session is showing")) }
        guard let t = terminals.existing(key) else { return .failure(.init(reason: "The session showing isn't running")) }
        guard t.isClaude else { return .failure(.init(reason: "The tab showing is a shell, not Claude")) }
        guard t.isLiveClaude else { return .failure(.init(reason: "The session showing has ended")) }
        if let why = t.notReadyReason { return .failure(.init(reason: why)) }
        let s = fixture.sessions.first { $0.tabKey == key }
        return .success(SendTarget(key: key, title: s?.name ?? "Session", project: s?.project ?? ""))
    }

    public struct SendUnavailable: Error, Equatable { public let reason: String }

    /// The project folder a target session runs in, for paths relative to it.
    func cwd(of key: String) -> String? { terminals.existing(key)?.cwd }

    // MARK: Delivery

    /// Types `text` into the session's prompt as one paste (bracketed, so newlines don't submit),
    /// then shows that session with the keyboard in it.
    @discardableResult
    public func send(_ text: String, to key: String? = nil) -> Bool {
        guard let key = key ?? (try? sendTarget.get())?.key, let t = terminals.existing(key), t.isLiveClaude, t.notReadyReason == nil else { return false }
        t.paste(text)
        reveal(sessionKey: key)
        t.view.window?.makeFirstResponder(t.view)
        lastSent = (key, text)
        return true
    }

    /// Starts a new session in the current project (Home at All projects) and sends to it once
    /// Claude's prompt is ready (its beacon reports idle, as for relocation).
    public func sendToNewSession(_ text: String) {
        let project = altitude.isAllProjects ? fixture.home?.name : currentProject?.name
        guard let project, let id = newSession(in: project) else { return }
        if altitude.isAllProjects { homeTab = id } else { consoleTab = id }
        guard let t = terminals.existing(id) else { return }
        whenPromptReady(t) { [weak self] in self?.send(text, to: id) }
    }

    /// Shows a session's terminal: switching project, or to Home, if it lives elsewhere.
    func reveal(sessionKey key: String) {
        guard visibleSessionId != key, let s = fixture.sessions.first(where: { $0.tabKey == key }) else { return }
        if s.project == fixture.home?.name, altitude.isAllProjects {
            homeTab = key
        } else {
            if currentProject?.name != s.project { open(project: s.project) }
            consoleTab = key
        }
    }

    /// Runs `then` once the session's Claude prompt is idle (its beacon), for up to 20 s.
    func whenPromptReady(_ t: TerminalSession, tries: Int = 0, then: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !t.exited, let pid = t.view.process?.shellPid else { return }
                if Beacon.readAll().contains(where: { $0.pid == pid && $0.status == "idle" }) {
                    then()
                } else if tries < 40 {
                    self.whenPromptReady(t, tries: tries + 1, then: then)
                }
            }
        }
    }

    // MARK: What can be sent

    /// A file or folder, as an @-reference relative to the receiving session's folder when it's
    /// inside it, else absolute.
    public func filePayload(_ path: String, for key: String?) -> String? {
        guard let url = projectFolder?.appending(path: path) else { return nil }
        let abs = url.standardizedFileURL.path
        if let cwd = key.flatMap(cwd(of:)).map({ URL(fileURLWithPath: $0).standardizedFileURL.path }), abs.hasPrefix(cwd + "/") {
            return SendFormat.file(String(abs.dropFirst(cwd.count + 1)))
        }
        return SendFormat.file(abs)
    }

    public func sessionPayload(_ sessionKey: String) -> String? {
        guard let s = fixture.sessions.first(where: { $0.tabKey == sessionKey }), let id = s.sessionId else { return nil }
        let folder = liveFolders[s.project]
        let transcript = folder.flatMap { ClaudeStorage.transcript(sessionId: id, cwd: $0.path) }?.path
        let entry = folder.map { SessionIndex.load(project: $0) }?.sessions.first { $0.sessionId == id }
        return SendFormat.session(.init(title: s.name, project: s.project, id: id, transcript: transcript, note: entry?.note, next: entry?.next))
    }

    public func projectPayload(_ name: String) -> String? {
        guard let p = fixture.projects.first(where: { $0.name == name }), let folder = liveFolders[name] else { return nil }
        let file = ["PROJECT.md", "HOME.md"].map { folder.appending(path: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        return SendFormat.project(.init(name: name, folder: folder.path, projectFile: file?.path,
                                        goal: p.goal.isEmpty ? nil : p.goal, health: p.health, next: p.next, isFolderOnly: p.isFolderOnly))
    }

    /// The editor's selection, with its file and lines; nil when nothing is selected.
    public func documentSelectionPayload(_ done: @escaping @MainActor (String?) -> Void) {
        guard let editor = editorIfLoaded, let url = editor.url else { return done(nil) }
        editor.run("return duo.selection()") { [weak self] result in
            guard let self, let r = result as? [String: Any], let text = r["text"] as? String,
                  let from = r["fromLine"] as? Int, let to = r["toLine"] as? Int else { return done(nil) }
            done(SendFormat.documentSelection(text, path: self.displayPath(url), fromLine: from, toLine: to))
        }
    }

    /// A file's path as Claude should see it: relative to the visible session's folder when
    /// inside it, else absolute.
    func displayPath(_ url: URL) -> String {
        let abs = url.standardizedFileURL.path
        if let cwd = visibleSessionId.flatMap(cwd(of:)).map({ URL(fileURLWithPath: $0).standardizedFileURL.path }), abs.hasPrefix(cwd + "/") {
            return String(abs.dropFirst(cwd.count + 1))
        }
        return abs
    }
}

extension TerminalSession {
    var isClaude: Bool { if case .shell = command { false } else { true } }
    /// A Claude process that is still running here.
    var isLiveClaude: Bool { isClaude && !exited && (view.process?.running ?? false) }

    /// Why Claude can't take a paste yet, from its beacon: before the folder-trust prompt is
    /// answered there's no beacon, and while it waits on a question or a permission prompt a
    /// paste would land in that menu. Working or at its prompt is fine (typing queues).
    var notReadyReason: String? {
        guard let pid = view.process?.shellPid, let b = Beacon.readAll().first(where: { $0.pid == pid }) else {
            return "Claude isn't ready yet"
        }
        if b.status == "waiting" { return "Claude is waiting on a \(b.waitingFor == "permission prompt" ? "permission prompt" : "question")" }
        return nil
    }

    /// One paste, bracketed so newlines are text, not Return. Claude Code always turns bracketed
    /// paste on (SwiftTerm doesn't expose the mode, and only Claude sessions receive sends).
    func paste(_ text: String) {
        view.send(txt: "\u{1b}[200~" + SendFormat.clean(text) + "\u{1b}[201~")
    }
}

// MARK: - Web views: the editor and HTML pages

extension AppModel {
    typealias AsyncPayload = (@escaping @MainActor (String?) -> Void) -> Void

    /// "Send … to Claude" and "Send … To ▸" as AppKit menu items, for web views' context menus.
    func sendMenuItems(_ noun: String, payload: @escaping AsyncPayload) -> [NSMenuItem] {
        let deliver: (String?) -> Void = { [weak self] key in
            payload { text in
                guard let self, let text else { return }
                if let key { self.send(text, to: key) } else { self.sendToNewSession(text) }
            }
        }
        var items: [NSMenuItem] = []
        let visible = (try? sendTarget.get())?.key
        switch sendTarget {
        case .success(let t):
            let item = ActionMenuItem("Send \(noun) to Claude") { deliver(t.key) }
            if noun == "Selection" { item.keyEquivalent = "d"; item.keyEquivalentModifierMask = .command }  // shown; Edit's ⌘D does it
            items.append(item)
        case .failure(let why): items.append(ActionMenuItem("Send \(noun) to Claude: \(why.reason)", enabled: false) {})
        }
        let more = NSMenuItem(title: "Send \(noun) To", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let others = sendTargets.filter { $0.key != visible }
        for t in others { sub.addItem(ActionMenuItem(t.project.isEmpty ? t.title : "\(t.title) — \(t.project)") { deliver(t.key) }) }
        if !others.isEmpty { sub.addItem(.separator()) }
        sub.addItem(ActionMenuItem("New Session") { deliver(nil) })
        more.submenu = sub
        items.append(more)
        return items
    }

    func wireEditor(_ e: EditorController) {
        e.onStateChange = { [weak self] in self?.editorRevision += 1 }
        e.onOpenLink = { [weak self, weak e] link in self?.openLink(link, from: e?.url) }
        e.webView.onFocusChange = { [weak self] on in
            guard let self else { return }
            if on { self.webFocus = .editor } else if self.webFocus == .editor { self.webFocus = .none }
        }
        e.webView.extraMenuItems = { [weak self, weak e] hasSelection, _ in
            guard let self, self.terminalsMode == .live else { return [] }
            var items = hasSelection ? self.sendMenuItems("Selection") { done in self.documentSelectionPayload(done) } : []
            // Revert Claude's changes (ENH-4): plain menu items until the highlight's own affordance is designed.
            if let e, e.claudeChanges > 0 {
                if !items.isEmpty { items.append(.separator()) }
                if e.atClaudeChange { items.append(ActionMenuItem("Revert This Change") { e.revertAtCaret() }) }
                items.append(ActionMenuItem("Revert All of Claude's Changes") { e.revertAll() })
            }
            return items
        }
    }

    func wireHTMLViewer(_ v: HTMLViewer) {
        v.onChange = { [weak self] in self?.pickerRevision += 1 }
        v.onLinkOut = { [weak self] u in self?.openLink(u.absoluteString) }
        v.webView.onFocusChange = { [weak self] on in
            guard let self else { return }
            if on { self.webFocus = .html } else if self.webFocus == .html { self.webFocus = .none }
        }
        v.webView.extraMenuItems = { [weak self] hasSelection, onImage in
            guard let self, self.terminalsMode == .live else { return [] }
            var items: [NSMenuItem] = []
            if hasSelection || onImage {
                items += self.sendMenuItems(hasSelection ? "Selection" : "Image") { done in self.htmlSelectionPayload(done) }
            }
            items.append(ActionMenuItem("Select Element") { v.startPicking() })
            items.append(ActionMenuItem("Reload Page") { v.reload() })
            return items
        }
    }

    /// The HTML page's selected text and images.
    func htmlSelectionPayload(_ done: @escaping @MainActor (String?) -> Void) {
        guard let v = htmlViewerIfLoaded, let url = v.url else { return done(nil) }
        v.selection { [weak self] sel in
            guard let self, let sel else { return done(nil) }
            let images = (sel["images"] as? [[String: Any]] ?? []).map { (src: $0["src"] as? String ?? "", alt: $0["alt"] as? String ?? "") }
            done(SendFormat.htmlSelection(sel["text"] as? String ?? "", path: self.displayPath(url), title: sel["title"] as? String, images: images))
        }
    }

    /// The picked element, with a screenshot saved for Claude to read.
    func pickedElementPayload(_ done: @escaping @MainActor (String?) -> Void) {
        guard let v = htmlViewerIfLoaded, let url = v.url, let e = v.picked else { return done(nil) }
        v.screenshot(rect: nil) { [weak self] shot in
            guard let self else { return done(nil) }
            done(SendFormat.element(e, path: self.displayPath(url), screenshot: shot))
        }
    }

    /// The picker bar's Send: to a session (nil: a new one), then the picker closes.
    public func sendPickedElement(to key: String?) {
        pickedElementPayload { [weak self] text in
            guard let self, let text else { return }
            if let key { self.send(text, to: key) } else { self.sendToNewSession(text) }
            self.htmlViewerIfLoaded?.stopPicking()
        }
    }

    /// Edit › Send Selection to Claude: whichever of the editor or an HTML page has the keyboard.
    public func sendSelection(to key: String? = nil) {
        let deliver: @MainActor (String?) -> Void = { [weak self] text in
            guard let self, let text else { return }
            if let key { self.send(text, to: key) } else { self.send(text) }
        }
        if webFocus == .editor || editorIfLoaded?.hasFocus == true { documentSelectionPayload(deliver) }
        else if webFocus == .html { htmlSelectionPayload(deliver) }
    }

    /// Whether the menu item can work: a web view with the keyboard, and a session to receive.
    public var canSendSelection: Bool {
        // Observed (webFocus, the console tab) so the menu re-validates; the send itself checks
        // the session's readiness and says why if it can't.
        webFocus != .none && visibleSessionId != nil
    }
}
