import Foundation

/// What Send to Claude types into a session's prompt (DL-67, DL-68): always inline, a short
/// provenance line and then the context, quoted. Hardened like legacy's `sendFormat.ts` (LR-17):
/// control characters can't reach the terminal (an ESC could end the bracketed paste and run the
/// rest as keystrokes), single-line fields lose their line breaks, fences outgrow any backtick run
/// inside, and the whole payload is capped.
public enum SendFormat {
    public static let cap = 6000

    /// A document selection: `From docs/prd.md, lines 12–14:` and the text, quoted.
    public static func documentSelection(_ text: String, path: String, fromLine: Int, toLine: Int) -> String {
        let lines = fromLine == toLine ? "line \(fromLine)" : "lines \(fromLine)–\(toLine)"
        return finish("From \(line(path)), \(lines):\n" + quote(text))
    }

    /// A file or folder: an @-reference Claude Code resolves (relative inside the session's folder).
    public static func file(_ path: String) -> String {
        let p = line(path)
        return (p.contains(" ") ? "@\"\(p)\"" : "@" + p) + " "
    }

    public struct SessionInfo: Sendable {
        public var title, project, id: String
        public var transcript: String?
        public var note, next: String?
        public init(title: String, project: String, id: String, transcript: String?, note: String? = nil, next: String? = nil) {
            self.title = title; self.project = project; self.id = id; self.transcript = transcript; self.note = note; self.next = next
        }
    }

    public static func session(_ s: SessionInfo) -> String {
        var out = "Duo session \"\(line(s.title))\" in project \(line(s.project)) (id \(s.id))."
        if let n = s.note, !n.isEmpty { out += "\nIts note: \(line(n))" }
        if let n = s.next, !n.isEmpty { out += "\nIts next step: \(line(n))" }
        out += "\nRead it with `duo2 session show \(s.id)`"
        if let t = s.transcript { out += ", or its transcript at \(line(t))" }
        return finish(out + ".")
    }

    public struct ProjectInfo: Sendable {
        public var name, folder: String
        public var projectFile: String?
        public var goal, health, next: String?
        public var isFolderOnly: Bool
        public init(name: String, folder: String, projectFile: String?, goal: String?, health: String?, next: String?, isFolderOnly: Bool) {
            self.name = name; self.folder = folder; self.projectFile = projectFile; self.goal = goal; self.health = health
            self.next = next; self.isFolderOnly = isFolderOnly
        }
    }

    public static func project(_ p: ProjectInfo) -> String {
        var out = p.isFolderOnly
            ? "Folder \(line(p.folder)) (Claude sessions, no project file)."
            : "Duo project \"\(line(p.name))\" at \(line(p.folder))."
        if let f = p.projectFile { out += "\nProject file: \(line(f))" }
        let facts = [p.goal.map { "goal: \(line($0))" }, p.health.map { "health: \(line($0))" }, p.next.map { "next: \(line($0))" }]
            .compactMap { $0 }.filter { !$0.hasSuffix(": ") }
        if !facts.isEmpty { out += "\n" + facts.joined(separator: " · ") }
        out += "\nIts sessions: `duo2 sessions --project \(shellWord(p.name))`."
        return finish(out)
    }

