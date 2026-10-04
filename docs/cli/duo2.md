# duo2 reference

Generated from the action registry (`Sources/DuoControl/Actions.swift`) by `duo2 help --markdown`; don't edit by hand.

Everything a person can do in Duo, Claude can do with `duo2` (DL-71). Every verb takes `--json`; errors go to stderr with a non-zero exit.

## Duo

| Command | What it does | In the app |
|---|---|---|
| `duo2 ping` | Check that Duo is running and reachable. | — |
| `duo2 status` | What Duo is showing: the view, the open project, session and document, and counts. | — |
| `duo2 needs-you` | Sessions waiting for the user, with their questions. | Needs You Elsewhere |
| `duo2 undo` | Undo Duo's last move, merge or Make a Project (Edit › Undo). | Undo |
| `duo2 help [family \| --markdown]` | Families and everyday verbs; a family's verbs; or the full reference as Markdown. | — |

## What's on screen

| Command | What it does | In the app |
|---|---|---|
| `duo2 go all` | Show All projects. | All Projects |
| `duo2 go home` | Show Home. | Home |
| `duo2 open <project> [session] [--file <path>]` | Open a project, optionally on one of its sessions or documents. | Open project, Review, project tile, map session row |
| `duo2 peek [open\|close]` | Show or hide the sessions that need the user in other projects. | Needs You Elsewhere |
| `duo2 peek jump` | Jump into the project selected in the peek. | Jump into Selected Project |
| `duo2 view sidebar show\|hide\|toggle` | Show or hide the left pane. | Toggle Sidebar |
| `duo2 view tab <Project \| document path \| group>` | Switch the right pane's tab. | right pane tab |
| `duo2 view group <group> expand\|collapse` | Expand or collapse a group in the session list. | group row |
| `duo2 view select <session id>` | Select a session's card (action column or peek) without opening it. | action card, peek card |

## Projects

