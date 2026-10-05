import DuoSearch
import Foundation

/// Finds projects on disk (Phase E). A project is a folder with `PROJECT.md`; Home is a folder
/// with `HOME.md` (DL-42), the container of its projects (DL-85); a topic is the folder a project
/// sits in (DL-83). Nothing is written here: discovery is read-only.
public enum ProjectDiscovery {
    public struct Found: Sendable, Equatable {
        public var project: Fixture.Project
        public var folder: URL
        public var isHomeCandidate: Bool
    }

    /// Scans `root` up to `depth` levels for PROJECT.md / HOME.md. Hidden folders, `node_modules`
    /// and `.build` are skipped. A project inside another project's folder is found too, and shown
    /// as its sibling (DL-89: parenthood doesn't matter on the map).
    public static func scan(root: URL, depth: Int = 4) -> [Found] { scanAll(root: root, depth: depth).projects }

    /// The same walk, also returning Claude folders: ones with a `CLAUDE.md` but no PROJECT.md,
    /// listed on the map as folders and searched (DL-101). One inside a project or another Claude
    /// folder belongs to that one (a monorepo's nested `CLAUDE.md` files) and isn't listed.
    public static func scanAll(root: URL, depth: Int = 4) -> (projects: [Found], claudeFolders: [URL]) {
        var found: [Found] = []
        var claude: [URL] = []
        walk(root, root: root, depth: depth, enclosed: false, into: &found, claude: &claude)
        return (found.sorted { $0.folder.path < $1.folder.path }, claude.sorted { $0.path < $1.path })
    }

    private static func walk(_ dir: URL, root: URL, depth: Int, enclosed: Bool, into found: inout [Found], claude: inout [URL]) {
        let fm = FileManager.default
        let projectFile = dir.appending(path: "PROJECT.md")
        let homeFile = dir.appending(path: "HOME.md")
        let isProject = fm.fileExists(atPath: projectFile.path)
        let isHome = fm.fileExists(atPath: homeFile.path)
        let atRoot = dir.standardizedFileURL == root.standardizedFileURL
        let isClaude = !atRoot && !isProject && !isHome && fm.fileExists(atPath: dir.appending(path: "CLAUDE.md").path)
        if isClaude, !enclosed { claude.append(dir) }
        // Home is the container of its projects (DL-85): a HOME.md at the root makes the root Home,
        // and its projects are still found inside it.
        if atRoot, isHome {
            let fmText = (try? String(contentsOf: homeFile, encoding: .utf8)) ?? ""
            found.append(Found(project: project(from: Frontmatter.parse(fmText), folder: dir, root: root, isHome: true),
                               folder: dir, isHomeCandidate: true))
        } else if (isProject || isHome), !atRoot {
            let file = isHome ? homeFile : projectFile
            let fmText = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            found.append(Found(project: project(from: Frontmatter.parse(fmText), folder: dir, root: root, isHome: isHome),
                               folder: dir, isHomeCandidate: isHome))
        }
        guard depth > 0, let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                       options: [.skipsHiddenFiles]) else { return }
        for child in children.sorted(by: { $0.path < $1.path })
        where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && !["node_modules", ".build", "build", "Library"].contains(child.lastPathComponent)
            && !protected.contains(child.standardizedFileURL.path) {
            walk(child, root: root, depth: depth - 1, enclosed: enclosed || (!atRoot && (isProject || isHome || isClaude)),
                 into: &found, claude: &claude)
        }
    }

    /// Folders macOS guards with a privacy prompt (F-28). A workspace inside one is fine (the
    /// root is never skipped); a broader root doesn't wander into them and trigger prompts.
    static var protected: Set<String> { ProtectedFolders.paths }

    /// A single folder with PROJECT.md outside the root (DL-63, DL-82): one made a project in Duo,
    /// or one Claude ran in. Found if it has PROJECT.md.
    public static func found(at folder: URL, root: URL?) -> Found? {
        let file = folder.appending(path: "PROJECT.md")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let p = project(from: Frontmatter.parse((try? String(contentsOf: file, encoding: .utf8)) ?? ""), folder: folder, root: root, isHome: false)
        return Found(project: p, folder: folder, isHomeCandidate: false)
    }

    /// The nearest folder at or above `folder` with a PROJECT.md, never the user's home folder or
    /// above it: a session run in `repo/src` belongs to `repo`'s project (DL-82).
    public static func enclosingProject(_ folder: URL) -> URL? {
        let fm = FileManager.default
        let stop = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        var dir = folder.standardizedFileURL
        while dir.path != "/", dir.path != stop, !stop.hasPrefix(dir.path + "/") {
            if fm.fileExists(atPath: dir.appending(path: "PROJECT.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// The map column a project or folder sits in (DL-83): inside Home, the folder it sits in
    /// ("" directly in Home: the unlabelled first column); outside Home, or with none, its parent
    /// folder's path (`~/repos`).
    /// A project inside another project's folder sits beside it, in the same column (DL-89).
    public static func topic(for folder: URL, root: URL?) -> String {
        let fm = FileManager.default
        let stops: [String] = [root?.standardizedFileURL.path, fm.homeDirectoryForCurrentUser.standardizedFileURL.path, "/"].compactMap { $0 }
        // The outermost project folder around this one, if any: this one sits beside it.
        var outer = folder.standardizedFileURL
        var up = outer.deletingLastPathComponent()
        while !stops.contains(up.path), up.path.count > 1 {
            if fm.fileExists(atPath: up.appending(path: "PROJECT.md").path) { outer = up }
            up = up.deletingLastPathComponent()
        }
        let parent = outer.deletingLastPathComponent()
        if let root, outer.path.hasPrefix(root.standardizedFileURL.path + "/") {
            return parent.path == root.standardizedFileURL.path ? "" : parent.lastPathComponent
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if outer.path == home { return "~" }
        return parent.path == home ? "~" : parent.path.replacingOccurrences(of: home + "/", with: "~/")
    }

    static func project(from fm: Frontmatter, folder: URL, root: URL?, isHome: Bool) -> Fixture.Project {
        let topic: String? = isHome ? nil : topic(for: folder, root: root)
        let name = folder.lastPathComponent
        let path = folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        return Fixture.Project(
            name: name,
            topic: topic,
            path: path,
            isHome: isHome ? true : nil,
            goal: fm.string("goal") ?? "",
            health: fm.string("health").map(Self.healthLabel),
            next: fm.string("next") ?? fm.string("milestone")
        )
    }

    /// `on-track` → `On track` (the Obsidian schema stores health as a slug).
    static func healthLabel(_ slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Exactly one Home (DL-42): the remembered choice if it is still a candidate, else the most
    /// recently modified HOME.md. Returns the chosen folder and whether several competed.
    public static func chooseHome(_ found: [Found], remembered: String?) -> (home: Found?, contested: Bool) {
        let candidates = found.filter(\.isHomeCandidate)
        // Compare resolved paths: /var vs /private/var, symlinked folders (LR-24).
        let resolved = { (p: String) in URL(fileURLWithPath: p).resolvingSymlinksInPath().path }
        if let r = remembered, let hit = candidates.first(where: { resolved($0.folder.path) == resolved(r) }) {
            return (hit, candidates.count > 1)
        }
        let newest = candidates.max { a, b in
            let da = (try? a.folder.appending(path: "HOME.md").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.folder.appending(path: "HOME.md").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        return (newest, candidates.count > 1)
    }
}
