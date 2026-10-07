import Compression
import Foundation

/// A PowerPoint deck as the agent reads it (ENH-12, DL-121): each slide's shapes with their OOXML
/// ids (`p:cNvPr`), names, groups, text and boxes, tables as tab-separated rows, charts with their
/// series, and the speaker notes. The viewer stamps the same ids on what it draws, so a shape the
/// user picks and the outline name the same thing. Ported from `Spikes/PptxViewer/pptx_outline.py`.
public enum Pptx {
    public struct Box: Codable, Equatable, Sendable {
        public var x, y, w, h: Int
        public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    }
    public struct Series: Codable, Equatable, Sendable {
        public var name: String
        public var values: [Double]
        public init(name: String, values: [Double]) { self.name = name; self.values = values }
    }

    public struct Shape: Codable, Equatable, Sendable {
        public var id: Int
        public var name: String
        /// shape, picture, table, chart, frame, group or connector.
        public var type: String
        /// The groups it sits in, outermost first.
        public var inGroups: [String]
        public var text: String?
        /// In slide pixels, 96 per inch, as the viewer draws. Nil for a placeholder that takes its
        /// place from the layout.
        public var box: Box?
        public var chart: String?
        public var series: [Series]?
    }

    public struct Slide: Codable, Equatable, Sendable {
        public var number: Int
        public var shapes: [Shape]
        public var notes: String
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    /// Every slide, or only `slide` (counted from 1).
    /// How many slides the deck lists, read from its slide list alone: the viewer draws an empty
    /// frame per slide while it renders (DL-132 j).
    public static func slideCount(_ url: URL) -> Int? {
        guard let zip = try? Zip(url), let pres = try? zip.xml("ppt/presentation.xml") else { return nil }
        return pres.all("sldId").count
    }

    public static func outline(_ url: URL, slide only: Int? = nil) throws -> [Slide] {
        let zip = try Zip(url)
        guard let pres = try zip.xml("ppt/presentation.xml") else { throw Failure(description: "not a PowerPoint deck: no ppt/presentation.xml") }
        let presRels = try rels(zip, "ppt/presentation.xml")
        let parts = pres.all("sldId").compactMap { $0.attr("r:id").flatMap { presRels[$0] } }
        var out: [Slide] = []
        for (i, part) in parts.enumerated() where only == nil || only == i + 1 {
            guard let root = try zip.xml(part), let tree = root.first("cSld")?.first("spTree") else { continue }
            let slideRels = try rels(zip, part)
            var notes = ""
            if let n = slideRels.values.first(where: { $0.contains("notesSlide") }), let nx = try zip.xml(n) {
                // The notes page's body placeholder; the slide image placeholder has no text.
                notes = nx.first("cSld").map(text) ?? ""
            }
            out.append(Slide(number: i + 1, shapes: try shapes(tree, zip: zip, rels: slideRels, groups: []), notes: notes))
        }
        return out
    }

    static let kinds = ["sp": "shape", "pic": "picture", "graphicFrame": "frame", "grpSp": "group", "cxnSp": "connector"]

    static func shapes(_ tree: Node, zip: Zip, rels: [String: String], groups: [String]) throws -> [Shape] {
        var out: [Shape] = []
        for el in tree.children {
            guard let kind = kinds[el.name], let nv = el.first("cNvPr", deep: true) else { continue }
            var s = Shape(id: Int(nv.attr("id") ?? "") ?? 0, name: nv.attr("name") ?? "", type: kind, inGroups: groups)
            if kind == "frame" {
                if let tbl = el.first("tbl", deep: true) {
                    s.type = "table"
                    s.text = tbl.all("tr").map { $0.children.filter { $0.name == "tc" }.map(text).joined(separator: "\t") }.joined(separator: "\n")
                } else if let ch = el.first("chart", deep: true), let target = ch.attr("r:id").flatMap({ rels[$0] }), let cx = try zip.xml(target) {
                    s.type = "chart"
                    s.chart = cx.first("plotArea", deep: true)?.children.first { $0.name.hasSuffix("Chart") }.map { String($0.name.dropLast(5)) }
                    s.series = cx.all("ser").map { ser in
                        Series(name: ser.first("tx")?.first("v", deep: true)?.value ?? "",
                               values: ser.first("val")?.all("v").compactMap { Double($0.value) } ?? [])
                    }
                }
            } else if kind != "group" {
                let t = text(el)
                if !t.isEmpty { s.text = t }
            }
            s.box = box(el)
            out.append(s)
            if kind == "group" { out += try shapes(el, zip: zip, rels: rels, groups: groups + [s.name]) }
        }
        return out
    }

