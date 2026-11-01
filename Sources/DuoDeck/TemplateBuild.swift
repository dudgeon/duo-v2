import DuoSearch
import Foundation

/// `duo2 deck template build <pack>` (plan.md §4 step 3, lifecycle M3): makes `<pack>.pptx` from the
/// pack's definition and its source deck.
///
/// The definition (`<pack>.md`) says, per template, where its layout comes from:
/// - `layout: <name>`: an existing layout of the source (kept as it is);
/// - `from-slide: N`: a slide of loose boxes, **promoted** into a new layout (slot boxes become
///   placeholders with idx 13 and up and the slide's run properties as the layout's list style;
///   every other shape becomes layout decoration). Each slot says which box with `shape: <name>`;
/// - `shape-slide: N` with `layout:`: the layout is kept and gains placeholders for slots that name
///   a `shape:` (or a `box: x y w h` in pt) it doesn't have, which is how optional slots (`optional:
///   true`) are added.
/// A template may take its slides from another deck with its own `source: <pptx>`.
///
/// The frontmatter's `source: <pptx>` is the deck the theme, masters and layouts are copied from;
/// without it, an existing `<pack>.pptx` is amended in place (what `deck import` does).
extension Deck {
    public struct BuildResult: Sendable {
        public var pptx: URL
        public var bytes: Int
        /// The definition with its `# duo` lines filled in.
        public var definition: String
        public var definitionChanged: Bool
        /// Structure problems stop the write.
        public var problems: [Problem]
        /// Limits that don't fit their box: reported, but the files are still written.
        public var fitProblems: [Problem]
        public var notes: [String]
        public var written: Bool
    }

    static func titleCase(_ name: String) -> String {
        name.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Raw lines of a template's yaml block, for rewriting the `# duo` lines in place.
    struct RawBlock { var name: String; var start: Int; var end: Int }   // body lines [start, end)

    static func rawBlocks(_ lines: [String]) -> [RawBlock] {
        var out: [RawBlock] = []
        var i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("## ") else { i += 1; continue }
            let name = lines[i].dropFirst(3).trimmingCharacters(in: .whitespaces)
            i += 1
            while i < lines.count, !lines[i].hasPrefix("```"), !lines[i].hasPrefix("## ") { i += 1 }
            guard i < lines.count, lines[i].hasPrefix("```yaml") else { continue }
            i += 1
            let start = i
            while i < lines.count, !lines[i].hasPrefix("```") { i += 1 }
            out.append(RawBlock(name: name, start: start, end: i))
        }
        return out
    }

    static func duoLine(_ key: String, _ value: String) -> String {
        let head = "\(key): \(value)"
        return head.padding(toLength: max(head.count + 2, 39), withPad: " ", startingAt: 0) + "# duo"
    }

