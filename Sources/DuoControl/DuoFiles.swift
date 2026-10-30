import Foundation

/// The files that make a folder a project or Home (DL-259 (2)): one name, the underscore prefix,
/// `_PROJECT.md` and `_HOME.md`. Duo writes only these. It still reads the old `PROJECT.md` and
/// `HOME.md` as the same file until they are moved over (Q-330); where both are there, the
/// underscore one wins.
public enum DuoFiles {
    public static let project = "_PROJECT.md"
    public static let home = "_HOME.md"
    /// Every name the project file is read by, the one Duo writes first.
    public static let projectNames = [project, "PROJECT.md"]
    public static let homeNames = [home, "HOME.md"]

    /// The project file in `folder`, by whichever name it has; nil if there's none.
    public static func projectFile(in folder: URL) -> URL? { first(of: projectNames, in: folder) }
    public static func homeFile(in folder: URL) -> URL? { first(of: homeNames, in: folder) }
    public static func isProject(_ folder: URL) -> Bool { projectFile(in: folder) != nil }
    public static func isHome(_ folder: URL) -> Bool { homeFile(in: folder) != nil }
    /// The project file to read or write in `folder`: the one there, else the name Duo writes.
    public static func projectFileOrNew(in folder: URL) -> URL { projectFile(in: folder) ?? folder.appending(path: project) }
    public static func homeFileOrNew(in folder: URL) -> URL { homeFile(in: folder) ?? folder.appending(path: home) }

    /// Whether `name` (a file name, not a path) is a project or Home file by any of its names.
    public static func isProjectFileName(_ name: String) -> Bool { projectNames.contains(name) }
    public static func isHomeFileName(_ name: String) -> Bool { homeNames.contains(name) }

    private static func first(of names: [String], in folder: URL) -> URL? {
        names.lazy.map { folder.appending(path: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
