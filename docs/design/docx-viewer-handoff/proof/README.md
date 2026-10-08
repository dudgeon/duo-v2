# Word viewer: proof (slice 1: viewer, markup, fallback; slice 2: picked)

Live captures of an isolated build on a scratch workspace (own `DUO_SUPPORT_DIR`, scratch `CLAUDE_CONFIG_DIR`, `open -g`, no Claude turn), the right pane cropped to the board's 460×800 (`scripts/chat-crop.py … 980 40 460 800`) and compared with `docs/design/build-handoff/tools/compare.sh docx-viewer-handoff/<board>`. The test documents are `../fixture/` (`python3 ../fixture/make_garden.py`). The document's own text and fonts, and Quick Look's preview, are exempt.

| File | Board | What it shows |
|---|---|---|
| `viewer-compare.png` | `viewer` | TARGET, BUILD, DIFFERENCE: the board's Garden plan (`fixture/board`), with the label over "(a third author)" (`docx-hover:`) |
| `markup-compare.png` | `markup` | the Markup menu open on `fixture/full` (its counts are the board's: Avery 5, Blake 9, Casey 2) |
| `fallback-quicklook-compare.png` | `fallback`, second half | `fixture/locked` (an OLE file, as Office saves a password): the notice and Quick Look |
| `fallback-question-window.png` | `fallback`, first half | the whole window with Convert to Markdown…'s question up (`docx-ask-convert`) |

`regions.py` measures a region against the board: the mean absolute difference per channel (0 to 255) at the shift in points that fits best, as the capture has no 1 pt outer border and text anti-aliasing differs. Numbers from these captures:

| Region | At 0 | Best (shift) | Note |
|---|---|---|---|
| bar rule | 29.82 | 0.14 (+1, -1) | the rule is 1 pt up: the deck's bar is 44 high in all, the board's 44 plus a 1 border |
| sheet top-left corner | 0.00 | 0.00 | |
| sheet right edge | 6.17 | 0.00 (+2) | the sheet's right edge is 2 pt off the board's (the pane's width) |
| comment card | 24.28 | 7.11 (0, +5) | the card is 5 pt lower: the document's own line heights above it |
| resolved line | 8.92 | 6.15 (0, +7) | likewise |
| hover label | 18.56 | 4.46 (0, +6) | likewise; text anti-aliasing |
| Markup button | 12.20 | 12.20 | the label's text only |
| menu (whole) | 9.77 | 9.77 | placed to the pixel; ✓ glyph and text anti-aliasing |
| menu, the four modes | 3.66 | 3.66 | |
| menu, people | 18.84 | 18.84 | dots and counts: text anti-aliasing and 1 pt of row height |

Stood in or different from the boards: the question is Duo's standard sheet over the window (459 wide), not drawn at the board's 418 inside the pane; the Markup button's pressed fill; the reviewAuthor4 and reviewAuthor5 colours are not on a board.

## Slice 2: Select Text (`picked`)

`scripts/check-docx.sh picked-hover picked` captures one state at a time (the board draws a hovered paragraph and a picked one together):

| File | What it shows |
|---|---|
| `picked-hover-compare.png` | Select Text on, the pointer over the first paragraph: dashed outline 3 out, tag `Paragraph · 1 comment` |
| `picked-compare.png` | Casey's paragraph picked: solid 1.5 outline, tag `Paragraph · 3 changes`, the picker bar (top-aligned crop: the bar is below the crop) |
| `picked-bottom-compare.png` | the same, the crop aligned to the bottom of the pane so the picker bar shows |

The board's own document has no comment card, so its paragraphs sit higher than the fixture's; `regions.py` is run with `SHIFT=160`, which finds the same element wherever the document put it. The tag is placed as the board's HTML places it (3 left of the paragraph, its 16 high box 8 clear above it).

| Region | At 0 | Best (shift) | Note |
|---|---|---|---|
| hover tag | 148.59 | 6.17 (0, +40) pt | the paragraph is 40 pt lower in the fixture |
| picked tag | 166.63 | 8.04 (0, +132) pt | 132 pt lower: the fixture's card and the extra lines |
| hover outline | 47.18 | 20.77 (0, +40) pt | the text inside is the document's own |
| picked outline | 33.24 | 23.90 (0, +132) pt | likewise |
| Select Text, pressed | 19.82 | 10.79 (+1, 0) pt | label anti-aliasing and the chevron buttons beside it |
| Open With | 29.31 | 13.30 (+1, 0) pt | |
| picker bar: rule, text, buttons | 23 to 54 | 21 to 43 | not matched: see below |

The picker bar is **not** a match to the pixel, and the numbers say so. The scratch workspace has no Claude session showing, so the bar carries the deck's "No session is showing: use Send To." line and Send To in the default look (DL-132 q68-no-session); the board has a session, so its buttons sit 20 pt higher and Send to Claude is the default. The wording, order, spacing (8 between lines, padding 10 20 12), weights and buttons are the board's. The terminal box at the bottom of the board is the terminal: the paste text is compared by content, in DuoChecks (`Send to Claude's text for a paragraph is the README's`). The board's paste says `(page 1)` after the heading; the README's text and the coordinator's do not, so the build follows them.

The bar's right edge: the board's four buttons run to 10 pt from the pane's edge (not the 20 the bar's padding says), because they need it; Duo's are a few points wider, so `docxBarTrailing` is 6.
