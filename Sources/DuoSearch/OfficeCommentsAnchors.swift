import Foundation

extension OfficeComments {
    /// PowerPoint anchors (DL-337): a modern comment is on the slide (`pc:sldMkLst`), a shape (`ac:deMkLst` with `ac:spMk`, `picMk`,
    /// `graphicFrameMk`, `grpSpMk` or `cxnSpMk`) or a run of characters in a shape (`ac:txMkLst`, the shape's moniker then `ac:txMk cp len`).
    /// The shape moniker needs the shape's id and its `a16:creationId`, the slide moniker the slide's `p14:creationId`; a slide or shape
    /// without one gets one written (in the slide part). `ac:context`, the hash PowerPoint writes inside `txMk` to re-find a range after
    /// the text moves, is not written (unverified without a PowerPoint sample, C-179).
    enum Anchors {
        static let ac = "http://schemas.microsoft.com/office/drawing/2013/main/command"
        static let pc = "http://schemas.microsoft.com/office/powerpoint/2013/main/command"
        static let monikers: [String: String] = ["sp": "spMk", "pic": "picMk", "graphicFrame": "graphicFrameMk", "grpSp": "grpSpMk", "cxnSp": "cxnSpMk"]

        struct Shape: Equatable {
            var id: String, name: String, kind: String
            var creationId: String?
            var text: String
        }

        /// Every shape of a slide: its id, name, kind and text.
        static func shapes(_ zip: Pptx.Zip, part: String) -> [Shape] {
            guard let root = try? zip.xml(part) else { return [] }
            var out: [Shape] = []
            func visit(_ n: Pptx.Node) {
                for c in n.children {
                    if monikers[c.name] != nil, let nv = c.children.first(where: { $0.name.hasPrefix("nv") }), let pr = nv.first("cNvPr"), let id = pr.attr("id") {
                        var text = ""
                        if c.name == "sp" { text = (c.first("txBody")?.children.filter { $0.name == "p" } ?? []).map { $0.all("t").map(\.value).joined() }.joined(separator: "\n") }
                        else if c.name != "grpSp" && c.name != "cxnSp" { text = c.all("p").map { $0.all("t").map(\.value).joined() }.joined(separator: "\n") }
                        out.append(Shape(id: id, name: pr.attr("name") ?? "", kind: c.name, creationId: pr.all("creationId").first?.attr("id"), text: text))
                    }
                    visit(c)
                }
            }
            visit(root)
            return out
        }

        /// What a comment is anchored to, read from its `p188:cm`.
        struct Read { var kind = "slide"; var shape: Shape?; var cp: Int?; var len: Int?; var text: String?; var lost = false }

        static func read(_ cm: Pptx.Node, shapes: [Shape]) -> Read {
            var r = Read()
            for list in cm.children where list.name == "deMkLst" || list.name == "txMkLst" {
                guard let mk = list.children.first(where: { monikers.values.contains($0.name) }), let id = mk.attr("id") else { continue }
                r.shape = shapes.first { $0.id == id }
                r.kind = "shape"
                if list.name == "txMkLst", let tx = list.first("txMk"), let cp = tx.attr("cp").flatMap(Int.init), let len = tx.attr("len").flatMap(Int.init) {
                    r.kind = "text"; r.cp = cp; r.len = len
                    if let s = r.shape?.text as NSString?, cp >= 0, len > 0, cp + len <= s.length { r.text = s.substring(with: NSRange(location: cp, length: len)) } else { r.lost = true }
                }
                if r.shape == nil { r.lost = true }
            }
            return r
        }

        // MARK: Writing

        static func randomCreationId() -> String { String(UInt32.random(in: 1...UInt32.max)) }

