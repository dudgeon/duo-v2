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
| Home pane with no Home folder | Designed (DL-100): "Choose a Home folder", Choose Home Folder… and Not Now | slice2 `no-home.html` | — | HomePane, `ConsoleMessage(.noHome)` |
| The map: columns, tiles | Designed (DL-100), changed by decision (DL-104): a filter and sort header, Home's ★ tile, folders outside Home as rows by parent folder with live ones as tiles; Home's unlabelled column alone flows its tiles three across (stand-in, Q-42) | slice2 `map-folders.html`, `no-home.html`; many-projects `map-many.html` | DB-38 (folder mark) | MapColumn, MapGrid, MapHeader, HomeTile, OutsideGroup, ProjectTile |
| Folder tiles ("No project file") | Stand-in (DL-63) | — | DB-12 | ProjectTile |
| Missing or moved folder tiles ("Folder not found", "Moved to …") | Designed (DL-101); "In the Trash" not built | slice3 `missing-folder.html` | — | ProjectTile, MissingNotice, `Live/MissingFolders.swift` |
| New project tile | Designed; opens the New project sheet (DL-100) | build `overview.html` | — | NewProjectTile |
| Sessions open in Duo, tinted | Stand-in (ENH-7) | — | DB-33 | TileSessionRow, `activeTint` |
| Archived rollup under the map | Stand-in (ENH-6) | — | DB-34 | `AllProjects/ArchivedProjects.swift` |
| Idle footer and idle list | Designed (DB-1) | surfaces `idle-list.html`, `idle-many.html` | — | `AllProjects/IdleList.swift` |
| Action column: needs you, ready for review | Designed (no reply buttons, DL-29); the reason after the project, 6-line clamp with "… more", "Nothing needs you." (DL-100) | build `overview.html`, `flow-zoom-*.html`, slice2 `needs-you-states.html` | — | ActionColumnPane, NeedsYouCard, ReviewCard |
| Action column: Open tasks | Designed (DL-100) | slice2 `map-folders.html` | — | ActionColumnPane, TaskLine |
| Peek (needs you elsewhere) | Designed | build `flow-zoom-*.html` | — | `Navigation/PeekView.swift` |

## Inside a project

| Surface | Status | Targets | Open | Code |
|---|---|---|---|---|
| Breadcrumb `All projects › folder › project` | Changed by decision (DL-92) | build `project.html` | — | ProjectBreadcrumb |
| Session list: Needs you, Open, Today, This week, Earlier, Tasks, Archived | Designed (DL-100) | slice2 `project-sessions.html`, `session-rows.html` | DB-33 (open tint) | `Project/ProjectPanes.swift` |
| Task rows and group rows | Designed (DL-100): task box, "status · n", no wait; groups keep `group · n` | slice2 `session-rows.html` | — | SidebarRowView, GroupRowMenu, TaskBox |
| Untitled sessions (first words, start time) | Built (DL-90) | — | — | `Live/SessionTitles.swift` |
| Files tree | Designed; open and closed folders and hidden files are stand-ins (DL-105) | build `project.html` | Q-40 | FileTreePane |
| A tab for a file outside the project | Stand-in (DL-106): the file name, its path as the tooltip; File › Open File… (⌘O) or a drop from Finder | — | Q-39 | RightPane, `Model/AppModel+Files.swift` `openFile` |
| Console and its tabs | Designed (DB-4 shell tabs) | build `project.html`, surfaces `shell-tab.html`, `console-tabs.html` | — | `Project/ConsoleTabStrip.swift` |
| Console with nothing running; ended session bar | Designed (DB-3) | surfaces `console-none.html`, `console-ended.html`, `console-empty-states.html` | — | `Project/ConsoleStates.swift` |
| Terminal colours | Designed (DB-2) | surfaces `terminal-palette.html` | — | `terminal*` tokens |
| Right pane: Project tab (`PROJECT.md`) | Changed by decision (DL-60): the project's own file | build `project.html` (card, superseded) | DB-16 | RightPane |
| Markdown editor | Designed (DL-101): headings, lists, tasks, quotes, code, tables, images, Claude's deletions, find | slice3 `editor-document.html`, `editor-states.html` | — | `Editor/`, CodeMirror |
| Claude's edits highlighted; revert | Built; revert is menu-only | build `project.html` (added block) | DB-35, DB-19 | DocumentEditor |
| Editor notices: conflict, removed, renamed, read only | Designed (DL-101) | slice3 `editor-notices.html` | — | DocumentStateBar, NoticeBar |
| Properties (frontmatter) block | Designed and built (F-77): icons, controls, fold, Tab, suggestions, type menu, date picker, invalid, changed by Claude; task notes keep their S2-5 look (Q-33) | frontmatter `frontmatter*.html`; slice2 `task-note.html` | — | `Vendor/codemirror/src/duo-editor.js`, `Live/PropertyCorpus.swift` |
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
| Move into Home… and New project sheets | Designed (DL-100): Duo's own sheets under the toolbar, the map dimmed to 55% | — | `Shell/Sheets.swift` |
| Confirmations and launch questions (merge, move, delete, reconnect, install, legacy Duo, .gitignore) | Designed (DL-101): Duo's own sheets, one at a time | — | `Shell/DuoQuestion.swift` |
| Drag a session or tile; drop targets | Built (Geoff's feel, F-51) | DB-12 | AllProjectsPanes DragCard |
| First launch | Designed (DL-100): no welcome screen; the map is it | — | — |
| Choose Home Folder… picker | System open panel | S2-3 | `Model/AppModel+Home.swift` |
| Settings | Designed (DL-101) | — | `Shell/SettingsView.swift` |
| Notifications and the Dock badge | Designed (DL-101); drawn by macOS | — | `Model/AppModel+Notify.swift` |
| Update notice, install consent | Standard sheets | — | `+Update.swift`, `Shell/InstallPrompt.swift` |
| Menu bar | Built from the shortcut map | DB-26 | `Navigation/Commands.swift` |
| Narrow windows, collapsing the right pane, motion | Not designed | DB-25 | — |
| Dark appearance | Not approved | DB-29 | — |
