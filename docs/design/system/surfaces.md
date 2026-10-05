# Surfaces

Every screen and state in Duo, with its status. Target screens are HTML exported from the design canvas, in the repo under `docs/design/<handoff>/screens/`. Rendered PNGs sit beside them in `png/`, and current captures of the built app are in this system's **Screens** assets.

Statuses:
- **Designed**: built to its target.
- **Changed by decision**: the target, amended by a later decision.
- **Stand-in**: built from a decision; its look waits on design.
- **Designed, not built.**
- **Not built.**

The open design items are DB-n (`docs/design/design-brief-2026-10-04.md`) and S2-n (`docs/design/design-brief-slice-2.md`, the current brief).

## All projects

| Surface | Status | Targets | Open | Code |
|---|---|---|---|---|
| Window, toolbar, counts | Designed; search field reads `Search all projects ⇧⌘A` (DL-80) | build `overview.html` | — | `Shell/DuoToolbar.swift` |
| Home pane: terminal and session tabs | Designed | build `overview.html`, surfaces `home-none.html` | — | `AllProjects/AllProjectsPanes.swift` HomePane |
| Home pane with no Home folder | Stand-in (DL-84) | — | DB-37, S2-3 | HomePane, `ConsoleMessage(.noHome)` |
| The map: columns, tiles | Changed by decision: folder columns with a folder mark and slash, unlabelled first column, wrapping (DL-83, DL-89, DL-92) | build `overview.html` | DB-38, S2-2 | MapColumn, ProjectTile |
| Folder tiles ("No project file") | Stand-in (DL-63) | — | DB-12 | ProjectTile |
| New project tile | Designed; the flow behind it isn't (DB-9) | build `overview.html` | DB-9, S2-6 | NewProjectTile |
| Sessions open in Duo, tinted | Stand-in (ENH-7) | — | DB-33 | TileSessionRow, `activeTint` |
| Archived rollup under the map | Stand-in (ENH-6) | — | DB-34 | `AllProjects/ArchivedProjects.swift` |
| Idle footer and idle list | Designed (DB-1) | surfaces `idle-list.html`, `idle-many.html` | — | `AllProjects/IdleList.swift` |
| Action column: needs you, ready for review | Designed (no reply buttons, DL-29) | build `overview.html`, `flow-zoom-*.html` | DB-7 | ActionColumnPane, NeedsYouCard, ReviewCard |
| Action column: Open tasks | Stand-in (DL-93) | — | S2-5 | ActionColumnPane, TaskLine |
| Peek (needs you elsewhere) | Designed | build `flow-zoom-*.html` | — | `Navigation/PeekView.swift` |

## Inside a project

| Surface | Status | Targets | Open | Code |
|---|---|---|---|---|
| Breadcrumb `All projects › folder › project` | Changed by decision (DL-92) | build `project.html` | — | ProjectBreadcrumb |
| Session list: Needs you, Open, Today, This week, Earlier, Tasks, Archived | Changed by decision (DL-91); new sections are stand-ins | build `project.html` (by state, superseded) | S2-1, DB-33 | `Project/ProjectPanes.swift` |
| Task rows and group rows | Stand-in (DL-93) | build `wireframes/` for groups | S2-1 | SidebarRowView, GroupRowMenu |
| Untitled sessions (first words, start time) | Built (DL-90) | — | — | `Live/SessionTitles.swift` |
| Files tree | Designed | build `project.html` | — | FileTreePane |
| Console and its tabs | Designed (DB-4 shell tabs) | build `project.html`, surfaces `shell-tab.html`, `console-tabs.html` | — | `Project/ConsoleTabStrip.swift` |
| Console with nothing running; ended session bar | Designed (DB-3) | surfaces `console-none.html`, `console-ended.html`, `console-empty-states.html` | — | `Project/ConsoleStates.swift` |
| Terminal colours | Designed (DB-2) | surfaces `terminal-palette.html` | — | `terminal*` tokens |
| Right pane: Project tab (`PROJECT.md`) | Changed by decision (DL-60): the project's own file | build `project.html` (card, superseded) | DB-16 | RightPane |
| Markdown editor | Built; its look of lists, tables and code isn't designed | build `project.html` | DB-15 | `Editor/`, CodeMirror |
| Claude's edits highlighted; revert | Built; revert is menu-only | build `project.html` (added block) | DB-35, DB-19 | DocumentEditor |
| Editor notices: conflict, removed, read-only | Stand-in (Q-20) | — | DB-14 | DocumentStateBar |
| Properties (frontmatter) block | Designed, not built | frontmatter `frontmatter*.html` | DB-16 | (raw YAML today) |
| Local HTML page and element picker | Stand-in (DL-70) | — | DB-13 | `Editor/HTMLViewer.swift`, PickerBar |
| Browser tab and its bar; not-allowed page | Stand-in (DL-3, DL-99) | — | DB-20 | `Browser/BrowserTabs.swift` |
| Group page | Designed at low fidelity | build `wireframes/group-page.html` | DB-17 | right pane group tab |
| Read-only session (from search) | Designed | search `search-open-session.html` | — | `Search/ReadOnlySession.swift` |

## Search (⇧⌘A)

| Surface | Status | Targets | Open | Code |
|---|---|---|---|---|
| Modal, field, filters, results, preview, footer | Designed; Jump merged in, no ⌘K (DL-80, DL-81) | search `search-overview.html` … `search-open-file.html` (`search-jump.html` superseded) | DB-21, DB-22, DB-24 | `Search/SearchView.swift` |
| Action menu (Tab) | Designed | search `search-actions-file.html`, `-session.html` | — | ActionMenu |
| Find similar from outside search | Built, plain | — | DB-23 | — |

## Sheets, menus, app

| Surface | Status | Open | Code |
|---|---|---|---|
| Move, merge, Make a Project, Delete Session…, Move into Home… confirmations | Stand-in (standard sheets) | DB-12, DB-36, DB-39 | `Model/AppModel+Organize.swift`, `+Home.swift` |
| Drag a session or tile; drop targets | Built (Geoff's feel, F-51) | DB-12 | AllProjectsPanes DragCard |
| First launch | Not designed: Duo opens on every session | DB-5 → S2-3 | — |
| Choose Home Folder… picker | System open panel | S2-3 | `Model/AppModel+Home.swift` |
| Settings | Not built | DB-10 | — |
| Update notice, install consent | Standard sheets | — | `+Update.swift`, `Shell/InstallPrompt.swift` |
| Menu bar | Built from the shortcut map | DB-26 | `Navigation/Commands.swift` |
| Narrow windows, collapsing the right pane, motion | Not designed | DB-25 | — |
| Dark appearance | Not approved | DB-29 | — |
