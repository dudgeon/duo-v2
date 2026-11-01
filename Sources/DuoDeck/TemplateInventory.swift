import Foundation

/// `duo2 deck template inventory` (Duo Decks P2, plan.md §4): what is in a pptx, deterministically,
/// so Claude can propose templates from it. The Swift form of
/// `docs/design/duo-decks-study/prototypes/pptx/inventory.py`, plus layout fingerprints and groups.
public enum TemplateInventory {
    public struct Box: Codable, Equatable, Sendable {
        public var x, y, w, h: Double
        public var text: String { "\(Self.n(x)),\(Self.n(y)) \(Self.n(w))x\(Self.n(h))" }
        static func n(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    }

    public struct Placeholder: Codable, Equatable, Sendable {
        public var type: String
        public var idx: Int
        public var name: String
        public var box: Box?
        public var fontSize: Double?
        public var font: String?
        public var autofit: String?
        /// true: bulleted, false: buNone.
        public var bullets: Bool?
        /// Left, top, right, bottom insets in pt.
        public var insets: [Double]
        /// Left margin of the first level in pt (the bullet's hanging indent), line spacing as a
        /// fraction of single, and space before a paragraph in pt.
        public var indent: Double = 0
        public var lineSpacing: Double?
        public var spaceBefore: Double?
        public var key: String { "\(type)@\(idx)" }
    }

    public struct Decoration: Codable, Equatable, Sendable {
        public var name: String
        public var kind: String
        public var box: Box?
        public var text: String?
    }

    public struct Layout: Codable, Equatable, Sendable {
        public var name: String
        public var part: String
        public var master: Int
        public var showMasterShapes: Bool
        public var placeholders: [Placeholder]
        public var decoration: [Decoration]
    }

    public struct ShapeInfo: Codable, Equatable, Sendable {
        public var name: String
        /// placeholder, text, shape, picture, chart, table, group, line, graphicFrame.
        public var kind: String
        public var placeholder: String?
        public var box: Box?
        public var fontSize: Double?
        public var text: String
    }

    public struct SlideInfo: Codable, Equatable, Sendable {
        public var n: Int
        public var layout: String
        public var shapes: [ShapeInfo]
        public var fingerprint: String
        public var hasNotes: Bool
        public var comments: Int
    }

    public struct FontUse: Codable, Equatable, Sendable {
        public var font: String
        public var where_: [String]
        public var google: Bool
        public var substitute: String?
    }

    public struct Group: Codable, Equatable, Sendable {
        public var id: String
        public var fingerprint: String
        public var slides: [Int]
        /// The largest gap, in pt, between matching boxes of the group's slides.
        public var drift: Double
    }

    public struct Near: Codable, Equatable, Sendable {
        public var a: String
        public var b: String
        public var detail: String
        public var drift: Double
        public var extra: [String]
    }

    public struct Report: Codable, Equatable, Sendable {
        public var file: String
        public var slideSize: [Double]
        public var themeName: String
        public var colors: [String: String]
        public var majorFont: String
        public var minorFont: String
        public var fonts: [FontUse]
        public var masters: Int
        public var layouts: [Layout]
        public var slides: [SlideInfo]
        public var groups: [Group]
        public var near: [Near]
    }

    static let pt = 12700.0
    public static let footers: Set<String> = ["dt", "ftr", "sldNum"]
    public static let colorKeys = ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]

    // MARK: reading shapes

    static func tree(_ root: XNode) -> XNode? { root.child("cSld")?.child("spTree") }
    static let shapeNames: Set<String> = ["sp", "pic", "graphicFrame", "grpSp", "cxnSp"]
    static func shapes(_ root: XNode) -> [XNode] { (tree(root)?.children ?? []).filter { shapeNames.contains($0.local) } }

