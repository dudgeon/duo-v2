import Foundation

/// A Word document as clean Markdown (ENH-14, spike): the subset Google Docs imports cleanly
/// (headings, emphasis, links, tight nested lists, GFM tables, block quotes, footnotes, images),
/// with no raw HTML. Structure Word only implies is inferred: headings set by font size or bold,
/// lists typed as "•" or "1.", tables used for layout. Reads the zip with `Pptx.Zip`; the .docx is
/// never written.
public enum Docx {
    public enum TrackedChanges: String, Sendable { case accept, reject }
    public enum Comments: String, Sendable { case leaveOut, footnotes }

    public struct Options: Sendable {
        /// The folder images go in, relative to the .md (`<name>-images`).
        public var imagesFolder: String
        public var trackedChanges: TrackedChanges = .accept
        public var comments: Comments = .leaveOut
        public init(imagesFolder: String) { self.imagesFolder = imagesFolder }
    }

    /// What the conversion inferred, cleaned or left out, for the summary Duo shows.
    public struct Report: Codable, Equatable, Sendable {
        public var headingsFromStyles = 0, headingsFromOutline = 0, headingsFromSize = 0, headingsFromBold = 0
        public var typedBullets = 0, typedNumbers = 0
        public var layoutTables = 0, tables = 0, mergedCells = 0, cellsJoined = 0
        public var insertions = 0, deletions = 0
        public var comments = 0, footnotes = 0, images = 0, imagesUnviewable = 0, linkedImages = 0
        public var textBoxes = 0, equations = 0, tableOfContents = 0, headersFooters = 0, codeBlocks = 0
        public var underlines = 0

        /// One short line per thing done, most important first.
        public func lines(_ o: Options) -> [String] {
            var out: [String] = []
            func n(_ c: Int, _ one: String, _ many: String) -> String { c == 1 ? one : many.replacingOccurrences(of: "#", with: "\(c)") }
            let inferred = headingsFromSize + headingsFromBold + headingsFromOutline
            if inferred > 0 {
                var how: [String] = []
                if headingsFromSize > 0 { how.append("font size") }
                if headingsFromBold > 0 { how.append("bold text") }
                if headingsFromOutline > 0 { how.append("outline level") }
                out.append(n(inferred, "1 heading inferred from ", "# headings inferred from ") + how.joined(separator: " and "))
            }
            if typedBullets + typedNumbers > 0 { out.append(n(typedBullets + typedNumbers, "1 typed list item made a real list item", "# typed list items made real lists")) }
            if layoutTables > 0 { out.append(n(layoutTables, "1 layout table unwrapped into paragraphs", "# layout tables unwrapped into paragraphs")) }
            if mergedCells > 0 { out.append(n(mergedCells, "1 merged table cell split", "# merged table cells split")) }
            if cellsJoined > 0 { out.append(n(cellsJoined, "1 table cell's paragraphs joined", "# table cells' paragraphs joined")) }
            if insertions + deletions > 0 {
                out.append(n(insertions + deletions, "1 tracked change ", "# tracked changes ") + (o.trackedChanges == .accept ? "accepted" : "rejected"))
            }
            if comments > 0 { out.append(n(comments, "1 comment ", "# comments ") + (o.comments == .leaveOut ? "left out (the .docx keeps them)" : "kept as footnotes")) }
            if images > 0 { out.append(n(images, "1 image saved in ", "# images saved in ") + o.imagesFolder + "/") }
            if imagesUnviewable > 0 { out.append(n(imagesUnviewable, "1 image is a Windows drawing (EMF/WMF) Duo can't show", "# images are Windows drawings (EMF/WMF) Duo can't show")) }
            if linkedImages > 0 { out.append(n(linkedImages, "1 linked image left out", "# linked images left out")) }
            if footnotes > 0 { out.append(n(footnotes, "1 footnote kept", "# footnotes kept")) }
            if tableOfContents > 0 { out.append("Table of contents left out") }
            if textBoxes > 0 { out.append(n(textBoxes, "1 text box moved into the text", "# text boxes moved into the text")) }
            if equations > 0 { out.append(n(equations, "1 equation kept as plain text", "# equations kept as plain text")) }
            if headersFooters > 0 { out.append("Headers and footers left out") }
            if underlines > 0 { out.append("Underlining dropped (Markdown has none)") }
            return out
        }
    }

    public struct Result: Sendable {
        public var markdown: String
        /// File name inside the images folder → bytes, in order of first use.
        public var images: [(name: String, data: Data)]
        public var report: Report
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public static func convert(_ url: URL, options: Options) throws -> Result {
        let zip = try Pptx.Zip(url)
        guard let doc = try zip.xml("word/document.xml"), let body = doc.first("body") else {
            throw Failure(description: "not a Word document: no word/document.xml")
        }
        var c = Converter(zip: zip, options: options)
        try c.load()
        return try c.run(body)
    }

    // MARK: Model

    struct Fmt: Equatable {
        var bold = false, italic = false, strike = false, code = false, sub = false, sup = false
        var link: String?
    }

    enum Inline {
        case text(String, Fmt)
        case lineBreak
        case note(String)          // a footnote label: "1", "c1"
        case image(alt: String, path: String)
    }

    struct Para {
        var style: String?
        var inlines: [Inline] = []
        var numId = 0, ilvl = 0
        var outline: Int?
        var indent: Int?           // left indent in twips, as set on the paragraph or its style
        /// Character-weighted size (half-points) and boldness of the visible text, for inference.
        var size: Double = 0
        var allBold = false
        var allMono = false
        var toc = false
        var level: Int?            // heading level once decided; 0 is a Title
        var list: ListItem?
    }

