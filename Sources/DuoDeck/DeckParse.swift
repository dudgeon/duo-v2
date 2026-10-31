import DuoControl
import DuoSearch
import Foundation

/// Duo Decks (DL-267, DL-268): a deck is one Markdown file, a template pack is a pptx plus a
/// definition note. This file reads both. Behaviour follows
/// `docs/design/duo-decks-study/prototypes/compile/deck.py`, plus an anchor map: the source line
/// range of every slide and slot, so a check or an edit can point at the exact lines.
public enum Deck {
    public struct Problem: Equatable, Sendable {
        public var line: Int
        public var message: String
        public init(line: Int, message: String) { self.line = line; self.message = message }
    }

    /// One slot's text as written: the heading's line, the last line it covers, and the lines
    /// (blank lines dropped, indentation kept).
    public struct Slot: Equatable, Sendable {
        public var name: String
        public var line: Int
        public var lastLine: Int
        public var lines: [String]
        /// Review marks (comments, highlights, suggestions) whose lines fall inside this slot.
        public var marks: [Mark] = []
        /// The slot's body as written in the file, comments and highlight markers included (what a
        /// template change carries over, DL-284): from the line after its `##` heading (the first
        /// text line for unheaded text) to the last line before the next heading, note or slide,
        /// with blank lines and `---` trimmed from both ends.
        public var raw: [String] = []
        /// The last source line of that body (the heading's line when it is empty).
        public var blockEnd: Int = 0
        public init(name: String, line: Int, lastLine: Int, lines: [String], marks: [Mark] = [], raw: [String] = [], blockEnd: Int = 0) {
            self.name = name; self.line = line; self.lastLine = lastLine; self.lines = lines; self.marks = marks; self.raw = raw; self.blockEnd = blockEnd
        }
    }

    /// A Review in Markdown mark (DL-236) found in the deck, with its source lines. The marks are
    /// not content: checks and export see the text without them.
    public struct Mark: Equatable, Sendable {
        /// comment, highlight, insertion, deletion or substitution.
        public var kind: String
        public var line: Int
        public var lastLine: Int
        /// The first comment's text, or the note on a suggestion.
        public var text: String
    }

    public struct Slide: Equatable, Sendable {
        public var template: String
        /// The `<!-- slide: -->` line, and the last line of content before the next slide.
        public var line: Int
        public var lastLine: Int
        public var slots: [Slot] = []
        public var notes: [String] = []
        public var notesLine: Int?
        /// Marks that belong to the slide itself: on the line after its marker, or outside any slot.
        public var marks: [Mark] = []
        public func slot(_ name: String) -> Slot? { slots.first { $0.name == name } }
        public init(template: String, line: Int, lastLine: Int, slots: [Slot] = [], notes: [String] = [], notesLine: Int? = nil, marks: [Mark] = []) {
            self.template = template; self.line = line; self.lastLine = lastLine; self.slots = slots; self.notes = notes; self.notesLine = notesLine; self.marks = marks
        }
    }

    public struct Parsed: Sendable {
        public var front: [String: String]
        public var slides: [Slide]
        public var problems: [Problem]
    }

    public struct SlotSpec: Equatable, Sendable {
        public var name: String
        public var idx: Int
        public var kind: String
        public var max: Int?
        public var items: Int?
        public var levels: Int?
        public var rows: Int?
        public var cols: Int?
        public var aspect: Double?
        public var isDefault: Bool
    }

    public struct Template: Equatable, Sendable {
        public var name: String
        public var purpose: String
        public var layout: String
        public var fingerprint: String
        public var slots: [SlotSpec]
        /// A pack's own carry-over for changing to this template (DL-285): `from: {bullets: {body: left}}`
        /// in its yaml block means "from `bullets`, the `body` slot goes to `left`". Wins over Duo's rules.
        public var overrides: [String: [String: String]] = [:]
        public func slot(_ n: String) -> SlotSpec? { slots.first { $0.name == n } }
        public var defaultSlot: SlotSpec? { slots.first(where: \.isDefault) }
    }

    public struct Pack: Sendable {
        public var name: String
        public var md: URL
        public var front: [String: String]
        public var templates: [Template]
        public var pptx: URL { md.deletingLastPathComponent().appending(path: front["pptx"] ?? "\(name).pptx") }
        public func template(_ n: String) -> Template? { templates.first { $0.name == n } }
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    // MARK: the deck

