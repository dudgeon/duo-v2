import Foundation

// `duo2 doc outline` (DL-162): a Word document's paragraphs as Claude reads them, from the file with
// no renderer: each with its w14:paraId (the id the viewer stamps on what it draws), style, heading,
// text with the tracked changes accepted, the changes inside it and the comments that end in it.
// Read only: the document is opened for reading, never written.
extension Docx {
    public struct Change: Codable, Equatable, Sendable {
        /// `insert`, `delete`, `move-from`, `move-to` or `format`.
        public var kind: String
        public var author: String
        /// ISO 8601, as the file has it.
        public var date: String
        public var text: String
    }

    public struct Comment: Codable, Equatable, Sendable {
        public var id: String
        public var author: String
        public var date: String
        public var text: String
        /// The comment this one replies to.
        public var parent: String?
        /// The thread's root comment (itself for a root).
        public var thread: String
        public var resolved: Bool
    }

    public struct Paragraph: Codable, Equatable, Sendable {
        /// `w14:paraId`; nil in a file that has none (older Word, python-docx, Google Docs).
        public var id: String?
        /// 1-based position among the document's paragraphs.
        public var index: Int
        public var style: String?
        /// 0 for a Title, 1 and up for headings.
        public var level: Int?
        /// The nearest heading above it (a heading is under the one before it).
        public var heading: String?
        /// The text as it reads with every tracked change accepted.
        public var text: String
        public var changes: [Change]
        /// The comments whose range ends in this paragraph, each root followed by its replies.
        public var comments: [Comment]
    }

    /// Every paragraph of `word/document.xml`, in order (table cells and text boxes included).
    public static func outline(_ url: URL) throws -> [Paragraph] {
        let zip: Pptx.Zip
        do { zip = try Pptx.Zip(url) } catch { throw classify(url) }
        guard let doc = try? zip.xml("word/document.xml"), let body = doc.first("body") else {
            throw zip.entries.isEmpty ? Failure.damaged : Failure.notWord
        }
        // Styles: id -> (name, outline level).
        var styleName: [String: String] = [:], styleLevel: [String: Int] = [:]
        if let s = try? zip.xml("word/styles.xml") {
            for st in s.all("style") {
                guard let id = st.attr("w:styleId") else { continue }
                styleName[id] = st.first("name")?.attr("w:val") ?? id
                if let o = st.first("pPr")?.first("outlineLvl")?.attr("w:val").flatMap(Int.init) { styleLevel[id] = o + 1 }
            }
        }
        // Comments, with their threads from commentsExtended (a reply's paraId names its parent's).
        var comments: [String: Comment] = [:]
        var order: [String] = []
        if let c = try? zip.xml("word/comments.xml") {
            var byPara: [String: String] = [:]          // last paragraph's paraId -> comment id
            var paraOf: [String: String] = [:]
            for n in c.all("comment") {
                guard let id = n.attr("w:id") else { continue }
                let ps = n.all("p")
                let text = ps.map { plain($0, accepted: true) }.joined(separator: "\n")
                comments[id] = Comment(id: id, author: n.attr("w:author") ?? "", date: n.attr("w:date") ?? "", text: text, parent: nil, thread: id, resolved: false)
                order.append(id)
                if let pid = ps.last?.attr("w14:paraId") { byPara[pid] = id; paraOf[id] = pid }
            }
            if let ext = try? zip.xml("word/commentsExtended.xml") {
                for e in ext.all("commentEx") {
                    guard let pid = e.attr("w15:paraId"), let id = byPara[pid] else { continue }
                    if let parentPara = e.attr("w15:paraIdParent"), let parent = byPara[parentPara] { comments[id]?.parent = parent }
                    if e.attr("w15:done") == "1" { comments[id]?.resolved = true }
                }
            }
            func root(_ id: String) -> String { var r = id; var n = 0; while let p = comments[r]?.parent, n < 50 { r = p; n += 1 }; return r }
            let roots = order.map { ($0, root($0)) }
            for (id, r) in roots { comments[id]?.thread = r }
            for (id, r) in roots where r != id { if let done = comments[r]?.resolved { comments[id]?.resolved = done } }
        }
        // Walk the body, collecting paragraphs and the comment ranges that end in each.
        var out: [Paragraph] = []
        var heading: String?
        func visit(_ n: Pptx.Node) {
            for c in n.children {
                if c.name == "Fallback" { continue }   // Word's VML copy of a text box
                if c.name == "p" {
                    var p = paragraph(c, index: out.count + 1, styleName: styleName, styleLevel: styleLevel, comments: comments)
                    p.heading = heading   // under the heading before it, not itself
                    out.append(p)
                    if let l = p.level, l >= 1, !p.text.isEmpty { heading = p.text }
                }
                visit(c)
            }
        }
        visit(body)
        return out
    }

