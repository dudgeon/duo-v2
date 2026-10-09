import Foundation

/// Going up from the project's folder in the Files block (DL-106, Q-162): a read-only listing of
/// the parent folders. Files open as tabs (inside the project as themselves, outside as `file:`
/// tabs); rows offer only the outside-file menu, so nothing there can be moved or trashed.
extension AppModel {
    /// The folder the tree is showing, if it has gone up.
    public var browsingFolder: URL? { currentProject.flatMap { browseRoots[$0.name] } }

    /// One folder up from what the tree shows. False at `/`, or outside live mode.
    @discardableResult
    public func browseUp() -> Bool {
        guard terminalsMode == .live, let p = currentProject?.name, let base = browseRoots[p] ?? liveFolders[p] else { return false }
        let parent = base.standardizedFileURL.deletingLastPathComponent()
        guard parent.path != base.standardizedFileURL.path else { return false }
        browseRoots[p] = parent
        browseExpanded[p] = []
        return true
    }

    /// Back to the project's own folder.
    public func browseBack() {
        guard let p = currentProject?.name else { return }
        browseRoots[p] = nil
        browseExpanded[p] = nil
    }

    /// Shows a folder above (or beside) the project's; the project's own folder is back.
    @discardableResult
    public func browse(to folder: URL) -> Bool {
        guard terminalsMode == .live, let p = currentProject?.name, let own = liveFolders[p] else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return false }
        if folder.realPath == own.realPath { browseBack() } else { browseRoots[p] = folder.standardizedFileURL; browseExpanded[p] = [] }
        return true
    }

    public func toggleBrowseFolder(_ rel: String) {
        guard let p = currentProject?.name else { return }
        if browseExpanded[p, default: []].remove(rel) == nil { browseExpanded[p, default: []].insert(rel) }
    }

    /// Opens a row of the browse listing: a file as a tab.
    public func openBrowsed(_ url: URL) { _ = openFile(at: url) }

    /// The browse listing, as paths from the browse root (folders end in `/`).
    public func browseListing() -> [String] {
        guard let p = currentProject?.name, let root = browseRoots[p] else { return [] }
        return LiveSnapshot.treeFiles(root, showHidden: showHiddenFiles, expanded: browseExpanded[p] ?? [])
    }
}
