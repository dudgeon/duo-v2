import DuoSearch
import Foundation

/// Finds projects on disk (Phase E). A project is a folder with `PROJECT.md`; Home is a folder
/// with `HOME.md` (DL-42); a topic is the project's parent folder under the workspace root
/// (brief §3). Nothing is written here: discovery is read-only.
public enum ProjectDiscovery {
    public struct Found: Sendable, Equatable {
        public var project: Fixture.Project
        public var folder: URL
        public var isHomeCandidate: Bool
    }

    /// Scans `root` up to `depth` levels for PROJECT.md / HOME.md. Hidden folders, `node_modules`
    /// and `.build` are skipped; a folder that is a project isn't searched further (projects don't
    /// nest, CONS L2).
    public static func scan(root: URL, depth: Int = 3) -> [Found] {
        var found: [Found] = []
        walk(root, root: root, depth: depth, into: &found)
        return found.sorted { $0.folder.path < $1.folder.path }
    }

    private static func walk(_ dir: URL, root: URL, depth: Int, into found: inout [Found]) {
        let fm = FileManager.default
        let projectFile = dir.appending(path: "PROJECT.md")
        let homeFile = dir.appending(path: "HOME.md")
        let isProject = fm.fileExists(atPath: projectFile.path)
        let isHome = fm.fileExists(atPath: homeFile.path)
        if (isProject || isHome), dir.standardizedFileURL != root.standardizedFileURL {
            let file = isHome ? homeFile : projectFile
            let fmText = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            found.append(Found(project: project(from: Frontmatter.parse(fmText), folder: dir, root: root, isHome: isHome),
                               folder: dir, isHomeCandidate: isHome))
            return
        }
        guard depth > 0, let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                                       options: [.skipsHiddenFiles]) else { return }
        for child in children.sorted(by: { $0.path < $1.path })
        where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            && !["node_modules", ".build", "build", "Library"].contains(child.lastPathComponent)
            && !protected.contains(child.standardizedFileURL.path) {
            walk(child, root: root, depth: depth - 1, into: &found)
        }
    }

    /// Folders macOS guards with a privacy prompt (F-28). A workspace inside one is fine (the
    /// root is never skipped); a broader root doesn't wander into them and trigger prompts.
    static var protected: Set<String> { ProtectedFolders.paths }

    /// A single folder made a project outside the root (DL-63): found if it has PROJECT.md.
    public static func found(at folder: URL, root: URL) -> Found? {
        let file = folder.appending(path: "PROJECT.md")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var p = project(from: Frontmatter.parse((try? String(contentsOf: file, encoding: .utf8)) ?? ""), folder: folder, root: root, isHome: false)
        if !folder.path.hasPrefix(root.path + "/") { p.topic = "Elsewhere" }
        return Found(project: p, folder: folder, isHomeCandidate: false)
    }

    static func project(from fm: Frontmatter, folder: URL, root: URL, isHome: Bool) -> Fixture.Project {
        let parent = folder.deletingLastPathComponent()
        let topic: String? = isHome || parent.standardizedFileURL == root.standardizedFileURL
            ? nil : parent.lastPathComponent.capitalized
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
