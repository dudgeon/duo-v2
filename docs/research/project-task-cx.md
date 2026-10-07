# Making projects and putting work in tasks: a service-design study

Study date: 2026-10-07 · Status: decided by Geoff, 2026-10-07 (DL-147); not built · Canvas: https://claude.ai/artifact/WXvp7zoUwu3jkXvWPQrATR (boards exported to `docs/design/project-task-cx/`) · Records: F-188 to F-190, Q-114 to Q-118, C-51, ENH-33, ENH-34

## The ask

Geoff, 2026-10-07: "the cx of creating projects (from scratch or from legacy project), and assigning tasks needs a thorough study with recommendations — the service design is not intuitive and has no explainer content or affordances."

His standing rule for this work: keep files plain Markdown with YAML frontmatter that Obsidian (Properties, Templates, Bases; Templater, Tasks, Dataview, Kanban) and legacy Duo's OKF format read and write without loss. Duo never adds keys or syntax that break them, and never rewrites what it doesn't own. `docs/research/obsidian-compatible-task-format.md` is the contract.

Coordinated with the **templates** session (it owns what PROJECT.md and task notes look like, through one `Templates.make(.project|.task, title:, project:, home:, values:)` call that these flows feed) and the **task kanban research** session (its board uses the same verbs and drop as these flows; its empty-board copy comes from here).

## 1. How the journeys were walked

