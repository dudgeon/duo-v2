# Duo Decks P3 track B: the deck viewer's approved UI

Branch `build/duo-decks-viewer`. Built to the approved handoff (`docs/design/duo-decks-handoff/`: `P3-1-comments`, `P3-3-problems`, `P3-4-sheets`, `make-templates`; DL-302 to DL-305, DL-291, DL-298, DL-281, DL-282, DL-286) on top of track A's provider (`p3a.md`), merged with split view's generic wiring (`PreviewProvider.bind`, the director's `register`) and track C (`p3c.md`). Both `bind` methods are kept (the exact-signature one and the optional-model one the checks use).

## What is built

| Piece | Where |
|---|---|
| **Deck bar** (P3-3): `‹ ›`, the count (`Slide 3 of 9`, `3/9` when narrow), **Problems ⌄** (only with errors: a triangle and "n problem(s)" semibold; its menu lists each error with its line, a rule, then the notices; choosing one reveals the slide in the preview and the lines in the source), the **export state** in `text2` ("Changed since export", "Exported 5 m ago", nothing), Select Shape, **Export ⌄** (Export as PowerPoint…, Export Again with "replaces <stamp>", Show Export in Finder, Upload to Google Slides… dimmed with "later"). After an export the DL-132 notice names the file and the slide count, with Show in Finder, Open With ⌄ and OK; it goes after ten seconds. | `Deck/DeckBarViews.swift`, `Deck/DeckPreview+Bar.swift`, `Project/DeckView.swift` (`DeckBar`) |
| **Export state**: the newest `<deck> YYYY-MM-DD HHmm.pptx` beside the deck; its `duoSourceSha` is compared with the buffer's SHA-256 (the export's property is read once per file and mtime). | `DeckExportState` in `Deck/DeckCards.swift` |
| **Cards under a slide** (P3-3), drawn by the renderer page (`Vendor/pptx-renderer/deck.js`, `deck.html`; not `Vendor/codemirror`): a **problem card** (slot semibold, the checker's message; one button when the answer is single, else Go to Line and Send to Claude) and the **notes-move card** (DL-281: "n points moved to the notes when this became t", Move to ‹slot› for each bullets slot of the template, Split with Claude, Undo Change). The number above each slide now reads "3 · kpi". | `DeckCards.problemCards`, `notesCards`, `moveNotes`; `DeckPreview.cardAction` |
| **One-answer fixes** (DL-298): an unknown template or slot with exactly one near match within two edits ("Use kpi"), and a renamed slot ("Use <new>", the migrate case). The fix rewrites that one line through the editor (`reviewWrite`, one undoable change). | `DeckCards.nearMatch` |
| **Comment pins** (P3-1): from the deck's open Review threads, an 18-high capsule on `pane` with a 1 pt `controlEdge` edge, a speech mark and the count in 10/16 semibold, at the slot box's top right (kept inside the slide when the box reaches its edge), or the slide's top right for a slide comment; hovering outlines the slot with its name tag as Select Shape does; a click emits `.openThread(thread:)`. A closed thread leaves no pin. Slot anchors now include the slot's trailing comment line, so "on its own line at the slot's end" belongs to the slot. | `DeckCards.pins`, `deck.js` (`applyOverlay`) |
| **Add Comment** first in the picked bar (default button; Send to Claude steps down to a plain button): emits `.addComment(anchor:)` for the slot or slide. | `DeckPickerBar`, `PickerButtonRow(addComment:)` |
| **pptx viewer bar** (P3-4, board 9A): Make Templates… and Convert to Duo Deck… beside Select Shape and Open With. Under 460 both fold into ⋯; in the narrowest pane (360) Open With goes in ⋯ too, so the bar still fits. **Make Templates…** turns on slide picking (a 28 tick box in each slide's corner, the picked ones ringed 2 pt in `text`, the slide's number semibold); the foot reads "**n slides picked** · click slides to pick them; Esc to stop", Cancel, **Add to Pack ⌄** (the project's and Home's packs) and **Make Templates with Claude**, which pastes `From <file>, slides 3 and 7:` / `make them templates in a pack.` / `duo2 deck template inventory "<path>" --slides 3,7` into Claude's prompt without Return (a new session if none shows). | `DeckPptxButtons`, `DeckSlidePickBar`, `AppModel.sendTemplatesRequest` |
| **New Deck…** sheet (P3-4 1): Name, Folder, Template pack (project, then Home, then built in, each "scope · n templates") with a strip of up to 8 template tiles, Start with (a title slide, or one slide of each template), Cancel / Create. Create writes the deck (the same text as `duo2 deck new`, plus `Deck.insertSlide` for "one of each") and opens it in its split tab. From Files' tree menu (New Deck…). | `Deck/DeckSheets.swift`; sheets hang from the toolbar through `SheetOverlay` |
| **Convert to Duo Deck…** sheet (P3-4 2): Template pack (or a new pack from this deck), Into; **Convert with Claude** pastes the request and the `duo2 deck import "<pptx>" --pack "<pack>" --out "<md>"` line without Return. From the pptx viewer's bar and Files' right-click on a .pptx. | `DeckSheets.convertRequest` |

## Verbs (DL-71)

New in `Actions.swift` (its own commit, one contiguous block): `deck problems`, `deck comments`, `deck comment`, `deck export again`, `deck export show`. All ask the app and work on the deck in split view or `--deck <file>`. `deck template pick [3,7]` / `picked` (registered in P2) are now handled by the app on the plain .pptx showing. The labels of the buttons above are on these verbs' `ui:` lists (and on `deck new`, `deck import`, `deck template pick/picked`); the pin's hover, the tiles and the pack strip are UI only. `docs/cli/duo2.md` is regenerated.

```
$ duo2 deck problems                       (the proof deck with "86 percent" in a kpi value)
decks/review.md: 1 problem, 2 notices
decks/review.md:36: error: slide 3 (kpi), value: is 10 characters; the template allows 7. Shorten it, or split the slide
decks/review.md:18: notice: slide 2 (two-column), left: is empty
decks/review.md:20: notice: slide 2 (two-column), right: is empty
$ duo2 deck comments
decks/verbs.md has no comment threads.
$ duo2 deck comment 3/value "Rounded from 87.6?" --as sam
Commented on slide 3/value as #c1 (line 33 of decks/verbs.md).
$ duo2 deck comment 4 "Add the third trial?" --as geoff
Commented on slide 4 as #c2 (line 45 of decks/verbs.md).
$ duo2 deck comments
decks/verbs.md
slide 3/value · #c1 [open] @sam: Rounded from 87.6? (line 33)
slide 4 · #c2 [open] @geoff: Add the third trial? (line 45)
$ duo2 deck export again
Exported verbs 2026-11-01 1445.pptx · 9 slides
$ duo2 deck template pick 3,7               (a plain .pptx showing)
The slide picker is on for grower-update.pptx: the user ticks slides; run `duo2 deck template picked` to read them.
$ duo2 deck template picked
grower-update.pptx: slides 3, 7 picked.
duo2 deck template inventory "…/grower-update.pptx" --slides 3,7
```

The author is what Review uses: `--as`, else `claude` when a Claude session runs the verb, else the Mac account (`reviewAuthor`, which is now internal rather than private). `deck export show` was not run live (it activates Finder, which a background run must not do); its path logic is the same as the Export menu's.

## Checks

`DUO_CHECKS=deckviewer` (`DuoChecks/DeckP3bChecks.swift`, 56 checks): the message split, the near match (exactly one within two edits), the fix writes only the marker line, a problem with no single answer offers Go to Line and Send to Claude, a clean deck has no cards, the notes card says what moved and offers each bullets slot, Move to ‹slot› moves the points and removes the card and keeps the author's own note, pins sit on the slot or slide with the thread to open and count replies, a slot comment is a signed line at the slot's end and a slide comment goes under its title, bad anchors are refused, export state (none, matches, changed, "Exported 5 m ago", the stamp), the notice's text, a deck with problems isn't exported, the sheets' forms and requests (no Return in them), and parity (the five new verbs are app verbs; the labels are on actions). The full DuoChecks, with these in the run (and track A's `deckpreview` checks, which weren't in it), pass: **5407 passed, 0 failed**; `scripts/check-records.sh`: ok. The check that said split view's lookup returns `.markdown` for a note now asks only that it isn't `.deck` (the Markdown preview kind left `Split/`).

## Proof

An isolated instance each time (`/tmp/p3b-sup` support, a scratch `CLAUDE_CONFIG_DIR`, `open -g`, no window shown, Haiku named, no Claude turn, quit by the instance's own pid; every `duo2` goes through a wrapper that refuses to run once that pid is gone, so nothing can reach another Duo, F-524). Fixture: Home `_HOME.md`, project `field-trials` (`_PROJECT.md`), `decks/field-trial-review.md` and copies (one with a comment on slide 3's value and two on slide 4, one after `deck change` to two-column for the notes card), `templates/decks/northwind/`, `grower-update.pptx`. `duo2 status` in each run names `field-trials`, and the run aborts otherwise.

The deck is **bound in a real split tab** (`duo2 split decks/verbs.md`, and the harness's `split:`): the slides draw, `duo2 deck` reports the slide, and the caret follows:

```
$ duo2 split decks/verbs.md
Split view: decks/verbs.md with its preview.   left: decks/verbs.md   right: Slides   ratio: 0.500   folded: false
$ duo2 deck
decks/verbs.md: slide 1 of 9 in the preview. The caret is not in a slide.
$ duo2 deck go 3
Slide 3 of 9. Source lines 28–38.
$ duo2 deck
decks/verbs.md: slide 3 of 9 in the preview. The caret is in slide 3 (lines 28–38).
```

Captures in Light, Dark and Classic, in `docs/design/duo-decks-handoff/proof/`: `p3b-<state>-<appearance>.png` for `pins` (P3-1: pins, the picked bar with Add Comment), `export` (P3-3: the Export menu, the notes-move card), `problems` (P3-3: the Problems menu, the problem card), `pptx` (make-templates), `newdeck` and `convert` (P3-4) and `splitdeck` (the bound split tab, against split view's `split-deck`); `compare-p3b-<state>-light.png` is TARGET | BUILD | DIFFERENCE against the handoff's board (the board's window cropped and scaled to the build's 2880 × 1802, as p3a did; the sheets and the pptx pane are regions scaled to the build's width). The pins and the splitdeck states were captured in a plain run of the deck in a split tab; no capture needed the unwired fallback.

### Comparison with the handoff (Light; the build's pt is 2 px)

| State vs target | Mean abs difference (per channel) | Pixels differing > 48 |
|---|---|---|
| `pins` vs P3-1 (the window) | 10.09 | 7.44% |
| `export` vs P3-3 (the window) | 10.53 | 7.73% |
| `problems` vs P3-3 (the window) | 10.75 | 8.58% |
| `splitdeck` vs split view's `split-deck` | 11.53 | 8.32% |
| `pptx` pane vs make-templates (the pane, scaled to width) | 17.79 | 11.32% |
| `newdeck` sheet vs P3-4 1 | 22.58 | 13.69% |
| `convert` sheet vs P3-4 2 | 33.03 | 18.83% |

The window comparisons differ by what the boards mock (the mock's source and terminal, 10 slides, "88%", names) and by where the pane sits: the board's pane is 369 pt wide in a 1124 pt window, the build's is 471 pt in a 1440 pt one, so every edge is a few points off; the numbers are the same as p3a's split-deck (11.5) and are exempt for the slides' own content. Read region by region, with `scripts/pixels.py` where a value is in question (build, pt):

- **Bar** (P3-3 1-3): 44 high with a 1 pt `rule` under it (rows 77 to 121, rule `#C9CDD3` = `rule`), buttons 26 high with a 1 pt `controlEdge` edge (`#8B939C`) and radius 6, as the board's `.btn`. Matches: `‹ ›`, the count, the triangle and "1 problem" semibold with its chevron, "Changed since export" in `text2`, wrapped to two lines, right-aligned before Select Shape, Export ⌄. Differs: the build's controls are 12 pt (`control`), the board's 11-12 px at a smaller window, so the build's bar is about 5% wider; at 471 pt there is room for the state text only with a short count ("3/9"), so the long count ("Slide 3 of 9") appears from about 500 pt, and under about 430 pt the state text goes first.
- **Menus** (P3-3 3): on `pane`, 1 pt `rule` edge, radius 6, popover shadow, rows 21 high, the first row on `selected`, "replaces 2026-11-01 …" in `text2` at the row's right, a rule above "Upload to Google Slides…" which is dimmed with "later". Matches the board; the build's rows are the real 12 pt, so the menu is 270 wide against the board's 262-ish. The Problems menu has no board of its own (the README describes it): each error then a rule then the notices, line numbers at the right.
- **Cards** (P3-3 4, 5): `pane` fill, 1 pt `rule` edge (measured `#C9CDD3`, 1 pt), radius 6, the message at 11 pt with the slot semibold, buttons 22 high; under the slide with the number label ("3 · kpi", "4 · two-column") after it. Matches, including the one-answer fix button when there is one. Differs: the card's message is the checker's ("is 10 characters; the template allows 7. Shorten it, or split the slide"), not the board's wording ("kpi takes 7"); the board's source line in `diffDelFill` is the editor's (see below).
- **Pins** (P3-1 1): 18 high capsules on `pane` with a 1 pt `controlEdge` edge, the stroke speech mark and the count 10/16 semibold, at the slot's top right (slide 3's value) and the slide's top right (slide 4, count 2 for a comment and its reply); hovering outlines the slot with its name tag. Matches. Differs: the value box on this template spans the slide, so the pin is kept inside the slide at the box's right edge instead of beside it (the board's box is narrower).
- **Picked bar** (P3-1 3): Add Comment first as the filled default (`text` fill, `pane` label, semibold), then Send to Claude, Send To ⌄, Pick Another, Cancel; the build wraps to two rows at this width as the board does. Matches.
- **Make Templates** (board 9A): tick boxes 28 square at the slide's corner, the picked slides ringed 2 pt in `text` with a filled `text` tick and a semibold number; the foot reads "2 slides picked" semibold then the hint, Cancel, Add to Pack ⌄, and the filled **Make Templates with Claude**. Differs: the pane is one column of slides (the board's is a 3-column grid in a wide pane, which the viewer doesn't lay out); the bar at this width shows ⋯ (under 460 would be sooner; the build's controls are wider than the board's).
- **Sheets** (P3-4): hanging from the toolbar, 460 wide, `ground`, radius 10 at the bottom; Name, Folder, Template pack ("northwind  this project · 8 templates"), the strip of 8 tiles, Start with (two radios), Cancel and the filled Create; Convert's title, description, pack, "Also: another pack, or a new pack from this deck", Into, Cancel and the filled Convert with Claude. Differs: the tiles are wireframes (see stand-ins), the Folder control is a full-width popup where the board's is a short one, and the build's rows are 5% larger than the board's.
- **Dark and Classic** follow the tokens (pane, ground, rule, `text`, `controlEdge`; the filled button swaps to `text` as a light fill on dark); the boards are Light only, so these are looked at, not diffed. In Dark the slides keep their own colours (DL-224), as the viewer always has.
- **Split tab**: bound (`duo2 split` opens it, the slides draw, `duo2 deck` reports the slide and the caret). Against `split-deck` it differs as p3a said (the mock's source, 10 slides), plus the track C chips and the Review margin now in the source; the bar adds the P3 controls.


## Stand-ins, differences and notes

- **Menus are drawn in the window**, not as `NSMenu`, so a capture sees them and they match the board's menu (pane, 1 pt `rule`, radius 6, 12 pt rows). They have no keyboard navigation yet (arrows, type-ahead); Esc and a click outside close them. If Geoff wants the native menu, `DeckDropdown` is the one place.
- **Template thumbnails in New Deck…** are wireframe tiles with a title bar mark, not renders: the pack has no thumbnails and `duo2 deck render` isn't built (Q-415 is the picker's version of the same question). The selected look follows the board (the second tile tinted).
- **Export as PowerPoint…** and **Export Again** write the same dated file by the same writer; "Export as" has no location chooser (the name is dated and the previous is removed, DL-282/286). Export writes the file on disk, not the unsaved buffer, as `duo2 deck export` does; the state text says "Changed since export" until the editor saves and the file is exported again.
- **Undo Change** runs the editor's `duo.undo()`, which undoes the last editor change; it is right when the template change was made in the editor (the slide chip) and does nothing useful when `duo2 deck change` changed the file on disk. The card's Move to ‹slot› is one plain, undoable edit.
- **Split with Claude** and **Send to Claude** (on a problem) paste into the prompt of the session showing, or of a new session, without Return.
- **The problem line in the source** (`diffDelFill` with the message under it in `diffDelText`, P3-3 4) is the source editor's: this track emits the problems through the provider as before; the editor draws them (track C / md-bar). Not drawn yet in these captures.
- **Pin click** emits `.openThread(thread:)` and **Add Comment** emits `.addComment(anchor:)`; split view's policy wires them to the margin (R11, R12). Neither was exercised live: the click needs a pointer, and the margin composer is the editor's. `⌥⌘M` is not bound (it is a menu command, `Commands.swift`).
- **Make Templates mode** ticks slides by click and shows `text` rings; Esc stops. The board's "Open With ⌄" stays on the bar at 460 and wider.
- The pptx bar under 460 shows ⋯ with Make Templates… and Convert to Duo Deck…; the md bar has no ⋯.
- Fonts on the slides are the viewer's fallback (the pack's fonts aren't embedded), as in p3a; they are exempt from the comparison.

## Requests for other sessions

- **File › New › New Deck…** is a `DuoCommand` in `Navigation/Commands.swift` (md-bar-build's file; I did not edit it): add `case newDeck` titled "New Deck…" next to `.newProject`, performing `model.showNewDeck()`, and list "New Deck…" is already on `deck new`'s `ui:` so parity holds. `AppModel.showNewDeck(name:)` is public.
- **⌥⌘M** (Add Comment on a picked shape): bind to `DeckPreviewHub.current?.addCommentForPicked()` when a deck is picking.
- **Split view's policy** should route `.openThread` and `.addComment` for the deck (they are emitted already) and show the problems' `diffDelFill` line from `problems(rev)`.
- **A + gallery between slides** (P3-2) is track C's; this track adds nothing that inserts a slide.

## Fix-up

1. **Make Templates is a grid** (board 9A). While slides are being picked, `deck.js` lays `#host` out as a CSS grid, 2 columns when the pane is under 640 pt and 3 from 640 (16 px gap, as the board), and sets the renderer's zoom so a slide is one column wide; each slide keeps its tick box and number. Resizing the pane re-fits the grid; a redraw (an edit in a split tab) keeps the grid. Leaving the mode (Cancel, Esc) puts the zoom back to 1 and scrolls to the slide that was current (checked live: slide 5 before, slide 5 after, bar "5/8"). The foot bar is unchanged. Harness: `slide-pick-off`.
   - Captures in Light, Dark and Classic at a 470 pt pane (2 columns) and an 820 pt pane (3 columns): `p3b-pptx-<light|dark|classic>-<470|820>.png`. The window is 1440 wide for 470 and 2000 for 820 (`right-width:` sets the pane).
   - Comparison with `make-templates.png` (the board's window, 819 pt wide, against an 820 pt pane 817 pt high; both scaled to the build's width; Light): `compare-p3b-pptx-grid-light.png`, **mean abs difference 13.97 per channel, 11.66% of pixels differing > 48** (the earlier one-column pane was 17.79 and 11.32%). What remains differs by content: the board shows slides 2 to 7 of 16 (scrolled, a different deck), the build shows 1 to 8 of 8; the build's slide text is the viewer's fallback fonts; the build's bar adds Make Templates and Convert to Duo Deck (dimmed while picking). Layout agrees: 3 columns, 16 px gaps, tick 28 square 10 px in from the corner, picked slides ringed 2 pt, number above each (semibold when picked), foot bar with "2 slides picked", Cancel, Add to Pack and the filled Make Templates with Claude.
   - A `--capture-window` capture of the narrower panes (about 460 to 520 pt) crops the right pane's left tab ("Project") and the foot bar's right edge: the test window's own layout (seen in the earlier `p3b-pptx-*` too); at 820 neither is cropped.
2. **File > New > New Deck...** (`Commands.swift`: `DuoCommand.newDeck`, after New Markdown File; no shortcut, DL-297; enabled with a project folder, like New Markdown File). It calls `showNewDeck()`, the sheet built in P3b. The Files + menu (`NewItemsMenu`) already had New Deck.... Parity: `deck new` lists "New Deck..." in its `ui:`; `docs/cli/duo2.md` regenerated, identical.
3. **Proof folder** 17 MB to 3.5 MB (42 files). Every `compare-*.png` kept (those wider than 3600 px resampled to 3600); the per-state captures (`p3b-*`, `chip-*`, `picker-*`) scaled to at most 1600 px wide and stored as 128-colour PNGs (flat colours exact, text edges softer than the originals; recapture with `scripts/check-ui.sh` for pixel work). Removed as superseded: `p3b-pptx-{light,dark,classic}.png` (the one-column captures, replaced by the 470/820 grid ones; `compare-p3b-pptx-light.png` is kept and shows the one-column pane), `build-{light,dark,classic}.png` (p3a's split-deck captures, replaced by `p3b-splitdeck-*`; `compare-split-deck-light.png` kept) and `target-split-deck.png` (a copy of the board in `split-view-handoff/screens/png`).
4. **Checks**: full DuoChecks 5407 passed, 0 failed; `scripts/check-records.sh`: records ok.
