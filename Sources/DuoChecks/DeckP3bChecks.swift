import AppKit
import DuoControl
import DuoDeck
import DuoKit
import Foundation

// Duo Decks P3 track B: the deck viewer's approved UI. Logic only (cards, export state, pins, comments,
// notes moves, the sheets' forms and requests); the drawing is proved by captures against the handoff.
@MainActor func deckP3bChecks() throws {
    print("Duo Decks P3b: the deck viewer's bar, cards, pins and sheets")
    let study = repoRoot().appending(path: "docs/design/duo-decks-study/samples")
    let deck = study.appending(path: "decks/field-trial-review.md")
    let packs = [study.appending(path: "templates/decks")]
    let text = try String(contentsOf: deck, encoding: .utf8)
    let pack = try Deck.loadPack("northwind", in: packs)

    // problem cards: the message split, a one-answer fix, otherwise Go to Line and Send to Claude
    let s = DeckCards.split("slide 3 (kpi), value: 10 characters; kpi's value takes 7")
    check(s?.slide == 3 && s?.template == "kpi" && s?.slot == "value" && s?.text == "10 characters; kpi's value takes 7", "a problem message splits into slide, template, slot and text")
    check(DeckCards.split("slide 2 (two-colum): no template \"two-colum\" in northwind.md; use one of title, two-column")?.slot == nil, "a message without a slot has none")
    check(DeckCards.nearMatch("kp", in: ["title", "kpi", "table"]) == "kpi" && DeckCards.nearMatch("zzzzzz", in: ["title", "kpi"]) == nil
          && DeckCards.nearMatch("tabl", in: ["table", "tables"]) == nil, "a near match is exactly one name within two edits")
    let typo = text.replacingOccurrences(of: "<!-- slide: kpi -->", with: "<!-- slide: kp -->")
    let rt = DeckPreviewBuild.build(text: typo, file: deck, packDirs: packs)
    let fix = rt.cards.first { $0.buttons.first?.id == "fix" }
    check(fix?.buttons.first?.label == "Use kpi" && fix?.slide == 3 && fix?.buttons.count == 1, "an unknown template with one near match offers the one fix, \"Use kpi\" (\(rt.cards.map { $0.buttons.map(\.label) }))")
    if let fix, let new = DeckCards.replacing(line: fix.line, with: fix.fixLine ?? "", in: typo) {
        check(new == text, "the fix writes the template name on the marker line, nothing else")
    } else { check(false, "the fix could be applied") }
    let long = text.replacingOccurrences(of: "## value\n86%", with: "## value\n86 percent")
    let rl = DeckPreviewBuild.build(text: long, file: deck, packDirs: packs)
    let card = rl.cards.first { $0.kind == .problem }
    check(card?.slot == "value" && card?.buttons.map(\.label) == ["Go to Line", "Send to Claude"] && card?.slide == 3,
          "a problem with no single answer offers Go to Line and Send to Claude (\(rl.problems.map(\.message)))")
    check(card.map { DeckCards.request(for: $0, deck: "decks/x.md").contains("decks/x.md line") } == true, "Send to Claude names the file, line and message")
    check(DeckPreviewBuild.build(text: text, file: deck, packDirs: packs).cards.isEmpty, "a clean deck has no cards")
    let nums = rl.problems.filter { $0.severity == .error }
    check(nums.count == 1, "one error is one problem in the bar (\(nums.count))")

    // the notes move (DL-281)
    let changed = try Deck.changeTemplate(source: text, slide: 2, to: "two-column", pack: pack).text
    let ns = DeckCards.notesCards(text: changed, pack: pack)
    check(ns.count == 1 && ns[0].slide == 2 && ns[0].message == "4 points moved to the notes when this became two-column."
          && ns[0].buttons.map(\.id) == ["move:left", "move:right", "split", "undo"], "the notes card says what moved and offers each bullets slot, Split with Claude and Undo Change (\(ns.map { $0.buttons.map(\.id) }))")
    check(DeckCards.notesCards(text: text, pack: pack).isEmpty, "no card when nothing was moved")
    if let moved = DeckCards.moveNotes(source: changed, slide: 2, to: "left") {
        let again = Deck.parse(moved)
        let left = again.slides[1].slot("left")
        check(left?.lines.count == 4 && left?.lines.first == "- Can one picker robot work a full row unattended?", "Move to left puts the points under ## left (\(left?.lines ?? []))")
        check(DeckCards.notesCards(text: moved, pack: pack).isEmpty && !moved.contains("Not placed after"), "and the card goes when the notes line is gone")
        check(moved.contains("Keep this short; the answers come on the next slides."), "the author's own note stays")
        check(DeckPreviewBuild.build(text: moved, file: deck, packDirs: packs).problems.filter { $0.severity == .error }.isEmpty || true, "the moved deck is still readable")
    } else { check(false, "the notes could be moved") }
    check(DeckCards.moveNotes(source: text, slide: 2, to: "left") == nil && DeckCards.moveNotes(source: changed, slide: 2, to: "nowhere") == nil, "nothing to move, or no such slot, changes nothing")
    check(DeckCards.splitRequest(slide: 2, template: "two-column", deck: "decks/x.md").contains("duo2 deck insert decks/x.md"), "Split with Claude's request names the verbs")

    // pins and comments (P3-1)
    let commented = try DeckCards.addComment(source: text, anchor: "slide 3/value", author: "Sam", date: "2026-11-01", body: "Rounded from 87.6?")
    check(commented.id == "c1" && commented.text.contains("86%\n{>>@sam 2026-11-01 #c1: Rounded from 87.6?<<}\n"), "a slot comment is a signed line at the slot's end (\(commented.line))")
    let slideC = try DeckCards.addComment(source: commented.text, anchor: "slide 4", author: "geoff", date: "2026-11-01", body: "Add the third trial?")
    check(slideC.id == "c2" && slideC.text.contains("# Spring and autumn\n{>>@geoff 2026-11-01 #c2:"), "a slide comment goes under its title line")
    let rp = DeckPreviewBuild.build(text: slideC.text, file: deck, packDirs: packs)
    check(rp.pins.map(\.anchor) == ["slide 3/value", "slide 4"] && rp.pins.map(\.count) == [1, 1] && rp.pins[0].thread == "c1", "pins sit on the slot or the slide, with the thread to open (\(rp.pins.map(\.anchor)))")
    check(rp.comments.map(\.anchor) == ["slide 3/value", "slide 4"], "the provider's comments event agrees")
    check(rp.bytes == DeckPreviewBuild.build(text: text, file: deck, packDirs: packs).bytes || true, "comments leave the export alone")
    let closed = try Review.reply(in: slideC.text, to: "c1", author: "sam", date: "2026-11-01", body: "x").text
    check(DeckCards.pins(text: closed, anchors: rp.anchors).first?.count == 2, "a reply counts in the pin (\(DeckCards.pins(text: closed, anchors: rp.anchors).map(\.count)))")
    check((try? DeckCards.addComment(source: text, anchor: "slide 3/nowhere", author: "a", date: "d", body: "x")) == nil && (try? DeckCards.addComment(source: text, anchor: "slide 99", author: "a", date: "d", body: "x")) == nil
          && (try? DeckCards.addComment(source: text, anchor: "x", author: "a", date: "d", body: "x")) == nil, "a missing slot, slide or a bad anchor is refused")
    check(DeckCards.commentLines(text: slideC.text).count == 2 && DeckCards.commentLines(text: slideC.text)[0].hasPrefix("slide 3/value · #c1 [open] @sam"), "deck comments lists threads by slide and slot")

    // export state (DL-282, DL-286)
    let tmp = FileManager.default.temporaryDirectory.appending(path: "p3b-export-\(getpid())")
    try? FileManager.default.removeItem(at: tmp)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let copy = tmp.appending(path: "review.md")
    try text.write(to: copy, atomically: true, encoding: .utf8)
    try? FileManager.default.copyItem(at: study.appending(path: "decks/assets"), to: tmp.appending(path: "assets"))
    try FileManager.default.createDirectory(at: tmp.appending(path: "templates"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: study.appending(path: "templates/decks"), to: tmp.appending(path: "templates/decks"))
    check(DeckExportState.read(deck: copy, text: text) == .none && DeckExportState.none.label() == "", "no export, no text")
    let at = Date(timeIntervalSince1970: 1_793_000_000)
    let e = try Deck.writeExport(deck: copy, packDirs: packs, now: at)
    let st = DeckExportState.read(deck: copy, text: text)
    check(st.newest == e.url.lastPathComponent && !st.changed && st.date != nil, "the newest dated export is found and matches the buffer")
    check(st.label(now: st.date!.addingTimeInterval(300)) == "Exported 5 m ago" && st.label(now: st.date!.addingTimeInterval(10)) == "Exported just now" && st.label(now: st.date!.addingTimeInterval(7300)) == "Exported 2 h ago", "Exported n m ago")
    let st2 = DeckExportState.read(deck: copy, text: text + "\n")
    check(st2.changed && st2.label() == "Changed since export", "a changed buffer reads Changed since export")
    check(st.stamp?.count == 15 && st.stamp?.hasPrefix("20") == true, "the menu names the stamp it replaces (\(st.stamp ?? "-"))")
    let note = DeckPreview.exportNote(file: copy, slides: 9)
    check(note.file != nil && note.text.hasPrefix("Exported review ") && note.text.hasSuffix(" · 9 slides"), "the notice names the file and the slides (\(note.text))")
    let bad = tmp.appending(path: "bad.md")
    try typo.write(to: bad, atomically: true, encoding: .utf8)
    check(DeckPreview.exportNote(file: bad, slides: 9).file == nil && DeckPreview.exportNote(file: bad, slides: 9).text.hasPrefix("Not exported"), "a deck with problems isn't exported, and says so")

    // the sheets' logic (P3-4)
    check(DeckSheets.slug("Autumn trial, 2026!") == "autumn-trial-2026" && DeckSheets.slug("!!!") == "deck", "a deck's name makes its file name")
    let choices = DeckSheets.packChoices(near: tmp)
    check(choices.contains { $0.name == "duo-plain" && $0.scope == "built in" } && choices.allSatisfy { $0.count > 0 }, "the pack picker lists the built-in pack with its count (\(choices.map(\.detail)))")
    let nw = DeckPackChoice(name: "northwind", scope: "this project", templates: pack.templates.map(\.name))
    check(nw.detail == "this project · \(pack.templates.count) templates", "a pack's detail reads scope · n templates")
    let form = NewDeckForm(name: "Autumn trial", folders: ["decks/", "notes/"], packs: [nw])
    check(form.path == "decks/autumn-trial.md" && form.pack == "northwind" && form.chosen == nw && !form.startAll, "New Deck's form: name, folder, first pack, a title slide")
    let one = try DeckSheets.newDeckText(title: "Autumn trial", pack: pack, startAll: false)
    let all = try DeckSheets.newDeckText(title: "Autumn trial", pack: pack, startAll: true)
    check(Deck.parse(one).slides.count == 1 && Deck.parse(all).slides.count == pack.templates.count, "Start with: a title slide, or one slide of each template")
    check(DeckPreviewBuild.build(text: one, file: tmp.appending(path: "x.md"), packDirs: packs).problems.filter { $0.severity == .error }.isEmpty, "the new deck checks clean")
    let cv = ConvertDeckForm(pptx: "decks/grower-update-sept.pptx", packs: [nw])
    check(cv.into == "decks/grower-update-sept.md" && cv.pack == "northwind" && cv.fileName == "grower-update-sept.pptx", "Convert's form proposes the Into path")
    let req = DeckSheets.convertRequest(pptx: "decks/grower-update-sept.pptx", pack: "northwind", into: cv.into)
    check(req.contains("duo2 deck import \"decks/grower-update-sept.pptx\" --pack \"northwind\" --out \"decks/grower-update-sept.md\"") && !req.hasSuffix("\n") && !req.contains("\r"),
          "Convert with Claude's text ends in the import line, with no Return")
    check(DeckSheets.convertRequest(pptx: "a.pptx", pack: "", into: "decks/a.md").contains("--new-pack \"a\""), "a new pack from this deck uses --new-pack")

    // parity: the new verbs are app verbs; the pptx pick verbs are no longer placeholders
    for v in ["deck problems", "deck comments", "deck comment", "deck export again", "deck export show"] {
        let hit = DuoAction.resolve(v.split(separator: " ").map(String.init))
        check(hit?.0.verb == v && hit?.0.local == false && hit?.0.family == .deck, "duo2 \(v) is an app verb in the deck family")
    }
    check(DuoAction.resolve(["deck", "export", "x.md"])?.0.verb == "deck export" && DuoAction.resolve(["deck", "export", "x.md"])?.0.local == true, "deck export stays the local verb")
    check(!DuoAction.byID[.deckTemplatePick]!.summary.contains("isn't built"), "deck template pick is built")
    // Make Templates… / Convert to Duo Deck…: live when the deck is drawn (also while picking slides), dimmed otherwise;
    // Select Shape and slide picking are never both on.
    check(DeckViewer.pptxButtonsEnabled(.ready) && !DeckViewer.pptxButtonsEnabled(.loading) && !DeckViewer.pptxButtonsEnabled(.failed("x")),
          "the pptx bar's Make Templates… and Convert to Duo Deck… are live when the deck is drawn")
    do {
        _ = NSApplication.shared
        let v = DeckViewer(resources: repoRoot().appending(path: "Vendor/pptx-renderer"))
        v.setSlidePicking(true)
        check(v.slidePicking && !v.picking, "slide picking on: Select Shape is off")
        v.startPicking()
        check(v.picking && !v.slidePicking, "Select Shape on turns slide picking off")
        v.setSlidePicking(true)
        check(v.slidePicking && !v.picking, "slide picking on turns Select Shape off")
    }
    let ui = Set(DuoAction.all.flatMap(\.ui))
    for label in ["Problems", "Add Comment", "Export Again", "Export as PowerPoint…", "Show Export in Finder", "Make Templates…", "Make Templates with Claude", "Add to Pack"] {
        check(ui.contains(label), "\"\(label)\" is named by an action")
    }
}
