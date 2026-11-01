import DuoControl
import DuoSearch
import Foundation

/// The rename map (Q-385, DL-293): a template's definition says `renamed: {context: note}`, the checker
/// says "renamed" rather than "unknown", and `duo2 deck migrate` rewrites the slot headings in every
/// deck of the project that uses the pack, showing the change as a diff.
extension Deck {
    public struct Migration: Sendable {
        public var deck: URL
        public var before: String
        public var after: String
        /// (slide number, line, old heading, new heading)
        public var changes: [(slide: Int, line: Int, old: String, new: String)]
    }

    /// `source` with the slot headings the pack renamed rewritten. A slide that already has the new
    /// heading is left alone (nothing is merged).
    public static func migrate(source: String, pack: Pack) -> (text: String, changes: [(slide: Int, line: Int, old: String, new: String)]) {
        let parsed = parse(source)
        var lines = source.components(separatedBy: "\n")
        var changes: [(Int, Int, String, String)] = []
        for (n, slide) in parsed.slides.enumerated() {
            guard let t = pack.template(slide.template), !t.renamed.isEmpty else { continue }
            for slot in slide.slots {
                guard let new = t.renamed[slot.name], slide.slot(new) == nil, slot.line - 1 < lines.count,
                      lines[slot.line - 1].hasPrefix("## ") else { continue }
                lines[slot.line - 1] = "## \(new)"
                changes.append((n + 1, slot.line, slot.name, new))
            }
        }
        return (lines.joined(separator: "\n"), changes)
    }

    /// A unified diff of one file's change (3 lines of context).
    public static func unifiedDiff(path: String, old: String, new: String) -> String {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        guard a.count == b.count else { return "" }   // renames change lines in place
        let changed = a.indices.filter { a[$0] != b[$0] }
        guard !changed.isEmpty else { return "" }
        var out = ["--- \(path)", "+++ \(path)"]
        var i = 0
        while i < changed.count {
            var j = i
            while j + 1 < changed.count, changed[j + 1] - changed[j] <= 7 { j += 1 }
            let lo = max(0, changed[i] - 3), hi = min(a.count - 1, changed[j] + 3)
            out.append("@@ -\(lo + 1),\(hi - lo + 1) +\(lo + 1),\(hi - lo + 1) @@")
            for k in lo...hi {
                if a[k] != b[k] { out.append("-" + a[k]); out.append("+" + b[k]) } else { out.append(" " + a[k]) }
            }
            i = j + 1
        }
        return out.joined(separator: "\n")
    }

    /// Every deck under `root` that uses `pack` (or, with nil, any pack that renames slots) and has headings to rewrite.
    public static func migrations(root: URL, packDirs: [URL], pack only: String?) -> [Migration] {
        let fm = FileManager.default
        var packs: [String: Pack] = [:]
        var out: [Migration] = []
        var stack = [root]
        let skip: Set<String> = [".git", ".build", "node_modules", ".duo", ".obsidian", "templates"]
        var visited = 0
        while let dir = stack.popLast(), visited < 20_000 {
            if ProtectedFolders.skip(dir, root: root) { continue }
            for f in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() {
                visited += 1
                if f.hasPrefix(".") || skip.contains(f) { continue }
                let u = dir.appending(path: f)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
                if isDir.boolValue { stack.append(u); continue }
                guard f.hasSuffix(".md"), let text = try? String(contentsOf: u, encoding: .utf8), text.hasPrefix("---"), text.contains("type: deck") else { continue }
                let front = parse(text).front
                guard front["type"] == "deck", let name = front["template"], only == nil || only == name else { continue }
                if packs[name] == nil { packs[name] = try? loadPack(name, in: packDirs) }
                guard let pack = packs[name] else { continue }
                let r = migrate(source: text, pack: pack)
                if !r.changes.isEmpty { out.append(Migration(deck: u, before: text, after: r.text, changes: r.changes)) }
            }
        }
        return out.sorted { $0.deck.path < $1.deck.path }
    }
}
