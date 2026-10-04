import Foundation

/// The files of one project that search covers (SRCH FR-7.1.2): text formats, `.gitignore`
/// respected, dependency and build folders skipped, secrets denied, large and binary files skipped.
public enum FileSource {
    public static let maxBytes = 5 * 1024 * 1024
    static let skipDirs: Set<String> = [".git", "node_modules", ".build", "build", "dist", ".venv", "venv", "__pycache__",
                                        ".duo", ".sem", ".next", ".cache", "Pods", "DerivedData", ".swiftpm", "target"]
    static let textExt: Set<String> = [
        "md", "markdown", "mdx", "rst", "txt", "text", "org", "adoc",
        "py", "js", "jsx", "ts", "tsx", "go", "rs", "java", "kt", "swift", "c", "h", "cc", "cpp", "hpp", "m", "mm",
        "rb", "php", "cs", "scala", "sh", "zsh", "bash", "sql", "r", "lua", "pl", "ex", "exs", "hs", "dart", "vue", "svelte",
        "html", "css", "scss", "json", "jsonl", "ndjson", "yaml", "yml", "toml", "ini", "cfg", "xml", "csv", "tsv",
    ]

    /// Text extractors for formats that need a framework the CLI shouldn't link (PDF: PDFKit,
    /// registered by the app, which is the only indexer).
    nonisolated(unsafe) public static var extractors: [String: @Sendable (String) -> String?] = [:]

    public struct Found: Sendable, Equatable {
        public var path: String     // absolute
        public var relative: String
        public var size: Int
        public var modified: Date
    }

    public static func files(in root: URL) -> [Found] {
        // Resolve symlinks first (/var → /private/var, a symlinked workspace): relative paths and
        // "is this still under the project?" must use the same spelling as the files found.
        let root = root.resolvingSymlinksInPath()
        var out: [Found] = []
        walk(root, root: root, prefix: "", rules: GitIgnore.rules(in: root, base: ""), into: &out)
        return out
    }

    /// Relative paths are built while walking, never sliced off a path: the directory listing may
    /// spell the same folder differently (`/var` vs `/private/var`).
    private static func walk(_ dir: URL, root: URL, prefix: String, rules: [GitIgnore.Rule], into out: inout [Found]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]) else { return }
        for url in items.sorted(by: { $0.path < $1.path }) {
            let name = url.lastPathComponent
            let rel = prefix.isEmpty ? name : prefix + "/" + name
            guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]),
                  v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if skipDirs.contains(name) || (name.hasPrefix(".") && name != ".github") { continue }
                if GitIgnore.ignored(rel, isDirectory: true, rules: rules) { continue }
                walk(url, root: root, prefix: rel, rules: rules + GitIgnore.rules(in: url, base: rel), into: &out)
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard textExt.contains(ext) || extractors[ext] != nil, !name.hasPrefix("."), let size = v.fileSize, size <= maxBytes,
                  !Secrets.isDenied(url.path), !GitIgnore.ignored(rel, isDirectory: false, rules: rules) else { continue }
            out.append(Found(path: root.path + "/" + rel, relative: rel, size: size, modified: v.contentModificationDate ?? .distantPast))
        }
    }

    /// The file's text, or nil for binary or undecodable content.
    public static func read(_ path: String) -> String? {
        if let extract = extractors[(path as NSString).pathExtension.lowercased()] { return extract(path) }
        guard let data = FileManager.default.contents(atPath: path), !data.prefix(8192).contains(0) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// Enough of `.gitignore` for search: globs, `**`, anchored and directory-only patterns, `!`.
enum GitIgnore {
    struct Rule { var pattern: String; var base: String; var negate: Bool; var dirOnly: Bool; var anchored: Bool }

    static func rules(in dir: URL, base: String) -> [Rule] {
        guard let text = try? String(contentsOf: dir.appending(path: ".gitignore"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { raw in
            var p = raw.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty, !p.hasPrefix("#") else { return nil }
            var negate = false
            if p.hasPrefix("!") { negate = true; p.removeFirst() }
            let dirOnly = p.hasSuffix("/")
            if dirOnly { p.removeLast() }
            let anchored = p.hasPrefix("/") || p.dropLast().contains("/")
            if p.hasPrefix("/") { p.removeFirst() }
            return Rule(pattern: p, base: base, negate: negate, dirOnly: dirOnly, anchored: anchored)
        }
    }

    static func ignored(_ rel: String, isDirectory: Bool, rules: [Rule]) -> Bool {
        var result = false
        for r in rules {
            if r.dirOnly && !isDirectory { continue }
            let local: String
            if r.base.isEmpty { local = rel }
            else if rel.hasPrefix(r.base + "/") { local = String(rel.dropFirst(r.base.count + 1)) }
            else { continue }
            let target = r.anchored ? local : (local as NSString).lastPathComponent
            if match(r.pattern, target) { result = !r.negate }
        }
        return result
    }

    static func match(_ pattern: String, _ s: String) -> Bool {
        if pattern.contains("**") {
            // `**` crosses directories: turn the glob into a regular expression.
            var re = "^"
            var i = pattern.startIndex
            while i < pattern.endIndex {
                let c = pattern[i]
                if pattern[i...].hasPrefix("**/") { re += "(.*/)?"; i = pattern.index(i, offsetBy: 3); continue }
                if pattern[i...].hasPrefix("**") { re += ".*"; i = pattern.index(i, offsetBy: 2); continue }
                switch c {
                case "*": re += "[^/]*"
                case "?": re += "[^/]"
                case ".", "+", "(", ")", "^", "$", "|", "{", "}", "[", "]", "\\": re += "\\\(c)"
                default: re.append(c)
                }
                i = pattern.index(after: i)
            }
            return s.range(of: re + "$", options: .regularExpression) != nil
        }
        return fnmatch(pattern, s, FNM_PATHNAME) == 0
    }
}
