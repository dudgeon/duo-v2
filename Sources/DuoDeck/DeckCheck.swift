import Foundation

extension Deck {
    public struct Checked: Sendable {
        public var parsed: Parsed
        public var pack: Pack?
        /// Slides with unheaded text and lone images moved into their slots.
        public var slides: [Slide]
        public var problems: [Problem]
    }

    /// Checks a deck against its template pack: the prototype's messages, one per problem, each
    /// naming the line and the fix. Problems are sorted by line.
    public static func check(deck: URL, packDirs: [URL]) throws -> Checked {
        let parsed = parse(try String(contentsOf: deck, encoding: .utf8))
        var problems = parsed.problems
        if parsed.front.isEmpty && parsed.slides.isEmpty { return Checked(parsed: parsed, pack: nil, slides: [], problems: problems) }
        if parsed.front["type"] != "deck" { problems.append(Problem(line: 2, message: "frontmatter needs type: deck")) }
        let pack = try loadPack(parsed.front["template"] ?? "", in: packDirs)
        var slides = parsed.slides
        for (n, s0) in parsed.slides.enumerated() {
            var s = s0
            let where_ = "slide \(n + 1) (\(s.template))"
            guard let t = pack.template(s.template) else {
                problems.append(Problem(line: s.line, message: "\(where_): no template \"\(s.template)\" in \(pack.md.lastPathComponent); use one of \(pack.templates.map(\.name).joined(separator: ", "))"))
                continue
            }
            if let d = s.slot("_default") {
                if let def = t.slots.first(where: \.isDefault) {
                    if s.slot(def.name) != nil {
                        problems.append(Problem(line: d.line, message: "\(where_): text with no slot heading, but \"## \(def.name)\" is also given"))
                    } else {
                        s.slots = s.slots.map { var x = $0; if x.name == "_default" { x.name = def.name }; return x }
                    }
                } else {
                    problems.append(Problem(line: d.line, message: "\(where_): text with no slot heading, and \(s.template) has no default slot"))
                }
            }
            if let img = s.slot("_image") {
                let pics = t.slots.filter { $0.kind == "image" }
                if pics.count == 1, s.slot(pics[0].name) == nil {
                    s.slots = s.slots.map { var x = $0; if x.name == "_image" { x.name = pics[0].name }; return x }
                } else {
                    s.slots.removeAll { $0.name == "_image" }
                    problems.append(Problem(line: img.line, message: "\(where_): an image with no slot heading; \(s.template) has no single image slot to put it in"))
                }
            }
            s.slots.removeAll { $0.name == "_default" && t.slots.first(where: \.isDefault) == nil }
            for got in s.slots where got.name != "_default" {
                guard let spec = t.slot(got.name) else {
                    problems.append(Problem(line: got.line, message: "\(where_): no slot \"\(got.name)\"; \(s.template) has \(t.slots.map(\.name).joined(separator: ", "))"))
                    continue
                }
                for m in checkSlot(spec, got.lines, deck: deck) { problems.append(Problem(line: got.line, message: "\(where_), \(got.name): \(m)")) }
            }
            slides[n] = s
        }
        problems.sort { ($0.line, $0.message) < ($1.line, $1.message) }
        return Checked(parsed: parsed, pack: pack, slides: slides, problems: problems)
    }

    static func bulletIndent(_ l: String) -> Int { l.prefix { $0 == " " }.count }
    static func isBullet(_ l: String) -> Bool {
        let t = l.drop { $0 == " " }
        return t.hasPrefix("- ") || t.hasPrefix("* ")
    }
    static func isSeparatorRow(_ l: String) -> Bool { l.hasPrefix("|") && l.hasSuffix("|") && l.allSatisfy { "|-: ".contains($0) } }

    static func checkSlot(_ spec: SlotSpec, _ lines: [String], deck: URL) -> [String] {
        var out: [String] = []
        switch spec.kind {
        case "text", "number":
            let text = lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            if lines.contains(where: { let t = $0.drop { $0 == " " }; return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("|") || t.hasPrefix("![") }) {
                out.append("is a \(spec.kind) slot; write a sentence, not a list, table or image")
            }
            let n = text.unicodeScalars.count
            if let m = spec.max, n > m { out.append("is \(n) characters; the template allows \(m). Shorten it, or split the slide") }
        case "bullets":
            let items = lines.filter(isBullet)
            if items.count != lines.count { out.append("takes a list: one \"- \" line per point") }
            let top = items.filter { bulletIndent($0) == 0 }
            if let m = spec.items, top.count > m { out.append("has \(top.count) points; the template allows \(m). Split the slide; never shrink the text") }
            let levels = spec.levels ?? 1
            if items.contains(where: { bulletIndent($0) >= 2 * levels }) { out.append("nests deeper than \(levels) levels") }
            if let m = spec.max {
                for l in items where l.trimmingCharacters(in: .whitespaces).unicodeScalars.count - 2 > m {
                    out.append("a point is \(l.trimmingCharacters(in: .whitespaces).unicodeScalars.count - 2) characters; the template allows \(m)")
                }
            }
        case "image":
            if lines.count == 1, let img = imageLine(lines[0]) {
                if !FileManager.default.fileExists(atPath: deck.deletingLastPathComponent().appending(path: img.path).path) {
                    out.append("no file \(img.path) next to the deck")
                }
            } else {
                out.append("takes one image: ![alt](path)")
            }
        case "table":
            let rows = lines.filter { $0.hasPrefix("|") && !isSeparatorRow($0) }
            if rows.count != lines.count - 1 { out.append("takes one Markdown table, a header row first") }
            if let m = spec.rows, rows.count > m { out.append("has \(rows.count) rows; the template allows \(m)") }
        default: break
        }
        return out
    }

    /// `file:line: message`, one per problem, then the count.
    public static func report(_ deckPath: String, _ problems: [Problem]) -> String {
        problems.map { "\(deckPath):\($0.line): \($0.message)" }.joined(separator: "\n")
            + (problems.isEmpty ? "no problems" : "\n\(problems.count) problem\(problems.count == 1 ? "" : "s")")
    }
}
