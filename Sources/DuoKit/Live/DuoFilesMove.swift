import DuoControl
import DuoSearch
import Foundation

/// Moves the old project and Home files to the one name (DL-259 (2), Q-330: Geoff, 2026-10-30,
/// "Rename quietly"): `PROJECT.md` becomes `_PROJECT.md` and `HOME.md` `_HOME.md`, by `git mv` where
/// git tracks the file so its history follows, else a plain rename. Then what pointed at the old
/// name points at the new one: `@PROJECT.md` imports in CLAUDE.md, Obsidian `[[PROJECT]]` links and
/// Markdown `](PROJECT.md)` links, in the notes of Home and the moved projects. Each edit changes the
/// link's file name only, so notes stay Obsidian- and OKF-readable. Quiet: no question, no window.
/// A folder that already has the new name keeps both files as they are (the new one is read).
public enum DuoFilesMove {
    public struct Moved: Equatable, Sendable {
        public var from: URL
        public var to: URL
    }

    /// The renames for `folders`, then the links. Returns what moved and which notes changed.
    @discardableResult
    public static func run(folders: [URL], home: URL?) -> (moved: [Moved], edited: [URL]) {
        var moved: [Moved] = []
        for folder in Set((folders + [home].compactMap { $0 }).map(\.standardizedFileURL)) {
            for (old, new) in [("PROJECT.md", DuoFiles.project), ("HOME.md", DuoFiles.home)] {
                if let m = move(old, to: new, in: folder) { moved.append(m) }
            }
        }
        guard !moved.isEmpty else { return ([], []) }
        // Notes are read from Home's tree and from each moved folder outside it.
        var roots: [URL] = home.map { [$0.standardizedFileURL] } ?? []
        for m in moved {
            let dir = m.to.deletingLastPathComponent()
            if !roots.contains(where: { dir.path == $0.path || dir.path.hasPrefix($0.path + "/") }) { roots.append(dir) }
        }
        var edited: [URL] = []
        let homeRoot = home?.standardizedFileURL
        for root in roots {
            for note in notes(in: root) {
                guard let text = try? String(contentsOf: note, encoding: .utf8) else { continue }
                let fixed = rewrite(text, note: note, moved: moved, home: homeRoot)
                if fixed != text, (try? Data(fixed.utf8).write(to: note, options: .atomic)) != nil { edited.append(note) }
            }
        }
        return (moved, edited)
    }

    /// Renames `old` in `folder` to `new` when the folder has exactly `old` (not a `project.md` that a
    /// case-insensitive disk also answers to, F-186) and nothing by the new name.
    static func move(_ old: String, to new: String, in folder: URL) -> Moved? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard names.contains(old), !names.contains(new) else { return nil }
        let from = folder.appending(path: old), to = folder.appending(path: new)
        let tracked = GitTool.git(["ls-files", "--error-unmatch", "--", old], in: folder, timeout: 10).ok
        if tracked, GitTool.git(["mv", "--", old, new], in: folder, timeout: 10).ok { return Moved(from: from, to: to) }
        do { try FileManager.default.moveItem(at: from, to: to) } catch { return nil }
        return Moved(from: from, to: to)
    }

    /// The Markdown files under `root`, `.claude/CLAUDE.md` included; never `.git`, `.duo`, other
    /// hidden folders, or build and package folders.
    static func notes(in root: URL) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: []) else { return [] }
        for case let url as URL in e {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir {
                // Of `.claude/`, only its CLAUDE.md: never work trees, skills or settings.
                if name == ".claude", fm.fileExists(atPath: url.appending(path: "CLAUDE.md").path) { out.append(url.appending(path: "CLAUDE.md").standardizedFileURL) }
                if name.hasPrefix(".") || ["node_modules", "build", "Library"].contains(name)
                    || ProtectedFolders.paths.contains(url.standardizedFileURL.path) { e.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < 2_000_000 else { continue }
            out.append(url.standardizedFileURL)
        }
        return out
    }

    // MARK: the links

    /// `text` (the note at `note`) with every link to a moved file renamed. Pure, for the checks.
    public static func rewrite(_ text: String, note: URL, moved: [Moved], home: URL?) -> String {
        let dir = note.deletingLastPathComponent().standardizedFileURL
        let olds = Dictionary(moved.map { ($0.from.standardizedFileURL.path, $0) }, uniquingKeysWith: { a, _ in a })
        func hit(_ target: String, from base: URL) -> Bool {
            let t = target.removingPercentEncoding ?? target
            guard !t.contains("://"), !t.hasPrefix("mailto:") else { return false }
            let url = t.hasPrefix("/") ? URL(fileURLWithPath: t) : base.appending(path: t)
            return olds[url.standardizedFileURL.path] != nil
        }
        /// `[[PROJECT]]` by name alone: the nearest moved project file at or above the note, or Home's.
        func bare(_ stem: String) -> Bool {
            let s = stem.lowercased()
            if s == "home" { return home.map { olds[$0.appending(path: "HOME.md").standardizedFileURL.path] != nil } ?? false }
            guard s == "project" else { return false }
            var d = dir
            while d.path != "/" {
                if olds[d.appending(path: "PROJECT.md").path] != nil { return true }
                if DuoFiles.isProject(d) { return false }   // a nearer project that didn't move owns the name
                d = d.deletingLastPathComponent()
            }
            return false
        }
        var out = text
        // @PROJECT.md imports (CLAUDE.md), relative to the note.
        out = replace(out, #"(^|\s)@((?:\./)?(?:[^\s@]*/)?(?:PROJECT|HOME)\.md)(?![\w.])"#, group: 2) { hit($0, from: dir) }
        // [[target#heading|alias]] wikilinks: a bare name, or a path from the note or from Home (the vault).
        out = replace(out, #"\[\[([^\]\|#\^\n]+)"#, group: 1) { t in
            let path = t.hasSuffix(".md") ? t : t + ".md"
            if !t.contains("/") { return bare(String(t.dropLast(t.hasSuffix(".md") ? 3 : 0))) }
            return hit(path, from: dir) || (home.map { hit(path, from: $0) } ?? false)
        }
        // Markdown links and images: ](target "title"), ](<target>).
        out = replace(out, #"\]\(\s*<?([^)\s>#]+)"#, group: 1) { hit($0, from: dir) }
        return out
    }

    /// Prefixes the last path component of each `group` match that `matches` accepts with `_`.
    static func replace(_ text: String, _ pattern: String, group: Int, where matches: (String) -> Bool) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return text }
        let ns = text as NSString
        var out = text, offset = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: group)
            guard r.location != NSNotFound else { continue }
            let target = ns.substring(with: r)
            guard matches(target) else { continue }
            let slash = (target as NSString).range(of: "/", options: .backwards)
            let at = r.location + (slash.location == NSNotFound ? 0 : slash.location + 1) + offset
            let i = out.utf16.index(out.utf16.startIndex, offsetBy: at)
            out.insert("_", at: i)
            offset += 1
        }
        return out
    }
}
