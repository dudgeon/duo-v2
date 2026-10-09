import AppKit
import Foundation

/// Documents and file verbs inside a project (DL-60–DL-62).
extension AppModel {
    /// The project folder on disk (live mode).
    public var projectFolder: URL? { currentProject.flatMap { liveFolders[$0.name] } }

    /// A tab's or the tree's path as a URL: an outside file's own path (DL-106), or a path that
    /// stays inside the project (C-20). Whether it exists is the caller's question.
    public func fileURL(_ path: String) -> URL? {
        if Self.isOutsideFile(path) { return URL(fileURLWithPath: String(path.dropFirst(Self.outsideFilePrefix.count))) }
        return projectFolder.flatMap { Self.contained(path, in: $0) }
    }

    /// The editor's own file when it's gone from disk: the document stays open with its text
    /// and the removed-on-disk bar (DL-77).
    public func keptFile(_ path: String) -> URL? {
        guard let e = editorIfLoaded, e.removedOnDisk, let u = e.url, let f = fileURL(path),
              u.standardizedFileURL.path == f.standardizedFileURL.path else { return nil }
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

    /// View › Show Hidden Files (DL-105): dotfiles in every project's tree, remembered.
    public func setShowHiddenFiles(_ on: Bool) {
        showHiddenFiles = on
        DuoState.update { $0.showHiddenFiles = on }
        refreshLive()
    }

    /// Whether a folder in the tree shows what's inside (DL-105). Live folders start closed and are
    /// listed when opened; the fixture's tree stays open, as its targets draw it.
    public func isFolderOpen(_ path: String) -> Bool {
        guard terminalsMode == .live, let p = currentProject?.name else { return true }
        return expandedFolders[p]?.contains(path) ?? false
    }

    public func toggleFolder(_ path: String) {
        guard terminalsMode == .live, let p = currentProject?.name else { return }
        if expandedFolders[p, default: []].remove(path) == nil {
            expandedFolders[p, default: []].insert(path)
            // Listed now, as the snapshot lists it (one directory read per open folder), so the
            // folder opens with its files instead of empty until the next refresh (Q-79, DL-130).
            if let root = liveFolders[p] {
                localChange += 1
                fixture.projectFiles[p] = LiveSnapshot.treeFiles(root, showHidden: showHiddenFiles, expanded: expandedFolders[p] ?? [])
            }
            refreshLive()
        }
    }

    /// Shows a document, adding its tab if it isn't open (one visible at a time, DL-11).
    public func openDocument(_ path: String) {
        if !openDocuments.contains(path) { openDocuments.append(path) }
        rightCollapsedProject = false   // a document opened into a hidden right pane shows it (DL-129)
        // Its folders open in the tree, so the selection shows (DL-105).
        if !Self.isOutsideFile(path), !path.hasPrefix("web:"), let p = currentProject?.name {
            var dir = (path as NSString).deletingLastPathComponent
            var added = false
            while !dir.isEmpty && dir != "/" {
                if expandedFolders[p, default: []].insert(dir).inserted { added = true }
                dir = (dir as NSString).deletingLastPathComponent
            }
            if added && terminalsMode == .live { refreshLive() }
        }
        rightTab = path
        selectedFile = path
    }

    /// File › Open File… (DL-106): files from anywhere on the Mac as tabs in this project.
    public func chooseFilesToOpen() {
        guard currentProject != nil else { return }
        for url in FileActions.chooseFiles(startingAt: projectFolder) { openFile(at: url) }
    }

    /// A file from anywhere (Open File…, a drop from Finder, `duo2 doc open`): inside the project it
    /// opens as itself; outside, as a `file:` tab kept with this project, through project switches
    /// and relaunch (DL-106, DL-107). Folders are refused.
    @discardableResult
    public func openFile(at url: URL) -> String? {
        guard currentProject != nil else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        let tab = relative(url) ?? Self.outsideFilePrefix + url.standardizedFileURL.path
        openDocument(tab)
        return tab
    }

    /// Closes a document tab; its file is saved first if it changed. The neighbour, or Project, shows.
    public func closeDocument(_ path: String) {
        guard let i = openDocuments.firstIndex(of: path) else { return }
        if path.hasPrefix("web:") { return closeWebTab(path) }
        // Save, then let go of the file: the editor kept it after its tab closed, so doc status
        // still said "open in Duo" and Claude's edits went into a buffer nobody could see (F-52).
        // A file gone from disk has no liveFile, but its tab still holds the editor (BUG-098): let go of it too.
        if let e = editorIfLoaded, let u = liveFile(path) ?? keptFile(path), u.standardizedFileURL == e.url?.standardizedFileURL {
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
        guard let path, !Self.isOutsideFile(path) else { return folder }
        guard let url = Self.contained(path, in: folder) else { return folder }
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
        return FileActions.templates(project: folder, home: homeFolder)
    }

    /// Home's folder, when there is one (DL-42).
    public var homeFolder: URL? { fixture.home.flatMap { liveFolders[$0.name] } }

    public func commitRename(_ path: String, to name: String) {
        renamingPath = nil
        run {
            guard let url = fileURL(path) else { return }
            let dest = try FileActions.rename(url, to: name)
            guard let rel = relative(dest) else { return }
            moved(path, to: rel, url: dest)
        }
    }

    public func duplicate(_ path: String) {
        run {
            guard let url = fileURL(path) else { return }
            let copy = try FileActions.duplicate(url)
            guard let rel = relative(copy) else { return }
            afterChange { self.renamingPath = rel }
        }
    }

    public func moveToFolder(_ path: String) {
        guard let folder = projectFolder, let dir = FileActions.chooseFolder(startingAt: folder) else { return }
        // The same move as a drop on the tree (DL-117): a taken name asks, and Edit › Undo puts it back.
        guard let url = Self.contained(path, in: folder) else { return }
        moveFiles([url], into: dir)
    }

    public func moveToTrash(_ path: String) {
        run {
            guard let url = fileURL(path) else { return }
            closeDocumentsUnder(path)
            if let r = renamingPath, r == path || r.hasPrefix(path + "/") { renamingPath = nil }
            // Already gone from disk (a tab showing "removed on disk"): closing its tab is all there is
            // to do, not an error (legacy Duo BUG-098, F-262).
            try FileActions.trashIfPresent(url)
            afterChange {}
        }
    }

    public func copyPath(_ path: String, relative rel: Bool) {
        guard let url = fileURL(path) else { return }
        FileActions.copy(rel && !Self.isOutsideFile(path) ? path : url.path)
    }

    public func copyLink(_ path: String) {
        FileActions.copy(FileActions.markdownLink(name: (path as NSString).lastPathComponent, relative: path))
    }

    public func reveal(_ path: String) { fileURL(path).map { FileActions.reveal($0) } }
    public func openInDefaultApp(_ path: String) { fileURL(path).map { FileActions.openInDefaultApp($0) } }
    public func openWithChosenApp(_ path: String) { fileURL(path).map { FileActions.openWithChosenApp($0) } }

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
            // Let go of a file still on disk without saving: callers trash or move it next, and
            // closeDocument's save would land after that and write it back (F-262). A file already
            // gone has no liveFile; closeDocument lets go of it (its save is paused, removed on disk).
            if liveFile(p) == editorIfLoaded?.url { editorIfLoaded?.closeFile() }
            closeDocument(p)
        }
    }

    /// Runs a verb, reporting a failure the way macOS does.
    func run(_ body: () throws -> Void) {
        do { try body() } catch {
            DuoAlert.present(NSAlert(error: error))
        }
    }

    /// Refreshes the tree right away (rather than on the next 2 s poll), then runs `then`.
    func afterChange(_ then: @escaping @MainActor () -> Void) {
        refreshLive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { then() } }
    }
}