    static func cNvPr(_ s: XNode) -> XNode? {
        for k in ["nvSpPr", "nvPicPr", "nvGraphicFramePr", "nvGrpSpPr", "nvCxnSpPr"] { if let c = s.child(k)?.child("cNvPr") { return c } }
        return nil
    }
    static func name(_ s: XNode) -> String { cNvPr(s)?["name"] ?? "" }
    static func phNode(_ s: XNode) -> XNode? {
        for k in ["nvSpPr", "nvPicPr", "nvGraphicFramePr"] { if let p = s.child(k)?.child("nvPr")?.child("ph") { return p } }
        return nil
    }
    static func phType(_ ph: XNode) -> String { ph["type"] ?? "obj" }
    static func phIdx(_ ph: XNode) -> Int { Int(ph["idx"] ?? "0") ?? 0 }

    static func box(_ s: XNode) -> Box? {
        let x: XNode?
        switch s.local {
        case "graphicFrame": x = s.child("xfrm")
        case "grpSp": x = s.child("grpSpPr")?.child("xfrm")
        default: x = s.child("spPr")?.child("xfrm")
        }
        guard let off = x?.child("off"), let ext = x?.child("ext"),
              let ox = Double(off["x"] ?? ""), let oy = Double(off["y"] ?? ""), let cx = Double(ext["cx"] ?? ""), let cy = Double(ext["cy"] ?? "") else { return nil }
        func r(_ v: Double) -> Double { (v / pt * 10).rounded() / 10 }
        return Box(x: r(ox), y: r(oy), w: r(cx), h: r(cy))
    }

    static func kind(_ s: XNode) -> String {
        if phNode(s) != nil { return "placeholder" }
        switch s.local {
        case "pic": return "picture"
        case "grpSp": return "group"
        case "cxnSp": return "line"
        case "graphicFrame":
            if s.find("tbl") != nil { return "table" }
            if (s.find("graphicData")?["uri"] ?? "").contains("chart") { return "chart" }
            return "graphicFrame"
        default:
            return s.child("nvSpPr")?.child("cNvSpPr")?["txBox"] == "1" || !text(s).isEmpty ? "text" : "shape"
        }
    }

    /// Paragraphs joined by a newline; empty paragraphs dropped.
    static func text(_ s: XNode) -> String {
        guard let tb = s.child("txBody") else { return "" }
        return tb.kids("p").map { $0.findAll("t").map(\.text).joined() }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
    }

    static func lvl1(_ s: XNode?) -> XNode? { s?.child("txBody")?.child("lstStyle")?.child("lvl1pPr") }

    // MARK: the package model

    struct Master { var part: String; var xml: XNode; var theme: XNode?; var layouts: [String] }

    struct Model {
        var pkg: PptxPackage
        var pres: XNode
        var masters: [Master] = []
        var major = "", minor = ""
        var themeName = ""
        var colors: [String: String] = [:]
        var slideParts: [String] = []

        init(_ pkg: PptxPackage) throws {
            self.pkg = pkg
            guard let p = pkg.xml("ppt/presentation.xml") else { throw Deck.Failure(description: "no presentation.xml") }
            pres = p
            for id in p.child("sldMasterIdLst")?.kids("sldMasterId") ?? [] {
                guard let rid = id["r:id"], let rel = pkg.rels(of: "ppt/presentation.xml").first(where: { $0.id == rid }) else { continue }
                let part = pkg.target(of: rel, from: "ppt/presentation.xml")
                guard let mx = pkg.xml(part) else { continue }
                let mrels = pkg.rels(of: part)
                let theme = mrels.first { $0.type == "theme" }.flatMap { pkg.xml(pkg.target(of: $0, from: part)) }
                var layouts: [String] = []
                for l in mx.child("sldLayoutIdLst")?.kids("sldLayoutId") ?? [] {
                    if let rid = l["r:id"], let rel = mrels.first(where: { $0.id == rid }) { layouts.append(pkg.target(of: rel, from: part)) }
                }
                masters.append(Master(part: part, xml: mx, theme: theme, layouts: layouts))
            }
            if let th = masters.first?.theme {
                themeName = th["name"] ?? ""
                if let cs = th.find("clrScheme") {
                    for c in cs.children { if let v = c.children.first { colors[c.local] = v["val"] ?? v["lastClr"] ?? "" } }
                }
                if let fs = th.find("fontScheme") {
                    major = fs.child("majorFont")?.child("latin")?["typeface"] ?? ""
                    minor = fs.child("minorFont")?.child("latin")?["typeface"] ?? ""
                }
            }
            for id in p.child("sldIdLst")?.kids("sldId") ?? [] {
                if let rid = id["r:id"], let rel = pkg.rels(of: "ppt/presentation.xml").first(where: { $0.id == rid }) {
                    slideParts.append(pkg.target(of: rel, from: "ppt/presentation.xml"))
                }
            }
        }