    /// Text (and any images) selected in an HTML page.
    public static func htmlSelection(_ text: String, path: String, title: String?, images: [(src: String, alt: String)]) -> String {
        var out = "From \(line(path))\(title.map { " (\"\(line($0))\")" } ?? ""), selected:\n"
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out += quote(text) }
        for i in images { out += "\nimage: \(line(i.src))" + (i.alt.isEmpty ? "" : " (alt \"\(line(i.alt))\")") }
        return finish(out)
    }

    /// An element picked in an HTML page (LR-44's payload, plus the screenshot as a file).
    public struct Element: Codable, Sendable {
        public var tag: String
        public var label: String          // tag#id.class.class
        public var selector: String
        public var trail: [String]        // headings above it, outermost first
        public var text: String
        public var attributes: [String: String]
        public var styles: [String: String]
        public var rect: [Double]         // x, y, width, height in page points
        public var html: String
        public var url: String
        public var title: String

        public init(tag: String, label: String, selector: String, trail: [String], text: String, attributes: [String: String],
                    styles: [String: String], rect: [Double], html: String, url: String, title: String) {
            self.tag = tag; self.label = label; self.selector = selector; self.trail = trail; self.text = text
            self.attributes = attributes; self.styles = styles; self.rect = rect; self.html = html; self.url = url; self.title = title
        }
    }

    public static func element(_ e: Element, path: String, screenshot: String?) -> String {
        var out = "From \(line(path))\(e.title.isEmpty ? "" : " (\"\(line(e.title))\")"), the element <\(line(e.label))>:"
        out += "\nselector: \(line(e.selector))"
        if !e.trail.isEmpty { out += "\nunder: " + e.trail.map(line).joined(separator: " › ") }
        let text = line(e.text)
        if !text.isEmpty { out += "\ntext: \"\(text.count > 300 ? String(text.prefix(300)) + "…" : text)\"" }
        if !e.attributes.isEmpty {
            out += "\nattributes: " + e.attributes.sorted { $0.key < $1.key }.map { "\(line($0.key))=\"\(line($0.value))\"" }.joined(separator: " ")
        }
        if e.rect.count == 4 { out += "\nbox: \(Int(e.rect[2]))×\(Int(e.rect[3])) at (\(Int(e.rect[0])), \(Int(e.rect[1])))" }
        if !e.styles.isEmpty { out += "\nstyles: " + e.styles.sorted { $0.key < $1.key }.map { "\(line($0.key)): \(line($0.value))" }.joined(separator: "; ") }
        if let s = screenshot { out += "\nscreenshot: \(line(s))" }
        let html = clean(e.html)
        out += "\nhtml:\n" + fenced(html.count > 3000 ? String(html.prefix(3000)) + "\n…" : html, lang: "html")
        return finish(out)
    }

    /// A shape picked on a slide (ENH-12, DL-125 board D).
    public struct Shape: Codable, Equatable, Sendable {
        public var slide, count, id: Int
        public var name, type: String
        public var groups: [String]
        public var text: String
        /// x, y, width, height in slide pixels (96 per inch).
        public var box: [Int]
        public var slideSize: [Int]

        public init(slide: Int, count: Int, id: Int, name: String, type: String, groups: [String], text: String, box: [Int], slideSize: [Int]) {
            self.slide = slide; self.count = count; self.id = id; self.name = name; self.type = type
            self.groups = groups; self.text = text; self.box = box; self.slideSize = slideSize
        }
    }

    /// What Claude gets for a picked shape: where it is, what it is, the command for the whole
    /// slide, and a picture (pptx-handoff `pptx-sent`).
    public static func shape(_ s: Shape, path: String, screenshot: String?) -> String {
        var out = "From \(line(path)), slide \(s.slide)\(s.count > 0 ? " of \(s.count)" : ""), the shape \"\(line(s.name))\" (id \(s.id)):"
        out += "\ntype: \(line(s.type))" + (s.groups.isEmpty ? "" : " · in groups: " + s.groups.map(line).joined(separator: " › "))
        let text = line(s.text)
        if !text.isEmpty { out += "\ntext: \"\(text.count > 300 ? String(text.prefix(300)) + "…" : text)\"" }
        if s.box.count == 4 {
            out += "\nbox: \(s.box[2])×\(s.box[3]) at (\(s.box[0]), \(s.box[1]))" + (s.slideSize.count == 2 ? " on a \(s.slideSize[0])×\(s.slideSize[1]) slide" : "")
        }
        out += "\nthe whole slide: duo2 slide shapes \(quoted(path)) \(s.slide)"
        if let shot = screenshot { out += "\nscreenshot: \(line(shot))" }
        return finish(out)
    }

    /// A path as the board writes it in a command: bare when it's plain, else in double quotes.
    static func quoted(_ s: String) -> String {
        let l = line(s)
        if l.allSatisfy({ $0.isLetter || $0.isNumber || "-_./~".contains($0) }) { return l }
        return "\"" + l.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`") + "\""
    }

    // MARK: Hardening

    /// No control characters but newline and tab; CRLF becomes LF.
    public static func clean(_ s: String) -> String {
        String(String.UnicodeScalarView(s.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars.filter { u in
            u == "\n" || u == "\t" || !(u.value < 0x20 || u.value == 0x7f || (0x80...0x9f).contains(u.value))
        }))
    }

    /// A single-line field: no line breaks of any kind.
    public static func line(_ s: String) -> String {
        clean(s).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ").replacingOccurrences(of: "\u{2029}", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func quote(_ text: String) -> String {
        clean(text).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
    }

    static func fenced(_ text: String, lang: String) -> String {
        var longest = 0, run = 0
        for c in text { if c == "`" { run += 1; longest = max(longest, run) } else { run = 0 } }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return "\(fence)\(lang)\n\(text)\n\(fence)"
    }

    static func shellWord(_ s: String) -> String {
        s.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Caps the payload and ends it on a new line, ready for the request to be typed after it.
    static func finish(_ s: String) -> String {
        let body = clean(s)
        let capped = body.count > cap ? String(body.prefix(cap)) + "\n[… cut at \(cap) characters]" : body
        return capped + "\n"
    }
}
