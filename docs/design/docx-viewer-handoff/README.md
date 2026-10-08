# Duo: the Word viewer — design handoff

Status: approved by Geoff, 2026-10-08 (DL-162). A .docx opens in a read-only viewer that shows its comments and tracked changes; Convert to Markdown (DL-123) is offered from the viewer's bar. Geoff, 2026-10-08: "offer to convert (may be lossy) or offer to render as view only, using a similar approach to the pptx approach; view only should preserve and render comments, track changes, etc".

The boards were drawn on the Design canvas https://claude.ai/artifact/F8PWth7cidMZvWjgh28ye4 with the Duo design system; Geoff chose by buttons (straight to the viewer, A at the pane's width, W4 to W6 as drawn). They're exported here as static HTML (`screens/`, listed in `screens/manifest.json`), with PNGs in `screens/png/`. Each board is the right pane, 460×800, like the deck viewer's (`pptx-handoff`). **Build `viewer`, `markup`, `picked` and `fallback`; `ask` (W1) and `pages` (W3) were not chosen.** The renderer and why: `docs/plan/spikes/docx-viewer.md` (`Spikes/DocxViewer/`).

## The viewer (W2, `viewer`)

- **A .docx opens straight into the viewer.** Nothing asks. The document is never written: the viewer reads its bytes, and nothing in this path opens it for writing.
- **The bar** (44 high under the tabs, a `rule` below, as the deck's): **Markup ⌄** at the left; **Select Text**, **Convert to Markdown…** and **Open With ⌄** at the right. Buttons as the deck's (12/16, padding 4 10, 1 `controlEdge`, radius 6, `pane`).
- **The document** sits on `ground`, 16 below the bar and 20 in from each side, on a `pane` sheet with a 1 `rule` edge and 28 24 padding. The renderer draws its text in the document's own fonts and styles (exempt from the comparison) **at the pane's width, never paginated** (`breakPages: false`): page layout, headers and footers' page numbers don't apply here.
- **Tracked changes**, in each person's colour (`reviewAuthor1…5`, assigned in the order people first appear, then repeating):
  - an insertion underlined (offset 3);
  - a deletion struck through;
  - a move struck at its source and double-underlined where it went;
  - a formatting change as the new formatting with a 2 dotted underline in the colour.
  - Under the pointer, a change shows a label above it, on `pane` with `shadowPopover`, radius 10, padding 4 10, 12/16: the name semibold in its colour, then `inserted · 7 Sep` (deleted, moved, formatted: Bold).
- **Comments**: the commented range on `commentHighlight`; the comment as a card under its paragraph (the last paragraph of its range): `pane`, 1 `rule`, radius 6, padding 8 10, 12/16 in the UI face; the name semibold in its colour, `· 1 Sep` in `text2`, then the text; replies under it, 12 in, the same way. **A resolved comment folds** to one line, `text2`, a chevron, `Resolved · <name>: <text>` (cut to one line); a click opens it.

## The Markup menu (W4, `markup`)

Markup ⌄ shows pressed (`selected`) while its menu is open, a menu Duo draws (`pane`, radius 10, `shadowPopover`):
- **All Markup** (default), **Simple Markup**, **No Markup**, **Original**: one checked.
  - All: everything as above.
  - Simple: the text with changes accepted, and a 2-wide bar in the margin at the left of each changed paragraph, in `text2`.
  - No Markup: changes accepted, no marks.
  - Original: the text before the changes (insertions out, deletions and moves back). The renderer keeps formatting changes applied here (F-234); Duo puts back bold, italic, underline and colour.
- **Show Comments** (on) and **Show Resolved Comments** (off): toggles.
- **PEOPLE**: each person with a 9 dot in their colour and their count of changes and comments. A click shows only that person's marks (a check by them); another click shows everyone again.
- The choice is kept per document while Duo runs.

## Select Text (W5, `picked`)

As Select Shape on slides (DL-125 B, C, D):
- Select Text shows pressed. A paragraph or a comment card under the pointer gets a 1 dashed `text` outline 3 outside it and a tag above it on `text`, 11/16 white: `Paragraph · 1 comment`, `Paragraph · 3 changes`, `Comment`.
- A click picks it: a 1.5 solid outline. The picker bar at the bottom (on `ground`, a `rule` above, padding 10 20 12): **A paragraph** under “<heading>” · “<text>” (one line), then its changes and comments in `text2`, 12/16; then **Send to Claude** (default), Send To ⌄, Pick Another, and Cancel at the right. Esc or Cancel stops.
- **Send to Claude** pastes into Claude's prompt without Return:
  ```
  From <path>, paragraph <w14:paraId> under “<heading>”:
  text: <the paragraph as it reads with All Markup's changes accepted>
  tracked changes: <name> inserted “…” <date>; <name> deleted “…” <date>
  comments: <name> <date>: “…” (reply <name>: “…”)
  the whole document: duo2 doc outline "<path>"
  ```
  A picked comment sends its thread and the paragraph it's on.

## Convert, and when it won't draw (W6, `fallback`)

- **Convert to Markdown…** asks first, as a Duo question (`SheetCenter`): “Convert <name> to Markdown?” / “Duo makes an editable copy, <name>.md, beside it. The Word document isn’t changed.” / in `text2`: what won't come over, with the document's own counts (its tracked changes accepted, its comments become notes at the end, page layout, columns and text boxes left out; only the parts it has). Cancel, **Convert**. A document with no comments, changes, columns or text boxes skips the question. Then DL-123's flow as built (the name-taken question, the progress bar, the result with Undo Conversion), except **the copy opens in a tab of its own beside the viewer** instead of taking its tab.
- **A document Duo can't draw** (a password, damage, the old .doc format, the renderer failing) opens in Quick Look under a notice bar as the deck's (DL-125 E): “Duo can’t draw <name>: <why>.” / “Quick Look shows what it can, read only. Claude can’t read it either.” (the last sentence only when Claude can't), Open With ⌄, Show in Finder.

## Behaviour a picture can't show

- **Renderer**: `@file-viewer/docx` 0.3.33 with JSZip, pinned and vendored under `Vendor/` (Apache-2.0 notice in the about box), nothing from the network. Options as the spike: `breakPages: false`, `exposeDisplayTargets: true` (each paragraph carries `data-office-target=…#p:<paraId>`), review mode from the Markup menu. Duo's review layer (`Spikes/DocxViewer/duo-review.js` as the start) draws the colours, cards and labels; the renderer's own review display is off.
- **Never a layout loop**: the web view's size doesn't follow its content (no size-change anchoring), and a viewer not on screen is dormant (F-225, F-226). A long document draws once.
- **On disk**: when the .docx changes on disk the viewer redraws and keeps its place.
- **Verbs (DL-71)**: `duo2 doc markup [all|simple|none|original]`, `duo2 doc comments [--resolved]`, `duo2 doc outline <path>` (paragraphs with ids, headings, changes and comments, read from the file by `Docx.swift`), `duo2 doc pick` (Select Text) and `duo2 send element` (Send to Claude), `duo2 file convert` (as DL-123, with `--yes` for the question).

## Exempt from the comparison

The document's own text, fonts and colours (the renderer draws them), Quick Look's preview, and the terminal in W5. Names and documents are illustrative.