    /// Paragraphs joined by newlines, runs by nothing (a:p, a:t).
    static func text(_ el: Node) -> String {
        el.all("p").map { $0.all("t").map(\.value).joined() }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func box(_ el: Node) -> Box? {
        // The shape's own transform: spPr/xfrm, grpSpPr/xfrm, or a frame's p:xfrm.
        let xfrm = el.children.first { $0.name == "spPr" || $0.name == "grpSpPr" }?.first("xfrm") ?? el.first("xfrm")
        guard let off = xfrm?.first("off"), let ext = xfrm?.first("ext"),
              let x = Double(off.attr("x") ?? ""), let y = Double(off.attr("y") ?? ""),
              let w = Double(ext.attr("cx") ?? ""), let h = Double(ext.attr("cy") ?? "") else { return nil }
        let px = 914_400.0 / 96
        return Box(x: Int((x / px).rounded()), y: Int((y / px).rounded()), w: Int((w / px).rounded()), h: Int((h / px).rounded()))
    }

    /// A part's relationships: id → part path inside the zip.
    static func rels(_ zip: Zip, _ part: String) throws -> [String: String] {
        let dir = (part as NSString).deletingLastPathComponent
        guard let r = try zip.xml("\(dir)/_rels/\((part as NSString).lastPathComponent).rels") else { return [:] }
        var out: [String: String] = [:]
        for rel in r.all("Relationship") where rel.attr("TargetMode") != "External" {
            guard let id = rel.attr("Id"), let target = rel.attr("Target") else { continue }
            out[id] = target.hasPrefix("/") ? String(target.dropFirst()) : normalize("\(dir)/\(target)")
        }
        return out
    }

    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for p in path.split(separator: "/") {
            if p == ".." { _ = parts.popLast() } else if p != "." { parts.append(p) }
        }
        return parts.joined(separator: "/")
    }

    // MARK: XML

    /// A parsed element: local name (prefix dropped), attributes as written, children, text.
    final class Node {
        let name: String
        let attrs: [String: String]
        var children: [Node] = []
        var value = ""
        init(_ name: String, _ attrs: [String: String]) { self.name = name; self.attrs = attrs }

        func attr(_ k: String) -> String? { attrs[k] }
        func first(_ name: String, deep: Bool = false) -> Node? {
            if let c = children.first(where: { $0.name == name }) { return c }
            return deep ? children.lazy.compactMap { $0.first(name, deep: true) }.first : nil
        }
        /// Every descendant with this name, in document order.
        func all(_ name: String) -> [Node] {
            children.flatMap { ($0.name == name ? [$0] : []) + $0.all(name) }
        }
    }

    final class Parser: NSObject, XMLParserDelegate {
        var stack: [Node] = [Node("#doc", [:])]
        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            let local = name.split(separator: ":").last.map(String.init) ?? name
            let n = Node(local, attributes)
            stack.last?.children.append(n)
            stack.append(n)
        }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
        func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.value += s }
        static func parse(_ data: Data) -> Node? {
            let d = Parser(), p = XMLParser(data: data)
            p.delegate = d
            p.shouldProcessNamespaces = false
            p.shouldResolveExternalEntities = false   // a deck is untrusted input
            return p.parse() ? d.stack.first?.children.first : nil
        }
    }

    // MARK: Zip

    /// Reads entries of a zip (stored or deflated) through its central directory. Foundation can't
    /// unzip; Compression's ZLIB is raw DEFLATE, which is what zip uses. No zip64, no encryption.
    struct Zip {
        struct Entry { let method: UInt16; let compressed: Int; let size: Int; let offset: Int }
        let data: Data
        var entries: [String: Entry] = [:]
        static let maxEntry = 64 * 1024 * 1024

        init(_ url: URL) throws {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
            let d = data
            func u16(_ i: Int) -> Int { Int(d[d.startIndex + i]) | Int(d[d.startIndex + i + 1]) << 8 }
            func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
            // End of central directory: the last PK\5\6 within the final 64 KB + 22 bytes.
            var eocd = -1
            var i = d.count - 22
            while i >= max(0, d.count - 65_557) {
                if u32(i) == 0x0605_4B50 { eocd = i; break }
                i -= 1
            }
            guard eocd >= 0 else { throw Failure(description: "not a zip file") }
            let count = u16(eocd + 10)
            var p = u32(eocd + 16)
            for _ in 0..<count {
                guard p + 46 <= d.count, u32(p) == 0x0201_4B50 else { throw Failure(description: "damaged zip directory") }
                let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
                guard p + 46 + nameLen <= d.count else { throw Failure(description: "damaged zip directory") }
                let name = String(decoding: d[(d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLen)], as: UTF8.self)
                entries[name] = Entry(method: UInt16(u16(p + 10)), compressed: u32(p + 20), size: u32(p + 24), offset: u32(p + 42))
                p += 46 + nameLen + extraLen + commentLen
            }
        }

        func read(_ name: String) throws -> Data? {
            guard let e = entries[name] else { return nil }
            let d = data
            func u16(_ i: Int) -> Int { Int(d[d.startIndex + i]) | Int(d[d.startIndex + i + 1]) << 8 }
            guard e.size <= Self.maxEntry, e.offset + 30 <= d.count else { throw Failure(description: "\(name) is too large or damaged") }
            let start = e.offset + 30 + u16(e.offset + 26) + u16(e.offset + 28)
            guard start + e.compressed <= d.count else { throw Failure(description: "\(name) is damaged") }
            let raw = d[(d.startIndex + start)..<(d.startIndex + start + e.compressed)]
            switch e.method {
            case 0: return Data(raw)
            case 8:
                if e.size == 0 { return Data() }
                var out = Data(count: e.size)
                let n = out.withUnsafeMutableBytes { dst in
                    raw.withUnsafeBytes { src in
                        compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, e.size,
                                                  src.bindMemory(to: UInt8.self).baseAddress!, e.compressed, nil, COMPRESSION_ZLIB)
                    }
                }
                guard n == e.size else { throw Failure(description: "\(name) didn't inflate") }
                return out
            default: throw Failure(description: "\(name) uses zip method \(e.method)")
            }
        }

        func xml(_ name: String) throws -> Node? { try read(name).flatMap(Parser.parse) }
    }
}
