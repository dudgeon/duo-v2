import DuoControl
import DuoDeck
import Foundation

// Duo Decks P1 (DL-281 to DL-290): empty-slot notices, the carry-over rules, dated exports, the
// scaffolding verbs' file work, the built-in pack and the skill. Called from deckChecks().
func deckP1Checks(tmp: URL, study: URL, deck: URL, packs: [URL]) throws {
    print("Duo Decks P1: notices, remap, dated exports, scaffolding, built-in pack, skill")
    let fm = FileManager.default
    let pack = try Deck.loadPack("northwind", in: packs)
    let parsed = Deck.parse(try String(contentsOf: deck, encoding: .utf8))
    let bullets = pack.template("bullets")!, two = pack.template("two-column")!, kpi = pack.template("kpi")!

    // empty slots are a notice
    let emptyDeck = tmp.appending(path: "decks/empty.md")
    try """
    ---
    type: deck
    title: Empty
    template: northwind
    footer: Northwind Labs · Internal
    ---

    <!-- slide: two-column -->
    # Spring and autumn

    ## left
    - One

    ## right
    """.write(to: emptyDeck, atomically: true, encoding: .utf8)
    let em = try Deck.check(deck: emptyDeck, packDirs: packs)
    check(em.problems.isEmpty && em.notices.map(\.message) == ["slide 1 (two-column), right: is empty"] && em.notices.first?.line == 14, "an empty slot is a notice, not an error (\(em.notices.map(\.message)), \(em.problems.map(\.message)))")
    check(Deck.report("decks/empty.md", em.problems, notices: em.notices) == "decks/empty.md:14: notice: slide 1 (two-column), right: is empty\nno problems, 1 notice", "the report lists notices after problems")
    check((try? Deck.export(deck: emptyDeck, packDirs: packs)) != nil, "a deck with an empty slot exports")
    let noSub = try Deck.check(deck: deck, packDirs: packs)
    check(noSub.notices.isEmpty, "the sample deck has no notices (\(noSub.notices.map(\.message)))")

    // the carry-over rules (DL-285)
    let s2 = parsed.slides[1]       // bullets: title + body, with a note
    let r1 = Deck.remap(s2, from: bullets, to: two)
    check(r1.unplaced == ["body"] && r1.moves == [Deck.Remap.Move(from: "title", to: "title")], "bullets to two-column: the title stays, the body has nowhere to go (\(r1.moves), \(r1.unplaced))")
    check(r1.slots.map(\.name) == ["title", "left", "right"] && r1.slots[1].lines.isEmpty && r1.slots[2].lines.isEmpty, "two-column starts with two empty columns")
    check(r1.notes.first == "Not placed after changing to two-column: body" && r1.notes.contains("- What breaks first in wet weather?"), "the body goes to the notes under a line naming it (\(r1.notes.prefix(2)))")
    let s3 = parsed.slides[2]       // kpi
    let r2 = Deck.remap(s3, from: kpi, to: bullets)
    check(r2.unplaced == ["value", "label", "context"] && r2.moves.map(\.to) == ["title"], "kpi to bullets: value, label and context have no home (\(r2.unplaced))")
    check(r2.notes[0] == "Not placed after changing to bullets: value, label, context" && r2.notes.contains("value:") && r2.notes.contains("86%"), "several unplaced slots are labelled in the notes (\(r2.notes))")
    let r3 = Deck.remap(parsed.slides[3], from: two, to: two)
    check(r3.unplaced.isEmpty && r3.moves.map(\.to) == ["title", "left", "right"], "the same template keeps every slot")
    let r4 = Deck.remap(Deck.Slide(template: "bullets", line: 1, lastLine: 3, slots: [
        Deck.Slot(name: "title", line: 2, lastLine: 2, lines: ["T"]), Deck.Slot(name: "_default", line: 3, lastLine: 3, lines: ["- a"])]), from: bullets, to: bullets)
    check(r4.moves.map(\.to) == ["title", "body"], "unheaded text counts as the default slot")

    // a pack's override (inside the target's yaml block) wins
    let pk = tmp.appending(path: "packs/northwind")
    try fm.createDirectory(at: pk, withIntermediateDirectories: true)
    try fm.copyItem(at: packs[0].appending(path: "northwind/northwind.pptx"), to: pk.appending(path: "northwind.pptx"))
    var md = try String(contentsOf: packs[0].appending(path: "northwind/northwind.md"), encoding: .utf8)
    md = md.replacingOccurrences(of: "fingerprint: title@0 body@1 body@2     # duo\n", with: "fingerprint: title@0 body@1 body@2     # duo\nfrom: {bullets: {body: left}, kpi: {context: right, label: left}}   # a pack's own carry-over\n")
    try md.write(to: pk.appending(path: "northwind.md"), atomically: true, encoding: .utf8)
    let opacks = [tmp.appending(path: "packs")]
    let opack = try Deck.loadPack("northwind", in: opacks)
    let two2 = opack.template("two-column")!
    check(two2.overrides == ["bullets": ["body": "left"], "kpi": ["context": "right", "label": "left"]], "from: is read from the yaml block (\(two2.overrides))")
    check(two2.slots.count == 3 && two2.layout == "Two Column", "the rest of the block still reads")
    let r5 = Deck.remap(s2, from: opack.template("bullets")!, to: two2)
    check(r5.unplaced.isEmpty && r5.moves.contains(Deck.Remap.Move(from: "body", to: "left")) && r5.slots[1].lines.count == 4, "with the pack's mapping, the body goes to left (\(r5.moves))")
    let r6 = Deck.remap(s3, from: opack.template("kpi")!, to: two2)
    check(r6.moves.map(\.to).sorted() == ["left", "right", "title"] && r6.unplaced == ["value"], "an override can map several slots; the rest go to the notes (\(r6.moves), \(r6.unplaced))")
    check(Deck.remap(s2, from: bullets, to: two, packOverrides: ["bullets": ["body": "right"]]).moves.contains(Deck.Remap.Move(from: "body", to: "right")), "overrides can be passed in")

    // the rewrite of a deck, comments with their text (DL-284)
    let src = try String(contentsOf: deck, encoding: .utf8)
    let ch = try Deck.changeTemplate(source: src, slide: 2, to: "two-column", pack: pack)
    let chp = Deck.parse(ch.text)
    check(chp.slides.count == 9 && chp.slides[1].template == "two-column" && chp.slides[0].template == "title", "change: slide 2 is now two-column, others untouched")
    check(chp.slides[1].notes.first == "Keep this short; the answers come on the next slides." && chp.slides[1].notes.contains("Not placed after changing to two-column: body"), "change: the old note stays and the unplaced text is added under it (\(chp.slides[1].notes))")
    check(chp.slides[1].notes.contains("- What breaks first in wet weather?"), "change: the points are in the notes")
    let after = tmp.appending(path: "decks/after.md")
    try ch.text.write(to: after, atomically: true, encoding: .utf8)
    let ac = try Deck.check(deck: after, packDirs: packs)
    check(ac.problems.isEmpty && ac.notices.count == 2 && ac.notices.allSatisfy { $0.message.hasSuffix("is empty") }, "change: the result checks clean, with two empty-slot notices (\(ac.problems.map(\.message)), \(ac.notices.map(\.message)))")
    check(Array(src.components(separatedBy: "\n").prefix(parsed.slides[1].line - 1)) == Array(ch.text.components(separatedBy: "\n").prefix(parsed.slides[1].line - 1)), "change: everything before the slide is byte-identical")
    check(ch.text.components(separatedBy: "<!-- slide: ").dropFirst(3).joined() == src.components(separatedBy: "<!-- slide: ").dropFirst(3).joined(), "change: every slide after it is byte-identical")

    let commented = src.replacingOccurrences(of: "- Can one picker robot work a full row unattended?\n", with: "- Can one picker robot work a full row unattended?\n{>>@sam 2026-10-31 #c9: say which robot<<}\n")
    check(commented != src, "(fixture) the comment was added")
    let cp = Deck.parse(commented)
    check(cp.slides[1].slot("_default")?.marks.map(\.kind) == ["comment"], "the comment is in the body text's anchor map")
    let cc = try Deck.changeTemplate(source: commented, slide: 2, to: "two-column", pack: pack)
    check(cc.text.contains("> {>>@sam 2026-10-31 #c9: say which robot<<}"), "a comment travels with its text into the notes")
    let cm = try Deck.changeTemplate(source: commented, slide: 2, to: "two-column", pack: opack)
    check(cm.text.contains("## left\n- Can one picker robot work a full row unattended?\n{>>@sam 2026-10-31 #c9: say which robot<<}") && Deck.parse(cm.text).slides[1].slot("left")?.marks.count == 1, "a comment travels with its slot when the pack maps it (\(cm.text.components(separatedBy: "\n").prefix(30).joined(separator: "|")))")
    check((try? Deck.changeTemplate(source: src, slide: 99, to: "kpi", pack: pack)) == nil && (try? Deck.changeTemplate(source: src, slide: 1, to: "nope", pack: pack)) == nil, "change refuses a missing slide or template")

    // dated exports (DL-282, DL-286)
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
    let t1 = utc.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14, minute: 5))!
    let t2 = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9, minute: 30))!
    let utcZone = TimeZone(identifier: "UTC")!
    check(Deck.exportName(deckName: "field-trial-review", at: t1, timeZone: utcZone) == "field-trial-review 2026-10-31 1405.pptx", "export name: <deck> YYYY-MM-DD HHmm.pptx")
    check(Deck.isExport("field-trial-review 2026-10-31 1405.pptx", of: "field-trial-review") && !Deck.isExport("field-trial-review-v2 2026-10-31 1405.pptx", of: "field-trial-review")
          && !Deck.isExport("field-trial-review.pptx", of: "field-trial-review") && !Deck.isExport("field-trial-review 2026-10-31 1405 copy.pptx", of: "field-trial-review"), "only this deck's dated exports match")
    let edir = tmp.appending(path: "export")
    try fm.createDirectory(at: edir, withIntermediateDirectories: true)
    try fm.copyItem(at: study.appending(path: "decks/assets"), to: edir.appending(path: "assets"))
    let edeck = edir.appending(path: "field-trial-review.md")
    try src.write(to: edeck, atomically: true, encoding: .utf8)
    let other = edir.appending(path: "field-trial-review-v2 2026-10-31 1405.pptx")
    try Data("not this deck's".utf8).write(to: other)
    let e1 = try Deck.writeExport(deck: edeck, packDirs: packs, now: t1, timeZone: utcZone)
    check(e1.url.lastPathComponent == "field-trial-review 2026-10-31 1405.pptx" && e1.removed.isEmpty && fm.fileExists(atPath: e1.url.path), "export writes the dated file beside the deck")
    let e2 = try Deck.writeExport(deck: edeck, packDirs: packs, now: t2, timeZone: utcZone)
    let left = (try fm.contentsOfDirectory(atPath: edir.path)).filter { $0.hasSuffix(".pptx") }.sorted()
    check(left == ["field-trial-review 2026-11-02 0930.pptx", "field-trial-review-v2 2026-10-31 1405.pptx"] && e2.removed.map(\.lastPathComponent) == ["field-trial-review 2026-10-31 1405.pptx"], "the next export removes the deck's previous one and nothing else (\(left))")
    check((try Data(contentsOf: e2.url)) == (try Deck.export(deck: edeck, packDirs: packs)), "the bytes depend on the source, not on the time")
    let e3 = try Deck.writeExport(deck: edeck, packDirs: packs, now: t2, timeZone: utcZone)
    check(e3.removed.isEmpty && fm.fileExists(atPath: e3.url.path), "exporting twice in one minute rewrites the same file")
    let outDir = tmp.appending(path: "elsewhere")
    let e4 = try Deck.writeExport(deck: edeck, packDirs: packs, dir: outDir, now: t1, timeZone: utcZone)
    check(e4.url.deletingLastPathComponent().lastPathComponent == "elsewhere" && fm.fileExists(atPath: e4.url.path), "--out puts it in another folder")
    let bad = tmp.appending(path: "decks/broken.md")
    let before = (try fm.contentsOfDirectory(atPath: tmp.appending(path: "decks").path)).count
    check(try (try? Deck.writeExport(deck: bad, packDirs: packs, now: t1)) == nil && (try fm.contentsOfDirectory(atPath: tmp.appending(path: "decks").path)).count == before, "a failed export writes and removes nothing")

    // the built-in pack
    let builtIn = try Deck.builtInPackDir()
    let plain = try Deck.loadPack("duo-plain", in: [builtIn])
    check(plain.templates.map(\.name) == ["title", "section", "bullets", "two-column", "kpi", "quote", "image", "table"], "duo-plain has the 8 templates")
    check(plain.front["google-heading-font"] == "Inter" && plain.front["body-font"] == "Inter", "duo-plain uses Inter, a Google Font")
    let pdirs = Deck.packDirs(near: tmp.appending(path: "decks"))
    check(pdirs.last == builtIn && pdirs.first?.standardizedFileURL.path == tmp.appending(path: "decks/templates/decks").standardizedFileURL.path, "pack lookup: nearest first, the built-in pack last")
    check(Deck.packs(in: pdirs).contains { $0.name == "duo-plain" }, "the built-in pack is found")
    let cat = Deck.catalogue(plain)
    check(cat.hasPrefix("duo-plain (") && cat.contains("value: number ≤7") && cat.contains("body: bullets ≤110 ×6 levels 2 (default)"), "the catalogue is compact (\(cat.split(separator: "\n").count) lines)")

    // new deck and insert, then every template exported from its bare skeleton
    var text = Deck.newDeckText(title: "Autumn trial", pack: plain)
    let nd = tmp.appending(path: "decks/autumn.md")
    try text.write(to: nd, atomically: true, encoding: .utf8)
    let nc = try Deck.check(deck: nd, packDirs: [builtIn])
    check(nc.problems.isEmpty && Deck.parse(text).slides.count == 1 && Deck.parse(text).front["template"] == "duo-plain", "a new deck is a title slide on the pack")
    for t in plain.templates { text = try Deck.insertSlide(source: text, template: t, after: nil) }
    text = try Deck.insertSlide(source: text, template: plain.template("quote")!, after: 0)
    let np = Deck.parse(text)
    check(np.slides.count == 10 && np.slides[0].template == "quote" && np.slides[1].template == "title" && np.slides.last?.template == "table", "insert: --after 0 goes first, the default goes last (\(np.slides.map(\.template)))")
    text = try Deck.insertSlide(source: text, template: plain.template("section")!, after: 1)
    check(Deck.parse(text).slides.map(\.template).prefix(3) == ["quote", "section", "title"], "insert: --after 1 goes between")
    try text.write(to: nd, atomically: true, encoding: .utf8)
    let sk = try Deck.check(deck: nd, packDirs: [builtIn])
    check(sk.problems.filter { !$0.message.contains("no file") }.isEmpty, "bare skeletons check without errors (\(sk.problems.map(\.message)))")
    check(sk.notices.count > 10, "and give notices for their empty slots (\(sk.notices.count))")
    let skOut = tmp.appending(path: "skeleton.pptx")
    // images have no file yet, so the skeleton's image slot is empty text; export it as is
    try Deck.export(deck: nd, packDirs: [builtIn]).write(to: skOut)
    let sg = try Deck.inspect(skOut)
    check(sg.slides.count == 11, "a deck of empty skeletons exports (\(sg.slides.count) slides)")
    check(sg.slides.map(\.layout).prefix(3) == ["Quote", "Section", "Title"], "duo-plain layouts are used by name (\(sg.slides.map(\.layout)))")

    // the skill
    let skill = Installer.skill()
    let verbs = skill.matches(of: /`duo2 (deck [a-z]+(?: [a-z]+)?(?: [a-z]+)?)/).map { String($0.1) }
    check(skill.contains("## Decks") && !verbs.isEmpty && verbs.allSatisfy { DuoAction.resolve($0.split(separator: " ").map(String.init)) != nil },
          "the skill's Decks section names only real verbs (\(Set(verbs).sorted()))")
    check(skill.contains("Don't run python-pptx") && skill.contains("Never open a pack's pptx") && skill.contains("`duo2 deck check <deck>`"), "the Decks section carries the rules")
    check(DuoAction.all.filter { $0.family == .deck }.allSatisfy { ($0.local || [.deckTemplatePick, .deckTemplatePicked, .deckShowing, .deckGo, .deckPick].contains($0.id)) && $0.ui.isEmpty }, "the deck verbs are local and CLI-only, except template pick/picked (waiting for their design) and deck, deck go, deck pick (the deck in split view, P3a: they ask the app)")
    try deckP2Checks(tmp: tmp, study: study)
}
