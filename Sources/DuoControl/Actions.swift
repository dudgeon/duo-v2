import Foundation

// The action registry (DL-71, DL-72): everything a person can do in Duo, defined once. The CLI's
// verbs, `duo2 help`, the generated reference (`docs/cli/duo2.md`), the primer Duo gives each
// session, and the parity check all come from this table. Views name the action they perform
// (`ActionButton(.fileRename)`, `.onActivate(.sessionOpen)`), and `DuoChecks` fails when a button,
// menu item or click in the app isn't tied to an action here or listed in `Parity.uiOnly`.

public enum ActionFamily: String, CaseIterable, Sendable {
    case app, view, projects, sessions, files, docs, html, slides, send, search, setup

    public var title: String {
        switch self {
        case .app: "Duo"
        case .view: "What's on screen"
        case .projects: "Projects"
        case .sessions: "Sessions"
        case .files: "Files"
        case .docs: "Documents"
        case .html: "HTML pages"
        case .slides: "PowerPoint decks"
        case .send: "Send to Claude"
        case .search: "Search"
        case .setup: "Setup"
        }
    }
}

/// Every action, by its CLI verb.
public enum ActionID: String, CaseIterable, Sendable {
    // Duo
    case update
    case compose
    case ping, status, needsYou = "needs-you", undo, help, doctor, legacy, install, uninstall, hook, walkSetup = "walk setup", settings, updateProbe = "update probe", hangs
    // What's on screen
    case goAll = "go all", goHome = "go home", open, peek, peekJump = "peek jump"
    case viewSidebar = "view sidebar", viewRight = "view right", viewTab = "view tab", viewGroup = "view group", viewSelect = "view select"
    case viewSort = "view sort", viewFilter = "view filter", viewHidden = "view hidden", viewFolder = "view folder", viewHome = "view home"
    // Projects
    case projects, projectShow = "project show", projectMake = "project make", projectMerge = "project merge"
    case projectArchive = "project archive", projectUnarchive = "project unarchive"
    case homeSet = "home set", projectMoveIntoHome = "project move-into-home", projectNew = "project new"
    case projectReconnect = "project reconnect", projectForget = "project forget"
    case inventory, evidence, migrations, migratePlan = "migrate plan", migrateApply = "migrate apply", migrateUndo = "migrate undo"
    // Sessions
    case sessions, sessionShow = "session show", sessionNew = "session new", sessionOpen = "session open"
    case sessionClose = "session close", sessionMove = "session move"
    case sessionNote = "session note", sessionNext = "session next", sessionCarryOn = "session carry-on"
    case sessionLink = "session link", sessionTask = "session task", sessionChat = "session chat"
    case shellNew = "shell new", sessionFork = "session fork", idle, sessionDelete = "session delete", sessionArchive = "session archive", sessionUnarchive = "session unarchive"
    case tasks, taskMake = "task make", taskAdd = "task add", taskNew = "task new", taskSession = "task session", taskStatus = "task status"
    case taskRename = "task rename", taskArchive = "task archive", taskUnarchive = "task unarchive", taskDelete = "task delete"
    case taskMove = "task move", taskLink = "task link", taskReveal = "task reveal"
    case groups, groupNew = "group new", groupAdd = "group add", groupRemove = "group remove", groupRename = "group rename", groupDelete = "group delete"
    // Files
    case files, fileNew = "file new", fileNewFolder = "file new-folder", fileTemplate = "file template", fileTemplates = "file templates"
    case fileRename = "file rename", fileDuplicate = "file duplicate", fileMove = "file move", fileTrash = "file trash"
    case fileReveal = "file reveal", fileOpenWith = "file open-with", filePath = "file path", fileConvert = "file convert"
    // Documents
    case docOpen = "doc open", docClose = "doc close", docTabs = "doc tabs", docStatus = "doc status", docRead = "doc read"
    case docSelection = "doc selection", docSelect = "doc select", docSave = "doc save", docFormat = "doc format", docTable = "doc table", docFind = "doc find"
    case docProp = "doc prop"
    case docInsert = "doc insert", docReplace = "doc replace", docEdit = "doc edit", docResolve = "doc resolve", docHistory = "doc history", docRevert = "doc revert"
    // HTML pages
    case browserOpen = "browser open", browserAllow = "browser allow", browserSites = "browser sites"
    case browserTabs = "browser tabs", browserRead = "browser read", browserClick = "browser click", browserFill = "browser fill"
    case browserWait = "browser wait", browserScreenshot = "browser screenshot", browserGo = "browser go", browserBack = "browser back"
    case browserForward = "browser forward", browserClose = "browser close"
    case browserZoom = "browser zoom", browserPrint = "browser print", browserUpload = "browser upload", browserDownloads = "browser downloads"
    case htmlReload = "html reload", htmlPick = "html pick", htmlStop = "html stop", htmlElement = "html element", htmlSelection = "html selection"
    // PowerPoint decks
    case slide, slideGo = "slide go", slideShapes = "slide shapes", slideNotes = "slide notes", slidePick = "slide pick", slideElement = "slide element"
    // Send to Claude
    case sendFile = "send file", sendSession = "send session", sendProject = "send project", sendSelection = "send selection"
    case sendElement = "send element", sendText = "send text", selection
    // Search
    case search, searchStatus = "search-status", searchRebuild = "search-rebuild"
}

public struct DuoAction: Sendable {
    public var id: ActionID
    public var family: ActionFamily
    /// Arguments after the verb, in usage notation.
    public var args: String
    public var summary: String
    /// Where a person does this in the app: the labels the parity check matches. Empty for
    /// verbs that only Claude needs (reading, narrating).
    public var ui: [String]
    /// Runs without the app (otherwise the CLI asks the app).
    public var local: Bool
    /// In the primer every session gets (keep it short).
    public var everyday: Bool
    /// Seconds the CLI waits: long for actions the person confirms in a sheet.
    public var timeout: Int