    /// Flat `key: value` frontmatter between the first two `---` lines. Returns the values and the
    /// 0-based index of the closing `---`.
    static func frontmatter(_ lines: [String]) -> ([String: String], Int)? {
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var out: [String: String] = [:]
        for l in lines[1..<end] {
            guard let c = l.firstIndex(of: ":"), !l.hasPrefix("#") else { continue }
            var v = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
            if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
            out[String(l[..<c]).trimmingCharacters(in: .whitespaces)] = v
        }
        return (out, end)
    }

    static func isName(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    static func slideMark(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<!--"), t.hasSuffix("-->"), t.count >= 7 else { return nil }
        let inner = t.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespaces)
        guard inner.hasPrefix("slide:") else { return nil }
        let name = inner.dropFirst(6).trimmingCharacters(in: .whitespaces)
        return isName(name) ? name : nil
    }

    static func slotHeading(_ line: String) -> String? {
        guard line.hasPrefix("## ") else { return nil }
        let n = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return isName(n) ? n : nil
    }

    public static func imageLine(_ line: String) -> (alt: String, path: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("!["), let close = t.range(of: "]("), t.hasSuffix(")") else { return nil }
        let alt = String(t[t.index(t.startIndex, offsetBy: 2)..<close.lowerBound])
        let path = String(t[close.upperBound..<t.index(before: t.endIndex)])
        return path.isEmpty || path.contains(where: \.isWhitespace) ? nil : (alt, path)
    }