| Command | What it does | In the app |
|---|---|---|
| `duo2 projects` | Projects and folders with sessions, with goal, health and next step. | — |
| `duo2 project show <project>` | A project's folder, project file, goal, health, next step and sessions. | — |
| `duo2 project make <folder name>` | Make a folder with sessions a documented project: writes a starter PROJECT.md and opens it. Undo with `duo2 undo`. | Make a Project |
| `duo2 project archive <project>` | File a project away: its tile moves into the map's Archived rollup. Sessions, counts and search are unchanged. Undo with `duo2 undo`. | Archive Project, archived rollup |
| `duo2 project unarchive <project>` | Bring an archived project back to its topic column. | Unarchive Project |
| `duo2 home set <folder>` | Make a folder Home, the container of the projects the user tracks (DL-85): adds a HOME.md if there's none. Duo lists every session with or without a Home. Undo with `duo2 undo`. | Choose Home Folder… |
| `duo2 project move-into-home <project\|folder>` | Move a project or folder into Home with every session filed under it (journaled; sessions stay its). The user confirms in Duo. Undo with `duo2 undo`. | Move into Home… |
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
| `duo2 session close [id]` | End a session's process and close its tab (it stays listed and resumable). | Close Tab |
| `duo2 session move <id> --to <project>` | File a session in another project; it moves there on its next resume. The user confirms in Duo. | Move to Project, drag a session onto a tile |
| `duo2 session note <text>` | Tell the user what this session is doing (one line, shown in Duo). | — |
| `duo2 session next <text>` | Tell the user what this session needs next (one line). | — |
| `duo2 session carry-on <id>` | Start a new session carrying on from an archived one. | — |
| `duo2 session fork <id>` | Carry a session on as a fork: a new session with the same history (the original is left alone). | Resume as a Fork |
| `duo2 session archive <id>` | File a session away: it leaves the lists and counts, keeps its transcript, stays searchable, and sits in its project's Archived fold. Not while it runs. Undo with `duo2 undo`. | Archive Session |
| `duo2 session unarchive <id>` | Bring an archived session back into its project's list. | Unarchive Session, Archived fold |
| `duo2 session delete <id>` | Delete a session and its local logs for good (transcript, file history, environment; Duo's archived copy). The user confirms in Duo; never for a running session. | Delete Session… |
| `duo2 idle` | Idle, resumable sessions, newest first, grouped by when (the map footer's list). | idle footer |
| `duo2 shell new` | Open a plain shell in the console (DL-8); typing `claude` in it makes it a session. | New Shell |
| `duo2 groups [--project <p>]` | Groups and their sessions, with each group's most urgent state. | — |
| `duo2 group new <name> <session>…` | Group sessions of one project under a name. | — |
| `duo2 group add <group> <session>…` | Add sessions to a group. | — |
| `duo2 group remove <group> <session>…` | Take sessions out of a group (an empty group goes away). | — |
| `duo2 group rename <group> <new name>` | Rename a group. | — |
| `duo2 group delete <group>` | Ungroup: the group goes, its sessions stay. | — |

## Files

| Command | What it does | In the app |
|---|---|---|
| `duo2 files [folder] [--project <p>]` | The project's files and folders. | — |
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
| `duo2 doc open <path>` | Open a document in the right pane (Markdown in the editor, HTML as a page). | Open, file row |
| `duo2 doc close [path] [--others]` | Close a document tab (saved first), or every other one. | Close Tab, Close Other Tabs |
| `duo2 doc tabs` | The open document tabs, and which one shows. | — |
| `duo2 doc status <file>` | Whether a file is open in Duo's editor, unsaved or in conflict. Check before editing a file the user may have open. | — |
| `duo2 doc read [path]` | A document's text as the editor has it (unsaved edits included); the showing document by default. | — |
| `duo2 doc selection` | The text selected in the editor, with its file and lines. | — |
| `duo2 doc select <line> [to-line]` | Select lines in the showing document. | — |
| `duo2 doc save` | Save the showing document now (it also autosaves). | Save |
| `duo2 doc format bold\|italic` | Make the selection bold or italic. | Bold, Italic |
| `duo2 doc find <text>` | Find text in the showing document and select the next match. | Find |
| `duo2 doc insert <text> [--line <n>]` | Insert text into the showing document through the editor (highlighted as added by Claude), at a line or the caret. | — |
| `duo2 doc replace <find> <replacement>` | Replace text in the showing document through the editor (highlighted as added by Claude). | — |
| `duo2 doc revert [--all \| --line <n>]` | Put back what Claude changed in the open document: the change at the caret or a line, or all of them since the user's last edit (ENH-4). | Revert This Change, Revert All of Claude's Changes, Revert Claude's Change |
| `duo2 doc edit --stdin` | Apply an Edit-tool-shaped change ({file_path, old_string, new_string, replace_all} or {file_path, edits} or {file_path, content}, as JSON on stdin) to a document open in Duo, through the editor, highlighted. | — |
| `duo2 doc resolve mine\|theirs` | End a conflict in the showing document: keep the user's text (saved over the file) or take the file's. The other version stays in history. Only when the user asks. | Keep Mine, Use Theirs |
| `duo2 doc history [path]` | Versions Duo kept of a document (as opened, both sides of conflicts, before removal), newest last, with where each is stored. | — |

## HTML pages

| Command | What it does | In the app |
|---|---|---|
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
| `duo2 install` | Install or refresh what lets Claude sessions anywhere use duo2: a short block in ~/.claude/CLAUDE.md, a duo2 skill, ~/.local/bin/duo2 (DL-74). | Install |
| `duo2 uninstall` | Remove exactly what `duo2 install` added (anything you edited stays). | — |
| `duo2 walk setup <test id>` | Put Duo in the state an acceptance-walk test starts from (the walk page's Set up test button, or `duo2://walk-setup?id=…`). Steps come from ~/DuoAcceptance/walk-setups.json, never from the caller. | Set up test |
| `duo2 hook pre-edit` | Used by Duo's sessions (a PreToolUse hook): Claude's Edit, MultiEdit and Write on a document open in Duo go through the editor instead of the file (DL-78). | — |
| `duo2 legacy [disable --yes \| restore <backup>]` | Find legacy Duo's instructions in ~/.claude; disable them (backed up first) or restore them. | — |

## In the app only

| Item | Why it has no verb |
|---|---|
| Add to .gitignore | a one-time question to the user (DL-50) |
| Cancel | a step inside another action's dialog or picker |
| Close Window | window management |
| Format | a menu, not an action |
| Go | a menu, not an action |
| Locate Folder… | not built: waits on its design (DB-8) |
| Look Again | re-reads what Duo already refreshes every 2 s; the CLI always reads fresh state |
| Next Pane | not built yet |
| No templates yet: add .md files to a templates folder | a disabled hint |
| Not Now | the user's answer to the install question; `duo2 install` and `duo2 uninstall` change it later |
| Open Settings… | not built: Settings waits on its design (DB-10) |
| Previous Pane | not built yet |
| Resume a session | the debug gallery only (DL-59 removed it from the app) |
| Save to Recreate | writes the user's own text back after the file was removed on disk; Claude can do the same with `duo2 doc edit` (content) once the user asks |
| Toggle Right Pane | not built yet |
| confirmation sheet | the user's own consent; Claude can't confirm for them |
