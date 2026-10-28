import Foundation

// `duo2 doc layout` (F-378): a Word document's geometry as the file declares it, with no renderer:
// each section's page size and margins (so the text width), each table's declared width and columns
// against the room it has, each picture's size, and a warning for whatever is wider than its room.
// No page numbers: Duo has no layout engine and the viewer doesn't paginate (DL-162). Read only.
// Sizes are in points (twips / 20).
extension Docx {
    public struct Section: Codable, Equatable, Sendable {
        /// 1-based, in document order.
        public var index: Int
        public var pageWidth: Double
        public var pageHeight: Double
        public var orientation: String
        public var marginLeft: Double
        public var marginRight: Double
        public var marginTop: Double
        public var marginBottom: Double
        /// The room for text: the page width less the side margins and gutter.
        public var textWidth: Double
        /// True when the file gave no page size (Word's Letter defaults are assumed).
        public var assumed: Bool
    }

    public struct TableLayout: Codable, Equatable, Sendable {
        /// 1-based, in document order (a table inside a cell follows the one that holds it).
        public var index: Int
        public var section: Int
        /// The paragraphs before it, counted as `doc outline` counts them.
        public var afterParagraph: Int
        /// 0 for a table in the body, 1 and up for a table in a cell.
        public var depth: Int
        /// The first cell's text.
        public var label: String
        public var rows: Int
        /// The column widths of `w:tblGrid`.
        public var columns: [Double]
        public var gridWidth: Double
        /// `w:tblW`: `dxa`, `pct`, `auto` or `nil` when absent.
        public var widthType: String
        /// The declared width in points (dxa only).
        public var declaredWidth: Double?
        public var indent: Double
        /// The room it sits in: the section's text width, or the width of the cell that holds it.
        public var room: Double
        public var warnings: [String]
    }

    public struct ImageLayout: Codable, Equatable, Sendable {
        public var index: Int
        public var section: Int
        /// The paragraph that holds it, counted as `doc outline` counts.
        public var paragraph: Int
        public var name: String
        public var alt: String
        public var width: Double
        public var height: Double
        /// `inline` or `anchored` (floating).
        public var placement: String
        public var room: Double
        public var warnings: [String]
    }

    public struct Layout: Codable, Equatable, Sendable {
        public var sections: [Section]
        public var tables: [TableLayout]
        public var images: [ImageLayout]
        public var warnings: [String] { tables.flatMap(\.warnings) + images.flatMap(\.warnings) }
    }

    static let layoutSlack = 1.0   // a point: rounding in the file