    struct ListItem { var ordered: Bool; var level: Int; var number: Int }

    indirect enum Block {
        case para(Para)
        case table([[Cell]])
    }

    struct Cell { var blocks: [Block]; var span = 1; var mergedBelow = false }

    struct Style {
        var name = "", basedOn: String?, numId: Int?, ilvl: Int?, outline: Int?, indent: Int?
        var size: Double?, bold: Bool?, font: String?
    }

    struct Level { var format: String; var start: Int; var indent: Int? }

    // MARK: Converter

    struct Converter {
        let zip: Pptx.Zip
        let options: Options
        var report = Report()
        var styles: [String: Style] = [:]
        var defaultParaStyle: String?
        var defaultSize: Double = 20
        var defaultFont: String?
        var abstract: [Int: [Int: Level]] = [:]
        var nums: [Int: (abstract: Int, starts: [Int: Int])] = [:]
        var rels: [String: String] = [:]
        var externalRels: [String: String] = [:]
        var footnoteXML: [String: Pptx.Node] = [:], endnoteXML: [String: Pptx.Node] = [:]
        var commentXML: [String: Pptx.Node] = [:]
        var notes: [(label: String, text: String)] = []
        var imageNames: [String: String] = [:]          // zip path → output name
        var images: [(name: String, data: Data)] = []
        var fields: [(instr: String, result: Bool)] = []
        /// Paragraphs that came out of text boxes, emitted after the paragraph holding them.
        var pendingBoxes: [Block] = []

        init(zip: Pptx.Zip, options: Options) { self.zip = zip; self.options = options }

        mutating func load() throws {
            if let s = try zip.xml("word/styles.xml") {
                if let d = s.first("docDefaults")?.first("rPrDefault")?.first("rPr") {
                    if let v = d.first("sz")?.attr("w:val").flatMap(Double.init) { defaultSize = v }
                    defaultFont = d.first("rFonts")?.attr("w:ascii")
                }
                for st in s.all("style") {
                    guard let id = st.attr("w:styleId") else { continue }
                    var y = Style()
                    y.name = st.first("name")?.attr("w:val")?.lowercased() ?? id.lowercased()
                    y.basedOn = st.first("basedOn")?.attr("w:val")
                    if let p = st.first("pPr") {
                        if let np = p.first("numPr") {
                            y.numId = np.first("numId")?.attr("w:val").flatMap(Int.init)
                            y.ilvl = np.first("ilvl")?.attr("w:val").flatMap(Int.init)
                        }
                        y.outline = p.first("outlineLvl")?.attr("w:val").flatMap(Int.init)
                        y.indent = Self.indent(p)
                    }
                    if let r = st.first("rPr") {
                        y.size = r.first("sz")?.attr("w:val").flatMap(Double.init)
                        if let b = r.first("b") { y.bold = on(b) }
                        y.font = r.first("rFonts")?.attr("w:ascii")
                    }
                    styles[id] = y
                    if st.attr("w:type") == "paragraph", on(st, "w:default") { defaultParaStyle = id }
                }
            }
            if let n = try zip.xml("word/numbering.xml") {
                for a in n.children where a.name == "abstractNum" {
                    guard let id = a.attr("w:abstractNumId").flatMap(Int.init) else { continue }
                    var lv: [Int: Level] = [:]
                    for l in a.children where l.name == "lvl" {
                        guard let i = l.attr("w:ilvl").flatMap(Int.init) else { continue }
                        lv[i] = Level(format: l.first("numFmt")?.attr("w:val") ?? "decimal",
                                      start: l.first("start")?.attr("w:val").flatMap(Int.init) ?? 1,
                                      indent: l.first("pPr").flatMap(Self.indent))
                    }
                    abstract[id] = lv
                }
                for m in n.children where m.name == "num" {
                    guard let id = m.attr("w:numId").flatMap(Int.init),
                          let a = m.first("abstractNumId")?.attr("w:val").flatMap(Int.init) else { continue }
                    var starts: [Int: Int] = [:]
                    for o in m.children where o.name == "lvlOverride" {
                        if let i = o.attr("w:ilvl").flatMap(Int.init), let s = o.first("startOverride")?.attr("w:val").flatMap(Int.init) { starts[i] = s }
                    }
                    nums[id] = (a, starts)
                }
            }
            if let r = try zip.xml("word/_rels/document.xml.rels") {
                for rel in r.all("Relationship") {
                    guard let id = rel.attr("Id"), let t = rel.attr("Target") else { continue }
                    if rel.attr("TargetMode") == "External" { externalRels[id] = t } else {
                        rels[id] = t.hasPrefix("/") ? String(t.dropFirst()) : Pptx.normalize("word/\(t)")
                    }
                    let type = rel.attr("Type") ?? ""
                    if type.hasSuffix("/header") || type.hasSuffix("/footer"), let part = rels[id], let x = try zip.xml(part),
                       !x.all("t").map(\.value).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        report.headersFooters += 1
                    }
                }
            }
            for (part, key) in [("word/footnotes.xml", "footnote"), ("word/endnotes.xml", "endnote"), ("word/comments.xml", "comment")] {
                guard let x = try zip.xml(part) else { continue }
                for n in x.children where n.name == key {
                    guard let id = n.attr("w:id") else { continue }
                    switch key {
                    case "footnote": footnoteXML[id] = n
                    case "endnote": endnoteXML[id] = n
                    default: commentXML[id] = n
                    }
                }
            }
        }

