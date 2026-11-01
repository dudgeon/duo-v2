import Foundation

/// The plan Claude writes for `duo2 deck import --plan` (lifecycle M3b, DL-294), and the survey it
/// plans from. The plan is a small YAML file:
///
///     groups:
///       - slides: 1
///         template: title
///       - slides: 3, 4, 5                 # or  group: G2  (an id from the survey)
///         template: kpi
///         map: {Footnote: footnote}       # loose box (by name on the slide) -> slot; optional
///         amend:                          # slots added to kpi, optional unless optional: false
///           footnote: {kind: text, max: 70, shape: Footnote, from-slide: 5}
///       - slides: 7
///         template: timeline
///         new:                            # a template the pack doesn't have yet
///           from-slide: 7                 # or  layout: <a layout of the pptx>
///           purpose: Steps along a line.
///           slots:
///             title: {kind: text, max: 60, shape: Title}
///             step: {kind: text, max: 40, shape: Step 1}
///
/// Loose boxes whose names the plan doesn't give are matched to the slots whose boxes are nearest.
public enum DeckImportPlan {
    // MARK: a YAML subset

    indirect enum Y {
        case s(String)
        case m([(String, Y)])
        case l([Y])

        subscript(_ k: String) -> Y? { if case .m(let kv) = self { return kv.first { $0.0 == k }?.1 }; return nil }
        var string: String? { if case .s(let v) = self { return v }; return nil }
        var map: [(String, Y)] { if case .m(let kv) = self { return kv }; return [] }
        var list: [Y] { if case .l(let v) = self { return v }; return [] }
    }

    struct Line { var indent: Int; var text: String; var number: Int }

    static func stripComment(_ s: String) -> String {
        var inQuote: Character?
        var prev: Character = " "
        for (i, c) in zip(s.indices, s) {
            if let q = inQuote { if c == q { inQuote = nil } }
            else if c == "\"" || c == "'" { inQuote = c }
            else if c == "#", prev == " " { return String(s[..<i]) }
            prev = c
        }
        return s
    }

