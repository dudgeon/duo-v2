import DuoControl
import Foundation

extension AppModel {
    /// Moves each project's and Home's file to the one name (DL-259, Q-330), quietly, off the main
    /// thread, once per folder per launch. An isolated instance moves nothing unless
    /// `DUO_MOVE_FILES=1`: test workspaces keep the names their scripts wrote.
    func moveDuoFiles(_ folders: [String: URL]) {
        guard !SupportFolder.isIsolated || Env.value("DUO_MOVE_FILES") == "1" else { return }
        let fresh = folders.filter { !movesChecked.contains($0.value.standardizedFileURL.path) }
        guard !fresh.isEmpty else { return }
        for f in fresh.values { movesChecked.insert(f.standardizedFileURL.path) }
        let home = homeFolder
        Task { @MainActor in
            let r = await Task.detached(priority: .utility) { DuoFilesMove.run(folders: Array(fresh.values), home: home) }.value
            guard !r.moved.isEmpty else { return }
            // An open tab on the old name follows the file.
            for (name, folder) in fresh {
                guard r.moved.contains(where: { $0.from.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path }) else { continue }
                let renamed = { (p: String) -> String in p == "PROJECT.md" || p == "HOME.md" ? "_" + p : p }
                if let docs = self.openDocumentsByProject[name] { self.openDocumentsByProject[name] = docs.map(renamed) }
                if self.currentProject?.name == name {
                    self.rightTab = self.rightTab.map(renamed)
                    self.selectedFile = self.selectedFile.map(renamed)
                }
            }
            FileHandle.standardError.write(Data("duo: moved \(r.moved.count) file(s) to the underscore name, fixed links in \(r.edited.count) note(s) (DL-259)\n".utf8))
            self.refreshLive()
        }
    }
}
