# duo2 reference

Generated from the action registry (`Sources/DuoControl/Actions.swift`) by `duo2 help --markdown`; don't edit by hand.

Everything a person can do in Duo, Claude can do with `duo2` (DL-71). Every verb takes `--json`; errors go to stderr with a non-zero exit.

## Duo

| Command | What it does | In the app |
|---|---|---|
| `duo2 ping` | Check that Duo is running and reachable. | — |
| `duo2 update` | Whether a newer Duo is on GitHub, and where to get it (Duo › Check for Updates…). | Check for Updates… |
| `duo2 update probe` | Whether in-app updates can work on this Mac, without Duo running: the update feed and the DMG reachable from here, and Duo installed where it can be replaced. | — |
| `duo2 status` | What Duo is showing: the view, the open project, session and document, and counts. | — |
| `duo2 needs-you` | Sessions waiting for the user, with their questions. | Needs You Elsewhere |
| `duo2 undo` | Undo Duo's last move, merge or Make a Project (Edit › Undo). | Undo |
| `duo2 help [family \| --markdown]` | Families and everyday verbs; a family's verbs; or the full reference as Markdown. | duo2 Reference |

## What's on screen

| Command | What it does | In the app |
|---|---|---|
| `duo2 go all` | Show All projects. | All Projects |
| `duo2 go home` | Show Home. | Home |
| `duo2 open <project> [session] [--file <path>]` | Open a project, optionally on one of its sessions or documents. | Open project, Review, project tile, map session row |
| `duo2 peek [open\|close]` | Show or hide the sessions that need the user in other projects. | Needs You Elsewhere |
| `duo2 peek jump` | Jump into the project selected in the peek. | Jump into Selected Project |
| `duo2 view sidebar show\|hide\|toggle` | Show or hide the left pane. | Toggle Sidebar |
| `duo2 view tab <Project \| document path \| group>` | Switch the right pane's tab. | right pane tab, Open Project File |
| `duo2 view group <group> expand\|collapse` | Expand or collapse a group in the session list. | group row |
| `duo2 view select <session id>` | Select a session's card (action column or peek) without opening it. | action card, peek card |
| `duo2 view sort recent\|name` | Order All projects' map by newest activity or by name (View › Sort Projects By). | Sort Projects By, map sort popup |
| `duo2 view filter [text]` | Narrow All projects' map to projects and folders whose name or path has the text; no text clears it. | Filter folders |
| `duo2 view hidden on\|off\|toggle` | Show or hide dotfiles in the project's file tree (View › Show Hidden Files). | Show Hidden Files |
| `duo2 view folder <folder> open\|close` | Open or close a folder in the project's file tree. | folder row |

## Projects

| Command | What it does | In the app |
|---|---|---|
| `duo2 projects` | Projects and folders with sessions, with goal, health and next step. | — |
| `duo2 project show <project>` | A project's folder, project file, goal, health, next step and sessions. | — |
| `duo2 project make <folder name> [--not-now]` | Make a folder with sessions a documented project: writes a starter PROJECT.md and opens it. --not-now instead hides the folder's Make a Project notice (the Project tab still offers it). Undo with `duo2 undo`. | Make a Project, Not Now |
| `duo2 project archive <project>` | File a project away: its tile moves into the map's Archived rollup. Sessions, counts and search are unchanged. Undo with `duo2 undo`. | Archive Project, archived rollup |
| `duo2 project unarchive <project>` | Bring an archived project back to its topic column. | Unarchive Project |
| `duo2 home set <folder>` | Make a folder Home, the container of the projects the user tracks (DL-85): adds a HOME.md if there's none. Duo lists every session with or without a Home. Undo with `duo2 undo`. | Choose Home Folder…, Change… |
| `duo2 project move-into-home <project\|folder> [--into <topic folder>]` | Move a project or folder into Home (its top level, or a topic folder with --into) with every session filed under it (journaled; sessions stay its). The user confirms in Duo. Undo with `duo2 undo`. | Move into Home…, Move |
| `duo2 project reconnect <project\|folder> [--to <folder>]` | A project or folder moved outside Duo (DB-8): its sessions follow it to where it is now (found by Duo, or --to), the way Claude's /cd moves them; journaled. The user confirms in Duo. Undo with `duo2 undo`. | Reconnect Sessions…, Use New Place, Locate Folder… |
| `duo2 project forget <folder>` | Remove a missing folder's tile from Duo (DB-8); its sessions stay in Claude's storage and in search. Undo with `duo2 undo`. | Remove from Duo |
| `duo2 project new <name> [--goal <text>] [--into <topic folder>] [--session]` | Make a new project in Home (or a topic folder in it): a folder with a starter PROJECT.md holding the goal. --session starts a Claude session in it. Undo with `duo2 undo`. | + New project, Create Project, New Project… |
| `duo2 inventory` | Claude's session storage, read only: each folder's sessions, size, missing folders, collisions, duplicate ids, and what Claude's cleanup takes within 7 days (CONS FR-7.1). | — |
| `duo2 evidence <project\|folder>` | For a catch-all folder, read only: the files each session edited, its candidate home, and date clusters (CONS FR-7.10). | — |
| `duo2 migrations` | Storage migrations Duo planned or ran, newest first, with their state (CONS §6.3). | — |
| `duo2 migrate plan relocate <session> --to <folder> \| move-folder <folder> --to <new path>` | Plan a storage change and show every step; nothing moves yet. Relocate moves a session's transcript into another folder's picker, as /cd does; move-folder moves a folder and its sessions together (CONS §7.4, §7.5). | — |
| `duo2 migrate apply <migration>` | Run a planned migration: journaled, verified, undoable. The user confirms in Duo. | — |
| `duo2 migrate undo <migration>` | Undo a migration by replaying its journal in reverse. | — |
| `duo2 project merge <source> --into <target>` | Move every session of one project or folder into another. Files stay. The user confirms in Duo. | Merge Into, Merge Sessions Into, drag a tile onto a tile |