    public var verb: String { id.rawValue }
    public var usage: String { "duo2 \(verb)" + (args.isEmpty ? "" : " \(args)") }

    init(_ id: ActionID, _ family: ActionFamily, _ args: String, _ summary: String, ui: [String] = [], local: Bool = false,
         everyday: Bool = false, timeout: Int = 15) {
        self.id = id; self.family = family; self.args = args; self.summary = summary; self.ui = ui; self.local = local
        self.everyday = everyday; self.timeout = timeout
    }
}

extension ActionID {
    public var action: DuoAction { DuoAction.byID[self]! }
    /// The label a button or menu item shows by default.
    public var title: String { action.ui.first ?? rawValue }
}

extension DuoAction {
    public static let all: [DuoAction] = [
        // Duo
        .init(.ping, .app, "", "Check that Duo is running and reachable."),
        .init(.update, .app, "[--open]", "Whether a newer Duo is on GitHub, its releases page, and whether installing it in place needs an administrator password (Duo › Check for Updates…, DL-114). --open opens the releases page, as the question's Open Releases Page does, to download the DMG and install it by hand.",
              ui: ["Check for Updates…", "Open Releases Page"], timeout: 30),
        .init(.updateProbe, .app, "", "Whether in-app updates can work on this Mac, without Duo running: the update feed and the DMG reachable from here, and Duo installed where it can be replaced.", local: true),
        .init(.hangs, .app, "[--since <hours>] [--stacks] [--clear]", "Times Duo froze: each stall of its main thread of 250 ms or more (2 s shows a beach ball), when, how long and what was on screen; --stacks adds where Duo was stuck, for stalls of half a second or more. Kept on this Mac only (Duo/logs/hangs.jsonl, DL-139). --clear empties it.", local: true),
        .init(.status, .app, "", "What Duo is showing: the view, the open project, session and document, and counts.", everyday: true),
        .init(.needsYou, .app, "", "Sessions waiting for the user, with their questions.", ui: ["Needs You Elsewhere"]),
        .init(.undo, .app, "", "Undo Duo's last move, merge or Make a Project (Edit › Undo).", ui: ["Undo", "Undo Conversion"]),
        .init(.help, .app, "[family | --markdown]", "Families and everyday verbs; a family's verbs; or the full reference as Markdown.", ui: ["duo2 Reference"], local: true),
        .init(.doctor, .setup, "", "How this terminal finds Duo, whether it can reach it, and what Duo installed.", local: true),
        .init(.install, .setup, "", "Install or refresh what lets Claude sessions anywhere use duo2: a short block in ~/.claude/CLAUDE.md, a duo2 skill, ~/.local/bin/duo2 (DL-74).",
              ui: ["Install", "Install…"], local: true),
        .init(.uninstall, .setup, "", "Remove exactly what `duo2 install` added (anything you edited stays).", ui: ["Remove…"], local: true),
        .init(.settings, .setup, "[claude-path <path|auto> | notify on|off | dock-badge on|off | macos]",
              "Duo's settings (S3-1): with no arguments, all of them, and what macOS allows; otherwise set one. The `claude` Duo runs, notifications when a session needs the user, the Dock badge; `macos` opens System Settings › Notifications › Duo.",
              ui: ["Choose…", "Use Found One", "Open Notification Settings…"]),
        .init(.walkSetup, .setup, "<test id>", "Put Duo in the state an acceptance-walk test starts from (the walk page's Set up test button, or `duo2://walk-setup?id=…`). Steps come from ~/DuoAcceptance/walk-setups.json, never from the caller.",
              ui: ["Set up test"]),
        .init(.compose, .setup, "<file>", "Claude Code's external editor in Duo's sessions (Ctrl+G; chat mode's composer, F-104, F-112): hands Claude the composer's text when chat mode asked for it, and otherwise opens your own editor ($VISUAL or $EDITOR as they were). Not for running by hand.", local: true),
        .init(.hook, .setup, "pre-edit | context", "Used by Duo's sessions. `pre-edit` (PreToolUse): Claude's Edit, MultiEdit and Write on a document open in Duo go through the editor instead of the file (DL-78). `context` (SessionStart, UserPromptSubmit): tells Claude the task(s) its session is attributed to, and on a prompt what changed since (DL-116).", local: true),
        .init(.legacy, .setup, "[disable --yes | restore <backup>]", "Find legacy Duo's instructions in ~/.claude; disable them (backed up first) or restore them.", ui: ["Disable…", "Restore"], local: true),

        // What's on screen
        .init(.goAll, .view, "", "Show All projects.", ui: ["All Projects"]),
        .init(.goHome, .view, "", "Show Home.", ui: ["Home"]),
        .init(.open, .view, "<project> [session] [--file <path>]", "Open a project, optionally on one of its sessions or documents.",
              ui: ["Open project", "Review", "project tile", "map session row"], everyday: true),
        .init(.peek, .view, "[open|close]", "Show or hide the sessions that need the user in other projects.", ui: ["Needs You Elsewhere"]),
        .init(.peekJump, .view, "", "Jump into the project selected in the peek.", ui: ["Jump into Selected Project"]),
        .init(.viewSidebar, .view, "show|hide|toggle", "Show or hide the left pane.", ui: ["Toggle Sidebar"]),
        .init(.viewRight, .view, "show|hide|toggle", "Show or hide the right pane: the action column at All projects, the documents in a project (⌥⌘0, DL-129).", ui: ["Toggle Right Pane", "right pane button"]),
        .init(.viewTab, .view, "<Project | document path | group>", "Switch the right pane's tab.", ui: ["right pane tab", "Open Project File"]),
        .init(.viewGroup, .view, "<group> expand|collapse", "Expand or collapse a group in the session list.", ui: ["group row"]),
        .init(.viewSelect, .view, "<session id>", "Select a session's card (action column or peek) without opening it.", ui: ["action card", "peek card"]),
        .init(.viewSort, .view, "recent|name", "Order All projects' map by newest activity or by name (View › Sort Projects By).", ui: ["Sort Projects By", "map sort popup"]),
        .init(.viewFilter, .view, "[text]", "Narrow All projects' middle, whichever shows: the Board to projects and folders whose name or path has the text, the List to sessions about it; no text clears it.", ui: ["Filter folders", "Filter sessions"]),
        .init(.viewHome, .view, "board|list|toggle [--archived on|off]", "All projects' middle (DL-142): the Board (the map) or the List, every session across projects by recency (View › Show Board / Show List). Duo remembers the choice. --archived shows or hides the List's Archived fold (its Group popup's Show Archived).",
              ui: ["Board", "List", "Show Board", "Show List", "Group By Recent", "Show Archived", "list group popup"]),
        .init(.viewHidden, .view, "on|off|toggle", "Show or hide dotfiles in the project's file tree (View › Show Hidden Files).", ui: ["Show Hidden Files"]),
        .init(.viewFolder, .view, "<folder> open|close", "Open or close a folder in the project's file tree.", ui: ["folder row"]),

        // Projects
        .init(.projects, .projects, "", "Projects and folders with sessions, with goal, health and next step.", everyday: true),
        .init(.projectShow, .projects, "<project>", "A project's folder, project file, goal, health, next step and sessions."),
        .init(.projectMake, .projects, "<folder name> [--not-now]", "Make a folder with sessions a documented project: writes a starter PROJECT.md and opens it. --not-now instead hides the folder's Make a Project notice (the Project tab still offers it). Undo with `duo2 undo`.",
              ui: ["Make a Project", "Not Now"]),
        .init(.projectArchive, .projects, "<project>", "File a project away: its tile moves into the map's Archived rollup. Sessions, counts and search are unchanged. Undo with `duo2 undo`.",
              ui: ["Archive Project", "archived rollup"]),
        .init(.projectUnarchive, .projects, "<project>", "Bring an archived project back to its topic column.", ui: ["Unarchive Project"]),
        .init(.homeSet, .projects, "<folder>", "Make a folder Home, the container of the projects the user tracks (DL-85): adds a HOME.md if there's none. Duo lists every session with or without a Home. Undo with `duo2 undo`.",
              ui: ["Choose Home Folder…", "Change…"]),
        .init(.projectMoveIntoHome, .projects, "<project|folder> [--into <topic folder>]", "Move a project or folder into Home (its top level, or a topic folder with --into) with every session filed under it (journaled; sessions stay its). The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Move into Home…", "Move"], timeout: 600),
        .init(.projectReconnect, .projects, "<project|folder> [--to <folder>]",
              "A project or folder moved outside Duo (DB-8): its sessions follow it to where it is now (found by Duo, or --to), the way Claude's /cd moves them; journaled. The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Reconnect Sessions…", "Use New Place", "Locate Folder…"], timeout: 600),
        .init(.projectForget, .projects, "<folder>", "Remove a missing folder's tile from Duo (DB-8); its sessions stay in Claude's storage and in search. Undo with `duo2 undo`.",
              ui: ["Remove from Duo"]),
        .init(.projectNew, .projects, "<name> [--goal <text>] [--into <topic folder>] [--session]", "Make a new project in Home (or a topic folder in it): a folder with a starter PROJECT.md holding the goal. --session starts a Claude session in it. Undo with `duo2 undo`.",
              ui: ["+ New project", "Create Project", "New Project…"]),
        .init(.inventory, .projects, "", "Claude's session storage, read only: each folder's sessions, size, missing folders, collisions, duplicate ids, and what Claude's cleanup takes within 7 days (CONS FR-7.1).", timeout: 180),
        .init(.evidence, .projects, "<project|folder>", "For a catch-all folder, read only: the files each session edited, its candidate home, and date clusters (CONS FR-7.10).", timeout: 300),
        .init(.migrations, .projects, "", "Storage migrations Duo planned or ran, newest first, with their state (CONS §6.3)."),
        .init(.migratePlan, .projects, "relocate <session> --to <folder> | move-folder <folder> --to <new path>",
              "Plan a storage change and show every step; nothing moves yet. Relocate moves a session's transcript into another folder's picker, as /cd does; move-folder moves a folder and its sessions together (CONS §7.4, §7.5)."),
        .init(.migrateApply, .projects, "<migration>", "Run a planned migration: journaled, verified, undoable. The user confirms in Duo.", timeout: 600),
        .init(.migrateUndo, .projects, "<migration>", "Undo a migration by replaying its journal in reverse.", timeout: 600),
        .init(.projectMerge, .projects, "<source> --into <target>", "Move every session of one project or folder into another. Files stay. The user confirms in Duo.",
              ui: ["Merge Into", "Merge Sessions Into", "drag a tile onto a tile"], timeout: 600),

        // Sessions
        .init(.sessions, .sessions, "[--project <p>]", "Sessions with id, state, title and project.", everyday: true),
        .init(.sessionShow, .sessions, "<id>", "A session's title, project, state, note, next step, transcript path and recent turns.", everyday: true),
        .init(.sessionNew, .sessions, "[--project <p>] [--prompt <text>] [--remote-control [name]]", "Start a Claude session in a project (the current one by default). --remote-control makes it reachable from the Claude app, named <name> or its project and a short id, and keeps it on when the session resumes; a claude without the flag starts without it and the reply says so.",
              ui: ["+ New session", "New Session", "console +", "New Claude Session", "Start Claude here", "Start Claude in Home", "Start in"]),
        .init(.sessionOpen, .sessions, "<id>", "Show a session's terminal, resuming it if needed.", ui: ["session row", "console tab", "Home tab", "Resume"]),
        .init(.sessionClose, .sessions, "[id] [--force]", "End a session's process and close its tab (it stays listed and resumable). Refuses while Claude is working there, unless --force.", ui: ["Close Tab", "End Session"]),
        .init(.sessionMove, .sessions, "<id> --to <project> [--new]", "File a session in another project, or with --new in a new project of that name made in Home; it moves there on its next resume. The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Move to Project", "New Project…", "drag a session onto a tile"], timeout: 600),
        .init(.sessionNote, .sessions, "<text>", "Tell the user what this session is doing (one line, shown in Duo).", everyday: true),
        .init(.sessionNext, .sessions, "<text>", "Tell the user what this session needs next (one line).", everyday: true),
        .init(.sessionTask, .sessions, "[id]", "The task(s) a session is attributed to (this session by default): each note's title, status and path. Duo's hooks tell Claude the same when the session starts, resumes, clears or compacts, and what changed on its next prompt (DL-116)."),
        .init(.sessionCarryOn, .sessions, "<id>", "Start a new session carrying on from an archived one."),
        .init(.sessionFork, .sessions, "<id>", "Carry a session on as a fork: a new session with the same history (the original is left alone).",
              ui: ["Resume as a Fork"]),
        .init(.sessionLink, .sessions, "<session>", "A Markdown link to a session for a note or task: [title](duo2://session/<id>). Clicking it in Duo opens or resumes the session (DL-87).",
              ui: ["Copy Link", "Copy Markdown link"]),
        .init(.sessionArchive, .sessions, "<id>", "File a session away: it leaves the lists and counts, keeps its transcript, stays searchable, and sits in its project's Archived fold. Not while it runs. Undo with `duo2 undo`.",
              ui: ["Archive Session"]),
        .init(.sessionUnarchive, .sessions, "<id>", "Bring an archived session back into its project's list.", ui: ["Unarchive Session", "Archived fold"]),
        .init(.sessionDelete, .sessions, "<id>", "Delete a session and its local logs for good (transcript, file history, environment; Duo's archived copy). The user confirms in Duo; never for a running session.",
              ui: ["Delete Session…"], timeout: 600),
        .init(.sessionChat, .sessions, "[id] on|off|toggle | --default last|chat|terminal | answer [id] <option|cancel> | mode [id] [next|manual|accept-edits|plan|auto|bypass]",
              "Chat mode (DL-118 to DL-120): show a Claude session as a readable chat over its real terminal, or as the terminal. Switching sends nothing to the session. --default sets the mode new sessions open in (last: the one used last). answer presses a review card's option key (1, 2, 3 …, or cancel for Esc) only after re-reading the screen; the same dialog must still be up. mode presses Claude Code's shift+tab, once (next) or until its footer shows the mode named; the cycle is the installed claude's own. With no id, the session on screen.",
              ui: ["Terminal", "Chat", "Back to Chat", "review card option", "Cancel esc", "Amend in Terminal…", "Approve with Feedback in Terminal…", "Manage in Terminal…", "Chat about this", "‹ Back", "mode chip", "⇧⇥ in the composer"]),
        .init(.idle, .sessions, "", "Idle, resumable sessions, newest first, grouped by when (the map footer's list).", ui: ["idle footer"]),
        .init(.shellNew, .sessions, "", "Open a plain shell in the console (DL-8); typing `claude` in it makes it a session.", ui: ["New Shell"]),
        // Groups (DL-24): related threads, grouped by hand; Duo-owned facts in the project's .duo/sessions.json.
        .init(.tasks, .sessions, "[--project <p>]", "Task notes (tasks/*.md in each project) with their status and how many sessions their `sessions:` frontmatter links (DL-93)."),
        .init(.taskMake, .sessions, "<session|group> [--title <t>]", "Make a Task: writes tasks/<slug>.md whose `sessions:` links the session (or the group's sessions; the group becomes the task) and opens it. Undo with `duo2 undo`.",
              ui: ["Make a Task"]),
        .init(.taskNew, .sessions, "[title] [--project <p>]", "+ New task: a task note with no sessions yet, opened to write. Undo with `duo2 undo`.", ui: ["+ New task", "New Task"]),
        .init(.taskSession, .sessions, "<task> [--project <p>]", "New Session in Task: starts a Claude session in the task's project with its link already in the note's `sessions:` list, and shows it when that project is open. Once Claude's prompt is up, Duo types `@tasks/<note>.md` into it and doesn't send it (DL-112): no turn is spent until someone adds a word and presses Return. Also the + on a task row's hover.",
              ui: ["New Session in Task"]),
        .init(.taskStatus, .sessions, "<task> <open|in-progress|waiting|review|done|dropped> [--project <p>]", "Set a task's status: rewrites only `status:` (and `completed:` when done or dropped). Done and dropped tasks leave the lists. Undo with `duo2 undo`.",
              ui: ["Set Status", "Mark Complete"]),
        .init(.taskAdd, .sessions, "<task> <session>", "Add to Task: puts the session's link in the task note's `sessions:` list, touching nothing else in the note. Undo with `duo2 undo`.",
              ui: ["Add to Task", "Open Task Note", "Add Session"]),
        .init(.taskRename, .sessions, "<task> <new title> [--project <p>]", "Rename a task: its `title:` and `# ` heading change, and the note moves to tasks/<slug of the new title>.md (-2, -3 when taken). Renaming in the note (heading or `title:`) moves the file too, once typing pauses. Undo with `duo2 undo`.",
              ui: ["Rename"]),
        .init(.taskArchive, .sessions, "<task> [--sessions|--keep-sessions] [--project <p>]", "Archive a task: `archived: true` in its note; it leaves the lists and counts, stays searchable, and sits in its project's Archived fold. With --sessions its linked sessions are archived too (never a running one); --keep-sessions leaves them. With neither, Duo asks the user. Undo with `duo2 undo`.",
              ui: ["Archive Task…"], timeout: 600),
        .init(.taskUnarchive, .sessions, "<task> [--project <p>]", "Bring an archived task back to the lists, with the sessions archived with it. Undo with `duo2 undo`.", ui: ["Unarchive Task"]),
        .init(.taskDelete, .sessions, "<task> [--project <p>]", "Delete a task: the user picks in Duo whether its linked sessions are deleted too (never a running one). The note goes to the Trash (`duo2 undo` brings it back); deleted sessions can't be undone.",
              ui: ["Delete Task…"], timeout: 600),
        .init(.taskMove, .sessions, "<task> <project> [--sessions|--keep-sessions] [--project <p>]", "Move a task's note to another project's tasks/. With --sessions its sessions in this project move too; --keep-sessions leaves them. With neither and sessions to move, Duo asks the user. Undo with `duo2 undo`.",
              ui: ["Move to Project"], timeout: 600),
        .init(.taskLink, .sessions, "<task> [--project <p>]", "A Markdown link to a task: [title](duo2://task/<id>). The id is written once into the note's `id:`, so the link survives renames and moves. Clicking it in Duo opens the note.",
              ui: ["Copy Link"]),
        .init(.taskReveal, .sessions, "<task> [--project <p>]", "Show a task's note in Finder.", ui: ["Reveal in Finder"]),
        .init(.groups, .sessions, "[--project <p>]", "Groups and their sessions, with each group's most urgent state."),
        .init(.groupNew, .sessions, "<name> <session>…", "Group sessions of one project under a name."),
        .init(.groupAdd, .sessions, "<group> <session>…", "Add sessions to a group."),
        .init(.groupRemove, .sessions, "<group> <session>…", "Take sessions out of a group (an empty group goes away)."),
        .init(.groupRename, .sessions, "<group> <new name>", "Rename a group."),
        .init(.groupDelete, .sessions, "<group>", "Ungroup: the group goes, its sessions stay."),

        // Files (paths are relative to the project, or absolute)
        .init(.files, .files, "[folder] [--project <p>] [--hidden]", "The project's files and folders, three levels deep; --hidden includes dotfiles."),
        .init(.fileNew, .files, "[--in <folder>] [--name <name>]", "Create a Markdown file and open it.", ui: ["New Markdown File", "right pane +"]),
        .init(.fileNewFolder, .files, "[--in <folder>] [--name <name>]", "Create a folder.", ui: ["New Folder"]),
        .init(.fileTemplate, .files, "<template> [--in <folder>]", "Create a file from a template (the project's templates/, then Home's).", ui: ["New from Template"]),
        .init(.fileTemplates, .files, "", "The templates available here."),
        .init(.fileRename, .files, "<path> <new name>", "Rename a file or folder; open tabs follow.", ui: ["Rename"]),
        .init(.fileDuplicate, .files, "<path>", "Copy a file or folder next to itself.", ui: ["Duplicate"]),
        .init(.fileMove, .files, "<path>… <folder> [--replace | --keep-both]", "Move files or folders into a folder; open tabs follow. A path may be anywhere on the Mac (the same move as dropping it from Finder on the tree); from another volume it's copied, as Finder does. A taken name fails unless --replace (the one there goes to the Trash) or --keep-both (\"name 2\"). A folder can't go into itself. Undo with `duo2 undo`.",
              ui: ["Move To…", "files dropped on the file tree"]),
        .init(.fileTrash, .files, "<path>", "Move to the Trash (never deleted outright).", ui: ["Move to Trash"]),
        .init(.fileReveal, .files, "<path>", "Show in Finder.", ui: ["Reveal in Finder"]),
        .init(.fileOpenWith, .files, "<path> [--app <name>]", "Open in another app (the default app if none named).", ui: ["Open With", "Other…", "Open Original"]),
        .init(.fileConvert, .files, "<docx> [--as <name.md>] [--replace] [--anyway]", "Make a Markdown copy of a Word document beside it (<name>.md, pictures in <name>-images); the .docx isn't changed (DL-123). Headings, lists and layout tables are inferred and cleaned; tracked changes are accepted; comments become endnotes. Prints what it inferred and what didn't come over. A taken name fails unless --as or --replace (the one there goes to the Trash); --anyway converts a document with no text. Undo with `duo2 undo`.",
              ui: ["Convert to Markdown", "Convert Anyway"]),
        .init(.filePath, .files, "<path> [--relative | --link] [--copy]", "Print a file's path, relative path or Markdown link; --copy puts it on the clipboard.",
              ui: ["Copy Path", "Copy Relative Path", "Copy as Link"]),

        // Documents
        .init(.docOpen, .docs, "<path> [--project <p>]", "Open a document in the right pane (Markdown in the editor, HTML as a page). A file outside every project opens as a tab in the project on screen (or --project).", ui: ["Open", "file row", "Open File…", "file dropped on the right pane", "Open CLAUDE.md"], everyday: true),
        .init(.docClose, .docs, "[path] [--others]", "Close a document tab (saved first), or every other one.", ui: ["Close Tab", "Close Other Tabs"]),
        .init(.docTabs, .docs, "", "The open document tabs, and which one shows."),
        .init(.docStatus, .docs, "<file>", "Whether a file is open in Duo's editor, unsaved or in conflict. Check before editing a file the user may have open.", everyday: true),
        .init(.docRead, .docs, "[path]", "A document's text as the editor has it (unsaved edits included); the showing document by default."),
        .init(.docSelection, .docs, "", "The text selected in the editor, with its file and lines."),
        .init(.docSelect, .docs, "<line> [to-line]", "Select lines in the showing document."),
        .init(.docSave, .docs, "", "Save the showing document now (it also autosaves).", ui: ["Save"]),
        .init(.docFormat, .docs, "bold|italic|code|link|heading1|heading2|heading3|task|properties",
              "Format the selection (bold, italic, code, a link waiting for its address), make its lines headings or tasks (again takes it off), or start the properties block.",
              ui: ["Bold", "Italic", "Code", "Link…", "Heading 1", "Heading 2", "Heading 3", "Task", "Add Properties"]),
        .init(.docTable, .docs, "insert|row-above|row-below|column-before|column-after|delete-row|delete-column|align-left|align-center|align-right|next|previous",
              "Edit the table at the caret as Markdown, its columns kept lined up: insert a 3 × 2 table, add or delete a row or column, align a column, or move to the next or previous cell (the last cell's next adds a row).",
              ui: ["Insert Table", "Add Row Above", "Add Row Below", "Add Column Before", "Add Column After", "Delete Row", "Delete Column",
                   "Left", "Center", "Right", "+ Row", "+ Column", "Align", "Delete"]),
        .init(.docFind, .docs, "<text>", "Find text in the showing document and select the next match.", ui: ["Find"]),
        .init(.docProp, .docs, "list | get <name> | set <name> <value> | remove <name> | type <name> <text|list|number|checkbox|date|datetime|link>",
              "The showing document's properties (frontmatter): read them, or change one line through the editor, highlighted as Claude's (DB-16). Lists: `set tags \"[a, b]\"`.",
              ui: ["Add a property", "property type menu", "Pick a date", "property checkbox"]),
        .init(.docInsert, .docs, "<text> [--line <n>]", "Insert text into the showing document through the editor (highlighted as added by Claude), at a line or the caret."),
        .init(.docReplace, .docs, "<find> <replacement>", "Replace text in the showing document through the editor (highlighted as added by Claude)."),

        .init(.docRevert, .docs, "[--all | --line <n>]", "Put back what Claude changed in the open document: the change at the caret or a line, or all of them since the user's last edit (ENH-4).",
              ui: ["Revert This Change", "Revert All of Claude's Changes", "Revert Claude's Change"]),
        .init(.docEdit, .docs, "--stdin", "Apply an Edit-tool-shaped change ({file_path, old_string, new_string, replace_all} or {file_path, edits} or {file_path, content}, as JSON on stdin) to a document open in Duo, through the editor, highlighted."),

        .init(.docResolve, .docs, "mine|theirs", "End a conflict in the showing document: keep the user's text (saved over the file) or take the file's. The other version stays in history. Only when the user asks.",
              ui: ["Keep Mine", "Use Theirs"]),
        .init(.docHistory, .docs, "[path]", "Versions Duo kept of a document (as opened, both sides of conflicts, before removal), newest last, with where each is stored."),

        // HTML pages
        .init(.browserOpen, .html, "[url]", "A browser tab in the right pane (⌥⌘T). Sites not on the allow list show Allow or Open in Browser instead of loading (DL-3).",
              ui: ["New Browser Tab", "Open Location…", "Open in Browser", "Copy Address"]),
        .init(.browserAllow, .html, "<host>", "Add a site to the allow list, so its pages open in Duo's browser tabs (and its subdomains)."),
        .init(.browserSites, .html, "", "The allow list: sites Duo opens in its own browser tabs; everything else opens in the system browser (DL-3).", ui: ["Edit…"]),
        .init(.browserTabs, .html, "", "Browser tabs open in Duo: id, project, title, address."),
        .init(.browserRead, .html, "[selector] [--tab <id>]", "The page's text (or one element's), with its title and address (LR-45). Allowed sites only."),
        .init(.browserClick, .html, "<selector> [--synthetic] [--tab <id>]", "Click the element a CSS selector names, scrolled into view: real mouse events at its centre, which apps like Google Docs need (DL-124). --synthetic sends element.click() instead (also used when the tab isn't on screen)."),
        .init(.browserFill, .html, "<selector> <text…> [--tab <id>]", "Type into an input, text area or editable element, as a person would (input and change events)."),
        .init(.browserWait, .html, "<selector> [--timeout <s>] [--tab <id>]", "Wait for an element to appear (default 10 s)."),
        .init(.browserScreenshot, .html, "[--tab <id>]", "Save a picture of the visible page as a PNG and print its path."),
        .init(.browserGo, .html, "<url> [--tab <id>]", "Go to an address in the tab; a site not on the allow list isn't loaded."),
        .init(.browserBack, .html, "[--tab <id>]", "Back in the tab's history.", ui: ["Back"]),
        .init(.browserForward, .html, "[--tab <id>]", "Forward in the tab's history.", ui: ["Forward"]),
        .init(.browserClose, .html, "[--tab <id>]", "Close the browser tab (a popup's tab hands back to the page that opened it)."),
        .init(.browserZoom, .html, "[<percent> | in | out | reset] [--tab <id>]", "The page's zoom, or set it: remembered for the site (DL-124). ⌘+ ⌘- ⌘0 while the tab has the keyboard.",
              ui: ["Zoom In", "Zoom Out", "Actual Size", "zoom percentage in the bar"]),
        .init(.browserPrint, .html, "[--pdf <path>] [--tab <id>]", "Print the page: the print panel on the window for the user (⌘P, or the page's own print), or --pdf saves it as a PDF without one (DL-124).",
              ui: ["Print…"]),
        .init(.browserUpload, .html, "<selector> <file…> [--tab <id>]", "Choose files for a file input: the files answer its file chooser, then it's clicked as a person would (DL-124). The user's own click opens the open panel."),
        .init(.browserDownloads, .html, "[--open [<n>] | --cancel]", "Downloads from browser tabs since Duo started, numbered, to ~/Downloads with Finder's names for clashes (DL-124). --open opens one (the newest by default) with its app, as the tab's notice's Open does. --cancel stops the one running and takes its partial file away, as the notice's Cancel does (DL-132).",
              ui: ["Open"]),
        .init(.htmlReload, .html, "", "Reload the HTML page showing (it also reloads when its files change).", ui: ["Reload Page"]),
        .init(.htmlPick, .html, "[selector]", "Start the element picker for the user, or select the element a CSS selector names.",
              ui: ["Select Element", "Pick Another"]),
        .init(.htmlStop, .html, "", "Close the element picker.", ui: ["Cancel picking"]),
        .init(.htmlElement, .html, "[selector]", "Describe an element (the picked one by default): selector, text, attributes, styles, box, HTML."),
        .init(.htmlSelection, .html, "", "The text and images selected in the HTML page."),

        // PowerPoint decks (ENH-12, DL-125)
        .init(.slide, .slides, "", "The deck showing and the slide on screen, with that slide's shapes and text."),
        .init(.slideGo, .slides, "<n> | next | previous", "Show a slide of the deck in the right pane (also ‹ ›, Page Up and Page Down).",
              ui: ["Previous Slide", "Next Slide"]),
        .init(.slideShapes, .slides, "[<file.pptx>] [<n>]", "A slide's shapes from the file: OOXML id, name, type, groups, text, box, tables, chart data, notes. The deck showing and its slide by default; a file without a slide gives every slide."),
        .init(.slideNotes, .slides, "[<file.pptx>] [<n>]", "A slide's speaker notes (the slide on screen by default)."),
        .init(.slidePick, .slides, "[<slide>/<shape id>]", "Start the shape picker for the user, or select the shape a slide and id name.",
              ui: ["Select Shape", "Pick Another"]),
        .init(.slideElement, .slides, "[<slide>/<shape id>]", "Describe a shape (the picked one by default): slide, id, name, groups, text, box, and a screenshot."),

        // Send to Claude (into a session's prompt; never pressing Enter)
        .init(.sendFile, .send, "<path> [--to <id> | --new]", "Put an @-reference to a file or folder into a session's prompt.", ui: ["Send to Claude", "Send To"]),
        .init(.sendSession, .send, "<id> [--to <id> | --new]", "Put a session's reference into a session's prompt.", ui: ["Send to Claude"]),
        .init(.sendProject, .send, "<project> [--to <id> | --new]", "Put a project's reference into a session's prompt.", ui: ["Send to Claude"]),
        .init(.sendSelection, .send, "[--to <id> | --new]", "Put the user's selection (document or HTML page) into a session's prompt.",
              ui: ["Send Selection to Claude", "Send Selection To", "Send Image to Claude", "Send Image To"]),
        .init(.sendElement, .send, "[--to <id> | --new]", "Put the picked HTML element, or the shape picked on a slide, into a session's prompt.", ui: ["Send to Claude", "Send To", "New Session"]),
        .init(.sendText, .send, "<text> [--to <id> | --new]", "Type text into a session's prompt for the user to finish and send."),
        .init(.selection, .send, "", "What the user has selected or picked right now, in the editor or an HTML page.", everyday: true),

        // Search
        .init(.search, .search, "<query> | --similar <path> [-k N] [--project P] [--kind file|session|memory] [--exact]",
              "Search every project by meaning and by words. Works without the app; read-only.",
              ui: ["Search Everything…", "Search all projects", "Clear filters", "Include archived", "Exact", "Find Similar"], local: true, everyday: true),
        .init(.searchStatus, .search, "", "How much of each project the search index covers.", ui: ["Show details"], local: true),
        .init(.searchRebuild, .search, "", "Rebuild the search index from scratch (the old one goes to the Trash).", ui: ["Rebuild the index"]),
    ]

    public static let byID: [ActionID: DuoAction] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Finds the action for a command line: two-word verbs first ("file rename"), then one word.
    /// Old spellings keep working.
    public static func resolve(_ args: [String]) -> (DuoAction, rest: [String])? {
        let words = args.prefix(2).map { aliases[$0] ?? $0 }
        if words.count == 2, let id = ActionID(rawValue: words.joined(separator: " ")) { return (byID[id]!, Array(args.dropFirst(2))) }
        if let w = words.first {
            if let id = ActionID(rawValue: w) { return (byID[id]!, Array(args.dropFirst())) }
            // "doc-status file" → "doc status"
            if let id = ActionID(rawValue: w.replacingOccurrences(of: "-", with: " ")) { return (byID[id]!, Array(args.dropFirst())) }
        }
        return nil
    }

    static let aliases = ["--help": "help", "-h": "help", "--ping": "ping"]
}

