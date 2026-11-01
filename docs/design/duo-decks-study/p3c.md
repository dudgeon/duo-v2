# Duo Decks P3 track C: the deck's editor pieces

Branch `build/duo-decks-editor` (from main 8ba74b25). Built to the approved P3-2 handoff (DL-295, DL-296, DL-303) and split view's anchor mark.

## What is built

| Piece | Where |
|---|---|
| Slide chip: each `<!-- slide: name -->` line is a block widget, 22 high, 1 pt `rule` above, "**Slide n** · name ⌄" in 11/20 (n semibold `text`, rest `text2`). The comment is hidden, the file is unchanged, and the line is an atomic range. A click opens the picker in change mode. | `Vendor/codemirror/src/deck.js` |
| ⌃⌘N New Slide: a pending chip under the caret's slide, the typed filter in it (pill), a list like the autocomplete (thumbnail, mono name, `text2` purpose, footer line). ↩ picks, Esc removes the pending chip, ↑↓ move, a click outside cancels. | `deck.js`; `DuoCommand.newSlide` in `Commands.swift` (Format menu, enabled only in a deck) |
| A pick runs in Swift (`EditorController+Deck.swift`): `Deck.insertSlide` or `Deck.changeTemplate` on the buffer's text, the same code as `duo2 deck insert` / `deck change`. The new text goes back as `duo.deckApply(text, line)`, one transaction (one undo step), the caret on the new slide's title. | `EditorController+Deck.swift` |
| Anchor mark: a 2 pt `controlEdge` bar, radius 1, 8 left of the text, over the caret's slide. The page reports the caret (120 ms debounce); Swift answers `duo.setDeckAnchor(first, last)` from `Deck.parse`. | `deck.js` layer; `deckAnchor` |
| `duo.revealDeckSlot(first, last)`: scrolls the lines into view, caret on the first content line, no focus taken. Also `EditorController.revealDeckSlot`. | `deck.js` |
| `duo.setDeckTemplates(json)`: pack name and templates (name, purpose, slots), sent when the page reports a `type: deck` document. | `deck.js`, `deckTemplatesJSON` |

`duo-editor.js` changed by the two agreed lines only. `dist/cm6.js` is rebuilt with `build.sh`.

## Verbs and parity

New Slide is on `deck insert`'s `ui:`, the chip on `deck change`'s. `Parity.uiOnly` gains "Template picker's typing", "Slide chip's look" and "Slide anchor mark". `docs/cli/duo2.md` is regenerated. The check that said deck verbs have no UI now allows insert and change.

## Checks

`DuoChecks/DeckEditorChecks.swift` (21): the list, a pick's text equals the verb's, the caret line, errors refused, the anchor's lines, the two-line `duo-editor.js` change, no raw hex, the chord, parity. `DocSafetyChecks` reads `deck.js` as well as `duo-editor.js`. Full DuoChecks: see the report.

## Proof

`scripts/check-deck-editor.sh` (isolated: `/private/tmp/p3c` support and config, `open -g`, no duo2 sent, no Claude turn). Fixture: `_HOME.md`, `work/orchard-robotics/_PROJECT.md`, `decks/field-trial-review.md`, `templates/decks/northwind`. Images in `docs/design/duo-decks-handoff/proof/`: `chip-*`, `picker-*` and `compare-picker-*` (target left, build right) for Light, Dark and Classic.

Measured against the target (P3-2-picker.png, 2 px per point; Light):
- The chip rule is 1 pt `#C9CDD3` (the `rule` token), the same colour as the target's.
- Picker: 320 wide (the target's is about 319), 10 radius, 6 padding, the selected row on `selected`, the footer line in `text2` 11.
- The anchor bar is 2 wide, `controlEdge`, left of the text column as in split-deck.

Differences, none a decision:
- **Thumbnails are stand-ins** (a schematic from the slot kinds); the target shows the real slide picture. `setDeckTemplates` takes a `thumb` URL, so a rendered picture drops in. Needs `deck render`, which isn't built (request below).
- The target's picker sits 40 pt lower, detached; the build sits 4 under the chip.
- The purpose wraps to up to three lines here; the target's wraps to two because its mock text is shorter.
- Light's chip number is semibold 11; the target's reads slightly smaller in the mock.

## Stand-ins and requests

- **Thumbnails**: needs `deck render` (or cached specimen pictures) to feed `thumb`. Request to the viewer track.
- **The editor's context menu "New Slide…"** (DL-295 lists it) is not added: the editor's menu is WebKit's own and has no Duo items yet. The Format menu and ⌃⌘N cover it. Request: a decision whether to add a Duo-built context menu.
- **The + between slides and its gallery** are the viewer's (slides side), not this track's.
- `src/deck-picker.js` was in the brief; the picker shares state with the chip, so it lives in `deck.js` to avoid a cycle. Say if it must be split.
- The caret in a captured background window gets no frames, so scrolling uses timers and `scrollIntoView` by hand; real use is unaffected.
- Not tried live: typing ⌃⌘N through the real menu (the capture runs the same `duo.deckNewSlide()` the menu calls).
