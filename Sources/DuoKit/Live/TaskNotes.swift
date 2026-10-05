import Foundation

/// Tasks are plain Markdown notes in a project's `tasks/` folder (DL-6, DL-87). A session belongs
/// to a task when the note's frontmatter `sessions:` list links to it (DL-93):
///
///     sessions:
///       - "[Interview synthesis notes](duo2://session/<id>)"
///
/// Bare session ids (DL-13's first form) are read too. Duo only ever edits the `sessions` key,
/// surgically, and leaves the rest of the note byte for byte as it was.
public struct TaskNote: Sendable, Equatable {
    /// Relative to the project folder: `tasks/exec-review-prep.md`.
    public var path: String
    public var title: String
    public var status: String?
    public var sessionIds: [String]
}

public enum TaskNotes {
    static let idPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

    /// Every note in `<project>/tasks/`, by path.
    public static func load(project folder: URL) -> [TaskNote] {
        let dir = folder.appending(path: "tasks")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parse(text, path: "tasks/" + url.lastPathComponent)
        }
    }

    public static func parse(_ text: String, path: String) -> TaskNote {
        let fm = Frontmatter.parse(text)
        let heading = fm.body.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // An emptied `title:` (the name being retyped) falls back to the heading, then the filename.
        let title = [fm.string("title"), heading].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return TaskNote(path: path, title: title ?? stem, status: fm.string("status"),
                        sessionIds: sessionIds(fm.list("sessions")))
    }

    /// The session ids in `sessions:` items: `duo2://session/<id>` links, or bare ids.
    public static func sessionIds(_ items: [String]) -> [String] {
        var out: [String] = []
        for item in items {
            guard let r = item.range(of: idPattern, options: .regularExpression) else { continue }
            let id = String(item[r]).lowercased()
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// `[title](duo2://session/<id>)`, brackets in the title escaped.
    public static func link(title: String, id: String) -> String {
        let t = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(t)](duo2://session/\(id))"
    }

    /// A YAML list item for a link: double-quoted, inner quotes escaped.
    static func item(_ link: String) -> String {
        "\"" + link.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Lowercase ASCII slug for the filename (research doc §1): fixed at creation; `title:` keeps the name.
    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US")).lowercased()
        let s = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "task" : String(s.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// A new task note (DL-6's fields: type, title, status; DL-93's session links).
    public static func newNote(title: String, links: [String]) -> String {
        let t = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var s = "---\ntype: task\ntitle: \"\(t)\"\nstatus: open\n"
        s += links.isEmpty ? "sessions: []\n" : "sessions:\n" + links.map { "  - \(item($0))\n" }.joined()
        s += "---\n\n# \(title)\n\n"
        return s
    }

    /// The statuses a task can have (research doc §1; TaskNotes-compatible).
    public static let statuses = ["open", "in-progress", "waiting", "review", "done", "dropped"]

    /// The note with one scalar frontmatter key set (or removed, `value` nil), touching nothing else.
    public static func setting(_ key: String, _ value: String?, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            return value.map { (["---", "\(key): \($0)", "---"] + lines).joined(separator: nl) } ?? text
        }
        if let k = (1..<close).first(where: { lines[$0].hasPrefix("\(key):") }) {
            if let value { lines[k] = "\(key): \(value)" } else { lines.remove(at: k) }
        } else if let value {
            lines.insert("\(key): \(value)", at: close)
        }
        return lines.joined(separator: nl)
    }

    /// Status, plus `completed:` (a date) when it becomes done or dropped, removed when it reopens.
    public static func settingStatus(_ status: String, in text: String, today: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let closed = ["done", "dropped"].contains(status)
        return setting("completed", closed ? f.string(from: today) : nil, in: setting("status", status, in: text))
    }

    /// The note with `link` added to its `sessions:` list, touching only that key; nil if the
    /// session is already listed.
    public static func adding(_ link: String, to text: String) -> String? {
        guard let id = link.range(of: idPattern, options: .regularExpression).map({ String(link[$0]).lowercased() }) else { return nil }
        if parse(text, path: "x.md").sessionIds.contains(id) { return nil }
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        let entry = "  - \(item(link))"
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            // No frontmatter yet: add one holding just the list.
            return (["---", "sessions:", entry, "---"] + lines).joined(separator: nl)
        }
        if let k = (1..<close).first(where: { lines[$0].hasPrefix("sessions:") }) {
            let value = lines[k].dropFirst("sessions:".count).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                var end = k + 1
                while end < close, lines[end].hasPrefix("  - ") || lines[end].hasPrefix("- ") { end += 1 }
                let indent = end > k + 1 && lines[end - 1].hasPrefix("- ") ? "- " : "  - "
                lines.insert(indent + item(link), at: end)
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                // An inline list becomes a block list with the same items.
                let old = Frontmatter.splitInlineList(String(value.dropFirst().dropLast())).filter { !$0.isEmpty }
                lines.replaceSubrange(k...k, with: ["sessions:"] + old.map { "  - \($0)" } + [entry])
            } else {
                lines.replaceSubrange(k...k, with: ["sessions:", "  - \(value)", entry])
            }
        } else {
            lines.insert(contentsOf: ["sessions:", entry], at: close)
        }
        return lines.joined(separator: nl)
    }
}
