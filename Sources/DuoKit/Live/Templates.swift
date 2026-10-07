import Foundation

/// The templates a new `PROJECT.md` and a new task note are made from (DL-146).
///
/// A template is a plain Markdown file that Obsidian's Templates plugin can use as it is: the only
/// placeholders filled are Obsidian's own (`{{title}}`, `{{date}}`, `{{time}}`, `{{date:FORMAT}}`,
/// `{{time:FORMAT}}`, Moment formats). Templater's `<% … %>` is left exactly as written. Values a
/// flow knows (a goal, a status, session links) are set by key after the fill, so a template never
/// needs a Duo-only placeholder. Which template: a project's `templates/new-task.md`, else Home's
/// `templates/new-<kind>.md`, else Duo's base below. A project's own folder doesn't exist yet when the
/// project is made, so `new-project.md` comes from Home or the base only.
public enum Templates {
    public enum Kind: String, CaseIterable, Sendable {
        case project, task
        /// The file name in a `templates/` folder: `new-project.md`, `new-task.md`. Not `project.md`:
        /// on a case-insensitive disk that is `PROJECT.md`, and would make `templates/` a project (F-186).
        public var fileName: String { "new-" + rawValue + ".md" }
    }

    /// Where the template in use comes from.
    public enum Scope: Equatable, Sendable {
        case project(URL), home(URL), base
    }

    /// A value set by key after the fill.
    public enum Value: Equatable, Sendable {
        case scalar(String)
        case list([String])
    }

    // MARK: The base templates (board T0)

    public static let baseProject = """
    ---
    type: project
    title: "{{title}}"
    aliases:
      - "{{title}}"
    status: active
    goal:
    health:
    next:
    created: "{{date}}"
    ---

    # {{title}}

    ## Why

    ## Done when

    - [ ]

    ## Notes

    ## Log

    - {{date}} Started.

    """

    public static let baseTask = """
    ---
    type: task
    title: "{{title}}"
    status: open
    sessions: []
    created: "{{date}}"
    ---

    # {{title}}

    ## Done when

    - [ ]

    ## Notes

    """

    public static func base(_ kind: Kind) -> String { kind == .project ? baseProject : baseTask }

    // MARK: Which template

    /// The user's template file for `kind`, if there is one: the project's own (tasks only), then Home's.
    public static func file(_ kind: Kind, project: URL?, home: URL?) -> (url: URL, scope: Scope)? {
        let fm = FileManager.default
        if kind == .task, let project {
            let own = project.appending(path: "templates").appending(path: kind.fileName)
            if fm.fileExists(atPath: own.path) { return (own, .project(project)) }
        }
        if let home {
            let url = home.appending(path: "templates").appending(path: kind.fileName)
            if fm.fileExists(atPath: url.path) { return (url, .home(home)) }
        }
        return nil
    }

    /// The template text in use for `kind`, and where it came from.
    public static func text(_ kind: Kind, project: URL?, home: URL?) -> (text: String, scope: Scope) {
        if let f = file(kind, project: project, home: home), let data = try? Data(contentsOf: f.url),
           let s = String(data: data, encoding: .utf8) {
            return (s, f.scope)
        }
        return (base(kind), .base)
    }

    /// Where a template of `kind` lives for a scope: `<folder>/templates/new-<kind>.md`.
    public static func path(_ kind: Kind, in folder: URL) -> URL {
        folder.appending(path: "templates").appending(path: kind.fileName)
    }

    /// Whether a path relative to a project or Home is one of these templates
    /// (`templates/new-project.md`, `templates/new-task.md`), so the editor shows the template bar.
    public static func kind(ofRelativePath rel: String) -> Kind? {
        Kind.allCases.first { rel == "templates/" + $0.fileName }
    }

    // MARK: Making a file

    /// A new file's text: the template in use for `kind`, filled for `title` and `date`, then each
    /// value set by key, then `bodyPrefix` (a line from the creation flow) after the `# ` heading.
    public static func make(_ kind: Kind, title: String, project: URL?, home: URL?,
                            values: [(String, Value)] = [], bodyPrefix: String? = nil, date: Date = Date()) -> String {
        render(text(kind, project: project, home: home).text, title: title, values: values, bodyPrefix: bodyPrefix, date: date)
    }

    /// `template` filled for `title` and `date`, with `values` set by key and `bodyPrefix` added.
    public static func render(_ template: String, title: String, values: [(String, Value)] = [],
                              bodyPrefix: String? = nil, date: Date = Date()) -> String {
        var out = fill(template, title: title, date: date)
        for (key, value) in values { out = setting(key, value, in: out) }
        if let bodyPrefix, !bodyPrefix.isEmpty { out = adding(bodyPrefix, in: out) }
        return out
    }