Build `c463b79` (main), on the acceptance fixtures rebuilt in a scratch home: `HOME=/private/tmp/ptx CLAUDE_CONFIG_DIR=/private/tmp/ptx/claude scripts/acceptance/fixtures.py`. Two folders were added outside Home, with no Claude sessions: an OKF vault (`_index.md` with `okf_version: "0.1"`, `initiatives/`, `templates/`) and an Obsidian vault (`.obsidian/`, a project note with a Tasks-plugin checkbox). Duo ran isolated (`DUO_SUPPORT_DIR=/tmp/d-ptx`, `env -u DUO_SUPPORT_DIR`, duo2 with that instance's socket and token). No Claude turns were spent: Home's session sat on Claude Code's first-run screen. Captures are in `docs/design/project-task-cx/journey/`:

| Capture | What it shows |
|---|---|
| `01-launch.png` | First launch: List (DL-142), Home's pane, Open tasks. No way to make a project on screen. |
| `02-board.png` | Board: topics as columns, Outside Home rows, + New project as the last tile. |
| `03-newproject-sheet.png` | The New project sheet (S2-6): Name, Goal, In, Start a session. |
| `04-folder-noproject.png` | A folder with sessions but no project file: DL-110's notice and the Project tab's offer. |
| `05-project-checkout.png` | A project with a task holding its only session; PROJECT.md's properties as raw YAML. |
| `06-refunds-hover-task.png` | The Tasks fold, the + on a task row's hover (DL-112). |
| `07-sheet-move.png` | After Move into Home (it went through because the run auto-confirmed): side-project in Home with "0 past sessions". |
| `08-new-task.png` | + New task: `tasks/untitled-task.md` with `sessions: []`. |
| `09-makeproject.png` | Make a Project on `scratch`. |

Menus were read with the harness's `menus` action; the files Duo wrote were read from disk.

## 2. Journey maps

Board 1 draws these as a table. "Breaks" marks where a person gets stuck or can't tell what happened.

### J1 · A new project from scratch

1. Find the way in. **List** (the first view now, DL-142) has none. **Board** has + New project as the last tile, below every topic and Outside Home. File › New Project… and `duo2 project new` work. Home's chief of staff can run `duo2 project new` if asked.
2. The sheet asks for Name, Goal, In (Home or a topic) and "Start a Claude session in it". **Breaks:** nothing says what a project is, what Duo will write, or that Claude reads the goal. The hint under Goal ("It shows on the project's tile") misses the bigger point: Claude is told it.
3. Duo makes `<Home>/<Name>/PROJECT.md`. **Breaks:** the folder keeps the typed name with its spaces (`Q4 plan/`) where legacy OKF used slugs. The file holds only `goal`, `health: on-track` and `next: ""` (F-188): no `type`, `title`, `aliases`, `status` or `created`, and a health nobody chose.

### J2 · A project from a folder Duo already lists (DL-63, DL-110)

1. The folder shows under its parent heading, or as a row under Outside Home. **Breaks:** rows outside Home show no affordance; Make a Project is in the right-click menu and the Project menu only. On List, folders don't appear at all.
2. Open it: the notice "This folder isn't a project yet. A project file gives it a goal and a next step…" with Make a Project / Not Now (DL-110). This is the best explainer in the app today.
3. Make a Project writes the same thin PROJECT.md as J1 and opens it. **Breaks:** nothing confirms what was written, or mentions Undo.

### J3 · A project from an Obsidian vault or legacy Duo notes

1. A notes folder usually has no Claude history, so Duo doesn't list it.
2. There's no folder picker for projects anywhere in the app. File › Open File… opens a note, not the folder. `duo2 project make /path/to/vault` answers "no folder".
3. **Dead end.** The only route is to start a Claude session in the folder from Terminal, wait for Duo to list it, then Make a Project. Nothing detects `.obsidian/` or an OKF `_index.md`.

### J4 · Move a project into Home

1. Right-click › Move into Home…: a good sheet (S2-4) listing paths and warnings.
2. The folder moves; its sessions follow on their next resume (DL-64). **Breaks:** no notice afterwards, no visible Undo. In the walk, the moved folder's only session vanished from every list (F-189).

### J5 · Make a task

1. + New task under the session list (also in a folder that isn't a project).
2. `tasks/untitled-task.md` opens with the title selected (DL-62). **Breaks:** nothing says what a task is for or how its sessions get there. The properties show `sessions: []`, which is YAML, not an instruction.
3. The task shows in the Tasks fold, then under Open tasks at All projects.

### J6 · Put a session in a task, and move it between tasks

1. Right-click a session › Add to Task ▸ › a task. Or on a task: the + on its row (New Session in Task, DL-112), the right-click Add Session, the note's `+ Add`. Make a Task makes a new task from a session.
2. **Breaks:** no drag (you can drag a session onto a project tile, but not onto a task row), no search, no feedback. A new task gives no hint.
3. **Breaks:** a session can't be taken out of a task, except by editing the note's YAML by hand, so work can't move from one task to another. Neither the menu nor duo2 has the verb (`duo2 task` has add, not remove).

## 3. Pain points, ranked

Ranked by how many people hit it times how badly it stops them.

| # | Pain | Who hits it | Severity |
|---|---|---|---|
| 1 | No definitions in the app for project, task, Home, topic, group, thread; Help links only the duo2 reference, not the guide | Everyone new | High: people guess, and Duo's "project" means something different from the Claude app's or ChatGPT's |
| 2 | Can't start a project from a folder you already have unless Duo lists it; Obsidian vaults and OKF notes can't be adopted at all | Anyone with existing work; every legacy Duo user | High: a dead end |
| 3 | Putting a session in a task is right-click only; can't take it out or move it | Anyone using tasks | High: tasks feel fragile, and fixing a mistake means editing YAML |
| 4 | List, the first view, has no way to make a project | Everyone new | Medium-high |
| 5 | You can't see what Duo writes, and what it writes misses the agreed format (F-188) | Obsidian users; anyone who opens the file | Medium (compatibility debt grows with every project made) |
| 6 | No confirmation or Undo after changes to files and folders | Everyone | Medium |
| 7 | The brief is raw YAML: no hint of what goal, health and next are for, or health's values | Everyone | Medium |
| 8 | Group, task and thread overlap (DL-88 kept both groups and tasks) | People who find groups | Low-medium |
| 9 | + New task offered in a folder that isn't a project | Few | Low |

## 4. Benchmark: how other tools teach this

Researched 2026-10-07. [V] = checked on the product's own help pages; [U] = from memory or a third party.

| Product | What it teaches first, and how | Starting from what you have | Putting an item in a container |
|---|---|---|---|
| **Linear** | A project is "a grouping of issues that have a clear outcome or planned completion date" [V]. Teaches by doing: a checklist of real actions ("Create an issue", "Use the command menu") [U], seeded welcome issues [U], a resettable demo workspace [V]. | Importers that map each source concept to Linear's, with a user-mapping step [V]. | ⇧P adds issues to a project; C inside a project makes an issue already in it [V]. One project per issue, a hard rule [V]. |
| **Things 3** | A project is for a to-do that "will actually take more than a single step"; an area is "an ongoing ambition" [V]. A sample project, "Meet Things", re-creatable from Help [V]. | None. | Drag between lists [V]; a Move picker with type-ahead [U]. |
| **Notion** | The page; New page offers table, board, list or "simply keep it as an empty page" [V]. A hint where you type ("/" for commands) [U]. Starter templates chosen from onboarding answers [V]. | Settings › Import, and inline: `/csv`, `/zip` on any page [V]. | Drag in the sidebar; "Move to" picker [U]. |
| **Obsidian** | "A vault is a folder on your local file system." Two choices, side by side: "create a new empty vault, or use an existing folder" [V]. A Welcome note [U]. | Open folder as vault [V]; the Importer plugin [V]. TaskNotes treats adoption as a careful migration: pick how tasks are identified (`type: task`), map fields, "Convert or edit a small group first" [V]. | A project picker on the task; the link is a wikilink, so backlinks come free [V]. |
| **Claude app Projects** | "Self-contained workspaces with their own chat histories and knowledge bases" [V]. Create dialog: name and description, with a warning that Claude can't see them [V]. | Upload files to project knowledge [V]; no folders. | Chat menu › "Add to project", then a searchable "Move chat" window [V]. |
| **ChatGPT Projects** | Says what moving a chat in does: it takes on the project's instructions and files [V]. | — | Drag a chat onto a project, or "Move to project" [V]. |
| **VS Code / Cursor** | "Agents work in the context of a folder, also referred to as a workspace" [V]. Walkthroughs: a short checklist whose steps tick when you do the real thing (`onCommand`, `onContext`), with progress kept until reset [V]. | Open Folder is the main door; Workspace Trust asks once per parent folder [V] (and frightens non-developers). | — |
| **Todoist, Asana, GitHub Projects** | Todoist: an Inbox catches everything not in a project [V]. Asana: blank / template / import a spreadsheet at the same level [V]. GitHub: "Start from scratch" beside templates, and a preview of a template's fields before you commit [V]. | Asana's CSV mapping [V]; GitHub's "Import items from repository" [V]. | Todoist `#Project` in Quick Add [V]; Asana multi-homing ("only one version which appears in both places") [V]; GitHub `#` search in the add row [V]. |

**What carries over to Duo:**

1. One sentence per container that says what it gives you (Linear, Things, Claude).
2. "Use what you have" at the same level as "start fresh" (Obsidian, Asana, GitHub).
3. Adopting existing material as a careful migration that shows what it found and what it will write (TaskNotes, Linear's importers).
4. Checklists that tick on the real action (VS Code, Linear), not tours.
5. Creating inside a container fills in the container (Linear's C, Duo's own New Session in Task).
6. Two or three routes to the same relationship, ending in one searchable picker (ChatGPT, Claude, Todoist, Asana).
7. Saying what changes when an item moves in (ChatGPT): for Duo, "Claude is told".

**What to avoid:** a blank canvas with no first step (Notion, an empty vault); a template marketplace in place of guidance; features found only through settings or plugins; a one-container rule nobody mentions (Linear, Claude); warnings that frighten (VS Code's trust prompt).

## 5. Principles [P]

1. **Say it where it happens.** One plain sentence at the first point of use, with "Learn more" opening the guide page. No tours, no coach marks that cover the app.
2. **Start from what people have.** A folder you already use is as good a start as a new one, whether Duo lists it or not.
3. **Show the file before writing it**, and say what Duo will never touch.
4. **Never rewrite what isn't Duo's.** Obsidian and OKF notes, `.obsidian/` and `_index.md` stay byte-identical; Duo adds its own file beside them (`obsidian-compatible-task-format.md` §4.8).
5. **One relationship, three routes:** drag, a menu, a typed picker. All are one duo2 verb (DL-71).
6. **Say what changed, with Undo**, and what Claude will now be told.
7. **Fewer nouns first.** Lead with project and session. Task when work spans sessions. Group, topic and thread only where they appear.
8. **Teach by doing.** A checklist that ticks when you do the real thing.

## 6. Recommendations

Effort: S = a day or less, M = a few days, L = a week or more. Boards are on the canvas.

| # | Recommendation | Board | Effort | Records |
|---|---|---|---|---|
| R1 | **The words, once each, where they appear**, with Learn more; Help › Duo Guide above duo2 Reference; the guide pages open with the same sentences. | 2 | S | — |
| R2 | **Write the agreed format** (F-188): PROJECT.md with `type`, `title`, `aliases`, `status`, `goal`, empty `health` and `next`, `created`; a task omits `sessions` until it has one, then block lists; folder names as slugs with the name in `title`. Through the templates session's `Templates.make()`. | 3 | S | F-188 |
| R3 | **New project, option A**: one sheet, "Start from: A new folder / A folder I have", the explainer, a Goal hint that says Claude reads it, and a "Will write" preview. Options B (a chooser first) and C (a separate File › Make a Project from Folder…) were drawn too. | 3–6 | M | Q-114 |
| R4 | **Adopt any folder.** "A folder I have" takes any folder, listed or not; Duo says what it found (`.obsidian/`, an OKF `_index.md` with `okf_version`, a git repo, `CLAUDE.md`, sessions) and promises what it won't touch. A new PROJECT.md takes its name from the index's `title`, and its body opens with `Brief: [<title>](_index.md)` when linked. An existing PROJECT.md is adopted as is. `duo2 project make <path>` takes any folder; File › Make a Project from Folder… opens the same sheet. | 4 | M | Q-115, C-51 |
| R5 | **+ New project on List** (the header, both views) and a one-time explainer over List while no project exists. | 7 | S | — |
| R6 | **Getting started**: a per-project card on the Project tab that ticks on real actions (goal written, a session started, health and next written, optionally a task), hidden when done or dismissed; Duo's state, never in PROJECT.md. Property hints for empty `health` (its three values) and `next`. | 8 | M | Q-118 |
| R7 | **Tasks' empty states**: a Tasks fold with the explainer and + New task while a project has none (the kanban board uses the same line); a task's empty sessions line reads "None yet. Drag a session here, or + Add / + New session". No + New task in a folder that isn't a project. | 10 | S | — |
| R8 | **Drag a session onto a task** (row, note, board card, Open tasks), with the file tree's drop look and a label saying what will happen; ⌥ moves instead of adding. | 11 | M | Q-117 |
| R9 | **Move to Task ▸, Remove from "…"** on the session menu; `duo2 task remove <task> <session>`, `duo2 task add … --move`. Then **Find a Task…**, a typed picker in search's style. | 12 | S (menu, verbs), M (picker) | Q-116 |
| R10 | **Notices with Undo** after every change to files or folders: what Duo wrote or moved, what Claude is told, Undo. | 13 | M | — |
| R11 | **Fix Move into Home losing a folder's sessions** under a symlinked path (F-189). | — | S–M | F-189 |
| Later | A "Meet Duo" sample project (ENH-33). Showing the tasks an adopted vault already has, without moving them (ENH-34). Option B's chooser if people miss the segment. | 9 | M each | ENH-33, ENH-34 |

### The recommended v1 slice

R1, R2, R3 (option A) with R4, R5, R6, R7, R8, R9's menu and verbs, R10, R11. The picker can follow. Board 14 draws it.

### Obsidian and OKF compatibility, decision by decision

- New PROJECT.md and task files follow §4.1 to §4.6 of the format doc: block lists, quoted links, no nested maps, no Dataview inline fields, no Tasks emoji, nothing in `.obsidian/`.
- Adopting a vault adds one file, `PROJECT.md`, beside the user's notes. It never edits `_index.md`, never adds keys to existing notes, never writes `.obsidian/`, never moves or relinks notes (legacy's silent ENH-266 rewrite is exactly what's ruled out).
- **Trade-off (C-51):** in a vault, `PROJECT.md` is a new note Obsidian shows (in the file list, graph and Bases with no type filter), and every project's note has the same basename (accepted in DL-18; `title` and `aliases` keep the switcher readable). A `tasks/` folder appears only when the first task is made.
- Templates live in `templates/` and keep `type: task` so they work as Obsidian Templates-plugin templates. Duo reads tasks only from `tasks/` and projects only from `PROJECT.md` / `HOME.md`, never `templates/` (the templates session adds a check). A hand-written base should exclude `templates/` (`!file.inFolder("templates")`), as legacy OKF learned (format doc §3, lesson 3).
- Detection reads markers and never writes them: `.obsidian/`, `_index.md`/`index.md` with `okf_version`, `loop.manifest.json` (a foreign brainkit vault: show it, promise even more plainly to change nothing).

## 7. Geoff's answers (DL-147)

Asked by buttons, two rounds, 2026-10-07; the canvas was redrawn to them (boards 3, 4, 8, 8b, 10, 11b, 14).

1. **Starting a project: A**, one sheet. Its segment gains **From GitHub**, drawn by the GitHub study (duo-v2-fe), which owns everything under it; this study owns the frame.
2. **The project file is `_PROJECT.md`** (Geoff: "project-md should have a _ prefix"), sorting first as OKF's `_index.md` does; Home's is `_HOME.md`. Existing `PROJECT.md` / `HOME.md` are read and never renamed.
3. **A folder's existing note:** Duo **asks** whether it should be the brief; yes marks it **`project_brief: true`**, an alternative to the project file. (Recommended was a link from a new brief; Geoff chose to let the note be the brief.) This is the one key Duo adds to a note it didn't write, with the person's yes, surgically; Q-114 and Q-115 hold the details.
4. **Teaching: Getting started, every step optional**, with **a guided flow for making a task** (board 8b). **Health will rarely be used**: not a step, not a sheet field.
5. **Assigning: drag a session onto a task**, and explain why sessions and tasks connect, briefly: most sessions are for a task or goal; Duo can keep them together so you can come back by what the work is for; a task has many sessions; a session doesn't need one. More affordances where needed: New Session in Task ▸ on the + menu (board 11b); Move to Task ▸ and Remove from "…" (board 12), which also fix the missing way out of a task.

Open: Q-114 to Q-118. Risk: C-51. Later: the picker (Q-116), ENH-33, ENH-34.

## 8. Recommendations after the answers

R3 is option A with From GitHub; R4 asks about the brief note and writes `project_brief: true` on yes; R2 writes `_PROJECT.md`; R6 drops health and adds the guided task sheet; R8 adds New Session in Task ▸; R9 keeps the menus and verbs, and the picker waits. Board 14 is the v1 slice.
