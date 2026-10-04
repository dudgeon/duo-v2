import Foundation

/// Folders macOS guards with a privacy prompt (F-28, F-53). Duo never walks into one on its own:
/// asking for Music or Photos access it doesn't need alarms people. A project that lives inside
/// one (a workspace in ~/Documents) is still read, because its own root isn't skipped.
public enum ProtectedFolders {
    public static let names = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Library", "Public",
                               "Applications"]

    public static let paths: Set<String> = {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return Set(names.map { "\(home)/\($0)" })
    }()

    /// Whether a walk that started at `root` should stay out of `dir`.
    public static func skip(_ dir: URL, root: URL) -> Bool {
        let d = dir.standardizedFileURL.path
        guard paths.contains(d) else { return false }
        // The walk started inside this folder: it's the user's own choice of project.
        return !root.standardizedFileURL.path.hasPrefix(d + "/") && root.standardizedFileURL.path != d
    }

    /// The home folder itself is never a file root (a "folder" entry for sessions started in ~).
    public static func isHome(_ url: URL) -> Bool {
        url.standardizedFileURL.path == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    }
}
