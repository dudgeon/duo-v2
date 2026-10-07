# Duo: a project's task board — design study

Status: **study, not approved** (Q-119, Q-120, Q-121; DL-148 reserved for the decision). Every mark on these boards is a proposal [P]. Nothing here is a build target until Geoff approves. The approved boards then move to a `task-board-handoff/` with `screens/`.

Geoff, 2026-10-07: "projects would benefit from a visual way of tracking tasks besides the left column — do some research into the obsidian kanban feature". He also asked for maximum compatibility with Obsidian and OKF. The research, the options and the rules are in `docs/research/task-board.md`. The boards are drawn on the Design canvas https://claude.ai/artifact/1yVhqtQsaXow8GGRQsUaYN with the Duo design system.

## Files

- `canvas/make.py` draws the 12 boards as static HTML into `canvas/boards/`. `canvas/render.sh` renders them to `canvas/boards/png/<name>@2x.png`. `canvas/to-canvas.py <root>` writes them as canvas artboards.
- The shared CSS and glyphs are copied from `home-evolution-handoff/canvas/make.py`. Colours are tokens by value.

## Boards

| Board | What it shows |
|---|---|
| `00-study` | The ask, what stays as decided, what Obsidian does (verified 2026-10-07) |
| `01-data` | Where the board's data lives: (a) computed from task notes, (b) a Kanban-plugin note, (c) a Bases `.base`, (d) TaskNotes. Recommended: a + c |
| `02-where-a` | A: a Board tab in the right pane |
| `03-where-b`, `03b-where-b-note` | B: Sessions \| Tasks; the board over the middle and right |
| `04-where-c` | C, recommended: the board over the left and middle, the note beside it |
| `05-where-1280` | B and C at 1280×800 |
| `06-cards` | A card and its variants |
| `07-drag` | Drag between lanes, onto Done, and a session onto a card; what's written; card order |
| `08-empty-narrow` | No tasks, an empty lane, widths |
| `09-obsidian` | The files: a task note, the `tasks.base` Duo would write, a Kanban-plugin note for contrast |
| `10-recommendation` | The recommendation and a first slice |

## Owned elsewhere

- **The explainer copy for "No tasks yet"** belongs to the project & task CX study.
- **Dragging a session onto a task** is that study's flow too. The board only accepts the same drop (`duo2 task add`).
- **The task template** belongs to the templates session. The board adds no keys to it.
