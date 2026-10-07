import Foundation

/// `@` in chat mode's composer (ENH-3, DL-133): the word being typed after an `@`, the project's
/// files and folders that match it, and the text that replaces it, Claude Code's own mention
/// (`@docs/checkout-flow.md `), so Claude reads the file in as when `@` is typed in the terminal.
public enum FileMention {
    /// The `@` word ending at the caret: `@` at the start or after white space, then no white space.
    /// `range` covers the `@` and the query (UTF-16, as NSTextView counts); nil when the caret isn't in one.
    public static func token(in text: String, caret: Int) -> (range: NSRange, query: String)? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        var i = caret
        while i > 0 {
            let c = ns.character(at: i - 1)
            if c == 0x40 /* @ */ {
                let before = i - 1 > 0 ? ns.character(at: i - 2) : 0x20
                guard let b = UnicodeScalar(before), CharacterSet.whitespacesAndNewlines.contains(b) || before == 0xFFFC else { return nil }
                return (NSRange(location: i - 1, length: caret - i + 1), ns.substring(with: NSRange(location: i, length: caret - i)))
            }
            if let s = UnicodeScalar(c), CharacterSet.whitespacesAndNewlines.contains(s) || c == 0xFFFC { return nil }
            i -= 1
        }
        return nil
    }

    public struct Match: Equatable, Sendable {
        /// Relative to Claude's folder; folders end in `/`.
        public var path: String
        public init(path: String) { self.path = path }
        public var isFolder: Bool { path.hasSuffix("/") }
        /// The last component (a folder keeps its `/`).
        public var name: String {
            let trimmed = isFolder ? String(path.dropLast()) : path
            return (trimmed as NSString).lastPathComponent + (isFolder ? "/" : "")
        }
        /// The folder it's in, with a trailing `/`; empty at the top.
        public var folder: String {
            let trimmed = isFolder ? String(path.dropLast()) : path
            let d = (trimmed as NSString).deletingLastPathComponent
            return d.isEmpty ? "" : d + "/"
        }
        /// What goes into the composer.
        public var inserted: String { "@" + path + " " }
    }

    /// Up to `limit` matches for `query` among `paths`, best first: a name that starts with the
    /// query, then a name that contains it, then a path that contains it (case-insensitive); within
    /// each, shallower first, then alphabetical. An empty query lists the top level, folders first.
    public static func matches(_ query: String, in paths: [String], limit: Int = 8) -> [Match] {
        let q = query.lowercased()
        func depth(_ p: String) -> Int { p.split(separator: "/").count }
        if q.isEmpty {
            return paths.filter { depth($0) == 1 }
                .sorted { ($0.hasSuffix("/") ? 0 : 1, $0.lowercased()) < ($1.hasSuffix("/") ? 0 : 1, $1.lowercased()) }
                .prefix(limit).map { Match(path: $0) }
        }
        var ranked: [(Int, Int, String)] = []
        for p in paths {
            let m = Match(path: p)
            let name = m.name.lowercased(), path = p.lowercased()
            let rank = name.hasPrefix(q) ? 0 : name.contains(q) ? 1 : path.contains(q) ? 2 : -1
            if rank >= 0 { ranked.append((rank, depth(p), path)) }
        }
        ranked.sort { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }
        let byLower = Dictionary(paths.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return ranked.prefix(limit).map { Match(path: byLower[$0.2] ?? $0.2) }
    }

    // MARK: The project's files and folders

    /// Every file and folder under `folder`, as the file tree lists them (DL-105: hidden files and
    /// `neverListed` left out), at any depth, up to `cap`. Folders end in `/`.
    public static func paths(in folder: URL, cap: Int = 5000) -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let u as URL in e {
            let rel = u.pathComponents.suffix(e.level).joined(separator: "/")
            if LiveSnapshot.unlisted(u, rel: rel, root: folder) { e.skipDescendants(); continue }
            out.append((try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? rel + "/" : rel)
            if out.count >= cap { break }
        }
        return out
    }

    /// The walk, once per folder for a few seconds, off the main thread: typing doesn't rewalk.
    @MainActor private static var cache: [String: (at: Date, paths: [String])] = [:]

    @MainActor public static func paths(in folder: String, done: @escaping @MainActor ([String]) -> Void) {
        if let hit = cache[folder], Date().timeIntervalSince(hit.at) < 10 { return done(hit.paths) }
        DispatchQueue.global(qos: .userInitiated).async {
            let found = paths(in: URL(fileURLWithPath: folder))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    cache[folder] = (Date(), found)
                    done(found)
                }
            }
        }
    }
}
