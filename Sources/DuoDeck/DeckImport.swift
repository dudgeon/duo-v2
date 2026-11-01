import DuoControl
import DuoSearch
import Foundation

/// `duo2 deck import <pptx> --plan <file>` (lifecycle M3b, DL-294): an existing pptx becomes a Duo
/// deck. The plan (`DeckImportPlan`) says which template each slide group becomes; this amends or
/// makes the pack (through `buildPack`), then converts the content:
/// - placeholder text goes to the slot with the same idx; loose boxes go by the plan's `map`, else to
///   the slot whose box is nearest;
/// - speaker notes become `> [!note]`;
/// - PowerPoint comments, legacy and modern, become Review comments signed with their author and date
///   (DL-290), under the slide's marker or in the slot their shape became;
/// - a chart becomes a placeholder picture (drawing one needs the deck viewer's renderer) and its data
///   goes to the notes;
/// - anything that maps nowhere goes to the speaker notes (DL-281).
/// The source pptx is only read.
extension Deck {
    public struct ImportOutcome: Sendable {
        public var deck: URL
        public var pack: URL
        public var report: String
        /// What `deck check` says about the new deck.
        public var problems: [Problem]
        public var notices: [Problem]
    }

    struct PPComment { var author: String; var date: String; var text: String; var anchorShape: String?; var replies: [(author: String, date: String, text: String)] }

    // MARK: entry