        static func indent(_ pPr: Pptx.Node) -> Int? {
            guard let i = pPr.first("ind") else { return nil }
            return (i.attr("w:left") ?? i.attr("w:start")).flatMap(Int.init)
        }

        func on(_ n: Pptx.Node, _ attr: String = "w:val") -> Bool {
            guard let v = n.attr(attr) else { return attr == "w:val" }
            return !["0", "false", "off", "none"].contains(v)
        }

        /// A style and the styles it's based on, nearest first.
        func chain(_ id: String?) -> [Style] {
            var out: [Style] = [], seen = Set<String>(), cur = id
            while let c = cur, !seen.contains(c), let s = styles[c] { out.append(s); seen.insert(c); cur = s.basedOn }
            return out
        }

        func headingLevel(_ style: String?) -> (level: Int, title: Bool)? {
            for s in chain(style) {
                if s.name == "title" { return (0, true) }
                if s.name.hasPrefix("heading "), let n = Int(s.name.dropFirst(8)), (1...9).contains(n) { return (n, false) }
            }
            return nil
        }

        // MARK: Run

        mutating func run(_ body: Pptx.Node) throws -> Result {
            var blocks = try readBlocks(body)
            let bodySize = self.bodySize(blocks)
            blocks = inferHeadings(blocks, bodySize: bodySize)
            blocks = inferLists(blocks)
            var md = render(blocks, inTable: false).joined(separator: "\n\n")
            if !notes.isEmpty {
                md += "\n\n" + notes.map { "[^\($0.label)]: \($0.text)" }.joined(separator: "\n\n")
            }
            return Result(markdown: md.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", images: images, report: report)
        }

        mutating func readBlocks(_ container: Pptx.Node) throws -> [Block] {
            var out: [Block] = []
            for el in container.children {
                switch el.name {
                case "p":
                    let p = try readPara(el)
                    out.append(.para(p))
                    out += pendingBoxes
                    pendingBoxes = []
                case "tbl": out.append(try readTable(el))
                case "sdt", "customXml", "sdtContent":
                    out += try readBlocks(el.name == "sdt" ? (el.first("sdtContent") ?? el) : el)
                case "ins", "moveTo":   // a tracked insertion of whole paragraphs
                    if options.trackedChanges == .accept { out += try readBlocks(el) }
                case "del", "moveFrom":
                    if options.trackedChanges == .reject { out += try readBlocks(el) }
                case "altChunk": break
                default: break
                }
            }
            return out
        }

        mutating func readTable(_ tbl: Pptx.Node) throws -> Block {
            var rows: [[Cell]] = []
            for tr in tbl.children where tr.name == "tr" {
                var row: [Cell] = []
                for tc in tr.children where tc.name == "tc" {
                    let pr = tc.first("tcPr")
                    var cell = Cell(blocks: try readBlocks(tc))
                    cell.span = pr?.first("gridSpan")?.attr("w:val").flatMap(Int.init) ?? 1
                    if let v = pr?.first("vMerge"), v.attr("w:val") != "restart" { cell.mergedBelow = true }
                    row.append(cell)
                }
                rows.append(row)
            }
            return .table(rows)
        }

        mutating func readPara(_ p: Pptx.Node) throws -> Para {
            var para = Para()
            let pPr = p.first("pPr")
            para.style = pPr?.first("pStyle")?.attr("w:val") ?? defaultParaStyle
            let ch = chain(para.style)
            if let np = pPr?.first("numPr") {
                para.numId = np.first("numId")?.attr("w:val").flatMap(Int.init) ?? 0
                para.ilvl = np.first("ilvl")?.attr("w:val").flatMap(Int.init) ?? 0
            } else if let s = ch.first(where: { $0.numId != nil }) {
                para.numId = s.numId ?? 0
                para.ilvl = s.ilvl ?? 0
            }
            para.indent = pPr.flatMap(Self.indent) ?? ch.compactMap(\.indent).first
            para.outline = pPr?.first("outlineLvl")?.attr("w:val").flatMap(Int.init) ?? ch.compactMap(\.outline).first
            var weights: [(size: Double, bold: Bool, mono: Bool, n: Int)] = []
            try readInlines(p, into: &para.inlines, fmt: Fmt(), paraStyle: ch, weights: &weights)
            let total = weights.reduce(0) { $0 + $1.n }
            if total > 0 {
                para.size = weights.reduce(0) { $0 + $1.size * Double($1.n) } / Double(total)
                para.allBold = weights.allSatisfy(\.bold)
                para.allMono = weights.allSatisfy(\.mono)
            }
            if fields.contains(where: { $0.instr.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("TOC") }) || ch.contains(where: { $0.name.hasPrefix("toc ") }) {
                para.toc = true
            }
            return para
        }

        static let monoFonts = ["courier", "consolas", "menlo", "monaco", "source code", "lucida console", "andale mono", "sf mono", "fira code", "jetbrains mono", "roboto mono", "inconsolata"]

        mutating func readInlines(_ el: Pptx.Node, into out: inout [Inline], fmt: Fmt, paraStyle: [Style], weights: inout [(size: Double, bold: Bool, mono: Bool, n: Int)]) throws {
            for c in el.children {
                switch c.name {
                case "r":
                    try readRun(c, into: &out, fmt: fmt, paraStyle: paraStyle, weights: &weights)
                case "hyperlink":
                    var f = fmt
                    if let id = c.attr("r:id"), let url = externalRels[id] { f.link = url }
                    try readInlines(c, into: &out, fmt: f, paraStyle: paraStyle, weights: &weights)
                case "ins", "moveTo":
                    if c.all("r").contains(where: { !$0.all("t").isEmpty }) { report.insertions += 1 }
                    if options.trackedChanges == .accept { try readInlines(c, into: &out, fmt: fmt, paraStyle: paraStyle, weights: &weights) }
                case "del", "moveFrom":
                    if !c.all("delText").isEmpty || !c.all("t").isEmpty { report.deletions += 1 }
                    if options.trackedChanges == .reject { try readInlines(c, into: &out, fmt: fmt, paraStyle: paraStyle, weights: &weights) }
                case "fldSimple":
                    var f = fmt
                    let instr = c.attr("w:instr") ?? ""
                    if let url = Self.hyperlink(instr) { f.link = url }
                    try readInlines(c, into: &out, fmt: f, paraStyle: paraStyle, weights: &weights)
                case "smartTag", "customXml", "sdt", "sdtContent", "bdo", "dir":
                    try readInlines(c.name == "sdt" ? (c.first("sdtContent") ?? c) : c, into: &out, fmt: fmt, paraStyle: paraStyle, weights: &weights)
                case "oMath", "oMathPara":
                    report.equations += 1
                    out.append(.text(c.all("t").map(\.value).joined(), fmt))
                case "commentReference":
                    break
                default: break
                }
            }
        }

        static func hyperlink(_ instr: String) -> String? {
            let t = instr.trimmingCharacters(in: .whitespaces)
            guard t.uppercased().hasPrefix("HYPERLINK") else { return nil }
            guard let a = t.firstIndex(of: "\""), let b = t[t.index(after: a)...].firstIndex(of: "\"") else { return nil }
            let url = String(t[t.index(after: a)..<b])
            return url.isEmpty || t.contains("\\l") && !url.contains(":") ? nil : url
        }

        mutating func readRun(_ r: Pptx.Node, into out: inout [Inline], fmt: Fmt, paraStyle: [Style], weights: inout [(size: Double, bold: Bool, mono: Bool, n: Int)]) throws {
            let rPr = r.first("rPr")
            var f = fmt
            let rs = chain(rPr?.first("rStyle")?.attr("w:val"))
            func prop<T>(_ run: T?, _ get: (Style) -> T?) -> T? { run ?? rs.lazy.compactMap(get).first ?? paraStyle.lazy.compactMap(get).first }
            let bold = prop(rPr?.first("b").map { on($0) }, \.bold) ?? false
            let size = prop(rPr?.first("sz")?.attr("w:val").flatMap(Double.init), \.size) ?? defaultSize
            let font = (prop(rPr?.first("rFonts")?.attr("w:ascii"), \.font) ?? defaultFont ?? "").lowercased()
            let mono = Self.monoFonts.contains { font.contains($0) }
            f.bold = bold
            f.italic = rPr?.first("i").map { on($0) } ?? false
            f.strike = (rPr?.first("strike").map { on($0) } ?? false) || (rPr?.first("dstrike").map { on($0) } ?? false)
            f.code = mono
            if let v = rPr?.first("vertAlign")?.attr("w:val") { f.sub = v == "subscript"; f.sup = v == "superscript" }
            if let u = rPr?.first("u"), u.attr("w:val") != "none", f.link == nil { report.underlines += 1 }
            func visible(_ s: String) {
                // The field machinery: inside a field's instructions nothing shows; inside its
                // result, a HYPERLINK field makes a link.
                if fields.contains(where: { !$0.result }) { return }
                if fields.contains(where: { $0.instr.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("TOC") }) { return }
                var g = f
                if let url = fields.reversed().lazy.compactMap({ Self.hyperlink($0.instr) }).first { g.link = url }
                let n = s.filter { !$0.isWhitespace }.count
                if n > 0 { weights.append((size, bold, mono, n)) }
                out.append(.text(s, g))
            }
            for c in r.children {
                switch c.name {
                case "t": visible(c.value)
                case "delText": if options.trackedChanges == .reject { visible(c.value) }
                case "tab", "ptab": visible(" ")
                case "noBreakHyphen": visible("-")
                case "softHyphen": break
                case "sym":
                    if let h = c.attr("w:char"), let v = UInt32(h, radix: 16), v < 0xF000, let u = Unicode.Scalar(v) { visible(String(Character(u))) }
                case "br", "cr":
                    if c.attr("w:type") == "page" || c.attr("w:type") == "column" { break }
                    if !fields.contains(where: { !$0.result }) { out.append(.lineBreak) }
                case "fldChar":
                    switch c.attr("w:fldCharType") {
                    case "begin": fields.append(("", false))
                    case "separate": if !fields.isEmpty { fields[fields.count - 1].result = true }
                    case "end":
                        if let last = fields.popLast(), last.instr.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("TOC") { report.tableOfContents += 1 }
                    default: break
                    }
                case "instrText":
                    if !fields.isEmpty { fields[fields.count - 1].instr += c.value }
                case "footnoteReference", "endnoteReference":
                    guard let id = c.attr("w:id"), let n = (c.name == "footnoteReference" ? footnoteXML : endnoteXML)[id] else { break }
                    let label = "\(notes.count + 1)"
                    notes.append((label, try noteText(n)))
                    report.footnotes += 1
                    out.append(.note(label))
                case "commentReference":
                    report.comments += 1
                    if options.comments == .footnotes, let id = c.attr("w:id"), let n = commentXML[id] {
                        let label = "c\(notes.filter { $0.label.hasPrefix("c") }.count + 1)"
                        let who = n.attr("w:author").map { "\($0): " } ?? ""
                        notes.append((label, "Comment. " + who + (try noteText(n))))
                        out.append(.note(label))
                    }
                case "drawing", "pict", "object":
                    try readDrawing(c, into: &out)
                case "AlternateContent":
                    // Prefer the Fallback's VML only when there's no Choice drawing.
                    if let ch = c.first("Choice") { try readDrawing(ch, into: &out) }
                default: break
                }
            }
        }

        mutating func readDrawing(_ d: Pptx.Node, into out: inout [Inline]) throws {
            for box in d.all("txbxContent") {
                report.textBoxes += 1
                pendingBoxes += try readBlocks(box)
            }
            let alt = d.first("docPr", deep: true).flatMap { $0.attr("descr") ?? $0.attr("title") } ?? ""
            for blip in d.all("blip") + d.all("imagedata") {
                if let id = blip.attr("r:embed") ?? blip.attr("r:id"), let part = rels[id] {
                    out.append(.image(alt: alt, path: try imagePath(part)))
                } else if blip.attr("r:link") != nil {
                    report.linkedImages += 1
                }
            }
        }

        mutating func imagePath(_ part: String) throws -> String {
            if let n = imageNames[part] { return "\(options.imagesFolder)/\(n)" }
            let ext = (part as NSString).pathExtension.lowercased()
            let name = "image-\(images.count + 1).\(ext.isEmpty ? "bin" : ext)"
            imageNames[part] = name
            if let data = try zip.read(part) { images.append((name, data)) }
            report.images += 1
            if ["emf", "wmf"].contains(ext) { report.imagesUnviewable += 1 }
            return "\(options.imagesFolder)/\(name)"
        }

        mutating func noteText(_ n: Pptx.Node) throws -> String {
            let saved = fields
            fields = []
            defer { fields = saved }
            var parts: [String] = []
            for p in n.children where p.name == "p" {
                var para = try readPara(p)
                para.inlines = para.inlines.filter { if case .text = $0 { return true }; return false }
                let s = inline(para.inlines).trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { parts.append(s) }
            }
            return parts.joined(separator: " ")
        }

        // MARK: Inference

        func plain(_ p: Para) -> String {
            p.inlines.map { if case .text(let s, _) = $0 { return s }; return "" }.joined()
        }

        func paras(_ blocks: [Block]) -> [Para] {
            blocks.flatMap { b -> [Para] in
                switch b {
                case .para(let p): return [p]
                case .table(let rows): return rows.flatMap { $0.flatMap { paras($0.blocks) } }
                }
            }
        }

        /// The body text size: the size most characters are set in, outside headings.
        func bodySize(_ blocks: [Block]) -> Double {
            var count: [Double: Int] = [:]
            for p in paras(blocks) where headingLevel(p.style) == nil && p.size > 0 {
                count[(p.size * 2).rounded() / 2, default: 0] += plain(p).count
            }
            return count.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? defaultSize
        }

        /// A paragraph that looks like a heading without being styled as one: short, no sentence
        /// punctuation at the end, and either bold throughout or clearly larger than the body.
        func candidate(_ p: Para, bodySize: Double) -> (key: Double, bold: Bool)? {
            guard p.numId == 0, !p.toc, !p.allMono else { return nil }
            if p.inlines.contains(where: { if case .lineBreak = $0 { return true }; if case .image = $0 { return true }; return false }) { return nil }
            let t = plain(p).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 120, t.split(whereSeparator: \.isWhitespace).count <= 12 else { return nil }
            let tail = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]» "))
            if let last = tail.last, ".,;:!".contains(last) { return nil }
            if Self.bulletPrefix(t) != nil { return nil }
            let ratio = p.size / bodySize
            if ratio >= 1.15 { return ((p.size * 2).rounded() / 2, p.allBold) }
            if p.allBold && ratio >= 0.95 { return ((p.size * 2).rounded() / 2, true) }
            return nil
        }