        func layoutPart(named n: String) -> (part: String, master: Int)? {
            for (mi, m) in masters.enumerated() {
                for l in m.layouts where pkg.xml(l)?.child("cSld")?["name"] == n { return (l, mi) }
            }
            return nil
        }
        func masterIndex(ofLayout part: String) -> Int { masters.firstIndex { $0.layouts.contains(part) } ?? 0 }

        func themeFont(_ face: String?, title: Bool) -> String {
            guard let f = face else { return title ? major : minor }
            switch f {
            case "+mj-lt": return major
            case "+mn-lt": return minor
            default: return f
            }
        }

        // The placeholder in `shapes` that a placeholder (type, idx) inherits from.
        static func norm(_ type: String) -> String? {
            switch type {
            case "title", "ctrTitle": return "title"
            case "body", "subTitle", "obj": return "body"
            case "dt", "ftr", "sldNum": return type
            default: return nil
            }
        }
        static func match(_ ph: XNode, in shapes: [XNode]) -> XNode? {
            let idx = phIdx(ph), type = phType(ph)
            let phs = shapes.filter { phNode($0) != nil }
            if let m = phs.first(where: { phIdx(phNode($0)!) == idx && (norm(phType(phNode($0)!)) == norm(type) || idx != 0) }) { return m }
            return phs.first { norm(phType(phNode($0)!)) == norm(type) && norm(type) != nil }
        }

        func resolve(_ ph: XNode, own: XNode, layout: XNode?, master: XNode?) -> (size: Double?, font: String?, autofit: String?, bullets: Bool?, insets: [Double], indent: Double, lineSpacing: Double?, spaceBefore: Double?) {
            let type = phType(ph)
            let isTitle = Self.norm(type) == "title"
            let chain: [XNode?] = [own, layout.flatMap { Self.match(ph, in: TemplateInventory.shapes($0)) }, master.flatMap { Self.match(ph, in: TemplateInventory.shapes($0)) }]
            let style = master?.child("txStyles")?.child(isTitle ? "titleStyle" : (Self.norm(type) == "body" ? "bodyStyle" : "otherStyle"))?.child("lvl1pPr")
            var lvls: [XNode?] = chain.map { lvl1($0) }
            lvls.append(style)
            var size: Double?, face: String?, bullets: Bool?, marL: Double?, lnSpc: Double?, spcBef: Double?
            for l in lvls.compactMap({ $0 }) {
                if marL == nil, let v = l["marL"].flatMap(Double.init) { marL = v / pt }
                if lnSpc == nil, let v = l.child("lnSpc")?.child("spcPct")?["val"].flatMap(Double.init) { lnSpc = v / 100_000 }
                if spcBef == nil, let v = l.child("spcBef")?.child("spcPts")?["val"].flatMap(Double.init) { spcBef = v / 100 }
                if size == nil, let sz = l.child("defRPr")?["sz"].flatMap(Double.init) { size = sz / 100 }
                if face == nil { face = l.child("defRPr")?.child("latin")?["typeface"] }
                if bullets == nil {
                    if l.child("buNone") != nil { bullets = false }
                    else if l.child("buChar") != nil || l.child("buAutoNum") != nil || l.child("buBlip") != nil { bullets = true }
                }
            }
            var autofit: String?
            var inset: [String: Double] = [:]
            for c in chain.compactMap({ $0 }) {
                guard let bp = c.child("txBody")?.child("bodyPr") else { continue }
                if autofit == nil { for t in ["normAutofit", "spAutoFit", "noAutofit"] where bp.child(t) != nil { autofit = t } }
                for k in ["lIns", "tIns", "rIns", "bIns"] where inset[k] == nil { if let v = bp[k].flatMap(Double.init) { inset[k] = v / pt } }
            }
            let insets = [inset["lIns"] ?? 7.2, inset["tIns"] ?? 3.6, inset["rIns"] ?? 7.2, inset["bIns"] ?? 3.6]
            return (size, themeFont(face, title: isTitle), autofit, bullets ?? (Self.norm(type) == "body" ? bullets : false), insets, marL ?? 0, lnSpc, spcBef)
        }

