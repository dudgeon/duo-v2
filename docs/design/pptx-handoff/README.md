# Duo: the PowerPoint viewer — design handoff

Status: approved by Geoff, 2026-10-06 (DL-125); being built. The boards were drawn on the Design canvas https://claude.ai/artifact/UXSLiK37uMERJEh1mNyevE with the Duo design system (every mark a [P]), and are exported here as static HTML with PNGs in `screens/png/`. The renderer and the reasons for it are in `docs/plan/spikes/pptx-viewer.md` (DL-121).

## What the boards settle

- `pptx-viewer` (A): a `.pptx` opens in the right pane with its slides top to bottom at the pane's width, each numbered above it, on `ground`. A bar under the tabs (44 high, a `rule` below): ‹ and › (previous and next slide), **Slide n of N**, then at the right **Select Shape** and **Open With ⌄**. The current slide is the one filling most of the pane: its number reads in `text` semibold, the others `text2`.
- `pptx-one-slide` (A2): **not chosen**. One slide at a time over a strip of thumbnails.
- `pptx-picking` (B): Select Shape shows pressed (`selected` fill). The shape under the pointer gets a 1 pt dashed `text` outline 3 pt outside it and its name on a `text` tag above it. The picker bar at the bottom (on `ground`, a `rule` above): "Click a shape on a slide to select it. Esc to stop." and Cancel.
- `pptx-picked` (C): the picked shape gets a 1.5 pt solid `text` outline and its name tag. The bar: **<name>** on slide n · “<text>”, then "In <outer group> › <inner group>" in `text2` when it's in groups, then **Send to Claude** (default), Send To ⌄, Pick Another, and Cancel at the right.
- `pptx-sent` (D): Send to Claude pastes the shape into Claude's prompt without pressing Return (Claude Code shows it as `[Pasted text #1 +5 lines]`), as HTML elements are sent today. The text: `From <path>, slide n of N, the shape "<name>" (id <id>):`, then `type:` with `in groups:`, `text:`, `box: w×h at (x, y) on a W×H slide`, `the whole slide: duo2 slide shapes "<path>" <n>` and `screenshot: <path>`.
- `pptx-fallback` (E): a deck the renderer can't open (password-protected, damaged) shows Quick Look under a notice bar: "Duo can’t draw <name>: <why>." / "Quick Look shows what it can, read only. Claude can’t read its slides either." and Open With ⌄, Show in Finder.

## Behaviour a picture can't show

- The deck is drawn by `@aiden0z/pptx-renderer` (Apache-2.0, vendored in the app, nothing loaded from the network) in a web view, patched so every shape's element carries its OOXML id (`p:cNvPr`). `duo2 slide shapes` reads the same ids from the file, so a picked shape and the outline name the same thing.
- ‹ and ›, Page Up and Page Down, and `duo2 slide go <n>` move between slides. `duo2 slide` says which is on screen. When the deck changes on disk, it redraws and keeps the slide.
- The picker runs `duo2 html pick`'s flow: Esc or Cancel stops it, Pick Another starts again, Send To offers the other sessions and a new one.
- Verbs (DL-71): `duo2 slide`, `slide go <n>`, `slide shapes [n]`, `slide element`, `slide notes [n]`; Select Shape is `duo2 slide pick`; Send to Claude is `duo2 send element`.

## Exempt from the comparison

Each slide's content (the renderer draws the deck), Quick Look's preview, and the terminal in D. Names and decks are illustrative.