        mutating func inferHeadings(_ blocks: [Block], bodySize: Double) -> [Block] {
            var out = blocks
            var realSizes: [Int: [Double]] = [:]
            for (i, b) in out.enumerated() {
                guard case .para(var p) = b, !p.toc else { continue }
                if let h = headingLevel(p.style) {
                    p.level = h.level
                    report.headingsFromStyles += 1
                } else if let o = p.outline, o < 9, p.numId == 0, !plain(p).trimmingCharacters(in: .whitespaces).isEmpty {
                    p.level = o + 1
                    report.headingsFromOutline += 1
                }
                if let l = p.level, l > 0, p.size > 0 { realSizes[l, default: []].append(p.size) }
                out[i] = .para(p)
            }
            // Candidates, keyed by their look. Bold at body size counts only when body text
            // follows, so a run of bold lines stays a run of bold lines.
            var cands: [Int: (key: Double, bold: Bool)] = [:]
            for (i, b) in out.enumerated() {
                guard case .para(let p) = b, p.level == nil, let c = candidate(p, bodySize: bodySize) else { continue }
                if c.key / bodySize < 1.15 {
                    guard let next = out[(i + 1)...].first(where: { if case .para(let q) = $0 { return !plain(q).trimmingCharacters(in: .whitespaces).isEmpty }; return true }),
                          case .para(let q) = next, q.level == nil, candidate(q, bodySize: bodySize) == nil else { continue }
                }
                cands[i] = c
            }
            guard !cands.isEmpty else { return normalized(out) }
            let looks = Set(cands.values.map { "\($0.key)|\($0.bold)" })
                .map { s -> (Double, Bool) in let a = s.split(separator: "|"); return (Double(a[0])!, a[1] == "true") }
                .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : ($0.1 && !$1.1) }
            var levelOf: [String: Int] = [:]
            if realSizes.isEmpty {
                for (n, l) in looks.enumerated() { levelOf["\(l.0)|\(l.1)"] = min(n + 1, 6) }
            } else {
                let typical = realSizes.mapValues { $0.reduce(0, +) / Double($0.count) }
                let deepest = typical.keys.max() ?? 1
                for l in looks {
                    let near = typical.min { abs($0.value - l.0) < abs($1.value - l.0) }!
                    levelOf["\(l.0)|\(l.1)"] = abs(near.value - l.0) <= 3 ? near.key : (l.0 > near.value ? max(1, near.key - 1) : min(deepest + 1, 6))
                }
            }
            for (i, c) in cands {
                guard case .para(var p) = out[i] else { continue }
                p.level = levelOf["\(c.key)|\(c.bold)"]
                if c.key / bodySize >= 1.15 { report.headingsFromSize += 1 } else { report.headingsFromBold += 1 }
                out[i] = .para(p)
            }
            return normalized(out)
        }