    static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) { return String(t.dropFirst().dropLast()) }
        return t
    }

    static func splitTop(_ s: String) -> [String] {
        var out: [String] = [], cur = "", depth = 0
        for c in s {
            if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
            if c == ",", depth == 0 { out.append(cur); cur = "" } else { cur.append(c) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    static func keyValue(_ s: String) -> (String, String)? {
        // the first ":" followed by a space or the end of the line
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == ":" {
                let n = s.index(after: i)
                if n == s.endIndex || s[n] == " " { return (unquote(String(s[..<i])), String(s[n...]).trimmingCharacters(in: .whitespaces)) }
            }
            i = s.index(after: i)
        }
        return nil
    }

    static func flow(_ s: String) -> Y {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("{"), t.hasSuffix("}") else { return .s(unquote(t)) }
        var kv: [(String, Y)] = []
        for part in splitTop(String(t.dropFirst().dropLast())) {
            guard let (k, v) = keyValue(part.trimmingCharacters(in: .whitespaces)) else { continue }
            kv.append((k, flow(v)))
        }
        return .m(kv)
    }

    static func parseYAML(_ text: String) throws -> Y {
        var lines: [Line] = []
        for (i, raw) in text.components(separatedBy: "\n").enumerated() {
            let s = stripComment(raw)
            if s.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            lines.append(Line(indent: s.prefix { $0 == " " }.count, text: s.trimmingCharacters(in: .whitespaces), number: i + 1))
        }
        var pos = 0
        func block(_ indent: Int) throws -> Y {
            guard pos < lines.count else { return .m([]) }
            if lines[pos].text.hasPrefix("- ") || lines[pos].text == "-" {
                var items: [Y] = []
                while pos < lines.count, lines[pos].indent == indent, lines[pos].text.hasPrefix("-") {
                    let rest = String(lines[pos].text.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if rest.isEmpty { pos += 1; items.append(pos < lines.count && lines[pos].indent > indent ? try block(lines[pos].indent) : .s("")); continue }
                    if keyValue(rest) != nil, !rest.hasPrefix("{") {
                        lines[pos] = Line(indent: indent + 2, text: rest, number: lines[pos].number)
                        items.append(try block(indent + 2))
                    } else { items.append(flow(rest)); pos += 1 }
                }
                return .l(items)
            }
            var kv: [(String, Y)] = []
            while pos < lines.count, lines[pos].indent == indent {
                let l = lines[pos]
                guard let (k, v) = keyValue(l.text) else { throw Deck.Failure(description: "plan line \(l.number): expected \"name: value\", not \"\(l.text)\"") }
                pos += 1
                if v.isEmpty {
                    if pos < lines.count, lines[pos].indent > indent { kv.append((k, try block(lines[pos].indent))) } else { kv.append((k, .s(""))) }
                } else { kv.append((k, flow(v))) }
            }
            if pos < lines.count, lines[pos].indent > indent { throw Deck.Failure(description: "plan line \(lines[pos].number): indented more than the line above it") }
            return .m(kv)
        }
        let y = try block(lines.first?.indent ?? 0)
        if pos < lines.count { throw Deck.Failure(description: "plan line \(lines[pos].number): can't read this line") }
        return y
    }

    // MARK: the plan

    public struct NewTemplate: Equatable, Sendable {
        public var fromSlide: Int?
        public var layout: String?
        public var purpose: String?
        /// slot name -> its keys as written (kind, max, shape, …), in order.
        public var slots: [(name: String, keys: [(String, String)])]
        public static func == (a: Self, b: Self) -> Bool { a.fromSlide == b.fromSlide && a.layout == b.layout && a.purpose == b.purpose && a.slots.map(\.name) == b.slots.map(\.name) }
    }

    public struct Added: Sendable {
        public var slot: String
        public var keys: [(String, String)]
        public var fromSlide: Int?
        public var shape: String?
    }

    public struct Group: Sendable {
        public var slides: [Int]
        public var groupIDs: [String]
        public var template: String
        public var map: [String: String]
        public var amend: [Added]
        public var new: NewTemplate?
    }

    public struct Plan: Sendable {
        public var groups: [Group]
        public var pack: String?
    }

    static func ints(_ s: String) throws -> [Int] {
        var out: [Int] = []
        for part in s.split(separator: ",") {
            let ends = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard ends.count == 1 || ends.count == 2 else { throw Deck.Failure(description: "plan: slides: takes numbers like 3, 4, 5 or 3-5, not \"\(s)\"") }
            out += ends.count == 1 ? [ends[0]] : Array(ends[0]...max(ends[0], ends[1]))
        }
        return out
    }

    public static func parse(_ text: String) throws -> Plan {
        let y = try parseYAML(text)
        var groups: [Group] = []
        for g in (y["groups"]?.list ?? []) {
            guard let template = g["template"]?.string, !template.isEmpty else { throw Deck.Failure(description: "plan: every group needs template: <name>") }
            let ids = (g["group"]?.string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let slides = try ints(g["slides"]?.string ?? "")
            guard !slides.isEmpty || !ids.isEmpty else { throw Deck.Failure(description: "plan: the group for \(template) needs slides: or group:") }
            var map: [String: String] = [:]
            for (k, v) in g["map"]?.map ?? [] { if let s = v.string { map[k] = s } }
            var amend: [Added] = []
            for (name, v) in g["amend"]?.map ?? [] {
                let keys = v.map.compactMap { k, x in x.string.map { (k, $0) } }
                amend.append(Added(slot: name, keys: keys.filter { $0.0 != "from-slide" }, fromSlide: v["from-slide"]?.string.flatMap { Int($0) }, shape: v["shape"]?.string))
            }
            var new: NewTemplate?
            if let n = g["new"] {
                var slots: [(String, [(String, String)])] = []
                for (name, v) in n["slots"]?.map ?? [] { slots.append((name, v.map.compactMap { k, x in x.string.map { (k, $0) } })) }
                new = NewTemplate(fromSlide: n["from-slide"]?.string.flatMap { Int($0) }, layout: n["layout"]?.string, purpose: n["purpose"]?.string, slots: slots)
            }
            groups.append(Group(slides: slides, groupIDs: ids, template: template, map: map, amend: amend, new: new))
        }
        guard !groups.isEmpty else { throw Deck.Failure(description: "plan: no groups: the file needs a \"groups:\" list") }
        return Plan(groups: groups, pack: y["pack"]?.string)
    }

    // MARK: the survey (no plan)

    public struct Candidate: Codable, Equatable, Sendable {
        public var template: String
        /// exact, optional (the group has all the template's required slots), extra, or loose.
        public var how: String
        public init(template: String, how: String) { self.template = template; self.how = how }
    }

    public struct SurveyGroup: Codable, Equatable, Sendable {
        public var id: String
        public var slides: [Int]
        public var fingerprint: String
        public var layout: String
        public var loose: Bool
        public var best: Candidate?
        public var others: [Candidate]
    }

    public struct Survey: Codable, Equatable, Sendable {
        public var file: String
        public var slides: Int
        public var pack: String?
        public var groups: [SurveyGroup]
        public var near: [TemplateInventory.Near]
        public var fonts: [String]
        public var comments: Int
    }

    /// The slide groups of a pptx, each with the pack template that fits best by placeholder fingerprint.
    public static func survey(_ pptx: URL, pack: Deck.Pack?) throws -> Survey {
        let inv = try TemplateInventory.read(pptx)
        let templates: [(name: String, required: Set<String>, all: Set<String>, textSlots: (min: Int, max: Int))] = (pack?.templates ?? []).map { t in
            let tokens = t.fingerprint.split(separator: " ").map(String.init)
            let required = Set(t.slots.filter { !$0.optional }.map { s in tokens.first { $0.hasSuffix("@\(s.idx)") } ?? "?@\(s.idx)" })
            let text = t.slots.filter { ["text", "number", "bullets"].contains($0.kind) }
            return (t.name, required, Set(tokens), (text.filter { !$0.optional }.count, text.count))
        }
        var groups: [SurveyGroup] = []
        for g in inv.groups {
            let slide = inv.slides.first { $0.n == g.slides[0] }
            let loose = slide?.shapes.filter { $0.placeholder == nil }.contains { $0.kind == "text" } ?? false
            let phTokens = Set((slide?.shapes ?? []).compactMap(\.placeholder).filter { !TemplateInventory.footers.contains(String($0.split(separator: "@")[0])) })
            var cands: [Candidate] = []
            if !loose || !phTokens.isEmpty {
                for t in templates {
                    if t.all == phTokens { cands.append(Candidate(template: t.name, how: "exact")) }
                    else if t.required.isSubset(of: phTokens), phTokens.isSubset(of: t.all) { cands.append(Candidate(template: t.name, how: "optional slots differ")) }
                    else if phTokens.isSubset(of: t.all), !phTokens.isEmpty { cands.append(Candidate(template: t.name, how: "slide has fewer boxes")) }
                    else if t.all.isSubset(of: phTokens), !t.all.isEmpty { cands.append(Candidate(template: t.name, how: "slide has extra boxes")) }
                }
            } else {
                let texts = slide?.shapes.filter { $0.kind == "text" }.count ?? 0
                for t in templates where t.textSlots.min <= texts && texts <= t.textSlots.max {
                    cands.append(Candidate(template: t.name, how: "loose boxes: \(texts) text boxes for \(t.textSlots.max) text slots; map them in the plan"))
                }
            }
            let rank = ["exact": 0, "optional slots differ": 1, "slide has extra boxes": 2, "slide has fewer boxes": 3]
            cands.sort { (rank[$0.how] ?? 9, $0.template) < (rank[$1.how] ?? 9, $1.template) }
            groups.append(SurveyGroup(id: g.id, slides: g.slides, fingerprint: g.fingerprint, layout: slide?.layout ?? "", loose: loose,
                                      best: cands.first, others: Array(cands.dropFirst().prefix(3))))
        }
        return Survey(file: inv.file, slides: inv.slides.count, pack: pack?.name, groups: groups, near: inv.near,
                      fonts: inv.fonts.filter { !$0.google }.map { "\($0.font) is not in Google Fonts" + ($0.substitute.map { " (closest: \($0))" } ?? "") },
                      comments: inv.slides.reduce(0) { $0 + $1.comments })
    }

    public static func render(_ s: Survey) -> String {
        var o = ["\(s.file): \(s.slides) slides in \(s.groups.count) group\(s.groups.count == 1 ? "" : "s")" + (s.pack.map { ", compared with the \($0) pack" } ?? "")]
        for g in s.groups {
            o.append("  \(g.id) slide\(g.slides.count == 1 ? "" : "s") \(g.slides.map(String.init).joined(separator: ", ")) on \(g.layout)\(g.loose ? " (loose boxes)" : ""): \(g.fingerprint)")
            if let b = g.best { o.append("      best: \(b.template) (\(b.how))") }
            else if s.pack != nil { o.append("      best: none in the pack; a new template, or amend one") }
            for c in g.others { o.append("      also: \(c.template) (\(c.how))") }
        }
        if !s.near.isEmpty {
            o.append("near groups (candidates to coalesce into one template with an optional slot):")
            for n in s.near { o.append("  \(n.a) ~ \(n.b): \(n.detail)") }
        }
        if !s.fonts.isEmpty { o.append("fonts: " + s.fonts.joined(separator: "; ")) }
        if s.comments > 0 { o.append("\(s.comments) PowerPoint comment\(s.comments == 1 ? "" : "s") will come in as Review comments") }
        o.append("Write a plan (see `duo2 help deck`) and run: duo2 deck import \(s.file) --pack <pack> --plan <plan.yaml>")
        return o.joined(separator: "\n")
    }

    public static func json(_ s: Survey) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(s), as: UTF8.self)
    }
}