/// What the app shows a person but has no verb, and why (DL-71's exceptions). The parity check
/// accepts these labels; everything else in the UI must name an action.
public enum Parity {
    public static let uiOnly: [String: String] = [
        "Close Window": "window management",
        "Enter Full Screen": "window management",
        "Exit Full Screen": "window management",
        "Toggle Right Pane": "not built yet",
        "Next Pane": "not built yet",
        "Previous Pane": "not built yet",
        "Cancel": "a step inside another action's dialog or picker",
        "Look Again": "re-reads what Duo already refreshes every 2 s; the CLI always reads fresh state",
        "Open Settings…": "not built: Settings waits on its design (DB-10)",
        "Go": "a menu, not an action",
        "Format": "a menu, not an action",
        "Project": "a menu, not an action",
        "Session": "a menu, not an action",
        "Heading": "a submenu, not an action",
        "Table": "a submenu, not an action",
        "Align Column": "a submenu, not an action",
        "What’s New in This Version": "opens this version's release notes on GitHub; `duo2 status` names the version",
        "Report an Issue…": "opens GitHub's new-issue form, filled in, for the user to edit and submit",
        "No templates yet: add .md files to a templates folder": "a disabled hint",
        "No other sessions in": "a disabled hint on + Add",
        "Resume a session": "the debug gallery only (DL-59 removed it from the app)",
        "Add to .gitignore": "a one-time question to the user (DL-50)",
        "confirmation sheet": "the user's own consent; Claude can't confirm for them",
        "Not Now": "the user's answer to the install question; `duo2 install` and `duo2 uninstall` change it later",
        "Show in Finder": "reveals a file or folder in Finder (Settings, editor notices, launch sheets)",
        "OK": "dismisses a notice",
        "Install Now": "on the update question: hands to Sparkle's own window, which installs only once the user agrees there (and gives an administrator password where one is needed); `duo2 update` says whether one is (DL-114)",
        "Later": "the user's answer to the update question; it remembers the version so the launch and scheduled checks don't ask again (DL-114)",
        "files dropped on a terminal": "types the dropped paths at the cursor, as Terminal.app does (DL-117); a session already has the paths, and `duo2 send` types text into a Claude session",
        "Save to Recreate": "writes the user's own text back after the file was removed on disk; Claude can do the same with `duo2 doc edit` (content) once the user asks",
    ]
}

