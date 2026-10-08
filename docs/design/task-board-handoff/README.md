# Duo: a project's task board — design handoff

Status: approved by Geoff, 2026-10-07 (DL-148, DL-150), by buttons in two rounds. Being built on `feature/task-board` (DL-158).

The research and the reasoning are in `docs/research/task-board.md`. The study, with every option drawn, is `docs/design/task-board-study/`, and the canvas is https://claude.ai/artifact/1yVhqtQsaXow8GGRQsUaYN. The screens here are copies of the study's boards (HTML, and `png/` at 2x). They are presentation boards: the window drawn inside each is the target. Where a board draws options, build only the one named below.

## Targets

| Screen | Build | Not chosen on the board |
|---|---|---|
| `04-where-c` | **C**: a **Sessions \| Tasks** switch in a project's toolbar; Tasks puts the board over the left and middle panes (980 at 1440); the right pane keeps the selected card's note. The header row: `TASKS · n`, Filter tasks, Anyone ▾, + New task. Done shows the last 7 days, then **Earlier · n** and **Dropped · n** folds. **Cards take board 11's session rows, not this board's line 3.** | — |
| `05-where-1280` | C at 1280×800 with the note open: Done folds into a 34-wide strip | B |
| `06-cards` | A card's anatomy: box and title (13/18 semibold, 3 lines), line 2 (`waiting on …`, owner when not you, due, `done …`), overdue in `text` semibold, done ticked in `text2`, hover +, selected `text` border. **Line 3 is replaced by board 11's rows.** | — |
| `07-drag` | A drag between lanes writes `status` (and `completed` onto Done) through the editor's buffer when the note is open; ⌘Z undoes it. Lift, ghost, target lane `selected` with a dashed edge, the dashed slot at the card's computed place. ⌥⌘← / ⌥⌘→ move the selected card a lane. A session onto a card is `duo2 task add` (the CX study's flow; see below). | Dragging within a lane does nothing |
| `08-empty-narrow` | No tasks: title, the explainer, + New task, "or drag a session here". An empty lane: a dashed box "Drop a task here to mark it <lane>". Widths: 900+ all lanes; under 900 Done folds into the strip; under 640 lanes keep 200 and scroll sideways. | — |
| `09-obsidian` | The `tasks.base` that **Add Obsidian Board** writes (`groupOrder` from the project's lanes, research doc §4). | The Kanban-plugin note (contrast only) |
| `11-sessions` | **S1**: under a hairline, a Sessions label with the session mark, then one filled row per linked session (glyph, title, wait; up to 3, then "+n more"); hover `selected` and the open arrow; a click opens that session (the board switches to Sessions with it in front). | S2 chips, S3 count |
| `12-columns` | + Add Column (name field; the slug is the status), each lane's ⋯ menu (Move Left, Move Right, Add Column After…, Remove Column…), Remove asks where its tasks go (a Duo question), `lanes:` in the project's brief written only once the default five change. Unlisted statuses show as extra lanes with **Keep as Column**. Open and Done can't be removed. "Obsidian board is out of date · Update". | `.duo/`, view state only |
| `13-documents` | A task's `references:` frontmatter list: rows in the note's properties (file, folder or globe mark; text; path or domain in mono `text2`), the field under them completing the project's files and folders, pasted URLs; the card's page mark and count on line 2. | A `## Documents` body section |

## Behaviour a picture can't show

- **Nothing stored for the board.** A board action writes only `status` (plus `completed`), a column change only the brief's `lanes:` list, a reference only the task's `references:` list. No order, rank, lane or position key (research doc §4).
- **Lenient reading.** `status` is trimmed and matched case-insensitively, never normalised in the file; missing counts as Open; unknown values become extra lanes at the end. `archived: true` notes and non-`.md` files never become cards.
- **Order inside a lane:** a session needing you first, then due (soonest), then oldest `created`.
- **The brief** is whichever note DL-147 names: `_PROJECT.md`, `PROJECT.md`, or a note marked `project_brief: true`.
- **Off screen is dormant** (ENH-45): the board reads nothing while Sessions is showing; nothing above a pane observes per-session state (ENH-46's scan).

## Owned elsewhere

The empty board's copy and the session-onto-card drop's label and Undo notice belong to the project & task CX study (DL-147, `project-task-cx/`). Until those flows are built, the board uses board 8's copy and the existing `duo2 task add` drop, with Q-141 and Q-142 open.
