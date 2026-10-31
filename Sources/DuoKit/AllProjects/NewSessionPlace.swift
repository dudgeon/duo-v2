import Foundation

/// Where the New session row at All projects starts a session (DL-262).
public struct StartPlace: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case home, project, folder }
    public var kind: Kind
    /// What the popup and the tooltip call it: "★ home", a project's name, or a folder's `~` path.
    public var label: String
    public var folder: URL
    /// The project the session files under (Home's name for Home); nil for a plain folder.
    public var project: String?

    public init(kind: Kind, label: String, folder: URL, project: String? = nil) {
        self.kind = kind; self.label = label; self.folder = folder; self.project = project
    }
}

public enum StartDefault {
    /// Duo's Home when there is one, else `~/Documents` when the folder exists, else nothing: no default
    /// (the row reads Choose…). Duo never creates `~/Documents` and never falls back to `~`.
    public static func resolve(home: (name: String, folder: URL)?, documents: URL, documentsExists: Bool) -> StartPlace? {
        if let home { return StartPlace(kind: .home, label: "★ home", folder: home.folder, project: home.name) }
        if documentsExists { return StartPlace(kind: .folder, label: "~/Documents", folder: documents) }
        return nil
    }

    public static var documentsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents") }

    /// Read off the main thread: `stat` on a protected folder is cheap, but nothing on the main thread touches one (F-28).
    public static func documentsExistsOnDisk() -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: documentsURL.path, isDirectory: &isDir) && isDir.boolValue
    }
}