// MARK: - Arguments

/// A parsed command line after the verb: positionals and `--flags` (`--flag value` or `--flag`).
public struct Invocation: Sendable {
    public var positional: [String] = []
    public var flags: [String: String] = [:]

    /// Flags that take no value.
    static let switches: Set<String> = ["json", "yes", "replace", "keep-both", "relative", "link", "copy", "others", "new", "markdown", "exact", "all", "session", "open", "sessions", "keep-sessions", "synthetic", "force"]

    /// Flags whose value is optional: the next word is theirs unless it's another flag.
    static let optionalValues: Set<String> = ["remote-control"]

    public init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--"), a.count > 2 {
                let name = String(a.dropFirst(2))
                if let eq = name.firstIndex(of: "=") {
                    flags[String(name[..<eq])] = String(name[name.index(after: eq)...])
                } else if Self.switches.contains(name) || i + 1 >= args.count || (Self.optionalValues.contains(name) && args[i + 1].hasPrefix("--")) {
                    flags[name] = ""
                } else {
                    flags[name] = args[i + 1]; i += 1
                }
            } else {
                positional.append(a)
            }
            i += 1
        }
    }

    public var json: Bool { flags["json"] != nil }
    public func has(_ flag: String) -> Bool { flags[flag] != nil }
    public subscript(_ i: Int) -> String? { positional.indices.contains(i) ? positional[i] : nil }
    /// Every positional joined, for free text (`session note fixing the parser`).
    public var text: String { positional.joined(separator: " ") }
}

