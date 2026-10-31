import Foundation

extension Deck {
    public struct InspectedShape: Equatable, Sendable {
        /// sp, pic or graphicFrame.
        public var element: String
        public var type: String
        public var idx: Int
        /// An sp or pic with its own `spPr/xfrm` (a placeholder should have none).
        public var ownBox: Bool
        public var text: String
        /// Rows and columns when this is a table.
        public var table: (rows: Int, cols: Int)?
        public var cropped: Bool
        public static func == (a: Self, b: Self) -> Bool {
            a.element == b.element && a.type == b.type && a.idx == b.idx && a.ownBox == b.ownBox && a.text == b.text
                && a.table?.rows == b.table?.rows && a.table?.cols == b.table?.cols && a.cropped == b.cropped
        }
    }

    public struct InspectedSlide: Sendable {
        public var layout: String
        public var shapes: [InspectedShape]
        public var notes: String?
    }

    /// Reads an exported deck back: each slide's layout name, placeholders (by type and idx) and
    /// notes. For checks and for `duo2 deck` to prove an export.
    public static func inspect(_ url: URL) throws -> (slides: [InspectedSlide], customProperties: [String: String]) {
        let zip = try Pptx.Zip(url)
        guard let pres = try zip.xml("ppt/presentation.xml") else { throw Failure(description: "no presentation.xml") }
        let presRels = try Pptx.rels(zip, "ppt/presentation.xml")
        var out: [InspectedSlide] = []
        for sld in pres.all("sldId") {
            guard let part = sld.attr("r:id").flatMap({ presRels[$0] }), let root = try zip.xml(part) else { continue }
            let rels = try Pptx.rels(zip, part)
            var layoutName = ""
            if let lp = rels.values.first(where: { $0.contains("slideLayouts/") }), let lx = try zip.xml(lp) { layoutName = lx.first("cSld")?.attr("name") ?? "" }
            var notes: String?
            if let np = rels.values.first(where: { $0.contains("notesSlides/") }), let nx = try zip.xml(np) {
                let body = nx.all("sp").first { $0.first("ph", deep: true)?.attr("type") == "body" }
                notes = body.map { Pptx.text($0) }
            }
            var shapes: [InspectedShape] = []
            for el in root.first("cSld")?.first("spTree")?.children ?? [] where ["sp", "pic", "graphicFrame"].contains(el.name) {
                guard let ph = el.first("ph", deep: true) else { continue }
                let tbl = el.first("tbl", deep: true)
                shapes.append(InspectedShape(
                    element: el.name, type: ph.attr("type") ?? "obj", idx: Int(ph.attr("idx") ?? "0") ?? 0,
                    ownBox: el.first("spPr")?.first("xfrm") != nil, text: Pptx.text(el),
                    table: tbl.map { t in (t.all("tr").count, t.first("tblGrid")?.all("gridCol").count ?? 0) },
                    cropped: el.first("blipFill")?.first("srcRect") != nil))
            }
            out.append(InspectedSlide(layout: layoutName, shapes: shapes, notes: notes))
        }
        var props: [String: String] = [:]
        for p in try zip.xml("docProps/custom.xml")?.all("property") ?? [] { props[p.attr("name") ?? ""] = p.all("lpwstr").first?.value }
        return (out, props)
    }
}
