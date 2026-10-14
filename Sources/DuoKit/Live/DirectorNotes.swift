import DuoControl
import Foundation

/// The director's conventions on a task note (DL-194): `## Request` (the user's words, exactly),
/// `done_when:`, `directed_by:`, `## Progress` (one dated line per step) and `status: suggested`
/// for proposed work. Everything else in the note stays the user's: these only add keys and
/// sections, or append a line, and never reorder or rewrite what's there.
public enum DirectorNotes {
    public static let suggested = "suggested"

    /// A new task note for a request: the project's task template (DL-146), then the director's keys
    /// and sections. `status` is `suggested` for proposed work, else `in-progress`.
    public static func newNote(title: String, request: String, doneWhen: String?, director: String, status: String,
                               links: [String], template: String, date: Date = Date()) -> String {
        var text = TaskNotes.newNote(title: title, links: links, template: template, date: date)
        text = TaskNotes.setting("status", status, in: text)
        text = TaskNotes.setting("directed_by", director, in: text)
        if let d = doneWhen?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { text = TaskNotes.setting("done_when", TaskNotes.quoted(d), in: text) }
        let body = text.hasSuffix("\n") ? text : text + "\n"
        return body + "\n## Request\n\n" + request.trimmingCharacters(in: .newlines) + "\n\n## Progress\n\n" + progressLine("Filed by \(director)\(status == suggested ? ", suggested" : "").", date: date) + "\n"
    }

    /// One Progress line: `- 2026-10-14 09:41 <text>`, on one line whatever the text holds.
    public static func progressLine(_ text: String, date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        let one = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return "- \(f.string(from: date)) \(one)"
    }

    /// The note with `line` appended to its `## <section>` (after the section's last non-blank
    /// line), or with that section added at the end. Nothing else moves.
    public static func appending(_ line: String, toSection section: String, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        let head = "## " + section.lowercased()
        // Only headings in the body count, never a line inside the frontmatter.
        var bodyStart = 0
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") { bodyStart = close + 1 }
        guard let h = lines[bodyStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == head }) else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines += ["", "## " + section, "", line, ""]
            return lines.joined(separator: nl)
        }
        let end = lines[(h + 1)...].firstIndex { $0.hasPrefix("# ") || $0.hasPrefix("## ") } ?? lines.endIndex
        var at = end
        while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        if at == h + 1 { lines.insert(contentsOf: ["", line], at: at) } else { lines.insert(line, at: at) }
        return lines.joined(separator: nl)
    }

    /// The director a note names in `directed_by:`, or nil.
    public static func directedBy(_ text: String) -> String? {
        Frontmatter.parse(text).string("directed_by").map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func doneWhen(_ text: String) -> String? {
        Frontmatter.parse(text).string("done_when").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The brief a new worker starts with: what the task is and how to report. Its words come from
    /// the note, which the worker reads; nothing here decides for the user.
    public static func workerPrompt(path: String, director: String) -> String {
        """
        You're the worker on the task @\(path), directed by \(director). Read its ## Request and done_when: first; \
        don't decide anything the Request says you mustn't, and ask in this session if something only the user can answer comes up. \
        As you go, append dated one-line updates under the note's ## Progress. When you're done or stuck, end your turn with your \
        report as your last message: what you did, what you checked and how, and any other work you noticed (as suggestions, not done).
        """
    }
}