    static func setIdx(_ line: String, _ idx: Int) -> String {
        if let r = line.range(of: #"idx:\s*-?\d+"#, options: .regularExpression) { return line.replacingCharacters(in: r, with: "idx: \(idx)") }
        if let b = line.firstIndex(of: "{") { return line.replacingCharacters(in: b...b, with: "{idx: \(idx), ") }
        return line
    }

    static func resolveFile(_ path: String, near md: URL) -> URL {
        let p = (path as NSString).expandingTildeInPath
        return p.hasPrefix("/") ? URL(fileURLWithPath: p) : md.deletingLastPathComponent().appending(path: p).standardizedFileURL
    }

    // MARK: build

    public static func buildPack(md: URL, write: Bool = true) throws -> BuildResult {
        let text = try String(contentsOf: md, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        let packName = md.deletingPathExtension().lastPathComponent
        let pack = try loadPack(md: md, name: packName)
        let blocks = rawBlocks(lines)
        var problems: [Problem] = [], fitProblems: [Problem] = [], notes: [String] = []
        func line(of t: String) -> Int { (blocks.first { $0.name == t }.map { $0.start } ?? 0) + 1 }
        func slotLine(_ t: String, _ s: String) -> Int {
            guard let b = blocks.first(where: { $0.name == t }) else { return 1 }
            for i in b.start..<b.end where lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(s + ":") { return i + 1 }
            return b.start + 1
        }

        // the base package
        var base: PptxPackage
        var prune: Bool
        let pptxURL = pack.pptx
        if let s = pack.front["source"], !s.isEmpty {
            let su = resolveFile(s, near: md)
            guard FileManager.default.fileExists(atPath: su.path) else { throw Failure(description: "\(md.lastPathComponent):1: source: \(s) isn't there") }
            base = try PptxPackage(su); prune = true
        } else if FileManager.default.fileExists(atPath: pptxURL.path) {
            base = try PptxPackage(pptxURL); prune = false
        } else {
            throw Failure(description: "\(md.lastPathComponent): the frontmatter needs source: <a pptx> (the deck to take the theme and layouts from), because \(pptxURL.lastPathComponent) doesn't exist yet")
        }
        let baseModel = try TemplateInventory.Model(base)
        var pkg = base
        var donors: [String: (PptxPackage, TemplateInventory.Model)] = [:]
        func donor(for t: Template) throws -> (pkg: PptxPackage, model: TemplateInventory.Model, same: Bool)? {
            guard let s = t.source else { return prune ? (base, baseModel, true) : nil }
            let u = resolveFile(s, near: md)
            if let d = donors[u.path] { return (d.0, d.1, false) }
            guard FileManager.default.fileExists(atPath: u.path) else { throw Failure(description: "\(md.lastPathComponent):\(line(of: t.name)): \(t.name): source: \(s) isn't there") }
            let p = try PptxPackage(u)
            let m = try TemplateInventory.Model(p)
            donors[u.path] = (p, m)
            return (p, m, false)
        }

        // which existing layouts are used
        var keepLayouts = Set<String>()
        var keepMasters = Set<String>()
        for t in pack.templates where t.fromSlide == nil {
            guard !t.layout.isEmpty else {
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): needs layout: <an existing layout> or from-slide: <a slide to promote>")); continue
            }
            if let (part, mi) = baseModel.layoutPart(named: t.layout) { keepLayouts.insert(part); keepMasters.insert(baseModel.masters[mi].part) }
            else {
                let names = baseModel.masters.flatMap { $0.layouts }.compactMap { base.xml($0)?.child("cSld")?["name"] }
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): no layout \"\(t.layout)\" in the source; its layouts are \(names.joined(separator: ", "))"))
            }
        }
        // promotions need a master of the donor slide's layout
        struct Promo { var t: Template; var slidePart: String; var donorPkg: PptxPackage; var donorModel: TemplateInventory.Model; var same: Bool; var masterPart: String; var layoutName: String }
        var promos: [Promo] = []
        let marked = markedLayouts(lines, blocks)
        for t in pack.templates {
            guard let n = t.fromSlide else { continue }
            guard let d = try donor(for: t) else {
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): from-slide needs a source: the pack's frontmatter, or this template's own source: <pptx>")); continue
            }
            guard d.model.slideParts.indices.contains(n - 1) else {
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): from-slide: \(n), but the source has \(d.model.slideParts.count) slides")); continue
            }
            let sp = d.model.slideParts[n - 1]
            let lp = d.pkg.related(sp, type: "slideLayout").first
            var mp = lp.map { d.model.masters[d.model.masterIndex(ofLayout: $0)].part }
            if !d.same { mp = baseModel.masters.first?.part }
            guard let mpart = mp ?? baseModel.masters.first?.part else {
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): the source has no slide master")); continue
            }
            keepMasters.insert(mpart)
            promos.append(Promo(t: t, slidePart: sp, donorPkg: d.pkg, donorModel: d.model, same: d.same, masterPart: mpart,
                                layoutName: marked[t.name] ?? titleCase(t.name)))
        }
        if !problems.isEmpty { return BuildResult(pptx: pptxURL, bytes: 0, definition: text, definitionChanged: false, problems: problems, fitProblems: [], notes: [], written: false) }

        // strip the slides, then prune
        stripSlides(&pkg)
        if prune { pruneLayouts(&pkg, keep: keepLayouts, keepMasters: keepMasters) }

        // amend: optional (and other) slots the layout doesn't have yet
        let curModel = try TemplateInventory.Model(pkg)
        var resolvedIdx: [String: [String: Int]] = [:]   // template -> slot -> idx
        for t in pack.templates where t.fromSlide == nil {
            guard let lp = curModel.layoutPart(named: t.layout)?.part, let lx = pkg.xml(lp) else { continue }
            let existing = TemplateInventory.shapes(lx).compactMap { TemplateInventory.phNode($0) }.map(TemplateInventory.phIdx)
            var used = Set(existing)
            var changed = false
            for s in t.slots where (s.shape != nil || s.box != nil) && !existing.contains(s.idx) {
                var idx = s.idx
                if idx == 0 || used.contains(idx) || (10...12).contains(idx) { idx = nextIdx(used) }
                used.insert(idx)
                do {
                    guard let node = try slotPlaceholder(s, template: t, idx: idx, shapeSlide: t.shapeSlide, donor: try donor(for: t), pkg: &pkg, layoutPart: lp, notes: &notes, line: slotLine(t.name, s.name)) else {
                        problems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): shape-slide is needed to find shape \"\(s.shape ?? "")\"")); continue
                    }
                    lx.child("cSld")?.child("spTree")?.children.append(node)
                    changed = true
                    resolvedIdx[t.name, default: [:]][s.name] = idx
                    notes.append("\(t.name): added optional placeholder \(s.name) (idx \(idx)) to layout \"\(t.layout)\"")
                } catch let f as Failure { problems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): \(f.description)")) }
            }
            if changed { renumber(lx); pkg.set(lp, lx) }
        }

        // promote
        for p in promos {
            do {
                let r = try promote(p.t, slidePart: p.slidePart, donorPkg: p.donorPkg, donorModel: p.donorModel, same: p.same, masterPart: p.masterPart,
                                    layoutName: p.layoutName, pkg: &pkg, notes: &notes)
                resolvedIdx[p.t.name, default: [:]] = r
            } catch let f as Failure { problems.append(Problem(line: line(of: p.t.name), message: "\(p.t.name): \(f.description)")) }
        }
        if !problems.isEmpty { return BuildResult(pptx: pptxURL, bytes: 0, definition: text, definitionChanged: false, problems: problems, fitProblems: [], notes: notes, written: false) }

        cleanMetadata(&pkg)
        pkg.collectGarbage()

        // validate the definition against what was built
        let finalModel = try TemplateInventory.Model(pkg)
        var fingerprints: [String: String] = [:]
        var layoutNames: [String: String] = [:]
        for t in pack.templates {
            let lname = t.fromSlide != nil ? (promos.first { $0.t.name == t.name }?.layoutName ?? t.layout) : t.layout
            layoutNames[t.name] = lname
            guard let lp = finalModel.layoutPart(named: lname)?.part, let info = finalModel.layoutInfo(lp) else {
                problems.append(Problem(line: line(of: t.name), message: "\(t.name): layout \"\(lname)\" isn't in the built pptx")); continue
            }
            let phs = info.placeholders.filter { !TemplateInventory.footers.contains($0.type) }
            fingerprints[t.name] = phs.sorted { ($0.idx, $0.type) < ($1.idx, $1.type) }.map(\.key).joined(separator: " ")
            for s in t.slots {
                let idx = resolvedIdx[t.name]?[s.name] ?? s.idx
                guard let ph = info.placeholders.first(where: { $0.idx == idx }) else {
                    problems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): unknown idx \(idx); layout \"\(lname)\" has " + info.placeholders.map { "\($0.idx) (\($0.type))" }.joined(separator: ", ")))
                    continue
                }
                let bad: Set<String>
                switch s.kind {
                case "image": bad = ["title", "ctrTitle", "subTitle", "body", "tbl", "chart", "dt", "ftr", "sldNum"]
                case "table": bad = ["title", "ctrTitle", "subTitle", "body", "pic", "chart", "dt", "ftr", "sldNum"]
                case "bullets": bad = ["pic", "tbl", "chart", "media", "dt", "ftr", "sldNum", "title", "ctrTitle"]
                default: bad = ["pic", "tbl", "chart", "media"]
                }
                if bad.contains(ph.type) {
                    problems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): kind \(s.kind) doesn't fit placeholder idx \(idx), which is type \(ph.type)"))
                    continue
                }
                if s.kind == "bullets", ph.bullets == false {
                    problems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): kind bullets, but placeholder idx \(idx) has no bullets (buNone); use kind text, or give the layout's placeholder bullets"))
                    continue
                }
                if ["text", "number", "bullets"].contains(s.kind), let m = s.max {
                    if let msg = TemplateFit.limitTooHigh(max: m, kind: s.kind, in: ph, bulleted: s.kind == "bullets", paragraphs: s.kind == "bullets" ? (s.items ?? 1) : 1) {
                        fitProblems.append(Problem(line: slotLine(t.name, s.name), message: "\(t.name).\(s.name): \(msg)"))
                    }
                }
            }
        }
        if !problems.isEmpty { return BuildResult(pptx: pptxURL, bytes: 0, definition: text, definitionChanged: false, problems: problems, fitProblems: fitProblems, notes: notes, written: false) }

        // the definition's # duo lines
        for b in blocks.reversed() {
            guard let t = pack.template(b.name) else { continue }
            var body = Array(lines[b.start..<b.end])
            var haveLayout = false, haveFp = false
            for i in body.indices {
                let l = body[i]
                if !l.hasPrefix(" "), !l.hasPrefix("\t") {
                    if l.hasPrefix("layout:") { body[i] = duoLine("layout", layoutNames[t.name] ?? t.layout); haveLayout = true }
                    else if l.hasPrefix("fingerprint:") { body[i] = duoLine("fingerprint", fingerprints[t.name] ?? ""); haveFp = true }
                } else if let c = l.firstIndex(of: ":"), l.contains("{") {
                    let sname = l[..<c].trimmingCharacters(in: .whitespaces)
                    if let idx = resolvedIdx[t.name]?[sname] { body[i] = setIdx(l, idx) }
                }
            }
            var head: [String] = []
            if !haveLayout { head.append(duoLine("layout", layoutNames[t.name] ?? t.layout)) }
            if !haveFp { head.append(duoLine("fingerprint", fingerprints[t.name] ?? "")) }
            lines.replaceSubrange(b.start..<b.end, with: head + body)
        }
        let newText = lines.joined(separator: "\n")
        let data = pkg.write()
        if write {
            try FileManager.default.createDirectory(at: pptxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: pptxURL, options: .atomic)
            if newText != text { try newText.write(to: md, atomically: true, encoding: .utf8) }
        }
        return BuildResult(pptx: pptxURL, bytes: data.count, definition: newText, definitionChanged: newText != text, problems: [], fitProblems: fitProblems.sorted { $0.line < $1.line }, notes: notes, written: write)
    }

    /// `layout: Name   # duo` lines already in the definition, by template (those are outputs of an
    /// earlier build, so a promotion keeps its layout's name).
    static func markedLayouts(_ lines: [String], _ blocks: [RawBlock]) -> [String: String] {
        var out: [String: String] = [:]
        for b in blocks {
            for i in b.start..<b.end where lines[i].hasPrefix("layout:") && lines[i].contains("# duo") {
                var v = String(lines[i].dropFirst(7))
                if let r = v.range(of: " #") { v = String(v[..<r.lowerBound]) }
                out[b.name] = v.trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }

    static func nextIdx(_ used: Set<Int>) -> Int {
        var i = 13
        while used.contains(i) { i += 1 }
        return i
    }

    // MARK: package surgery

    static func stripSlides(_ pkg: inout PptxPackage) {
        guard let pres = pkg.xml("ppt/presentation.xml") else { return }
        pres.child("sldIdLst")?.children = []
        if pres.child("sldIdLst") == nil {
            // keep the schema order: after the masters (and the notes master, handout master) and before sldSz
            let at = pres.children.firstIndex { ["sldSz", "notesSz"].contains($0.local) } ?? pres.children.count
            pres.children.insert(XNode("p:sldIdLst"), at: at)
        }
        // sections name slide ids
        for ext in pres.child("extLst")?.children ?? [] where ext.children.contains(where: { $0.local == "sectionLst" }) {
            pres.child("extLst")?.children.removeAll { $0 === ext }
        }
        if pres.child("extLst")?.children.isEmpty == true { pres.removeChildren("extLst") }
        pres.removeChildren("custShowLst")
        pkg.set("ppt/presentation.xml", pres)
        var rels = pkg.rels(of: "ppt/presentation.xml")
        rels.removeAll { ["slide", "commentAuthors", "authors", "printerSettings"].contains($0.type) }
        pkg.setRels(of: "ppt/presentation.xml", rels)
    }

    static func pruneLayouts(_ pkg: inout PptxPackage, keep: Set<String>, keepMasters: Set<String>) {
        guard let model = try? TemplateInventory.Model(pkg), let pres = pkg.xml("ppt/presentation.xml") else { return }
        var presRels = pkg.rels(of: "ppt/presentation.xml")
        for m in model.masters {
            if !keepMasters.contains(m.part) {
                guard let rel = presRels.first(where: { pkg.target(of: $0, from: "ppt/presentation.xml") == m.part }) else { continue }
                pres.child("sldMasterIdLst")?.children.removeAll { $0["r:id"] == rel.id }
                presRels.removeAll { $0.id == rel.id }
                continue
            }
            var rels = pkg.rels(of: m.part)
            let mx = m.xml
            for l in m.layouts where !keep.contains(l) {
                guard let rel = rels.first(where: { pkg.target(of: $0, from: m.part) == l }) else { continue }
                mx.child("sldLayoutIdLst")?.children.removeAll { $0["r:id"] == rel.id }
                rels.removeAll { $0.id == rel.id }
            }
            pkg.set(m.part, mx)
            pkg.setRels(of: m.part, rels)
        }
        pkg.set("ppt/presentation.xml", pres)
        pkg.setRels(of: "ppt/presentation.xml", presRels)
    }

    /// The notes: stale metadata out, so the pack carries nothing of the deck it came from.
    static func cleanMetadata(_ pkg: inout PptxPackage) {
        if let core = pkg.xml("docProps/core.xml") {
            if let n = core.children.first(where: { $0.name == "cp:lastModifiedBy" }) { n.text = "Duo" }
            else { core.children.append(XNode("cp:lastModifiedBy", text: "Duo")) }
            pkg.set("docProps/core.xml", core)
        }
        if let app = pkg.xml("docProps/app.xml") {
            for k in ["Slides", "Notes", "HiddenSlides", "Words", "Paragraphs", "MMClips"] { app.child(k)?.text = "0" }
            app.removeChildren("TitlesOfParts"); app.removeChildren("HeadingPairs")
            pkg.set("docProps/app.xml", app)
        }
        // the thumbnail is a picture of a slide
        if let r = pkg.xml("_rels/.rels") {
            for rel in r.kids("Relationship") where (rel["Type"] ?? "").hasSuffix("/thumbnail") {
                if let t = rel["Target"] { pkg.parts[t] = nil }
                r.children.removeAll { $0 === rel }
            }
            pkg.set("_rels/.rels", r)
        }
        // a 16:9 size isn't "screen4x3" (or any named type)
        if let pres = pkg.xml("ppt/presentation.xml"), let sz = pres.child("sldSz"), let cx = Int(sz["cx"] ?? ""), let cy = Int(sz["cy"] ?? ""), cx * 9 == cy * 16 || cx * 10 == cy * 16 {
            sz["type"] = nil
            pkg.set("ppt/presentation.xml", pres)
        }
    }

    static func renumber(_ layout: XNode) {
        var id = 1
        func walk(_ n: XNode) {
            if n.local == "cNvPr" { id += 1; n["id"] = String(id) }
            n.children.forEach(walk)
        }
        id = 1
        if let tree = layout.child("cSld")?.child("spTree") { walk(tree) }
    }

    // MARK: building placeholders

    static func ints(_ s: XNode) -> [Int]? {
        let x: XNode?
        switch s.local {
        case "graphicFrame": x = s.child("xfrm")
        case "grpSp": x = s.child("grpSpPr")?.child("xfrm")
        default: x = s.child("spPr")?.child("xfrm")
        }
        guard let off = x?.child("off"), let ext = x?.child("ext"),
              let a = Int(off["x"] ?? ""), let b = Int(off["y"] ?? ""), let c = Int(ext["cx"] ?? ""), let d = Int(ext["cy"] ?? "") else { return nil }
        return [a, b, c, d]
    }

    /// Finds a slide's shape by name (or 1-based position), with the layout and master XML that a
    /// placeholder on that slide inherits its box and style from.
    struct SlideShape { var node: XNode; var ctx: (layout: XNode?, master: XNode?); var box: [Int]?; var slidePart: String }

    static func slideShape(_ ref: String, slide n: Int, donor: (pkg: PptxPackage, model: TemplateInventory.Model, same: Bool)) throws -> SlideShape {
        guard donor.model.slideParts.indices.contains(n - 1) else { throw Failure(description: "the source has \(donor.model.slideParts.count) slides; slide \(n) isn't there") }
        let part = donor.model.slideParts[n - 1]
        guard let sx = donor.pkg.xml(part) else { throw Failure(description: "slide \(n) is damaged") }
        let shapes = TemplateInventory.shapes(sx)
        guard let node = shapes.first(where: { TemplateInventory.name($0) == ref }) ?? Int(ref).flatMap({ shapes.indices.contains($0 - 1) ? shapes[$0 - 1] : nil }) else {
            throw Failure(description: "no shape \"\(ref)\" on slide \(n); its shapes are " + shapes.map { "\"\(TemplateInventory.name($0))\"" }.joined(separator: ", "))
        }
        let lp = donor.pkg.related(part, type: "slideLayout").first
        let lx = lp.flatMap { donor.pkg.xml($0) }
        let mx = lp.map { donor.model.masters[donor.model.masterIndex(ofLayout: $0)].xml }
        var box = ints(node)
        if box == nil, let ph = TemplateInventory.phNode(node) {
            if let l = lx.flatMap({ TemplateInventory.Model.match(ph, in: TemplateInventory.shapes($0)) }), let b = ints(l) { box = b }
            else if let m = mx.flatMap({ TemplateInventory.Model.match(ph, in: TemplateInventory.shapes($0)) }), let b = ints(m) { box = b }
        }
        return SlideShape(node: node, ctx: (lx, mx), box: box, slidePart: part)
    }

    static let nsA = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let nsR = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let nsP = "http://schemas.openxmlformats.org/presentationml/2006/main"

    /// The placeholder `p:sp` for a slot: type by kind, idx as given, box from the source shape (or
    /// `box:`), and the shape's first run and paragraph properties as its list style.
    static func slotPlaceholder(_ s: SlotSpec, template t: Template, idx: Int, shapeSlide: Int?,
                                donor: (pkg: PptxPackage, model: TemplateInventory.Model, same: Bool)?, pkg: inout PptxPackage,
                                layoutPart: String, notes: inout [String], line: Int) throws -> XNode? {
        var src: SlideShape?
        var box: [Int]?
        if let b = s.box {
            let v = b.split(whereSeparator: { $0 == " " || $0 == "/" }).compactMap { Double($0) }
            guard v.count == 4 else { throw Failure(description: "box: needs four numbers in pt, x y w h (not \"\(b)\")") }
            box = v.map { Int(($0 * 12700).rounded()) }
        }
        if let ref = s.shape {
            guard let d = donor, let n = shapeSlide else { return nil }
            src = try slideShape(ref, slide: n, donor: d)
            if box == nil { box = src?.box }
        }
        guard let b = box else { throw Failure(description: "no box: the shape has no position of its own, and no box: x y w h was given") }
        let type = s.name == "title" ? "title" : (s.kind == "image" ? "pic" : s.kind == "table" ? "tbl" : "body")
        var phAttrs = ["type": type, "idx": String(idx)]
        if type == "body" || type == "pic" { phAttrs["sz"] = "quarter" }
        let nv = XNode("p:nvSpPr", [:], [
            XNode("p:cNvPr", ["id": "2", "name": titleCase(s.name) + " Placeholder"]),
            XNode("p:cNvSpPr", [:], [XNode("a:spLocks", ["noGrp": "1"])]),
            XNode("p:nvPr", [:], [XNode("p:ph", phAttrs)]),
        ])
        let sp = XNode("p:sp", [:], [nv, XNode("p:spPr", [:], [XNode("a:xfrm", [:], [
            XNode("a:off", ["x": String(b[0]), "y": String(b[1])]), XNode("a:ext", ["cx": String(b[2]), "cy": String(b[3])])])])])
        guard type != "pic", type != "tbl" else { return sp }
        let (bodyPr, lst) = style(for: s, from: src, donor: donor)
        sp.children.append(XNode("p:txBody", [:], [bodyPr, lst, XNode("a:p", [:], [XNode("a:r", [:], [XNode("a:rPr", ["lang": "en-US"]), XNode("a:t", text: titleCase(s.name))])])]))
        return sp
    }

    static func style(for s: SlotSpec, from src: SlideShape?, donor: (pkg: PptxPackage, model: TemplateInventory.Model, same: Bool)?) -> (XNode, XNode) {
        let tb = src?.node.child("txBody")
        let bodyPr = tb?.child("bodyPr")?.copy() ?? XNode("a:bodyPr")
        for k in ["normAutofit", "spAutoFit", "noAutofit"] { bodyPr.removeChildren(k) }
        bodyPr.children.append(XNode("a:normAutofit"))
        bodyPr["wrap"] = "square"
        let para = tb?.kids("p").first
        let pPr = para?.child("pPr")
        let rPr = para?.child("r")?.child("rPr") ?? para?.child("endParaRPr")
        let lvl = XNode("a:lvl1pPr")
        for k in ["algn", "marL", "indent"] { if let v = pPr?[k] { lvl[k] = v } }
        let bullets = s.kind == "bullets"
        var hasBu = false
        for c in pPr?.children ?? [] {
            if ["lnSpc", "spcBef", "spcAft", "buClr", "buSzPct", "buFont", "buNone", "buChar", "buAutoNum", "buBlip"].contains(c.local) {
                lvl.children.append(c.copy())
                if ["buNone", "buChar", "buAutoNum", "buBlip"].contains(c.local) { hasBu = true }
            }
        }
        if bullets, !hasBu {
            lvl["marL"] = lvl["marL"] ?? "285750"; lvl["indent"] = lvl["indent"] ?? "-285750"
            lvl.children.append(XNode("a:buFont", ["typeface": "Arial"])); lvl.children.append(XNode("a:buChar", ["char": "•"]))
        } else if !bullets, !hasBu {
            lvl["marL"] = lvl["marL"] ?? "0"; lvl["indent"] = lvl["indent"] ?? "0"
            lvl.children.append(XNode("a:buNone"))
        }
        let def = XNode("a:defRPr")
        for k in ["sz", "b", "i", "u", "spc", "cap", "baseline"] { if let v = rPr?[k] { def[k] = v } }
        for c in rPr?.children ?? [] where ["solidFill", "latin", "ea", "cs"].contains(c.local) { def.children.append(c.copy()) }
        if let z = s.size { def["sz"] = String(Int(z * 100)) }
        if def["sz"] == nil, let node = src?.node, let ph = TemplateInventory.phNode(node), let d = donor, let sz = d.model.resolve(ph, own: node, layout: src?.ctx.layout, master: src?.ctx.master).size {
            def["sz"] = String(Int(sz * 100))
        }
        lvl.children.append(def)
        return (bodyPr, XNode("a:lstStyle", [:], [lvl]))
    }

    // MARK: promote

    /// Turns a slide into a layout of the pack. Returns the idx each slot got.
    static func promote(_ t: Template, slidePart: String, donorPkg: PptxPackage, donorModel: TemplateInventory.Model, same: Bool, masterPart: String,
                        layoutName: String, pkg: inout PptxPackage, notes: inout [String]) throws -> [String: Int] {
        guard let n = t.fromSlide else { return [:] }
        let donor = (pkg: donorPkg, model: donorModel, same: same)
        guard let sx = donorPkg.xml(slidePart) else { throw Failure(description: "slide \(n) is damaged") }
        // which shape is which slot
        var slotFor: [String: SlotSpec] = [:]
        var assigned: [String: Int] = [:]
        var used = Set<Int>([10, 11, 12])
        for s in t.slots where s.idx >= 13 { used.insert(s.idx) }
        for s in t.slots {
            if s.shape == nil, s.box != nil {
                if s.idx >= 13, !assigned.values.contains(s.idx) { assigned[s.name] = s.idx } else { let i = nextIdx(used); used.insert(i); assigned[s.name] = i }
                continue
            }
            guard let ref = s.shape else { throw Failure(description: "slot \(s.name) needs shape: <a shape name on slide \(n)> to say which box becomes it, or box: x y w h") }
            let sh = try slideShape(ref, slide: n, donor: donor)
            slotFor[TemplateInventory.cNvPr(sh.node)?["id"] ?? ""] = s
            if s.name == "title" { assigned[s.name] = 0 }
            else if s.idx >= 13, !assigned.values.contains(s.idx) { assigned[s.name] = s.idx }
            else { let i = nextIdx(used); used.insert(i); assigned[s.name] = i }
        }
        let layoutRelBase = donorPkg.rels(of: slidePart)
        // the layout
        var part: String?
        if let m = try? TemplateInventory.Model(pkg), let hit = m.layoutPart(named: layoutName) { part = hit.part }
        let isNew = part == nil
        if part == nil {
            var k = 1
            while pkg.parts["ppt/slideLayouts/slideLayout\(k).xml"] != nil { k += 1 }
            part = "ppt/slideLayouts/slideLayout\(k).xml"
        }
        let lpart = part!
        var rels: [PptxPackage.Rel] = [PptxPackage.Rel(id: "rId1", type: "slideMaster", target: PptxPackage.relative(masterPart, from: lpart), external: false,
                                                       fullType: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster")]
        func nextRid() -> String { "rId\(rels.count + 1)" }
        var shapesOut: [XNode] = []
        var decorationText: [String] = []
        let slideLayoutPart = donorPkg.related(slidePart, type: "slideLayout").first
        for sh in TemplateInventory.shapes(sx) {
            if let s = slotFor[TemplateInventory.cNvPr(sh)?["id"] ?? "-"] {
                var spec = s
                spec.shape = TemplateInventory.name(sh)
                if let p = try slotPlaceholder(spec, template: t, idx: assigned[s.name]!, shapeSlide: n, donor: donor, pkg: &pkg, layoutPart: lpart, notes: &notes, line: 0) {
                    shapesOut.append(p)
                }
                continue
            }
            if let ph = TemplateInventory.phNode(sh), TemplateInventory.footers.contains(TemplateInventory.phType(ph)) { continue }
            if TemplateInventory.phNode(sh) != nil { continue }   // a placeholder of the slide's own layout that no slot uses: not decoration
            let c = sh.copy()
            // pictures and links: bring the parts the shape points at
            for d in allNodes(c) {
                for (k, v) in d.attrs where k.hasPrefix("r:") {
                    guard let rel = layoutRelBase.first(where: { $0.id == v }) else { continue }
                    let nid = nextRid()
                    if rel.external {
                        rels.append(PptxPackage.Rel(id: nid, type: rel.type, target: rel.target, external: true, fullType: rel.fullType))
                    } else {
                        let src = PptxPackage.resolve(rel.target, from: slidePart)
                        let dst = try bring(src, from: donorPkg, into: &pkg)
                        rels.append(PptxPackage.Rel(id: nid, type: rel.type, target: PptxPackage.relative(dst, from: lpart), external: false, fullType: rel.fullType))
                    }
                    d[k] = nid
                }
            }
            let tx = TemplateInventory.text(sh)
            if !tx.isEmpty { decorationText.append("\"\(String(tx.prefix(40)))\"") }
            shapesOut.append(c)
        }
        // slots given only a box
        for s in t.slots where s.shape == nil && s.box != nil {
            if let p = try slotPlaceholder(s, template: t, idx: assigned[s.name]!, shapeSlide: n, donor: donor, pkg: &pkg, layoutPart: lpart, notes: &notes, line: 0) { shapesOut.append(p) }
        }
        // footer, date and slide number placeholders come from the layout the slide was on
        if let lp = slideLayoutPart, let lx = donorPkg.xml(lp) {
            for sh in TemplateInventory.shapes(lx) {
                if let ph = TemplateInventory.phNode(sh), TemplateInventory.footers.contains(TemplateInventory.phType(ph)) { shapesOut.append(sh.copy()) }
            }
        }
        let grp = XNode("p:nvGrpSpPr", [:], [XNode("p:cNvPr", ["id": "1", "name": ""]), XNode("p:cNvGrpSpPr"), XNode("p:nvPr")])
        let grpPr = XNode("p:grpSpPr", [:], [XNode("a:xfrm", [:], [XNode("a:off", ["x": "0", "y": "0"]), XNode("a:ext", ["cx": "0", "cy": "0"]),
                                                                  XNode("a:chOff", ["x": "0", "y": "0"]), XNode("a:chExt", ["cx": "0", "cy": "0"])])])
        let cSld = XNode("p:cSld", ["name": layoutName])
        if let bg = sx.child("cSld")?.child("bg") { cSld.children.append(bg.copy()) }
        cSld.children.append(XNode("p:spTree", [:], [grp, grpPr] + shapesOut))
        let root = XNode("p:sldLayout", ["xmlns:a": nsA, "xmlns:r": nsR, "xmlns:p": nsP, "preserve": "1", "userDrawn": "1"],
                         [cSld, XNode("p:clrMapOvr", [:], [XNode("a:masterClrMapping")])])
        renumber(root)
        pkg.set(lpart, root)
        pkg.setRels(of: lpart, rels)
        pkg.addOverride(lpart, "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml")
        if isNew {
            // the master lists it
            guard let mx = pkg.xml(masterPart) else { throw Failure(description: "the master \(masterPart) isn't in the pack") }
            var mrels = pkg.rels(of: masterPart)
            let rid = "rId\((mrels.compactMap { Int($0.id.dropFirst(3)) }.max() ?? 0) + 1)"
            mrels.append(PptxPackage.Rel(id: rid, type: "slideLayout", target: PptxPackage.relative(lpart, from: masterPart), external: false,
                                         fullType: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"))
            pkg.setRels(of: masterPart, mrels)
            var ids = pkg.xml("ppt/presentation.xml")?.child("sldMasterIdLst")?.kids("sldMasterId").compactMap { Int($0["id"] ?? "") } ?? []
            for p in pkg.parts.keys where p.hasPrefix("ppt/slideMasters/slideMaster") && p.hasSuffix(".xml") {
                ids += pkg.xml(p)?.child("sldLayoutIdLst")?.kids("sldLayoutId").compactMap { Int($0["id"] ?? "") } ?? []
            }
            let lst = mx.child("sldLayoutIdLst") ?? { let n = XNode("p:sldLayoutIdLst"); mx.children.insert(n, at: (mx.children.firstIndex { $0.local == "cSld" || $0.local == "clrMap" }.map { $0 + 2 }) ?? mx.children.count); return n }()
            lst.children.append(XNode("p:sldLayoutId", ["id": String((ids.max() ?? 2_147_483_647) + 1), "r:id": rid]))
            pkg.set(masterPart, mx)
        }
        let deco = shapesOut.filter { TemplateInventory.phNode($0) == nil }
        notes.append("\(t.name): promoted slide \(n) to layout \"\(layoutName)\": " + t.slots.map { "\($0.name) is idx \(assigned[$0.name]!)" }.joined(separator: ", ")
                     + (deco.isEmpty ? "" : "; \(deco.count) other shape\(deco.count == 1 ? "" : "s") became decoration"))
        if !decorationText.isEmpty { notes.append("\(t.name): decoration with text, now part of the layout: " + decorationText.joined(separator: ", ")) }
        return assigned
    }

    static func allNodes(_ n: XNode) -> [XNode] { [n] + n.children.flatMap(allNodes) }

    /// Copies a part (a picture) from another package if `pkg` doesn't already hold the same bytes there.
    static func bring(_ part: String, from donor: PptxPackage, into pkg: inout PptxPackage) throws -> String {
        guard let data = donor.parts[part] else { throw Failure(description: "\(part) is missing from the source") }
        if let have = pkg.parts[part] {
            if have == data { return part }
            var k = 1
            let ext = (part as NSString).pathExtension
            while pkg.parts["ppt/media/duo\(k).\(ext)"] != nil { k += 1 }
            let name = "ppt/media/duo\(k).\(ext)"
            pkg.parts[name] = data
            if let ct = donor.contentType(ofExtension: ext) { pkg.addDefault(ext, ct) }
            return name
        }
        pkg.parts[part] = data
        let ext = (part as NSString).pathExtension
        if let ct = donor.contentType(ofExtension: ext) { pkg.addDefault(ext, ct) }
        return part
    }
}
