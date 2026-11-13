# Duo: organising All projects' Board — design study

Status: **study, waiting on Geoff** (Q-539 to Q-547). Nothing is built.

Geoff, 2026-11-13, from a photo of his own Board (not reproduced; sample data here): space goes unused (a tall stack under Home, white space to the right); many users don't use a Home folder as their main way of organising; the one New session control is in a random place and doesn't say which project it starts in. He asked for directions that rely less on Home, a subtle but visible New session button on every project tile, and a broad look at other ways to organise the view.

- **Study page:** https://claude.ai/artifact/KssyGmv9iLu75RAtsAnkHV (every board as an image, the decisions).
- **Design canvas:** https://claude.ai/artifact/7zdNWzWyfrCPDgGtBot5M4, minted by the director. A background session can't publish to an artifact made from an Artifact type (F-685), so the boards' sources in `canvas/project/` still need loading there from a session with the Design canvas tools. The Duo design system goes in as `project/ds/duo/tokens.json`, copied from https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH; the `designSystems` record is already in `canvas.json`.
- **Why it looks like that:** F-684 (board 01), captures in `today/`.

## Directions

- **B, recommended: by activity** (boards B1, B2). Pinned, Now (needs you, working, open or to review), Today as tiles; This week as rows; Earlier and Archived folded. The folder becomes a line on each tile. A folder with no project file is shown with the others, marked, with Make a Project. There's no Outside Home part. Group ⌄ offers Activity, Folder (A) and None. Four across at 1440, six at 1900.
- **A: folder bands** (board A). The smallest fix: each folder is a band of tiles across the width, Home is a band like any folder, and short folders share a row.
- **C: flat, pins and a folder filter** (board C).
- **D: a projects table** (board D), the broad rethink; recommended as a later extra view (ENH-351).
- **Every direction (board T):** + New session as a quiet last row on every tile, a tooltip with the project and folder, and ⌘T on the focused tile; `duo2 session new --project` (exists).
- **Fit (board X):** with the Projects pane study (Q-527 to Q-531, the pane's order follows Q-539) and Getting started (Q-532 to Q-536, the card above the Board; step 2's Show me points at a tile's row; Home's explainer anchors on ★ home's tile). Considered, not drawn: a timeline, tags or people (ENH-352), tasks first.

## New marks, all [P]

The tile's New session row (rest, hover, focused with ⌘T, beside Make a Project) and T2's + in the name row; section labels Pinned, Now, Today, This week; project rows (name, folder, status, when, +); folder bands with a ★ home band; folder chips; the projects table; Group ⌄ Activity / Folder / None.

## Decisions (console-ready)

Each with the study page https://claude.ai/artifact/KssyGmv9iLu75RAtsAnkHV and the board to look at.

1. **Q-539 · How should the Board organise projects?** Boards B1, A, C, D. **B, by activity (recommended)** · A folder bands · C flat with a folder filter · D a projects table.
2. **Q-540 · Group ⌄ on the Board?** Board B1. **Activity, Folder, None (recommended)** · only the chosen direction.
3. **Q-541 · Pinned projects?** Boards B1, C. **Yes, a Pinned row first; ★ home pinned when there is a Home (recommended)** · no pins.
4. **Q-542 · The tile's New session control?** Board T. **A quiet last row, + New session (recommended)** · a + in the name row · only on hover.
5. **Q-543 · ⌘T on the Board?** Board T. **The focused tile's project, else as today (recommended)** · always as today.
6. **Q-544 · Folders with no project file, Outside Home, Archived?** Boards B1, T. **In the same sections, marked, with Make a Project; no Outside Home part (recommended)** · keep today's Outside Home part.
7. **Q-545 · How many across?** Boards A, B2. **As many as fit at 220 (recommended)** · three at most.

8. **Q-546 · List grouped by project: where is each project's New session?** Boards L1, L2. **At the right end of the project's header (recommended)** · a last row in each project.
9. **Q-547 · Its order.** Board L1. **Projects by newest activity, sessions newest first, five then "n more", quiet projects folded, the dashed row kept (recommended)** · projects by name · nothing folded.

The List grouped by project (boards L1, L2) is Geoff's second ask, 2026-11-13: "in the all projects >> list view, add an option to group by project and when list is grouped by projects, there should be a new session button per project". It's independent of Q-539: it can be built whichever direction the Board takes.

After the answers: load and finish the chosen boards on the canvas, export them to `docs/design/all-projects-board-handoff/screens/`, and write the build brief. Changes DL-83, DL-104 and DL-111 if B or C is chosen.

## Files

`make_boards.py` (with `boards.py` and `style.css`) writes `canvas/project/` from one set of sample data; `page/` is the study page as published (boards rendered at 2x with headless Chrome); `today/` holds the captures of main.