        /// The slide's `p14:creationId` (writing one if it has none).
        static func slideCreationId(_ xml: inout String) -> String {
            if let re = try? NSRegularExpression(pattern: "p14:creationId[^>]*?\\bval=\"(\\d+)\""),
               let m = re.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)) {
                return (xml as NSString).substring(with: m.range(at: 1))
            }
            let id = randomCreationId()
            let ext = "<p:ext uri=\"{BB962C8B-B14F-4D97-AF65-F5344CB8AC3E}\"><p14:creationId xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" val=\"\(id)\"/></p:ext>"
            let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("</p:extLst></p:sld>"), let r = xml.range(of: "</p:extLst>", options: .backwards) { xml.insert(contentsOf: ext, at: r.lowerBound) }
            else if let r = xml.range(of: "</p:sld>", options: .backwards) { xml.insert(contentsOf: "<p:extLst>" + ext + "</p:extLst>", at: r.lowerBound) }
            return id
        }

        /// The shape's `a16:creationId`, written into its `p:cNvPr` when it has none.
        static func shapeCreationId(_ xml: inout String, shape: Shape) throws -> String {
            if let c = shape.creationId { return c }
            guard let re = try? NSRegularExpression(pattern: "<p:cNvPr\\b[^>]*?\\bid=\"\(shape.id)\"[^>]*?(/?)>"),
                  let m = re.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)) else {
                throw Failure("shape \(shape.id) (\(shape.name)) isn't in the slide's XML where Duo can write an id to it")
            }
            let guidv = "{" + UUID().uuidString.uppercased() + "}"
            let ext = "<a:ext uri=\"{FF2B5EF4-FFF2-40B4-BE49-F238E27FC236}\"><a16:creationId xmlns:a16=\"http://schemas.microsoft.com/office/drawing/2014/main\" id=\"\(guidv)\"/></a:ext>"
            let ns = xml as NSString
            let tag = ns.substring(with: m.range)
            if m.range(at: 1).length == 1 {   // `<p:cNvPr … />`: open it
                xml = ns.replacingCharacters(in: m.range, with: String(tag.dropLast(2)) + "><a:extLst>" + ext + "</a:extLst></p:cNvPr>")
            } else {
                let after = NSRange(location: m.range.location + m.range.length, length: ns.length - m.range.location - m.range.length)
                let close = ns.range(of: "</p:cNvPr>", range: after)
                guard close.location != NSNotFound else { throw Failure("damaged shape \(shape.id)") }
                let inner = ns.substring(with: NSRange(location: after.location, length: close.location - after.location))
                if let r = inner.range(of: "</a:extLst>", options: .backwards) {
                    let at = after.location + (inner as NSString).range(of: "</a:extLst>", options: .backwards).location
                    _ = r
                    xml = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: ext)
                } else {
                    xml = ns.replacingCharacters(in: NSRange(location: close.location, length: 0), with: "<a:extLst>" + ext + "</a:extLst>")
                }
            }
            return guidv
        }

        /// The `pc:`/`ac:` monikers of a comment on the slide, a shape or a run of text.
        static func anchorXML(cId: String, sldId: String, shape: Shape?, shapeCid: String?, cp: Int?, len: Int?) -> String {
            let sld = "<pc:docMk xmlns:pc=\"\(pc)\"/><pc:sldMk xmlns:pc=\"\(pc)\" cId=\"\(cId)\" sldId=\"\(sldId)\"/>"
            guard let shape, let shapeCid else { return "<pc:sldMkLst xmlns:pc=\"\(pc)\"><pc:docMk/><pc:sldMk cId=\"\(cId)\" sldId=\"\(sldId)\"/></pc:sldMkLst>" }
            let mk = "<ac:\(monikers[shape.kind] ?? "spMk") id=\"\(shape.id)\" creationId=\"\(shapeCid)\"/>"
            if let cp, let len { return "<ac:txMkLst xmlns:ac=\"\(ac)\">" + sld + mk + "<ac:txMk cp=\"\(cp)\" len=\"\(len)\"/></ac:txMkLst>" }
            return "<ac:deMkLst xmlns:ac=\"\(ac)\">" + sld + mk + "</ac:deMkLst>"
        }

        /// `--at` for a slide: `3` (the slide), `3/Photo` or `3/<shape id>` (a shape), `3/Title/Yields up` (a run of text in it).
        struct Spec { var slide: Int; var shape: String?; var text: String? }
        static func parse(_ at: String) throws -> Spec {
            let parts = at.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            let digits = parts[0].lowercased().replacingOccurrences(of: "slide", with: "").trimmingCharacters(in: .whitespaces)
            guard let n = Int(digits) else { throw Failure("name a slide to comment on: `--at 3` (the slide), `--at 3/Photo` (a shape by name or id), `--at 3/Title/some text` (a run of text in it)") }
            return Spec(slide: n, shape: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil, text: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil)
        }

        static func pick(_ shapes: [Shape], _ key: String, slide: Int) throws -> Shape {
            if let s = shapes.first(where: { $0.id == key }) { return s }
            let named = shapes.filter { $0.name.lowercased() == key.lowercased() }
            if named.count == 1 { return named[0] }
            if named.count > 1 { throw Failure("slide \(slide) has \(named.count) shapes named “\(key)”: use an id (\(named.map(\.id).joined(separator: ", ")))") }
            throw Failure("slide \(slide) has no shape “\(key)”; it has: " + shapes.map { "\($0.id) \($0.name)" }.joined(separator: ", "))
        }
    }
}
