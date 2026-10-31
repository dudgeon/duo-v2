import CryptoKit
import DuoDeck
import DuoSearch
import Foundation

// Duo Decks P0 spike (DL-267, DL-268, DL-270): the Swift writer turns the sample deck and the Northwind
// pack into a correct, deterministic pptx, and the checker reports the prototype's three errors on a
// broken copy. `DUO_CHECKS=deck swift run DuoChecks`; DUO_DECK_OUT=<file> also keeps the export.
func deckChecks() throws {
    print("Duo Decks: parse, check, export (DL-267, DL-268, DL-270)")
    let study = repoRoot().appending(path: "docs/design/duo-decks-study/samples")
    let deck = study.appending(path: "decks/field-trial-review.md")
    let packs = [study.appending(path: "templates/decks")]

    // parse + anchor map
    let parsed = Deck.parse(try String(contentsOf: deck, encoding: .utf8))
    check(parsed.problems.isEmpty && parsed.slides.count == 9, "the sample parses to 9 slides with no problems (\(parsed.slides.count))")
    check(parsed.slides.map(\.template) == ["title", "bullets", "kpi", "two-column", "image", "table", "quote", "section", "bullets"], "templates in order")
    check(parsed.slides[1].notes == ["Keep this short; the answers come on the next slide."] || parsed.slides[1].notes.count == 1, "slide 2 has its note")
    check(parsed.slides[2].slot("value")?.lines == ["86%"] && parsed.slides[2].slot("value")?.line == 31, "anchor map: kpi value is at line 31 (\(parsed.slides[2].slot("value")?.line ?? 0))")
    check(parsed.slides[0].line == 8 && parsed.slides[0].lastLine < 15 && parsed.slides[1].line > parsed.slides[0].lastLine, "anchor map: slide line ranges don't overlap")

    // pack loader
    let pack = try Deck.loadPack("northwind", in: packs)
    check(pack.templates.map(\.name) == ["title", "section", "bullets", "two-column", "kpi", "quote", "image", "table"], "pack lists its 8 templates")
    check(pack.template("kpi")?.slots.map(\.idx) == [0, 13, 14, 15] && pack.template("kpi")?.layout == "Big Number", "kpi: layout Big Number, idx 0 13 14 15")
    check(pack.template("image")?.slot("image")?.aspect == 1.52 && pack.template("bullets")?.slot("body")?.isDefault == true, "flow-map values: aspect 1.52, default true")

    // check: the sample is clean; a broken copy gives the three errors
    let ok = try Deck.check(deck: deck, packDirs: packs)
    check(ok.problems.isEmpty, "the sample deck has no problems (\(ok.problems.map(\.message)))")
    let tmp = FileManager.default.temporaryDirectory.appending(path: "duo-deck-p0-\(getpid())")
    try? FileManager.default.removeItem(at: tmp)
    try FileManager.default.createDirectory(at: tmp.appending(path: "decks"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try FileManager.default.copyItem(at: study.appending(path: "decks/assets"), to: tmp.appending(path: "decks/assets"))
    var broken = try String(contentsOf: deck, encoding: .utf8)
    broken = broken.replacingOccurrences(of: "- What breaks first in wet weather?\n", with: "- What breaks first in wet weather?\n- One\n- Two\n- Three\n- Four\n")
    broken = broken.replacingOccurrences(of: "## value\n86%", with: "## value\n86% of all")
    broken = broken.replacingOccurrences(of: "<!-- slide: two-column -->", with: "<!-- slide: comparison -->")
    let brokenURL = tmp.appending(path: "decks/broken.md")
    try broken.write(to: brokenURL, atomically: true, encoding: .utf8)
    let bad = try Deck.check(deck: brokenURL, packDirs: packs)
    check(bad.problems.count == 3, "the broken copy has 3 problems (\(bad.problems.map { "\($0.line): \($0.message)" }))")
    let report = Deck.report("decks/broken.md", bad.problems)
    let expected = [
        "slide 2 (bullets), body: has 7 points; the template allows 6. Split the slide; never shrink the text",
        "slide 3 (kpi), value: is 10 characters; the template allows 7. Shorten it, or split the slide",
        "slide 4 (comparison): no template \"comparison\" in northwind.md; use one of title, section, bullets, two-column, kpi, quote, image, table",
    ]
    for e in expected { check(report.contains(e), "message: \(e.prefix(60))…") }
    check(report.hasSuffix("3 problems"), "ends with the count")
    check((try? Deck.export(deck: brokenURL, packDirs: packs)) == nil, "export refuses a deck with problems")

    // export, twice
    let t0 = Date()
    let a = try Deck.export(deck: deck, packDirs: packs)
    let seconds = Date().timeIntervalSince(t0)
    let b = try Deck.export(deck: deck, packDirs: packs)
    check(a == b, "deterministic: two exports are identical bytes")
    let sha = SHA256.hash(data: a).map { String(format: "%02x", $0) }.joined()
    print("    \(a.count) bytes, sha256 \(sha), \(String(format: "%.0f", seconds * 1000)) ms")
    let file = ProcessInfo.processInfo.environment["DUO_DECK_OUT"].map { URL(fileURLWithPath: $0) } ?? tmp.appending(path: "out.pptx")
    try a.write(to: file)

    // read it back
    let got = try Deck.inspect(file)
    check(got.slides.count == 9, "9 slides")
    let layouts = ["Title", "Title + Bullets", "Big Number", "Two Column", "Image + Caption", "Table", "Quote", "Section", "Title + Bullets"]
    check(got.slides.map(\.layout) == layouts, "each slide on its layout (\(got.slides.map(\.layout)))")
    check(got.slides.allSatisfy { s in s.shapes.filter { !["ftr", "sldNum"].contains($0.type) }.allSatisfy { !$0.ownBox } }, "placeholders carry no box of their own")
    check(got.slides.allSatisfy { s in s.shapes.contains { $0.type == "ftr" && $0.text == "Northwind Labs · Internal" } && s.shapes.contains { $0.type == "sldNum" } }, "footer text and slide number on every slide")
    check(got.slides[2].shapes.map(\.idx) == [0, 13, 14, 15, 11, 12], "kpi fills idx 0 13 14 15 then footer 11, number 12 (\(got.slides[2].shapes.map(\.idx)))")
    check(got.slides[1].notes?.contains("Keep this short") == true && got.slides[8].notes?.contains("Close on the asks") == true, "notes on slides 2 and 9")
    check(got.slides.enumerated().allSatisfy { [1, 8].contains($0.offset) || $0.element.notes == nil }, "no notes elsewhere")
    check(got.slides[4].shapes.contains { $0.element == "pic" && $0.type == "pic" && $0.idx == 1 }, "slide 5 has a picture in placeholder 1")
    let tbl = got.slides[5].shapes.first { $0.table != nil }
    check(tbl?.table?.rows == 5 && tbl?.table?.cols == 3 && tbl?.type == "tbl", "slide 6 has a 5x3 table at the table placeholder")
    check(got.slides[1].shapes.first { $0.idx == 1 }?.text == "Can one picker robot work a full row unattended?\nHow often does a person need to step in?\nper row, and per hour of picking\nWhat breaks first in wet weather?", "bullets text")
    let source = try Data(contentsOf: deck)
    check(got.customProperties["duoSourceSha"] == SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined(), "duoSourceSha is the deck's sha-256")

    // Review marks (CriticMarkup, DL-236) are not content: stripped for checks and export, kept in the anchor map.
    let rv = """
    ---
    type: deck
    title: Review marks
    template: northwind
    footer: Northwind Labs · Internal
    ---

    <!-- slide: title -->
    {>>@sam 2026-10-31 #c1: is this the right title?<<}
    # Field {++trial ++}review

    Orchard team{>>@geoff 2026-10-31 #c2: name the farms<<}

    <!-- slide: kpi -->
    # Unattended rows

    ## value
    {==86%==}{>>@sam 2026-10-31 #c3: source?<<}

    ## label
    of rows done

    ## context
    {~~Up from 61%~>Up from 60%~~} in the spring{--, roughly--}.
    """
    let rvURL = tmp.appending(path: "decks/review.md")
    try rv.write(to: rvURL, atomically: true, encoding: .utf8)
    let rvp = Deck.parse(rv)
    check(rvp.problems.isEmpty && rvp.slides.count == 2, "review deck parses (\(rvp.problems))")
    check(rvp.slides[0].slot("title")?.lines == ["Field review"], "pending insertion: the title reads as before (\(rvp.slides[0].slot("title")?.lines ?? []))")
    check(rvp.slides[0].slot("_default")?.lines == ["Orchard team"], "a comment is not content")
    check(rvp.slides[1].slot("value")?.lines == ["86%"], "a highlight is its text")
    check(rvp.slides[1].slot("context")?.lines == ["Up from 61% in the spring, roughly."], "substitution reads as a, deletion as x (\(rvp.slides[1].slot("context")?.lines ?? []))")
    check(rvp.slides[0].marks.count == 1 && rvp.slides[0].marks[0].line == 9 && rvp.slides[0].marks[0].kind == "comment", "anchor map: the comment after the marker is the slide's, line 9 (\(rvp.slides[0].marks))")
    check(rvp.slides[0].slot("title")?.marks.map(\.kind) == ["insertion"], "anchor map: the insertion is in the title slot")
    check(rvp.slides[0].slot("_default")?.marks.map(\.line) == [12], "anchor map: the slot comment is at line 12 (\(rvp.slides[0].slot("_default")?.marks ?? []))")
    check(rvp.slides[1].slot("value")?.marks.map(\.kind) == ["highlight"] && rvp.slides[1].slot("value")?.marks.first?.line == 18, "anchor map: the highlight is in the value slot, line 18")
    check(rvp.slides[1].slot("context")?.marks.map(\.kind) == ["substitution", "deletion"], "anchor map: both suggestions are in the context slot")
    let rvOut = tmp.appending(path: "review.pptx")
    try Deck.export(deck: rvURL, packDirs: packs).write(to: rvOut)
    let rvGot = try Deck.inspect(rvOut)
    check(rvGot.slides[0].shapes.first?.text == "Field review" && rvGot.slides[1].shapes.first { $0.idx == 15 }?.text == "Up from 61% in the spring, roughly.", "the exported text has no marks")
    let rvAll = rvGot.slides.flatMap(\.shapes).map(\.text).joined()
    check(!rvAll.contains("{") && !rvAll.contains("@sam"), "no CriticMarkup in the pptx")
}
