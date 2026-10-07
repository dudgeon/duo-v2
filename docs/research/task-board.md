# A task board for a project

Research date: 2026-10-07 · Status: **decided** (DL-148, DL-150; Q-119 to Q-121, Q-127, Q-128 closed); not built · Canvas: https://claude.ai/artifact/1yVhqtQsaXow8GGRQsUaYN · Boards: `docs/design/task-board-study/`

**The ask.** Geoff, 2026-10-07: "projects would benefit from a visual way of tracking tasks besides the left column — do some research into the obsidian kanban feature". His standing rule for this work: "For everything we build, I want to maximize backwards compatibility with existing obsidian handling and/or OKF."

**Markers.** **[V]**: verified this session against a primary source (plugin source, official help, changelog, maintainer's file). **[U]**: inferred, or the source doesn't say. The base reference for files is `docs/research/obsidian-compatible-task-format.md` (the format doc). This study adds nothing to the task format.

---

## 0. The answer in one screen

**Decided by Geoff, 2026-10-07 (DL-148, DL-150), in two rounds of buttons:**
- placement **C**, with a card's note shown in the right pane;
- **computed** card order;
- the Obsidian base with **pinned lanes**;
- **session rows** on cards (S1, board 11);
- columns as status values, listed in **`PROJECT.md` `lanes:`** (board 12);
- a task's documents, folders and links as a frontmatter **`references:`** list (board 13).

The rest of this section is the study's recommendation as it went to him.

- **Data: compute the board from the task notes, and on request write a Bases board for Obsidian (options a + c).**
  - A lane is a task's `status`. A drag in Duo writes the `status:` line only, plus `completed:` when the task closes, exactly as Set Status does today.
  - "Add Obsidian Board" (DL-20's action) writes a `tasks.base` with a `kanban` view grouped by `status`. Obsidian then shows the same board with no plugin, and a drag in either app moves the card in the other.
  - **No new keys, no new files by default, no second copy of any fact.**
- **Why now.** Obsidian's core Bases got a Kanban layout that went public in **1.14.4 on 2026-10-05** [V]. It is the same model as Duo's: one note per task, columns from one property. The Kanban *plugin* is the wrong model: one note holds the whole board, it rewrites the note on every change, and it can't read one-note-per-task. It is also unmaintained.
- **Where: C, recommended [P].** A **Sessions | Tasks** switch in a project's toolbar. Tasks shows the board over the left and middle panes, and the right pane keeps the selected card's note, so the board and the note sit side by side at 1440 and at 1280. The close second is B (the board in the middle and right panes, with the session list kept). Not recommended: A (a tab in the 460-wide right pane fits only two lanes).
- **Order inside a lane: computed, not stored [P].** Needs you first, then due date, then oldest. Bases stores no manual card order either [V]. A manual order would mean a rank key written into every task note.
- **Lanes:** Open, In progress, Waiting, Review, Done. Dropped is a fold under Done. A status Duo doesn't know gets a lane of its own at the end and is never rewritten.

---

## 1. What Obsidian has

### 1.1 The Kanban plugin (mgmeyers → community archive)

**Where it lives [V].** `github.com/mgmeyers/obsidian-kanban` now redirects to `community-archive/obsidian-kanban`. `community-plugins.json` lists it as `obsidian-community/obsidian-kanban` by "Obsidian Community Archive".

**State [V].**
- Last release: 2.0.51, 2024-05-31. Last commit: 2026-03-06.
- 553 open issues. 2,724,415 downloads (`community-plugin-stats.json`).
- `MAINTAINERS.md` (2026-01-12), from the author: "I no longer have the bandwidth to maintain the Kanban plugin… looking for new maintainers."

**File format** [V, from `src/parsers/common.ts`, `formats/list.ts`, `parseMarkdown.ts` and `Settings.ts`]:
- **Board marker.** Frontmatter `kanban-plugin: board`. Other values are `basic` (read as `board`), `table` and `list`. Any truthy value makes the note a board.
- **Lanes.** Each `## Heading` followed by a list is a lane.
  - `## Doing (3)` sets a WIP limit of 3.
  - A `**Complete**` paragraph right under the heading marks a completion lane: cards moved into it get ticked.
- **Cards.** List items `- [ ] text`. Custom checkbox characters are kept.
  - Extra lines are indented 4 spaces (or a tab).
  - ` ^id` at the end of the first line is a block ID. "Copy link to card" creates one.
- **Archive.** `***` immediately followed by `## Archive` and its list.
- **Settings footer.** A JSON object in a bare fenced block, wrapped as follows (the footer's `%%` lines and fence shown indented):

      %% kanban:settings
      ```
      {"kanban-plugin":"board", …}
      ```
      %%

  The keys include `date-trigger` (`@`), `time-trigger` (`@@`), `new-card-insertion-method`, `new-note-folder`, `new-note-template`, `metadata-keys`, `archive-with-date`, `append-archive-date`, `lane-width`, `show-checkboxes`, `tag-colors`, `date-colors`, `hide-card-count`, `inline-metadata-position` and `max-archive-size`, among others.
- **Dates, tags and links.** `@{2026-10-10}`, `@[[2026-10-10]]` (a daily-note link), `@@{10:30}`, `#tag`, `[[wikilinks]]` and markdown links.
  - A card's first link is its linked note.
  - `metadata-keys` shows that note's frontmatter on the card.
  - "New note from card" creates a note (folder and template from settings) and turns the card into a link to it.
- **It rewrites the whole file [V].** `boardToMd()` rebuilds the note on every change: the frontmatter (via `stringifyYaml`), then each lane, the archive and the footer.
  - Prose between lanes is lost on the next save.
  - YAML comments and formatting are lost.
  - Unknown frontmatter keys survive.
- **One note per task: not supported [V].** The parser reads `##` lanes and list items in one file. Linked notes only add metadata to cards.
  - Open requests: #467 "auto populate from notes" and #405 "update frontmatter of linked note on complete".
  - #1207 (2026-05) points users at a Bases kanban plugin instead.

### 1.2 Bases Kanban (core)

**Release [V].**
- 1.14.0 early access (2026-09-02) added the layout.
- 1.14.2 lets cards move between `file.folder` columns.
- 1.14.3 added the Group menu, and embedded boards stopped having a fixed height.
- 1.14.4 added "Hide column" and was the **public release on 2026-10-05**, desktop and mobile.
- Source: obsidian.md/changelog.

The format doc (2026-10-03) and its default for Q1 ("the early-access Kanban is a bonus, not a promise") predate the public release. That premise has changed (F-191).

**Behaviour** [V, from the help pages for the Kanban view, Views and Bases syntax]:
- **The view.** `type: kanban` in a `.base` file or a ` ```base ` block. `groupBy: {property, direction}` is required. Notes with no value go to a **None** column.
- **Columns.** `groupOrder` fixes the order **and the visibility** of columns: only the listed groups show, and `null` means "no value". Other ways to change them:
  - the Group menu's Manual order;
  - dragging a column header;
  - unchecking groups;
  - "Add group" (an empty column);
  - "Hide empty columns".
- **Drag** "update[s] the grouped property in that note". Only Markdown notes move. Grouping by a formula, or by a `file.*` property other than `file.folder`, disables moving.
- **New notes.** A column's **+** creates a note with that column's value.
- **Cards** show the properties listed in `order`; the first one is the title. An optional cover image comes from an image property.
- **Card order** follows the view's `sort`. **No manual card order is stored** (none is documented, and nothing writes a position) [V/U].
- **[U]** What a drag writes to a list-typed or link-typed group property. It doesn't matter here: `status` is a scalar.

### 1.3 Other plugins

| Plugin | Unit | Board? | Drag writes | Manual card order | State |
|---|---|---|---|---|---|
| **TaskNotes** | one note per task | its own Bases view, `tasknotesKanban` [V] | the group property, and the swimlane property too [V] | frontmatter `tasknotes_manual_order`, a LexoRank string, written into each note; a reorder can rewrite hidden notes in the same scope [V] | active: 4.13.8 on 2026-10-02, about 2M downloads |
| **Obsidian Tasks** | a checklist line | `view columns by …` since 8.4.0 [V] | priority and dates only, not status [V] | none [V] | active, 4.36M |
| **Dataview** | frontmatter and inline fields | no kanban; DataviewJS by hand [V/U] | n/a | n/a | stagnant: 0.5.70 on 2025-04-07 |
| **Projects** (marcusolsson) | a folder of notes | had a board view [U] | `status` [U] | n/a | archived, and out of the plugin list [V] |
| **Kanban Bases View** (xiwcx) | notes, via Bases | yes [V] | the property via `processFrontMatter`; replaces lists [V] | `cardOrders` (file paths) in the `.base` view config [V] | 39k |
| **Bases Board** (flowing-abyss) | notes, via Bases | columns × rows [V] | the property [U] | columns in the view config; cards [U] | 10k, 1.2.1 on 2026-10-06 |
| **kanban-status-updater** | Kanban-plugin cards | — | writes the linked note's `status` when a card moves [V] | the plugin's | 6k |

**Where manual card order lives.**
- Kanban plugin: position in the board note.
- Bases (core): nowhere; the view's sort decides.
- TaskNotes: a key in every task note.
- Kanban Bases View: the `.base` file.
- Tasks: nowhere.

**So.**
- Duo's flat task notes (DL-6) already fit **Bases Kanban** and **TaskNotes**: grouped by `status`, nothing to add.
- They do not fit the Kanban plugin.

---

## 2. Options for Duo (board `01-data`)

Compatibility is the first criterion. Each option is judged on: what round-trips, what Obsidian shows, what breaks when someone edits in either app, card order, and effort.

### (a) A board computed from `tasks/*.md` (recommended)

- **On disk.** Nothing new. Lane = `status`.
- **A drag in Duo** is `duo2 task status`. It changes one line, plus `completed:` on done or dropped, through the editor's buffer when the note is open (DL-13). ⌘Z undoes it.
- **Round-trips.** Everything, because the board stores nothing.
  - Any edit of `status` (Obsidian Properties, a Bases drag, TaskNotes, git, Claude) is a file change. Duo's watcher moves the card.
- **What Obsidian shows.** Each task as a note, with `status` in Properties.
- **Breaks:** nothing.
  - A status Duo doesn't know gets its own lane, in `text2`, and is never rewritten.
  - A note with no `status` shows under Open, and nothing is written.
- **Order.** Computed: needs you, then due, then created.
- **Effort.** Medium: a view, drag and drop, a filter. The write already exists (`TaskNotes.settingStatus`).

### (b) Read and write a real Kanban-plugin note (not recommended)

- **On disk.** A board note (`tasks/board.md`, `kanban-plugin: board`): a `##` per status and a card per task that links its note.
- **Round-trips: badly.** The lane lives in two places, the board note and each task's `status`.
  - A drag in the plugin moves the card line and leaves `status` stale. Plugins like kanban-status-updater exist to patch exactly this.
  - Duo would need two-way reconciliation, with conflicts when both change.
  - The plugin rewrites the whole note on each change (§1.1), so Duo can't edit it surgically (format doc §4.1 rule 5). Any prose a user adds between lanes is lost.
- **What Obsidian shows.** A board, if the plugin is installed; otherwise a list of links.
- **Order.** The order of lines in the note, the only manual order anywhere. Duo would have to keep it.
- **Effort.** High: a parser and serialiser that match the plugin's output, and sync.
- **Also against it.** The plugin is unmaintained (§1.1), it can't do one-note-per-task (DL-6), and OKF never had this file type.
- **What we keep.** A Kanban note a user already has opens in Duo as a note, and its links work. ENH-36 could import one once.

### (c) Generate an Obsidian Bases `.base` file (recommended, on request)

- **On disk.** `tasks.base` beside `PROJECT.md`, written only by the explicit "Add Obsidian Board" action (DL-20). Its views:
  - **Board**: `type: kanban`, grouped by `status`, `groupOrder` set to Duo's five lanes, sorted by `due` then `created`;
  - **By status**: the format doc's table.

  See board `09-obsidian` and §4.
- **Round-trips.** `status` only, the same key as (a). A Bases drag writes it and Duo follows. Duo never edits the base after writing it: columns, sort and card properties are the user's.
- **What Obsidian shows.** Duo's board, in core Obsidian 1.14.4+, with no plugin. Older Obsidian versions can't show a `kanban` view [U, probably an error or blank view]. The table view still works there.
- **Breaks.**
  - `groupOrder` hides groups it doesn't list (§1.2). So a status typed in Obsidian that isn't one of Duo's five is hidden **in Obsidian's board**, while Duo shows it as an extra lane. That's C-52, and Q-121 asks whether to write `groupOrder` at all.
  - Without `groupOrder`, columns sort by value ASC: done, in-progress, open, review, waiting. That is the wrong reading order.
- **Order.** The view's sort: due, then created. There's no "needs you" in Obsidian, since that's live session state.
- **Effort.** Small: extend DL-20's action with one view.

### (d) Anything better?

- **TaskNotes' board needs nothing from Duo.** Set TaskNotes to identify tasks by `type` = `task` and add the statuses `waiting`, `review` and `dropped`, and its Kanban shows Duo's tasks.
  - One trade-off: if its user drags *within* a column, TaskNotes writes `tasknotes_manual_order` into the note. Duo preserves that key (format doc §4.8 rule 3) and ignores it.
- **A ` ```base ` block embedded in `PROJECT.md`** instead of a separate file. Rejected for now: it puts an Obsidian-only block in the brief Duo shows. Duo's editor would draw it as a code block. DL-20 already chose a separate file.
- **Recommendation: (a) + (c).** One truth (`status`), Duo's board always, and Obsidian's board wherever the user asks for it.

---

## 3. Design (canvas boards, every mark [P])

The boards are drawn with the Duo design system. Source: `docs/design/task-board-study/canvas/make.py`. PNGs: `canvas/boards/png/`.

| Board | What it settles |
|---|---|
| `00-study` | The ask, what stays as decided, what Obsidian does |
| `01-data` | Options a–d, compared |
| `02-where-a` | A: a Board tab in the right pane (460: two lanes, sideways scroll) |
| `03-where-b`, `03b-where-b-note` | B: **Sessions \| Tasks** in the toolbar; the board over the middle and right (1140); a card's note brings the right pane back and the board scrolls |
| `04-where-c` | **C (recommended)**: the board over the left and middle (980); the right pane keeps the selected card's note |
| `05-where-1280` | B and C at 1280×800. In C with the note open, Done folds into a 34-wide strip |
| `06-cards` | A card's anatomy and its variants |
| `07-drag` | A drag between lanes; what is written; onto Done; a session onto a card; keys |
| `08-empty-narrow` | No tasks; an empty lane; widths in steps |
| `09-obsidian` | A task note, the `tasks.base` Duo writes, and a Kanban-plugin note for contrast |
| `10-recommendation` | a + c, C, computed order, and a first slice (marked approved) |
| `11-sessions` | Sessions on a card: S1 rows (chosen), S2 chips, S3 a count with a list |
| `12-columns` | + Add Column, the lane menu, removing a column that holds tasks, `PROJECT.md` `lanes:` |
| `13-documents` | A task's `references:`: rows in the note's properties, file and folder completion, the card's count |

**A card** (`06-cards`) is read entirely from the note and its sessions' live state. Nothing is stored for the card.
- **Line 1:** the task box and the title, semibold.
- **Line 2** (12/16, `text2`): `waiting on …`, the owner when it isn't you, the due date, `done …`, and "n sessions" when there are several.
- **Line 3:** the most urgent linked session, with its name and wait. A session that needs you is drawn in `needsYou`, semibold.
- **Overdue** is `text` semibold, not `needsYou`: that colour stays for sessions waiting on you.
- **Hover:** the + is New Session in Task (DL-112). Right-click is the task menu (DL-115). Selected: a `text` border.

**Drag** (`07-drag`):
- **The motion.** The card lifts (the popover shadow token) and leaves a dashed ghost. The target lane takes `selected` with a dashed edge, and a dashed slot shows the card's *computed* place in that lane.
- **Onto Done** plays Mark Complete's 5-second hold (DL-130). Dropped is a fold under Done.
- **A session dropped on a card** is `duo2 task add`, the same drop as on a task row (the project & task CX study owns that flow).
- **Keys.** ⌥⌘← and ⌥⌘→ move a card one lane [P]. VoiceOver gets a "Move to ▸" action.

**Empty and narrow** (`08-empty-narrow`):
- **No tasks.** The board shows a title, the CX study's explainer copy (not drawn here), **+ New task** and **Make a Task from a session…**.
- **Lanes always show,** so each one is a drop target.
- **Widths, in steps:**
  - 900 and up: five lanes;
  - under 900: Done folds into a strip;
  - under 640: lanes keep 200 and scroll sideways.

  The Tasks fold grouped by status is a later narrow form (ENH-35).

**duo2 (DL-71).**
- New: `duo2 task board [show|hide|toggle]` switches Sessions | Tasks.
- Already there: `duo2 task status` and `duo2 task add` for drops.
- "Add Obsidian Board": its verb is whatever DL-20's action gets. Q-121 is where that's settled.

**Not designed yet.**
- The board across all projects (ENH-35).
- Choosing card properties (ENH-36).
- The exact keyboard model beyond the two moves.
- Shortcuts for the switch (they would join Q-100).

---

## 4. Rules for whoever builds it

These come from the format doc's §4.8, applied to a board:

1. A board action writes **only** `status`, plus `completed` when a task closes or reopens, as `settingStatus` already does. It writes no order, rank, lane or position key. Drops of sessions write only the `sessions:` list (DL-93).
2. Duo writes a `.base` only through "Add Obsidian Board" (DL-20), and never edits it afterwards. It never writes `.obsidian/`.
3. Duo never writes a Kanban-plugin note. If it finds one, it treats it as a note.
4. Duo reads `status` leniently: it trims the value and compares case-insensitively for lane matching, but never normalises the file. It shows unknown values as extra lanes. A missing `status` counts as Open, with nothing written.
5. `archived: true` tasks (DL-115) and files that aren't tasks (`.base`, `.canvas`) in `tasks/` never become cards.
6. TaskNotes and Bases keys found in a note (`tasknotes_manual_order`, `priority`, `scheduled`, `projects`) are preserved and ignored.

The `tasks.base` (board `09-obsidian`) extends the format doc's §4.7 example. The folder filter is unchanged:

```yaml
filters:
  and:
    - type == "task"
    - 'file.folder == if(this.file.folder == "/", "tasks", this.file.folder + "/tasks")'
views:
  - type: kanban
    name: Board
    groupBy:
      property: status
      direction: ASC
    groupOrder: [open, in-progress, waiting, review, done]   # written as a block list; see Q-121
    order: [title, owner, waiting_on, due]
    sort:
      - property: due
        direction: ASC
      - property: created
        direction: ASC
  - type: table
    name: By status
    groupBy:
      property: status
      direction: ASC
    order: [title, owner, waiting_on, due]
```

Before this ships, check in a real Obsidian 1.14.4 (about 10 minutes, extending the format doc's §4.7 test):
- a drag changes only the `status` line;
- the `sort` key spelling and shape;
- `this.file.folder` at the vault root;
- what a note with an unlisted status does under `groupOrder`.

---

## 5. Records

- **F-191**: Bases Kanban is public (1.14.4, 2026-10-05). The format doc's Q1 default ("Kanban is a bonus") predates it.
- **F-192**: The Kanban plugin's format and behaviour: whole-file rewrites, no one-note-per-task, unmaintained.
- **F-193**: Where each tool keeps card order: Bases nowhere, TaskNotes a key per note.
- **Q-119**: Where the board lives: A, B or C.
- **Q-120**: Order inside a lane: computed, or manual with a key.
- **Q-121**: The `tasks.base` board view and its `groupOrder`.
- **C-52**: An unlisted status is hidden in Obsidian's board while Duo shows it.
- **ENH-35**: A board across projects, and the Tasks fold grouped by status.
- **ENH-36**: Choosing card properties, and importing a Kanban-plugin note once.
- **DL-148**: The board: (a) + (c), C, computed order, the pinned base, session rows.
- **DL-150**: Columns as `PROJECT.md` `lanes:`; a task's `references:`.
- **Q-127**, **Q-128**: Where columns live; how references are kept. Both closed.

## Sources

- **Kanban plugin.** github.com/community-archive/obsidian-kanban, main at 5134c05: `src/parsers/common.ts`, `src/parsers/formats/list.ts`, `src/parsers/parseMarkdown.ts`, `src/parsers/helpers/parser.ts`, `src/Settings.ts`, `MAINTAINERS.md`, and issues #467, #405, #1182 and #1207. Downloads: obsidianmd/obsidian-releases `community-plugin-stats.json`.
- **Obsidian.** obsidian.md/changelog.xml (1.14.0 to 1.14.4, including the 2026-10-05 public release); obsidian.md/help/bases/views/kanban; obsidianmd/obsidian-help `en/Bases/Layouts/Kanban view.md`, `Views.md` and `Bases syntax.md`.
- **TaskNotes.** github.com/callumalpass/tasknotes `docs/views/kanban-view.md` and `src/types.ts`.
- **Obsidian Tasks.** github.com/obsidian-tasks-group/obsidian-tasks `docs/Queries/Views.md`.
- **Others.** github.com/xiwcx/obsidian-bases-kanban; the community plugin directory for Bases Board, kanban-status-updater and the rest.
- **This repo.** `docs/research/obsidian-compatible-task-format.md`; `docs/design/decisions.md` (DL-6, DL-13, DL-20, DL-60, DL-93, DL-112, DL-115, DL-129, DL-142); `docs/design/task-menu-handoff/`; `docs/guide/tasks.md`; `Sources/DuoKit/Live/TaskNotes.swift`.
