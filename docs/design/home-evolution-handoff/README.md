# Duo: Home's evolution — design handoff

Status: approved by Geoff, 2026-10-07 (DL-142), by buttons one at a time (his canvas comments failed). Not built: the build is a separate job.

Geoff asked for one list of every active and recent session, with its project and task, like the Claude app's left bar; for Needs you to stay; and for Home to open in chat. The study drew four placements (A to D), three groupings, three ways for Needs you to sit with the list, filtering, what a click does, and Home in chat, on the Design canvas https://claude.ai/artifact/UmuuYZdzroUbBDmY2UYRBY with the Duo design system. All 18 boards are in `canvas/` (`make.py` draws them, `render.sh` renders them, `to-canvas.py` writes them as canvas artboards). The approved ones are exported to `screens/` (listed in `screens/manifest.json`, PNGs in `screens/png/`).

## Targets: `list-1440`, `list-1280`, `board-1440`

All projects, B: Home on the left (340, in chat), the middle switches **Board | List**, the Needs you column on the right (340). Compare with `WINDOW=1280x800` for `list-1280`.

- **The toggle** sits first in the map's header: a segmented control (`Board` with a two-column mark, `List` with three lines), 22 high, `controlEdge` border, the chosen half on `selected` and semibold. Then the filter field (`Filter sessions` with List, `Filter folders` with Board), then `Group` / `Sort` and its popup at the right.
- **First launch shows List**; after that Duo remembers the last choice.
- **The list** fills the middle under the header. Sections as a project's list (DL-91), across projects: `OPEN · n`, `TODAY`, `THIS WEEK`, then the `Earlier · n` and `Archived · n` folds.
- **A row** (`rows`, compact, 26 high): state glyph, title (one line, truncates first), project (150; `★ home` for Home), task box and task name (150, empty when there's none), the wait or `working` / `at prompt` (64, right-aligned, never truncated). **No `activeTint`** in this list (Geoff); tiles and a project's list keep it.
- **Needs you, N1** (`needs-you`, top left): needs-you sessions are left out of the sections. The list starts with one 28-high line, 1 `needsYou` border, radius 6: the filled glyph, `3 need you` semibold in `needsYou`, `in the column` in `text2`, a chevron in `needsYou`. It selects the column's first card. With the right pane hidden (⌥⌘0) the line opens into the rows themselves.

## Boards

- `rows`: the compact row (build this) and the two-line row (Q-101: the stand-in under 520).
- `grouping`: by recency (build this); by state and by project are ENH-29.
- `filter`: A (build this). B, chips, is ENH-29. **The filter is Duo's search** (F-36, F-170): hybrid, by meaning and by words, over each session's title and what was said in it (search's session index) and its project, folder and task names. While it has text the sections give way to `MATCHES · n`, best first, each row followed by the passage that matched (12/18 `text2`, who and when first in `controlEdge`, matched words semibold). Esc clears. A needs-you session can match. Nothing found: "Nothing in your sessions is about “…”." and a link, "Search files and notes too ⇧⌘A", opening search with the same words.
- `needs-you`: N1 (build this); N2 and N3 weren't chosen.
- `home-chat`: **Choice 2, board 10** (build this): while Home's selected tab shows chat, Home's header (36, on `ground`, `★ home` semibold and the path in mono `text2`) and its tab strip are DL-136's thin light strip, with the light Terminal/Chat pill at the right. A terminal tab keeps the dark header and strip. Choice 1, Q-57 as built (F-145), wasn't chosen.
- `slice`: the decision summary and the v1 slice.

## Behaviour a picture can't show

- **A click on a row jumps** into the session's project with that session selected, as a tile's session row does. Return does the same. Right-click is the session menu (DL-108). Open in place waits for ENH-28.
- **Home opens in chat**: new Home sessions, the one Duo starts on launch included (DL-54), open in chat. Each keeps its own mode once switched. Other sessions still open in the mode used last (DL-119 (5)). The fallback rules don't change (DL-119 (6), Q-56). The chat slash-commands session's notes apply (F-173, C-46): attach Home's chat so its launch id is set, re-key it on `/clear`, `/branch` and `/resume`, and give Home's pane the same fall-back bar.
- **Order inside a section** is a project's list's (DL-93): most urgent first, then the longest wait.
- **Counts** don't change: the toolbar, the Dock badge and `duo2 needs-you` count each session once.

## duo2 (DL-71)

- `duo2 view home board|list|toggle` — the middle at All projects (Board, List).
- `duo2 view filter [text]` — the map's or the list's filter, whichever shows.
- `duo2 session chat --home chat|terminal|last` — the mode new Home sessions open in (Settings › General: "Home opens in").
- Shortcuts for Show Board / Show List: Q-100 (none until decided).

## Not drawn (stand-ins and questions)

- Q-100: chords for Show Board / Show List.
- Q-101: the list under 520 (two-line rows, as drawn on `rows`).
- Home across windows: the multi-window study's Q-98.
- The Group popup's menu (Group By Recent, then under a rule Show Archived): system menu.

## Exempt from the comparison

- Names, times and data are illustrative.
- Everything inside the Home pane's chat below its strip is chat mode's (chat-mode-handoff, chat-polish-handoff).
- The map on `board-1440` is the built map (narrow-handoff, many-projects-handoff).
- The boards' labels, captions and notes are the board's, not the app's.
