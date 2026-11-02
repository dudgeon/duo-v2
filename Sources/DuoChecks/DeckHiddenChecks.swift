import DuoControl
import DuoKit
import Foundation

// DL-307 (F-533): one switch, DeckFeature, keeps Duo Decks out of a release build. These checks turn it off and on with
// `DeckFeature.override` and look at what a person and Claude would see: duo2 help, the primer, the skill, verb lookup,
// split view's deck kind, the menus, the editor's page and the .pptx bar. Debug builds (DuoChecks) have it on.
@MainActor func deckHiddenChecks() throws {
    print("Duo Decks hidden in a release build (DL-307)")
    defer { DeckFeature.override = nil }
    check(DeckFeature.builtOn, "a debug build (DuoChecks, Duo Dev) has Duo Decks on")

    DeckFeature.override = false
    check(!ActionFamily.shown.contains(.deck) && ActionFamily.shown.count == ActionFamily.allCases.count - 1, "off: the deck family isn't shown")
    let help = DuoAction.help()
    check(!help.contains("deck "), "off: duo2 help lists no deck verbs")
    check(!DuoAction.help(family: "deck").contains("deck check"), "off: duo2 help deck shows the overview, not the deck verbs")
    check(DuoAction.resolve(["deck", "check", "a.md"]) == nil && DuoAction.resolve(["deck", "template", "build", "x"]) == nil
          && DuoAction.resolve(["deck", "new", "x"]) == nil, "off: deck verbs are unknown to duo2 and the app")
    check(DuoAction.resolve(["slide", "go", "2"]) != nil && DuoAction.resolve(["status"]) != nil, "off: the other verbs, the .pptx viewer's included, still resolve")
    check(!DuoAction.primer().contains("deck"), "off: the primer names no deck family")
    let skill = Installer.skill()
    check(!skill.contains("## Decks") && !skill.contains("duo2 help deck") && skill.contains("## Families"), "off: the skill has no Decks section and no deck family")
    check(!DeckPreviewRegistration.test("decks/a.md", ["type": "deck"]), "off: a type: deck note isn't a deck to split view")
    DeckPreviewRegistration.install()
    check(PreviewProviders.kind(forFile: "decks/a.md", frontmatter: ["type": "deck"]) == nil, "off: a type: deck note opens as plain Markdown, with no split tab")
    check(parityGaps().isEmpty, "off: Parity stays clean")

    DeckFeature.override = true
    check(DuoAction.resolve(["deck", "check", "a.md"]) != nil && DuoAction.help().contains("deck check"), "on: the deck verbs are back")
    check(Installer.skill().contains("## Decks") && Installer.skill().contains("### Making templates"), "on: the skill's Decks section is back")
    check(PreviewProviders.kind(forFile: "decks/a.md", frontmatter: ["type": "deck"]) == .deck, "on: a type: deck note gets the deck split tab")
    DeckFeature.override = nil

    // The views read the switch where they draw (no model needed to see it).
    let src = { (p: String) in (try? String(contentsOf: repoRoot().appending(path: p), encoding: .utf8)) ?? "" }
    let commands = src("Sources/DuoKit/Navigation/Commands.swift")
    check(commands.contains("if DeckFeature.enabled { item(.newDeck) }") && commands.contains("if DeckFeature.enabled { item(.newSlide) }"),
          "off: File › New Deck… and Format › New Slide (⌃⌘N) are absent from the menus")
    check(commands.contains("case .newDeck: DeckFeature.enabled &&") && commands.contains("case .newSlide: DeckFeature.enabled &&"), "off: their commands are disabled too")
    let panes = src("Sources/DuoKit/Project/ProjectPanes.swift")
    check(panes.contains("if DeckFeature.enabled { Button(\"New Deck…\")") && panes.contains("if DeckFeature.enabled, !isFolder, path.lowercased().hasSuffix(\".pptx\")"),
          "off: the Files + menu has no New Deck…, and a .pptx's menu no Convert to Duo Deck…")
    let view = src("Sources/DuoKit/Project/DeckView.swift")
    if let a = view.range(of: "private var legacyBar"), let b = view.range(of: "private var deckBar") {
        let legacy = view[a.upperBound..<b.lowerBound]
        check(!legacy.contains("DeckPptxButtons") && !legacy.contains("Convert") && legacy.contains("OpenWithMenu") && legacy.contains("Select Shape"),
              "off: a .pptx's bar is 0.2.22's (‹ › count, Select Shape, Open With), with no Make Templates… or Convert")
    } else { check(false, "DeckBar has the 0.2.22 bar for Decks off") }
    check(view.contains("if preview == nil && !DeckFeature.enabled { legacyBar }"), "off: the plain .pptx draws that bar")
    check(src("Sources/DuoKit/Editor/DocumentEditor.swift").contains("window.__duoDecksOff = true;"), "off: the editor's page is told at document start")
    check(src("Vendor/codemirror/src/deck.js").contains("window.__duoDecksOff) return false") && src("Vendor/codemirror/dist/cm6.js").contains("__duoDecksOff"),
          "off: the page treats a type: deck note as plain Markdown (no chips, picker or anchors), and cm6.js is rebuilt")
    check(src("Sources/DuoKit/Editor/EditorController+Deck.swift").contains("isDeck = DeckFeature.enabled &&"), "off: the editor never thinks it's in a deck")
}
