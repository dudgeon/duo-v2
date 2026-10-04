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
    public func moveSessions(_ ids: [String], to target: String) {
        let moving = fixture.sessions.filter { s in s.sessionId.map(ids.contains) ?? false && s.project != target }
        guard !moving.isEmpty, let targetFolder = liveFolders[target] else { return }
        let names = moving.map { "“\($0.name)” (from \($0.project))" }
        let shown = names.prefix(8).joined(separator: "\n") + (names.count > 8 ? "\nand \(names.count - 8) more" : "")
        guard confirm(title: moving.count == 1 ? "Move this session to “\(target)”?" : "Move \(moving.count) sessions to “\(target)”?",
                      detail: "\(shown)\n\nFiles stay where they are. Each session moves to \(target)'s folder the next time you resume it. You can undo this.",
                      button: "Move") else { return }
        apply(moving, to: target, folder: targetFolder, action: moving.count == 1 ? "Move Session" : "Move Sessions")
    }

    /// Merges a project's (or folder's) sessions into another (DL-65: sessions only).
    public func mergeProject(_ source: String, into target: String) {
        let moving = fixture.sessions(inProject: source).filter { $0.sessionId != nil }
        guard let targetFolder = liveFolders[target] else { return }
        guard !moving.isEmpty else {
            info("“\(source)” has no sessions to merge.")
            return
        }
        let isFolder = fixture.projects.first { $0.name == source }?.isFolderOnly == true
        let names = moving.map { "“\($0.name)”" }
        let shown = names.prefix(8).joined(separator: "\n") + (names.count > 8 ? "\nand \(names.count - 8) more" : "")
        guard confirm(title: "Merge “\(source)” into “\(target)”?",
                      detail: "\(moving.count) session\(moving.count == 1 ? "" : "s") will move to \(target):\n\(shown)\n\n"
                        + "\(source)'s folder and files stay where they are\(isFolder ? "" : ", and it stays a project with no sessions")"
                        + ". Each session moves to \(target)'s folder the next time you resume it. You can undo this.",
                      button: "Merge") else { return }
        apply(moving, to: target, folder: targetFolder, action: "Merge Projects")
    }

    /// Files the sessions in the target's index (sticky: provenance moved-by-user), removes them
    /// from wherever they were filed, and registers an undo that restores every index exactly.
    private func apply(_ moving: [Fixture.Session], to target: String, folder targetFolder: URL, action: String) {
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

    /// What a dragged item carries: "duo-session:<id>" or "duo-project:<name>".
    public static func dragPayload(session id: String) -> String { "duo-session:\(id)" }
    public static func dragPayload(project name: String) -> String { "duo-project:\(name)" }

    /// A drop on a project tile (DL-66): sessions move; a project merges.
    public func handleDrop(_ payload: String, onto target: String) {
        if payload.hasPrefix("duo-session:") {
            moveSessions([String(payload.dropFirst("duo-session:".count))], to: target)
        } else if payload.hasPrefix("duo-project:") {
            let source = String(payload.dropFirst("duo-project:".count))
            if source != target { mergeProject(source, into: target) }
        }
    }

    // MARK: Helpers

    func confirm(title: String, detail: String, button: String) -> Bool {
        if ProcessInfo.processInfo.environment["DUO_AUTOCONFIRM"] != nil {   // scripted checks only
            FileHandle.standardError.write(Data("confirm: \(title) | \(detail.replacingOccurrences(of: "\n", with: " / "))\n".utf8))
            return true
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }

    /// Edit › Undo, through the main window's undo manager.
    func registerUndo(_ name: String, _ undo: @escaping @MainActor (AppModel) -> Void) {
        guard let manager = NSApp.windows.first(where: { $0.title == "Duo" })?.undoManager else { return }
        manager.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { undo(model) } }
        manager.setActionName(name)
    }
}
