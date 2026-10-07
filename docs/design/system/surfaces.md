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
| Home pane: terminal and session tabs | Designed (DL-126 the hover ×; DL-134 its fill); changed by decision (DL-142): Home opens in chat, with the light header and strip while chat shows (built, F-182; a terminal or fallen back keeps them dark) | build `overview.html`, surfaces `home-none.html`, tab-close `console-tabs-close.html`, tab-hover `hover-fill-a.html` | — | `AllProjects/AllProjectsPanes.swift` HomePane |
| Home pane with no Home folder | Designed (DL-100): "Choose a Home folder", Choose Home Folder… and Not Now | slice2 `no-home.html` | — | HomePane, `ConsoleMessage(.noHome)` |
| The map: columns, tiles | Designed (DL-100), changed by decision (DL-104): a filter and sort header, Home's ★ tile, folders outside Home as rows by parent folder with live ones as tiles; Home's unlabelled column alone flows its tiles three across, and two lists keep a third each (DL-111) | slice2 `map-folders.html`, `no-home.html`; many-projects `map-many.html`; stand-ins `q42-one-list.html`, `q42-two-lists.html` | DB-38 (folder mark) | MapColumn, MapGrid, MapHeader, HomeTile, OutsideGroup, ProjectTile |
| Folder tiles ("No project file") | Stand-in (DL-63) | — | DB-12 | ProjectTile |
| Inside a folder: `Folder · no project file`, the notice with Make a Project and Not Now, the Project tab's offer | Designed (DL-110) | folder `folder-not-project.html` | — | FolderNotice, FolderProjectTab |
| Missing or moved folder tiles ("Folder not found", "Moved to …") | Designed (DL-101); "In the Trash" not built | slice3 `missing-folder.html` | — | ProjectTile, MissingNotice, `Live/MissingFolders.swift` |
| New project tile | Designed; opens the New project sheet (DL-100) | build `overview.html` | — | NewProjectTile |
| Sessions open in Duo: `at prompt`/`working`, tinted | Designed (DL-133, ENH-7) | canvas https://claude.ai/artifact/2qhPnZG6qUpLWFsXKCYSzt `Tiles` (A) | — | TileSessionRow, `activeTint` |
| Archived rollup under the map | Stand-in (ENH-6) | — | DB-34 | `AllProjects/ArchivedProjects.swift` |
| Idle footer and idle list | Designed (DB-1) | surfaces `idle-list.html`, `idle-many.html` | — | `AllProjects/IdleList.swift` |
| The session list: Board \| List in the map's header, every session across projects by recency, the `3 need you ›` line, `Filter sessions` by search's hybrid ranking | Designed (DL-142); built: Board \| List, the list, its rows (two-line under 520, Q-101), N1's line and its rows with the column hidden, the folds. the filter (search's session hits fused with a word match on names, F-181: `MATCHES · n`, passages, nothing found). Not yet: Home in chat | home-evolution `list-1440`, `list-1280`, `board-1440`, `rows`, `grouping`, `filter`, `needs-you` | Q-100, Q-101 | `AllProjects/SessionList.swift`, `AllProjects/SessionListView.swift` `SessionListPane`, `SessionListRow`, `NeedsYouLine`, `HomeViewToggle`; `AllProjects/SessionListFilter.swift` |
| Action column: needs you, ready for review | Designed (no reply buttons, DL-29); the reason after the project, 6-line clamp with "… more", "Nothing needs you." (DL-100) | build `overview.html`, `flow-zoom-*.html`, slice2 `needs-you-states.html` | — | ActionColumnPane, NeedsYouCard, ReviewCard |
| Action column: Open tasks | Designed (DL-100) | slice2 `map-folders.html` | — | ActionColumnPane, TaskLine |
| Peek (needs you elsewhere) | Designed | build `flow-zoom-*.html` | — | `Navigation/PeekView.swift` |

## Inside a project