    /// Takes the Review marks out of `text` (DuoControl's `Review` finds them): comments and
    /// highlight markers vanish, a highlight keeps its text, and a pending suggestion reads as the
    /// text before the change (`{++x++}` nothing, `{--x--}` x, `{~~a~>b~~}` a). Newlines inside a
    /// mark stay, so line numbers don't move. `record` hears each top-level mark with its lines.
    static func stripReview(_ text: String, record: ((Mark) -> Void)?) -> String {
        let parsed = Review.parse(text)
        if parsed.isEmpty { return text }
        let ns = text as NSString
        struct Edit { var range: NSRange; var with: String; var mark: Mark? }
        func nl(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } }
        func line(_ loc: Int) -> Int { nl(ns.substring(to: loc)) + 1 }
        func mark(_ kind: String, _ r: NSRange, _ t: String) -> Mark? {
            record == nil ? nil : Mark(kind: kind, line: line(r.location), lastLine: line(max(r.location, NSMaxRange(r) - 1)), text: t)
        }
        var edits: [Edit] = []
        for s in parsed.suggestions {
            let old = s.kind == .insertion ? "" : s.old
            let pad = String(repeating: "\n", count: max(0, nl(ns.substring(with: s.range)) - nl(old)))
            edits.append(Edit(range: s.range, with: old + pad, mark: mark(s.kind.rawValue, s.range, s.note)))
        }
        for t in parsed.threads {
            let sub = NSMutableString(string: ns.substring(with: t.range))
            let cut = (t.comments.map(\.range) + t.pieces.flatMap { [$0.open, $0.close] }).sorted { $0.location > $1.location }
            for r in cut { sub.replaceCharacters(in: NSRange(location: r.location - t.range.location, length: r.length), with: "") }
            let lost = nl(ns.substring(with: t.range)) - nl(sub as String)
            let inner = stripReview(sub as String, record: nil) + String(repeating: "\n", count: max(0, lost))
            edits.append(Edit(range: t.range, with: inner, mark: mark(t.anchor == nil ? "comment" : "highlight", t.range, t.root?.text ?? "")))
        }
        edits.sort { ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length) }
        var top: [Edit] = []
        for e in edits where top.last.map({ NSMaxRange($0.range) <= e.range.location }) ?? true { top.append(e) }
        let out = NSMutableString(string: text)
        for e in top.reversed() { out.replaceCharacters(in: e.range, with: e.with) }
        for e in top { if let m = e.mark { record?(m) } }
        return out as String
    }

    public static func parse(_ source: String) -> Parsed {
        var marks: [Mark] = []
        let text = stripReview(source) { marks.append($0) }.components(separatedBy: "\n")
            .map { l in String(l.reversed().drop { $0 == " " || $0 == "\t" }.reversed()) }.joined(separator: "\n")
        let lines = text.components(separatedBy: "\n")
        guard let (front, end) = frontmatter(lines) else {
            return Parsed(front: [:], slides: [], problems: [Problem(line: 1, message: "a deck starts with frontmatter holding type: deck")])
        }
        var slides: [Slide] = []
        var problems: [Problem] = []
        var slot: String?   // current slot name; "_notes" while in a note
        var cur: Int?       // index into slides
        for (i, line) in lines.enumerated() where i > end {
            let n = i + 1
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if let t = slideMark(line) {
                slides.append(Slide(template: t, line: n, lastLine: n))
                cur = slides.count - 1
                slot = nil
                continue
            }
            guard let c = cur else {
                if !blank, line.trimmingCharacters(in: .whitespaces) != "---" {
                    problems.append(Problem(line: n, message: "text before the first slide marker; start each slide with <!-- slide: name -->"))
                }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "---" { continue }
            if line.hasPrefix("# ") || line == "#", slides[c].slot("title") == nil {
                slides[c].slots.append(Slot(name: "title", line: n, lastLine: n, lines: [String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)]))
                slot = nil; slides[c].lastLine = n
                continue
            }
            if let name = slotHeading(line) {
                slot = name
                slides[c].slots.removeAll { $0.name == name }
                slides[c].slots.append(Slot(name: name, line: n, lastLine: n, lines: []))
                slides[c].lastLine = n
                continue
            }
            if line.hasPrefix("> [!note]") {
                slot = "_notes"
                if slides[c].notesLine == nil { slides[c].notesLine = n }
                slides[c].lastLine = n
                continue
            }
            if slot == "_notes", line.hasPrefix(">") {
                slides[c].notes.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)); slides[c].lastLine = n
                continue
            }
            if blank {
                if slot == "_notes" { slot = nil }
                continue
            }
            let key = slot ?? (imageLine(line) != nil ? "_image" : "_default")
            if let k = slides[c].slots.firstIndex(where: { $0.name == key }) {
                slides[c].slots[k].lines.append(line); slides[c].slots[k].lastLine = n
            } else {
                slides[c].slots.append(Slot(name: key, line: n, lastLine: n, lines: [line]))
            }
            slides[c].lastLine = n
        }
        // Each slot's body as written (comments kept): see Slot.raw.
        let original = source.components(separatedBy: "\n")
        for (si, slide) in slides.enumerated() {
            let end = (si + 1 < slides.count ? slides[si + 1].line : lines.count + 1)   // exclusive, 1-based
            let starts = Set(slide.slots.map(\.line) + [slide.notesLine].compactMap { $0 })
            for (k, sl) in slide.slots.enumerated() {
                if sl.name == "title" { slides[si].slots[k].raw = sl.lines; slides[si].slots[k].blockEnd = sl.line; continue }
                let next = starts.filter { $0 > sl.line }.min() ?? end
                let headed = sl.name != "_default" && sl.name != "_image"
                var lo = headed ? sl.line + 1 : sl.line, hi = min(next, end) - 1
                func skip(_ i: Int) -> Bool { let t = original[i - 1].trimmingCharacters(in: .whitespaces); return t.isEmpty || t == "---" }
                while lo <= hi, skip(lo) { lo += 1 }
                while hi >= lo, skip(hi) { hi -= 1 }
                slides[si].slots[k].raw = lo <= hi ? Array(original[(lo - 1)...(hi - 1)]) : []
                slides[si].slots[k].blockEnd = max(hi, sl.line)
            }
        }
        // The anchor map for marks: a slot when the mark sits inside its lines, else the slide.
        // A comment alone on the line after the slide marker is the slide's.
        for m in marks {
            guard let n = slides.lastIndex(where: { $0.line <= m.line }) else { continue }
            let own = m.line == slides[n].line + 1 && lines[m.line - 1].trimmingCharacters(in: .whitespaces).isEmpty
            if !own, let k = slides[n].slots.firstIndex(where: { $0.line <= m.line && m.lastLine <= $0.lastLine }) {
                slides[n].slots[k].marks.append(m)
            } else {
                slides[n].marks.append(m)
            }
        }
        return Parsed(front: front, slides: slides, problems: problems)
    }

    // MARK: the pack

    static func scalar(_ s: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let i = Int(t) { return i }
        if let d = Double(t) { return d }
        if t == "true" { return true }
        if t == "false" { return false }
        return t
    }

    /// The small YAML subset a template note uses: `key: value`, comments after ` #`, and under
    /// `slots:` indented `name: {k: v, …}` flow maps.
    static func yaml(_ block: [String]) -> (top: [String: String], slots: [(String, [String: Any])]) {
        var top: [String: String] = [:]
        var slots: [(String, [String: Any])] = []
        var inSlots = false
        for raw in block {
            var l = raw
            if let r = l.range(of: " #") { l = String(l[..<r.lowerBound]) }
            if l.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indented = l.hasPrefix(" ") || l.hasPrefix("\t")
            guard let c = l.firstIndex(of: ":") else { continue }
            let key = String(l[..<c]).trimmingCharacters(in: .whitespaces)
            let val = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            if !indented {
                inSlots = key == "slots"
                if !inSlots { top[key] = val }
            } else if inSlots, val.hasPrefix("{"), val.hasSuffix("}") {
                var map: [String: Any] = [:]
                for part in val.dropFirst().dropLast().split(separator: ",") {
                    guard let cc = part.firstIndex(of: ":") else { continue }
                    map[part[..<cc].trimmingCharacters(in: .whitespaces)] = scalar(String(part[part.index(after: cc)...]))
                }
                slots.append((key, map))
            }
        }
        return (top, slots)
    }

    /// `{bullets: {body: left}, kpi: {context: left}}`: nested flow maps of plain words.
    static func overrides(_ text: String?) -> [String: [String: String]] {
        guard let text, text.hasPrefix("{"), text.hasSuffix("}") else { return [:] }
        var out: [String: [String: String]] = [:]
        var depth = 0, token = "", key = "", outer = ""
        func word(_ t: String) -> String { t.trimmingCharacters(in: .whitespaces) }
        func store() { if !word(key).isEmpty, !word(token).isEmpty { out[outer, default: [:]][word(key)] = word(token) }; key = ""; token = "" }
        for ch in text.dropFirst().dropLast() {
            switch (ch, depth) {
            case ("{", 0): depth = 1; token = ""; key = ""
            case ("}", 1): store(); depth = 0
            case (":", 0): outer = word(token); token = ""
            case (":", 1): key = token; token = ""
            case (",", 1): store()
            case (",", 0): token = ""
            default: token.append(ch)
            }
        }
        return out
    }

    public static func loadPack(_ name: String, in dirs: [URL]) throws -> Pack {
        guard let md = dirs.map({ $0.appending(path: name).appending(path: "\(name).md") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Failure(description: "no template pack \"\(name)\" in \(dirs.map(\.path).joined(separator: ", "))")
        }
        let lines = try String(contentsOf: md, encoding: .utf8).components(separatedBy: "\n")
        guard let (front, end) = frontmatter(lines) else { throw Failure(description: "\(md.lastPathComponent): no frontmatter") }
        var templates: [Template] = []
        var i = end + 1
        while i < lines.count {
            guard lines[i].hasPrefix("## ") else { i += 1; continue }
            let name = lines[i].dropFirst(3).trimmingCharacters(in: .whitespaces)
            var purpose: [String] = []
            i += 1
            while i < lines.count, !lines[i].hasPrefix("```"), !lines[i].hasPrefix("## ") { purpose.append(lines[i]); i += 1 }
            guard i < lines.count, lines[i].hasPrefix("```yaml") else { continue }
            i += 1
            var block: [String] = []
            while i < lines.count, !lines[i].hasPrefix("```") { block.append(lines[i]); i += 1 }
            let y = yaml(block)
            let specs = y.slots.map { n, m -> SlotSpec in
                SlotSpec(name: n, idx: m["idx"] as? Int ?? 0, kind: m["kind"] as? String ?? "text", max: m["max"] as? Int,
                         items: m["items"] as? Int, levels: m["levels"] as? Int, rows: m["rows"] as? Int, cols: m["cols"] as? Int,
                         aspect: (m["aspect"] as? Double) ?? (m["aspect"] as? Int).map(Double.init), isDefault: m["default"] as? Bool ?? false)
            }
            var tpl = Template(name: name, purpose: purpose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                               layout: y.top["layout"] ?? "", fingerprint: y.top["fingerprint"] ?? "", slots: specs)
            tpl.overrides = overrides(y.top["from"])
            templates.append(tpl)
        }
        return Pack(name: name, md: md, front: front, templates: templates)
    }
}
