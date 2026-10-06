import Foundation

/// Where Duo is installed, and whether this account can replace it there (F-85, DL-114). Sparkle
/// asks for an administrator password when it can't: `duo2 update probe`, `duo2 update` and
/// Duo's update question all ask this one test, write access to the app and the folder holding it.
public enum InstallLocation {
    /// The .app around a file inside it (the app's executable, `Contents/Helpers/duo2`), or nil
    /// for a file outside an app (a development `duo2`).
    public static func app(containing url: URL?) -> URL? {
        guard var x = url?.resolvingSymlinksInPath() else { return nil }
        while x.path != "/" {
            if x.pathExtension == "app" { return x }
            x.deleteLastPathComponent()
        }
        return nil
    }

    /// This account can replace the app in place, with no administrator password.
    public static func canReplace(_ app: URL) -> Bool {
        let fm = FileManager.default
        return fm.isWritableFile(atPath: app.path) && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Running from a disk image or a translocated copy: nothing can update it in place.
    public static func isTransient(_ app: URL) -> Bool {
        app.path.hasPrefix("/Volumes/") || app.path.contains("/AppTranslocation/")
    }
}
