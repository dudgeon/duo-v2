import AppKit
import Foundation

/// Documents and file verbs inside a project (DL-60–DL-62).
extension AppModel {
    /// The project folder on disk (live mode).
    public var projectFolder: URL? { currentProject.flatMap { liveFolders[$0.name] } }

    /// The editor's own file when it's gone from disk: the document stays open with its text
    /// and the removed-on-disk bar (DL-77).
    public func keptFile(_ path: String) -> URL? {
        guard let e = editorIfLoaded, e.removedOnDisk, let u = e.url, let folder = projectFolder,
              u.standardizedFileURL.path == folder.appending(path: path).standardizedFileURL.path else { return nil }
        return u
    }

    /// The project's own file: `PROJECT.md`, or `HOME.md` for Home (DL-52, DL-60).
    public var projectFile: String? {
        guard let folder = projectFolder else { return nil }
        return ["PROJECT.md", "HOME.md"].first { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }

    /// Open document tabs for the current project, in the order they were opened.
    public var openDocuments: [String] {
        get { currentProject.map { openDocumentsByProject[$0.name] ?? [] } ?? [] }
        set { if let p = currentProject?.name { openDocumentsByProject[p] = newValue } }
    }

    /// Shows a document, adding its tab if it isn't open (one visible at a time, DL-11).
    public func openDocument(_ path: String) {
        if !openDocuments.contains(path) { openDocuments.append(path) }
        rightTab = path
        selectedFile = path
    }

    /// Closes a document tab; its file is saved first if it changed. The neighbour, or Project, shows.
    public func closeDocument(_ path: String) {
        guard let i = openDocuments.firstIndex(of: path) else { return }
        // Save, then let go of the file: the editor kept it after its tab closed, so doc status
        // still said "open in Duo" and Claude's edits went into a buffer nobody could see (F-52).
        if let e = editorIfLoaded, let u = liveFile(path), u.standardizedFileURL == e.url?.standardizedFileURL {
            e.saveNow(force: true)
            e.closeFile()
        }
        openDocuments.remove(at: i)
        if rightTab == path {
            rightTab = openDocuments.indices.contains(i) ? openDocuments[i] : openDocuments.last ?? "Project"
            selectedFile = rightTab == "Project" ? nil : rightTab
        }
    }

    public func closeOtherDocuments(than path: String) {
        for p in openDocuments where p != path { closeDocument(p) }
    }

    /// Whether a path is shown in the tree (renaming happens there).
    public func isInTree(_ path: String) -> Bool {
        currentProject.flatMap { fixture.projectFiles[$0.name] }?.contains { $0 == path || $0 == path + "/" } ?? false
    }

    func relative(_ url: URL) -> String? {
        guard let folder = projectFolder?.standardizedFileURL.path else { return nil }
        let p = url.standardizedFileURL.path
        return p.hasPrefix(folder + "/") ? String(p.dropFirst(folder.count + 1)) : nil
    }

    /// The folder a "new" verb applies to: the folder itself, a file's folder, else the root.
    func targetFolder(for path: String?) -> URL? {
        guard let folder = projectFolder else { return nil }
        guard let path else { return folder }
        let url = folder.appending(path: path)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue ? url : url.deletingLastPathComponent()
    }

    // MARK: Verbs

    /// New Markdown file, named inline (DL-62), opened in the editor.
    public func newMarkdownFile(near path: String? = nil) {
        run {
            guard let dir = targetFolder(for: path) else { return }
            let url = try FileActions.newMarkdown(in: dir)
            guard let rel = relative(url) else { return }
            afterChange { self.openDocument(rel); self.renamingPath = rel }
        }
    }

    public func newFolder(near path: String? = nil) {
        run {
            guard let dir = targetFolder(for: path) else { return }
            let url = try FileActions.newFolder(in: dir)
            guard let rel = relative(url) else { return }
            afterChange { self.renamingPath = rel }
        }
    }

    public func newFromTemplate(_ template: URL, near path: String? = nil) {
        run {
            guard let dir = targetFolder(for: path) else { return }
            let url = try FileActions.newFromTemplate(template, in: dir)
            guard let rel = relative(url) else { return }
            afterChange { self.openDocument(rel); self.renamingPath = rel }
        }
    }

    public var templates: [URL] {
        guard let folder = projectFolder else { return [] }
        return FileActions.templates(project: folder, home: fixture.home.flatMap { liveFolders[$0.name] })
    }

    public func commitRename(_ path: String, to name: String) {
        renamingPath = nil
        run {
            guard let url = projectFolder?.appending(path: path) else { return }
            let dest = try FileActions.rename(url, to: name)
            guard let rel = relative(dest) else { return }
            moved(path, to: rel, url: dest)
        }
    }

    public func duplicate(_ path: String) {
        run {
            guard let url = projectFolder?.appending(path: path) else { return }
            let copy = try FileActions.duplicate(url)
            guard let rel = relative(copy) else { return }
            afterChange { self.renamingPath = rel }
        }
    }

    public func moveToFolder(_ path: String) {
        guard let folder = projectFolder, let dir = FileActions.chooseFolder(startingAt: folder) else { return }
        run {
            let url = folder.appending(path: path)
            let dest = try FileActions.move(url, into: dir)
            if let rel = relative(dest) { moved(path, to: rel, url: dest) } else { closeDocumentsUnder(path); afterChange {} }
        }
    }

    public func moveToTrash(_ path: String) {
        run {
            guard let url = projectFolder?.appending(path: path) else { return }
            closeDocumentsUnder(path)
            if let r = renamingPath, r == path || r.hasPrefix(path + "/") { renamingPath = nil }
            try FileActions.trash(url)
            afterChange {}
        }
    }

    public func copyPath(_ path: String, relative rel: Bool) {
        guard let url = projectFolder?.appending(path: path) else { return }
        FileActions.copy(rel ? path : url.path)
    }

    public func copyLink(_ path: String) {
        FileActions.copy(FileActions.markdownLink(name: (path as NSString).lastPathComponent, relative: path))
    }

    public func reveal(_ path: String) { projectFolder.map { FileActions.reveal($0.appending(path: path)) } }
    public func openInDefaultApp(_ path: String) { projectFolder.map { FileActions.openInDefaultApp($0.appending(path: path)) } }
    public func openWithChosenApp(_ path: String) { projectFolder.map { FileActions.openWithChosenApp($0.appending(path: path)) } }

    // MARK: Helpers

    /// Keeps tabs and the editor pointing at a file or folder that was renamed or moved.
    func moved(_ old: String, to new: String, url: URL) {
        openDocuments = openDocuments.map { p in
            p == old ? new : p.hasPrefix(old + "/") ? new + p.dropFirst(old.count) : p
        }
        if let tab = rightTab, tab == old || tab.hasPrefix(old + "/") { rightTab = new + tab.dropFirst(old.count) }
        if let sel = selectedFile, sel == old || sel.hasPrefix(old + "/") { selectedFile = new + sel.dropFirst(old.count) }
        if let e = editorIfLoaded, let open = e.url, let folder = projectFolder {
            let oldURL = folder.appending(path: old).standardizedFileURL.path
            if open.standardizedFileURL.path == oldURL || open.standardizedFileURL.path.hasPrefix(oldURL + "/") {
                e.fileMoved(to: folder.appending(path: new + open.standardizedFileURL.path.dropFirst(oldURL.count)))
            }
        }
        afterChange {}
    }

    func closeDocumentsUnder(_ path: String) {
        for p in openDocuments where p == path || p.hasPrefix(path + "/") {
            if liveFile(p) == editorIfLoaded?.url { editorIfLoaded?.closeFile() }
            closeDocument(p)
        }
    }

    /// Runs a verb, reporting a failure the way macOS does.
    func run(_ body: () throws -> Void) {
        do { try body() } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// Refreshes the tree right away (rather than on the next 2 s poll), then runs `then`.
    func afterChange(_ then: @escaping @MainActor () -> Void) {
        refreshLive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { then() } }
    }
}
