# Split view: design study

Status: **proposed, waiting on Geoff** (Q-362 to Q-368; Geoff's answers become DL-275 to DL-278). Every mark on the canvas is [P]. Research and design only; nothing is built.

Geoff, 2026-10-31 (the full request is in `tasks/split-view.md`): study legacy Duo's Split View and every decision behind it, so v2 can build split view cleanly. It comes first because split view is the way to show a deck's Markdown source beside its rendered slides (Duo Decks).

## For Geoff

- **The canvas**: https://claude.ai/artifact/8j6ukv88cvTqvdSEoHnEc1 (sources in `canvas/project/`), with the Duo design system. Its 11 boards:
  1. the job, today's right pane, and why halving it fails;
  2. option A, a paired view;
  3. option B, two tab groups;
  4. option C, a split tab, with a deck (recommended);
  5. C with two documents, and how a split is made;
  6. option D, a companion pane;
  7. C in Dark and Classic;
  8. making room, animated (Geoff's rule);
  9. focus, commands and duo2 verbs;
  10. the Duo Decks interface;
  11. the pre-mortem and cost.

## Read in this order

| File | What it holds |
|---|---|
| `legacy.md` | Legacy's Split View: timeline, how it worked, decisions and their reasons, Geoff's words, what broke and why, what v2 keeps, drops and fixes |
| `legacy/commits.md`, `legacy/documents.md`, `legacy/code.md` | The detail: every commit by phase; what legacy's documents say; how the final code behaved, with file:line references |
| `v2-today.md` | v2's panes, tabs, focus, documents, persistence, duo2, multi-window and Duo Decks' plans, and 24 constraints a split must respect |
| `options.md` | The options, the recommendation, the routing table, the verbs, the interface with Duo Decks, the pre-mortem and the decisions |

## Records

F-474 to F-479 (findings), Q-362 to Q-368 (questions), C-135 to C-137, ENH-301 to ENH-303. DL-275 to DL-278 are reserved for Geoff's answers.
