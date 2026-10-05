# Model

What Duo's objects are, as decided. Design against this model, not against older briefs (`docs/design/claude-design-handoff.md`, build-handoff §2), which predate it.

## Objects

| Object | What it is | On disk | Decided |
|---|---|---|---|
| **Session** | One Claude Code conversation, in a terminal. Carries the attention state. Every session in Claude's logs is listed, with no setup. | Claude's transcript; Duo's notes in `<project>/.duo/sessions.json` | DL-82 |
| **Folder** | Where a session ran. A folder with sessions but no `PROJECT.md` shows as a folder tile, "No project file". It can become a project, or have its sessions merged into one. | Any folder | DL-63 |
| **Project** | A folder with `PROJECT.md`, wherever it is: goal, health, next step. A session belongs to the deepest project around the folder it ran in. A project inside another project's folder shows beside it. | `PROJECT.md` | DL-18, DL-82, DL-89 |
| **Home** | Optional. The folder that holds the projects the user tracks, with `HOME.md` at its top. Home's own session sorts asks and sends them to projects. Each user picks theirs (File › Choose Home Folder…). | `HOME.md` | DL-84, DL-85, DL-94 |
| **Topic** | A folder that isn't a project but holds projects. Nothing marks it. On the map it's a column. | Any folder | DL-83, DL-89 |
| **Task** | A Markdown note in a project's `tasks/` folder: a to-do first. Its frontmatter `sessions:` list links the sessions working on it. It has a status: open, in-progress, waiting, review, done, dropped. | `tasks/<slug>.md` | DL-87, DL-93 |
| **Group** | Sessions bundled by hand. Duo-only. Kept beside tasks. | `.duo/sessions.json` | DL-24, DL-88 |
| **Thread** | A session and its forks, folded into one row. | Derived | DL-24 |
| **Document** | Any file in the project, opened in the right pane: Markdown in the editor, HTML as a live page. | The file | DL-11, DL-67 |
| **Browser tab** | A web page beside the documents. Sites on the user's allow list load and stay signed in; others open in the system browser. | `allowed-sites.txt` | DL-3, DL-99 |
| **Session link** | `[title](duo2://session/<id>)` in a note; clicking it opens or resumes the session. | Text in notes | DL-87 |

## Attention

A session is in one of five states, most urgent first:
1. **needs you**: Claude asked something, needs a permission, or has a plan to approve;
2. **ready for review**: it finished and made something you haven't looked at;
3. **working**;
4. **idle**: not running, or open at its prompt;
5. **resolved**.

Its thread, group, task, project and column each show the most urgent state underneath them. Within a state, the longest wait comes first.

## The two altitudes

| | All projects | Inside a project |
|---|---|---|
| Answers | What's in flight, and what's waiting on me? | Where was I, and what is this session doing? |
| Left | Home's terminal (dark); with no Home, a prompt to choose one | The project's heading, its session list, then FILES |
| Middle | The map: columns of tiles by folder, then the idle footer | The session console (dark), its tabs above |
| Right | Needs you · Ready for review · Open tasks | Tabs: Project (`PROJECT.md`), a group, documents, browser tabs, a read-only session |
| Toolbar | `All projects`, counts, the search field | `All projects › payments › checkout`, the needs-you chip, the search field |

## The map (All projects)

Columns are folders (DL-83, DL-92):
- First, an unlabelled column of the projects sitting directly in Home.
- Then Home's topic folders (`payments /`).
- Then the folders outside Home, labelled by path (`~/repos /`).
- Columns sit side by side while each gets 220, and wrap into rows past that.

Each tile is one project or folder:
- its name;
- its goal, or its path for a folder;
- health · next step;
- its live sessions, or `Nothing running`.

Archived projects fold into a rollup under the map. The footer reads `N idle, resumable ›` and opens the idle list.

## A project's session list

Sections, in order (DL-91):
1. **Needs you**.
2. **Open · n**: sessions with a tab open in Duo, whatever Claude is doing. They read "at prompt" or "working" in place of a time.
3. **Today**, then **This week**.
4. **Earlier · n**, folded.
5. **Tasks · n**: tasks with no sessions yet, folded open.
6. **Archived · n**, folded.

Within each section, task rows and group rows mix with loose sessions by urgency (DL-93):
- A pill says `task · n` or `group · n`.
- A task row shows its status once it's past "open".
- Both fold open to their sessions, and threads fold forks.
