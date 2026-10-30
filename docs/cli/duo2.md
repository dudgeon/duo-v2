# duo2 reference

Generated from the action registry (`Sources/DuoControl/Actions.swift`) by `duo2 help --markdown`; don't edit by hand.

Everything a person can do in Duo, Claude can do with `duo2` (DL-71). Every verb takes `--json`; errors go to stderr with a non-zero exit.

## Duo

| Command | What it does | In the app |
|---|---|---|
| `duo2 ping` | Check that Duo is running and reachable. | — |
| `duo2 update [--open]` | Whether a newer Duo is on GitHub, its releases page, and whether installing it in place needs an administrator password (Duo › Check for Updates…, DL-114). --open opens the releases page, as the question's Open Releases Page does, to download the DMG and install it by hand. | Check for Updates…, Open Releases Page |
| `duo2 update probe` | Whether in-app updates can work on this Mac, without Duo running: the update feed and the DMG reachable from here, and Duo installed where it can be replaced. | — |
| `duo2 hangs [--since <hours>] [--stacks] [--clear]` | Times Duo froze: each stall of its main thread of 250 ms or more (2 s shows a beach ball), when, how long and what was on screen; --stacks adds where Duo was stuck, for stalls of half a second or more. Kept on this Mac only (Duo/logs/hangs.jsonl, DL-139). --clear empties it. | — |
| `duo2 status` | What Duo is showing: the view, the open project, session and document, and counts. | — |
| `duo2 needs-you` | Sessions waiting for the user, with their questions. | Needs You Elsewhere |
| `duo2 undo` | Undo Duo's last move, merge or Make a Project (Edit › Undo). | Undo, Undo Conversion |
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
| `duo2 view right show\|hide\|toggle` | Show or hide the right pane: the action column at All projects, the documents in a project (⌥⌘0, DL-129). | Toggle Right Pane, right pane button |
| `duo2 view tab <Project \| document path \| group \| next \| previous>` | Switch the right pane's tab; next and previous step through the active pane's tabs instead (⌃Tab, ⌃⇧Tab, DL-165). | right pane tab, Open Project File, Show Next Tab, Show Previous Tab |
| `duo2 view tab-move left\|right\|<n> [tab] [--pane middle\|right]` | Move a tab along its strip: one place left or right (Move Tab Left / Right on its menu), or to place n among the tabs that move (1 is the leftmost), as a drag does (DL-220). The tab is a document path, a session id or name, or by default the selected tab of the active pane (or --pane). The right pane's Project tab stays first. | Move Tab Left, Move Tab Right, tab dragged along its strip |
| `duo2 view pane next\|previous\|left\|middle\|right` | Make a pane active and give it the keyboard: the next or previous one (⌥⌘→, ⌥⌘←), or one by name; a hidden pane can't be chosen. | Next Pane, Previous Pane |
| `duo2 view group <group\|original id> expand\|collapse` | Expand or collapse a group in the session list: a time group (today, week, earlier), later (the tasks quiet for 3 days), a task, or a thread of forks by its original's session id (DL-228). | group row, Later fold |
| `duo2 view select [<id>…] [--add] [--all] [--clear] [--list project\|list\|action\|idle]` | Select sessions without opening them (DL-247). With one id and no flag it also selects that session's card (action column or peek). Ids set the selection in the list in front: the list with the keyboard, else the project's pane when a project is open, else All projects' List; --add keeps what is selected; --all selects every row showing in the list; --clear clears it; --list names the list (project is the open project's pane). With no arguments it prints the selection and its list. An id that can't be found is named. Acts only on the selection; nothing else changes. | action card, peek card, ⇧-click, ⌘-click, ⌘A |
| `duo2 view sort recent\|name` | Order All projects' map by newest activity or by name (View › Sort Projects By). | Sort Projects By, map sort popup |
| `duo2 view filter [text]` | Narrow All projects' middle, whichever shows: the Board to projects and folders whose name or path has the text, the List to sessions about it; no text clears it. | Filter folders, Filter sessions |
| `duo2 view home board\|list\|toggle [--archived on\|off]` | All projects' middle (DL-142): the Board (the map) or the List, every session across projects by recency (View › Show Board / Show List). Duo remembers the choice. --archived shows or hides the List's Archived fold (its Group popup's Show Archived). | Board, List, Show Board, Show List, Group By Recent, Show Archived, list group popup |
| `duo2 view hidden on\|off\|toggle` | Show or hide dotfiles in the project's file tree (View › Show Hidden Files). | Show Hidden Files |
| `duo2 view folder <folder> open\|close` | Open or close a folder in the project's file tree. | folder row |

## Projects

| Command | What it does | In the app |
|---|---|---|
| `duo2 projects` | Projects and folders with sessions, with goal, health and next step. | — |
| `duo2 project show <project>` | A project's folder, project file, goal, health, next step and sessions. | — |
| `duo2 project make <folder name \| path in Home> [--no-interview] [--not-now]` | Make a folder a documented project (one with sessions, or any folder in Home, DL-212): writes a starter PROJECT.md, opens it, and starts a Claude session there that looks around the folder, interviews you in a few questions and fills PROJECT.md in (DL-223); --json gives its id. --no-interview writes the file without the session. --not-now instead hides the folder's Make a Project notice (the Project tab still offers it). Undo with `duo2 undo`. | Make a Project, Not Now |
| `duo2 project archive <project>` | File a project away: its tile moves into the map's Archived rollup. Sessions, counts and search are unchanged. Undo with `duo2 undo`. | Archive Project, archived rollup |
| `duo2 project unarchive <project>` | Bring an archived project back to its topic column. | Unarchive Project |
| `duo2 home set <folder>` | Make a folder Home, the container of the projects the user tracks (DL-85): adds a HOME.md if there's none. Duo lists every session with or without a Home. Undo with `duo2 undo`. | Choose Home Folder…, Change… |
| `duo2 project move-into-home <project\|folder> [--into <topic folder>]` | Move a project or folder into Home (its top level, or a topic folder with --into) with every session filed under it (journaled; sessions stay its). The user confirms in Duo. Undo with `duo2 undo`. | Move into Home…, Move |
| `duo2 project reconnect <project\|folder> [--to <folder>]` | A project or folder moved outside Duo (DB-8): its sessions follow it to where it is now (found by Duo, or --to), the way Claude's /cd moves them; journaled. The user confirms in Duo. Undo with `duo2 undo`. | Reconnect Sessions…, Use New Place, Locate Folder… |
| `duo2 project forget <folder>` | Remove a missing folder's tile from Duo (DB-8); its sessions stay in Claude's storage and in search. Undo with `duo2 undo`. | Remove from Duo |
| `duo2 project new <name> [--goal <text>] [--into <folder in Home>] [--use-folder] [--session] \| --from-github <link\|owner/repo> [<name>] [--new-branch <b> [--from <base>] \| --branch <existing>] [--keep-in-git] [--sheet]` | Make a new project in Home: a folder with a starter PROJECT.md holding the goal. --into puts it in a folder in Home, by name or by its path in Home (DL-211); with --use-folder that folder itself becomes the project instead, keeping its name, with <name> (optional) as the project's title. --session starts a Claude session in it that interviews you and fills PROJECT.md in (DL-223). --from-github copies a repository into it instead, on a new branch of its own (or --branch), with PROJECT.md kept out of git unless --keep-in-git (DL-149); nothing changes on GitHub. --sheet opens New project from GitHub filled in, for the user. Undo with `duo2 undo`. | + New project, Create Project, New Project…, New Project from GitHub…, Choose Folder…, Make this folder the project |
| `duo2 inventory` | Claude's session storage, read only: each folder's sessions, size, missing folders, collisions, duplicate ids, and what Claude's cleanup takes within 7 days (CONS FR-7.1). | — |
| `duo2 evidence <project\|folder>` | For a catch-all folder, read only: the files each session edited, its candidate home, and date clusters (CONS FR-7.10). | — |
| `duo2 migrations` | Storage migrations Duo planned or ran, newest first, with their state (CONS §6.3). | — |
| `duo2 migrate plan relocate <session> --to <folder> \| move-folder <folder> --to <new path>` | Plan a storage change and show every step; nothing moves yet. Relocate moves a session's transcript into another folder's picker, as /cd does; move-folder moves a folder and its sessions together (CONS §7.4, §7.5). | — |
| `duo2 migrate apply <migration>` | Run a planned migration: journaled, verified, undoable. The user confirms in Duo. | — |
| `duo2 migrate undo <migration>` | Undo a migration by replaying its journal in reverse. | — |
| `duo2 project merge <source> --into <target>` | Move every session of one project or folder into another. Files stay. The user confirms in Duo. | Merge Into, Merge Sessions Into, drag a tile onto a tile |
| `duo2 template show <project\|task> [--project <p>]` | The template new projects or tasks are made from (DL-146): its text and whose it is (a project's own templates/new-task.md, Home's templates/new-<kind>.md, or Duo's base). | — |
| `duo2 template edit <project\|task> [--project <p>]` | Open that template in the right pane with its template bar; with no file yet, Duo's base is written to Home's templates/ first. | Edit Task Template, Edit… |
| `duo2 template copy task --project <p>` | Give a project its own task template: a copy of the one it uses now, in its templates/new-task.md, opened. | Make a Template for |
| `duo2 template reset <project\|task> [--project <p>]` | Home's template back to Duo's base, or (with --project) a project's own removed so Home's is used again. The file goes to the Trash. Asks first. | Reset…, Use Home's…, Use Home's Template… |
| `duo2 template preview <project\|task> [--project <p>] [--title <name>]` | The file that template would make now, filled for a name (Preview in the template bar). | Preview |

## Sessions

| Command | What it does | In the app |
|---|---|---|
| `duo2 sessions [--project <p>]` | Sessions with id, state, kind (terminal or chat), title and project. Text marks the project's director and the pinned (Keep Running) ones; --json adds "director": true, "pinned" and the row's "section" in the project pane: pinned, needs-you, open, tasks, later or other (DL-217, DL-218). A fork (a /branch or /fork) adds "forkOf" (its parent's id) and "fork": "branch" or "fork" (DL-228). | — |
| `duo2 session show <id>` | A session's title, project, state, note, next step, transcript path and recent turns. | — |
| `duo2 session new [--project <p>] [--prompt <text>] [--name <name>] [--remote-control [name]]` | Start a Claude session in a project (the current one by default). --name gives it a fixed name (claude -n), which survives restarts: a director's is director-<project> (DL-200). --remote-control makes it reachable from the Claude app, named <name> or its project and a short id, and keeps it on when the session resumes; a claude without the flag starts without it and the reply says so. | + New session, + New Claude Code session, New Session, console +, New Claude Session, New session pill, robot half, Start Claude here, Start Claude in Home, Start in |
| `duo2 session open <id>` | Show a session's terminal, resuming it if needed. | session row, console tab, Home tab, Resume, Open Session |
| `duo2 session close [id] [--force]` | End a session's process and close its tab (it stays listed and resumable). Refuses while Claude is working there, unless --force. | Close Tab, End Session, Close |
| `duo2 session park <id>… \| --background` | Park a session (several ids park each that can; the rest say why): end its Claude process, keep its tab, and resume it when the tab is shown (it picks up where it left off). Refuses, saying why, while Claude is working or waiting on the user, is running something in the background or has a subagent running, or the session is set to Keep Running; a tab on screen first gives its pane to the next tab. --background parks every idle tab that isn't on screen and says what it kept and why. | Park Session, Park Background Sessions, Park n Sessions, Park Sessions |
| `duo2 session keep-running <id> [on\|off]` | Keep a session running: it is never parked (by hand, in bulk or under memory pressure) and starts at launch instead of waiting to be shown. Turning it on wakes a parked tab. With no on/off it says whether the session is set. | Keep Running, pinned + |
| `duo2 session move <id>… --to <project> [--new]` | File one or several sessions in another project, or with --new in a new project of that name made in Home; it moves there on its next resume. The user confirms in Duo. Undo with `duo2 undo`. | Move to Project, New Project…, drag a session onto a tile |
| `duo2 session note <text>` | Tell the user what this session is doing (one line, shown in Duo). | — |
| `duo2 session next <text>` | Tell the user what this session needs next (one line). | — |
| `duo2 session task [id]` | The task(s) a session is attributed to (this session by default): each note's title, status and path. Duo's hooks tell Claude the same when the session starts, resumes, clears or compacts, and what changed on its next prompt (DL-116). | — |
| `duo2 session carry-on <id>` | Start a new session carrying on from an archived one. | — |
| `duo2 session fork <id>` | Carry a session on as a fork: a new session with the same history (the original is left alone). | Resume as a Fork |
| `duo2 session trust-folder <id>` | When a session's /fork said "Workspace not trusted": show Duo's sheet and wait for the user's answer. Yes sets only that folder's hasTrustDialogAccepted in Claude Code's file; it prints `trusted <path>` or `cancelled`. There is no --yes: Claude can ask, but can't trust a folder for itself (DL-229). | Trust This Folder…, Try Again |
| `duo2 session fork-again <id>` | After the folder is trusted: type the session's blocked /fork line again, only while Claude is at its prompt with nothing typed (DL-229). | Fork Again |
| `duo2 session link <session>` | A Markdown link to a session for a note or task: [title](duo2://session/<id>). Clicking it in Duo opens or resumes the session (DL-87). | Copy Link, Copy Markdown link |
| `duo2 session archive <id>…` | File sessions away (one or several; several undo with one `duo2 undo`): it leaves the lists and counts, keeps its transcript, stays searchable, and sits in its project's Archived fold. Not while it runs. Undo with `duo2 undo`. | Archive Session, Archive n Sessions |
| `duo2 session unarchive <id>…` | Bring archived sessions back into their projects' lists (several undo with one `duo2 undo`). | Unarchive Session, Archived fold, Unarchive n Sessions |
| `duo2 session delete <id>…` | Delete one or several sessions and their local logs for good (transcript, file history, environment; Duo's archived copy). The user confirms in Duo; several ids ask once, then the reply names any id skipped and why. A session running in one of Duo's terminals is ended first; one running outside Duo is refused. | Delete Session…, Delete n Sessions… |
| `duo2 session chat [id] on\|off\|toggle \| --default last\|chat\|terminal \| --home chat\|terminal\|last \| answer [id] <option\|level\|cancel> [--session-only] \| mode [id] [next\|manual\|accept-edits\|plan\|auto\|bypass] \| model [id] \| effort [id] \| why [id] \| why --log` | Chat mode (DL-118 to DL-120): show a Claude session as a readable chat over its real terminal, or as the terminal. Switching sends nothing to the session. --default sets the mode new sessions open in (last: the one used last). --home sets the mode new Home sessions open in: chat unless set (DL-142), terminal, or last to follow --default (Settings › General, Home opens in). answer presses a review card's option key (1, 2, 3 …, or cancel for Esc) only after re-reading the screen; the same dialog must still be up. On /model's and /effort's cards (DL-143) it takes a row's number or a level (low, medium, high, xhigh, max), moves Claude Code's own cursor there and presses Return, or s with --session-only. mode presses Claude Code's shift+tab, once (next) or until its footer shows the mode named; the cycle is the installed claude's own. model and effort do what the model chip and the effort chip do (DL-168): send /model or /effort into Claude's prompt, only when the screen shows Claude idle with an empty prompt, so the card docks; answer then takes its row or level as above. On Switch model? and Change effort level? (Claude Code's question after a pick on a session with history) answer takes the option's number, or cancel. why prints the fallback bar's Debug report (DL-234): the rule that fired, the reader's verdict and evidence, the screen rows it judged, the Claude Code version, and the session's recent chat-state changes; it can hold private screen text, and nothing is sent anywhere. why --log lists the recent automatic fallbacks from logs/chat-fallbacks.jsonl in Duo's support folder. With no id, the session on screen. | Home opens in, Terminal, Chat, Back to Chat, Debug, review card option, Cancel esc, Amend in Terminal…, Approve with Feedback in Terminal…, Manage in Terminal…, Chat about this, ‹ Back, mode chip, ⇧⇥ in the composer, picker card row, effort level, model chip, effort chip, Switch model? option, Set as Default, Confirm, This Session Only, Cancel |
| `duo2 idle` | Idle, resumable sessions, newest first, grouped by when (the map footer's list). | idle footer |
| `duo2 shell new` | Open a plain shell in the console (DL-8); typing `claude` in it makes it a session. | New Shell, New session pill, shell half |
| `duo2 tasks [--project <p>]` | Task notes (tasks/*.md in each project) with their status and how many sessions their `sessions:` frontmatter links (DL-93). --json adds "later" (the pane lists it under Later: nothing in it for 3 days) and "lastActivity", when the note last changed (DL-217). | — |
| `duo2 task make <session>… \| <group> [--title <t>]` | Make a Task: writes tasks/<slug>.md whose `sessions:` links the session (several sessions of one project make one task; or a group's sessions, and the group becomes the task) and opens it. Undo with `duo2 undo`. | Make a Task |
| `duo2 task new [title] [--project <p>] [--status <s>] [--no-open]` | + New task: a task note in tasks/ with no sessions yet, opened to write; use this, not a TASKS.md file. --no-open leaves the note closed (for making several); --status starts it at open, in-progress, waiting, review, done or dropped. Undo with `duo2 undo`. | + New task, New Task |
| `duo2 task session <task> [--project <p>]` | New Session in Task: starts a Claude session in the task's project with its link already in the note's `sessions:` list, and shows it when that project is open. Once Claude's prompt is up, Duo types `@tasks/<note>.md` into it and doesn't send it (DL-112): no turn is spent until someone adds a word and presses Return. Also the + on a task row's hover. | New Session in Task |
| `duo2 task status <task> <open\|in-progress\|waiting\|review\|done\|dropped> [--project <p>]` | Set a task's status: rewrites only `status:` (and `completed:` when done or dropped). Done and dropped tasks leave the lists. Undo with `duo2 undo`. | Set Status, Mark Complete |
| `duo2 task add <task> <session>…` | Add to Task: puts each session's link in the task note's `sessions:` list, touching nothing else in the note. Undo with `duo2 undo`. | Add to Task, Open Task Note, Add Session |
| `duo2 task rename <task> <new title> [--project <p>]` | Rename a task: its `title:` and `# ` heading change, and the note moves to tasks/<slug of the new title>.md (-2, -3 when taken). Renaming in the note (heading or `title:`) moves the file too, once typing pauses. Undo with `duo2 undo`. | Rename |
| `duo2 task archive <task> [--sessions\|--keep-sessions] [--project <p>]` | Archive a task: `archived: true` in its note; it leaves the lists and counts, stays searchable, and sits in its project's Archived fold. With --sessions its linked sessions are archived too (never a running one); --keep-sessions leaves them. With neither, Duo asks the user. Undo with `duo2 undo`. | Archive Task… |
| `duo2 task unarchive <task> [--project <p>]` | Bring an archived task back to the lists, with the sessions archived with it. Undo with `duo2 undo`. | Unarchive Task |
| `duo2 task delete <task> [--project <p>]` | Delete a task: the user picks in Duo whether its linked sessions are deleted too (never a running one). The note goes to the Trash (`duo2 undo` brings it back); deleted sessions can't be undone. | Delete Task… |
| `duo2 task move <task> <project> [--sessions\|--keep-sessions] [--project <p>]` | Move a task's note to another project's tasks/. With --sessions its sessions in this project move too; --keep-sessions leaves them. With neither and sessions to move, Duo asks the user. Undo with `duo2 undo`. | Move to Project |
| `duo2 task link <task> [--project <p>]` | A Markdown link to a task: [title](duo2://task/<id>). The id is written once into the note's `id:`, so the link survives renames and moves. Clicking it in Duo opens the note. | Copy Link |
| `duo2 task reveal <task> [--project <p>]` | Show a task's note in Finder. | Reveal in Finder |
| `duo2 task board [show\|hide\|toggle] [--project <p>]` | The task board (DL-148): a project's Sessions \| Tasks switch. Tasks shows the board over the session list and console, lanes by `status`, and a card's note in the right pane. With no argument, says which is showing and lists the board's lanes and cards. Drag between lanes is `duo2 task status`. | Sessions, Tasks, Board |
| `duo2 task column <add\|remove\|move\|keep> <name> [--after <column>] [--to <column>] [--left\|--right] [--project <p>]` | A board's columns (DL-150): each is a `status` value, listed in the project brief's `lanes:` (written the first time the default five change, then edited in place). add: the name's slug is the status (Blocked → blocked), at the end or --after a column. remove: Open and Done can't go; a column holding tasks moves them --to another (without --to, Duo asks the user). move --left\|--right. keep: an unlisted status found on tasks becomes a column. Undo with `duo2 undo`. | + Add Column, Add Column After…, Remove Column…, Move Left, Move Right, Keep as Column, Remove Column |
| `duo2 task reference <add\|remove> <task> <file\|folder\|url> [--title <t>] [--project <p>]` | A task's references (DL-150): its `references:` frontmatter, a list of quoted markdown links to files, folders (trailing /) and web links, relative to the note. Written only when one is added; nothing else in the note changes. With the note open in Duo, the change goes through the editor. Undo with `duo2 undo`. | Remove from Task, references field, file dropped on a card |
| `duo2 task base [show\|add\|update] [--project <p>]` | The Obsidian board (DL-20, DL-148): add writes tasks.base beside the project's brief, a Bases kanban view grouped by `status` with groupOrder pinned to the project's columns (sorted by due, then created) and a table view; Obsidian 1.14.4+ shows the same board, and a drag there writes `status`. Never written unless asked, never over a base that's there. update rewrites only its groupOrder lines when the columns change. show: where it is and whether it's out of date. Undo with `duo2 undo`. | Add Obsidian Board, Update Obsidian Board, Update |
| `duo2 groups [--project <p>]` | Groups and their sessions, with each group's most urgent state. | — |
| `duo2 group new <name> <session>…` | Group sessions of one project under a name. | — |
| `duo2 group add <group> <session>…` | Add sessions to a group. | — |
| `duo2 group remove <group> <session>…` | Take sessions out of a group (an empty group goes away). | — |
| `duo2 group rename <group> <new name>` | Rename a group. | — |
| `duo2 group delete <group>` | Ungroup: the group goes, its sessions stay. | — |
| `duo2 task issue <task> <issue\|--clear> [--project <p>]` | A task's issue link (DL-226): writes `issue:` with the full URL, quoted, by key (a task tracks one issue; the issue's state is read from GitHub, never copied into the note). <issue> is a URL, owner/repo#n or #n in the project's GitHub remote. --clear removes the link; nothing on GitHub changes. Through the editor when the note is open. Undo with `duo2 undo`. | Link Issue…, Change Issue…, Unlink Issue |

## Director

| Command | What it does | In the app |
|---|---|---|
| `duo2 director status [--project <p>]` | Who directs this project (and whether you're its director, or one it replaced), its workers and their tasks with each one's state, the rules to read (the Director sections: Home's HOME.md, then the project's PROJECT.md), and what this Claude client can do: messaging, background sessions, Remote Control, hooks, Monitor. Works with Duo closed, from Claude's own files (DL-231). | — |
| `duo2 director start <task> \| --title <t> --request <the user's words> [--done-when <text>] [--suggest \| --no-worker \| --worker <session id> [--adopt]] [--adopt] [--in-duo] [--background] [--take-over] [--project <p>]` | Start a worker on a task this director directs (DL-194, DL-201): writes directed_by:, ## Request and ## Progress, then starts the worker in the background (`claude --bg`, with Remote Control) by default: it prints the command to run, and the worker is linked by its name when it starts. --in-duo starts it in Duo instead; so does a client without background sessions. Workers are reached by SendMessage, not by Duo (DL-257). --worker links an existing session; --background asks for the default explicitly. --suggest files it as suggested with no worker; --no-worker makes it a task the director does itself (organising work, DL-208). Refuses a task another director directs, and a project another director runs (--take-over replaces it; alone, it records a resumed director). A task or session of the user's needs --adopt: Duo then asks the user, and goes ahead only if they allow it. | — |
| `duo2 director send <task> <message> [--handed-back] \| --director <project> <message>` | Reach a task's worker (or, from Home, a project's director) the best way this client has, and log which (DL-199, DL-257): a live worker gets your own SendMessage (this prints the call; Duo can't make it for you, and it is held if your permission class and the worker's differ); a stopped background worker is resumed with the message (`claude --bg --resume`, no other flags); a stopped worker in Duo is reopened with it; else the user passes it on. Nothing is typed into a terminal. Every send goes into the task's ## Progress. A worker the user typed in is paused (DL-200): --handed-back makes Duo ask the user to hand it back. With Duo closed, the rungs that need it are left out, and --handed-back records the user's word in your own session (DL-231). | — |
| `duo2 director retire [--project <p>]` | Stand this director down: .duo/director.json moves it to the retired list, and if it wakes later it's told to stop. Its workers stay on their tasks until a new director takes over. Works with Duo closed. | — |
| `duo2 director guide` | Print the duo-director skill, for a Claude client where personal skills are blocked. | — |
| `duo2 director watch [--project <p>] [--every <seconds>]` | One line per change to this director's workers (finished, needs you, working, stopped) or their task notes, until stopped: run it under Monitor to be woken (DL-199). It watches without Duo too (DL-231). | — |

## Files

| Command | What it does | In the app |
|---|---|---|
| `duo2 files [folder] [--project <p>] [--hidden]` | The project's files and folders, three levels deep; --hidden includes dotfiles. | — |
| `duo2 files browse [up \| back \| <folder>] [--project <p>]` | Go up from the project's folder in the Files block (DL-106): `up` shows the parent folder, again for the next; `back` returns to the project's folder; a folder path shows that folder. Read-only: files there open as tabs, and can't be moved or trashed from the tree. With none, says what the tree shows. | Show Parent Folder, Back to Project Folder, the Files path row |
| `duo2 file new [--in <folder>] [--name <name>]` | Create a Markdown file and open it. | New Markdown File, right pane + |
| `duo2 file new-folder [--in <folder>] [--name <name>]` | Create a folder. | New Folder |
| `duo2 file template <template> [--in <folder>]` | Create a file from a template (the project's templates/, then Home's). | New from Template |
| `duo2 file templates` | The templates available here. | — |
| `duo2 file rename <path> <new name>` | Rename a file or folder; open tabs follow. | Rename |
| `duo2 file duplicate <path>` | Copy a file or folder next to itself. | Duplicate |
| `duo2 file move <path>… <folder> [--replace \| --keep-both]` | Move files or folders into a folder; open tabs follow. A path may be anywhere on the Mac (the same move as dropping it from Finder on the tree); from another volume it's copied, as Finder does. A taken name fails unless --replace (the one there goes to the Trash) or --keep-both ("name 2"). A folder can't go into itself. Undo with `duo2 undo`. | Move To…, files dropped on the file tree |
| `duo2 file trash <path>` | Move to the Trash (never deleted outright). | Move to Trash |
| `duo2 file reveal <path>` | Show in Finder. | Reveal in Finder |
| `duo2 file open-with <path> [--app <name>]` | Open in another app (the default app if none named). | Open With, Other…, Open Original |
| `duo2 file convert <docx> [--as <name.md>] [--replace] [--anyway] [--yes]` | Make a Markdown copy of a Word document beside it (<name>.md, pictures in <name>-images); the .docx isn't changed (DL-123). Headings, lists and layout tables are inferred and cleaned; tracked changes are kept as signed CriticMarkup suggestions and comments as signed threads, replies and resolved ones included (DL-236 12A). Prints what it inferred and what didn't come over. A taken name fails unless --as or --replace (the one there goes to the Trash); --anyway converts a document with no text. The copy opens in a tab of its own beside the Word viewer. The bar's Convert to Markdown… asks first, saying what won't come over; this verb never asks, and --yes (accepted for scripts) says so. Undo with `duo2 undo`. | Convert to Markdown, Convert to Markdown…, Convert, Convert Anyway |
| `duo2 file path <path> [--relative \| --link] [--copy]` | Print a file's path, relative path or Markdown link; --copy puts it on the clipboard. | Copy Path, Copy Relative Path, Copy as Link |

## GitHub

| Command | What it does | In the app |
|---|---|---|
| `duo2 repo status [--project <name>] [--copy] [--json]` | Where the project's repository stands, as the Files block shows it: branch, base, ahead and behind, changed files, the pull request, your access and whether the default branch is protected, and the line's one fact. Local state, plus what GitHub said at the last quiet fetch. --copy copies the branch name. | Copy Branch Name |
| `duo2 repo check [--project <name> \| <owner/repo>]` | Whether the GitHub CLI is here and signed in (as whom), and what you can do in a repository: push, or read only (then pushes go to your fork), and whether its default branch is protected. Reads only. | Try Again |
| `duo2 repo latest [--project <name>]` | Get Latest: bring in new commits on this branch from GitHub (merge, never rebase; your uncommitted files ride along). Stops at a conflict and says so. | Get Latest, Get Latest and Push |
| `duo2 repo update [--project <name>] [--from <branch>]` | Bring In Changes from the default branch (or --from), as GitHub's Update branch does: a merge, never a rebase. | Bring In Changes from |
| `duo2 repo put-back [--project <name>]` | Put Back: undo a Get Latest that stopped at a conflict (git merge --abort). Your own changes are as they were. | Put Back |
| `duo2 repo push [--project <name>] [--message <m>] [--files <f,…>] [--fork] --yes` | Commit the changed files (all, or --files) with the message, then push the branch (never forced). Publishes under the user's name, so without --yes it opens Duo's Push sheet for the user to confirm. --fork pushes to the user's fork (read-only access). | Push…, Push, Push to GitHub…, Fork and Push |
| `duo2 repo pr [--project <name>] [--message <m>] [--title <t>] [--body <b>] [--draft] [--browser] [--fork] --yes` | Push and open a pull request into the default branch: with the GitHub CLI, or GitHub's own page filled in (--browser, or no CLI). Without --yes it opens Duo's Push sheet for the user to confirm. | Push and Open PR, Fork, Push and Open PR, Push and Open in Browser |
| `duo2 repo draft [--message <m>] [--title <t>] [--body <b>]` | Fill in the open Push sheet's message, pull request title and description: how Claude answers Ask Claude to Write These. Doesn't push. | Ask Claude to Write These |
| `duo2 repo move-to-branch <new branch> [--project <name>] --yes` | Move commits made on a protected branch to a new branch; the old one goes back to GitHub's only once the new one holds every commit. Then push it with `duo2 repo pr`. | Move to a Branch…, Move to a Branch and Push |
| `duo2 repo signin` | Sign in to GitHub: a shell tab running the GitHub CLI's browser sign-in (`gh auth login --web`, then `gh auth setup-git`). Duo never sees or keeps a token. Without the CLI, a shell tab with `brew install gh` typed. | Sign In…, Sign In in a Shell…, Install in a Shell…, Switch Account… |
| `duo2 issue show [<task\|issue>] [--project <p>] [--refresh]` | The GitHub issue a task tracks (its `issue:` link, DL-226) and its state now: open or closed, labels, and why it can't be read without gh or access. <issue> is a URL, owner/repo#n or #n (the project's GitHub remote). With no argument, every task in the project that tracks one. Reads only. | issue chip, issue row, Copy Issue Link |
| `duo2 issue open <task\|issue> [--project <p>]` | Open the issue on GitHub in the browser. | Open Issue on GitHub |
| `duo2 issue close <task\|issue> [--project <p>] --yes` | Close the issue on GitHub (`gh issue close`): the one change Duo makes to an issue besides reopening it. Needs --yes. Undo with `duo2 undo` reopens it. | Close Issue, Close #n too, Close too |
| `duo2 issue reopen <task\|issue> [--project <p>] --yes` | Reopen the issue on GitHub (`gh issue reopen`). Needs --yes. | Reopen Issue |
| `duo2 issue new --from-task <task> [--project <p>] --yes` | New Issue from Task: files the task as an issue in the project's GitHub repository, titled after it with its note's text as the body, and links it (`issue:`). Needs --yes (it publishes under the user's name); without it the user is asked in Duo. Undo with `duo2 undo` unlinks it; the issue stays on GitHub. | New Issue from Task… |
| `duo2 repo open [--project <name>] [--pr]` | Open the repository (its branch) or the branch's pull request on GitHub. | Open on GitHub, Open Pull Request #, Open PR, Open GitHub |

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
| `duo2 doc format bold\|italic\|strikethrough\|code\|link\|heading1\|heading2\|heading3\|task\|properties` | Format the selection (bold, italic, strikethrough, code, a link waiting for its address), make its lines headings or tasks (again takes it off), or start the properties block. | Bold, Italic, Strikethrough, Code, Link…, Heading 1, Heading 2, Heading 3, Task, Add Properties |
| `duo2 doc table insert\|row-above\|row-below\|column-before\|column-after\|delete-row\|delete-column\|align-left\|align-center\|align-right\|next\|previous` | Edit the table at the caret as Markdown, its columns kept lined up: insert a 3 × 2 table, add or delete a row or column, align a column, or move to the next or previous cell (the last cell's next adds a row). | Insert Table, Add Row Above, Add Row Below, Add Column Before, Add Column After, Delete Row, Delete Column, Left, Center, Right, + Row, + Column, Align, Delete |
| `duo2 doc find <text>` | Find text in the showing document and select the next match. | Find |
| `duo2 doc mode [source\|preview\|toggle]` | Show the document as its text (source) or rendered (preview), as View › Source Mode does; remembered per document. With nothing, says which it shows now (DL-167). | Source Mode |
| `duo2 doc prop list \| get <name> \| set <name> <value> \| remove <name> \| type <name> <text\|list\|number\|checkbox\|date\|datetime\|link>` | The showing document's properties (frontmatter): read them, or change one line through the editor, highlighted as Claude's (DB-16). Lists: `set tags "[a, b]"`. | Add a property, property type menu, Pick a date, property checkbox |
| `duo2 doc markup [all\|simple\|none\|original] [--comments on\|off] [--show-resolved on\|off] [--person <name>\|everyone]` | On a Markdown document: the same modes for its suggestions and comments, with --show-closed on\|off for closed threads (DL-237). The Word document showing: which markup its viewer draws, and change it, as the Markup menu does (DL-162). All Markup draws every change in its person's colour with the comments; simple accepts the changes and marks the margin where one was; none accepts them with no marks; original shows the text before them. --person shows only that person's marks. Kept per document while Duo runs. With nothing, says what it shows now and who is in the document. | Markup, All Markup, Simple Markup, No Markup, Original, Show Comments, Show Resolved Comments, Show Closed Comments |
| `duo2 doc review [on\|off\|next\|previous]` | The Markdown document's Suggest Edits switch (DL-237): on, every change anyone makes becomes a signed suggestion; kept in the file as `suggest-edits: true` in its frontmatter, written only while on. With nothing, says which it is. next and previous select the next or previous suggestion or comment in the document (the review bar's ‹ ›). Edit › Suggest Edits does the same as on and off. | Suggest Edits, Next Change, Previous Change |
| `duo2 doc outline <file.docx> [--json]` | A Word document's paragraphs, read from the file (no viewer needed): each with its w14:paraId (the id the viewer draws it under), style and heading level, its text with the tracked changes accepted, its tracked changes (kind, author, date, text) and the comments that end in it (thread, resolved). Then every comment thread. A picked paragraph's Send to Claude names the same ids. | — |
| `duo2 doc layout <file.docx> [--json]` | A Word document's geometry, read from the file (no viewer, no renderer): each section's page size, orientation and margins, so its text width; each table's declared width and column widths against the room it has (the text width, or its cell's); each picture's size; and a warning for anything wider than its room, a percentage table width, or a width that disagrees with its columns. Sizes in points. No page numbers. Only a document open in a Duo tab or inside the session's project folder (C-115). | — |
| `duo2 doc screenshot [<file>] [--all] [--width <px>]` | Save PNGs of a document as Duo's viewer draws it and print their paths: the Word document named (or showing) at the pane's width, 460 px unless --width says otherwise (320–1600), tables at the document's own column widths. Without --all, the top of it (up to 1600 px); with --all, the whole document in 1600 px pieces, numbered. A Word document needn't be showing: Duo draws it out of sight, and the user's view doesn't change. A Markdown preview or a slide deck is captured only while it is showing. The PNGs go in .duo/screenshots/ in the session's folder. Only a document open in a Duo tab or inside the session's project folder (C-115). | — |
| `duo2 doc pick [<paragraph id> \| c:<comment id>]` | Start Select Text in the Word document showing, for the user to click a paragraph or a comment, or select the paragraph (its w14:paraId from `doc outline`) or comment (`c:<id>`) named. | Select Text |
| `duo2 doc element [<paragraph id> \| c:<comment id>]` | Describe a paragraph or comment of the Word document showing (the picked one by default) as Send to Claude would send it: where it is, its text with changes accepted, its tracked changes and comments. | — |
| `duo2 doc comments [--resolved \| --closed]` | The comments of the document showing. A Word document: from what its viewer drew, with author, date, text, replies and whether each is resolved (--resolved: only those). A Markdown document: its threads, read from the text as the editor has it, with author, date, text and replies; closed threads are left out unless --closed (DL-237). | — |
| `duo2 doc insert <text> [--line <n>]` | Insert text into the showing document through the editor (highlighted as added by Claude), at a line or the caret. | — |
| `duo2 doc replace <find> <replacement>` | Replace text in the showing document through the editor (highlighted as added by Claude). | — |
| `duo2 doc revert [--all \| --line <n>]` | Put back what Claude changed in the open document: the change at the caret or a line, or all of them since the user's last edit (ENH-4). | Revert This Change, Revert All of Claude's Changes, Revert Claude's Change |
| `duo2 doc edit --stdin` | Apply an Edit-tool-shaped change ({file_path, old_string, new_string, replace_all} or {file_path, edits} or {file_path, content}, as JSON on stdin) to a document open in Duo, through the editor, highlighted. | — |
| `duo2 doc resolve mine\|theirs` | End a conflict in the showing document: keep the user's text (saved over the file) or take the file's. The other version stays in history. Only when the user asks. | Keep Mine, Use Theirs |
| `duo2 doc history [path]` | Versions Duo kept of a document (as opened, both sides of conflicts, before removal), newest last, with where each is stored. | — |

## Review in Markdown

| Command | What it does | In the app |
|---|---|---|
| `duo2 comment add <file> --at <line\|text> [--as <name>] <text>` | Comment on a line (its number) or on a text that appears once: the text becomes a highlight and the signed comment follows it. A comment that names @claude is addressed to a session (`duo2 comment send`). | Add Comment |
| `duo2 comment list <file> [--closed \| --unsent]` | The file's comment threads: id, who and when, the text it is on, the comment and its replies. Closed threads are left out unless --closed (only those); --unsent lists the open ones that name @claude and have no reply. | — |
| `duo2 comment reply <id> <text> [--file <file>] [--suggest] [--as <name>]` | Reply in a thread (or to a suggestion) with the next number, `#c1.2`; a closed thread reopens. --suggest instead proposes the reply text as a replacement of the text the thread is on. Never rewrites anyone's comment. Without --file, the document showing. | — |
| `duo2 comment send <id \| --all> [--file <file>] [--to <session> \| --new]` | Send a comment that names @claude to a session, quoted as data, when the person says to (DL-236 10): the turn is pasted and Returned through the idle-and-empty-prompt guard of `director send`, or waits (Queued) until the session is ready. Without --to, the thread's session, the document's last choice, the last to edit it through Duo, then the one on screen. --all sends every @claude comment not yet sent or answered. Never sent from the file on its own. | — |
| `duo2 comment close <id> [--file <file>] [--as <name>]` | Close and Keep: add a closing line `{>>@name date #c1.2 closed<<}` after the thread's last comment; the highlight and comments stay (Q-262). | Close and Keep |
| `duo2 comment delete <id> [--file <file>]` | Delete the thread: its highlight markers and every comment go, the text stays. | — |
| `duo2 comment reopen <id> [--file <file>]` | Reopen a closed thread: its closing line goes. | Reopen |
| `duo2 comment status <id> [--file <file>]` | One thread: open or closed, who is in it, whether it names @claude, whether Claude has replied, and where its delivery stands: not sent, queued, sent, replying, replied or not delivered, with the session. | — |
| `duo2 suggestion list <file>` | The file's suggestions: id, kind (insertion, deletion, substitution), who and when, the text. | — |
| `duo2 suggestion accept <id \| --all> [--file <file>] [--person <name>]` | Accept a suggestion: the change is made and its mark goes (--all: every one, or one person's). The person's call: only when they ask. | Accept, Accept All, Accept All from |
| `duo2 suggestion reject <id \| --all> [--file <file>] [--person <name>]` | Reject a suggestion: the text stays as it was and its mark goes. The person's call: only when they ask. | Reject, Reject All, Reject All from |

## HTML pages

| Command | What it does | In the app |
|---|---|---|
| `duo2 browser open [url]` | A browser tab in the right pane (⌥⌘T). Sites not on the allow list show Allow or Open in Browser instead of loading (DL-3). | New Browser Tab, Open Location…, Open in Browser, Copy Address |
| `duo2 browser allow <host>` | Ask the user to add a site to the allow list, so its pages open in Duo's browser tabs (and its subdomains). The user answers on a Duo sheet. | — |
| `duo2 browser sites` | The allow list: sites Duo opens in its own browser tabs; everything else opens in the system browser (DL-3). | Edit… |
| `duo2 browser tabs` | Browser tabs open in Duo: id, project, title, address. | — |
| `duo2 browser read [selector] [--tab <id>]` | The page's text (or one element's), with its title and address (LR-45). Allowed sites only. | — |
| `duo2 browser click <selector> [--synthetic] [--tab <id>]` | Click the element a CSS selector names, scrolled into view: real mouse events at its centre, which apps like Google Docs need (DL-124). --synthetic sends element.click() instead (also used when the tab isn't on screen). | — |
| `duo2 browser fill <selector> <text…> [--tab <id>]` | Type into an input, text area or editable element, as a person would (input and change events). | — |
| `duo2 browser wait <selector> [--timeout <s>] [--tab <id>]` | Wait for an element to appear (default 10 s). | — |
| `duo2 browser screenshot [--full-page] [--tab <id>]` | Save a picture of the visible page as a PNG and print its path. --full-page takes the whole page top to bottom, scrolling and joining the pictures (up to 20000 px tall, then it says it stopped); the page is left where it was. | — |
| `duo2 browser scroll <top\|bottom\|up\|down\|<pixels>\|<selector>> [--tab <id>]` | Scroll the page: to the top or bottom, up or down by a screen, by a number of pixels (negative goes up), or to the element a selector names. Says where the page is now, out of how tall. | — |
| `duo2 browser go <url> [--tab <id>]` | Go to an address in the tab; a site not on the allow list isn't loaded. | — |
| `duo2 browser back [--tab <id>]` | Back in the tab's history. | Back |
| `duo2 browser forward [--tab <id>]` | Forward in the tab's history. | Forward |
| `duo2 browser close [--tab <id>]` | Close the browser tab (a popup's tab hands back to the page that opened it). | — |
| `duo2 browser zoom [<percent> \| in \| out \| reset] [--tab <id>]` | The page's zoom, or set it: remembered for the site (DL-124). ⌘+ ⌘- ⌘0 while the tab has the keyboard. | Zoom In, Zoom Out, Actual Size, zoom percentage in the bar |
| `duo2 browser print [--pdf <path>] [--tab <id>]` | Print the page: the print panel on the window for the user (⌘P, or the page's own print), or --pdf saves it as a PDF without one (DL-124). | Print… |
| `duo2 browser upload <selector> <file…> [--tab <id>]` | Choose files for a file input: the files answer its file chooser, then it's clicked as a person would (DL-124). The user's own click opens the open panel. | — |
| `duo2 browser downloads [--open [<n>] \| --cancel]` | Downloads from browser tabs since Duo started, numbered, to ~/Downloads with Finder's names for clashes (DL-124). --open opens one (the newest by default) with its app, as the tab's notice's Open does. --cancel stops the one running and takes its partial file away, as the notice's Cancel does (DL-132). | Open |
| `duo2 html reload` | Reload the HTML page showing (it also reloads when its files change). | Reload Page |
| `duo2 html pick [selector]` | Start the element picker for the user, or select the element a CSS selector names. | Select Element, Pick Another |
| `duo2 html stop` | Close the element picker. | Cancel picking |
| `duo2 html element [selector]` | Describe an element (the picked one by default): selector, text, attributes, styles, box, HTML. | — |
| `duo2 html selection` | The text and images selected in the HTML page. | — |

## PowerPoint decks

| Command | What it does | In the app |
|---|---|---|
| `duo2 slide` | The deck showing and the slide on screen, with that slide's shapes and text. | — |
| `duo2 slide go <n> \| next \| previous` | Show a slide of the deck in the right pane (also ‹ ›, Page Up and Page Down). | Previous Slide, Next Slide |
| `duo2 slide shapes [<file.pptx>] [<n>]` | A slide's shapes from the file: OOXML id, name, type, groups, text, box, tables, chart data, notes. The deck showing and its slide by default; a file without a slide gives every slide. | — |
| `duo2 slide notes [<file.pptx>] [<n>]` | A slide's speaker notes (the slide on screen by default). | — |
| `duo2 slide pick [<slide>/<shape id>]` | Start the shape picker for the user, or select the shape a slide and id name. | Select Shape, Pick Another |
| `duo2 slide element [<slide>/<shape id>]` | Describe a shape (the picked one by default): slide, id, name, groups, text, box, and a screenshot. | — |

## Send to Claude

| Command | What it does | In the app |
|---|---|---|
| `duo2 send file <path> [--to <id> \| --new]` | Put an @-reference to a file or folder into a session's prompt. | Send to Claude, Send To |
| `duo2 send session <id> [--to <id> \| --new]` | Put a session's reference into a session's prompt. | Send to Claude |
| `duo2 send project <project> [--to <id> \| --new]` | Put a project's reference into a session's prompt. | Send to Claude |
| `duo2 send selection [--to <id> \| --new]` | Put the user's selection (document or HTML page) into a session's prompt. | Send Selection to Claude, Send Selection To, Send Image to Claude, Send Image To |
| `duo2 send element [--to <id> \| --new]` | Put the picked HTML element, or the shape picked on a slide, into a session's prompt. | Send to Claude, Send To, New Session |
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
| `duo2 doctor` | How this terminal finds Duo, whether it can reach it, what Duo installed, and whether Claude Code mods work here. | — |
| `duo2 install [--director-name director\|duo-director]` | Install or refresh what lets Claude sessions anywhere use duo2: a short block in ~/.claude/CLAUDE.md, a duo2 skill, a director skill, ~/.local/bin/duo2 (DL-74). The director skill is named `director`; where a project has a skill of that name, a personal one would hide it, so Duo asks first and until you say yes installs it as `duo-director`. --director-name answers that: `director` takes the name, `duo-director` keeps the project's skill (DL-222). | Install, Install…, Use director, Keep duo-director |
| `duo2 uninstall` | Remove exactly what `duo2 install` added (anything you edited stays). | Remove… |
| `duo2 settings [claude-path <path\|auto> \| notify on\|off \| dock-badge on\|off \| appearance system\|light\|dark \| explainers reset \| macos]` | Duo's settings (S3-1): with no arguments, all of them, and what macOS allows; otherwise set one. The `claude` Duo runs, notifications when a session needs the user, the Dock badge; `appearance` (Match System, Light or Dark, DL-224); `explainers reset` shows the explanations the user dismissed again (Settings › General); `macos` opens System Settings › Notifications › Duo. | Choose…, Use Found One, Open Notification Settings…, Show dismissed explanations again, Appearance |
| `duo2 walk setup <test id>` | Put Duo in the state an acceptance-walk test starts from (the walk page's Set up test button, or `duo2://walk-setup?id=…`). Steps come from ~/DuoAcceptance/walk-setups.json, never from the caller. | Set up test |
| `duo2 compose <file>` | Claude Code's external editor in Duo's sessions (Ctrl+G; chat mode's composer, F-104, F-112): hands Claude the composer's text when chat mode asked for it, and otherwise opens your own editor ($VISUAL or $EDITOR as they were). Not for running by hand. | — |
| `duo2 hook pre-edit \| context` | Used by Duo's sessions. `pre-edit` (PreToolUse): Claude's Edit, MultiEdit and Write on a document open in Duo go through the editor instead of the file (DL-78). `context` (SessionStart, UserPromptSubmit): tells Claude the task(s) its session is attributed to, and on a prompt what changed since (DL-116). | — |
| `duo2 legacy [disable --yes \| restore <backup>]` | Find legacy Duo's instructions in ~/.claude; disable them (backed up first) or restore them. | Disable…, Restore |

## In the app only

| Item | Why it has no verb |
|---|---|
| @ menu in a margin comment | input help while typing a comment (DL-251): it inserts the text `@claude`, and `duo2 comment add`/`reply` take that text as typed |
| About Duo | the standard macOS About panel, whose credits list the third-party notices (DL-176); system UI for a person at the screen |
| Add to .gitignore | a one-time question to the user (DL-50) |
| Align Column | a submenu, not an action |
| Anyone | the task board's owner filter: view state; `duo2 task board` lists every card |
| Ask Claude to Combine | drafts the conflict's instruction into the project's Claude session, unsent (DL-149 board 11) |
| Ask Claude to Remove It | drafts an instruction about the refused secret into the project's Claude session, unsent (DL-149 board 10) |
| Cancel | a step inside another action's dialog or picker |
| Close Window | window management |
| Enter Full Screen | window management |
| Exit Full Screen | window management |
| Explain Tasks | Help › Explain Tasks shows an explanation to a person at the screen (DL-172); `duo2 task new` is the action it explains |
| Format | a menu, not an action |
| Go | a menu, not an action |
| Heading | a submenu, not an action |
| Install Now | on the update question: hands to Sparkle's own window, which installs only once the user agrees there (and gives an administrator password where one is needed); `duo2 update` says whether one is (DL-114) |
| Later | the user's answer to the update question; it remembers the version so the launch and scheduled checks don't ask again (DL-114) |
| Look Again | re-reads what Duo already refreshes every 2 s; the CLI always reads fresh state |
| Me | the task board's owner filter: view state; `duo2 task board` lists every card |
| No other sessions in | a disabled hint on + Add |
| No templates yet: add .md files to a templates folder | a disabled hint |
| Not Now | the user's answer to the install question; `duo2 install` and `duo2 uninstall` change it later |
| OK | dismisses a notice |
| Open Settings… | not built: Settings waits on its design (DB-10) |
| Paste or drop a picture in the editor | a gesture, not a menu item: the picture is saved beside the document and linked (LR-39); `duo2 doc insert` adds the same `![](name)` text, and `duo2 file move` puts a picture beside a note |
| Project | a menu, not an action |
| Report an Issue… | opens GitHub's new-issue form, filled in, for the user to edit and submit |
| Resolve… | drafts the conflict's instruction into the project's Claude session, unsent (DL-149 board 11); the user presses Return. Claude is already the one resolving |
| Resume a session | the debug gallery only (DL-59 removed it from the app) |
| Save to Recreate | writes the user's own text back after the file was removed on disk; Claude can do the same with `duo2 doc edit` (content) once the user asks |
| Session | a menu, not an action |
| Show Details | dismisses a failure question whose details are already shown |
| Show in Finder | reveals a file or folder in Finder (Settings, editor notices, launch sheets) |
| Show the File | opens the conflicted file, as `duo2 doc open` does |
| Table | a submenu, not an action |
| Toggle Right Pane | not built yet |
| What’s New in This Version | opens this version's release notes on GitHub; `duo2 status` names the version |
| confirmation sheet | the user's own consent; Claude can't confirm for them |
| files dropped on a terminal | types the dropped paths at the cursor, as Terminal.app does (DL-117); a session already has the paths, and `duo2 send` types text into a Claude session |
