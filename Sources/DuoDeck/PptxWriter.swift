import DuoSearch
import CryptoKit
import Foundation

extension Deck {
    /// Exports a checked deck to pptx bytes (DL-270): opens the pack's pptx, adds one slide per
    /// deck slide on the template's named layout, and fills placeholders by idx with no geometry of
    /// its own. Footer and slide-number placeholders are cloned from the layout (without their
    /// boxes), notes go in a notes slide (a notes master is added when the pack has none), and the
    /// deck's sha-256 is stored as the custom property `duoSourceSha`. The same deck and pack give
    /// the same bytes.
    public static func export(deck: URL, packDirs: [URL], measureFit: Bool = true) throws -> Data {
        let checked = try check(deck: deck, packDirs: packDirs, measureFit: measureFit)
        guard checked.problems.isEmpty, let pack = checked.pack else {
            throw Failure(description: report(deck.path, checked.problems))
        }
        let source = try Data(contentsOf: deck)
        return try PptxWriter(pack: pack, front: checked.parsed.front, slides: checked.slides, deckDir: deck.deletingLastPathComponent(),
                              sourceSha: SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()).write()
    }
}

// MARK: - the writer

struct PptxWriter {
    let pack: Deck.Pack
    let front: [String: String]
    let slides: [Deck.Slide]
    let deckDir: URL
    let sourceSha: String

