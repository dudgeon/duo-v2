import AppKit
import SwiftUI

/// Hands the hosting NSWindow to a closure once the view is in it.
public struct WindowConfigurator: NSViewRepresentable {
    let configure: @MainActor (NSWindow) -> Void

    public init(_ configure: @escaping @MainActor (NSWindow) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> NSView {
        let v = Probe()
        v.onWindow = configure
        return v
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let onWindow else { return }
            self.onWindow = nil
            DispatchQueue.main.async { onWindow(window) }
        }
    }
}

/// Sets the window up for fixture mode and, when asked, captures it and quits.
@MainActor
public enum FixtureHarness {
    /// Where the panes start in the targets: the 38 pt toolbar plus its 1 pt bottom border, which
    /// CSS adds on top of the height (findings F-10).
    public static let designContentTop = DuoMetric.toolbarHeight + DuoMetric.borderHairline

    /// Content area under the toolbar at the design size: 1440 × (900 − 39).
    public static let contentSize = CGSize(
        width: DuoMetric.designWindow.width,
        height: DuoMetric.designWindow.height - designContentTop
    )

    /// Cleanup the app registers for the capture path's direct exit.
    nonisolated(unsafe) public static var beforeExit: (@MainActor () -> Void)?

    /// Runs one scripted action (`--then`), as a click or chord would.
    static func perform(_ action: String, on model: AppModel) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "open":
            let target = parts.count > 1 ? parts[1].split(separator: "/", maxSplits: 1).map(String.init) : []
            if let project = target.first { model.open(project: project, session: target.count > 1 ? target[1] : nil) }
        case "peek": model.togglePeek()
        case "down": model.movePeekSelection(by: 1)
        case "up": model.movePeekSelection(by: -1)
        case "jump": model.jumpToPeekSelection()
        case "home": model.goHome()
        case "zoom-out": model.zoomOut()
        case "focus-tile": model.moveTileFocus(dx: 0, dy: 0)
        case "new": model.newSession()
        case "close": model.closeVisibleSession()
        case "newfile": model.newMarkdownFile(near: parts.count > 1 ? parts[1] : nil)
        case "newfolder": model.newFolder(near: parts.count > 1 ? parts[1] : nil)
        case "rename":  // rename:<path>=<new name>
            if parts.count > 1 { let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init); if kv.count == 2 { model.commitRename(kv[0], to: kv[1]) } }
        case "dup": if parts.count > 1 { model.duplicate(parts[1]) }
        case "trash": if parts.count > 1 { model.moveToTrash(parts[1]) }
        case "projects":
            for p in model.fixture.projects {
                FileHandle.standardError.write(Data("project: \(p.name) [\(p.topic ?? "-")] \(p.isFolderOnly ? "folder" : "project")\(p.hasClaudeMD == true ? " +CLAUDE.md" : "") sessions=\(model.fixture.sessions(inProject: p.name).count) \(p.path)\n".utf8))
            }
        case "move":   // move:<session id prefix>=<project>
            if parts.count > 1 {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, let id = model.fixture.sessions.first(where: { $0.sessionId?.hasPrefix(kv[0]) == true })?.sessionId { model.moveSessions([id], to: kv[1]) }
            }
        case "merge":  // merge:<source>=<target>
            if parts.count > 1 { let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init); if kv.count == 2 { model.mergeProject(kv[0], into: kv[1]) } }
        case "makeproject": if parts.count > 1 { model.makeProject(parts[1]) }
        case "undo": NSApp.windows.first(where: { $0.title == "Duo" })?.undoManager?.undo()
        case "tabs":
            FileHandle.standardError.write(Data("tabs: \(model.openDocuments) right=\(model.rightTab ?? "-") renaming=\(model.renamingPath ?? "-") editor=\(model.editorIfLoaded?.url?.lastPathComponent ?? "-")\ntree: \(model.currentProject.flatMap { model.fixture.projectFiles[$0.name] } ?? [])\n".utf8))
        case "resume":
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.sessionId?.hasPrefix(parts[1]) == true }), let id = s.sessionId {
                model.open(project: s.project); model.consoleTab = id
                _ = model.terminal(project: s.project, session: id)
            }
        case "file": if parts.count > 1 { model.selectedFile = parts[1]; model.rightTab = parts[1] }
        case "edit-bold": model.editor.run("duo.select(2, 9); duo.exec('bold'); return 1") { _ in }
        case "editor-snapshot":
            let out = parts.count > 1 ? parts[1] : "/tmp/editor.png"
            model.editor.webView.takeSnapshot(with: nil) { image, _ in
                if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
            }
        case "outside-title":
            if let url = model.editor.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                let lines = text.components(separatedBy: "\n")
                try? (["# PRD v3, renamed outside"] + lines.dropFirst()).joined(separator: "\n").write(to: url, atomically: false, encoding: .utf8)
            }
        case "doc-status":
            if let url = model.editor.url { FileHandle.standardError.write(Data("doc-status: \(model.editor.status(of: url))\n".utf8)) }
        // Collisions (DL-77): a person typing, and another writer on disk, at the same time.
        case "user-type":     // user-type:<find>=><replacement> in the editor, unsaved
            let p = (parts.count > 1 ? parts[1] : "").components(separatedBy: "=>")
            if p.count == 2 { model.editor.run("return duo.userReplace(f, t)", ["f": p[0], "t": p[1]]) { v in
                FileHandle.standardError.write(Data("user-type: \(v as? Bool == true ? "typed" : "not found")\n".utf8)) } }
        case "disk-write", "disk-rename":   // disk-write:<find>=><replacement>, in place or by atomic rename
            let p = (parts.count > 1 ? parts[1] : "").components(separatedBy: "=>")
            if p.count == 2, let url = model.editor.url, let text = try? String(contentsOf: url, encoding: .utf8), text.contains(p[0]) {
                try? text.replacingOccurrences(of: p[0], with: p[1]).write(to: url, atomically: parts[0] == "disk-rename", encoding: .utf8)
                FileHandle.standardError.write(Data("\(parts[0]): done\n".utf8))
            } else { FileHandle.standardError.write(Data("\(parts[0]): text not on disk\n".utf8)) }
        case "quit":   // quit as ⌘Q would, mid-script (save-on-quit checks)
            NSApp.terminate(nil)
        case "disk-delete":
            if let url = model.editor.url { try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("gone")) }
        case "disk-restore":
            if let url = model.editor.url { try? FileManager.default.moveItem(at: url.appendingPathExtension("gone"), to: url) }
        case "editor-state":
            let e = model.editor
            e.run("return duo.text()") { v in
                let disk = e.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "<none>"
                FileHandle.standardError.write(Data("editor-state: event=\(e.lastEvent) dirty=\(e.dirty) conflict=\(e.conflict) removed=\(e.removedOnDisk)\n  buffer=\((v as? String ?? "").debugDescription)\n  disk=\(disk.debugDescription)\n  status=\(e.url.map { e.status(of: $0) } ?? "-")\n".utf8))
            }
        case "outside":
            if let url = model.editor.url, var text = try? String(contentsOf: url, encoding: .utf8) {
                text += "\nA line added by another app.\n"
                try? text.write(to: url, atomically: false, encoding: .utf8)
            }
        case "editor":
            let e = model.editor
            e.run("""
                const c = document.querySelector('.cm-content'), cs = c && getComputedStyle(c), h = document.querySelector('.duo-h');
                return JSON.stringify({ length: duo.text().length, head: duo.text().slice(0, 60), font: cs && cs.fontSize, line: cs && cs.lineHeight,
                  padding: cs && cs.padding, bg: getComputedStyle(document.body).backgroundColor, color: cs && cs.color,
                  heading: h && getComputedStyle(h).fontSize + ' ' + getComputedStyle(h).fontWeight, added: duo.addedCount() })
                """) { v in
                FileHandle.standardError.write(Data("editor: \(e.url?.lastPathComponent ?? "-") event=\(e.lastEvent) readOnly=\(e.readOnlyReason ?? "no") conflict=\(e.conflict) \(v ?? "nil")\n".utf8))
            }
        case "type": model.visibleTerminal?.view.send(txt: parts.count > 1 ? parts[1] : "")
        case "enter": model.visibleTerminal?.view.send(txt: "\r")
        case "key":   // key:down|up|esc|tab: one key into the visible terminal (menus such as the trust prompt)
            let codes = ["down": "\u{1b}[B", "up": "\u{1b}[A", "esc": "\u{1b}", "tab": "\t"]
            if parts.count > 1, let c = codes[parts[1]] { model.visibleTerminal?.view.send(txt: c) }
        case "dump":
            for t in model.terminals.all.sorted(by: { $0.key < $1.key }) {
                t.view.selectAll()
                let text = (t.view.getSelection() ?? "").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                t.view.selectNone()
                FileHandle.standardError.write(Data("---- \(t.key) frame=\(t.view.frame.size) window=\(t.view.window != nil) ----\n\(text.prefix(12).joined(separator: "\n"))\n".utf8))
            }
            for s in model.fixture.sessions where s.sessionId != nil {
                FileHandle.standardError.write(Data("== \(s.sessionId!.prefix(8)) \(s.project)/\(s.name) [\(s.state)] wait=\(s.wait ?? "-") q=\(s.question ?? "-") opts=\(s.options ?? []) summary=\(s.summary ?? "-")\n".utf8))
            }
        // Send to Claude (DL-67): each source, into the visible session.
        case "send-file": if parts.count > 1, let p = model.filePayload(parts[1], for: model.visibleSessionId) { model.send(p) }
        case "send-session":
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.name == parts[1] }), let p = model.sessionPayload(s.tabKey) { model.send(p) }
        case "send-project": if parts.count > 1, let p = model.projectPayload(parts[1]) { model.send(p) }
        case "doc-select":   // doc-select:<from>-<to> (character offsets)
            let r = (parts.count > 1 ? parts[1] : "0-0").split(separator: "-").compactMap { Int($0) }
            model.editor.run("duo.select(a, b); return 1", ["a": r.first ?? 0, "b": r.last ?? 0]) { _ in }
        case "send-doc-selection": model.documentSelectionPayload { if let p = $0 { model.send(p) } }
        case "html-select":  // html-select:<css selector>: select that element's contents
            model.htmlViewer.webView.callAsyncJavaScript(
                "const r = document.createRange(); r.selectNodeContents(document.querySelector(s)); getSelection().removeAllRanges(); getSelection().addRange(r); return 1",
                arguments: ["s": parts.count > 1 ? parts[1] : "body"], in: nil, in: .page, completionHandler: nil)
        case "send-html-selection": model.htmlSelectionPayload { if let p = $0 { model.send(p) } }
        case "html-pick": if parts.count > 1 { model.htmlViewer.pick(selector: parts[1]) }
        case "html-snapshot":   // html-snapshot:<png path>: what the page web view draws
            let path = parts.count > 1 ? parts[1] : "/tmp/duo-html.png"
            model.htmlViewer.webView.takeSnapshot(with: nil) { image, _ in
                if let t = image?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                FileHandle.standardError.write(Data("html-snapshot: \(image != nil ? path : "failed")\n".utf8))
            }
        case "send-picked": model.sendPickedElement(to: model.visibleSessionId)
        case "dump-tail":   // the visible terminal's last lines
            if let t = model.visibleTerminal {
                t.view.selectAll()
                let lines = (t.view.getSelection() ?? "").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                t.view.selectNone()
                FileHandle.standardError.write(Data("---- tail \(t.key) ----\n\(lines.suffix(30).joined(separator: "\n"))\n".utf8))
            }
            if let l = model.lastSent { FileHandle.standardError.write(Data("---- lastSent to \(l.key.prefix(8)) ----\n\(l.text)\n----\n".utf8)) }
        case let a where a.hasPrefix("wait"): break
        default: FileHandle.standardError.write(Data("Unknown action '\(action)'\n".utf8))
        }
    }

    public static func configure(_ window: NSWindow, model: AppModel, options: LaunchOptions) {
        if options.capturing { FileHandle.standardError.write(Data("trace configure\n".utf8)) }
        window.isRestorable = false
        window.tabbingMode = .disallowed
        guard options.state != nil || options.capturing else { return }

        // Render in sRGB so captured pixels are the token values exactly. Otherwise the window
        // draws in the display's colour space and the capture is off by a unit after conversion.
        window.colorSpace = .sRGB

        // The system toolbar may not be 38 high; the panes start below whatever it is (§0.4),
        // so size the area below it to exactly the design's.
        let chrome = window.frame.height - window.contentLayoutRect.height
        let height = contentSize.height + chrome
        let screen = window.screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: max(screen.minX, screen.midX - contentSize.width / 2),
                             y: max(screen.minY, screen.maxY - height))
        window.setFrame(CGRect(origin: origin, size: CGSize(width: contentSize.width, height: height)), display: true)

        // Scripted actions, one every 0.6 s, so each change renders before the next.
        for (i, action) in options.thenActions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(i + 1)) { perform(action, on: model) }
        }

        guard options.capturing else { return }
        // Give SwiftUI and the split view a moment to settle at the new size. When the peek
        // should be open, also wait for its popover to be on screen and done animating: a fixed
        // delay sometimes caught it half-drawn or not yet there (F-44).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + 0.6 * Double(options.thenActions.count)) {
            whenPopoverSettled(model: model) { capture() }
        }

        func whenPopoverSettled(model: AppModel, tries: Int = 0, then: @escaping @MainActor () -> Void) {
            let shown = NSApp.windows.contains { $0.isVisible && $0.className.contains("Popover") }
            if !model.peekOpen || (shown && tries > 0) || tries >= 30 {
                // One more beat after it appears, for the fade-in.
                DispatchQueue.main.asyncAfter(deadline: .now() + (model.peekOpen ? 0.4 : 0)) { MainActor.assumeIsolated { then() } }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainActor.assumeIsolated { whenPopoverSettled(model: model, tries: shown ? max(tries, 1) : tries + 1, then: then) }
            }
        }

        func capture() {
            var failed = false
            do {
                if let path = options.capturePath {
                    try WindowCapture.content(of: window, to: URL(fileURLWithPath: path))
                    print("captured content \(path)")
                }
                if let path = options.captureWindowPath {
                    try WindowCapture.window(window, to: URL(fileURLWithPath: path))
                    print("captured window \(path)")
                }
            } catch {
                FileHandle.standardError.write(Data("capture failed: \(error.localizedDescription)\n".utf8))
                failed = true
            }
            fflush(stdout)
            beforeExit?()  // exit() skips willTerminate: end sessions, remove the endpoint
            exit(failed ? 1 : 0)
        }
    }
}