        /// Heading levels in use, renumbered from 1 with no gaps (a Title becomes the one `#`).
        func normalized(_ blocks: [Block]) -> [Block] {
            let used = Set(blocks.compactMap { b -> Int? in if case .para(let p) = b { return p.level }; return nil }).sorted()
            let map = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($1, min($0 + 1, 6)) })
            // Then no heading more than one level below the one before it.
            var prev = 0
            return blocks.map { b in
                guard case .para(var p) = b, let l = p.level, let m = map[l] else { return b }
                p.level = min(m, prev + 1)
                prev = p.level!
                return .para(p)
            }
        }

        /// Typed bullets, including Symbol-font U+F0B7 pasted from old documents.
        static let bullets = Set("•●○◦▪■□–—-*·➢►✓✔\u{F0B7}")

        /// The length of a typed bullet ("• ", "-\t") at the start of the text.
        static func bulletPrefix(_ t: String) -> Int? {
            guard let f = t.first, bullets.contains(f) else { return nil }
            let rest = t.dropFirst()
            let ws = rest.prefix { $0 == " " || $0 == "\t" || $0 == "\u{a0}" }.count
            return ws > 0 && rest.count > ws ? 1 + ws : nil
        }

        /// A typed number ("1. ", "2)\t", "a) ") at the start: its value and prefix length.
        static func numberPrefix(_ t: String) -> (value: Int, letter: Bool, length: Int)? {
            var i = t.startIndex, digits = ""
            while i < t.endIndex, t[i].isASCII, t[i].isNumber, digits.count < 3 { digits.append(t[i]); i = t.index(after: i) }
            var value: Int?, letter = false
            if !digits.isEmpty { value = Int(digits) } else if i < t.endIndex, let a = t[i].asciiValue, (97...122).contains(a) {
                value = Int(a) - 96; letter = true; i = t.index(after: i)
            }
            guard let v = value, i < t.endIndex, t[i] == "." || t[i] == ")" else { return nil }
            i = t.index(after: i)
            let ws = t[i...].prefix { $0 == " " || $0 == "\t" || $0 == "\u{a0}" }.count
            guard ws > 0, t.distance(from: t.startIndex, to: i) + ws < t.count else { return nil }
            return (v, letter, t.distance(from: t.startIndex, to: i) + ws)
        }

        mutating func inferLists(_ blocks: [Block]) -> [Block] {
            var out = blocks
            var counters: [Int: [Int: Int]] = [:]       // numId → ilvl → next number
            var i = 0
            while i < out.count {
                guard case .para(var p) = out[i], p.level == nil else { i += 1; continue }
                // A real list: its numbering definition says bullet or number.
                if p.numId != 0, let def = nums[p.numId], let lv = abstract[def.abstract]?[p.ilvl] ?? abstract[def.abstract]?[0], lv.format != "none" {
                    var c = counters[p.numId] ?? [:]
                    let n = c[p.ilvl] ?? (def.starts[p.ilvl] ?? lv.start)
                    c[p.ilvl] = n + 1
                    for deeper in c.keys where deeper > p.ilvl { c[deeper] = nil }
                    counters[p.numId] = c
                    p.list = ListItem(ordered: lv.format != "bullet", level: p.ilvl, number: n)
                    if p.indent == nil { p.indent = lv.indent }
                    out[i] = .para(p)
                    i += 1
                    continue
                }
                let t = plain(p)
                if let len = Self.bulletPrefix(t) {
                    p.inlines = Self.drop(len, from: p.inlines)
                    p.list = ListItem(ordered: false, level: 0, number: 0)
                    report.typedBullets += 1
                    out[i] = .para(p)
                    i += 1
                    continue
                }
                // Typed numbers need a run of two or more counting up by one, so "2026 was…" or a
                // lone "1." stays text.
                if let first = Self.numberPrefix(t) {
                    var run = [(i, first)]
                    var j = i + 1
                    while j < out.count, case .para(let q) = out[j], q.level == nil, q.numId == 0,
                          let n = Self.numberPrefix(plain(q)), n.letter == first.letter, n.value == run.last!.1.value + 1 {
                        run.append((j, n)); j += 1
                    }
                    if run.count >= 2 {
                        for (k, n) in run {
                            guard case .para(var q) = out[k] else { continue }
                            q.inlines = Self.drop(n.length, from: q.inlines)
                            q.list = ListItem(ordered: true, level: 0, number: n.value)
                            report.typedNumbers += 1
                            out[k] = .para(q)
                        }
                        i = j
                        continue
                    }
                }
                i += 1
            }
            return nestByIndent(out)
        }

        /// Word nests "List Bullet 2" by indent, not by level: within each run of list items, the
        /// distinct indents, smallest first, are the nesting levels.
        func nestByIndent(_ blocks: [Block]) -> [Block] {
            var out = blocks, i = 0
            while i < out.count {
                guard case .para(let first) = out[i], first.list != nil else { i += 1; continue }
                var j = i
                while j < out.count, case .para(let q) = out[j], q.list != nil { j += 1 }
                let items = (i..<j).compactMap { k -> Para? in if case .para(let q) = out[k] { return q }; return nil }
                if items.allSatisfy({ $0.indent != nil }) {
                    var levels: [Int] = []
                    for x in Set(items.map { $0.indent! / 180 }).sorted() { levels.append(x) }
                    for k in i..<j {
                        guard case .para(var q) = out[k] else { continue }
                        q.list!.level = levels.firstIndex(of: q.indent! / 180) ?? q.list!.level
                        out[k] = .para(q)
                    }
                }
                i = j
            }
            return out
        }

        static func drop(_ n: Int, from inlines: [Inline]) -> [Inline] {
            var left = n, out: [Inline] = []
            for x in inlines {
                if left > 0, case .text(let s, let f) = x {
                    if s.count <= left { left -= s.count; continue }
                    out.append(.text(String(s.dropFirst(left)), f)); left = 0
                } else { out.append(x) }
            }
            return out
        }

        // MARK: Render

        mutating func render(_ blocks: [Block], inTable: Bool) -> [String] {
            var out: [String] = []
            var listWidths: [Int] = []        // marker width per open list level
            var lastWasList = false
            var code: [String] = []
            func flushCode() {
                if !code.isEmpty { out.append("```\n" + code.joined(separator: "\n") + "\n```"); report.codeBlocks += 1; code = [] }
            }
            for b in blocks {
                switch b {
                case .table(let rows):
                    flushCode()
                    out += renderTable(rows)
                    lastWasList = false
                case .para(let p):
                    if p.toc { continue }
                    let isCodeStyle = chain(p.style).contains { $0.name.contains("code") || $0.name.contains("preformatted") || $0.name == "plain text" }
                    if p.list == nil, p.level == nil, (p.allMono || isCodeStyle), !plain(p).isEmpty {
                        code.append(plain(p).replacingOccurrences(of: "\u{a0}", with: " "))
                        continue
                    }
                    flushCode()
                    if let l = p.level {
                        let text = inline(p.inlines.map { x -> Inline in
                            switch x {
                            case .text(let s, var f): f.bold = false; return .text(s, f)
                            case .lineBreak: return .text(" ", Fmt())
                            default: return x
                            }
                        }).trimmingCharacters(in: .whitespaces)
                        if text.isEmpty { continue }
                        out.append(String(repeating: "#", count: l) + " " + text)
                        lastWasList = false
                        continue
                    }
                    var paragraphs = splitOnBlankLines(p.inlines).map { inline($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if paragraphs.isEmpty { continue }
                    if let item = p.list {
                        let level = min(item.level, listWidths.count)
                        listWidths = Array(listWidths.prefix(level))
                        let marker = item.ordered ? "\(item.number). " : "- "
                        let indent = String(repeating: " ", count: listWidths.reduce(0, +))
                        listWidths.append(marker.count)
                        let body = paragraphs.joined(separator: "\\\n").replacingOccurrences(of: "\n", with: "\n" + indent + String(repeating: " ", count: marker.count))
                        let line = indent + marker + body
                        // Tight lists: items join with one newline.
                        if lastWasList, let prev = out.popLast() { out.append(prev + "\n" + line) } else { out.append(line) }
                        lastWasList = true
                        continue
                    }
                    listWidths = []
                    lastWasList = false
                    paragraphs = paragraphs.map(Self.escapeLineStarts)
                    let quote = chain(p.style).contains { $0.name == "quote" || $0.name == "intense quote" || $0.name == "block text" }
                    out += quote ? paragraphs.map { "> " + $0.replacingOccurrences(of: "\n", with: "\n> ") } : paragraphs
                }
            }
            flushCode()
            return out
        }

        /// Two or more line breaks in a row were spacing: they become separate paragraphs.
        func splitOnBlankLines(_ inlines: [Inline]) -> [[Inline]] {
            var out: [[Inline]] = [[]], breaks = 0
            for x in inlines {
                if case .lineBreak = x { breaks += 1; continue }
                if breaks >= 2 { out.append([]) } else if breaks == 1, !out[out.count - 1].isEmpty { out[out.count - 1].append(.lineBreak) }
                breaks = 0
                out[out.count - 1].append(x)
            }
            return out
        }

        mutating func renderTable(_ rows: [[Cell]]) -> [String] {
            let cols = rows.map { $0.reduce(0) { $0 + $1.span } }.max() ?? 0
            let nested = rows.contains { $0.contains { $0.blocks.contains { if case .table = $0 { return true }; return false } } }
            let headed = rows.contains { $0.contains { $0.blocks.contains { if case .para(let p) = $0 { return headingLevel(p.style) != nil }; return false } } }
            if rows.count <= 1 || cols <= 1 || nested || headed {
                report.layoutTables += 1
                return rows.flatMap { $0.flatMap { render($0.blocks, inTable: true) } }
            }
            report.tables += 1
            var grid: [[String]] = []
            for row in rows {
                var cells: [String] = []
                for c in row {
                    let ps = paras(c.blocks).map { p -> String in
                        let s = inline(p.inlines.map { if case .lineBreak = $0 { return .text(" ", Fmt()) }; return $0 })
                        return s.trimmingCharacters(in: .whitespaces)
                    }.filter { !$0.isEmpty }
                    if ps.count > 1 { report.cellsJoined += 1 }
                    cells.append(c.mergedBelow ? "" : ps.joined(separator: " ").replacingOccurrences(of: "|", with: "\\|"))
                    if c.mergedBelow { report.mergedCells += 1 }
                    if c.span > 1 { report.mergedCells += 1; cells += Array(repeating: "", count: c.span - 1) }
                }
                grid.append(cells + Array(repeating: "", count: max(0, cols - cells.count)))
            }
            func line(_ r: [String]) -> String { "| " + r.joined(separator: " | ") + " |" }
            return [([line(grid[0]), line(Array(repeating: "---", count: cols))] + grid.dropFirst().map(line)).joined(separator: "\n")]
        }

        static func escapeLineStarts(_ s: String) -> String {
            s.split(separator: "\n", omittingEmptySubsequences: false).map { l -> String in
                var l = String(l)
                if let f = l.first, "#>".contains(f) { l = "\\" + l }
                else if l.hasPrefix("- ") || l.hasPrefix("+ ") { l = "\\" + l }
                else if let n = numberPrefix(l), !n.letter {
                    let digits = String(n.value).count
                    l.insert("\\", at: l.index(l.startIndex, offsetBy: digits))
                }
                return l
            }.joined(separator: "\n")
        }

        static let subs: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎"]
        static let sups: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ"]

        static func escape(_ s: String) -> String {
            var out = ""
            let chars = Array(s)
            for (i, ch) in chars.enumerated() {
                switch ch {
                case "\\", "*", "`", "[", "]", "<", "~": out += "\\" + String(ch)
                case "_":
                    // Inside a word (snake_case) an underscore can't start emphasis.
                    let before = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                    let after = i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)
                    out += before && after ? "_" : "\\_"
                case "\u{a0}": out += " "
                default: out.append(ch)
                }
            }
            return out
        }

        /// Inline Markdown: emphasis opened and closed as the formatting changes, spaces kept
        /// outside the markers, links grouped, sub/superscript digits as Unicode.
        func inline(_ inlines: [Inline]) -> String {
            // Merge neighbours with the same formatting first; Word splits runs freely.
            var merged: [Inline] = []
            for x in inlines {
                if case .text(let s, let f) = x, case .text(let ps, let pf)? = merged.last, pf == f { merged[merged.count - 1] = .text(ps + s, f) } else { merged.append(x) }
            }
            var out = "", open: [String] = []
            func close(to n: Int) {
                guard open.count > n else { return }
                let trail = String(out.reversed().prefix { $0 == " " }.reversed())
                out.removeLast(trail.count)
                while open.count > n { out += open.removeLast() }
                out += trail
            }
            func marks(_ f: Fmt) -> [String] { (f.bold ? ["**"] : []) + (f.italic ? ["*"] : []) + (f.strike ? ["~~"] : []) }
            var link: String?
            var linkStart = 0
            func endLink() {
                guard let url = link else { return }
                close(to: 0)
                let start = out.index(out.startIndex, offsetBy: linkStart)
                let text = String(out[start...]).trimmingCharacters(in: .whitespaces)
                out.removeSubrange(start...)
                out += text.isEmpty ? "" : "[\(text)](\(url.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: ")", with: "%29")))"
                link = nil
            }
            for x in merged {
                switch x {
                case .text(var s, let f):
                    if f.link != link { endLink(); if let u = f.link { close(to: 0); link = u; linkStart = out.count } }
                    if f.sub, s.allSatisfy({ Self.subs[$0] != nil }) { s = String(s.map { Self.subs[$0]! }) }
                    if f.sup, s.allSatisfy({ Self.sups[$0] != nil }) { s = String(s.map { Self.sups[$0]! }) }
                    if s.allSatisfy({ $0 == " " }) { out += s; continue }
                    let want = marks(f)
                    var keep = 0
                    while keep < open.count, keep < want.count, open[keep] == want[keep] { keep += 1 }
                    close(to: keep)
                    let lead = s.prefix { $0 == " " }
                    out += lead
                    s.removeFirst(lead.count)
                    for m in want.dropFirst(keep) { out += m; open.append(m) }
                    if f.code {
                        let fence = s.contains("`") ? "``" : "`"
                        let core = s.trimmingCharacters(in: .whitespaces)
                        out += fence + (fence == "``" ? " \(core) " : core) + fence + String(s.reversed().prefix { $0 == " " })
                    } else {
                        out += Self.escape(s)
                    }
                case .lineBreak:
                    endLink(); close(to: 0); out += "\\\n"
                case .note(let label):
                    out += "[^\(label)]"
                case .image(let alt, let path):
                    endLink(); close(to: 0)
                    let p = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? path
                    out += "![\(Self.escape(alt))](\(p))"
                }
            }
            endLink()
            close(to: 0)
            return out
        }
    }
}
