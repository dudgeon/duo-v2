# Duo: editing tables in documents (ENH-11) — design handoff

Status: approved by Geoff, 2026-10-06 (DL-113), and built (F-94). Answers Q-45. The boards were drawn on the Design canvas https://claude.ai/artifact/AmLcw8SFba5CnqvymoCz2S with the Duo design system (every mark a [P]). The three approved ones are exported here as static HTML, with PNGs in `screens/png/`. Boards B (editing in the drawn table) and Insert 2 (pick a size) were not chosen and are not exported.

## What the boards settle

- `tables-menu` (board A): **Format › Table ▸** has Insert Table, Add Row Above, Add Row Below, Add Column Before, Add Column After, Delete Row, Delete Column, and Align Column ▸ (Left, Center, Right). The board shows "Insert Table…"; DL-113's t2 answer drops the ellipsis because nothing asks first. With the caret on a table its Markdown shows, as before (S3-5).
- `tables-bar` (board C): while the caret is in a table, a bar over it holds **+ Row**, **+ Column**, **Align ▾** and **Delete ▾**: 12/16 buttons, 2 8 padding, `controlEdge` border, radius 6, gap 6, 6 above the table. The ▾ menus are the system's. The bar shows **only while the caret is in the table** (Geoff, on t1).
- `tables-insert` (Insert 1): Insert Table puts in three columns, a header and two empty rows at once, `Column 1` selected.

## Behaviour a picture can't show

- Every command rewrites the table with its columns lined up (padded with spaces, at least 3 wide) as one undoable step.
- **Tab** and **⇧Tab** go to the next or previous cell, selecting its text. **Tab in the last cell adds a row.** **Return** goes to the same column in the next row, and in the last row adds one; a row is never split in two.
- **Guarding against other readers** (DL-113). What Duo writes must read the same in GitHub, Obsidian and other renderers:
  - an inserted table always has a blank line before and after it, so it never joins a list or paragraph;
  - one line per row: text pasted into a cell has its line breaks turned into `<br>` and its `|` escaped as `\|`;
  - lists can't live in a cell: a pasted list stays as its text, one line each, joined by `<br>`.
- The header row can't be deleted, since a table needs one. Delete Column on the last column removes the table.
- Every command has a `duo2 doc table` verb (DL-71). There's no ⌘ chord (DL-34).

## Exempt from the comparison

The tab strip is Swift (drawn by the pane, not the editor). The heading spacing in the boards is simplified: `slice3-handoff/editor-document` governs document spacing (S3-5). Names and data are illustrative.
