Proof for slice 2a (pictures), DL-161. `*-compare.png` are scripts/check-chat.sh's whole-board comparisons (target | build | difference); the board shows several snippets, so the numbers below compare cropped snippets (`board-*` / `build-*`), mean absolute difference per channel, 0 to 255:
picture composer 4.7; adding tile 7.9; sent bubble 3.0; six-picture composer 3.3; six-picture bubble 0.24; replay bubble 0.62; failure line 1 (field and line) 14.1; failure line 2 11.2. What remains is the composer text sitting 3.5 pt right of the boards (the composer's existing inset, as on the chat-mode `composer` board), the caret (a capture has none), the stand-in art, and 1 px field edges.

Slice 2b (long text), DL-161: `paste-text`, `paste-text-open`, `paste-huge` (the folded block with its words after, the opened block, the 12,480-line block). Snippet numbers, mean absolute difference per channel (0 to 255): folded 10.9, opened 13.5, huge 14.1. They are higher than the picture snippets because these are mostly text, antialiased differently and sitting 3.5 pt right of the boards (the composer's existing inset); the field and block edges, heights (103.5 and 243.5 pt) and the header, preview and × rows line up with the boards. `f231-*`: the overflow before (20 lines drew under the hint row) and after (a 20-line paste folds; a 12-line one scrolls inside the field, the caret followed).

## Live (Geoff OK, 2026-10-08)

- `live-2.1.294-picture.png`: a real ⌘V of a PNG in chat, sent; Claude Code 2.1.294 on the mock API (F-233).
- `live-2.1.219-picture-and-40-lines.png`: paste mode on 2.1.219: a picture, then 40 pasted lines, then a question. Taken before the fix that keeps a folded paste on its own line.