        func placeholderBox(_ ph: XNode, own: XNode, layout: XNode?, master: XNode?) -> Box? {
            if let b = box(own) { return b }
            if let l = layout.flatMap({ Self.match(ph, in: TemplateInventory.shapes($0)) }), let b = box(l) { return b }
            if let m = master.flatMap({ Self.match(ph, in: TemplateInventory.shapes($0)) }), let b = box(m) { return b }
            return nil
        }

        func layoutInfo(_ part: String) -> Layout? {
            guard let lx = pkg.xml(part) else { return nil }
            let mi = masterIndex(ofLayout: part)
            let mx = masters.indices.contains(mi) ? masters[mi].xml : nil
            var phs: [Placeholder] = [], deco: [Decoration] = []
            for s in shapes(lx) {
                if let ph = phNode(s) {
                    let r = resolve(ph, own: s, layout: nil, master: mx)
                    phs.append(Placeholder(type: phType(ph), idx: phIdx(ph), name: name(s), box: placeholderBox(ph, own: s, layout: nil, master: mx),
                                           fontSize: r.size, font: r.font, autofit: r.autofit, bullets: r.bullets, insets: r.insets,
                                           indent: r.indent, lineSpacing: r.lineSpacing, spaceBefore: r.spaceBefore))
                } else {
                    let t = text(s)
                    deco.append(Decoration(name: name(s), kind: kind(s), box: box(s), text: t.isEmpty ? nil : String(t.prefix(60))))
                }
            }
            return Layout(name: lx.child("cSld")?["name"] ?? "", part: part, master: mi, showMasterShapes: lx["showMasterSp"] != "0", placeholders: phs, decoration: deco)
        }
    }

    // MARK: fingerprints

    /// A slide's loose shapes and placeholders reduced to tokens: placeholders as `type@idx`
    /// (footers left out), loose shapes as `kind@gx,gy gwxgh` on a 12 pt grid.
    struct Item { var key: String; var kind: String; var ph: Bool; var box: Box? }

    static func grid(_ v: Double) -> Int { Int((v / 12).rounded()) }