    /// A paragraph's text; `accepted` leaves out deletions and the source of a move.
    static func plain(_ n: Pptx.Node, accepted: Bool) -> String {
        var s = ""
        for c in n.children {
            switch c.name {
            case "t": s += c.value
            case "delText": if !accepted { s += c.value }
            case "tab": s += "\t"
            case "br", "cr": s += "\n"
            case "noBreakHyphen": s += "-"
            case "del", "moveFrom": if !accepted { s += plain(c, accepted: accepted) }
            case "pPr", "rPr", "Fallback", "txbxContent", "drawing", "pict", "instrText", "footnoteReference", "endnoteReference", "commentReference": break
            default: s += plain(c, accepted: accepted)
            }
        }
        return s
    }

    private static func paragraph(_ p: Pptx.Node, index: Int, styleName: [String: String], styleLevel: [String: Int], comments: [String: Comment]) -> Paragraph {
        let ppr = p.first("pPr")
        let style = ppr?.first("pStyle")?.attr("w:val")
        var level: Int?
        if let style, let name = styleName[style] {
            let lower = name.lowercased()
            if lower == "title" { level = 0 }
            else if lower.hasPrefix("heading "), let n = Int(lower.dropFirst(8)) { level = n }
            else if let l = styleLevel[style] { level = l }
        }
        if let o = ppr?.first("outlineLvl")?.attr("w:val").flatMap(Int.init), o < 9 { level = o + 1 }
        var changes: [Change] = []
        var ends: [String] = []
        func scan(_ n: Pptx.Node, inRun: Bool) {
            for c in n.children {
                switch c.name {
                case "Fallback", "txbxContent": continue
                case "ins", "del", "moveFrom", "moveTo":
                    guard n.name != "rPr", n.name != "trPr" else { continue }   // a paragraph or row mark's own revision
                    let kind = ["ins": "insert", "del": "delete", "moveFrom": "move-from", "moveTo": "move-to"][c.name]!
                    changes.append(Change(kind: kind, author: c.attr("w:author") ?? "", date: c.attr("w:date") ?? "", text: plain(c, accepted: false).trimmingCharacters(in: .newlines)))
                    scan(c, inRun: inRun)
                case "r":
                    if let ch = c.first("rPr")?.first("rPrChange") {
                        changes.append(Change(kind: "format", author: ch.attr("w:author") ?? "", date: ch.attr("w:date") ?? "", text: plain(c, accepted: false)))
                    }
                    scan(c, inRun: true)
                case "pPr":
                    if let ch = c.first("pPrChange") { changes.append(Change(kind: "format", author: ch.attr("w:author") ?? "", date: ch.attr("w:date") ?? "", text: "")) }
                case "commentRangeEnd": if let id = c.attr("w:id") { ends.append(id) }
                default: scan(c, inRun: inRun)
                }
            }
        }
        scan(p, inRun: false)
        // Each root with its replies, once.
        var roots: [String] = []
        for id in ends { if let t = comments[id]?.thread, !roots.contains(t) { roots.append(t) } }
        var mine: [Comment] = []
        for r in roots {
            if let c = comments[r] { mine.append(c) }
            for id in ends where id != r && comments[id]?.thread == r { if let c = comments[id] { mine.append(c) } }
        }
        return Paragraph(id: p.attr("w14:paraId"), index: index, style: style, level: level, heading: nil, text: plain(p, accepted: true), changes: changes, comments: mine)
    }
}