    /// Obsidian's placeholders filled. In the frontmatter a value holding one is re-written as a
    /// YAML scalar of the result, quoted only when YAML needs it, so `title: "{{title}}"` (quoted in
    /// the template so Obsidian reads the template's own properties) becomes `title: Draft PRD v2`.
    public static func fill(_ template: String, title: String, date: Date) -> String {
        let nl = template.contains("\r\n") ? "\r\n" : "\n"
        var lines = template.components(separatedBy: nl)
        var close = -1
        if lines.first == "---", let c = lines.dropFirst().firstIndex(of: "---") { close = c }
        for i in lines.indices {
            guard lines[i].contains("{{") else { continue }
            if i > 0, i < close, let r = lines[i].range(of: #"^(\s*- |\s*[^\s:#][^:]*:\s)"#, options: .regularExpression) {
                let prefix = String(lines[i][r])
                let raw = String(lines[i][r.upperBound...]).trimmingCharacters(in: .whitespaces)
                let inner = Frontmatter.unquote(raw)
                let filled = substitute(inner, title: title, date: date)
                lines[i] = filled == inner ? lines[i] : prefix + scalar(filled)
            } else {
                lines[i] = substitute(lines[i], title: title, date: date)
            }
        }
        return lines.joined(separator: nl)
    }

    /// The placeholders in one string replaced; anything else left as it is.
    static func substitute(_ s: String, title: String, date: Date) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}"#) else { return s }
        var out = "", last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s), let nameR = Range(m.range(at: 1), in: s) else { continue }
            out += s[last..<r.lowerBound]
            let format = Range(m.range(at: 2), in: s).map { String(s[$0]).trimmingCharacters(in: .whitespaces) }
            switch s[nameR] {
            case "title": out += title
            case "date": out += formatted(date, moment: format?.isEmpty == false ? format! : "YYYY-MM-DD")
            default: out += formatted(date, moment: format?.isEmpty == false ? format! : "HH:mm")
            }
            last = r.upperBound
        }
        return out + s[last...]
    }

    /// A date in a Moment.js format (the one Obsidian's Templates plugin takes).
    public static func formatted(_ date: Date, moment: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = dateFormat(fromMoment: moment)
        return f.string(from: date)
    }

    /// Moment tokens as `DateFormatter` ones; `[text]` is literal; other letters are quoted literals.
    static func dateFormat(fromMoment m: String) -> String {
        let tokens: [(String, String)] = [
            ("YYYY", "yyyy"), ("YY", "yy"), ("MMMM", "MMMM"), ("MMM", "MMM"), ("MM", "MM"), ("M", "M"),
            ("dddd", "EEEE"), ("ddd", "EEE"), ("Do", "d"), ("DD", "dd"), ("D", "d"),
            ("HH", "HH"), ("H", "H"), ("hh", "hh"), ("h", "h"), ("mm", "mm"), ("m", "m"),
            ("ss", "ss"), ("s", "s"), ("A", "a"), ("a", "a"), ("ZZ", "xx"), ("Z", "xxx"),
        ]
        var out = "", i = m.startIndex
        func literal(_ s: Substring) { out += "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
        while i < m.endIndex {
            if m[i] == "[", let end = m[i...].firstIndex(of: "]") {
                literal(m[m.index(after: i)..<end]); i = m.index(after: end); continue
            }
            if let (t, f) = tokens.first(where: { m[i...].hasPrefix($0.0) }) {
                out += f; i = m.index(i, offsetBy: t.count); continue
            }
            if m[i].isLetter { literal(m[i...i]) } else { out.append(m[i]) }
            i = m.index(after: i)
        }
        return out
    }

    /// A one-line YAML scalar, plain unless YAML needs quotes (research doc §4.8 rule 5), so a value
    /// reads the way Obsidian's own Properties panel writes it.
    public static func scalar(_ value: String) -> String {
        let v = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        if v.isEmpty { return "\"\"" }
        let first = v.first!
        let needs = "[]{},&*!|>%@`#'\"?:".contains(first) || v == "-" || v.hasPrefix("- ")
            || first == " " || v.last == " "
            || v.contains(": ") || v.contains(" #") || v.hasSuffix(":")
            || ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(v.lowercased())
            || Double(v) != nil
        if !needs { return v }
        return "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The text with one frontmatter key set: its line (and any list items under it) replaced in
    /// place, or added at the end of the block. Nothing else changes.
    public static func setting(_ key: String, _ value: Value, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        let new: [String]
        switch value {
        case .scalar(let s): new = [s.isEmpty ? "\(key):" : "\(key): \(scalar(s))"]
        case .list(let items): new = items.isEmpty ? ["\(key): []"] : ["\(key):"] + items.map { "  - \(scalar($0))" }
        }
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else {
            return (["---"] + new + ["---"] + lines).joined(separator: nl)
        }
        if let k = (1..<close).first(where: { lines[$0].hasPrefix("\(key):") }) {
            var end = k + 1
            while end < close, lines[end].hasPrefix(" ") || lines[end].hasPrefix("- ") { end += 1 }
            lines.replaceSubrange(k..<end, with: new)
        } else {
            lines.insert(contentsOf: new, at: close)
        }
        return lines.joined(separator: nl)
    }

    /// `line` added to the body: after the first `# ` heading and its blank line, else at the top.
    static func adding(_ line: String, in text: String) -> String {
        let nl = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: nl)
        var start = 0
        if lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") { start = close + 1 }
        if let h = lines[start...].firstIndex(where: { $0.hasPrefix("# ") }) {
            lines.insert(contentsOf: ["", line], at: h + 1)
        } else {
            lines.insert(contentsOf: [line, ""], at: min(start + (start < lines.count && lines[start].isEmpty ? 1 : 0), lines.count))
        }
        return lines.joined(separator: nl)
    }
}