    public static func layout(_ url: URL) throws -> Layout {
        let zip: Pptx.Zip
        do { zip = try Pptx.Zip(url) } catch { throw classify(url) }
        guard let doc = try? zip.xml("word/document.xml"), let body = doc.first("body") else {
            throw zip.entries.isEmpty ? Failure.damaged : Failure.notWord
        }
        func pt(_ n: Pptx.Node?, _ k: String) -> Double? { n?.attr(k).flatMap(Double.init).map { $0 / 20 } }
        func section(_ s: Pptx.Node?, index: Int) -> Section {
            let sz = s?.first("pgSz"), mar = s?.first("pgMar")
            let w = pt(sz, "w:w"), h = pt(sz, "w:h")
            let l = pt(mar, "w:left") ?? 72, r = pt(mar, "w:right") ?? 72, g = pt(mar, "w:gutter") ?? 0
            let pw = w ?? 612, ph = h ?? 792
            let landscape = sz?.attr("w:orient") == "landscape" || pw > ph
            return Section(index: index, pageWidth: pw, pageHeight: ph, orientation: landscape ? "landscape" : "portrait",
                           marginLeft: l, marginRight: r, marginTop: pt(mar, "w:top") ?? 72, marginBottom: pt(mar, "w:bottom") ?? 72,
                           textWidth: max(0, pw - l - r - g), assumed: w == nil)
        }
        // A section's properties sit in the last paragraph that belongs to it; the body's own sectPr ends the last.
        var sections: [Section] = []
        func collect(_ n: Pptx.Node) {
            for c in n.children {
                if c.name == "Fallback" { continue }
                if c.name == "sectPr", n.name == "pPr" || n === body { sections.append(section(c, index: sections.count + 1)) }
                collect(c)
            }
        }
        collect(body)
        if sections.isEmpty { sections = [section(nil, index: 1)] }

        var tables: [TableLayout] = [], images: [ImageLayout] = []
        var paragraphs = 0, sectionIndex = 1
        func room(_ s: Int) -> Double { sections[min(max(s, 1), sections.count) - 1].textWidth }
        func visit(_ n: Pptx.Node, limit: Double?, depth: Int) {
            for c in n.children {
                switch c.name {
                case "Fallback": continue
                case "p":
                    paragraphs += 1
                    visit(c, limit: limit, depth: depth)
                    if c.first("pPr")?.first("sectPr") != nil { sectionIndex += 1 }
                    continue
                case "tbl":
                    var t = table(c, index: tables.count + 1, depth: depth, limit: limit ?? room(sectionIndex))
                    t.section = sectionIndex; t.afterParagraph = paragraphs
                    tables.append(t)
                    // Rows, cells; a cell gives its own width to what it holds.
                    for tr in c.children where tr.name == "tr" {
                        for tc in tr.children where tc.name == "tc" {
                            let w = tc.first("tcPr")?.first("tcW")
                            let cell = w?.attr("w:type") == "dxa" ? pt(w, "w:w") : nil
                            visit(tc, limit: cell ?? limit ?? room(sectionIndex), depth: depth + 1)
                        }
                    }
                    continue
                case "inline", "anchor":
                    if let ext = c.first("extent"), let cx = ext.attr("cx").flatMap(Double.init), let cy = ext.attr("cy").flatMap(Double.init) {
                        let limit = limit ?? room(sectionIndex)
                        let doc = c.first("docPr")
                        var im = ImageLayout(index: images.count + 1, section: sectionIndex, paragraph: paragraphs,
                                             name: doc?.attr("name") ?? "", alt: doc?.attr("descr") ?? "",
                                             width: cx / 12700, height: cy / 12700, placement: c.name == "inline" ? "inline" : "anchored",
                                             room: limit, warnings: [])
                        if im.width > limit + layoutSlack {
                            im.warnings.append("Image \(im.index) (\(im.name.isEmpty ? "unnamed" : im.name)): \(Self.pts(im.width)) wide, wider than the \(Self.pts(limit)) it has" + (limit < room(sectionIndex) ? " in its cell" : " between the margins"))
                        }
                        images.append(im)
                    }
                    continue
                default: break
                }
                visit(c, limit: limit, depth: depth)
            }
        }
        visit(body, limit: nil, depth: 0)
        return Layout(sections: sections, tables: tables, images: images)
    }

    private static func table(_ tbl: Pptx.Node, index: Int, depth: Int, limit: Double) -> TableLayout {
        func pt(_ n: Pptx.Node?, _ k: String) -> Double? { n?.attr(k).flatMap(Double.init).map { $0 / 20 } }
        let props = tbl.first("tblPr")
        let w = props?.first("tblW")
        let type = w?.attr("w:type") ?? (w == nil ? "nil" : "dxa")
        let declared = type == "dxa" ? pt(w, "w:w") : nil
        let cols = (tbl.first("tblGrid")?.children.filter { $0.name == "gridCol" } ?? []).map { pt($0, "w:w") ?? 0 }
        let grid = cols.reduce(0, +)
        let indent = pt(props?.first("tblInd"), "w:w") ?? 0
        let rows = tbl.children.filter { $0.name == "tr" }.count
        let label = tbl.first("tr")?.first("tc").map { SendFormatLite.line(plain($0, accepted: true)) } ?? ""
        var t = TableLayout(index: index, section: 0, afterParagraph: 0, depth: depth, label: label, rows: rows, columns: cols, gridWidth: grid,
                            widthType: type, declaredWidth: declared, indent: indent, room: limit, warnings: [])
        let name = "Table \(index)" + (label.isEmpty ? "" : " (“\(label)”)")
        if cols.isEmpty { t.warnings.append("\(name): no column grid; Word and Google Docs will guess the widths") }
        if type == "pct" { t.warnings.append("\(name): width is a percentage; Google Docs may not honour it (use DXA widths)") }
        if let d = declared, grid > 0, abs(d - grid) > layoutSlack {
            t.warnings.append("\(name): declared width \(pts(d)) differs from its columns' \(pts(grid)); make them match")
        }
        let used = max(declared ?? 0, grid) + indent
        if used > limit + layoutSlack { t.warnings.append("\(name): \(pts(used)) wide, wider than the \(pts(limit)) it has") }
        return t
    }

    public static func pts(_ v: Double) -> String { "\(String(format: "%g", (v * 10).rounded() / 10)) pt" }
}

/// One line of a table's first cell, as a label.
enum SendFormatLite {
    static func line(_ s: String) -> String {
        let one = s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return one.count > 40 ? String(one.prefix(39)) + "…" : one
    }
}
