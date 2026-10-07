# Duo: making projects and putting sessions in tasks — design handoff

Status: **choices decided by Geoff, 2026-10-07 (DL-147)**, by buttons in two rounds. The boards were redrawn to his answers; the build waits for his look at the redrawn boards and is a separate job. Every mark is [P] until then.

Geoff asked for a thorough study of creating projects (from scratch or from a legacy project) and assigning tasks, because "the service design is not intuitive and has no explainer content or affordances". The study is `docs/research/project-task-cx.md`: journey maps, ranked pain points, a benchmark of eight products, principles, and recommendations with effort. The canvas, https://claude.ai/artifact/WXvp7zoUwu3jkXvWPQrATR, holds 17 boards drawn with the Duo design system (`canvas/make.py` draws them, reusing the home-evolution study's helpers; `canvas/render.sh` renders them; `canvas/to-canvas.py` writes them as canvas artboards). The boards to build from are in `screens/` (`screens/manifest.json`, PNGs in `screens/png/`). Captures of today's journeys, from an isolated Duo on the fixtures, are in `journey/`.

## Targets

| Board | What | Decision |
|---|---|---|
| `03-new-a-fresh` | New project sheet: explainer, Start from (A new folder · A folder I have · From GitHub), Goal hint, In, Start a session, the **Will write** preview of `_PROJECT.md` | DL-147 (1), (2) |
| `04-new-a-existing` | A folder I have: any folder, Choose…, **Found** (`.obsidian/`, OKF `_index.md`, sessions), the promise, Name from the index's `title`, **Brief**: use `_index.md` as the brief (adds `project_brief: true`) or write a new `_PROJECT.md`; Also move it into Home | DL-147 (1), (3) |
| `07-empty-all-projects` | List with + New project in the header and a one-time explainer while no project exists | Slice [P] |
| `08-first-project` | Getting started on the Project tab: four optional steps that tick on the real action; no health step | DL-147 (4) |
| `08b-guided-task` | The guided Make a Task… sheet: the why, Task, Done when, Sessions (recent ones ticked / start a new one / none yet), Will write | DL-147 (4), (5) |
| `10-tasks-empty` | The Tasks fold's explainer (the why) with + New task; an empty `sessions` line that says what to do | DL-147 (5) |
| `11-assign-drag` | Dragging a session onto a task: the drop look, the label, the row folding under the task, the notice with Undo | DL-147 (5), Q-117 |
| `11b-new-session-in-task` | New Session in Task ▸ on the console's + menu | DL-147 (5) |
| `12-assign-menu-picker` | Move to Task ▸ and Remove from "…" on the session menu (build); the Find a Task… picker (later, Q-116) | DL-147 (5) |
| `13-notices` | One notice after every change to files or folders: what changed, what Claude is told, Undo | Slice [P] |

Not built: boards 05 (option B), 06 (option C) and 09 (sample project, ENH-33) weren't chosen.

## Behaviour a picture can't show

- **Files.** New projects write `_PROJECT.md`, new Homes `_HOME.md`, through the templates session's `Templates.make()` (design/templates, 295581b) (the agreed format: `type`, `title`, `aliases`, `status`, `goal`, empty `health` and `next`, `created`; F-188). Duo still reads `PROJECT.md` and `HOME.md`, treats either name as the project file, and never renames one. A note marked `project_brief: true` is a project's brief too; with both, the project file wins (Q-115). New folders are slugs (`q4-plan`), the name kept in `title`.
- **Adopting a folder** never moves, renames or rewrites a note, never writes `.obsidian/`, and never relinks. The only change to an existing note is the one `project_brief: true` line, after the person says yes, added surgically at the end of its properties, with Undo.
- **Detection** reads, never writes: `.obsidian/`; `_index.md` / `index.md` with `okf_version`; `loop.manifest.json` (a foreign vault: same promise, said plainly); a git repo; `CLAUDE.md`; Claude sessions for the folder.
- **Getting started** is Duo's state (Application Support), per project, for projects made or adopted after the build; each step ticks wherever it's done (the sheet, duo2, Claude); Hide ends it (Q-118).
- **Drop on a task** adds; ⌥ moves; another project's task asks first; already there says so (Q-117). The task board (DL-148) uses the same labels and notice.
- **Notices** appear at the foot of the pane acted in, stay 8 s or until used, never take the keyboard, and say the same words on duo2's stdout.

## duo2 (DL-71)

- `duo2 project new <name> [--goal] [--into] [--session]`: writes `_PROJECT.md`.
- `duo2 project make <folder|path> [--brief <note>|--no-brief]`: any folder; `--brief` marks that note `project_brief: true`.
- `duo2 task new <title> [--done-when <text>] [--session <id>]… [--start]`: the guided sheet.
- `duo2 task add <task> <session> [--move]`, **`duo2 task remove <task> <session>`**.
- `duo2 project getting-started <project> show|hide` (Q-118).
- Help › Duo Guide: `duo2 help guide` opens it.

## Not drawn (stand-ins and questions)

Q-114 (the brief key's exact name), Q-115 (which notes are offered; two briefs), Q-116 (the picker and its chord), Q-117 (drop semantics, defaulted), Q-118 (where Getting started shows). C-51: what adopting a vault leaves in it.
