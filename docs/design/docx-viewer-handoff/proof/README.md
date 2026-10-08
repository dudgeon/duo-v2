# Word viewer, slice 1: proof (viewer, markup, fallback)

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

Stood in or different from the boards: Select Text is not in the bar (slice 2); the question is Duo's standard sheet over the window (459 wide), not drawn at the board's 418 inside the pane; the Markup button's pressed fill; the reviewAuthor4 and reviewAuthor5 colours are not on a board.