    public static func fingerprint(_ items: [(key: String, kind: String, ph: Bool, box: Box?)]) -> String {
        let phs = items.filter { $0.ph }.sorted { a, b in
            let ai = Int(a.key.split(separator: "@").last ?? "") ?? 0, bi = Int(b.key.split(separator: "@").last ?? "") ?? 0
            return (ai, a.key) < (bi, b.key)
        }.map(\.key)
        let loose = items.filter { !$0.ph }.map { i -> (Int, Int, String) in
            let b = i.box ?? Box(x: 0, y: 0, w: 0, h: 0)
            return (grid(b.y), grid(b.x), "\(i.kind)@\(grid(b.x)),\(grid(b.y)) \(grid(b.w))x\(grid(b.h))")
        }.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }.map(\.2)
        return (phs + loose).joined(separator: phs.isEmpty || loose.isEmpty ? " " : " + ")
    }

    // MARK: read

    public static func read(_ url: URL, slides only: Set<Int>? = nil) throws -> Report {
        let model = try Model(try PptxPackage(url))
        let pkg = model.pkg
        var sw = 0.0, sh = 0.0
        if let sz = model.pres.child("sldSz") { sw = (Double(sz["cx"] ?? "") ?? 0) / pt; sh = (Double(sz["cy"] ?? "") ?? 0) / pt }
        let layouts = model.masters.flatMap { $0.layouts }.compactMap { model.layoutInfo($0) }

        var slides: [SlideInfo] = []
        var items: [Int: [Item]] = [:]
        for (i, part) in model.slideParts.enumerated() {
            let n = i + 1
            if let only, !only.contains(n) { continue }
            guard let sx = pkg.xml(part) else { continue }
            let rels = pkg.rels(of: part)
            let layoutPart = rels.first { $0.type == "slideLayout" }.map { pkg.target(of: $0, from: part) }
            let lx = layoutPart.flatMap { pkg.xml($0) }
            let mx = layoutPart.map { model.masters[model.masterIndex(ofLayout: $0)].xml }
            var infos: [ShapeInfo] = [], its: [Item] = []
            for s in shapes(sx) {
                var b = box(s), size: Double?
                var ph: XNode?
                if let p = phNode(s) {
                    ph = p
                    if let lx { b = model.placeholderBox(p, own: s, layout: lx, master: mx) } else { b = b ?? nil }
                    size = model.resolve(p, own: s, layout: lx, master: mx).size
                }
                if let rpr = s.findAll("rPr").first(where: { $0["sz"] != nil }), let v = rpr["sz"].flatMap(Double.init) { size = v / 100 }
                else if ph == nil, let v = lvl1(s)?.child("defRPr")?["sz"].flatMap(Double.init) { size = v / 100 }
                let k = kind(s)
                let t = text(s).replacingOccurrences(of: "\n", with: " | ")
                let key = ph.map { "\(phType($0))@\(phIdx($0))" }
                infos.append(ShapeInfo(name: name(s), kind: k, placeholder: key, box: b, fontSize: size, text: t.count > 60 ? String(t.prefix(60)) + "…" : t))
                if let p = ph, footers.contains(phType(p)) { continue }
                its.append(Item(key: key ?? k, kind: k, ph: ph != nil, box: b))
            }
            items[n] = its
            let notes = rels.first { $0.type == "notesSlide" }.flatMap { pkg.xml(pkg.target(of: $0, from: part)) }
            let hasNotes = notes.map { nx in shapes(nx).contains { phNode($0).map { phType($0) == "body" } ?? false && !text($0).isEmpty } } ?? false
            var comments = 0
            for r in rels where r.type == "comments" { comments += pkg.xml(pkg.target(of: r, from: part))?.findAll("cm").count ?? 0 }
            slides.append(SlideInfo(n: n, layout: lx?.child("cSld")?["name"] ?? "", shapes: infos,
                                    fingerprint: fingerprint(its.map { ($0.key, $0.kind, $0.ph, $0.box) }), hasNotes: hasNotes, comments: comments))
        }

        // Groups: identical fingerprints, in order of first appearance.
        var groups: [Group] = []
        for s in slides {
            if let g = groups.firstIndex(where: { $0.fingerprint == s.fingerprint }) { groups[g].slides.append(s.n) }
            else { groups.append(Group(id: "G\(groups.count + 1)", fingerprint: s.fingerprint, slides: [s.n], drift: 0)) }
        }
        for g in groups.indices where groups[g].slides.count > 1 {
            let base = items[groups[g].slides[0]] ?? []
            groups[g].drift = groups[g].slides.dropFirst().map { drift(base, items[$0] ?? []).drift }.max() ?? 0
        }
        // Near groups: the smaller one's boxes all find a partner in the larger within 36 pt.
        var near: [Near] = []
        for a in groups.indices {
            for b in groups.indices where b > a {
                let ia = items[groups[a].slides[0]] ?? [], ib = items[groups[b].slides[0]] ?? []
                let d = drift(ia, ib)
                guard d.matched, d.drift <= 36, d.extra.count <= 2 else { continue }
                let more = ia.count > ib.count ? groups[a].id : groups[b].id
                let detail = d.extra.isEmpty
                    ? "same boxes; positions differ by up to \(Box.n(d.drift)) pt"
                    : "\(more) has \(d.extra.count) extra box\(d.extra.count == 1 ? "" : "es") (\(d.extra.joined(separator: ", "))); positions differ by up to \(Box.n(d.drift)) pt"
                near.append(Near(a: groups[a].id, b: groups[b].id, detail: detail, drift: d.drift, extra: d.extra))
            }
        }

        // Fonts: the theme's, then any typeface named in a layout, master or slide.
        var uses: [String: [String]] = [:]
        func use(_ f: String, _ w: String) {
            guard !f.isEmpty, !f.hasPrefix("+") else { return }
            if !(uses[f] ?? []).contains(w) { uses[f, default: []].append(w) }
        }
        use(model.major, "theme heading"); use(model.minor, "theme body")
        for part in pkg.parts.keys.sorted() where part.hasPrefix("ppt/slideLayouts/slideLayout") || part.hasPrefix("ppt/slideMasters/slideMaster") || part.hasPrefix("ppt/slides/slide") {
            guard part.hasSuffix(".xml"), let x = pkg.xml(part) else { continue }
            let w = part.hasPrefix("ppt/slides/") ? "slides" : "layouts and masters"
            for l in x.findAll("latin") { if let t = l["typeface"] { use(t, w) } }
        }
        let fonts = uses.keys.sorted().map { f in
            FontUse(font: f, where_: uses[f]!, google: GoogleFontsData.isGoogle(f), substitute: GoogleFontsData.isGoogle(f) ? nil : GoogleFontsData.substitute(for: f))
        }
        return Report(file: url.lastPathComponent, slideSize: [sw, sh], themeName: model.themeName, colors: model.colors,
                      majorFont: model.major, minorFont: model.minor, fonts: fonts, masters: model.masters.count, layouts: layouts,
                      slides: slides, groups: groups, near: near)
    }

    /// Matches the boxes of the shorter list to boxes in the longer one (same key, nearest first) and
    /// returns the biggest gap between a pair, and the keys left over in the longer list.
    static func drift(_ a: [Item], _ b: [Item]) -> (matched: Bool, drift: Double, extra: [String]) {
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        var free = large.indices.map { $0 }
        var worst = 0.0
        for s in small {
            let sb = s.box ?? Box(x: 0, y: 0, w: 0, h: 0)
            var best: (Int, Double)?
            for i in free where large[i].key == s.key || (!s.ph && !large[i].ph && large[i].kind == s.kind) {
                let lb = large[i].box ?? Box(x: 0, y: 0, w: 0, h: 0)
                let d = max(abs(sb.x - lb.x), abs(sb.y - lb.y), abs(sb.w - lb.w), abs(sb.h - lb.h))
                if best == nil || d < best!.1 { best = (i, d) }
            }
            guard let (i, d) = best else { return (false, 0, []) }
            free.removeAll { $0 == i }
            worst = max(worst, d)
        }
        return (true, (worst * 10).rounded() / 10, free.map { large[$0].ph ? large[$0].key : large[$0].kind })
    }

    // MARK: text

    public static func render(_ r: Report) -> String {
        var o: [String] = []
        o.append("file: \(r.file)")
        let ratio = r.slideSize[1] > 0 ? r.slideSize[0] / r.slideSize[1] : 0
        o.append("slide size: \(Box.n(r.slideSize[0])) x \(Box.n(r.slideSize[1])) pt\(abs(ratio - 16.0 / 9) < 0.01 ? " (16:9)" : abs(ratio - 4.0 / 3) < 0.01 ? " (4:3)" : "")")
        o.append("theme \"\(r.themeName)\": " + PptxModelColors.order(r.colors).map { "\($0) \(r.colors[$0] ?? "")" }.joined(separator: ", "))
        o.append("fonts:")
        for f in r.fonts {
            let flag = f.google ? "in Google Fonts" : "NOT in Google Fonts" + (f.substitute.map { "; closest: \($0)" } ?? "")
            o.append("  \(f.font) (\(f.where_.joined(separator: ", "))): \(flag)")
        }
        o.append("layouts (\(r.layouts.count)\(r.masters > 1 ? ", \(r.masters) masters" : "")):")
        for l in r.layouts {
            o.append("  \(l.name)\(l.showMasterShapes ? "" : " (no master shapes)")")
            for p in l.placeholders {
                var s = "    \(p.key) \"\(p.name)\"" + (p.box.map { " box \($0.text)" } ?? "")
                if let z = p.fontSize { s += " size \(Box.n(z))" }
                if let a = p.autofit { s += " autofit \(a)" }
                if let b = p.bullets { s += b ? " bullets" : " buNone" }
                o.append(s)
            }
            for d in l.decoration { o.append("    decoration \(d.kind) \"\(d.name)\"" + (d.box.map { " box \($0.text)" } ?? "") + (d.text.map { " \"\($0)\"" } ?? "")) }
        }
        o.append("slides (\(r.slides.count)):")
        for s in r.slides {
            o.append("  \(s.n) on \(s.layout)\(s.hasNotes ? ", notes" : "")\(s.comments > 0 ? ", \(s.comments) comment\(s.comments == 1 ? "" : "s")" : "")")
            o.append("    fingerprint: \(s.fingerprint)")
            for sh in s.shapes {
                var l = "    \(sh.placeholder ?? sh.kind) \"\(sh.name)\"" + (sh.box.map { " box \($0.text)" } ?? "")
                if let z = sh.fontSize { l += " size \(Box.n(z))" }
                if !sh.text.isEmpty { l += " \"\(sh.text)\"" }
                o.append(l)
            }
        }
        o.append("groups (identical fingerprints):")
        for g in r.groups {
            o.append("  \(g.id) slide\(g.slides.count == 1 ? "" : "s") \(g.slides.map(String.init).joined(separator: ", "))\(g.slides.count > 1 ? " (positions differ by up to \(Box.n(g.drift)) pt)" : ""): \(g.fingerprint)")
        }
        if !r.near.isEmpty {
            o.append("near groups:")
            for n in r.near { o.append("  \(n.a) ~ \(n.b): \(n.detail)") }
        }
        return o.joined(separator: "\n")
    }

    public static func json(_ r: Report) throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(r), as: UTF8.self)
    }

    /// `3,7` or `3-5,9`.
    public static func parseSlides(_ s: String) throws -> Set<Int> {
        var out = Set<Int>()
        for part in s.split(separator: ",") {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            guard ends.count == 1 || ends.count == 2, ends.allSatisfy({ $0 > 0 }) else { throw Deck.Failure(description: "--slides takes numbers like 3,7 or 3-5, not \"\(s)\"") }
            out.formUnion(ends.count == 1 ? [ends[0]] : Set(ends[0]...max(ends[0], ends[1])))
        }
        return out
    }
}

enum PptxModelColors {
    static func order(_ c: [String: String]) -> [String] {
        let known = TemplateInventory.colorKeys.filter { c[$0] != nil }
        return known + c.keys.filter { !known.contains($0) }.sorted()
    }
}