// MARK: - Help and generated docs

extension DuoAction {
    public static func help(family: String? = nil) -> String {
        if let family, let f = ActionFamily.allCases.first(where: { $0.rawValue == family || $0.title.lowercased() == family.lowercased() }) {
            return "\(f.title)\n\n" + table(all.filter { $0.family == f }) + "\nEvery verb takes --json.\n"
        }
        var out = "duo2 talks to the Duo app: everything a person can do in Duo, Claude can do here.\n\nEveryday:\n"
        out += table(all.filter(\.everyday))
        out += "\nAll verbs, by family (duo2 help <family>):\n"
        out += ActionFamily.allCases.map { f in
            "  \(f.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) " + all.filter { $0.family == f }.map(\.verb).joined(separator: ", ")
        }.joined(separator: "\n")
        return out + "\n\nEvery verb takes --json. Errors go to stderr with a non-zero exit.\n"
    }

    /// Usage then summary, aligned; a usage too long to align puts its summary on the next line.
    static func table(_ rows: [DuoAction]) -> String {
        let width = min(44, rows.map(\.usage.count).max() ?? 0)
        return rows.map { a in
            a.usage.count > width
                ? "  \(a.usage)\n  \(String(repeating: " ", count: width + 2))\(a.summary)"
                : "  " + a.usage.padding(toLength: width + 2, withPad: " ", startingAt: 0) + a.summary
        }.joined(separator: "\n") + "\n"
    }

