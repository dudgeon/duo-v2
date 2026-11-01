# Duo: Duo Decks' viewer (P3) — design handoff

Status: **approved by Geoff, 2026-11-01** (DL-302 to DL-305), by button after the design round on the canvas https://claude.ai/artifact/Sk28K1tkHgwk6gHs7RFGqQ, boards 10–13. Make Templates is board 9A, chosen as DL-291. Every mark was [P] and is now the target. The screens are exported here (`screens/*.html`, rendered by `render.sh` to `screens/png/`). The deck in a split tab itself is split view's `split-deck` (`docs/design/split-view-handoff/`), which these build on.

## Where things are

| Screen | What it settles | Decisions |
|---|---|---|
| split view's `split-deck` | The split tab, the deck's 44 bar on the preview side (‹ › n/N, Select Shape, Export ⌄), the caret's 2 pt `controlEdge` anchor mark, the 250 ms redraw | DL-269, DL-275 |
| `P3-1-comments` | Comment pins; a pin opens its thread in the source margin; Add Comment from Select Shape | DL-302 (Q-395, Q-396), DL-284 |
| `P3-2-picker` | The slide chip; ⌃⌘N's template list; the + between slides and its gallery | DL-303, DL-295, DL-296 |
| `P3-3-problems` | Problems ⌄ and export state in the deck bar; the Export ⌄ menu; problem and notes-move cards under a slide | DL-304, DL-282, DL-286, DL-298, DL-281 |
| `P3-4-sheets` | The New Deck… and Convert to Duo Deck… sheets; the pptx viewer's bar gaining Make Templates… and Convert to Duo Deck… | DL-305, DL-297, DL-294 |
| `make-templates` (board 9A) | Make Templates…: slide tick boxes and the picked bar | DL-291 |

## What the boards say, as rules

**Comments (P3-1):**
- **The pin.**
  - A pin sits at the top right of a commented slot's box, or of the slide for a slide comment.
  - It is an 18-high capsule on `pane`, with a 1 pt `controlEdge` edge, a stroke speech mark and the count in `text` 10/16 semibold.
  - Hovering it outlines the slot as Select Shape does.
  - A closed comment leaves no pin.
- **Opening a thread.** Click a pin to open the thread in the source's review margin, active and scrolled to (R11). Folded to the slides, it opens as DL-237's narrow popover. The slides keep the keyboard.
- **Adding a comment.**
  - In Select Shape's picked bar, **Add Comment** comes first, then Send to Claude, Send To ⌄, Pick Another, Cancel.
  - It opens the margin composer on the slot's lines without taking the keyboard (R12). Duo writes the signed comment on its own line at the slot's end.
  - A slide's blank area picks the whole slide, whose anchor range is the title line (or the marker line).
  - ⌥⌘M does the same on a picked shape.

**Picker (P3-2):**
- **The slide chip.** Marker lines are drawn as a 22-high chip with a 1 pt `rule` above: "**Slide n** · template ⌄" in 11/20, with the number in `text` semibold and the rest in `text2`. The comment text is hidden, and the file is unchanged. Clicking the chip changes the slide's template, with DL-285's carry-over and the leftovers going to the notes.
- **⌃⌘N.**
  - It inserts a new chip under the caret's slide, with the list open.
  - Each row has a thumbnail, the name in mono and the purpose in `text2`. Typing filters.
  - ↩ inserts the skeleton with the caret in the title. Esc removes the empty chip.
  - It looks like the editor's autocomplete.
- **+ between slides.** Hovering a gap shows an 18 round + on `pane`. Clicking it opens "Insert a slide after n", a 4-column gallery of the pack's thumbnails, and the source scrolls to the inserted skeleton.

**Bar and cards (P3-3):**
- **Problems ⌄.** It appears only when there are errors: a triangle in `text` and "n problem(s)" semibold. Its menu lists each problem, and choosing one reveals both sides. Notices are counted in the menu only.
- **Export state.** It sits before Select Shape in `text2`: "Changed since export", "Exported 5 m ago", or nothing.
- **Export ⌄.** The menu holds:
  - Export as PowerPoint… (a dated name, removing the previous one);
  - Export Again (naming the file it replaces);
  - Show Export in Finder;
  - Upload to Google Slides…, dimmed and marked "later" (ENH-307).
  After an export, the DL-132 notice shows.
- **Problem card.**
  - It sits under the slide, on `pane` with a 1 pt `rule` and radius 6, and gives the message with the slot semibold.
  - One-answer fixes are buttons (DL-298). Otherwise the buttons are Go to Line and Send to Claude.
  - The source line takes `diffDelFill`, with the message under it in `diffDelText` 11/16.
- **Notes-move card (DL-281).** It says "n points moved to the notes when this became t", with Move to ‹slot› per bullets slot, Split with Claude and Undo Change. It goes when the notes line is gone.

**Sheets (P3-4):**
- **New Deck…** opens from File › New and Files' + menu.
  - Fields: Name, Folder, Template pack (project, then Home, then built in, each with its count), plus a strip of 8 thumbnails, and Start with (a title slide, or one of each).
  - Cancel / **Create**. Create opens the deck in its split tab.
- **Convert to Duo Deck…** opens from the pptx viewer's bar and Files' right-click.
  - Fields: Template pack (or another, or a new pack from this deck) and Into.
  - **Convert with Claude** pastes the request and the `duo2 deck import` line into Claude's prompt without Return. The plan, its questions and the report happen in the session.
- **The pptx viewer's bar** reads ‹ › n of N · Select Shape · Make Templates… · Convert to Duo Deck… · Open With ⌄. Under 460, Make Templates and Convert fold into a ⋯ menu.

## Verbs (DL-71)

- `duo2 deck` / `deck go` / `deck pick` (built in P3a).
- To add:
  - `deck comments` and `deck comment <slide>[/<slot>] "text"`;
  - `deck problems`;
  - `deck export` (exists, local);
  - `deck template pick` / `picked` (registered in P2);
  - `deck new` and `deck import` (exist; the sheets call them);
  - `deck insert` / `deck change` (exist; the chip, picker and + call them).
- The picker's typing, the chip's look and the pin's hover are UI-only (`Parity.uiOnly`, with the reason).

## Exempt from the comparison

The slides' own content (the renderer draws the deck), the terminal's text, and the sample names.
