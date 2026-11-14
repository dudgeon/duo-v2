import DuoControl
import DuoDeck
import DuoKit
import Foundation

// Duo Decks P3 track C (DL-295, DL-296, DL-303): the editor's pieces. The page draws the chip, the picker and the anchor
// mark; these checks cover what Swift decides: the templates the picker lists, a pick's text (the same code as
// `duo2 deck insert` and `deck change`), the anchor's lines, and that the page's skeleton matches Deck.skeleton.
@MainActor func deckEditorChecks() throws {
    print("Duo Decks in the editor: chip, picker, anchor (DL-295, DL-296, DL-303)")
    let dir = try Deck.builtInPackDir()
    let pack = try Deck.loadPack(Deck.builtInPackName, in: [dir])
    let deck = Deck.newDeckText(title: "Trial", pack: pack)
    var text = deck
    // Two more slides so there is something to go between.
    text = try Deck.insertSlide(source: text, template: pack.template("bullets")!, after: nil)
    text = try Deck.insertSlide(source: text, template: pack.template("kpi")!, after: nil)

    // The picker's list.
    let json = EditorController.deckTemplatesJSON(pack)
    let obj = (try JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    let list = obj?["templates"] as? [[String: Any]] ?? []
    check(obj?["pack"] as? String == pack.name && list.count == pack.templates.count && list.count >= 6, "the picker lists the pack's templates (\(list.count) in \(pack.name))")
    check(list.allSatisfy { ($0["name"] as? String)?.isEmpty == false && $0["purpose"] is String && ($0["slots"] as? [[String: String]])?.isEmpty == false }, "each row has a name, a purpose and its slots")
    check(list.contains { ($0["name"] as? String) == "kpi" && ($0["purpose"] as? String)?.isEmpty == false }, "kpi is there with its purpose")

    // New Slide: the skeleton goes under the caret's slide; the caret lands in the title.
    let ins = try EditorController.deckPicked(op: "insert", slide: 1, template: "kpi", text: text, pack: pack)
    check(ins.text == (try Deck.insertSlide(source: text, template: pack.template("kpi")!, after: 1)), "a pick inserts exactly what `duo2 deck insert` does")
    let slides = Deck.parse(ins.text).slides
    check(slides.count == Deck.parse(text).slides.count + 1 && slides[1].template == "kpi", "…as slide 2, after the caret's slide 1")
    let titleLine = ins.text.components(separatedBy: "\n")[ins.line - 1]
    check(titleLine == "# ", "…and the caret goes to the new slide's empty title line (\(ins.line): \"\(titleLine)\")")
    let first = try EditorController.deckPicked(op: "insert", slide: 0, template: "title", text: text, pack: pack)
    check(Deck.parse(first.text).slides[0].template == "title", "slide 0 puts the new slide first")

    // The chip: change.
    let chg = try EditorController.deckPicked(op: "change", slide: 2, template: "two-column", text: text, pack: pack)
    let direct = try Deck.changeTemplate(source: text, slide: 2, to: "two-column", pack: pack)
    check(chg.text == direct.text && Deck.parse(chg.text).slides[1].template == "two-column", "a chip's pick changes the template exactly as `duo2 deck change` does")
    check(chg.text.components(separatedBy: "\n")[chg.line - 1] == "<!-- slide: two-column -->", "…and the marker line is the line reported")
    var threw = false
    do { _ = try EditorController.deckPicked(op: "change", slide: 9, template: "kpi", text: text, pack: pack) } catch { threw = true }
    check(threw, "a slide that isn't there is refused, not applied")
    threw = false
    do { _ = try EditorController.deckPicked(op: "insert", slide: 1, template: "nope", text: text, pack: pack) } catch { threw = true }
    check(threw, "so is a template the pack doesn't have")

    // The anchor mark: the lines of the slide holding the caret.
    let marks = text.components(separatedBy: "\n").enumerated().filter { $0.element.hasPrefix("<!-- slide:") }.map { $0.offset + 1 }
    let a1 = EditorController.deckAnchor(text: text, line: marks[1] + 1)
    check(a1?.first == marks[1] && (a1?.last ?? 0) >= marks[1] + 1, "the caret in slide 2 anchors from its marker (line \(marks[1])) to its last line (\(a1?.last ?? 0))")
    check(EditorController.deckAnchor(text: text, line: 1) == nil, "above the first slide there is no anchor")
    let a0 = EditorController.deckAnchor(text: text, line: text.components(separatedBy: "\n").count)
    check(a0?.first == marks.last, "the last slide anchors to the end of the file")

    // The page: only two lines changed in duo-editor.js; the chip, the skeleton and the label come from deck.js.
    let src = repoRoot().appending(path: "Vendor/codemirror/src")
    let ed = (try? String(contentsOf: src.appending(path: "duo-editor.js"), encoding: .utf8)) ?? ""
    let js = (try? String(contentsOf: src.appending(path: "deck.js"), encoding: .utf8)) ?? ""
    check(ed.contains("import { deckExtensions } from \"./deck.js\"") && ed.contains("...deckExtensions(),"), "duo-editor.js imports deckExtensions and spreads it into extensions()")
    check(js.contains("`<!-- slide: ${t.name} -->`") && js.contains("out.push(\"# \")") && js.contains("`## ${s.name}`"), "the page's skeleton is Deck.skeleton's: marker, an empty title, a heading per other slot")
    check(js.contains("`Slide ${n}`") && js.contains("\"⌄\""), "the chip reads \"Slide n · name ⌄\"")
    check(js.contains("var(--duo-rule)") && js.contains("var(--duo-control-edge)") && !js.contains("#"+"fff") && js.range(of: #"#[0-9a-fA-F]{6}\b"#, options: .regularExpression) == nil, "the page takes colours from the theme's variables, no raw hex")

    // ⌃⌘N: a chord that adds to DL-34, enabled only in a deck, in the Format menu; its verb is deck insert.
    check(DuoCommand.newSlide.shortcut != nil && DuoCommand.newSlide.title == "New Slide", "⌃⌘N is New Slide")
    check(DuoAction.all.first { $0.id == .deckInsert }?.ui.contains("New Slide") == true && DuoAction.all.first { $0.id == .deckChange }?.ui.contains("Slide chip") == true, "New Slide names `deck insert` and the chip names `deck change` (DL-71)")
    check(["Template picker's typing", "Slide chip's look", "Slide anchor mark"].allSatisfy { Parity.uiOnly[$0] != nil }, "the picker's typing, the chip's look and the anchor mark are in Parity.uiOnly, with why")
}