## Sessions

| Command | What it does | In the app |
|---|---|---|
| `duo2 sessions [--project <p>]` | Sessions with id, state, title and project. | — |
| `duo2 session show <id>` | A session's title, project, state, note, next step, transcript path and recent turns. | — |
| `duo2 session new [--project <p>] [--prompt <text>]` | Start a Claude session in a project (the current one by default). | + New session, New Session, console +, New Claude Session, Start Claude here, Start Claude in Home, Start in |
| `duo2 session open <id>` | Show a session's terminal, resuming it if needed. | session row, console tab, Home tab, Resume |
| `duo2 session close [id]` | End a session's process and close its tab (it stays listed and resumable). | Close Tab, End Session |
| `duo2 session move <id> --to <project> [--new]` | File a session in another project, or with --new in a new project of that name made in Home; it moves there on its next resume. The user confirms in Duo. Undo with `duo2 undo`. | Move to Project, New Project…, drag a session onto a tile |
| `duo2 session note <text>` | Tell the user what this session is doing (one line, shown in Duo). | — |
| `duo2 session next <text>` | Tell the user what this session needs next (one line). | — |
| `duo2 session carry-on <id>` | Start a new session carrying on from an archived one. | — |
| `duo2 session fork <id>` | Carry a session on as a fork: a new session with the same history (the original is left alone). | Resume as a Fork |
| `duo2 session link <session>` | A Markdown link to a session for a note or task: [title](duo2://session/<id>). Clicking it in Duo opens or resumes the session (DL-87). | Copy Link, Copy Markdown link |
| `duo2 session archive <id>` | File a session away: it leaves the lists and counts, keeps its transcript, stays searchable, and sits in its project's Archived fold. Not while it runs. Undo with `duo2 undo`. | Archive Session |
| `duo2 session unarchive <id>` | Bring an archived session back into its project's list. | Unarchive Session, Archived fold |
| `duo2 session delete <id>` | Delete a session and its local logs for good (transcript, file history, environment; Duo's archived copy). The user confirms in Duo; never for a running session. | Delete Session… |
| `duo2 idle` | Idle, resumable sessions, newest first, grouped by when (the map footer's list). | idle footer |
| `duo2 shell new` | Open a plain shell in the console (DL-8); typing `claude` in it makes it a session. | New Shell |
| `duo2 tasks [--project <p>]` | Task notes (tasks/*.md in each project) with their status and how many sessions their `sessions:` frontmatter links (DL-93). | — |
| `duo2 task make <session\|group> [--title <t>]` | Make a Task: writes tasks/<slug>.md whose `sessions:` links the session (or the group's sessions; the group becomes the task) and opens it. Undo with `duo2 undo`. | Make a Task |
| `duo2 task new [title] [--project <p>]` | + New task: a task note with no sessions yet, opened to write. Undo with `duo2 undo`. | + New task, New Task |
| `duo2 task session <task> [--project <p>]` | New Session in Task: starts a Claude session in the task's project with its link already in the note's `sessions:` list, and shows it when that project is open. Once Claude's prompt is up, Duo types `@tasks/<note>.md` into it and doesn't send it (DL-112): no turn is spent until someone adds a word and presses Return. Also the + on a task row's hover. | New Session in Task |
| `duo2 task status <task> <open\|in-progress\|waiting\|review\|done\|dropped> [--project <p>]` | Set a task's status: rewrites only `status:` (and `completed:` when done or dropped). Done and dropped tasks leave the lists. Undo with `duo2 undo`. | Status |
| `duo2 task add <task> <session>` | Add to Task: puts the session's link in the task note's `sessions:` list, touching nothing else in the note. Undo with `duo2 undo`. | Add to Task, Open Task Note |
| `duo2 groups [--project <p>]` | Groups and their sessions, with each group's most urgent state. | — |
| `duo2 group new <name> <session>…` | Group sessions of one project under a name. | — |
| `duo2 group add <group> <session>…` | Add sessions to a group. | — |
| `duo2 group remove <group> <session>…` | Take sessions out of a group (an empty group goes away). | — |
| `duo2 group rename <group> <new name>` | Rename a group. | — |
| `duo2 group delete <group>` | Ungroup: the group goes, its sessions stay. | — |

## Files

| Command | What it does | In the app |
|---|---|---|
| `duo2 files [folder] [--project <p>] [--hidden]` | The project's files and folders, three levels deep; --hidden includes dotfiles. | — |
| `duo2 file new [--in <folder>] [--name <name>]` | Create a Markdown file and open it. | New Markdown File, right pane + |
| `duo2 file new-folder [--in <folder>] [--name <name>]` | Create a folder. | New Folder |
| `duo2 file template <template> [--in <folder>]` | Create a file from a template (the project's templates/, then Home's). | New from Template |
| `duo2 file templates` | The templates available here. | — |
| `duo2 file rename <path> <new name>` | Rename a file or folder; open tabs follow. | Rename |
| `duo2 file duplicate <path>` | Copy a file or folder next to itself. | Duplicate |
| `duo2 file move <path> <folder>` | Move a file or folder; open tabs follow. | Move To… |
| `duo2 file trash <path>` | Move to the Trash (never deleted outright). | Move to Trash |
| `duo2 file reveal <path>` | Show in Finder. | Reveal in Finder |
| `duo2 file open-with <path> [--app <name>]` | Open in another app (the default app if none named). | Open With, Other… |
| `duo2 file path <path> [--relative \| --link] [--copy]` | Print a file's path, relative path or Markdown link; --copy puts it on the clipboard. | Copy Path, Copy Relative Path, Copy as Link |

## Documents

| Command | What it does | In the app |
|---|---|---|
| `duo2 doc open <path> [--project <p>]` | Open a document in the right pane (Markdown in the editor, HTML as a page). A file outside every project opens as a tab in the project on screen (or --project). | Open, file row, Open File…, file dropped on the right pane, Open CLAUDE.md |
| `duo2 doc close [path] [--others]` | Close a document tab (saved first), or every other one. | Close Tab, Close Other Tabs |
| `duo2 doc tabs` | The open document tabs, and which one shows. | — |
| `duo2 doc status <file>` | Whether a file is open in Duo's editor, unsaved or in conflict. Check before editing a file the user may have open. | — |
| `duo2 doc read [path]` | A document's text as the editor has it (unsaved edits included); the showing document by default. | — |
| `duo2 doc selection` | The text selected in the editor, with its file and lines. | — |
| `duo2 doc select <line> [to-line]` | Select lines in the showing document. | — |
| `duo2 doc save` | Save the showing document now (it also autosaves). | Save |
| `duo2 doc format bold\|italic\|code\|link\|heading1\|heading2\|heading3\|task\|properties` | Format the selection (bold, italic, code, a link waiting for its address), make its lines headings or tasks (again takes it off), or start the properties block. | Bold, Italic, Code, Link…, Heading 1, Heading 2, Heading 3, Task, Add Properties |
| `duo2 doc table insert\|row-above\|row-below\|column-before\|column-after\|delete-row\|delete-column\|align-left\|align-center\|align-right\|next\|previous` | Edit the table at the caret as Markdown, its columns kept lined up: insert a 3 × 2 table, add or delete a row or column, align a column, or move to the next or previous cell (the last cell's next adds a row). | Insert Table, Add Row Above, Add Row Below, Add Column Before, Add Column After, Delete Row, Delete Column, Left, Center, Right, + Row, + Column, Align, Delete |
| `duo2 doc find <text>` | Find text in the showing document and select the next match. | Find |
| `duo2 doc prop list \| get <name> \| set <name> <value> \| remove <name> \| type <name> <text\|list\|number\|checkbox\|date\|datetime\|link>` | The showing document's properties (frontmatter): read them, or change one line through the editor, highlighted as Claude's (DB-16). Lists: `set tags "[a, b]"`. | Add a property, property type menu, Pick a date, property checkbox |
| `duo2 doc insert <text> [--line <n>]` | Insert text into the showing document through the editor (highlighted as added by Claude), at a line or the caret. | — |
| `duo2 doc replace <find> <replacement>` | Replace text in the showing document through the editor (highlighted as added by Claude). | — |
| `duo2 doc revert [--all \| --line <n>]` | Put back what Claude changed in the open document: the change at the caret or a line, or all of them since the user's last edit (ENH-4). | Revert This Change, Revert All of Claude's Changes, Revert Claude's Change |
| `duo2 doc edit --stdin` | Apply an Edit-tool-shaped change ({file_path, old_string, new_string, replace_all} or {file_path, edits} or {file_path, content}, as JSON on stdin) to a document open in Duo, through the editor, highlighted. | — |
| `duo2 doc resolve mine\|theirs` | End a conflict in the showing document: keep the user's text (saved over the file) or take the file's. The other version stays in history. Only when the user asks. | Keep Mine, Use Theirs |
| `duo2 doc history [path]` | Versions Duo kept of a document (as opened, both sides of conflicts, before removal), newest last, with where each is stored. | — |

## HTML pages

| Command | What it does | In the app |
|---|---|---|
| `duo2 browser open [url]` | A browser tab in the right pane (⌥⌘T). Sites not on the allow list show Allow or Open in Browser instead of loading (DL-3). | New Browser Tab, Open Location…, Open in Browser, Copy Address |
| `duo2 browser allow <host>` | Add a site to the allow list, so its pages open in Duo's browser tabs (and its subdomains). | — |
| `duo2 browser sites` | The allow list: sites Duo opens in its own browser tabs; everything else opens in the system browser (DL-3). | Edit… |
| `duo2 browser tabs` | Browser tabs open in Duo: id, project, title, address. | — |
| `duo2 browser read [selector] [--tab <id>]` | The page's text (or one element's), with its title and address (LR-45). Allowed sites only. | — |
| `duo2 browser click <selector> [--tab <id>]` | Click the element a CSS selector names, scrolled into view. | — |
| `duo2 browser fill <selector> <text…> [--tab <id>]` | Type into an input, text area or editable element, as a person would (input and change events). | — |
| `duo2 browser wait <selector> [--timeout <s>] [--tab <id>]` | Wait for an element to appear (default 10 s). | — |
| `duo2 browser screenshot [--tab <id>]` | Save a picture of the visible page as a PNG and print its path. | — |
| `duo2 browser go <url> [--tab <id>]` | Go to an address in the tab; a site not on the allow list isn't loaded. | — |
| `duo2 browser back [--tab <id>]` | Back in the tab's history. | Back |
| `duo2 browser forward [--tab <id>]` | Forward in the tab's history. | Forward |
| `duo2 browser close [--tab <id>]` | Close the browser tab. | — |
| `duo2 html reload` | Reload the HTML page showing (it also reloads when its files change). | Reload Page |
| `duo2 html pick [selector]` | Start the element picker for the user, or select the element a CSS selector names. | Select Element, Pick Another |
| `duo2 html stop` | Close the element picker. | Cancel picking |
| `duo2 html element [selector]` | Describe an element (the picked one by default): selector, text, attributes, styles, box, HTML. | — |
| `duo2 html selection` | The text and images selected in the HTML page. | — |

## Send to Claude

| Command | What it does | In the app |
|---|---|---|
| `duo2 send file <path> [--to <id> \| --new]` | Put an @-reference to a file or folder into a session's prompt. | Send to Claude, Send To |
| `duo2 send session <id> [--to <id> \| --new]` | Put a session's reference into a session's prompt. | Send to Claude |
| `duo2 send project <project> [--to <id> \| --new]` | Put a project's reference into a session's prompt. | Send to Claude |
| `duo2 send selection [--to <id> \| --new]` | Put the user's selection (document or HTML page) into a session's prompt. | Send Selection to Claude, Send Selection To, Send Image to Claude, Send Image To |
| `duo2 send element [--to <id> \| --new]` | Put the picked HTML element into a session's prompt. | Send to Claude, Send To, New Session |
| `duo2 send text <text> [--to <id> \| --new]` | Type text into a session's prompt for the user to finish and send. | — |
| `duo2 selection` | What the user has selected or picked right now, in the editor or an HTML page. | — |

## Search

| Command | What it does | In the app |
|---|---|---|
| `duo2 search <query> \| --similar <path> [-k N] [--project P] [--kind file\|session\|memory] [--exact]` | Search every project by meaning and by words. Works without the app; read-only. | Search Everything…, Search all projects, Clear filters, Include archived, Exact, Find Similar |
| `duo2 search-status` | How much of each project the search index covers. | Show details |
| `duo2 search-rebuild` | Rebuild the search index from scratch (the old one goes to the Trash). | Rebuild the index |

## Setup

| Command | What it does | In the app |
|---|---|---|
| `duo2 doctor` | How this terminal finds Duo, whether it can reach it, and what Duo installed. | — |
| `duo2 install` | Install or refresh what lets Claude sessions anywhere use duo2: a short block in ~/.claude/CLAUDE.md, a duo2 skill, ~/.local/bin/duo2 (DL-74). | Install, Install… |
| `duo2 uninstall` | Remove exactly what `duo2 install` added (anything you edited stays). | Remove… |
| `duo2 settings [claude-path <path\|auto> \| notify on\|off \| dock-badge on\|off]` | Duo's settings (S3-1): with no arguments, all of them; otherwise set one. The `claude` Duo runs, notifications when a session needs the user, the Dock badge. | Choose…, Use Found One |
| `duo2 walk setup <test id>` | Put Duo in the state an acceptance-walk test starts from (the walk page's Set up test button, or `duo2://walk-setup?id=…`). Steps come from ~/DuoAcceptance/walk-setups.json, never from the caller. | Set up test |
| `duo2 hook pre-edit` | Used by Duo's sessions (a PreToolUse hook): Claude's Edit, MultiEdit and Write on a document open in Duo go through the editor instead of the file (DL-78). | — |
| `duo2 legacy [disable --yes \| restore <backup>]` | Find legacy Duo's instructions in ~/.claude; disable them (backed up first) or restore them. | Disable…, Restore |

## In the app only

| Item | Why it has no verb |
|---|---|
| Add to .gitignore | a one-time question to the user (DL-50) |
| Align Column | a submenu, not an action |
| Cancel | a step inside another action's dialog or picker |
| Close Window | window management |
| Enter Full Screen | window management |
| Exit Full Screen | window management |
| Format | a menu, not an action |
| Go | a menu, not an action |
| Heading | a submenu, not an action |
| Look Again | re-reads what Duo already refreshes every 2 s; the CLI always reads fresh state |
| Next Pane | not built yet |
| No other sessions in | a disabled hint on + Add |
| No templates yet: add .md files to a templates folder | a disabled hint |
| Not Now | the user's answer to the install question; `duo2 install` and `duo2 uninstall` change it later |
| OK | dismisses a notice |
| Open Settings… | not built: Settings waits on its design (DB-10) |
| Previous Pane | not built yet |
| Project | a menu, not an action |
| Report an Issue… | opens GitHub's new-issue form, filled in, for the user to edit and submit |
| Resume a session | the debug gallery only (DL-59 removed it from the app) |
| Save to Recreate | writes the user's own text back after the file was removed on disk; Claude can do the same with `duo2 doc edit` (content) once the user asks |
| Session | a menu, not an action |
| Show in Finder | reveals a file or folder in Finder (Settings, editor notices, launch sheets) |
| Table | a submenu, not an action |
| Toggle Right Pane | not built yet |
| What’s New in This Version | opens this version's release notes on GitHub; `duo2 status` names the version |
| confirmation sheet | the user's own consent; Claude can't confirm for them |
