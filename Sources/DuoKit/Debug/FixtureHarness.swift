import DuoControl
import AppKit
import ObjectiveC
import DuoSearch
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
    /// The chat composer's field in Duo's window, for `chat-type:` and `chat-key:`.
    /// The composer of the session on screen: Home's chat stays in the window under a project
    /// (DL-132 g), so the first composer found isn't always the one you see.
    static func composerView(for key: String? = nil) -> ComposerTextView? {
        func all(_ v: NSView) -> [ComposerTextView] { ((v as? ComposerTextView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
        let found = NSApp.windows.flatMap { $0.contentView.map(all) ?? [] }
        return found.first { key != nil && $0.coordinator?.chat.key == key } ?? found.first
    }

    /// Where the panes start in the targets: the 38 pt toolbar plus its 1 pt bottom border, which
    /// CSS adds on top of the height (findings F-10).
    public static let designContentTop = DuoMetric.toolbarHeight + DuoMetric.borderHairline

    /// Content area under the toolbar at the design size: 1440 × (900 − 39).
    public static let contentSize = CGSize(
        width: DuoMetric.designWindow.width,
        height: DuoMetric.designWindow.height - designContentTop
    )

    /// A capture keeps the peek open when its popover closes on its own (C-35).
    public static var holdsPeek = false

    /// Cleanup the app registers for the capture path's direct exit.
    nonisolated(unsafe) public static var beforeExit: (@MainActor () -> Void)?

    /// A menu as indented text: separators as —, submenus nested, dimmed and checked items marked.
    static func walk(_ menu: NSMenu, _ depth: Int) -> [String] {
        menu.delegate?.menuNeedsUpdate?(menu)
        if Env.isSet("DUO_MENU_UPDATE") { menu.update() }
        return menu.items.flatMap { i -> [String] in
            if i.isHidden { return [] }
            if i.isSeparatorItem { return [String(repeating: "  ", count: depth) + "—"] }
            var mods = ""
            if !i.keyEquivalent.isEmpty {
                let m = i.keyEquivalentModifierMask
                if m.contains(.control) { mods += "⌃" }; if m.contains(.option) { mods += "⌥" }
                if m.contains(.shift) || i.keyEquivalent != i.keyEquivalent.lowercased() { mods += "⇧" }; if m.contains(.command) { mods += "⌘" }
            }
            let key = i.keyEquivalent.isEmpty ? "" : "  \(mods)\(keyName(i.keyEquivalent))"
            let line = String(repeating: "  ", count: depth) + i.title + (i.submenu?.autoenablesItems == true ? " [auto]" : "") + key + (i.isEnabled ? "" : "  (dim)") + (i.state == .on ? "  ✓" : "")
            return [line] + (i.submenu.map { walk($0, depth + 1) } ?? [])
        }
    }

    /// A key equivalent as the menu shows it.
    static func keyName(_ k: String) -> String {
        switch k.unicodeScalars.first.map({ Int($0.value) }) ?? 0 {
        case NSUpArrowFunctionKey: "↑"
        case NSDownArrowFunctionKey: "↓"
        case NSLeftArrowFunctionKey: "←"
        case NSRightArrowFunctionKey: "→"
        case 13, 3: "↩"
        default: k.uppercased()
        }
    }

    /// Runs one scripted action (`--then`), as a click or chord would.
    static func perform(_ action: String, on model: AppModel) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "open":
            let target = parts.count > 1 ? parts[1].split(separator: "/", maxSplits: 1).map(String.init) : []
            if let project = target.first { model.open(project: project, session: target.count > 1 ? target[1] : nil) }
        case "peek": model.togglePeek()
        case "repo":   // repo:push|latest|update|putback|details|refresh|dump: the Files block's repo state (DL-149)
            switch parts.count > 1 ? parts[1] : "dump" {
            case "push": model.showPush()
            case "new": model.showGitHubProject("acme/website")
            case "create": model.commitGitHubProject()
            case "latest": model.getLatest(from: nil)
            case "update": model.getLatest(from: model.currentRepo?.base)
            case "putback": model.putBack()
            case "details": model.repoDetailsShown = true
            case "refresh": model.refreshRepo(force: true, fetch: true)
            default:
                let v = model.currentRepo
                let line = v.map { RepoLine.of($0) }
                FileHandle.standardError.write(Data("repo: \(v?.status.branch ?? "-") | \(line?.fact ?? "no repo") | \(line?.action?.rawValue ?? "-") | marks \(v?.marks ?? [:])\n".utf8))
            }
        case "deactivate": NSApp.deactivate()   // as when the user clicks into another app (C-35)
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
        case "notnow": if parts.count > 1 { model.notNowProject(parts[1]) }   // notnow:<folder>: Not Now on its Make a Project notice (DL-110)
        case "sheet-move":   // sheet-move:<project>: Move into Home…'s sheet, up and waiting
            if parts.count > 1 { model.moveIntoHome(parts[1]) }
        case "sheet-new":    // sheet-new[:<name>]: the New project sheet
            model.showNewProject(name: parts.count > 1 ? parts[1] : "")
        case "sheet-goal": model.newProjectForm?.goal = parts.count > 1 ? parts[1] : ""
        case "sheet-into":   // sheet-into:<topic>: pick a place on whichever sheet is up
            if let p = model.homePlaces().first(where: { $0.folder.lastPathComponent == (parts.count > 1 ? parts[1] : "") }) {
                model.moveIntoHomeForm?.into = p; model.newProjectForm?.into = p
            }
        case "notify-hidden":   // notify-hidden:notifications|badges|none: what macOS hides, for Settings (Q-93)
            SettingsInfo.shared.macOSHidesOverride = .some(parts.count > 1 ? MacOSHides(rawValue: parts[1]) : nil)
        case "render-settings":   // render-settings:<png>: the Settings view, drawn to an image at 2x
            if parts.count > 1 {
                SettingsInfo.shared.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    MainActor.assumeIsolated {
                        let r = ImageRenderer(content: SettingsView(scrolls: false).environment(model))
                        r.scale = 2
                        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: parts[1])) }
                        else { FileHandle.standardError.write(Data("render-settings: nothing drawn (image \(r.nsImage == nil ? "nil" : "\(r.nsImage!.size)"))\n".utf8)) }
                    }
                }
            }
        case "ask-legacy": LegacyPrompt.run()
        case "ask-update":   // ask-update:writable|admin|no-sparkle|no-notes: the update question (DL-114) for 0.1.9 over 0.1.8, its buttons only logged
            let form = parts.count > 1 ? parts[1] : "writable"
            let o = UpdateCheck.Offer(version: "0.1.9", current: "0.1.8", page: UpdateCheck.releasePage("0.1.9"), needsAdmin: form == "admin",
                                      canInstallNow: form != "no-sparkle", folder: "/Applications",
                                      notes: form == "no-notes" ? "" : "## What's new\n\n- Closing a tab where Claude is working asks first.\n- Files dropped on the tree move there, with Undo.\n- PowerPoint decks open in the right pane.\n- Narrow windows keep the side panes’ widths.\n")
            func say(_ s: String) -> @MainActor () -> Void { { FileHandle.standardError.write(Data("ask-update: \(s)\n".utf8)) } }
            SheetCenter.shared.ask(UpdateCheck.question(o, openPage: say("Open Releases Page"), installNow: say("Install Now"), later: say("Later")))
        case "sheet-ok": if model.moveIntoHomeForm != nil { model.confirmMoveIntoHome() } else { model.commitNewProject() }
        case "sheet-cancel": model.cancelSheet()
        // Drag and drop of files (DL-117), as the drop delegates hand them over. Paths are split on "|".
        case "drop-files":   // drop-files:<folder or root>=<path>|<path>: files dropped on the tree
            if parts.count > 1 {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { model.dropFiles(kv[1].split(separator: "|").map { URL(fileURLWithPath: String($0)) }, onto: kv[0] == "root" ? nil : kv[0]) }
            }
        case "drop-terminal":   // drop-terminal:<path>|<path>: files dropped on the visible terminal
            if parts.count > 1 { model.visibleTerminal?.view.insertPaths(parts[1].split(separator: "|").map { URL(fileURLWithPath: String($0)) }) }
        case "drop-hover":   // drop-hover:<folder>|root|off: a drag of files held over the tree
            model.treeDropTarget = parts.count < 2 || parts[1] == "off" ? nil : parts[1] == "root" ? "" : parts[1]
        case "answer":   // answer:<label>: press that button on Duo's own question sheet
            if let q = SheetCenter.shared.current {
                FileHandle.standardError.write(Data("answer: \(q.title) [\(q.choices.map(\.label).joined(separator: " | "))]\n".utf8))
                if let c = q.choices.first(where: { $0.label == (parts.count > 1 ? parts[1] : "") }) { SheetCenter.shared.answer(c) }
            } else { FileHandle.standardError.write(Data("answer: no question\n".utf8)) }
        case "undo": NSApp.windows.first(where: { $0.title == "Duo" })?.undoManager?.undo()
        case "tabs":
            FileHandle.standardError.write(Data("tabs: \(model.openDocuments) right=\(model.rightTab ?? "-") renaming=\(model.renamingPath ?? "-") editor=\(model.editorIfLoaded?.url?.lastPathComponent ?? "-")\ntree: \(model.currentProject.flatMap { model.fixture.projectFiles[$0.name] } ?? [])\n".utf8))
        case "resume":
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.sessionId?.hasPrefix(parts[1]) == true }), let id = s.sessionId {
                model.open(project: s.project); model.consoleTab = id
                _ = model.terminal(project: s.project, session: id)
            }
        case "ask-close":   // ask-close:<tab key> | ask-close:shell=<command>: the question closing a busy tab asks (Q-71), always shown
            if parts.count > 1 {
                let why: AppModel.TabBusy? = parts[1].hasPrefix("shell=") ? .shellRunning(command: String(parts[1].dropFirst(6))) : model.busy(parts[1])
                if let why { SheetCenter.shared.ask(model.closeQuestion(why) {}) }
            }
        case "hover-tab":   // hover-tab:<tab key or document path>[=close|press]: the pointer over a tab, or on its × (DL-126)
            if parts.count > 1 {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                let key = kv[0], on = kv.count > 1 ? kv[1] : ""
                model.hoveredTab = key
                model.hoveredTabClose = on == "close" || on == "press" ? key : nil
                model.pressedTabClose = on == "press" ? key : nil
            }
        case "file": if parts.count > 1 { model.selectedFile = parts[1]; model.rightTab = parts[1] }
        case "doc": if parts.count > 1 { model.openDocument(parts[1]) }   // doc:<path>: a document tab, as the file tree opens it
        case "convert": if parts.count > 1 { model.convertToMarkdown(parts[1]) }   // convert:<docx>: the bar's Convert to Markdown (DL-123)
        case "converting":   // converting:<docx>: hold the progress bar (C) as drawn, for a capture
            if parts.count > 1 { model.converting[parts[1]] = (0.62, "Images, 3 of 5") }
        case "convert-failed":   // convert-failed:<docx>=password|damaged|scan: the failure bar (F, F2)
            let kv = parts.count > 1 ? parts[1].split(separator: "=", maxSplits: 1).map(String.init) : []
            if kv.count == 2 {
                model.conversionFailures[kv[0]] = kv[1] == "password" ? .passwordProtected : kv[1] == "scan" ? .noText(images: 4) : .damaged
            }
        case "open-file": if parts.count > 1 { model.openFile(at: URL(fileURLWithPath: parts[1])) }   // open-file:<path>: Open File… (DL-106)
        case "hidden": model.setShowHiddenFiles(parts.count > 1 ? parts[1] == "on" : !model.showHiddenFiles)   // hidden:on|off (DL-105)
        case "folder": if parts.count > 1 { withDuoAnimation(.fold) { model.toggleFolder(parts[1]) } }   // folder:<path>: open or close it in the tree
        case "browse":   // browse:up|back|<folder>|open=<path from the browse root>: the Files block above the project's folder (Q-162)
            if parts.count > 1 {
                switch parts[1] {
                case "up": _ = model.browseUp()
                case "back": model.browseBack()
                case let p where p.hasPrefix("open="): model.toggleBrowseFolder(String(p.dropFirst(5)))
                default: _ = model.browse(to: URL(fileURLWithPath: parts[1]))
                }
            }
        case "zoom-out": model.zoomOut()
        case "restore-save": model.saveRestoreState(force: true)
        case "restore-state":
            let s = model.currentRestoreState()
            FileHandle.standardError.write(Data("restore-state: project=\(s.project.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "-") \(s.projects.map { "\(URL(fileURLWithPath: $0.folder).lastPathComponent):\($0.sessions.count)s/\($0.documents.joined(separator: "+"))/\($0.rightTab ?? "-")" }.joined(separator: " "))\n".utf8))
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
        case "event":  // event:esc|return|cmd-v: a real key event through the app's queue (local monitors, key window, field editor); cmd-v reads the real clipboard
            let codes: [String: (UInt16, String)] = ["esc": (53, "\u{1b}"), "return": (36, "\r"), "cmd-v": (9, "v")]
            if parts.count > 1, let (code, chars) = codes[parts[1]], let w = NSApp.windows.first(where: { $0.title == "Duo" }) {
                if !TestBackground.isOn { NSApp.activate(ignoringOtherApps: true) }; w.makeKey()   // a background launch never activates (F-227)
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: parts[1] == "cmd-v" ? .command : [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: w.windowNumber, context: nil, characters: chars,
                                                   charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { continue }
                    NSApp.postEvent(e, atStart: false)
                    // With the screen locked the window can't become key and the queue drops key events after
                    // the monitors; deliver keyDown as NSApp would: key equivalents first, then the first responder.
                    if type == .keyDown, !w.isKeyWindow {
                        DispatchQueue.main.async { if !w.performKeyEquivalent(with: e) { w.sendEvent(e) } }
                    }
                }
            }
        case "template-preview": model.toggleTemplatePreview()   // the template bar's Preview (DL-146, board A2)
        case "new-task": if let p = model.currentProject?.name { model.newTask(in: p) }   // + New task in the open project
        case "board": model.showBoard(parts.count < 2 || parts[1] != "off")   // board[:off]: Sessions | Tasks (DL-148)
        case "card": if parts.count > 1, let p = model.currentProject?.name { model.selectCard(project: p, path: parts[1]) }   // card:<path>: a click on a card
        case "hover-card":   // hover-card:<path>[=<session title>]: the pointer over a card, or one of its session rows
            if parts.count > 1, let p = model.currentProject?.name {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                model.hoveredCard = TaskRowHover.key(project: p, path: kv[0])
                if kv.count > 1, let s = model.fixture.sessions.first(where: { $0.project == p && $0.name == kv[1] }) {
                    model.hoveredCardSession = "\(p)/\(kv[0])#\(s.sessionId ?? "")"
                }
            }
        case "move-card":   // move-card:<path>=<status>: a card dropped on that lane
            if parts.count > 1, let p = model.currentProject?.name {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { _ = model.moveCard(project: p, path: kv[0], to: kv[1]) }
            }
        case "drag-card":   // drag-card:<path>=<lane>: hold a card over a lane, mid-drag (board 7)
            if parts.count > 1, let p = model.currentProject?.name {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                model.dragging = AppModel.dragPayload(card: p, path: kv[0])
                model.boardDropLane = kv.count > 1 ? kv[1] : nil
            }
        case "ask-remove-column":   // ask-remove-column:<status>: Remove Column… on that lane (its question)
            if parts.count > 1, let p = model.currentProject?.name { model.askRemoveColumn(parts[1], project: p) }
        case "add-column":   // add-column[:<after>]: the name field, as + Add Column or Add Column After… opens it
            model.addingColumn = parts.count > 1 ? parts[1] : ""
        case "hover-lane": model.hoveredLane = parts.count > 1 ? parts[1] : nil   // hover-lane:<status>: its ⋯
        case "board-filter": model.boardFilter = parts.count > 1 ? parts[1] : ""
        case "task-session":   // task-session:<path>: New Session in Task on a task in the open project
            if parts.count > 1, let p = model.currentProject?.name { model.startSession(inTask: parts[1], project: p) }
        case "hover-task":   // hover-task:<path>: the pointer over a task's row (its +, DL-112); in the open project, else the first with that note
            if parts.count > 1, let p = model.currentProject?.name ?? model.fixture.tasks?.first(where: { $0.path == parts[1] })?.project {
                model.hoveredTaskRow = TaskRowHover.key(project: p, path: parts[1])
            }
        case "keys":   // keys:<text>: real key events to whatever has the keyboard (no focusing first)
            if parts.count > 1, let w = NSApp.windows.first(where: { $0.title == "Duo" }) {
                if !TestBackground.isOn { NSApp.activate(ignoringOtherApps: true) }; w.makeKey()   // a background launch never activates (F-227)
                for ch in parts[1] {
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: w.windowNumber, context: nil, characters: String(ch),
                                                       charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0) else { continue }
                        if w.isKeyWindow { NSApp.postEvent(e, atStart: false) } else if type == .keyDown { w.sendEvent(e) }
                    }
                }
            }
        case "focus":   // what has the keyboard, and the editor's selection
            let w = NSApp.windows.first(where: { $0.title == "Duo" })
            let e = model.editor
            e.run("const s = duo.selection(); return s ? s.text : ''") { v in
                FileHandle.standardError.write(Data("focus: responder=\(w?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") editor=\(e.hasFocus) selected=\(String(describing: v ?? "nil").debugDescription)\n".utf8))
            }
        case "editor-js":   // editor-js:<js>: run in the editor page (focused first), print what it returns
            let e = model.editor
            e.webView.window?.makeFirstResponder(e.webView)
            // `--then` splits on commas: write ⸴ for a comma inside the script.
            e.run(parts.count > 1 ? parts[1].replacingOccurrences(of: "⸴", with: ",") : "return null") { v in
                FileHandle.standardError.write(Data("editor-js: \(String(describing: v ?? "nil"))\n".utf8))
            }
        case "sheet":   // sheet:<button title>: press that button on the sheet attached to Duo's window
            if let w = NSApp.windows.first(where: { $0.title == "Duo" }), let sheet = w.attachedSheet {
                func buttons(_ v: NSView) -> [NSButton] { (v as? NSButton).map { [$0] } ?? v.subviews.flatMap(buttons) }
                let all = sheet.contentView.map(buttons) ?? []
                FileHandle.standardError.write(Data("sheet: [\(all.map(\.title).joined(separator: " | "))]\n".utf8))
                all.first(where: { $0.title == (parts.count > 1 ? parts[1] : "") })?.performClick(nil)
            } else { FileHandle.standardError.write(Data("sheet: none\n".utf8)) }
        case "search":   // search:<query>: open the modal (⇧⌘A) and type the query
            if !model.search.isOpen { model.openSearch() }
            model.searchQueryChanged(parts.count > 1 ? parts[1] : "")
        case "search-kind":   // search-kind:file|session|memory|any (the Kind pop-up)
            model.setSearchKind(parts.count > 1 ? SearchItem.Kind(rawValue: parts[1]) : nil)
        case "search-close": model.closeSearch()
        case "shell": model.newShell()
        case "archived": model.archivedOpen.toggle()
        case "click":   // click:<x> <y>: a real mouse click at that point of the window, from its top left
            if parts.count > 1, let w = NSApp.windows.first(where: { $0.title == "Duo" }) {
                let xy = parts[1].split(separator: " ").compactMap { Double($0) }
                if xy.count == 2, let content = w.contentView {
                    let p = NSPoint(x: xy[0], y: content.bounds.height - xy[1])
                    for (i, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                        if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + Double(i) * 0.05,
                                                      windowNumber: w.windowNumber, context: nil, eventNumber: i, clickCount: 1, pressure: 1) { w.sendEvent(e) }
                    }
                }
            }
        case "where":
            FileHandle.standardError.write(Data("where: \(model.altitude.isAllProjects ? "all" : model.currentProject?.name ?? "?") console=\(model.consoleTab ?? "-")\n".utf8))
        case "fork":   // fork:<session id prefix>: Resume as a Fork (DB-3)
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.sessionId?.hasPrefix(parts[1]) == true }), let id = s.sessionId {
                model.open(project: s.project); model.resumeAsFork(id, in: s.project)
            }
        case "idle": model.toggleIdleList()
        case "console-state":
            let p = model.currentProject?.name ?? "-"
            FileHandle.standardError.write(Data("console-state: project=\(p) tab=\(model.consoleTab ?? "-") shells=\(model.shells(inProject: p).map { model.consoleTitle($0) }) ended=\(model.consoleTab.flatMap { model.terminals.existing($0)?.ended.map { "exit \($0.status ?? -1)" } } ?? "-") empty=\(model.consoleEmpty(project: p).map { $0.title } ?? "-") idleRows=\(model.idleRows().count)\n".utf8))
        case "similar-file": if parts.count > 1 { model.findSimilar(file: parts[1]) }   // the tree's Find Similar
        case "search-archived": model.setIncludeArchived(true)
        case "search-turns":
            if let it = model.search.selectedItem { FileHandle.standardError.write(Data("search-turns: \(it.title) \(it.turns.map { "\($0.number)\($0.matched ? "*" : "")" }) archived=\(it.archived) actions=\(model.search.actions(for: it).map(\.title))\n".utf8)) }
        case "search-scope": model.setSearchScope(parts.count > 1 && parts[1] != "all" ? parts[1] : nil)
        case "search-pick":   // search-pick:<n>: select row n
            if parts.count > 1, let n = Int(parts[1]) { model.selectSearchRow(n) }
        case "search-action":   // search-action:<SearchAction.ID raw value>
            if parts.count > 1, let id = SearchAction.ID(rawValue: parts[1]) { model.runSearchAction(id) }
        case "search-key":   // search-key:down|up|return|tab|esc|exact|narrow|send
            let keys: [String: SearchKey] = ["down": .down, "up": .up, "return": .returnKey, "tab": .tab, "esc": .escape,
                                             "exact": .toggleExact, "narrow": .narrow, "send": .chord(.sendToClaude), "extend": .extendDown,
                                             "readonly": .chord(.readOnly), "copypath": .chord(.copyPath)]
            if parts.count > 1, let k = keys[parts[1]] { model.searchKey(k) }
        case "search-state":
            let st = model.search
            var lines = ["search-state: open=\(st.isOpen) phase=\(st.phase) query=\(st.query.debugDescription) exact=\(st.exact) scope=\(st.scopeProject ?? "all") selected=\(st.selected) menu=\(st.menuOpen) coverage=\(st.coverage ?? "-")"]
            lines += st.items.prefix(12).enumerated().map { i, it in "  \(i == st.selected ? ">" : " ") \(it.goTo ? "goto" : it.kind.rawValue) \(it.project ?? "Unfiled") · \(it.title) · \(it.location) · \(it.matchedBy) \(it.date ?? "")" }
            if case .empty = st.phase { lines.append("  recents: \(st.recents.map(\.query))") }
            lines.append("  footer: ↩ \(st.returnLabel) · similar=\(st.similarTo?.title ?? "-") · at=\(model.altitude.isAllProjects ? "all" : model.currentProject?.name ?? "?") rightTab=\(model.rightTab ?? "-") console=\(model.consoleTab ?? "-")")
            FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        case "ui-state":
            let w = NSApp.windows.first(where: { $0.title == "Duo" })
            let fr = w?.firstResponder.map { String(describing: type(of: $0)) } ?? "-"
            FileHandle.standardError.write(Data("ui-state: renaming=\(model.renamingPath ?? "-") picking=\(model.visiblePage?.picking ?? false) picked=\(model.visiblePage?.picked?.selector ?? "-") send=\((try? model.sendTarget.get()).map { "ok \($0.key.prefix(12))" } ?? { if case .failure(let e) = model.sendTarget { return e.reason }; return "-" }()) key=\(w?.isKeyWindow ?? false) firstResponder=\(fr)\n".utf8))
        case "menus":   // the menu bar as text, to compare with the walk's mockups (DL-108): window captures don't draw it
            if let bar = NSApp.mainMenu {
                FileHandle.standardError.write(Data(("---- menus ----\n" + Self.walk(bar, 0).joined(separator: "\n") + "\n---- end menus ----\n").utf8))
            }
        case "task-menu":   // task-menu:<path>: a task's right-click menu as text (DL-115, board A or B), in the open project
            if parts.count > 1, let p = model.currentProject?.name ?? model.fixture.tasks?.first(where: { $0.path == parts[1] })?.project {
                let menu = NSHostingMenu(rootView: TaskMenuItems(model: model, project: p, path: parts[1]).environment(model))
                menu.update()
                FileHandle.standardError.write(Data(("---- task menu \(parts[1]) ----\n" + Self.walk(menu, 0).joined(separator: "\n") + "\n---- end menus ----\n").utf8))
            }
        case "expand":   // expand:<key>: open a fold (`<project>/archived`, a group's name), as a click does
            if parts.count > 1 { withDuoAnimation(.fold) { _ = model.expandedGroups.insert(parts[1]) } }
        case "collapse":   // collapse:<key>: close it again
            if parts.count > 1 { withDuoAnimation(.fold) { _ = model.expandedGroups.remove(parts[1]) } }
        case "open-sessions":   // open-sessions:<name>+<name>: as if a terminal were open for each in Duo (ENH-7, DL-133)
            let names = parts.count > 1 ? Set(parts[1].split(separator: "+").map(String.init)) : []
            model.fixtureActive = Set(model.fixture.sessions.filter { names.contains($0.name) }.map(\.tabKey))
        case "session-state":   // session-state:<name>=<needsYou|readyForReview|working|idle|resolved>[@<wait>]: as a snapshot would bring it
            let f = parts.count > 1 ? parts[1].split(separator: "=", maxSplits: 1).map(String.init) : []
            guard f.count == 2 else { break }
            let sw = f[1].split(separator: "@", maxSplits: 1).map(String.init)
            let states: [String: SessionState] = ["needsYou": .needsYou, "readyForReview": .readyForReview, "working": .working, "idle": .idle, "resolved": .resolved]
            guard let st = states[sw[0]], let i = model.fixture.sessions.firstIndex(where: { $0.name == f[0] }) else {
                FileHandle.standardError.write(Data("session-state: no session \(f[0]) or state \(sw[0])\n".utf8)); break
            }
            model.fixture.sessions[i].state = st
            if sw.count > 1 { model.fixture.sessions[i].wait = sw[1] }
        case "session-add":   // session-add:<name>=<state>@<wait>: a new session in the open project, as a snapshot would bring it
            let f = parts.count > 1 ? parts[1].split(separator: "=", maxSplits: 1).map(String.init) : []
            guard f.count == 2, let p = model.currentProject?.name, var s = model.fixture.sessions.first(where: { $0.project == p }) else { break }
            let sw = f[1].split(separator: "@", maxSplits: 1).map(String.init)
            s.name = f[0]; s.forkOf = nil; s.question = nil; s.options = nil; s.sessionId = nil; s.document = nil
            s.state = ["needsYou": .needsYou, "working": .working, "idle": .idle][sw[0]] ?? .working
            s.wait = sw.count > 1 ? sw[1] : "now"
            model.fixture.sessions.append(s)
        case "session-remove":   // session-remove:<name>: gone from the list (archived), as a snapshot would bring it
            if parts.count > 1 { model.fixture.sessions.removeAll { $0.name == parts[1] } }
        case "task-complete":   // task-complete:<path>: Mark Complete on a task in the open project (DL-130)
            if parts.count > 1, let p = model.currentProject?.name { model.completeTask(project: p, path: parts[1]) }
        case "task-open":   // task-open:<path>: Status ▸ Open, as Mark Open would (keeps a completing task)
            if parts.count > 1, let p = model.currentProject?.name { model.setTaskStatus(project: p, path: parts[1], "open") }
        case "archive-session":   // archive-session:<name>: Archive Session on its row
            if parts.count > 1, let s = model.fixture.sessions.first(where: { $0.name == parts[1] }) {
                if let why = model.setSessionArchived(s.tabKey, true) { FileHandle.standardError.write(Data("archive-session: \(why)\n".utf8)) }
            }
        case "refresh":   // refresh: start reading a snapshot now, as the 2 s timer would
            model.refreshLive()
        case "sidebar-hover":   // sidebar-hover:on|off: the pointer in the session list or out of it (Q-80)
            model.hoverSidebar(parts.count > 1 && parts[1] == "on")
        case "task-archive", "task-delete":   // task-archive:<path>, task-delete:<path>: the task's question, up and waiting (board C)
            if parts.count > 1, let p = model.currentProject?.name {
                if parts[0] == "task-archive" { model.askArchiveTask(project: p, path: parts[1]) } else { model.askDeleteTask(project: p, path: parts[1]) }
            }
        case "task-move":   // task-move:<path>=<project>: Move to Project's question (board C)
            if parts.count > 1, let p = model.currentProject?.name {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { model.askMoveTask(project: p, path: kv[0], to: kv[1]) }
            }
        // Chat mode (DL-118): the visible Claude session's chat.
        case "chat-prompt":   // chat-prompt:<text>: your message arriving in the fixture chat, as its hook brings it
            if parts.count > 1, let tab = model.consoleTab, let c = model.fixtureChats[tab] { c.log.prompt(parts[1], time: Date(), fromHook: true) }
        case "chat-screen":   // chat-screen:idle|permission|…: the fixture chat's screen, as if the dialog came or went
            if parts.count > 1, let k = ChatScreen.Kind(rawValue: parts[1]), let tab = model.consoleTab, let c = model.fixtureChats[tab] {
                c.harnessScreenKind(k)
            }
        case "chat-cwd":   // chat-cwd:<folder>: the fixture chat's folder, for the composer's @ menu (DL-133)
            if parts.count > 1, let c = model.consoleTab.flatMap({ model.fixtureChats[$0] }) { c.log.cwd = parts[1] }
        case "chat-type":   // chat-type:<text>: typed into the composer, as keys would (its menus follow)
            if parts.count > 1, let v = Self.composerView(for: model.visibleSessionId) {
                v.window?.makeFirstResponder(v)
                v.insertText(parts[1], replacementRange: v.selectedRange())
            }
        case "chat-paste":   // chat-paste:text=<s>|lines=<n>|image|file=<path>: ⌘V in the composer through the menu, from a private pasteboard (never the user's)
            if parts.count > 1, let v = Self.composerView(for: model.visibleSessionId), let w = v.window {
                let pb = HarnessPasteboard.take()
                pb.clearContents()
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                switch kv[0] {
                case "text": pb.setString(kv.count > 1 ? kv[1] : "", forType: .string)
                case "lines": pb.setString((1...(Int(kv.count > 1 ? kv[1] : "20") ?? 20)).map { "line \($0) of the pasted text" }.joined(separator: "\n"), forType: .string)
                case "image": pb.setData(HarnessPasteboard.png, forType: .png)
                case "file": pb.writeObjects([URL(fileURLWithPath: kv.count > 1 ? kv[1] : "/tmp/x.png") as NSURL])
                default: break
                }
                w.makeFirstResponder(v)
                w.makeKey()
                let item = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.action == #selector(NSText.paste(_:)) && $0.keyEquivalent == "v" }
                let enabled = item.map { v.validateUserInterfaceItem($0) }
                let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: w.windowNumber,
                                         context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
                var byMenu = NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
                // A window drawn in the background is never key, so the menu finds no target: send
                // the item's action to the window's first responder, as it would in the key window.
                if !w.isKeyWindow, let item, enabled == true { byMenu = NSApp.sendAction(item.action!, to: w.firstResponder, from: item) }
                let chat = v.coordinator?.chat
                FileHandle.standardError.write(Data("chat-paste: \(kv[0]) key=\(w.isKeyWindow) firstResponder=\(w.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") pasteItem=\(item != nil) enabled=\(enabled.map(String.init) ?? "-") menuHandled=\(byMenu) composer=\(v.plainText.prefix(40).debugDescription) chatComposer=\((chat?.ui.composer ?? "").prefix(40).debugDescription) fallback=\(chat?.fallback.map { "\($0)" } ?? "nil")\n".utf8))
            }
        case "chat-key":   // chat-key:up|down|tab|shift-tab|return|esc: a key in the composer
            let codes: [String: UInt16] = ["up": 126, "down": 125, "tab": 48, "shift-tab": 48, "return": 36, "esc": 53]
            if parts.count > 1, let code = codes[parts[1]], let v = Self.composerView(for: model.visibleSessionId),
               let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: parts[1] == "shift-tab" ? .shift : [], timestamp: 0, windowNumber: v.window?.windowNumber ?? 0,
                                        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) {
                v.keyDown(with: e)
            }
        case "chat-hover":   // chat-hover:<x>x<y>: the pointer at that point of the content (top-left origin), as the link monitor reads it (DL-132 g)
            if parts.count > 1, let w = NSApp.windows.first(where: { $0.title == "Duo" }), let c = w.contentView,
               let k = model.visibleSessionId, let chat = model.chat(for: k) {
                let xy = parts[1].split(separator: "x").compactMap { Double($0) }
                if xy.count == 2 {
                    let p = c.convert(NSPoint(x: xy[0], y: c.isFlipped ? xy[1] : c.bounds.height - xy[1]), to: nil)
                    chat.ui.hoverLink = ChatLinkHover.Probe.link(in: w, at: p)
                    FileHandle.standardError.write(Data("chat-hover: \(chat.ui.hoverLink?.absoluteString ?? "no link")\n".utf8))
                }
            }
        case "home-chat":   // Home's session in chat (DL-142 (6)), as the boards draw it, whatever is on screen: C-47's two composers
            model.fixtureChats["Morning triage"] = HomeListTargets.homeChat()
            model.homeTab = "Morning triage"
            model.fixtureChats["Morning triage"]?.focusComposer += 1   // as an interrupted turn does (ChatSession): Home's composer asks for the keyboard
        case "focus-check":   // C-47, F-183: only the chat on screen has a composer that can hold the keyboard
            func all(_ v: NSView) -> [ComposerTextView] { ((v as? ComposerTextView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
            let visible = model.altitude.isAllProjects ? model.homeTab : model.consoleTab
            var bad: [String] = []
            for w in NSApp.windows {
                for c in w.contentView.map(all) ?? [] where c.coordinator?.chat.key != visible {
                    bad.append("composer of a chat not on screen: \(c.coordinator?.chat.key ?? "-")\(w.firstResponder === c ? " (has the keyboard)" : " (in the window)")")
                }
            }
            // And the other way round: a chat on screen that asked for the keyboard (an interrupted
            // turn, Chat about this, a board's `focusComposer`) has it, so its caret shows.
            if let visible, model.chat(for: visible)?.focusComposer ?? 0 > 0 {
                let shown = NSApp.windows.flatMap { w in (w.contentView.map(all) ?? []).filter { $0.coordinator?.chat.key == visible }.map { (w, $0) } }
                if let (w, c) = shown.first {
                    if w.firstResponder !== c, (w.firstResponder as? PasteBlockEditor)?.owner?.host !== c { bad.append("the composer on screen asked for the keyboard; \(w.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing") has it") }
                } else { bad.append("the chat on screen asked for the keyboard but has no composer") }
            }
            FileHandle.standardError.write(Data("focus-check: \(bad.isEmpty ? "ok" : "FAIL: \(bad.joined(separator: "; "))")\n".utf8))
        case "focus-away":   // the window's keyboard to nothing, as a control that takes it would: focus-check must fail
            NSApp.windows.first(where: { $0.title == "Duo" })?.makeFirstResponder(nil)
        case "composers":   // every composer in the windows: its session, whether it's on screen, and which has the keyboard
            func all(_ v: NSView) -> [ComposerTextView] { ((v as? ComposerTextView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
            for w in NSApp.windows {
                for c in w.contentView.map(all) ?? [] {
                    let shown = !c.isHiddenOrHasHiddenAncestor && c.visibleRect.width > 0
                    FileHandle.standardError.write(Data("composer: chat=\(c.coordinator?.chat.key.prefix(8) ?? "-") shown=\(shown) first=\(w.firstResponder === c) text=\(c.string.debugDescription) frame=\(c.convert(c.bounds, to: nil))\n".utf8))
                }
            }
        case "chat-clear":   // the composer emptied, as select-all and delete would
            if let c = model.visibleSessionId.flatMap(model.chat(for:)) { c.ui.composer = "" }
        case "chat":   // chat:on|off
            if let k = model.visibleSessionId { model.setChatMode(parts.count > 1 && parts[1] == "off" ? .terminal : .chat, for: k) }
        case "chat-send":   // chat-send:<text>: the composer's Return
            if let c = model.visibleSessionId.flatMap(model.chat(for:)), parts.count > 1 {
                let text = parts[1]
                Task { let r = await c.send(text); FileHandle.standardError.write(Data("chat-send: \(r.ok ? "ok" : "refused: \(r.why ?? "")")\n".utf8)) }
            }
        case "chat-answer":   // chat-answer:<n>: a permission or plan card's option
            if let c = model.visibleSessionId.flatMap(model.chat(for:)), parts.count > 1, let n = Int(parts[1]),
               let o = c.screen.options.first(where: { $0.n == n }) {
                let sig = c.screen.sig
                Task { let r = await c.answerOption(n, label: o.label, sig: sig); FileHandle.standardError.write(Data("chat-answer: \(r.ok ? "ok" : "refused: \(r.why ?? "")")\n".utf8)) }
            }
        case "chat-ask":   // chat-ask:pick=<label> | toggle=<label> | next | submit | decline
            if let c = model.visibleSessionId.flatMap(model.chat(for:)), parts.count > 1 {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                let intent: ChatAskIntent? = switch kv[0] {
                case "pick": .pick(kv.count > 1 ? kv[1] : ""); case "toggle": .toggle(kv.count > 1 ? kv[1] : "")
                case "other": .other(kv.count > 1 ? kv[1] : ""); case "next": .next; case "submit": .submit; case "decline": .decline
                default: nil
                }
                if let intent { let sig = c.screen.sig; Task { let r = await c.ask(intent, sig: sig); FileHandle.standardError.write(Data("chat-ask: \(r.ok ? "ok" : "refused: \(r.why ?? "")")\n".utf8)) } }
            }
        case "chat-state":   // what the chat shows, for a scripted run's log
            if let k = model.visibleSessionId, let c = model.chat(for: k) {
                var lines = ["chat-state: \(k.prefix(8)) mode=\(c.mode.rawValue) showing=\(c.showsChat ? "chat" : "terminal") screen=\(c.screen.kind.rawValue) card=\(c.cardUp) fallback=\(c.fallback?.message ?? "-") version=\(c.cliVersion ?? "-") hooks=\(c.log.hooksSeen) streams=\(c.log.streams) compose=\(c.usesExternalEditor)",
                             "  mode=\(c.screen.mode?.rawValue ?? "-") composer=\(c.ui.composer.debugDescription) input=\((c.screen.input ?? "-").debugDescription) menu=\(c.screen.commands.map { ($0.selected ? "❯" : "") + $0.name })"]
                for item in c.log.items {
                    switch item {
                    case .you(let y): lines.append("  you: \(y.text.prefix(80))\(y.queued ? " (queued)" : "")")
                    case .claude(let t):
                        for seg in t.segments {
                            switch seg {
                            case .text(let x): lines.append("  claude: \(x.markdown.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(120))\(x.streaming ? " …" : "")")
                            case .tools(_, let st): for s in st { lines.append("  step: \(s.verb) \(s.object.prefix(60)) [\(s.status)]\(s.detail.map { " · \($0)" } ?? "")") }
                            case .thinking(_, let secs, _): lines.append("  thought \(secs ?? 0)s")
                            case .asked(_, let q): lines.append("  asked: \(q.map(\.header))")
                            }
                        }
                    case .answer(let n): lines.append("  answer: \(n.text)")
                    case .note(let n), .divider(let n), .interrupted(let n): lines.append("  line: \(n.text)")
                    case .result(let r): lines.append("  result: \(r.summary.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(140))")
                    }
                }
                FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            }
        // Blocks the main thread for n seconds: the hang log's own check (F-208).
        case "freeze": Thread.sleep(forTimeInterval: Double(parts.count > 1 ? parts[1] : "5") ?? 5)
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
        case "html-click":   // html-click:<css selector>: a real mouse click at that element's centre in the page
            let wv = model.htmlViewer.webView
            wv.callAsyncJavaScript("const r = document.querySelector(s).getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]",
                                   arguments: ["s": parts.count > 1 ? parts[1] : "a"], in: nil, in: .page) { r in
                guard case .success(let v) = r, let xy = v as? [Double], xy.count == 2, let w = wv.window else { return }
                let inView = NSPoint(x: xy[0], y: wv.isFlipped ? xy[1] : wv.bounds.height - xy[1])
                let p = wv.convert(inView, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { w.sendEvent(e) }
                }
            }
        case "html-js-click":   // html-js-click:<css selector>: the page's own click() on it (when real mouse events can't reach WebKit)
            model.htmlViewer.webView.callAsyncJavaScript("document.querySelector(s).click(); return 1",
                arguments: ["s": parts.count > 1 ? parts[1] : "a"], in: nil, in: .page, completionHandler: nil)
        case "send-html-selection": model.htmlSelectionPayload { if let p = $0 { model.send(p) } }
        case "html-pick": if parts.count > 1 { model.htmlViewer.pick(selector: parts[1]) }
        // The PowerPoint viewer (pptx-handoff): slide-go:<n>, slide-picking, slide-hover:<slide>/<id>
        // (the picker's dashed outline, B), slide-pick:<slide>/<id> (a shape picked, C).
        case "right":   // right:hidden|shown, or toggle: the right pane (DL-129), as ⌥⌘0
            model.rightCollapsed = parts.count > 1 ? parts[1] == "hidden" : !model.rightCollapsed
        case "right-width":   // right-width:<pt>: the right pane's width, as if its divider were dragged
            if let w = Double(parts.count > 1 ? parts[1] : ""), let split = NSApp.windows.lazy.compactMap({ $0.contentView.map { paneSplits($0) } }).first(where: { !$0.isEmpty }).map({ $0[model.altitude.isAllProjects ? 0 : min(1, $0.count - 1)] }),
               split.arrangedSubviews.count >= 2 {
                split.setPosition(split.bounds.width - w - split.dividerThickness, ofDividerAt: split.arrangedSubviews.count - 2)
                split.adjustSubviews()
                FileHandle.standardError.write(Data("right-width: \(split.arrangedSubviews.map { Int($0.frame.width) })\n".utf8))
            } else { FileHandle.standardError.write(Data("right-width: no split\n".utf8)) }
        // The Word viewer (docx-viewer-handoff): docx-menu:open|close, docx-markup:<all|simple|none|original>,
        // docx-person:<name>, docx-hover:<change id or text> (the label above a change), docx-ask-convert
        // (the question Convert to Markdown… asks), docx-dump (the viewer's state on stderr).
        case "docx-menu": model.docxMenuOpen = parts.count > 1 ? parts[1] == "open" : !model.docxMenuOpen
        case "docx-markup": model.setMarkup(mode: parts.count > 1 ? parts[1] : "all")
        case "docx-person": model.setMarkup(person: .some(parts.count > 1 ? parts[1] : nil))
        case "docx-hover": if parts.count > 1 { model.docxViewer.hover(parts[1]) }
        case "docx-picking": model.docxViewer.startPicking()   // Select Text on
        case "docx-pick-hover": if parts.count > 1 { model.docxViewer.hoverPicker(parts[1]) }   // docx-pick-hover:<paraId or c:id>
        case "docx-pick": if parts.count > 1 { model.docxViewer.pick(selector: parts[1]) }   // a paragraph or comment picked
        case "docx-send-picked": if let d = model.visiblePage as? DocxViewer, let p = d.pickedParagraph { FileHandle.standardError.write(Data("docx payload:\n\(SendFormat.paragraph(p, path: d.url?.path ?? "", thread: d.pickedThread))\n".utf8)) }
        case "docx-ask-convert": if let t = model.rightTab { model.askConvertToMarkdown(t) }
        case "docx-dump":
            let v = model.docxViewer
            FileHandle.standardError.write(Data("docx: \(v.url?.lastPathComponent ?? "-") state=\(v.state) people=\(v.people.map { "\($0.name):\($0.count)" }) changes=\(v.changeCount) comments=\(v.comments.count) drawMillis=\(v.drawMillis) frameChanges=\(v.frameChanges) blocked=\(v.blocked)\n".utf8))
            v.pageStats { st in FileHandle.standardError.write(Data("docx page: \(st)\n".utf8)) }
        case "slide-go": model.deckViewer.go(Int(parts.count > 1 ? parts[1] : "1") ?? 1)
        case "slide-picking": model.deckViewer.startPicking()
        case "slide-hover": if parts.count > 1 { model.deckViewer.hover(parts[1]) }
        case "slide-pick": if parts.count > 1 { model.deckViewer.pick(selector: parts[1]) }
        case "html-snapshot":   // html-snapshot:<png path>: what the page web view draws
            let path = parts.count > 1 ? parts[1] : "/tmp/duo-html.png"
            model.htmlViewer.webView.takeSnapshot(with: nil) { image, _ in
                if let t = image?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                FileHandle.standardError.write(Data("html-snapshot: \(image != nil ? path : "failed")\n".utf8))
            }
        case "send-picked": model.sendPickedElement(to: model.visibleSessionId)
        case "send-picked-new": model.sendPickedElement(to: nil)   // Send To ▸ New Session
        case "dump-tail":   // the visible terminal's last lines
            if let t = model.visibleTerminal {
                t.view.selectAll()
                let lines = (t.view.getSelection() ?? "").split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                t.view.selectNone()
                FileHandle.standardError.write(Data("---- tail \(t.key) ----\n\(lines.suffix(30).joined(separator: "\n"))\n".utf8))
            }
            if let l = model.lastSent { FileHandle.standardError.write(Data("---- lastSent to \(l.key.prefix(8)) ----\n\(l.text)\n----\n".utf8)) }
            if let l = model.lastDrafted { FileHandle.standardError.write(Data("---- lastDrafted into \(l.key.prefix(8)) ----\n\(l.text.debugDescription)\n----\n".utf8)) }
        case "browser":   // browser:<url>: a browser tab on that address (duo2 browser open)
            if parts.count > 1, let u = AllowedSites.url(from: parts[1]) { model.newBrowserTab(u) }
        case "browser-cookies":   // the visible tab's store: persistent or not, and each cookie's domain and name (never values; C-32)
            guard let store = model.visibleWebTab?.webView.configuration.websiteDataStore else {
                FileHandle.standardError.write(Data("browser-cookies: no browser tab\n".utf8)); break
            }
            store.httpCookieStore.getAllCookies { cookies in
                let names = cookies.map { "\($0.domain) \($0.name)" }.sorted()
                let google = names.filter { $0.contains("google.") }
                FileHandle.standardError.write(Data("browser-cookies: persistent=\(store.isPersistent) count=\(cookies.count) google=\(google.count)\n\(names.map { "  " + $0 }.joined(separator: "\n"))\n".utf8))
            }
        case "browser-click":   // browser-click:<css selector>: duo2 browser click, real mouse events (DL-124)
            if parts.count > 1 { model.visibleWebTab?.click(selector: parts[1]) { FileHandle.standardError.write(Data("browser-click: \($0 ?? "no match")\n".utf8)) } }
        case "download-notice":   // download-notice:<file name>[=<error>]: the visible tab's download notice, with nothing downloaded (Q-66)
            if parts.count > 1, let t = model.visibleWebTab {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                t.download = DownloadRecord(file: downloads.appending(path: kv[0]), error: kv.count > 1 ? kv[1] : nil, tab: t.id)
            }
        case "download-running":   // download-running:<file name>=<done>/<total bytes>: the visible tab's running-download notice (DL-132 h)
            if parts.count > 1, let t = model.visibleWebTab {
                let kv = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                let n = (kv.count > 1 ? kv[1] : "0/0").split(separator: "/").map { Int64($0) ?? 0 }
                t.running = .init(name: kv[0], done: n.first ?? 0, total: n.count > 1 ? n[1] : 0)
            }
        case "browser-key":   // browser-key:=|-|0|p: ⌘ and the key, with the page holding the keyboard, as NSApp delivers it (no activation)
            if parts.count > 1, let t = model.visibleWebTab, let w = t.webView.window,
               let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: parts[1], charactersIgnoringModifiers: parts[1], isARepeat: false, keyCode: 0) {
                w.makeFirstResponder(t.webView)
                let handled = w.performKeyEquivalent(with: e) || NSApp.mainMenu?.performKeyEquivalent(with: e) == true
                FileHandle.standardError.write(Data("browser-key: ⌘\(parts[1]) handled=\(handled) zoom=\(t.zoom)\n".utf8))
            }
        case "drag-lift":   // drag-lift:<project>: a tile picked up on the map (it sinks), as a real drag starts
            model.dragging = parts.count > 1 ? AppModel.dragPayload(project: parts[1]) : nil
        case "drag-over":   // drag-over:<project>: the dragged tile held over another (it rises)
            model.dropTarget = parts.count > 1 ? parts[1] : nil
        case "drag-land":   // drag-land:<project>=<note>: the drag ends and that tile shows what arrived
            let f = parts.count > 1 ? parts[1].split(separator: "=", maxSplits: 1).map(String.init) : []
            model.dragging = nil; model.dropTarget = nil
            if let name = f.first { model.landedNote = f.count > 1 ? f[1] : "2 sessions moved in"; model.landed = name }
        case "film", "filmw":   // film:<png prefix>:<ms>|<ms>|…: frames at those offsets from now, <prefix>-<ms>.png (Q-77); filmw: with the toolbar
            let f = parts.count > 1 ? parts[1].split(separator: ":", maxSplits: 1).map(String.init) : []
            guard f.count == 2, let window = NSApp.windows.first(where: { $0.title == "Duo" }) else { break }
            let started = CACurrentMediaTime()
            for ms in f[1].split(separator: "|").compactMap({ Int($0) }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) {
                    MainActor.assumeIsolated {
                        let path = "\(f[0])-\(ms).png"
                        let late = Int(((CACurrentMediaTime() - started) * 1000).rounded()) - ms
                        // Web views (the editor, the deck) draw from their own snapshots, as the capture does.
                        WindowCapture.withWebSnapshots(in: window) {
                            do {
                                if parts[0] == "filmw" { try WindowCapture.window(window, to: URL(fileURLWithPath: path)) }
                                else { try WindowCapture.content(of: window, to: URL(fileURLWithPath: path)) }
                            } catch {
                                FileHandle.standardError.write(Data("film: \(path) failed: \(error.localizedDescription)\n".utf8))
                            }
                            FileHandle.standardError.write(Data("film: \(path) (\(late) ms late)\n".utf8))
                        }
                    }
                }
            }
        case "menu-open": model.contextMenuSession = parts.count > 1 ? parts[1] : nil   // a session row as its context menu leaves it (Q-147)
        case let a where a.hasPrefix("wait"): break
        case let a where a.hasPrefix("perf-"): ChatPerf.perform(parts, on: model)   // chat mode's performance runs (F-157)
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
        let contentSize = options.windowSize.map { CGSize(width: $0.width, height: $0.height - designContentTop) } ?? contentSize
        let height = contentSize.height + chrome
        let screen = window.screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: max(screen.minX, screen.midX - contentSize.width / 2),
                             y: max(screen.minY, screen.maxY - height))
        window.setFrame(CGRect(origin: origin, size: CGSize(width: contentSize.width, height: height)), display: true)

        // Scripted actions, one every 0.6 s, so each change renders before the next; `wait:<s>`
        // holds the rest (and the capture) back, for a session's turn to finish.
        var at = 0.0
        for action in options.thenActions {
            if action.hasPrefix("wait:") { at += Double(action.dropFirst(5)) ?? 0; continue }
            // `+<action>` runs a beat after the one before it, not 0.6 s later: `film:` right after its trigger.
            let together = action.hasPrefix("+")
            let act = together ? String(action.dropFirst()) : action
            at += together ? 0.02 : 0.6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { perform(act, on: model) }
        }

        guard options.capturing else { return }
        holdsPeek = true
        // Give SwiftUI and the split view a moment to settle at the new size. When the peek
        // should be open, also wait for its popover to be on screen and done animating: a fixed
        // delay sometimes caught it half-drawn or not yet there (F-44).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + at) {
            whenPopoverSettled(model: model) { capture() }
        }

        // The peek is a transient popover: it closes when Duo stops being the active app, as when a
        // background launch is activated and the user's own app takes focus back (C-35). A capture
        // holds `peekOpen` (`holdsPeek`), so SwiftUI keeps it up.
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

        // Web views are drawn from their own snapshots, so they show even when the window is
        // covered or the screen is locked (F-120). The trace says whether the window was on screen.
        func capture() {
            FileHandle.standardError.write(Data("trace capture onScreen=\(window.occlusionState.contains(.visible)) active=\(NSApp.isActive) background=\(TestBackground.isOn) editorReady=\(model.editor.isPageReady)\n".utf8))
            WindowCapture.withWebSnapshots(in: window) { captureNow() }
        }

        func captureNow() {
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

/// The window's three-pane splits, All projects' then the project's (for `right-width:`). Both
/// altitudes stay alive, so the first alone is often the wrong one (DL-129).
@MainActor func paneSplits(_ v: NSView) -> [NSSplitView] {
    if let s = v as? NSSplitView, s.arrangedSubviews.count >= 3 { return [s] }
    return v.subviews.flatMap(paneSplits)
}

/// A private pasteboard standing in for the general one in harness runs, so a scripted paste never
/// reads or changes the user's clipboard.
@MainActor enum HarnessPasteboard {
    static let name = NSPasteboard.Name("com.dudgeon.duo.harness-paste")
    /// By name, never through the swapped method (after the swap that one is the general board).
    static var board: NSPasteboard { NSPasteboard(name: name) }
    private static var swapped = false
    static func take() -> NSPasteboard {
        if !swapped, let a = class_getClassMethod(NSPasteboard.self, #selector(getter: NSPasteboard.general)),
           let b = class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.duoHarnessGeneral)) {
            method_exchangeImplementations(a, b); swapped = true
        }
        precondition(NSPasteboard.general.name == name, "the harness paste must never reach the user's clipboard")
        return board
    }
    /// A 64×48 red PNG.
    static var png: Data {
        let img = NSImage(size: NSSize(width: 64, height: 48), flipped: false) { r in NSColor.systemRed.setFill(); r.fill(); return true }
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}

extension NSPasteboard {
    @objc class func duoHarnessGeneral() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("com.dudgeon.duo.harness-paste")) }   // HarnessPasteboard.name
}