    /// The full reference (`docs/cli/duo2.md`), generated; DuoChecks fails if the file is stale.
    public static func markdown() -> String {
        var out = "# duo2 reference\n\nGenerated from the action registry (`Sources/DuoControl/Actions.swift`) by `duo2 help --markdown`; don't edit by hand.\n\n"
        out += "Everything a person can do in Duo, Claude can do with `duo2` (DL-71). Every verb takes `--json`; errors go to stderr with a non-zero exit.\n"
        for f in ActionFamily.allCases {
            out += "\n## \(f.title)\n\n| Command | What it does | In the app |\n|---|---|---|\n"
            for a in all where a.family == f {
                let ui = a.ui.isEmpty ? "—" : a.ui.joined(separator: ", ")
                out += "| `\(a.usage.replacingOccurrences(of: "|", with: "\\|"))` | \(a.summary.replacingOccurrences(of: "|", with: "\\|")) | \(ui) |\n"
            }
        }
        out += "\n## In the app only\n\n| Item | Why it has no verb |\n|---|---|\n"
        for (k, v) in Parity.uiOnly.sorted(by: { $0.key < $1.key }) { out += "| \(k) | \(v) |\n" }
        return out
    }

    /// What Duo tells each session it starts (`--append-system-prompt`, DL-15, DL-74): short,
    /// generated, so it never names a verb that doesn't exist.
    public static func primer() -> String {
        "You are running inside Duo, a Mac app that organizes the user's Claude Code sessions into projects and shows their documents. "
            + "The `duo2` command talks to Duo; it is on PATH and needs no approval. Everything the user can do in Duo, you can do with it "
            + "(`duo2 help`, then `duo2 help <family>`: " + ActionFamily.allCases.map(\.rawValue).joined(separator: ", ") + "). Everyday:\n"
            + all.filter(\.everyday).map { "- `\($0.usage)`: \($0.summary)" }.joined(separator: "\n")
            + "\nFor questions across projects, or about meaning rather than exact text, run `duo2 search \"<question>\"` before grep or reading folders. "
            + "Read only the lines it points to. Its scores only compare results within one search. Use `--exact` for identifiers."
            + "\nWhen the user says \"this\", \"here\" or \"what I selected\", run `duo2 selection` first."
            + "\nDocuments the user has open in Duo (`duo2 status` shows them) are theirs to see change: edit them with "
            + "`duo2 doc edit --stdin`, piping the JSON your Edit tool takes ({\"file_path\",\"old_string\",\"new_string\"}, or {\"file_path\",\"content\"} to rewrite), "
            + "not with Edit, Write or shell redirection. Duo applies it in the editor the user is looking at, highlighted, and merges it with their unsaved typing."
            + "\nWhen you start substantial work, `duo2 session note \"<one line>\"`; when you hand back, `duo2 session next \"<one line>\"`."
    }
}