| Surface | Status | Targets | Open | Code |
|---|---|---|---|---|
| Breadcrumb `All projects › folder › project` | Changed by decision (DL-92) | build `project.html` | — | ProjectBreadcrumb |
| Session list: Needs you, Open, Today, This week, Earlier, Tasks, Archived | Designed (DL-100); archived tasks in the Archived fold (DL-115) | slice2 `project-sessions.html`, `session-rows.html` | — | `Project/ProjectPanes.swift` |
| Task rows and group rows | Designed (DL-100): task box, "status · n", no wait; groups keep `group · n`. On hover a task row (line or group style) shows a + where its status or time sits: New Session in Task, which drafts `@tasks/<note>.md` in the new session's prompt, unsent (DL-112); the group style also takes the `selected` fill and keeps its status whole, the + after it (DL-132). Right-click: the task menu, with Archive, Delete and Move asking whether the task's sessions go too (DL-115) | slice2 `session-rows.html`; stand-ins `q43-hover.html`, `q43-drafted.html`; standins2 `q46-hover.html`; task-menu `task-menu.html`, `task-menu-archived.html`, `task-questions.html` | — | SidebarRowView, GroupRowMenu, TaskBox, TaskLine, NewSessionInTaskButton, TaskMenuItems |
| Untitled sessions (first words, start time) | Built (DL-90) | — | — | `Live/SessionTitles.swift` |
| Files tree | Designed; open and closed folders and hidden files are stand-ins (DL-105) | build `project.html` | Q-40 | FileTreePane |
| A tab for a file outside the project | Designed (DL-132): the file name, its folder in `text2` under the pointer, its path as the tooltip; File › Open File… (⌘O) or a drop from Finder | standins2 `q39-hover.html` | — | RightPane, `Model/AppModel+Files.swift` `openFile` |
| Console and its tabs | Designed (DB-4 shell tabs; DL-126 the hover ×; DL-134 its fill) | build `project.html`, surfaces `shell-tab.html`, `console-tabs.html`, tab-close `console-tabs-close.html`, tab-hover `hover-fill-a.html` | — | `Project/ConsoleTabStrip.swift` |
| Console with nothing running; ended session bar | Designed (DB-3) | surfaces `console-none.html`, `console-ended.html`, `console-empty-states.html` | — | `Project/ConsoleStates.swift` |
| Chat mode: a readable view of the Claude session (toggle pill, transcript, tool cards, review cards, composer, fallback bar) | Designed (DL-119), built to its boards (F-108 to F-112), `@` in the composer (DL-133, F-148), runs of tool calls folded (DL-135, F-151), the thin strip over chat (DL-136, F-152; Q-87 stand-in: tab glyphs kept); stand-ins for Q-56 (dark, other heading levels, long history, narrow panes, pasted images); in Home's pane too, with the pill on Home's tab row, and a link's target in a status line under the pointer (DL-132); slash commands built to DL-143, `chat-slash-handoff/` (F-177): the ⎿ quiet line and output block, /context drawn, /model and /effort as picker cards, the fallback bar naming the command, the menu's fitted name column (Q-107 open: /context's box on replay) | chat-mode `window.html`, `toggle.html`, `text.html`, `tools.html`, `permission-*.html`, `plan.html`, `question-*.html`, `composer.html`, `status.html`, `fallback.html`; small-features `composer-at.html`, `composer-at-chosen.html`; chat-polish `collapsed.html`, `expanded.html`, `mixed.html`, `needs-you.html`, the candidates `output.html` to `paste.html`, `bar-thin.html`; standins2 `q57-home-pill.html`, `q57-link-status.html`; chat-slash `output.html`, `context.html`, `model-card.html`, `effort-card.html`, `fallback-named.html`, `menu.html` | — | `Chat/` (ChatView, ChatToolViews, ChatRuns, ChatReviewCard, ChatComposerView, ChatChrome) |
| Terminal colours | Designed (DB-2) | surfaces `terminal-palette.html` | — | `terminal*` tokens |
| Right pane: Project tab (`PROJECT.md`) | Changed by decision (DL-60): the project's own file | build `project.html` (card, superseded) | DB-16 | RightPane |
| Markdown editor | Designed (DL-101): headings, lists, tasks, quotes, code, tables, images, Claude's deletions, find | slice3 `editor-document.html`, `editor-states.html` | — | `Editor/`, CodeMirror |
| Editing tables (Format › Table, the bar while the caret is in a table, Tab between cells) | Designed (DL-113) | tables `tables-menu.html`, `tables-bar.html`, `tables-insert.html` | — | `duo-editor.js` (tables), `EditorController.tableMenu` |
| Claude's edits highlighted; revert | Built; revert is menu-only | build `project.html` (added block) | DB-35, DB-19 | DocumentEditor |
| Editor notices: conflict, removed, renamed, read only | Designed (DL-101) | slice3 `editor-notices.html` | — | DocumentStateBar, NoticeBar |
| A file that isn't text: a quiet strip (its kind in plain words, read only, Open With, Show in Finder) over Quick Look, or the name, a line and the buttons centred | Designed (DL-132) | standins2 `q52-preview.html`, `q52-none.html` | — | `Project/BinaryFileView.swift` |
| A Word document (.docx): the offer to make a Markdown copy over Quick Look, the progress bar, why it couldn't; the copy's notice (Undo Conversion, Open Original, OK) with what was inferred and what didn't come over; the name-taken question with a Save new as field | Designed (DL-123) | docx `docx-offer.html`, `docx-name-taken.html`, `docx-converting.html`, `docx-result.html`, `docx-partial.html`, `docx-failed.html`, `docx-failed-kinds.html` | Q-62 (tracked changes) | WordDocumentBar, ConversionNotice, `Model/AppModel+Convert.swift`, `DuoSearch/Docx.swift` |
| Properties (frontmatter) block | Designed and built (F-77): icons, controls, fold, Tab, suggestions, type menu, date picker, invalid, changed by Claude; task notes keep their S2-5 look (Q-33) | frontmatter `frontmatter*.html`; slice2 `task-note.html` | — | `Vendor/codemirror/src/duo-editor.js`, `Live/PropertyCorpus.swift` |
| A PowerPoint deck (.pptx): the slides at the pane's width, the bar with ‹ › Slide n of N, Select Shape and Open With, the shape picker and its bar, Quick Look with why when a deck can't be drawn | Designed (DL-125); drawing, no session and narrow panes (DL-132) | pptx `pptx-viewer.html`, `pptx-picking.html`, `pptx-picked.html`, `pptx-sent.html`, `pptx-fallback.html`; standins2 `q68-drawing.html`, `q68-no-session.html`, `q68-narrow.html` | — | DeckViewer, DeckView, `Vendor/pptx-renderer/`, `DuoSearch/Pptx.swift` |
| Local HTML page and element picker | Stand-in (DL-70) | — | DB-13 | `Editor/HTMLViewer.swift`, PickerBar |
| Browser tab and its bar; not-allowed page; zoom level, download notice, popup tabs | Stand-in (DL-3, DL-99, DL-124); the running download and the popup mark designed (DL-132; zoom and the notice's place and words kept) | standins2 `q66-downloading.html`, `q67-popup.html` | DB-20 | `Browser/BrowserTabs.swift` |
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
| Files dropped on the file tree (move, with a highlight and the clash question) and on a terminal (paths) | Designed (DL-132): selection fill with the drop-target dash; the clash question counts and says where each came from; copies across volumes (standins2 `q50-highlight`, `q50-clash`, `q51-copy`) | — | `Project/TreeDrop.swift`, `Model/AppModel+Drop.swift`, `Live/FileDrop.swift` |
| First launch | Designed (DL-100): no welcome screen; the map is it | — | — |
| Choose Home Folder… picker | System open panel | S2-3 | `Model/AppModel+Home.swift` |
| Settings | Designed (DL-101) | — | `Shell/SettingsView.swift` |
| Notifications and the Dock badge | Designed (DL-101); drawn by macOS. Badges asked for with alerts (DL-138); the Dock menu of sessions that need you, and Settings' line when macOS hides them, designed and built (DL-144) | dock-badge `screens/dock-menu.html`, `q93-*.html` | `Model/AppModel+Notify.swift`, `Shell/SettingsView.swift`, `Duo/DuoApp.swift` (`applicationDockMenu`) |
| Update question (Open Releases Page, Install Now, Later) | Designed (DL-132): the release's notes in a box, Later apart at the left; Open Releases Page is the default where installing needs an administrator password (DL-114) (standins2 `q47-writable`, `q47-admin`) | — | `Model/AppModel+Update.swift` |
| Closing a busy tab | Designed (DL-127; words DL-132): Stop Claude and close “‹name›”? / Stop “‹command›” and close the tab? (standins2 `close-busy`) | — | `Model/AppModel+CloseTab.swift` |
| Install consent | Standard sheet | — | `Shell/InstallPrompt.swift` |
| Menu bar | Designed (DL-108): the walk page's mockups m1–m4: Duo, File, Edit, Format (with Table ▸, DL-113), View, Project, Session, Go, Window, Help; ⌘K is Link… | — | `Navigation/Commands.swift`, `Navigation/ObjectMenus.swift` |
| Narrow windows, collapsing the right pane, motion | Designed (DL-129): side panes hold their width and the middle flexes; the right-pane button at the toolbar's trailing end (⌥⌘0); the map packs topics into columns; motion with Reduce Motion | narrow `narrow-*.html` | — | `Shell/PaneSplit.swift`, `Shell/DuoToolbar.swift` `RightPaneToggle`, `AllProjects/AllProjectsPanes.swift` `PackedColumns` |
| Motion across Duo | Designed (DL-130) and built (F-131 to F-141): sheets, the session list and folds, Mark Complete's hold, the chat review card, drag and drop, tabs, notices, the chip, project to project, the editor highlight, the deck, chat items, drop targets; one Reduce Motion flag; tokens `motion*` with `motionEase` | motion `screens/*.dc.html` (canvas boards), `audit.md` | — | `Design/Motion.swift` (`MotionSettings`, `DuoMotionToken`), each surface's view; `Vendor/codemirror/src/duo-editor.js`, `Vendor/pptx-renderer/deck.js` |
| Dark appearance | Not approved | DB-29 | — |