    public static func importDeck(pptx: URL, plan: DeckImportPlan.Plan, pack packName: String?, newPack: String?, out: URL?, cwd: URL) throws -> ImportOutcome {
        let src = try PptxPackage(pptx)
        let model = try TemplateInventory.Model(src)
        let inv = try TemplateInventory.read(pptx)
        let nSlides = inv.slides.count
        let fm = FileManager.default

        // groups -> slides
        var groups = plan.groups
        for (i, g) in groups.enumerated() where !g.groupIDs.isEmpty {
            for id in g.groupIDs {
                guard let sg = inv.groups.first(where: { $0.id == id }) else { throw Failure(description: "plan: there is no group \(id); the survey has \(inv.groups.map(\.id).joined(separator: ", "))") }
                groups[i].slides += sg.slides
            }
            groups[i].slides = Array(Set(groups[i].slides)).sorted()
        }
        var owner: [Int: Int] = [:]
        for (i, g) in groups.enumerated() {
            for s in g.slides {
                guard (1...nSlides).contains(s) else { throw Failure(description: "plan: slide \(s) isn't in \(pptx.lastPathComponent), which has \(nSlides)") }
                if owner[s] != nil { throw Failure(description: "plan: slide \(s) is in two groups") }
                owner[s] = i
            }
        }
        let missing = (1...max(nSlides, 1)).filter { owner[$0] == nil }
        if !missing.isEmpty { throw Failure(description: "plan: slides \(missing.map(String.init).joined(separator: ", ")) aren't in any group; every slide needs a template") }

        // the pack
        let nearDirs = packDirs(near: cwd)
        var mdURL: URL
        var createdPack = false
        if let np = newPack {
            guard isName(np) else { throw Failure(description: "--new-pack: \"\(np)\" should be lower case letters, digits and hyphens") }
            let builtIn = try? builtInPackDir()
            let root = nearDirs.first(where: { fm.fileExists(atPath: $0.path) && $0.standardizedFileURL != builtIn?.standardizedFileURL }) ?? nearDirs[0]
            let folder = root.appending(path: np)
            mdURL = folder.appending(path: "\(np).md")
            guard !fm.fileExists(atPath: mdURL.path) else { throw Failure(description: "the pack \(np) already exists at \(mdURL.path); use --pack \(np) to amend it") }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let rel = relativePath(from: folder, to: pptx)
            let heading = inv.majorFont.isEmpty ? "" : "heading-font: \(inv.majorFont)\nbody-font: \(inv.minorFont)\n"
            let google = inv.fonts.first { $0.font == inv.majorFont && !$0.google }?.substitute.map { "google-heading-font: \($0)\n" } ?? ""
            try """
            ---
            type: deck-template
            title: \(titleCase(np))
            pptx: \(np).pptx
            slide-size: 16:9
            source: \(rel)
            \(heading)\(google)---

            # \(titleCase(np)) deck templates

            Made from `\(pptx.lastPathComponent)` by `duo2 deck import`. Each template is a layout in `\(np).pptx`; its slots are that layout's placeholders.

            Lines marked `# duo` are written by `duo2 deck template build` from the pptx and are checked against it. The rest (names, purpose, limits) can be edited freely.

            """.replacingOccurrences(of: "\n\n\n", with: "\n\n").write(to: mdURL, atomically: true, encoding: .utf8)
            createdPack = true
        } else if let pn = packName ?? plan.pack {
            guard let found = packs(in: nearDirs).first(where: { $0.name == pn }) else {
                throw Failure(description: "no template pack \"\(pn)\" in " + nearDirs.map(\.path).joined(separator: ", "))
            }
            mdURL = found.md
        } else {
            throw Failure(description: "say which pack the slides become: --pack <pack>, or --new-pack <name> to make one from this deck")
        }
        let packFront = (try? loadPack(md: mdURL, name: mdURL.deletingPathExtension().lastPathComponent))?.front ?? [:]
        let packSourceSame = packFront["source"].map { resolveFile($0, near: mdURL).standardizedFileURL.path == pptx.standardizedFileURL.path } ?? false
        let relSource = relativePath(from: mdURL.deletingLastPathComponent(), to: pptx)

        // amend and new templates, written into the definition
        var lines = try String(contentsOf: mdURL, encoding: .utf8).components(separatedBy: "\n")
        let existing = (try? loadPack(md: mdURL, name: mdURL.deletingPathExtension().lastPathComponent))?.templates ?? []
        var packNotes: [String] = []
        for g in groups {
            let exists = existing.contains { $0.name == g.template } || lines.contains("## \(g.template)")
            if let n = g.new {
                guard !exists else { throw Failure(description: "plan: \(g.template) is already a template of the pack; use amend: to change it, or another name") }
                guard isName(g.template) else { throw Failure(description: "plan: template names are lower case letters, digits and hyphens, not \"\(g.template)\"") }
                let first = g.slides.first ?? 1
                var top: [String] = []
                var slotLines: [String] = []
                if let layout = n.layout {
                    top.append("layout: \(layout)")
                    slotLines = n.slots.isEmpty ? autoSlots(layout: layout, inv: inv, pack: nil) : n.slots.map { slotLine($0.name, $0.keys) }
                } else {
                    let from = n.fromSlide ?? first
                    guard !n.slots.isEmpty else { throw Failure(description: "plan: \(g.template) is new from slide \(from), which has loose boxes: list its slots under new: slots: (each with shape: <the box's name>)") }
                    top.append("from-slide: \(from)")
                    slotLines = n.slots.map { slotLine($0.name, $0.keys) }
                }
                if !packSourceSame { top.append("source: \(relSource)") }
                lines += ["", "## \(g.template)", "", n.purpose ?? "Imported from \(pptx.lastPathComponent), slide \(n.fromSlide ?? first). Say here what this template is for.", "",
                          "```yaml"] + top + ["slots:"] + slotLines + ["```", ""]
                packNotes.append("\(g.template) is a new template" + (n.layout != nil ? " on layout \"\(n.layout!)\"" : " promoted from slide \(n.fromSlide ?? first)"))
            } else if !g.amend.isEmpty {
                guard let b = rawBlocks(lines).first(where: { $0.name == g.template }) else {
                    throw Failure(description: "plan: amend: needs the template \(g.template) in the pack; it has " + existing.map(\.name).joined(separator: ", "))
                }
                var add: [String] = []
                for a in g.amend {
                    let slide = a.fromSlide ?? g.slides.first ?? 1
                    var keys = a.keys.filter { !["shape", "from-slide"].contains($0.0) }
                    if !keys.contains(where: { $0.0 == "kind" }) { keys.insert(("kind", "text"), at: 0) }
                    if !keys.contains(where: { $0.0 == "optional" }) { keys.append(("optional", "true")) }
                    if !keys.contains(where: { $0.0 == "box" }) {
                        guard let ref = a.shape else { throw Failure(description: "plan: amend \(a.slot) needs shape: <the box on slide \(slide)> or box: x y w h") }
                        let sh = try slideShape(ref, slide: slide, donor: (src, model, true))
                        guard let bx = sh.box else { throw Failure(description: "plan: shape \"\(ref)\" on slide \(slide) has no position") }
                        keys.append(("box", bx.map { String(Int((Double($0) / 12700).rounded())) }.joined(separator: " ")))
                        if !keys.contains(where: { $0.0 == "size" }), let z = sh.node.findAll("rPr").compactMap({ $0["sz"].flatMap(Double.init) }).first { keys.append(("size", TemplateFit.sizeText(z / 100))) }
                    }
                    add.append(slotLine(a.slot, keys))
                    packNotes.append("\(g.template) gains the optional slot \(a.slot)")
                }
                var at = b.end
                while at > b.start, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                lines.insert(contentsOf: add, at: at)
            }
        }
        if lines.joined(separator: "\n") != (try String(contentsOf: mdURL, encoding: .utf8)) {
            try lines.joined(separator: "\n").write(to: mdURL, atomically: true, encoding: .utf8)
        }
        var buildNotes: [String] = []
        let needsBuild = createdPack || groups.contains { $0.new != nil || !$0.amend.isEmpty }
        if needsBuild {
            let r = try buildPack(md: mdURL)
            guard r.problems.isEmpty else {
                throw Failure(description: "the pack didn't build:\n" + r.problems.map { "\(mdURL.lastPathComponent):\($0.line): \($0.message)" }.joined(separator: "\n"))
            }
            buildNotes = r.notes + r.fitProblems.map { "\(mdURL.lastPathComponent):\($0.line): \($0.message)" }
        }
        let pack = try loadPack(md: mdURL, name: mdURL.deletingPathExtension().lastPathComponent)
        for g in groups where pack.template(g.template) == nil {
            throw Failure(description: "plan: the pack \(pack.name) has no template \"\(g.template)\"; it has \(pack.templates.map(\.name).joined(separator: ", ")). Add new: for it")
        }
        let layoutPhs = layoutPlaceholders(pack)

        // convert
        let deckURL = out ?? pptx.deletingPathExtension().appendingPathExtension("md")
        guard !fm.fileExists(atPath: deckURL.path) else { throw Failure(description: "\(deckURL.path) already exists; pick another with --out") }
        let assets = deckURL.deletingLastPathComponent().appending(path: "assets")
        let deckName = deckURL.deletingPathExtension().lastPathComponent
        let authors = commentAuthors(src)
        var commentNo = 0
        var report = Report()
        var slideTexts: [String] = []
        var imageFiles: [(URL, Data)] = []
        for n in 1...nSlides {
            let g = groups[owner[n]!]
            let t = pack.template(g.template)!
            let reference = g.slides.first!
            var ctx = SlideConvert(n: n, template: t, group: g, referenceSlide: reference, model: model, src: src, phs: layoutPhs[t.layout] ?? [],
                                   deckName: deckName, assets: assets)
            let text = try convertSlide(&ctx, authors: authors, commentNo: &commentNo, report: &report)
            imageFiles += ctx.files
            slideTexts.append(text)
        }
        var front = ["---", "type: deck", "title: \(src.xml("docProps/core.xml")?.child("title")?.text.nonEmpty ?? titleCase(deckName))", "template: \(pack.name)"]
        if let f = pack.front["footer"] { front.append("footer: \(f)") }
        front.append("imported-from: \(pptx.lastPathComponent)")
        front += ["---", ""]
        let body = front.joined(separator: "\n") + "\n" + slideTexts.joined(separator: "\n---\n\n")
        try fm.createDirectory(at: deckURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !imageFiles.isEmpty { try fm.createDirectory(at: assets, withIntermediateDirectories: true) }
        for (u, d) in imageFiles { try d.write(to: u, options: .atomic) }
        try body.write(to: deckURL, atomically: true, encoding: .utf8)

        // the check, then the report
        let dirs = [mdURL.deletingLastPathComponent().deletingLastPathComponent()] + packDirs(near: deckURL.deletingLastPathComponent())
        let checked = try check(deck: deckURL, packDirs: dirs)
        var rep: [String] = []
        var head = "\(deckURL.lastPathComponent): \(nSlides) slides from \(nSlides)."
        if report.charts > 0 { head += " \(report.charts) chart\(report.charts == 1 ? "" : "s") became a placeholder picture (slide\(report.chartSlides.count == 1 ? "" : "s") \(report.chartSlides.map(String.init).joined(separator: ", "))); drawing charts needs the deck viewer's renderer (WebKit), which isn't built yet, and the chart's data is in the slide's notes." }
        if !report.toNotes.isEmpty { head += " \(report.toNotes.count) shape\(report.toNotes.count == 1 ? "" : "s") went to notes (" + report.toNotes.map { "slide \($0.slide): \"\($0.text)\"" }.joined(separator: "; ") + ")." }
        if report.comments > 0 { head += " \(report.comments) PowerPoint comment\(report.comments == 1 ? "" : "s") imported." }
        let fonts = inv.fonts.filter { !$0.google }
        if !fonts.isEmpty { head += " Fonts: " + fonts.map { $0.font + ($0.substitute.map { " -> \($0) for Google" } ?? " is not in Google Fonts") }.joined(separator: ", ") + "." }
        rep.append(head)
        if !packNotes.isEmpty || !buildNotes.isEmpty { rep.append("Pack \(pack.name) (\(mdURL.path)): " + packNotes.joined(separator: "; ") + ".") ; rep += buildNotes.map { "  " + $0 } }
        rep.append(contentsOf: report.other)
        rep.append("Check: " + Deck.report(deckURL.lastPathComponent, checked.problems, notices: checked.notices).components(separatedBy: "\n").last!)
        for p in checked.problems.prefix(12) { rep.append("  \(deckURL.lastPathComponent):\(p.line): \(p.message)") }
        return ImportOutcome(deck: deckURL, pack: mdURL, report: rep.joined(separator: "\n"), problems: checked.problems, notices: checked.notices)
    }

    // MARK: helpers

    struct Report {
        var charts = 0
        var chartSlides: [Int] = []
        var toNotes: [(slide: Int, text: String)] = []
        var comments = 0
        var other: [String] = []
    }

    static func relativePath(from dir: URL, to file: URL) -> String {
        let a = dir.standardizedFileURL.pathComponents, b = file.standardizedFileURL.pathComponents
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        let ups = Array(repeating: "..", count: a.count - i)
        return (ups + b[i...]).joined(separator: "/")
    }

    static func slotLine(_ name: String, _ keys: [(String, String)]) -> String {
        "  \(name): {" + keys.map { "\($0.0): \($0.1)" }.joined(separator: ", ") + "}"
    }

    /// Slots for a new template that reuses a layout of the pptx: one per placeholder, named by type.
    static func autoSlots(layout: String, inv: TemplateInventory.Report, pack: Pack?) -> [String] {
        guard let l = inv.layouts.first(where: { $0.name == layout }) else { return [] }
        var out: [String] = []
        var bodies = 0
        for p in l.placeholders where !TemplateInventory.footers.contains(p.type) {
            var name: String, kind = "text"
            switch p.type {
            case "title", "ctrTitle": name = "title"
            case "subTitle": name = "subtitle"
            case "pic": name = "picture"; kind = "image"
            case "tbl": name = "table"; kind = "table"
            default:
                bodies += 1; name = bodies == 1 ? "body" : "body-\(bodies)"
                kind = p.bullets == false ? "text" : "bullets"
            }
            var keys: [(String, String)] = [("idx", String(p.idx)), ("kind", kind)]
            if ["text", "bullets"].contains(kind), let m = TemplateFit.largestFit(kind: "text", in: p, bulleted: kind == "bullets", paragraphs: kind == "bullets" ? 6 : 1) { keys.append(("max", String(m))) }
            if kind == "bullets" { keys.append(("items", "6")); keys.append(("levels", "2")) }
            if name == "body" || (name == "subtitle" && bodies == 0) { keys.append(("default", "true")) }
            out.append(slotLine(name, keys))
        }
        return out
    }

    // MARK: one slide

    struct SlideConvert {
        var n: Int
        var template: Template
        var group: DeckImportPlan.Group
        var referenceSlide: Int
        var model: TemplateInventory.Model
        var src: PptxPackage
        var phs: [TemplateInventory.Placeholder]
        var deckName: String
        var assets: URL
        var files: [(URL, Data)] = []
    }

    static func paragraphs(_ shape: XNode) -> [(level: Int, text: String)] {
        var out: [(Int, String)] = []
        for p in shape.child("txBody")?.kids("p") ?? [] {
            let runs = p.children.filter { ["r", "fld", "br"].contains($0.local) }
            let anyPlain = runs.contains { $0.local == "r" && $0.child("rPr")?["b"] != "1" }
            var s = ""
            for r in runs {
                if r.local == "br" { s += " "; continue }
                if r.local == "fld", r["type"]?.hasPrefix("slidenum") == true { continue }
                let t = r.child("t")?.text ?? ""
                let core = t.trimmingCharacters(in: .whitespaces)
                if core.isEmpty { s += t; continue }
                let lead = String(t.prefix { $0 == " " }), trail = String(t.reversed().prefix { $0 == " " })
                s += (r.child("rPr")?["b"] == "1" && anyPlain) ? "\(lead)**\(core)**\(trail)" : t
            }
            let clean = s.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { out.append((Int(p.child("pPr")?["lvl"] ?? "0") ?? 0, clean)) }
        }
        return out
    }

    static func convertSlide(_ c: inout SlideConvert, authors: (legacy: [String: String], modern: [String: String]), commentNo: inout Int, report: inout Report) throws -> String {
        let t = c.template
        let part = c.model.slideParts[c.n - 1]
        guard let sx = c.src.xml(part) else { throw Failure(description: "slide \(c.n) is damaged") }
        let lp = c.src.related(part, type: "slideLayout").first
        let lx = lp.flatMap { c.src.xml($0) }
        let mx = lp.map { c.model.masters[c.model.masterIndex(ofLayout: $0)].xml }
        let rels = c.src.rels(of: part)
        let shapes = TemplateInventory.shapes(sx)
        var content: [String: [String]] = [:]
        var shapeSlot: [String: String] = [:]   // cNvPr id -> slot, for comments
        var pending: [XNode] = []
        var notes: [String] = []

        func isContent(_ s: XNode) -> Bool {
            switch TemplateInventory.kind(s) {
            case "text", "placeholder": return !TemplateInventory.text(s).isEmpty || TemplateInventory.phNode(s).map { ["pic", "tbl"].contains(TemplateInventory.phType($0)) } == true
            case "picture", "chart", "table": return true
            default: return false
            }
        }
        func compat(_ s: XNode, _ spec: SlotSpec) -> Bool {
            switch TemplateInventory.kind(s) {
            case "picture", "chart": return spec.kind == "image"
            case "table": return spec.kind == "table"
            default: return ["text", "number", "bullets"].contains(spec.kind)
            }
        }
        func append(_ slot: String, _ lines: [String], joinText: Bool) {
            if content[slot] == nil { content[slot] = lines }
            else if joinText, let last = content[slot]?.last, !last.hasPrefix("-"), !last.hasPrefix("!["), let first = lines.first { content[slot]![content[slot]!.count - 1] = last + " " + first }
            else { content[slot]! += lines }
        }
        func fill(_ s: XNode, _ spec: SlotSpec) throws {
            shapeSlot[TemplateInventory.cNvPr(s)?["id"] ?? "?"] = spec.name
            let kind = TemplateInventory.kind(s)
            switch spec.kind {
            case "image":
                if kind == "chart" {
                    let name = TemplateInventory.name(s)
                    let file = "\(c.deckName)-\(c.n)-chart.png"
                    c.files.append((c.assets.appending(path: file), placeholderPNG(aspect: Double(spec.aspect ?? 1.5))))
                    append(spec.name, ["![Chart: \(name)](assets/\(file))"], joinText: false)
                    report.charts += 1; report.chartSlides.append(c.n)
                    notes += chartNote(s, rels: rels, slidePart: part, src: c.src, name: name)
                } else {
                    guard let blip = s.find("blip"), let rid = blip["r:embed"], let rel = rels.first(where: { $0.id == rid }) else { return }
                    let media = PptxPackage.resolve(rel.target, from: part)
                    guard let data = c.src.parts[media] else { return }
                    let ext = (media as NSString).pathExtension.lowercased()
                    let file = "\(c.deckName)-\(c.n)-\(content.count + 1).\(ext)"
                    c.files.append((c.assets.appending(path: file), data))
                    let alt = TemplateInventory.cNvPr(s)?["descr"] ?? TemplateInventory.name(s)
                    append(spec.name, ["![\(alt)](assets/\(file))"], joinText: false)
                }
            case "table":
                let rows = s.findAll("tr").map { tr in tr.kids("tc").map { tc in tc.child("txBody")?.kids("p").map { $0.findAll("t").map(\.text).joined() }.joined(separator: " ") ?? "" } }
                guard let head = rows.first else { return }
                var l = ["| " + head.joined(separator: " | ") + " |", "|" + String(repeating: " --- |", count: head.count)]
                for r in rows.dropFirst() { l.append("| " + r.joined(separator: " | ") + " |") }
                append(spec.name, l, joinText: false)
            case "bullets":
                let maxLevel = max((spec.levels ?? 1) - 1, 0)
                append(spec.name, paragraphs(s).map { String(repeating: "  ", count: min($0.level, maxLevel)) + "- " + $0.text }, joinText: false)
            default:
                let text = paragraphs(s).map(\.text).joined(separator: " ")
                if !text.isEmpty { append(spec.name, [text], joinText: true) }
            }
        }

        // 1. placeholders by idx; loose boxes the plan names
        for s in shapes {
            if let ph = TemplateInventory.phNode(s) {
                if TemplateInventory.footers.contains(TemplateInventory.phType(ph)) { continue }
                if let spec = t.slots.first(where: { $0.idx == TemplateInventory.phIdx(ph) }), compat(s, spec) || TemplateInventory.kind(s) == "placeholder" { try fill(s, spec); continue }
            } else if let slot = c.group.map[TemplateInventory.name(s)], let spec = t.slot(slot) {
                try fill(s, spec); continue
            }
            if isContent(s) { pending.append(s) }
        }
        // 2. the rest by position: the nearest slot whose box is within 60 pt, then a lone fit
        func ptBox(_ s: XNode) -> TemplateInventory.Box? {
            if let ph = TemplateInventory.phNode(s) { return c.model.placeholderBox(ph, own: s, layout: lx, master: mx) }
            return TemplateInventory.box(s)
        }
        var freeSlots = t.slots.filter { content[$0.name] == nil }
        var cand: [(Double, XNode, SlotSpec)] = []
        for s in pending {
            guard let b = ptBox(s) else { continue }
            for spec in freeSlots where compat(s, spec) {
                guard let p = c.phs.first(where: { $0.idx == spec.idx }), let pb = p.box else { continue }
                let d = max(abs(b.x - pb.x), abs(b.y - pb.y), abs(b.w - pb.w), abs(b.h - pb.h))
                if d <= 60 { cand.append((d, s, spec)) }
            }
        }
        var placed = Set<ObjectIdentifier>()
        for (_, s, spec) in cand.sorted(by: { $0.0 < $1.0 }) where !placed.contains(ObjectIdentifier(s)) && freeSlots.contains(where: { $0.name == spec.name }) {
            try fill(s, spec); placed.insert(ObjectIdentifier(s)); freeSlots.removeAll { $0.name == spec.name }
        }
        for s in pending where !placed.contains(ObjectIdentifier(s)) {
            let fits = freeSlots.filter { compat(s, $0) }
            let same = pending.filter { !placed.contains(ObjectIdentifier($0)) && TemplateInventory.kind($0) == TemplateInventory.kind(s) }
            if fits.count == 1, same.count == 1 { try fill(s, fits[0]); placed.insert(ObjectIdentifier(s)); freeSlots.removeAll { $0.name == fits[0].name } }
        }
        // a required slot still empty takes the nearest shape of its kind that is left, however far
        for spec in freeSlots where !spec.optional && content[spec.name] == nil {
            let left = pending.filter { !placed.contains(ObjectIdentifier($0)) && compat($0, spec) }
            guard !left.isEmpty else { continue }
            let pb = c.phs.first(where: { $0.idx == spec.idx })?.box
            func dist(_ s: XNode) -> Double {
                guard let b = ptBox(s), let pb else { return .infinity }
                return max(abs(b.x - pb.x), abs(b.y - pb.y), abs(b.w - pb.w), abs(b.h - pb.h))
            }
            if let best = left.min(by: { dist($0) < dist($1) }) { try fill(best, spec); placed.insert(ObjectIdentifier(best)) }
        }
        for s in pending where !placed.contains(ObjectIdentifier(s)) {
            let k = TemplateInventory.kind(s)
            let tx = TemplateInventory.text(s).replacingOccurrences(of: "\n", with: " ")
            if k == "chart" { notes += chartNote(s, rels: rels, slidePart: part, src: c.src, name: TemplateInventory.name(s)); notes.append("Not placed: the chart \"\(TemplateInventory.name(s))\"") ; report.other.append("slide \(c.n): chart \"\(TemplateInventory.name(s))\" has no picture slot in \(t.name); its data is in the notes") }
            else if tx.isEmpty { notes.append("Not placed: a \(k) \"\(TemplateInventory.name(s))\""); report.other.append("slide \(c.n): a \(k) \"\(TemplateInventory.name(s))\" went to the notes") }
            else { notes.append("Not placed from the original slide: \(tx)"); report.toNotes.append((c.n, String(tx.prefix(40)))) }
        }

        // the speaker notes of the original
        var original: [String] = []
        if let np = rels.first(where: { $0.type == "notesSlide" }).map({ PptxPackage.resolve($0.target, from: part) }), let nx = c.src.xml(np) {
            for sp in TemplateInventory.shapes(nx) where TemplateInventory.phNode(sp).map({ TemplateInventory.phType($0) == "body" }) == true {
                original += paragraphs(sp).map(\.text)
            }
        }
        let allNotes = original + (original.isEmpty || notes.isEmpty ? [] : [""]) + notes

        // comments
        var slideLevel: [String] = []
        var slotComments: [String: [String]] = [:]
        for cm in comments(of: part, rels: rels, src: c.src, authors: authors) {
            commentNo += 1
            report.comments += 1 + cm.replies.count
            var l = [Review.comment(author: cm.author, date: cm.date, id: "c\(commentNo)", text: cm.text)]
            for (j, r) in cm.replies.enumerated() { l.append(Review.comment(author: r.author, date: r.date, id: "c\(commentNo).\(j + 1)", text: r.text)) }
            if let a = cm.anchorShape, let slot = shapeSlot[a] { slotComments[slot, default: []] += l } else { slideLevel += l }
        }

        // assemble in the template's order
        var out = ["<!-- slide: \(t.name) -->"]
        out += slideLevel
        for spec in t.slots {
            let body = (content[spec.name] ?? []) + (slotComments[spec.name] ?? [])
            if spec.name == "title" { out.append("# " + (content["title"]?.joined(separator: " ") ?? "")); out += slotComments["title"] ?? []; continue }
            if body.isEmpty, spec.optional { continue }
            out += ["", "## \(spec.name)"] + body
        }
        if !allNotes.isEmpty {
            out += ["", "> [!note]"] + allNotes.map { $0.isEmpty ? ">" : "> " + $0 }
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func chartNote(_ s: XNode, rels: [PptxPackage.Rel], slidePart: String, src: PptxPackage, name: String) -> [String] {
        guard let rid = s.find("chart")?["r:id"], let rel = rels.first(where: { $0.id == rid }), let cx = src.xml(PptxPackage.resolve(rel.target, from: slidePart)) else {
            return ["Chart \"\(name)\" from the original slide (no data found)."]
        }
        let kind = cx.find("plotArea")?.children.first { $0.local.hasSuffix("Chart") }?.local ?? "chart"
        var out = ["Chart data from the original slide (\"\(name)\", \(kind.replacingOccurrences(of: "Chart", with: " chart"))):"]
        for ser in cx.findAll("ser") {
            let n = ser.child("tx")?.find("v")?.text ?? "series"
            let cats = ser.child("cat")?.findAll("v").map(\.text) ?? []
            let vals = ser.child("val")?.findAll("v").map(\.text) ?? []
            out.append("- \(n): " + vals.enumerated().map { i, v in (cats.indices.contains(i) ? "\(cats[i]) \(v)" : v) }.joined(separator: ", "))
        }
        return out
    }

    // MARK: comments

    static func commentAuthors(_ src: PptxPackage) -> (legacy: [String: String], modern: [String: String]) {
        var legacy: [String: String] = [:], modern: [String: String] = [:]
        for rel in src.rels(of: "ppt/presentation.xml") {
            let part = PptxPackage.resolve(rel.target, from: "ppt/presentation.xml")
            if rel.type == "commentAuthors", let x = src.xml(part) { for a in x.kids("cmAuthor") { if let id = a["id"], let n = a["name"] { legacy[id] = n } } }
            if rel.type == "authors", let x = src.xml(part) { for a in x.kids("author") { if let id = a["id"], let n = a["name"] { modern[id] = n } } }
        }
        return (legacy, modern)
    }

    static func comments(of slidePart: String, rels: [PptxPackage.Rel], src: PptxPackage, authors: (legacy: [String: String], modern: [String: String])) -> [PPComment] {
        var out: [PPComment] = []
        for rel in rels where rel.type == "comments" && !rel.external {
            guard let x = src.xml(PptxPackage.resolve(rel.target, from: slidePart)) else { continue }
            func text(_ n: XNode) -> String { n.findAll("p").map { $0.findAll("t").map(\.text).joined() }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            for cm in x.kids("cm") {
                if let t = cm.child("text") {   // legacy: p:cm authorId dt, p:text
                    out.append(PPComment(author: authors.legacy[cm["authorId"] ?? ""] ?? "unknown", date: String((cm["dt"] ?? "").prefix(10)), text: t.text.trimmingCharacters(in: .whitespacesAndNewlines), anchorShape: nil, replies: []))
                } else {                         // modern: authorId is a guid, created, txBody, replyLst
                    let replies = (cm.child("replyLst")?.kids("reply") ?? []).map { r in
                        (author: authors.modern[r["authorId"] ?? ""] ?? "unknown", date: String((r["created"] ?? "").prefix(10)), text: r.child("txBody").map(text) ?? "")
                    }
                    out.append(PPComment(author: authors.modern[cm["authorId"] ?? ""] ?? "unknown", date: String((cm["created"] ?? "").prefix(10)), text: cm.child("txBody").map(text) ?? "",
                                         anchorShape: cm.find("spMk")?["id"], replies: replies))
                }
            }
        }
        return out
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
