import AppKit
import Foundation

/// Cleaning up projects and sessions (DL-63–DL-66): move sessions into a project, merge one
/// project's sessions into another, make a folder a project. Only Duo's session indexes change;
/// files and transcripts stay where they are (a moved session moves to its new folder the next
/// time it's resumed). Every change is confirmed with exactly what moves, and can be undone.
extension AppModel {
    /// Projects and folders a session or project can go to.
    public func moveTargets(excluding name: String?) -> [Fixture.Project] {
        fixture.projects.filter { $0.name != name }.sorted { a, b in
            a.isFolderOnly != b.isFolderOnly ? !a.isFolderOnly : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Moves sessions into a project, after confirming exactly what moves.
    public func moveSessions(_ ids: [String], to target: String, done: (@MainActor (Bool) -> Void)? = nil) {
        let moving = fixture.sessions.filter { s in (s.sessionId.map(ids.contains) ?? false) && s.project != target }
        guard !moving.isEmpty, let targetFolder = liveFolders[target] else { done?(false); return }
        let names = moving.map { "“\($0.name)” (from \($0.project))" }
        let shown = names.prefix(8).joined(separator: "\n") + (names.count > 8 ? "\nand \(names.count - 8) more" : "")
        confirm(title: moving.count == 1 ? "Move this session to “\(target)”?" : "Move \(moving.count) sessions to “\(target)”?",
                detail: "\(shown)\n\nFiles stay where they are. Each session moves to \(target)'s folder the next time you resume it. You can undo this.",
                button: "Move") { [weak self] ok in
            guard let self, ok else { done?(false); return }
            self.apply(moving, to: target, folder: targetFolder, action: moving.count == 1 ? "Move Session" : "Move Sessions")
            done?(true)
        }
    }

    /// Move to Project ▸ New Project…: asks for a name, then makes the project in Home and moves the
    /// sessions into it. The name sheet is the confirmation: it says what will be made and moved.
    public func moveSessionsToNewProject(_ ids: [String]) {
        guard fixture.sessions.contains(where: { s in s.sessionId.map(ids.contains) ?? false }) else { return }
        showNewProject(moving: ids)
    }

    /// Makes a project folder in Home (or one of its topic folders) with a starter PROJECT.md
    /// carrying the goal, files any sessions given in it, and starts a session there if asked: one
    /// undo step. Returns why it couldn't, or nil.
    @discardableResult
    public func createProject(named raw: String, goal: String = "", in parent: URL? = nil, moving ids: [String], startSession: Bool = false) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let why = newProjectProblem(name, in: parent) { return why }
        guard let root = liveRoot else { return nil }
        let folder = (parent ?? root).appending(path: name)
        let fm = FileManager.default
        let moving = fixture.sessions.filter { s in s.sessionId.map(ids.contains) ?? false }
        guard ids.isEmpty || !moving.isEmpty else { return "No session to move." }
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "\\\"")
        let starter = "---\ngoal: \"\(g)\"\nhealth: on-track\nnext: \"\"\n---\n\n# \(name)\n\n"
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data(starter.utf8).write(to: folder.appending(path: "PROJECT.md"), options: .withoutOverwriting)
        } catch { return error.localizedDescription }
        // Undo also trashes the folder made here, unless something else has been put in it since.
        let trashIfUntouched: @MainActor (AppModel) -> Void = { _ in
            let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if Set(left).isSubset(of: ["PROJECT.md", ".duo"]) { try? FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
        }
        if moving.isEmpty {
            registerUndo("New Project") { model in trashIfUntouched(model); model.refreshLive() }
        } else {
            apply(moving, to: name, folder: folder, action: "Move to New Project", alsoUndo: trashIfUntouched)
        }
        liveFolders[name] = folder   // known now; the snapshot catches up on refresh
        let started = startSession ? newSession(in: name) : nil
        refreshLive()
        if moving.isEmpty {
            // Go to the new project once the refresh has it on the map.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                MainActor.assumeIsolated {
                    self?.open(project: name)
                    if let started { self?.consoleTab = started }
                }
            }
        }
        return nil
    }

    /// Why a new project can't be made in Home with this name, or nil.
    public func newProjectProblem(_ raw: String, in parent: URL? = nil) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = liveRoot else { return "There's no Home folder yet: choose one first (File › Choose Home Folder…)." }
        guard !name.isEmpty else { return "A project needs a name." }
        guard !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else {
            return "“\(name)” can't be a folder name: it can't start with a dot or contain / or :."
        }
        guard liveFolders[name] == nil else { return "There's already a project or folder called “\(name)”: use Move to Project ▸ \(name)." }
        let folder = (parent ?? root).appending(path: name)
        guard !FileManager.default.fileExists(atPath: folder.path) else { return "\(Self.short(folder.path)) already exists." }
        return nil
    }

    /// Merges a project's (or folder's) sessions into another (DL-65: sessions only).
    public func mergeProject(_ source: String, into target: String, done: (@MainActor (Bool) -> Void)? = nil) {
        let moving = fixture.sessions(inProject: source).filter { $0.sessionId != nil }
        DuoLog.write("mergeProject \(source) → \(target): \(moving.count) session(s), target folder \(liveFolders[target]?.path ?? "none")")
        guard let targetFolder = liveFolders[target] else { done?(false); return }
        guard !moving.isEmpty else {
            info("“\(source)” has no sessions to merge.")
            done?(false); return
        }
        let isFolder = fixture.projects.first { $0.name == source }?.isFolderOnly == true
        let names = moving.map { "“\($0.name)”" }
        let shown = names.prefix(8).joined(separator: "\n") + (names.count > 8 ? "\nand \(names.count - 8) more" : "")
        confirm(title: "Merge “\(source)” into “\(target)”?",
                detail: "\(moving.count) session\(moving.count == 1 ? "" : "s") will move to \(target):\n\(shown)\n\n"
                  + "\(source)'s folder and files stay where they are\(isFolder ? "" : ", and it stays a project with no sessions")"
                  + ". Each session moves to \(target)'s folder the next time you resume it. You can undo this.",
                button: "Merge") { [weak self] ok in
            guard let self, ok else { done?(false); return }
            self.apply(moving, to: target, folder: targetFolder, action: "Merge Projects")
            done?(true)
        }
    }

    /// Files the sessions in the target's index (sticky: provenance moved-by-user), removes them
    /// from wherever they were filed, and registers an undo that restores every index exactly.
    private func apply(_ moving: [Fixture.Session], to target: String, folder targetFolder: URL, action: String,
                       alsoUndo: (@MainActor (AppModel) -> Void)? = nil) {
        let touched = Set(moving.compactMap { liveFolders[$0.project] } + [targetFolder])
        let before = touched.map { ($0, SessionIndex.load(project: $0)) }
        for s in moving {
            guard let id = s.sessionId else { continue }
            if let from = liveFolders[s.project] {
                var idx = SessionIndex.load(project: from)
                if idx.sessions.contains(where: { $0.sessionId == id }) {
                    idx.sessions.removeAll { $0.sessionId == id }
                    for i in idx.groups.indices { idx.groups[i].sessions.removeAll { $0 == id } }
                    try? idx.save(project: from)
                }
            }
            var to = SessionIndex.load(project: targetFolder)
            to.sessions.removeAll { $0.sessionId == id }
            to.sessions.append(.init(sessionId: id, provenance: "moved-by-user:\(s.project)"))
            try? to.save(project: targetFolder)
        }
        registerUndo(action) { model in
            for (folder, idx) in before { try? idx.save(project: folder) }
            alsoUndo?(model)
            model.refreshLive()
        }
        refreshLive()
    }

    /// Makes a folder a documented project (DL-63): writes a starter PROJECT.md (until Geoff's
    /// template, G-1), remembers the folder if it's outside the workspace, and opens the file.
    public func makeProject(_ name: String) {
        guard let folder = liveFolders[name] else { return }
        let file = folder.appending(path: "PROJECT.md")
        if !FileManager.default.fileExists(atPath: file.path) {
            let starter = "---\ngoal: \"\"\nhealth: on-track\nnext: \"\"\n---\n\n# \(folder.lastPathComponent)\n\n"
            do { try Data(starter.utf8).write(to: file, options: .withoutOverwriting) } catch { info(error.localizedDescription); return }
        }
        DuoState.update { s in if !s.projects.contains(folder.path) { s.projects.append(folder.path) } }
        extraProjects = DuoState.load().projects.map { URL(fileURLWithPath: $0) }
        registerUndo("Make Project") { model in
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            DuoState.update { $0.projects.removeAll { $0 == folder.path } }
            model.extraProjects = DuoState.load().projects.map { URL(fileURLWithPath: $0) }
            model.refreshLive()
        }
        refreshLive()
        let projectName = folder.lastPathComponent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                self.open(project: projectName)
                self.rightTab = "Project"
            }
        }
    }

    // MARK: Drag and drop

    /// A drag began (the source dims; F-51). There's no drag-ended callback in SwiftUI, so this
    /// watches the mouse button and clears when it's released, wherever the drop went.
    func beginDrag(_ item: String) {
        dragging = item
        watchDragEnd(item)
    }

    private func watchDragEnd(_ item: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.dragging == item else { return }
                if NSEvent.pressedMouseButtons == 0 { self.dragging = nil; self.dropTarget = nil } else { self.watchDragEnd(item) }
            }
        }
    }

    /// What a dragged item carries: "duo-session:<id>" or "duo-project:<name>".
    public static func dragPayload(session id: String) -> String { "duo-session:\(id)" }
    public static func dragPayload(project name: String) -> String { "duo-project:\(name)" }

    /// A drop on a project tile (DL-66): sessions move; a project merges.
    public func handleDrop(_ payload: String, onto target: String) {
        DuoLog.write("handleDrop \(payload) onto \(target)")
        dragging = nil
        let count = payload.hasPrefix("duo-project:")
            ? fixture.sessions(inProject: String(payload.dropFirst("duo-project:".count))).filter { $0.sessionId != nil }.count : 1
        let landed: @MainActor (Bool) -> Void = { [weak self] ok in
            DuoLog.write("drop onto \(target): \(ok ? "done" : "cancelled")")
            guard let self, ok else { return }
            // The target pulses and says what arrived, for a few seconds (F-51): idle sessions
            // don't show on tiles, so without this the move looked like nothing happened.
            self.landed = target
            self.landedNote = count == 1 ? "1 session moved in" : "\(count) sessions moved in"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { MainActor.assumeIsolated { if self.landed == target { self.landed = nil } } }
        }
        if payload.hasPrefix("duo-session:") {
            moveSessions([String(payload.dropFirst("duo-session:".count))], to: target, done: landed)
        } else if payload.hasPrefix("duo-project:") {
            let source = String(payload.dropFirst("duo-project:".count))
            if source != target { mergeProject(source, into: target, done: landed) }
        }
    }

    // MARK: Helpers

    /// Asks before a move or merge, as a sheet on the window. Shown just after any drag has
    /// finished: an alert started inside a drop came up as a loose window with the drag image
    /// frozen over it, so a drop looked like it did nothing (F-51).
    func confirm(title: String, detail: String, button: String, then: @escaping @MainActor (Bool) -> Void) {
        if ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] != nil {   // scripted checks only
            FileHandle.standardError.write(Data("confirm: \(title) | \(detail.replacingOccurrences(of: "\n", with: " / "))\n".utf8))
            return then(true)
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                DuoAlert.present(alert) { r in then(r == .alertFirstButtonReturn) }
            }
        }
    }

    func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        DuoAlert.present(alert)
    }

    /// Edit › Undo, through the main window's undo manager.
    func registerUndo(_ name: String, _ undo: @escaping @MainActor (AppModel) -> Void) {
        guard let manager = NSApp.windows.first(where: { $0.title == "Duo" })?.undoManager else { return }
        // Each change is its own undo step. Left to group by event, a change made from duo2 opens a
        // group that only closes at the next user event, so several duo2 changes undid as one (F-57).
        // At level 0 beginUndoGrouping would first open the automatic group, which then stays open.
        let byEvent = manager.groupsByEvent
        if manager.groupingLevel == 0 { manager.groupsByEvent = false }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { undo(model) } }
        manager.setActionName(name)
        manager.endUndoGrouping()
        manager.groupsByEvent = byEvent
    }
}
