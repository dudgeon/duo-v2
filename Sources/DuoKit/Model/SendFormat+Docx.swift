import DuoSearch
import Foundation

/// What Claude gets for a paragraph or comment picked in a Word document (DL-162 W5, `picked`):
/// where it is, its text with All Markup's changes accepted, its tracked changes and comments,
/// and the command for the rest. Lines with nothing in them are left out.
extension SendFormat {
    /// `~/garden/Garden plan.docx`: a path under the home folder as the board writes it.
    public static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// "7 Sep" from an ISO 8601 date, in the document's own day (UTC), as the cards and labels say it.
    public static func day(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return "" }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][c.component(.month, from: d) - 1]
        return "\(c.component(.day, from: d)) \(m)"
    }

    static let changeVerbs = ["insert": "inserted", "delete": "deleted", "move-from": "moved away", "move-to": "moved here", "format": "formatted"]

    /// "Blake Editor deleted “three” and inserted “four” 6 Sep": one person's changes in a row, on one day.
    public static func changeLines(_ changes: [Docx.Change]) -> String {
        var groups: [(author: String, date: String, parts: [String])] = []
        for c in changes {
            let part = (changeVerbs[c.kind] ?? c.kind) + (c.text.isEmpty ? "" : " “\(line(c.text))”")
            let d = day(c.date)
            if let last = groups.last, last.author == c.author, last.date == d { groups[groups.count - 1].parts.append(part) }
            else { groups.append((c.author, d, [part])) }
        }
        return groups.map { "\($0.author) \($0.parts.joined(separator: " and "))" + ($0.date.isEmpty ? "" : " \($0.date)") }.joined(separator: "; ")
    }

    /// "Avery Reviewer 1 Sep: “…” (reply Blake Editor: “…”)": a thread per entry.
    public static func commentLines(_ comments: [Docx.Comment]) -> String {
        var out: [String] = []
        for c in comments where c.parent == nil {
            var s = "\(c.author)\(day(c.date).isEmpty ? "" : " " + day(c.date)): “\(line(c.text))”"
            for r in comments where r.thread == c.id && r.id != c.id { s += " (reply \(r.author): “\(line(r.text))”)" }
            out.append(s + (c.resolved ? " [resolved]" : ""))
        }
        return out.joined(separator: "; ")
    }

    /// `thread`: a picked comment's root id, so the comments line is that thread alone (its paragraph is still sent).
    public static func paragraph(_ p: Docx.Paragraph, path: String, thread: String? = nil) -> String {
        let shown = tilde(path)
        var out = "From \(line(shown)), "
        out += thread == nil ? "paragraph " : "a comment on paragraph "
        out += (p.id ?? "#\(p.index)") + (p.heading.map { " under “\(line($0))”" } ?? "") + ":"
        let text = line(p.text)
        out += "\ntext: " + (text.count > 600 ? String(text.prefix(600)) + "…" : text)
        if !p.changes.isEmpty { out += "\ntracked changes: " + changeLines(p.changes) }
        let comments = thread.map { t in p.comments.filter { $0.thread == t } } ?? p.comments
        if !comments.isEmpty { out += "\ncomments: " + commentLines(comments) }
        out += "\nthe whole document: duo2 doc outline \(quoted(shown))"
        return finish(out)
    }

    /// Picker bar line 2: "3 tracked changes: Casey Counsel inserted, Blake Editor deleted and inserted".
    public static func paragraphSummary(_ p: Docx.Paragraph) -> String {
        var parts: [String] = []
        if !p.changes.isEmpty {
            var who: [(String, [String])] = []
            for c in p.changes {
                let v = changeVerbs[c.kind] ?? c.kind
                if let i = who.firstIndex(where: { $0.0 == c.author }) { if !who[i].1.contains(v) { who[i].1.append(v) } } else { who.append((c.author, [v])) }
            }
            parts.append("\(p.changes.count) tracked change\(p.changes.count == 1 ? "" : "s"): " + who.map { "\($0.0) \($0.1.joined(separator: " and "))" }.joined(separator: ", "))
        }
        let roots = p.comments.filter { $0.parent == nil }
        if !roots.isEmpty {
            let names = p.comments.map(\.author).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            parts.append("\(roots.count) comment\(roots.count == 1 ? "" : "s"): " + names.joined(separator: ", "))
        }
        return parts.isEmpty ? "No tracked changes or comments." : parts.joined(separator: " · ")
    }
}