    struct LayoutPh {
        var name: String
        var type: String
        var idx: Int
        var attrs: String
        var box: (x: Int, y: Int, cx: Int, cy: Int)?
        var text: String?
    }
    struct Layout { var part: String; var name: String; var phs: [LayoutPh] }

    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"
    static let ns = "xmlns:a=\"\(nsA)\" xmlns:r=\"\(nsR)\" xmlns:p=\"\(nsP)\""
    static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    static let grp = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func matches(_ pattern: String, in s: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))?.matches(in: s, range: NSRange(s.startIndex..., in: s)) ?? []
    }
    static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
        Range(m.range(at: i), in: s).map { String(s[$0]) }
    }

    // MARK: layouts

    func layouts(_ zip: Pptx.Zip) throws -> [Layout] {
        var out: [Layout] = []
        for part in zip.entries.keys.filter({ $0.hasPrefix("ppt/slideLayouts/slideLayout") && $0.hasSuffix(".xml") }).sorted() {
            guard let data = try zip.read(part), let s = String(data: data, encoding: .utf8) else { continue }
            let name = Self.matches("<p:cSld(?:\\s+name=\"([^\"]*)\")?", in: s).first.flatMap { Self.group($0, 1, in: s) } ?? ""
            var phs: [LayoutPh] = []
            for m in Self.matches("<p:(sp|pic|graphicFrame)>(.*?)</p:\\1>", in: s) {
                guard let body = Self.group(m, 2, in: s), let ph = Self.matches("<p:ph((?:\\s+[A-Za-z]+=\"[^\"]*\")*)\\s*/>", in: body).first,
                      let attrs = Self.group(ph, 1, in: body) else { continue }
                let type = Self.matches("type=\"([^\"]*)\"", in: attrs).first.flatMap { Self.group($0, 1, in: attrs) } ?? "obj"
                let idx = Self.matches("idx=\"(\\d+)\"", in: attrs).first.flatMap { Self.group($0, 1, in: attrs) }.flatMap(Int.init) ?? 0
                let nm = Self.matches("<p:cNvPr[^>]*name=\"([^\"]*)\"", in: body).first.flatMap { Self.group($0, 1, in: body) } ?? "Placeholder"
                var box: (Int, Int, Int, Int)?
                if let x = Self.matches("<a:off x=\"(-?\\d+)\" y=\"(-?\\d+)\"/>\\s*<a:ext cx=\"(\\d+)\" cy=\"(\\d+)\"/>", in: body).first {
                    let v = (1...4).compactMap { Self.group(x, $0, in: body).flatMap(Int.init) }
                    if v.count == 4 { box = (v[0], v[1], v[2], v[3]) }
                }
                let text = Self.matches("<a:t>([^<]*)</a:t>", in: body).first.flatMap { Self.group($0, 1, in: body) }
                phs.append(LayoutPh(name: nm, type: type, idx: idx, attrs: attrs, box: box, text: text))
            }
            out.append(Layout(part: part, name: name, phs: phs))
        }
        return out
    }

    // MARK: text

    /// `**bold**` runs, as the prototype splits them.
    static func runs(_ text: String) -> String {
        var out = "", rest = Substring(text)
        func plain(_ t: Substring) { if !t.isEmpty { out += "<a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(esc(String(t)))</a:t></a:r>" } }
        while let open = rest.range(of: "**") {
            let after = rest[open.upperBound...]
            if let close = after.range(of: "**"), !after[..<close.lowerBound].contains("*"), !after[..<close.lowerBound].isEmpty {
                plain(rest[..<open.lowerBound])
                out += "<a:r><a:rPr lang=\"en-US\" b=\"1\" dirty=\"0\"/><a:t>\(esc(String(after[..<close.lowerBound])))</a:t></a:r>"
                rest = after[close.upperBound...]
            } else {
                plain(rest[..<open.upperBound]); rest = after
            }
        }
        plain(rest)
        return out
    }

    static func para(_ text: String, level: Int = 0) -> String {
        "<a:p>\(level > 0 ? "<a:pPr lvl=\"\(level)\"/>" : "")\(runs(text))</a:p>"
    }

    // MARK: images

    static func imageSize(_ d: Data) -> (w: Int, h: Int)? {
        let b = [UInt8](d)
        if b.count > 24, b[0] == 0x89, b[1] == 0x50 {
            func be(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
            return (be(16), be(20))
        }
        if b.count > 4, b[0] == 0xFF, b[1] == 0xD8 {
            var i = 2
            while i + 9 < b.count {
                guard b[i] == 0xFF else { i += 1; continue }
                let m = b[i + 1]
                if m == 0xFF { i += 1; continue }
                if m >= 0xC0, m <= 0xCF, m != 0xC4, m != 0xC8, m != 0xCC { return (Int(b[i + 7]) << 8 | Int(b[i + 8]), Int(b[i + 5]) << 8 | Int(b[i + 6])) }
                i += 2 + (Int(b[i + 2]) << 8 | Int(b[i + 3]))
            }
        }
        return nil
    }

    // MARK: write

    func write() throws -> Data {
        let zip = try Pptx.Zip(pack.pptx)
        let layoutList = try layouts(zip)
        var ct = String(decoding: try zip.read("[Content_Types].xml") ?? Data(), as: UTF8.self)
        var presXML = String(decoding: try zip.read("ppt/presentation.xml") ?? Data(), as: UTF8.self)
        var presRels = String(decoding: try zip.read("ppt/_rels/presentation.xml.rels") ?? Data(), as: UTF8.self)
        var rootRels = String(decoding: try zip.read("_rels/.rels") ?? Data(), as: UTF8.self)
        var core = String(decoding: try zip.read("docProps/core.xml") ?? Data(), as: UTF8.self)
        guard presXML.contains("<p:sldIdLst/>") else { throw Deck.Failure(description: "\(pack.pptx.lastPathComponent): the pack already has slides; a pack holds layouts only") }

        var newParts: [(String, Data)] = []
        var overrides: [String] = []
        var defaults: [String: String] = [:]
        var nextRel = ((Self.matches("Id=\"rId(\\d+)\"", in: presRels).compactMap { Self.group($0, 1, in: presRels).flatMap(Int.init) }.max()) ?? 0) + 1
        var mediaFor: [String: String] = [:]   // asset path -> media part
        var mediaCount = 0
        var sldIds = "", newRels = ""
        let footer = front["footer"]
        let hasNotesMaster = zip.entries.keys.contains { $0.hasPrefix("ppt/notesMasters/") }
        let anyNotes = slides.contains { !$0.notes.isEmpty }
        var notesMasterPart = "ppt/notesMasters/notesMaster1.xml"
        if let existing = zip.entries.keys.filter({ $0.hasPrefix("ppt/notesMasters/notesMaster") && $0.hasSuffix(".xml") }).sorted().first { notesMasterPart = existing }

        func override(_ part: String, _ type: String) { overrides.append("<Override PartName=\"/\(part)\" ContentType=\"\(type)\"/>") }

        if anyNotes && !hasNotesMaster {
            guard zip.entries["ppt/theme/theme1.xml"] != nil else { throw Deck.Failure(description: "pack has no theme") }
            var theme = 2
            while zip.entries["ppt/theme/theme\(theme).xml"] != nil { theme += 1 }
            newParts.append((notesMasterPart, Data(Self.notesMaster.utf8)))
            newParts.append(("ppt/notesMasters/_rels/notesMaster1.xml.rels", Data(Self.rels([("rId1", "theme", "../theme/theme\(theme).xml")]).utf8)))
            newParts.append(("ppt/theme/theme\(theme).xml", try zip.read("ppt/theme/theme1.xml") ?? Data()))
            override(notesMasterPart, "application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml")
            override("ppt/theme/theme\(theme).xml", "application/vnd.openxmlformats-officedocument.theme+xml")
        }
        var notesMasterRel: String?
        // A pack made from a real deck already lists its notes master in presentation.xml: don't list a second one.
        let presHasNotesMaster = presXML.contains("<p:notesMasterIdLst>")
        if anyNotes && presHasNotesMaster {
            notesMasterRel = "existing"
        } else if anyNotes {
            notesMasterRel = "rId\(nextRel)"; nextRel += 1
            newRels += "<Relationship Id=\"\(notesMasterRel!)\" Type=\"\(Self.relBase)/notesMaster\" Target=\"notesMasters/\((notesMasterPart as NSString).lastPathComponent)\"/>"
        }

        for (n, slide) in slides.enumerated() {
            let num = n + 1
            guard let template = pack.template(slide.template) else { continue }
            guard let layout = layoutList.first(where: { $0.name == template.layout }) else {
                throw Deck.Failure(description: "slide \(num) (\(slide.template)): \(pack.pptx.lastPathComponent) has no layout \"\(template.layout)\"")
            }
            var shapes = "", id = 2
            var slideRels: [(String, String, String)] = [("rId1", "slideLayout", "../slideLayouts/\((layout.part as NSString).lastPathComponent)")]
            func rid() -> String { "rId\(slideRels.count + 1)" }

            for ph in layout.phs where !["dt", "ftr", "sldNum"].contains(ph.type) {
                guard let spec = template.slots.first(where: { $0.idx == ph.idx }), let got = slide.slot(spec.name) else { continue }
                let nv = "<p:cNvPr id=\"\(id)\" name=\"\(Self.esc(ph.name))\"/>"
                let phTag = "<p:nvPr><p:ph\(ph.attrs)/></p:nvPr>"
                // An empty slot (a notice, not an error): text and bullets keep their placeholder, empty, so an
                // editor shows where text goes; a picture or table has nothing to draw and is left out.
                if got.lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    if ["text", "number", "bullets"].contains(spec.kind) {
                        shapes += "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>\(phTag)</p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"en-US\"/></a:p></p:txBody></p:sp>"
                        id += 1
                    }
                    continue
                }
                switch spec.kind {
                case "text", "number":
                    let text = got.lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                    shapes += "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>\(phTag)</p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(Self.para(text))</p:txBody></p:sp>"
                case "bullets":
                    let paras = got.lines.map { l -> String in
                        Self.para(String(l.trimmingCharacters(in: .whitespaces).dropFirst(2)), level: Deck.bulletIndent(l) / 2)
                    }.joined()
                    shapes += "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>\(phTag)</p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(paras)</p:txBody></p:sp>"
                case "image":
                    guard let img = Deck.imageLine(got.lines[0]) else { continue }
                    let file = deckDir.appending(path: img.path)
                    let data = try Data(contentsOf: file)
                    guard let size = Self.imageSize(data) else { throw Deck.Failure(description: "slide \(num): \(img.path) is not a PNG or JPEG") }
                    let ext = file.pathExtension.lowercased() == "jpg" ? "jpeg" : file.pathExtension.lowercased()
                    defaults[ext] = ext == "png" ? "image/png" : "image/jpeg"
                    let media: String
                    if let m = mediaFor[img.path] { media = m } else {
                        mediaCount += 1
                        media = "ppt/media/image\(mediaCount).\(file.pathExtension.lowercased())"
                        mediaFor[img.path] = media
                        newParts.append((media, data))
                    }
                    let r = rid()
                    slideRels.append((r, "image", "../media/\((media as NSString).lastPathComponent)"))
                    // Crop to fill: trim the longer side so the picture has the placeholder's aspect.
                    var crop = ""
                    if let b = ph.box, b.cy > 0, size.h > 0 {
                        let box = Double(b.cx) / Double(b.cy), im = Double(size.w) / Double(size.h)
                        if im > box + 0.0005 {
                            let t = Int(((1 - box / im) / 2 * 100_000).rounded()); crop = "<a:srcRect l=\"\(t)\" r=\"\(t)\"/>"
                        } else if im < box - 0.0005 {
                            let t = Int(((1 - im / box) / 2 * 100_000).rounded()); crop = "<a:srcRect t=\"\(t)\" b=\"\(t)\"/>"
                        }
                    }
                    shapes += "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(Self.esc(ph.name))\" descr=\"\(Self.esc(img.alt))\"/><p:cNvPicPr><a:picLocks noGrp=\"1\" noChangeAspect=\"1\"/></p:cNvPicPr>\(phTag)</p:nvPicPr><p:blipFill><a:blip r:embed=\"\(r)\"/>\(crop)<a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr/></p:pic>"
                case "table":
                    guard let b = ph.box else { throw Deck.Failure(description: "slide \(num): the layout's table placeholder has no box") }
                    let rows = got.lines.filter { $0.hasPrefix("|") && !Deck.isSeparatorRow($0) }
                        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
                    let cols = rows.first?.count ?? 1
                    let colW = b.cx / cols, rowH = min(370_840, b.cy / max(rows.count, 1))   // compact rows, as python-pptx draws them
                    let grid = (0..<cols).map { "<a:gridCol w=\"\($0 == cols - 1 ? b.cx - colW * (cols - 1) : colW)\"/>" }.joined()
                    let trs = rows.map { row -> String in
                        "<a:tr h=\"\(rowH)\">" + (0..<cols).map { c -> String in
                            let t = c < row.count ? row[c] : ""
                            return "<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>\(t.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : Self.para(t))</a:txBody><a:tcPr/></a:tc>"
                        }.joined() + "</a:tr>"
                    }.joined()
                    shapes += "<p:graphicFrame><p:nvGraphicFramePr>\(nv)<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr>\(phTag)</p:nvGraphicFramePr><p:xfrm><a:off x=\"\(b.x)\" y=\"\(b.y)\"/><a:ext cx=\"\(b.cx)\" cy=\"\(rowH * rows.count)\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr firstRow=\"1\" bandRow=\"1\"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr><a:tblGrid>\(grid)</a:tblGrid>\(trs)</a:tbl></a:graphicData></a:graphic></p:graphicFrame>"
                default: continue
                }
                id += 1
            }
            // Footer and slide number: the layout's placeholders, without their boxes, so they
            // inherit position and look from the layout (F-466: python-pptx drops them).
            for ph in layout.phs where ph.type == "ftr" || ph.type == "sldNum" {
                let nv = "<p:cNvPr id=\"\(id)\" name=\"\(Self.esc(ph.name))\"/>"
                let body: String
                if ph.type == "ftr" {
                    let t = footer ?? ph.text.map { $0.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">") } ?? ""
                    body = t.isEmpty ? "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>" : Self.para(t)
                } else {
                    body = "<a:p><a:fld id=\"{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}\" type=\"slidenum\"><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\u{2039}#\u{203A}</a:t></a:fld><a:endParaRPr lang=\"en-US\"/></a:p>"
                }
                shapes += "<p:sp><p:nvSpPr>\(nv)<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph\(ph.attrs)/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(body)</p:txBody></p:sp>"
                id += 1
            }

            let slidePart = "ppt/slides/slide\(num).xml"
            var notesXML: String?
            if !slide.notes.isEmpty, notesMasterRel != nil {
                let rId = rid()
                slideRels.append((rId, "notesSlide", "../notesSlides/notesSlide\(num).xml"))
                let paras = slide.notes.map { Self.para($0) }.joined()
                let notes = Self.head + "<p:notes \(Self.ns)><p:cSld><p:spTree>\(Self.grp)<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp><p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(paras)</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
                notesXML = notes
                override("ppt/notesSlides/notesSlide\(num).xml", "application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml")
            }
            let xml = Self.head + "<p:sld \(Self.ns)><p:cSld><p:spTree>\(Self.grp)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
            newParts.append((slidePart, Data(xml.utf8)))
            newParts.append(("ppt/slides/_rels/slide\(num).xml.rels", Data(Self.rels(slideRels).utf8)))
            if let notes = notesXML {
                newParts.append(("ppt/notesSlides/notesSlide\(num).xml", Data(notes.utf8)))
                newParts.append(("ppt/notesSlides/_rels/notesSlide\(num).xml.rels", Data(Self.rels([
                    ("rId1", "notesMaster", "../notesMasters/\((notesMasterPart as NSString).lastPathComponent)"),
                    ("rId2", "slide", "../slides/slide\(num).xml"),
                ]).utf8)))
            }
            override(slidePart, "application/vnd.openxmlformats-officedocument.presentationml.slide+xml")
            let r = "rId\(nextRel)"; nextRel += 1
            newRels += "<Relationship Id=\"\(r)\" Type=\"\(Self.relBase)/slide\" Target=\"slides/slide\(num).xml\"/>"
            sldIds += "<p:sldId id=\"\(255 + num)\" r:id=\"\(r)\"/>"
        }

        // custom property: the sha-256 of the deck's Markdown
        newParts.append(("docProps/custom.xml", Data((Self.head + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/custom-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><property fmtid=\"{D5CDD505-2E9C-101B-9397-08002B2CF9AE}\" pid=\"2\" name=\"duoSourceSha\"><vt:lpwstr>\(sourceSha)</vt:lpwstr></property></Properties>").utf8)))
        override("docProps/custom.xml", "application/vnd.openxmlformats-officedocument.custom-properties+xml")
        let customRel = "rId\(((Self.matches("Id=\"rId(\\d+)\"", in: rootRels).compactMap { Self.group($0, 1, in: rootRels).flatMap(Int.init) }.max()) ?? 0) + 1)"
        rootRels = rootRels.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"\(customRel)\" Type=\"\(Self.relBase)/custom-properties\" Target=\"docProps/custom.xml\"/></Relationships>")

        let defaultsXML = defaults.keys.sorted().filter { !ct.contains("Extension=\"\($0)\"") }.map { "<Default Extension=\"\($0)\" ContentType=\"\(defaults[$0]!)\"/>" }.joined()
        ct = ct.replacingOccurrences(of: "</Types>", with: defaultsXML + overrides.joined() + "</Types>")
        presRels = presRels.replacingOccurrences(of: "</Relationships>", with: newRels + "</Relationships>")
        let nmList = notesMasterRel.flatMap { $0 == "existing" ? nil : "<p:notesMasterIdLst><p:notesMasterId r:id=\"\($0)\"/></p:notesMasterIdLst>" } ?? ""
        presXML = presXML.replacingOccurrences(of: "<p:sldIdLst/>", with: nmList + "<p:sldIdLst>\(sldIds)</p:sldIdLst>")
        if let t = front["title"], let r = core.range(of: "<dc:title>.*?</dc:title>", options: .regularExpression) {
            core.replaceSubrange(r, with: "<dc:title>\(Self.esc(t))</dc:title>")
        }

        var out = ZipWriter()
        let replaced: [String: String] = ["[Content_Types].xml": ct, "ppt/presentation.xml": presXML, "ppt/_rels/presentation.xml.rels": presRels,
                                          "_rels/.rels": rootRels, "docProps/core.xml": core]
        for (name, _) in zip.entries.sorted(by: { ($0.value.offset, $0.key) < ($1.value.offset, $1.key) }) {
            if let r = replaced[name] { out.add(name, Data(r.utf8)) } else if let d = try zip.read(name) { out.add(name, d) }
        }
        for (name, data) in newParts { out.add(name, data) }
        return out.finish()
    }

    static func rels(_ items: [(String, String, String)]) -> String {
        head + "<Relationships xmlns=\"\(relNS)\">" + items.map { "<Relationship Id=\"\($0.0)\" Type=\"\(relBase)/\($0.1)\" Target=\"\($0.2)\"/>" }.joined() + "</Relationships>"
    }

    static let notesMaster = head + "<p:notesMaster \(ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg><p:spTree>\(grp)"
        + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\" idx=\"2\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"1143000\"/><a:ext cx=\"5486400\" cy=\"3086100\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln w=\"12700\"><a:solidFill><a:prstClr val=\"black\"/></a:solidFill></a:ln></p:spPr></p:sp>"
        + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" sz=\"quarter\" idx=\"3\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"4400550\"/><a:ext cx=\"5486400\" cy=\"3600450\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\"/><a:lstStyle/><a:p><a:pPr lvl=\"0\"/><a:r><a:rPr lang=\"en-US\"/><a:t>Click to edit Master text styles</a:t></a:r></a:p></p:txBody></p:sp>"
        + "</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
        + "<p:notesStyle><a:lvl1pPr marL=\"0\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\"><a:defRPr sz=\"1200\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl1pPr></p:notesStyle></p:notesMaster>"
}
