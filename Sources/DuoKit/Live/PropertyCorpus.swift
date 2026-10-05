import Foundation

/// The frontmatter names and values used in a project's notes and across Home, for the properties
/// block's suggestions (frontmatter-handoff §4): this project's names first, most used first, each
/// with its type and how many documents use it; and, per name, the values used under it. Read
/// from the files each time; nothing is stored.
public enum PropertyCorpus {
    struct Seen {
        var count = 0
        var here = false
        var types: [String: Int] = [:]
        var values: [String: Int] = [:]
    }

    /// JSON-ready: `["names": [[name, type, count, here]], "values": [name: [[value, count]]]]`.
    public static func scan(here: URL?, others: [URL], fileLimit: Int = 1500) -> [String: Any] {
        var seen: [String: Seen] = [:]
        var files = 0
        var visited = Set<String>()
        for (root, isHere) in ([here].compactMap { $0 }.map { ($0, true) } + others.map { ($0, false) }) {
            for file in markdownFiles(in: root, limit: fileLimit - files) where visited.insert(file.path).inserted {
                files += 1
                guard let props = properties(in: file) else { continue }
                for (name, value, items) in props {
                    var s = seen[name] ?? Seen()
                    s.count += 1
                    if isHere { s.here = true }
                    s.types[type(name: name, value: value, hasItems: !items.isEmpty), default: 0] += 1
                    for v in (items.isEmpty ? [value] : items) {
                        let t = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                        if !t.isEmpty, t.count <= 60 { s.values[t, default: 0] += 1 }
                    }
                    seen[name] = s
                }
            }
        }
        let names = seen.sorted { a, b in
            a.value.here != b.value.here ? a.value.here : a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }.prefix(200).map { k, s -> [String: Any] in
            ["name": k, "type": s.types.max { $0.value < $1.value }?.key ?? "text", "count": s.count, "here": s.here]
        }
        var values: [String: Any] = [:]
        for (k, s) in seen where !s.values.isEmpty {
            values[k] = s.values.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(12).map { ["value": $0.key, "count": $0.value] }
        }
        return ["names": Array(names), "values": values]
    }

    /// The type a value reads as, as the editor reads it (duo-editor.js `valueType`).
    public static func type(name: String, value: String, hasItems: Bool) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        if hasItems || ["aliases", "tags", "cssclasses"].contains(name) || (v.hasPrefix("[") && v.hasSuffix("]") && !v.contains("](")) { return "list" }
        if v.lowercased() == "true" || v.lowercased() == "false" { return "checkbox" }
        if v.wholeMatch(of: /-?\d+(\.\d+)?/) != nil { return "number" }
        if v.prefixMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/) != nil { return "datetime" }
        if v.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil { return "date" }
        if v.contains("](") || v.hasPrefix("http") || v.hasPrefix("\"http") { return "link" }
        return "text"
    }

    /// A note's top-level properties: name, inline value, and list items under it.
    static func properties(in file: URL) -> [(String, String, [String])]? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 8192), let text = String(data: data, encoding: .utf8) ?? String(data: data.prefix(8000), encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard lines.first == "---" else { return nil }
        var out: [(String, String, [String])] = []
        for line in lines.dropFirst() {
            if line == "---" || line == "..." { return out }
            if let m = line.wholeMatch(of: /([^\s#:\-][^:#]*?):(?:\s+(.*))?/) {
                out.append((String(m.1).trimmingCharacters(in: .whitespaces), String(m.2 ?? ""), []))
            } else if let m = line.wholeMatch(of: /\s+-\s+(.*)/), !out.isEmpty {
                out[out.count - 1].2.append(String(m.1))
            }
        }
        return nil  // no closing fence in the first 8 KB: not a properties block
    }

    /// Markdown files under a folder, four levels deep, skipping hidden folders and dependencies.
    static func markdownFiles(in root: URL, limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        var out: [URL] = []
        func walk(_ dir: URL, _ depth: Int) {
            guard out.count < limit, let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for u in items where out.count < limit {
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if depth < 4, !["node_modules", "build", "dist", "Pods", "vendor"].contains(u.lastPathComponent) { walk(u, depth + 1) }
                } else if u.pathExtension.lowercased() == "md" {
                    out.append(u)
                }
            }
        }
        walk(root, 0)
        return out
    }
}
