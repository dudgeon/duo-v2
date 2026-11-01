import DuoControl
import DuoDeck
import DuoSearch
import Foundation

// Duo Decks P2 (DL-291 to DL-294): templates from your decks. Inventory, build with promotion and
// optional slots, specimen, the measured fit, the rename map, and importing a pptx with a plan.
// Called from deckChecks(). The fixture is samples/import/grower-update.pptx (made by
// prototypes/pptx/gen_import_fixture.py): slides 3 to 5 are the same "big number" slide drawn three
// times a few points apart, the third with a footnote box; 7 has a chart; 8 has a stray "Draft" box.
func deckP2Checks(tmp: URL, study: URL) throws {
    print("Duo Decks P2: inventory, build, specimen, fit, rename map, import")
    let fm = FileManager.default
    let fixture = study.appending(path: "import/grower-update.pptx")
    let fixtureBytes = try Data(contentsOf: fixture)
    let work = tmp.appending(path: "p2")
    try? fm.removeItem(at: work)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)

    // MARK: the package round trip
    let pkg = try PptxPackage(fixture)
    check(pkg.write() == pkg.write() && (try? PptxPackage(fixture).write()) == pkg.write(), "a package writes the same bytes every time")

    // MARK: inventory
    let inv = try TemplateInventory.read(fixture)
    check(inv.slides.count == 8 && inv.layouts.count >= 10 && inv.slideSize == [960, 540], "inventory: 8 slides, the layouts, 960 x 540 pt (\(inv.slideSize))")
    check(inv.majorFont == "Avenir Next" && inv.minorFont == "Inter" && inv.colors["accent1"] == "0F7B6C", "inventory: theme fonts and colours")
    let avenir = inv.fonts.first { $0.font == "Avenir Next" }, inter = inv.fonts.first { $0.font == "Inter" }
    check(avenir?.google == false && avenir?.substitute == "Nunito Sans" && inter?.google == true, "inventory: Avenir Next is flagged (closest Nunito Sans), Inter is a Google font")
    let kp = inv.layouts.first { $0.name == "Big Number" }
    check(kp?.placeholders.contains { $0.type == "body" && $0.idx == 13 && $0.box != nil && $0.fontSize != nil } == true, "inventory: a layout's placeholders carry type, idx, box and size")
    check(inv.layouts.first { $0.name == "Title + Bullets" }?.placeholders.first { $0.idx == 1 }?.bullets == true, "inventory: bullets are read from the master's body style")
    check(inv.slides[0].fingerprint == "ctrTitle@0 subTitle@1" && inv.slides[1].fingerprint == "title@0 body@1", "fingerprints of slides on real layouts are their placeholders (\(inv.slides[0].fingerprint), \(inv.slides[1].fingerprint))")
    check(inv.slides[2].fingerprint.contains("text@") && inv.slides[2].fingerprint == inv.slides[3].fingerprint, "slides 3 and 4 (loose boxes, a few points apart) share a fingerprint on the 12 pt grid")
    check(inv.slides[4].fingerprint != inv.slides[2].fingerprint, "slide 5 (shifted, with a footnote) has its own")
    let g = inv.groups
    check(g.map(\.slides) == [[1], [2], [3, 4], [5], [6], [7], [8]], "groups: identical fingerprints together (\(g.map(\.slides)))")
    check(g[2].drift > 0 && g[2].drift <= 6, "the group of 3 and 4 records its drift (\(g[2].drift) pt)")
    check(inv.near.count == 1 && inv.near[0].a == "G3" && inv.near[0].b == "G4" && inv.near[0].drift == 6 && inv.near[0].extra == ["text"] && inv.near[0].detail.contains("1 extra box"),
          "the near group: G4 has one extra text box, 6 pt apart (\(inv.near.map(\.detail)))")
    check(inv.slides[4].shapes.first { $0.name == "Footnote" }?.fontSize == 11 && inv.slides[2].shapes.first { $0.name == "Value" }?.fontSize == 80, "slide shapes carry their font size")
    check(inv.slides[1].hasNotes && inv.slides[2].comments == 1 && inv.slides[4].comments == 1 && !inv.slides[0].hasNotes, "notes and comments are counted (legacy on 3, modern on 5)")
    let only = try TemplateInventory.read(fixture, slides: try TemplateInventory.parseSlides("3,5-6"))
    check(only.slides.map(\.n) == [3, 5, 6], "--slides 3,5-6 lists only those")
    let text = TemplateInventory.render(inv)
    check(text.contains("NOT in Google Fonts; closest: Nunito Sans") && text.contains("near groups:") && text.contains("fingerprint: ctrTitle@0 subTitle@1"), "the text form shows the font flag, the fingerprints and the near groups")
    let back = try JSONDecoder().decode(TemplateInventory.Report.self, from: Data(try TemplateInventory.json(inv).utf8))
    check(back == inv, "--json round-trips")
    check((try? TemplateInventory.parseSlides("x")) == nil, "--slides refuses nonsense")

    // MARK: the measured fit
    check(TemplateFit.sample(10) == "Sample tex" && TemplateFit.sample(5, kind: "number") == "12345", "the sample text is \"Sample text\" repeated to the limit")
    let short = TemplateFit.lineCount("Sample text", font: "Helvetica Neue", size: 18, width: 600)
    let long = TemplateFit.lineCount(TemplateFit.sample(300), font: "Helvetica Neue", size: 18, width: 600)
    check(short.lines == 1 && short.note == nil && long.lines >= 4, "CoreText counts lines (\(short.lines) and \(long.lines))")
    let ghost = TemplateFit.lineCount("Sample text", font: "Zzyzx Display", size: 18, width: 600)
    check(ghost.note == "Zzyzx Display isn't installed here; measured in Helvetica Neue", "a font that isn't installed falls back, and says so (\(ghost.note ?? "nil"))")

    // MARK: build, with a promotion
    let packDir = work.appending(path: "templates/decks/growers")
    try fm.createDirectory(at: packDir, withIntermediateDirectories: true)
    let src = packDir.appending(path: "grower-update.pptx")
    try fm.copyItem(at: fixture, to: src)
    let md = packDir.appending(path: "growers.md")
    let packText = """
    ---
    type: deck-template
    title: Growers
    pptx: growers.pptx
    source: grower-update.pptx
    slide-size: 16:9
    google-heading-font: Nunito Sans
    ---

    # Growers

    ## title

    The opening slide.

    ```yaml
    layout: Title
    slots:
      title:    {kind: text, max: 28, lines: 1}
      subtitle: {idx: 1, kind: text, max: 60, lines: 1, default: true}
    ```

    ## bullets

    A heading and up to five short points.

    ```yaml
    layout: Title + Bullets
    slots:
      title: {idx: 0, kind: text, max: 36}
      body:  {idx: 1, kind: bullets, items: 4, levels: 2, max: 40, default: true}
    ```

    ## two-column

    Two lists side by side.

    ```yaml
    layout: Two Column
    slots:
      title: {idx: 0, kind: text, max: 36}
      left:  {idx: 1, kind: bullets, items: 3, levels: 1, max: 30}
      right: {idx: 2, kind: bullets, items: 3, levels: 1, max: 30}
    ```

    ## kpi

    One number that matters, what it measures, and a line of context.

    ```yaml
    from-slide: 3
    slots:
      title:   {kind: text, max: 40, shape: Title}
      value:   {kind: number, max: 6, shape: Value}
      label:   {kind: text, max: 45, shape: Label}
      context: {kind: text, max: 120, shape: Context, default: true}
    ```
    """
    try packText.write(to: md, atomically: true, encoding: .utf8)
    let b1 = try Deck.buildPack(md: md)
    check(b1.problems.isEmpty && b1.written, "build: no problems (\(b1.problems.map(\.message)))")
    check(b1.fitProblems.isEmpty, "build: the limits fit their boxes (\(b1.fitProblems.map(\.message)))")
    let built = try TemplateInventory.read(packDir.appending(path: "growers.pptx"))
    check(built.slides.isEmpty && built.layouts.map(\.name) == ["Title", "Title + Bullets", "Two Column", "Kpi"], "build: no slides, only the chosen layouts and the promoted one (\(built.layouts.map(\.name)))")
    let kpi = built.layouts.first { $0.name == "Kpi" }!
    check(kpi.placeholders.filter { !TemplateInventory.footers.contains($0.type) }.map(\.key) == ["title@0", "body@13", "body@14", "body@15"], "promotion: title is the title placeholder, slots are idx 13 and up in order (\(kpi.placeholders.map(\.key)))")
    check(kpi.placeholders.contains { $0.type == "ftr" } && kpi.placeholders.contains { $0.type == "sldNum" }, "promotion: the footer and slide number placeholders come along")
    check(kpi.decoration.map(\.name) == ["Accent bar"], "promotion: the other shape became layout decoration (\(kpi.decoration.map(\.name)))")
    let valuePh = kpi.placeholders.first { $0.idx == 13 }
    check(valuePh?.fontSize == 80 && valuePh?.box?.w == 400 && valuePh?.bullets == false, "promotion: the slot keeps the slide's size and box, and has no bullets (\(String(describing: valuePh?.fontSize)), \(String(describing: valuePh?.box)))")
    check(kpi.placeholders.first { $0.idx == 15 }?.fontSize == 16, "promotion: each slot has its own run size")
    let defMD = try String(contentsOf: md, encoding: .utf8)
    check(defMD.contains("layout: Kpi") && defMD.contains("fingerprint: title@0 body@13 body@14 body@15") && defMD.contains("# duo"), "the # duo lines are filled in")
    check(defMD.contains("value:   {idx: 13, kind: number") && defMD.contains("title:   {idx: 0, kind: text, max: 40, shape: Title}") && defMD.contains("fingerprint: ctrTitle@0 subTitle@1"), "idx is written into the slot lines (\(defMD.components(separatedBy: "\n").filter { $0.contains("value:") }))")
    check(b1.definitionChanged && defMD.contains("The opening slide.") && defMD.contains("A heading and up to five short points."), "Claude's lines are left alone")
    let bytes1 = try Data(contentsOf: packDir.appending(path: "growers.pptx"))
    let b2 = try Deck.buildPack(md: md)
    let bytes2 = try Data(contentsOf: packDir.appending(path: "growers.pptx"))
    check(b2.problems.isEmpty && !b2.definitionChanged && bytes2 == bytes1, "build again: the same bytes, the definition unchanged")
    let srcNow = try Data(contentsOf: src), fixNow = try Data(contentsOf: fixture)
    check(fixNow == fixtureBytes && srcNow == fixtureBytes, "build never writes the source")
    let zip = try Pptx.Zip(packDir.appending(path: "growers.pptx"))
    let core = String(decoding: try zip.read("docProps/core.xml") ?? Data(), as: UTF8.self)
    let app = String(decoding: try zip.read("docProps/app.xml") ?? Data(), as: UTF8.self)
    let presXML = String(decoding: try zip.read("ppt/presentation.xml") ?? Data(), as: UTF8.self)
    check(core.contains("<cp:lastModifiedBy>Duo</cp:lastModifiedBy>") && app.contains("<Slides>0</Slides>") && !app.contains("TitlesOfParts"), "stale metadata is cleaned: last modified by Duo, 0 slides in app.xml")
    check(zip.entries.keys.allSatisfy { !$0.contains("thumbnail") && !$0.contains("/slides/") && !$0.contains("comment") && !$0.contains("printerSettings") }, "no thumbnail, slides, comments or printer settings in the pack (\(zip.entries.keys.sorted().filter { $0.contains("thumb") || $0.contains("slides/") }))")
    check(!presXML.contains("type=\"screen4x3\"") && presXML.contains("<p:sldIdLst/>"), "the 16:9 size has no wrong type, and the slide list is empty")

    // checks against the pptx
    var bad = packText.replacingOccurrences(of: "body:  {idx: 1, kind: bullets", with: "body:  {idx: 9, kind: bullets")
    let badMD = work.appending(path: "bad/bad.md")
    try fm.createDirectory(at: badMD.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.copyItem(at: src, to: badMD.deletingLastPathComponent().appending(path: "grower-update.pptx"))
    try bad.write(to: badMD, atomically: true, encoding: .utf8)
    let r3 = try Deck.buildPack(md: badMD)
    check(r3.problems.count == 1 && r3.problems[0].message.hasPrefix("bullets.body: unknown idx 9; layout \"Title + Bullets\" has 0 (title), 1 (body)") && !r3.written
          && !fm.fileExists(atPath: badMD.deletingLastPathComponent().appending(path: "growers.pptx").path), "an unknown idx is a problem with its line, and nothing is written (\(r3.problems.map { "\($0.line): \($0.message)" }))")
    bad = packText.replacingOccurrences(of: "left:  {idx: 1, kind: bullets", with: "left:  {idx: 1, kind: image")
    try bad.write(to: badMD, atomically: true, encoding: .utf8)
    let r4 = try Deck.buildPack(md: badMD)
    check(r4.problems.count == 1 && r4.problems[0].message == "two-column.left: kind image doesn't fit placeholder idx 1, which is type body", "a slot kind that doesn't suit its placeholder is a problem (\(r4.problems.map(\.message)))")
    bad = packText.replacingOccurrences(of: "layout: Title + Bullets", with: "layout: Nope")
    try bad.write(to: badMD, atomically: true, encoding: .utf8)
    let r5 = try Deck.buildPack(md: badMD)
    check(r5.problems.first?.message.contains("no layout \"Nope\" in the source; its layouts are Title,") == true, "a missing layout names the ones there are")

    // limit too high: the largest that fits
    bad = packText.replacingOccurrences(of: "label:   {kind: text, max: 45", with: "label:   {kind: text, max: 200")
    try bad.write(to: badMD, atomically: true, encoding: .utf8)
    let r6 = try Deck.buildPack(md: badMD)
    let msg = r6.fitProblems.first?.message ?? ""
    check(r6.problems.isEmpty && r6.written && r6.fitProblems.count == 1 && msg.hasPrefix("kpi.label: limit too high: 200 characters at 18 pt take ") && msg.contains("the box holds 1; largest that fits: "), "a limit too high is reported with the largest that fits, and the pack is still built (\(msg))")
    if let k = msg.range(of: "largest that fits: ").map({ Int(msg[$0.upperBound...].prefix { $0.isNumber }) }) ?? nil, let ph = (try TemplateInventory.read(badMD.deletingLastPathComponent().appending(path: "growers.pptx"))).layouts.first(where: { $0.name == "Kpi" })?.placeholders.first(where: { $0.idx == 14 }) {
        let at = TemplateFit.measure(text: [TemplateFit.sample(k)], in: ph, bulleted: false), over = TemplateFit.measure(text: [TemplateFit.sample(k + 1)], in: ph, bulleted: false)
        check(at.map { $0.lines <= $0.holds } == true && over.map { $0.lines > $0.holds } == true && k >= 30 && k < 200, "the number named is the largest: \(k) fits, \(k + 1) doesn't")
    } else { check(false, "the largest that fits could be read from \(msg)") }

    // MARK: the fit in `deck check`
    let packs = [work.appending(path: "templates/decks")]
    let decks = work.appending(path: "decks")
    try fm.createDirectory(at: decks, withIntermediateDirectories: true)
    func deck(_ name: String, _ body: String) throws -> URL {
        let u = decks.appending(path: name)
        try ("---\ntype: deck\ntitle: T\ntemplate: growers\n---\n\n" + body).write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    let loose = packText.replacingOccurrences(of: "label:   {kind: text, max: 45", with: "label:   {kind: text, max: 400")
    let looseDir = work.appending(path: "loose/templates/decks/growers")
    try fm.createDirectory(at: looseDir, withIntermediateDirectories: true)
    try fm.copyItem(at: src, to: looseDir.appending(path: "grower-update.pptx"))
    try loose.write(to: looseDir.appending(path: "growers.md"), atomically: true, encoding: .utf8)
    _ = try Deck.buildPack(md: looseDir.appending(path: "growers.md"))
    let longLabel = String(repeating: "Sample words and more ", count: 4).trimmingCharacters(in: .whitespaces)
    let fitDeck = try deck("fit.md", "<!-- slide: kpi -->\n# Fit\n\n## value\n86%\n\n## label\n\(longLabel)\n\n## context\nOne line.\n")
    let fitRes = try Deck.check(deck: fitDeck, packDirs: [work.appending(path: "loose/templates/decks")])
    check(fitRes.problems.count == 1 && fitRes.problems[0].message.hasPrefix("slide 1 (kpi), label: does not fit: 2 lines at 18 pt; the box holds 1") , "deck check measures the text against its box (\(fitRes.problems.map(\.message)))")
    let skip = try Deck.check(deck: fitDeck, packDirs: [work.appending(path: "loose/templates/decks")], measureFit: false)
    check(skip.problems.isEmpty, "the measure can be left off (the specimen does)")
    let okDeck = try deck("ok.md", "<!-- slide: kpi -->\n# Fit\n\n## value\n86%\n\n## label\nOf rows done\n\n## context\nOne line.\n")
    check(try Deck.check(deck: okDeck, packDirs: packs).problems.isEmpty, "text that fits passes")

    // MARK: specimen
    let sp = try Deck.writeSpecimen(md: md, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(identifier: "UTC")!)
    let spText = try String(contentsOf: sp.deck, encoding: .utf8)
    let spParsed = Deck.parse(spText)
    check(spParsed.slides.map(\.template) == ["title", "bullets", "two-column", "kpi"], "specimen: every template once, in order (\(spParsed.slides.map(\.template)))")
    check(spParsed.slides[3].slot("label")?.lines == [TemplateFit.sample(45)] && spParsed.slides[3].slot("value")?.lines == ["123456"], "specimen: each slot is filled to its limit with sample text (\(spParsed.slides[3].slot("label")?.lines ?? []))")
    check(spParsed.slides[1].slot("body")?.lines.count == 4 && spParsed.slides[1].slot("body")?.lines.allSatisfy { $0.hasPrefix("- Sample text") } == true, "specimen: bullets are filled to their item count")
    check(fm.fileExists(atPath: sp.export.url.path) && sp.export.url.lastPathComponent == "growers-specimen 2027-01-15 0800.pptx", "specimen: exported with the dated name (\(sp.export.url.lastPathComponent))")
    let spGot = try Deck.inspect(sp.export.url)
    check(spGot.slides.map(\.layout) == ["Title", "Title + Bullets", "Two Column", "Kpi"], "specimen: the export is on the pack's layouts")
    let ps = Deck.placeholderPNG(aspect: 1.5)
    let pngBytes = [UInt8](ps)
    check(Array(pngBytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] && pngBytes[19] == 96 && pngBytes[23] == 64, "the placeholder picture is a PNG, 96 x 64")

    // MARK: the rename map
    let renamedMD = packText.replacingOccurrences(of: "from-slide: 3\nslots:", with: "from-slide: 3\nrenamed: {context: note}\nslots:")
        .replacingOccurrences(of: "context: {kind: text, max: 120, shape: Context, default: true}", with: "note:    {kind: text, max: 120, shape: Context, default: true}")
    let rdir = work.appending(path: "renamed/templates/decks/growers")
    try fm.createDirectory(at: rdir, withIntermediateDirectories: true)
    try fm.copyItem(at: src, to: rdir.appending(path: "grower-update.pptx"))
    try renamedMD.write(to: rdir.appending(path: "growers.md"), atomically: true, encoding: .utf8)
    let rb = try Deck.buildPack(md: rdir.appending(path: "growers.md"))
    check(rb.problems.isEmpty, "(fixture) the renamed pack builds (\(rb.problems.map(\.message)))")
    let rpack = [work.appending(path: "renamed/templates/decks")]
    let rpk = try Deck.loadPack("growers", in: rpack)
    check(rpk.template("kpi")?.renamed == ["context": "note"], "renamed: is read from the definition")
    let oldDeckText = "---\ntype: deck\ntitle: T\ntemplate: growers\n---\n\n<!-- slide: kpi -->\n# Rows\n\n## value\n86%\n\n## label\nOf rows done\n\n## context\nUp from 61%.\n\n---\n\n<!-- slide: title -->\n# Hello\n\n---\n\n<!-- slide: kpi -->\n# Again\n\n## value\n1%\n\n## note\nAlready new.\n\n## context\nStray.\n"
    let rdeckDir = work.appending(path: "renamed/decks")
    try fm.createDirectory(at: rdeckDir, withIntermediateDirectories: true)
    let rdeck = rdeckDir.appending(path: "a.md")
    try oldDeckText.write(to: rdeck, atomically: true, encoding: .utf8)
    let rc = try Deck.check(deck: rdeck, packDirs: rpack)
    check(rc.problems.contains { $0.message == "slide 1 (kpi): renamed \"context\" to \"note\" in growers.md; run duo2 deck migrate" && $0.line == 16 }, "the checker says renamed, not unknown (\(rc.problems.map { "\($0.line): \($0.message)" }))")
    let mig = Deck.migrate(source: oldDeckText, pack: rpk)
    check(mig.changes.count == 1 && mig.changes[0].slide == 1 && mig.changes[0].old == "context" && mig.changes[0].new == "note", "migrate renames the heading on the slide that has the old name (\(mig.changes))")
    check(mig.text.contains("## note\nUp from 61%.") && mig.text.contains("## context\nStray."), "a slide that already has the new heading is left alone")
    let diff = Deck.unifiedDiff(path: "decks/a.md", old: oldDeckText, new: mig.text)
    check(diff.hasPrefix("--- decks/a.md\n+++ decks/a.md\n@@ ") && diff.contains("-## context\n+## note") && diff.contains(" Up from 61%."), "the diff is a unified diff (\(diff.components(separatedBy: "\n").count) lines)")
    let ms = Deck.migrations(root: work.appending(path: "renamed"), packDirs: rpack, pack: "growers")
    check(ms.count == 1 && ms[0].deck.lastPathComponent == "a.md" && ms[0].after == mig.text, "migrations finds the decks under the project that use the pack")
    check(Deck.migrations(root: work.appending(path: "renamed"), packDirs: rpack, pack: "other").isEmpty, "--pack limits it")
    check((try String(contentsOf: rdeck, encoding: .utf8)) == oldDeckText, "a dry run writes nothing")
    try ms[0].after.write(to: rdeck, atomically: true, encoding: .utf8)
    let rc2 = try Deck.check(deck: rdeck, packDirs: rpack)
    check(rc2.problems.count == 1 && rc2.problems[0].message.hasPrefix("slide 3 (kpi): renamed"), "after migrating, slide 1 is clean (the stray old heading on slide 3, which also has the new one, stays an error: \(rc2.problems.map(\.message)))")

    // MARK: optional slots in the checker
    let optMD = packText.replacingOccurrences(of: "context: {kind: text, max: 120, shape: Context, default: true}", with: "context: {kind: text, max: 120, shape: Context, default: true}\n      footnote: {kind: text, max: 60, optional: true, box: 60 470 800 20, size: 11}")
    let odir = work.appending(path: "optional/templates/decks/growers")
    try fm.createDirectory(at: odir, withIntermediateDirectories: true)
    try fm.copyItem(at: src, to: odir.appending(path: "grower-update.pptx"))
    try optMD.write(to: odir.appending(path: "growers.md"), atomically: true, encoding: .utf8)
    let ob = try Deck.buildPack(md: odir.appending(path: "growers.md"))
    let okpi = try TemplateInventory.read(odir.appending(path: "growers.pptx")).layouts.first { $0.name == "Kpi" }
    check(ob.problems.isEmpty && okpi?.placeholders.first { $0.idx == 16 }?.box?.y == 470 && okpi?.placeholders.first { $0.idx == 16 }?.fontSize == 11, "an optional slot with a box becomes a placeholder, idx 16, at 11 pt (\(ob.problems.map(\.message)), \(okpi?.placeholders.map(\.key) ?? []))")
    check((try String(contentsOf: odir.appending(path: "growers.md"), encoding: .utf8)).contains("fingerprint: title@0 body@13 body@14 body@15 body@16"), "the fingerprint lists the optional placeholder")
    let optDeck = try deck("opt.md", "<!-- slide: kpi -->\n# Fit\n\n## value\n86%\n\n## label\nOf rows done\n\n## context\nOne line.\n")
    let oc = try Deck.check(deck: optDeck, packDirs: [work.appending(path: "optional/templates/decks")])
    check(oc.problems.isEmpty && oc.notices.isEmpty, "a slide may leave an optional slot out: no notice (\(oc.notices.map(\.message)))")

    // MARK: importing a pptx
    let importPack = work.appending(path: "imp")
    try fm.createDirectory(at: importPack.appending(path: "templates/decks/growers"), withIntermediateDirectories: true)
    try fm.copyItem(at: src, to: importPack.appending(path: "templates/decks/growers/grower-update.pptx"))
    let impMD = importPack.appending(path: "templates/decks/growers/growers.md")
    try packText.write(to: impMD, atomically: true, encoding: .utf8)
    _ = try Deck.buildPack(md: impMD)
    let pk0 = try Deck.loadPack(md: impMD, name: "growers")
    let survey = try DeckImportPlan.survey(fixture, pack: pk0)
    check(survey.groups.count == 7 && survey.groups[0].best == DeckImportPlan.Candidate(template: "title", how: "exact") && survey.groups[1].best?.template == "bullets", "survey: slides on real layouts match their template exactly (\(survey.groups.map { $0.best?.template ?? "-" }))")
    check(survey.groups[2].loose && survey.groups[2].best?.template == "kpi" && survey.groups[2].best?.how.hasPrefix("loose boxes") == true && survey.groups[3].best == nil, "survey: loose boxes are matched by how many text slots; the slide with the extra box fits nothing yet (\(survey.groups[2].best?.how ?? ""))")
    check(survey.near.count == 1 && survey.comments == 2 && survey.fonts.first?.hasPrefix("Avenir Next") == true, "survey: the near group, the comments and the font to watch")
    let surveyText = DeckImportPlan.render(survey)
    check(surveyText.contains("G3 slides 3, 4 on Blank (loose boxes)") && surveyText.contains("best: kpi (loose boxes") && surveyText.contains("G3 ~ G4:"), "survey: the text form")
    check((try DeckImportPlan.json(survey)).contains("\"fingerprint\""), "survey: --json")

    let plan = """
    # one pack, three kinds of slide
    groups:
      - slides: 1
        template: title
      - slides: 2
        template: bullets
      - group: G3, G4                # the three big-number slides: one template, one optional slot
        template: kpi
        amend:
          footnote: {kind: text, max: 60, shape: Footnote, from-slide: 5}
      - slides: 6
        template: two-column
      - slides: 7
        template: chart-slide
        new:
          from-slide: 7
          purpose: A heading and a chart. Charts come in as a picture.
          slots:
            title: {kind: text, max: 40, shape: Title}
            chart: {kind: image, shape: Rows chart, aspect: 2.2}
      - slides: 8
        template: closing
        new:
          layout: Title Only
    """
    let pl = try DeckImportPlan.parse(plan)
    check(pl.groups.count == 6 && pl.groups[2].groupIDs == ["G3", "G4"] && pl.groups[2].amend.first?.slot == "footnote" && pl.groups[2].amend.first?.fromSlide == 5 && pl.groups[4].new?.slots.map(\.name) == ["title", "chart"]
          && pl.groups[4].new?.slots[1].keys.contains(where: { $0 == ("shape", "Rows chart") }) == true, "the plan reads: groups, amend, new, slots with names that have spaces")
    check((try? DeckImportPlan.parse("groups:\n  - slides: 1\n")) == nil && (try? DeckImportPlan.parse("nothing: here")) == nil, "a plan without a template or groups is refused")
    let missingPlan = try DeckImportPlan.parse("groups:\n  - slides: 1\n    template: title\n")
    check((try? Deck.importDeck(pptx: fixture, plan: missingPlan, pack: "growers", newPack: nil, out: importPack.appending(path: "x.md"), cwd: importPack)) == nil, "a plan must cover every slide")

    let outDeck = importPack.appending(path: "decks/grower-update.md")
    let outcome = try Deck.importDeck(pptx: fixture, plan: pl, pack: "growers", newPack: nil, out: outDeck, cwd: importPack)
    let deckText = try String(contentsOf: outDeck, encoding: .utf8)
    let idp = Deck.parse(deckText)
    print("    --- import report ---")
    for l in outcome.report.components(separatedBy: "\n") { print("    " + l) }
    check(idp.problems.isEmpty && idp.slides.map(\.template) == ["title", "bullets", "kpi", "kpi", "kpi", "two-column", "chart-slide", "closing"], "import: eight slides on the planned templates (\(idp.slides.map(\.template)), \(idp.problems))")
    check(idp.slides[0].slot("title")?.lines == ["Grower update, September"] && idp.slides[0].slot("subtitle")?.lines == ["Field team, Northwind Labs"], "placeholder text goes to its slot by idx")
    check(idp.slides[1].slot("body")?.lines == ["- Three farms, 412 rows", "- Two weeks of unattended runs", "- Wet weather in week two"], "bullets keep their order")
    check(idp.slides[1].notes == ["Mention the three farms by name."], "speaker notes become the note callout")
    check(idp.slides[2].slot("value")?.lines == ["86%"] && idp.slides[3].slot("value")?.lines == ["3.2"] && idp.slides[4].slot("value")?.lines == ["1.4"], "loose boxes go to the slot with the nearest box (even 6 pt off)")
    check(idp.slides[2].slot("title")?.lines == ["Unattended rows"] && idp.slides[2].slot("context")?.lines == ["Up from 61% in the spring trial, over 412 rows on three farms."], "the title and context of the first big-number slide")
    check(idp.slides[4].slot("footnote")?.lines == ["Source: trial logs, three farms, Aug to Sep"] && idp.slides[2].slot("footnote") == nil, "coalesced: the extra box is the optional footnote slot, only on the slide that has it")
    check(idp.slides[2].marks.count == 1 && idp.slides[2].marks[0].line == idp.slides[2].line + 1 && deckText.contains("{>>@sam-rivera 2026-10-20 #c1: which farms?<<}"), "a legacy comment becomes a signed Review comment under the slide's marker")
    check(deckText.contains("{>>@priya-shah 2026-10-21 #c2: Is the footnote needed on every slide?<<}\n{>>@sam-rivera 2026-10-22 #c2.1: Only here; the others cite it above.<<}"), "a modern comment and its reply keep author, date and thread")
    check(idp.slides[6].slot("chart")?.lines.first?.hasPrefix("![Chart: Rows chart](assets/grower-update-7-chart.png)") == true && fm.fileExists(atPath: importPack.appending(path: "decks/assets/grower-update-7-chart.png").path), "a chart becomes a placeholder picture")
    check(idp.slides[6].notes.contains("Chart data from the original slide (\"Rows chart\", bar chart):") && idp.slides[6].notes.contains("- Rows: Week 1 120, Week 2 180, Week 3 240"), "the chart's data goes to the notes (\(idp.slides[6].notes))")
    check(idp.slides[7].notes.contains("Not placed from the original slide: Draft - not for circulation") && idp.slides[7].slot("title")?.lines == ["What comes next"], "a box that maps nowhere goes to the speaker notes (DL-281)")
    check(outcome.report.contains("1 chart became a placeholder picture (slide 7)") && outcome.report.contains("WebKit") && outcome.report.contains("1 shape went to notes (slide 8: \"Draft - not for circulation\")")
          && outcome.report.contains("3 PowerPoint comments imported") && outcome.report.contains("Avenir Next -> Nunito Sans for Google"), "the report says what didn't convert")
    check(outcome.problems.isEmpty, "the imported deck checks clean (\(outcome.problems.map { "\($0.line): \($0.message)" }))")
    let fixAfter = try Data(contentsOf: fixture)
    check(fixAfter == fixtureBytes, "import never writes the source pptx")

    // the pack after the import
    let pk1 = try Deck.loadPack(md: impMD, name: "growers")
    check(pk1.templates.map(\.name) == ["title", "bullets", "two-column", "kpi", "chart-slide", "closing"], "the pack gained two templates (\(pk1.templates.map(\.name)))")
    let kpi1 = pk1.template("kpi")!
    check(kpi1.slot("footnote")?.optional == true && kpi1.slot("footnote")?.idx == 16 && kpi1.fingerprint == "title@0 body@13 body@14 body@15 body@16", "kpi gained the optional slot footnote at idx 16 (\(kpi1.fingerprint))")
    check(pk1.template("closing")?.layout == "Title Only" && pk1.template("closing")?.slots.map(\.name) == ["title"] && pk1.template("chart-slide")?.slot("chart")?.kind == "image", "the new templates: a layout of the source, and a promoted slide")
    let after = try Deck.buildPack(md: impMD)
    check(after.problems.isEmpty && !after.definitionChanged, "the amended pack builds again with nothing to change (\(after.problems.map(\.message)))")
    let exp = try Deck.export(deck: outDeck, packDirs: [importPack.appending(path: "templates/decks")])
    let expGot = try Deck.inspect(URLWrite(exp, importPack.appending(path: "imported.pptx")))
    check(expGot.slides.count == 8 && expGot.slides[4].shapes.contains { $0.idx == 16 && $0.text == "Source: trial logs, three farms, Aug to Sep" } && expGot.slides[2].shapes.allSatisfy { $0.idx != 16 }, "the imported deck exports, with the footnote on slide 5 only")
    // a deck written before the amendment still checks clean
    let old = try Deck.check(deck: okDeck, packDirs: [importPack.appending(path: "templates/decks")])
    check(old.problems.isEmpty && old.notices.isEmpty, "existing decks are untouched by an optional slot (\(old.notices.map(\.message)))")
    check((try? Deck.importDeck(pptx: fixture, plan: pl, pack: "growers", newPack: nil, out: outDeck, cwd: importPack)) == nil, "import refuses to overwrite a deck")

    // a new pack from the deck
    let np = work.appending(path: "newpack")
    try fm.createDirectory(at: np, withIntermediateDirectories: true)
    let newPlan = try DeckImportPlan.parse("""
    groups:
      - slides: 1
        template: title
        new: {layout: Title}
      - slides: 2, 6
        template: text
        new: {layout: Title + Bullets}
      - slides: 3, 4, 5
        template: kpi
        new:
          from-slide: 3
          slots:
            title: {kind: text, max: 40, shape: Title}
            value: {kind: number, max: 6, shape: Value}
            label: {kind: text, max: 45, shape: Label}
            context: {kind: text, max: 120, shape: Context}
            footnote: {kind: text, max: 60, optional: true, box: 60 470 800 20, size: 11}
      - slides: 7, 8
        template: heading
        new: {layout: Title Only}
    """)
    let nout = try Deck.importDeck(pptx: fixture, plan: newPlan, pack: nil, newPack: "from-growers", out: np.appending(path: "decks/g.md"), cwd: np)
    let npk = try Deck.loadPack("from-growers", in: [np.appending(path: "templates/decks")])
    let nbuilt = try TemplateInventory.read(npk.pptx)
    check(npk.front["source"] == "../../../../grower-update.pptx" || npk.front["source"]?.hasSuffix("grower-update.pptx") == true, "--new-pack: the definition names the pptx it came from (\(npk.front["source"] ?? ""))")
    check(npk.templates.map(\.name) == ["title", "text", "kpi", "heading"] && nbuilt.layouts.map(\.name).contains("Kpi") && nbuilt.slides.isEmpty && nbuilt.layouts.count == 4, "--new-pack: the pack holds only the layouts it uses (\(nbuilt.layouts.map(\.name)))")
    check(nout.report.contains("Check:"), "--new-pack: the report ends with the check (\(nout.report.components(separatedBy: "\n").last ?? ""))")
    let fixEnd = try Data(contentsOf: fixture)
    check(fixEnd == fixtureBytes, "the source is untouched after both imports")
}

/// Writes `data` and returns the URL (a check helper).
func URLWrite(_ data: Data, _ url: URL) throws -> URL { try data.write(to: url); return url }
