import Foundation

// The action registry (DL-71, DL-72): everything a person can do in Duo, defined once. The CLI's
// verbs, `duo2 help`, the generated reference (`docs/cli/duo2.md`), the primer Duo gives each
// session, and the parity check all come from this table. Views name the action they perform
// (`ActionButton(.fileRename)`, `.onActivate(.sessionOpen)`), and `DuoChecks` fails when a button,
// menu item or click in the app isn't tied to an action here or listed in `Parity.uiOnly`.

public enum ActionFamily: String, CaseIterable, Sendable {
    case app, view, projects, sessions, director, files, repo, docs, review, html, slides, send, search, setup

    public var title: String {
        switch self {
        case .app: "Duo"
        case .view: "What's on screen"
        case .projects: "Projects"
        case .sessions: "Sessions"
        case .director: "Director"
        case .files: "Files"
        case .repo: "GitHub"
        case .docs: "Documents"
        case .review: "Review in Markdown"
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
    case viewSidebar = "view sidebar", viewRight = "view right", viewTab = "view tab", viewTabMove = "view tab-move", viewPane = "view pane", viewGroup = "view group", viewSelect = "view select"
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
    case sessionPark = "session park", sessionKeepRunning = "session keep-running"
    case sessionNote = "session note", sessionNext = "session next", sessionCarryOn = "session carry-on"
    case sessionLink = "session link", sessionTask = "session task", sessionChat = "session chat"
    case shellNew = "shell new", sessionFork = "session fork", sessionTrustFolder = "session trust-folder", sessionForkAgain = "session fork-again", idle, sessionDelete = "session delete", sessionArchive = "session archive", sessionUnarchive = "session unarchive"
    case tasks, taskMake = "task make", taskAdd = "task add", taskNew = "task new", taskSession = "task session", taskStatus = "task status"
    case taskRename = "task rename", taskArchive = "task archive", taskUnarchive = "task unarchive", taskDelete = "task delete"
    case taskMove = "task move", taskLink = "task link", taskReveal = "task reveal"
    case taskBoard = "task board", taskColumn = "task column", taskReference = "task reference", taskBase = "task base"
    case templateShow = "template show", templateEdit = "template edit", templateCopy = "template copy", templateReset = "template reset", templatePreview = "template preview"
    case groups, groupNew = "group new", groupAdd = "group add", groupRemove = "group remove", groupRename = "group rename", groupDelete = "group delete"
    // Director (DL-193 to DL-206)
    case directorStatus = "director status", directorStart = "director start", directorSend = "director send"
    case directorRetire = "director retire", directorGuide = "director guide", directorWatch = "director watch"
    // Files
    case files, filesBrowse = "files browse", fileNew = "file new", fileNewFolder = "file new-folder", fileTemplate = "file template", fileTemplates = "file templates"
    case fileRename = "file rename", fileDuplicate = "file duplicate", fileMove = "file move", fileTrash = "file trash"
    case fileReveal = "file reveal", fileOpenWith = "file open-with", filePath = "file path", fileConvert = "file convert"
    // GitHub (DL-149, DL-157)
    case repoStatus = "repo status", repoCheck = "repo check", repoLatest = "repo latest", repoUpdate = "repo update", repoPutBack = "repo put-back"
    case repoPush = "repo push", repoPR = "repo pr", repoDraft = "repo draft", repoMoveToBranch = "repo move-to-branch", repoSignin = "repo signin", repoOpen = "repo open"
    // GitHub issues (DL-226)
    case issueShow = "issue show", issueOpen = "issue open", issueClose = "issue close", issueReopen = "issue reopen", issueNew = "issue new", taskIssue = "task issue"
    // Documents
    case docOpen = "doc open", docClose = "doc close", docTabs = "doc tabs", docStatus = "doc status", docRead = "doc read"
    case docSelection = "doc selection", docSelect = "doc select", docSave = "doc save", docFormat = "doc format", docTable = "doc table", docFind = "doc find"
    case docProp = "doc prop", docMode = "doc mode"
    case docMarkup = "doc markup", docComments = "doc comments", docOutline = "doc outline", docLayout = "doc layout", docScreenshot = "doc screenshot", docPick = "doc pick", docElement = "doc element"
    case docReview = "doc review"
    case commentAdd = "comment add", commentList = "comment list", commentReply = "comment reply", commentSend = "comment send"
    case commentClose = "comment close", commentDelete = "comment delete", commentReopen = "comment reopen", commentStatus = "comment status"
    case suggestionList = "suggestion list", suggestionAccept = "suggestion accept", suggestionReject = "suggestion reject"
    case docInsert = "doc insert", docReplace = "doc replace", docEdit = "doc edit", docResolve = "doc resolve", docHistory = "doc history", docRevert = "doc revert"
    // HTML pages
    case browserOpen = "browser open", browserAllow = "browser allow", browserSites = "browser sites"
    case browserTabs = "browser tabs", browserRead = "browser read", browserClick = "browser click", browserFill = "browser fill"
    case browserWait = "browser wait", browserScreenshot = "browser screenshot", browserScroll = "browser scroll",browserGo = "browser go", browserBack = "browser back"
    case browserForward = "browser forward", browserClose = "browser close"
    case browserZoom = "browser zoom", browserPrint = "browser print", browserUpload = "browser upload", browserDownloads = "browser downloads"
    case htmlReload = "html reload", htmlPick = "html pick", htmlStop = "html stop", htmlElement = "html element", htmlSelection = "html selection"
    // PowerPoint decks
    case slide, slideGo = "slide go", slideShapes = "slide shapes", slideNotes = "slide notes", slidePick = "slide pick", slideElement = "slide element"
    // Send to Claude
    case sendFile = "send file", sendSession = "send session", sendProject = "send project", sendSelection = "send selection"
    case sendElement = "send element", sendText = "send text", selection
    // Voice input (DL-260, DL-261)
    case voiceStart = "voice start", voiceStop = "voice stop", voiceStatus = "voice status", voiceFile = "voice file"
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
        .init(.doctor, .setup, "", "How this terminal finds Duo, whether it can reach it, what Duo installed, and whether Claude Code mods work here.", local: true),
        .init(.install, .setup, "[--director-name director|duo-director]", "Install or refresh what lets Claude sessions anywhere use duo2: a short block in ~/.claude/CLAUDE.md, a duo2 skill, a director skill, ~/.local/bin/duo2 (DL-74). The director skill is named `director`; where a project has a skill of that name, a personal one would hide it, so Duo asks first and until you say yes installs it as `duo-director`. --director-name answers that: `director` takes the name, `duo-director` keeps the project's skill (DL-222).",
              ui: ["Install", "Install…", "Use director", "Keep duo-director"], local: true),
        .init(.uninstall, .setup, "", "Remove exactly what `duo2 install` added (anything you edited stays).", ui: ["Remove…"], local: true),
        .init(.settings, .setup, "[claude-path <path|auto> | notify on|off | dock-badge on|off | appearance system|light|dark|classic | explainers reset | macos]",
              "Duo's settings (S3-1): with no arguments, all of them, and what macOS allows; otherwise set one. The `claude` Duo runs, notifications when a session needs the user, the Dock badge; `appearance` (Match System, Light, Dark or Classic, DL-224, DL-252); `explainers reset` shows the explanations the user dismissed again (Settings › General); `macos` opens System Settings › Notifications › Duo.",
              ui: ["Choose…", "Use Found One", "Open Notification Settings…", "Show dismissed explanations again", "Appearance"]),
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
        .init(.viewTab, .view, "<Project | document path | group | next | previous>", "Switch the right pane's tab; next and previous step through the active pane's tabs instead (⌃Tab, ⌃⇧Tab, DL-165).",
              ui: ["right pane tab", "Open Project File", "Show Next Tab", "Show Previous Tab"]),
        .init(.viewTabMove, .view, "left|right|<n> [tab] [--pane middle|right]",
              "Move a tab along its strip: one place left or right (Move Tab Left / Right on its menu), or to place n among the tabs that move (1 is the leftmost), as a drag does (DL-220). The tab is a document path, a session id or name, or by default the selected tab of the active pane (or --pane). The right pane's Project tab stays first.",
              ui: ["Move Tab Left", "Move Tab Right", "tab dragged along its strip"]),
        .init(.viewPane, .view, "next|previous|left|middle|right", "Make a pane active and give it the keyboard: the next or previous one (⌥⌘→, ⌥⌘←), or one by name; a hidden pane can't be chosen.", ui: ["Next Pane", "Previous Pane"]),
        .init(.viewGroup, .view, "<group|original id> expand|collapse", "Expand or collapse a group in the session list: a time group (today, week, earlier), later (the tasks quiet for 3 days), a task, or a thread of forks by its original's session id (DL-228).", ui: ["group row", "Later fold"]),
        .init(.viewSelect, .view, "[<id>…] [--add] [--all] [--clear] [--list project|list|action|idle]",
              "Select sessions without opening them (DL-247). With one id and no flag it also selects that session's card (action column or peek). Ids set the selection in the list in front: the list with the keyboard, else the project's pane when a project is open, else All projects' List; --add keeps what is selected; --all selects every row showing in the list; --clear clears it; --list names the list (project is the open project's pane). With no arguments it prints the selection and its list. An id that can't be found is named. Acts only on the selection; nothing else changes.",
              ui: ["action card", "peek card", "⇧-click", "⌘-click", "⌘A"]),
        .init(.viewSort, .view, "recent|name", "Order All projects' map by newest activity or by name (View › Sort Projects By).", ui: ["Sort Projects By", "map sort popup"]),
        .init(.viewFilter, .view, "[text]", "Narrow All projects' middle, whichever shows: the Board to projects and folders whose name or path has the text, the List to sessions about it; no text clears it.", ui: ["Filter folders", "Filter sessions"]),
        .init(.viewHome, .view, "board|list|toggle [--archived on|off]", "All projects' middle (DL-142): the Board (the map) or the List, every session across projects by recency (View › Show Board / Show List). Duo remembers the choice. --archived shows or hides the List's Archived fold (its Group popup's Show Archived).",
              ui: ["Board", "List", "Show Board", "Show List", "Group By Recent", "Show Archived", "list group popup"]),
        .init(.viewHidden, .view, "on|off|toggle", "Show or hide dotfiles in the project's file tree (View › Show Hidden Files).", ui: ["Show Hidden Files"]),
        .init(.viewFolder, .view, "<folder> open|close", "Open or close a folder in the project's file tree.", ui: ["folder row"]),

        // Projects
        .init(.projects, .projects, "", "Projects and folders with sessions, with goal, health and next step.", everyday: true),
        .init(.projectShow, .projects, "<project>", "A project's folder, project file, goal, health, next step and sessions."),
        .init(.projectMake, .projects, "<folder name | path in Home> [--no-interview] [--not-now]", "Make a folder a documented project (one with sessions, or any folder in Home, DL-212): writes a starter _PROJECT.md, opens it, and starts a Claude session there that looks around the folder, interviews you in a few questions and fills _PROJECT.md in (DL-223); --json gives its id. --no-interview writes the file without the session. --not-now instead hides the folder's Make a Project notice (the Project tab still offers it). Undo with `duo2 undo`.",
              ui: ["Make a Project", "Not Now"]),
        .init(.projectArchive, .projects, "<project>", "File a project away: its tile moves into the map's Archived rollup. Sessions, counts and search are unchanged. Undo with `duo2 undo`.",
              ui: ["Archive Project", "archived rollup"]),
        .init(.projectUnarchive, .projects, "<project>", "Bring an archived project back to its topic column.", ui: ["Unarchive Project"]),
        .init(.homeSet, .projects, "<folder>", "Make a folder Home, the container of the projects the user tracks (DL-85): adds a _HOME.md if there's none. Duo lists every session with or without a Home. Undo with `duo2 undo`.",
              ui: ["Choose Home Folder…", "Change…"]),
        .init(.projectMoveIntoHome, .projects, "<project|folder> [--into <topic folder>]", "Move a project or folder into Home (its top level, or a topic folder with --into) with every session filed under it (journaled; sessions stay its). The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Move into Home…", "Move"], timeout: 600),
        .init(.projectReconnect, .projects, "<project|folder> [--to <folder>]",
              "A project or folder moved outside Duo (DB-8): its sessions follow it to where it is now (found by Duo, or --to), the way Claude's /cd moves them; journaled. The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Reconnect Sessions…", "Use New Place", "Locate Folder…"], timeout: 600),
        .init(.projectForget, .projects, "<folder>", "Remove a missing folder's tile from Duo (DB-8); its sessions stay in Claude's storage and in search. Undo with `duo2 undo`.",
              ui: ["Remove from Duo"]),
        .init(.projectNew, .projects, "<name> [--goal <text>] [--into <folder in Home>] [--use-folder] [--session] | --from-github <link|owner/repo> [<name>] [--new-branch <b> [--from <base>] | --branch <existing>] [--sheet]", "Make a new project in Home: a folder with a starter _PROJECT.md holding the goal. --into puts it in a folder in Home, by name or by its path in Home (DL-211); with --use-folder that folder itself becomes the project instead, keeping its name, with <name> (optional) as the project's title. --session starts a Claude session in it that interviews you and fills _PROJECT.md in (DL-223). --from-github copies a repository into it instead, on a new branch of its own (or --branch) (DL-149), where Duo's files are ordinary files (DL-259); nothing changes on GitHub. --sheet opens New project from GitHub filled in, for the user. Undo with `duo2 undo`.",
              ui: ["+ New project", "Create Project", "New Project…", "New Project from GitHub…", "Choose Folder…", "Make this folder the project"]),
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
        .init(.sessions, .sessions, "[--project <p>]", "Sessions with id, state, kind (terminal or chat), title and project. Text marks the project's director and the pinned (Keep Running) ones; --json adds \"director\": true, \"pinned\" and the row's \"section\" in the project pane: pinned, needs-you, open, tasks, later or other (DL-217, DL-218). A fork (a /branch or /fork) adds \"forkOf\" (its parent's id) and \"fork\": \"branch\" or \"fork\" (DL-228).", everyday: true),
        .init(.sessionShow, .sessions, "<id>", "A session's title, project, state, note, next step, transcript path and recent turns.", everyday: true),
        .init(.sessionNew, .sessions, "[--project <p> | --folder <path>] [--prompt <text>] [--name <name>] [--remote-control [name]]", "Start a Claude session in a project (the current one by default) or, with --folder, in a plain folder (Claude Code asks its own folder-trust question there, answered in Duo; Duo never writes trust). At All projects with neither, it starts where the New session row does: Home, else ~/Documents; with no such default it refuses and asks for --project or --folder. --name gives it a fixed name (claude -n), which survives restarts: a director's is director-<project> (DL-200). --remote-control makes it reachable from the Claude app, named <name> or its project and a short id, and keeps it on when the session resumes; a claude without the flag starts without it and the reply says so.",
              ui: ["+ New session", "+ New Claude Code session", "New Session", "console +", "New Claude Session", "New session pill, robot half", "Start Claude here", "Start Claude in Home", "Start in", "New session row", "New session row popup", "Choose Another Folder…"]),
        .init(.sessionOpen, .sessions, "<id>", "Show a session's terminal, resuming it if needed.", ui: ["session row", "console tab", "Home tab", "Resume", "Open Session"]),
        .init(.sessionClose, .sessions, "[id] [--force]", "End a session's process and close its tab (it stays listed and resumable). Refuses while Claude is working there, unless --force.", ui: ["Close Tab", "End Session", "Close"]),
        .init(.sessionPark, .sessions, "<id>… | --background", "Park a session (several ids park each that can; the rest say why): end its Claude process, keep its tab, and resume it when the tab is shown (it picks up where it left off). Refuses, saying why, while Claude is working or waiting on the user, is running something in the background or has a subagent running, or the session is set to Keep Running; a tab on screen first gives its pane to the next tab. --background parks every idle tab that isn't on screen and says what it kept and why.",
              ui: ["Park Session", "Park Background Sessions", "Park n Sessions", "Park Sessions"]),
        .init(.sessionKeepRunning, .sessions, "<id> [on|off]", "Keep a session running: it is never parked (by hand, in bulk or under memory pressure) and starts at launch instead of waiting to be shown. Turning it on wakes a parked tab. With no on/off it says whether the session is set.",
              ui: ["Keep Running", "pinned +"]),
        .init(.sessionMove, .sessions, "<id>… --to <project> [--new]", "File one or several sessions in another project, or with --new in a new project of that name made in Home; it moves there on its next resume. The user confirms in Duo. Undo with `duo2 undo`.",
              ui: ["Move to Project", "New Project…", "drag a session onto a tile"], timeout: 600),
        .init(.sessionNote, .sessions, "<text>", "Tell the user what this session is doing (one line, shown in Duo).", everyday: true),
        .init(.sessionNext, .sessions, "<text>", "Tell the user what this session needs next (one line).", everyday: true),
        .init(.sessionTask, .sessions, "[id]", "The task(s) a session is attributed to (this session by default): each note's title, status and path. Duo's hooks tell Claude the same when the session starts, resumes, clears or compacts, and what changed on its next prompt (DL-116)."),
        .init(.sessionCarryOn, .sessions, "<id>", "Start a new session carrying on from an archived one."),
        .init(.sessionFork, .sessions, "<id>", "Carry a session on as a fork: a new session with the same history (the original is left alone).",
              ui: ["Resume as a Fork"]),
        .init(.sessionTrustFolder, .sessions, "<id>", "When a session's /fork said \"Workspace not trusted\", or Claude Code asks at a session's start whether it trusts the folder: show Duo's sheet and wait for the user's answer. After a /fork, Yes sets only that folder's hasTrustDialogAccepted in Claude Code's file; at the start, Duo gives Claude Code the answer on its own screen. It prints `trusted <path>`, or fails with `cancelled` or `not trusted`. There is no --yes: Claude can ask, but can't trust a folder for itself (DL-229, F-444).",
              ui: ["Trust This Folder…", "Try Again", "Trust Folder", "Don’t Trust"], timeout: 600),
        .init(.sessionForkAgain, .sessions, "<id>", "After the folder is trusted: type the session's blocked /fork line again, only while Claude is at its prompt with nothing typed (DL-229).",
              ui: ["Fork Again"]),
        .init(.sessionLink, .sessions, "<session>", "A Markdown link to a session for a note or task: [title](duo2://session/<id>). Clicking it in Duo opens or resumes the session (DL-87).",
              ui: ["Copy Link", "Copy Markdown link"]),
        .init(.sessionArchive, .sessions, "<id>…", "File sessions away (one or several; several undo with one `duo2 undo`): it leaves the lists and counts, keeps its transcript, stays searchable, and sits in its project's Archived fold. Not while it runs. Undo with `duo2 undo`.",
              ui: ["Archive Session", "Archive n Sessions"]),
        .init(.sessionUnarchive, .sessions, "<id>…", "Bring archived sessions back into their projects' lists (several undo with one `duo2 undo`).", ui: ["Unarchive Session", "Archived fold", "Unarchive n Sessions"]),
        .init(.sessionDelete, .sessions, "<id>…", "Delete one or several sessions and their local logs for good (transcript, file history, environment; Duo's archived copy). The user confirms in Duo; several ids ask once, then the reply names any id skipped and why. A session running in one of Duo's terminals is ended first; one running outside Duo is refused.",
              ui: ["Delete Session…", "Delete n Sessions…"], timeout: 600),
        .init(.sessionChat, .sessions, "[id] on|off|toggle | --default last|chat|terminal | --home chat|terminal|last | answer [id] <option|level|cancel> [--session-only] | mode [id] [next|manual|accept-edits|plan|auto|bypass] | model [id] | effort [id] | why [id] | why --log",
              "Chat mode (DL-118 to DL-120): show a Claude session as a readable chat over its real terminal, or as the terminal. Switching sends nothing to the session. --default sets the mode new sessions open in (last: the one used last). --home sets the mode new Home sessions open in: chat unless set (DL-142), terminal, or last to follow --default (Settings › General, Home opens in). answer presses a review card's option key (1, 2, 3 …, or cancel for Esc) only after re-reading the screen; the same dialog must still be up. On /model's and /effort's cards (DL-143) it takes a row's number or a level (low, medium, high, xhigh, max), moves Claude Code's own cursor there and presses Return, or s with --session-only. mode presses Claude Code's shift+tab, once (next) or until its footer shows the mode named; the cycle is the installed claude's own. model and effort do what the model chip and the effort chip do (DL-168): send /model or /effort into Claude's prompt, only when the screen shows Claude idle with an empty prompt, so the card docks; answer then takes its row or level as above. On Switch model? and Change effort level? (Claude Code's question after a pick on a session with history) answer takes the option's number, or cancel. why prints the fallback bar's Debug report (DL-234): the rule that fired, the reader's verdict and evidence, the screen rows it judged, the Claude Code version, and the session's recent chat-state changes; it can hold private screen text, and nothing is sent anywhere. why --log lists the recent automatic fallbacks from logs/chat-fallbacks.jsonl in Duo's support folder. With no id, the session on screen.",
              ui: ["Home opens in", "Terminal", "Chat", "Back to Chat", "Debug", "review card option", "Cancel esc", "Amend in Terminal…", "Approve with Feedback in Terminal…", "Manage in Terminal…", "Chat about this", "‹ Back", "mode chip", "⇧⇥ in the composer", "picker card row", "effort level", "model chip", "effort chip", "Switch model? option", "Set as Default", "Confirm", "This Session Only", "Cancel"]),
        .init(.idle, .sessions, "", "Idle, resumable sessions, newest first, grouped by when (the map footer's list).", ui: ["idle footer"]),
        .init(.shellNew, .sessions, "", "Open a plain shell in the console (DL-8); typing `claude` in it makes it a session.", ui: ["New Shell", "New session pill, shell half"]),
        // Groups (DL-24): related threads, grouped by hand; Duo-owned facts in the project's .duo/sessions.json.
        .init(.tasks, .sessions, "[--project <p>]", "Task notes (tasks/*.md in each project) with their status and how many sessions their `sessions:` frontmatter links (DL-93). --json adds \"later\" (the pane lists it under Later: nothing in it for 3 days) and \"lastActivity\", when the note last changed (DL-217).", everyday: true),
        .init(.taskMake, .sessions, "<session>… | <group> [--title <t>]", "Make a Task: writes tasks/<slug>.md whose `sessions:` links the session (several sessions of one project make one task; or a group's sessions, and the group becomes the task) and opens it. Undo with `duo2 undo`.",
              ui: ["Make a Task"]),
        .init(.taskNew, .sessions, "[title] [--project <p>] [--status <s>] [--no-open]", "+ New task: a task note in tasks/ with no sessions yet, opened to write; use this, not a TASKS.md file. --no-open leaves the note closed (for making several); --status starts it at open, in-progress, waiting, review, done or dropped. Undo with `duo2 undo`.", ui: ["+ New task", "New Task"], everyday: true),
        .init(.taskSession, .sessions, "<task> [--project <p>]", "New Session in Task: starts a Claude session in the task's project with its link already in the note's `sessions:` list, and shows it when that project is open. Once Claude's prompt is up, Duo types `@tasks/<note>.md` into it and doesn't send it (DL-112): no turn is spent until someone adds a word and presses Return. Also the + on a task row's hover.",
              ui: ["New Session in Task"]),
        .init(.taskStatus, .sessions, "<task> <open|in-progress|waiting|review|done|dropped> [--project <p>]", "Set a task's status: rewrites only `status:` (and `completed:` when done or dropped). Done and dropped tasks leave the lists. Undo with `duo2 undo`.",
              ui: ["Set Status", "Mark Complete"]),
        .init(.taskAdd, .sessions, "<task> <session>…", "Add to Task: puts each session's link in the task note's `sessions:` list, touching nothing else in the note. Undo with `duo2 undo`.",
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
        .init(.taskBoard, .sessions, "[show|hide|toggle] [--project <p>]", "The task board (DL-148): a project's Sessions | Tasks switch. Tasks shows the board over the session list and console, lanes by `status`, and a card's note in the right pane. With no argument, says which is showing and lists the board's lanes and cards. Drag between lanes is `duo2 task status`.",
              ui: ["Sessions", "Tasks", "Board"]),
        .init(.taskColumn, .sessions, "<add|remove|move|keep> <name> [--after <column>] [--to <column>] [--left|--right] [--project <p>]", "A board's columns (DL-150): each is a `status` value, listed in the project brief's `lanes:` (written the first time the default five change, then edited in place). add: the name's slug is the status (Blocked → blocked), at the end or --after a column. remove: Open and Done can't go; a column holding tasks moves them --to another (without --to, Duo asks the user). move --left|--right. keep: an unlisted status found on tasks becomes a column. Undo with `duo2 undo`.",
              ui: ["+ Add Column", "Add Column After…", "Remove Column…", "Move Left", "Move Right", "Keep as Column", "Remove Column"], timeout: 600),
        .init(.taskReference, .sessions, "<add|remove> <task> <file|folder|url> [--title <t>] [--project <p>]", "A task's references (DL-150): its `references:` frontmatter, a list of quoted markdown links to files, folders (trailing /) and web links, relative to the note. Written only when one is added; nothing else in the note changes. With the note open in Duo, the change goes through the editor. Undo with `duo2 undo`.",
              ui: ["Remove from Task", "references field", "file dropped on a card"]),
        .init(.taskBase, .sessions, "[show|add|update] [--project <p>]", "The Obsidian board (DL-20, DL-148): add writes tasks.base beside the project's brief, a Bases kanban view grouped by `status` with groupOrder pinned to the project's columns (sorted by due, then created) and a table view; Obsidian 1.14.4+ shows the same board, and a drag there writes `status`. Never written unless asked, never over a base that's there. update rewrites only its groupOrder lines when the columns change. show: where it is and whether it's out of date. Undo with `duo2 undo`.",
              ui: ["Add Obsidian Board", "Update Obsidian Board", "Update"]),
        .init(.templateShow, .projects, "<project|task> [--project <p>]", "The template new projects or tasks are made from (DL-146): its text and whose it is (a project's own templates/new-task.md, Home's templates/new-<kind>.md, or Duo's base)."),
        .init(.templateEdit, .projects, "<project|task> [--project <p>]", "Open that template in the right pane with its template bar; with no file yet, Duo's base is written to Home's templates/ first.",
              ui: ["Edit Task Template", "Edit…"]),
        .init(.templateCopy, .projects, "task --project <p>", "Give a project its own task template: a copy of the one it uses now, in its templates/new-task.md, opened.", ui: ["Make a Template for"]),
        .init(.templateReset, .projects, "<project|task> [--project <p>]", "Home's template back to Duo's base, or (with --project) a project's own removed so Home's is used again. The file goes to the Trash. Asks first.",
              ui: ["Reset…", "Use Home's…", "Use Home's Template…"], timeout: 120),
        .init(.templatePreview, .projects, "<project|task> [--project <p>] [--title <name>]", "The file that template would make now, filled for a name (Preview in the template bar).", ui: ["Preview"]),
        .init(.groups, .sessions, "[--project <p>]", "Groups and their sessions, with each group's most urgent state."),
        .init(.groupNew, .sessions, "<name> <session>…", "Group sessions of one project under a name."),
        .init(.groupAdd, .sessions, "<group> <session>…", "Add sessions to a group."),
        .init(.groupRemove, .sessions, "<group> <session>…", "Take sessions out of a group (an empty group goes away)."),
        .init(.groupRename, .sessions, "<group> <new name>", "Rename a group."),
        .init(.groupDelete, .sessions, "<group>", "Ungroup: the group goes, its sessions stay."),

        // Files (paths are relative to the project, or absolute)
        .init(.files, .files, "[folder] [--project <p>] [--hidden]", "The project's files and folders, three levels deep; --hidden includes dotfiles."),
        .init(.filesBrowse, .files, "[up | back | <folder>] [--project <p>]", "Go up from the project's folder in the Files block (DL-106): `up` shows the parent folder, again for the next; `back` returns to the project's folder; a folder path shows that folder. Read-only: files there open as tabs, and can't be moved or trashed from the tree. With none, says what the tree shows.",
              ui: ["Show Parent Folder", "Back to Project Folder", "the Files path row"]),
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
        .init(.fileConvert, .files, "<docx> [--as <name.md>] [--replace] [--anyway] [--yes]", "Make a Markdown copy of a Word document beside it (<name>.md, pictures in <name>-images); the .docx isn't changed (DL-123). Headings, lists and layout tables are inferred and cleaned; tracked changes are kept as signed CriticMarkup suggestions and comments as signed threads, replies and resolved ones included (DL-236 12A). Prints what it inferred and what didn't come over. A taken name fails unless --as or --replace (the one there goes to the Trash); --anyway converts a document with no text. The copy opens in a tab of its own beside the Word viewer. The bar's Convert to Markdown… asks first, saying what won't come over; this verb never asks, and --yes (accepted for scripts) says so. Undo with `duo2 undo`.",
              ui: ["Convert to Markdown", "Convert to Markdown…", "Convert", "Convert Anyway"]),
        .init(.filePath, .files, "<path> [--relative | --link] [--copy]", "Print a file's path, relative path or Markdown link; --copy puts it on the clipboard.",
              ui: ["Copy Path", "Copy Relative Path", "Copy as Link"]),

        // Documents
        // GitHub (DL-149, DL-157): any project whose folder is in a git repository.
        .init(.repoStatus, .repo, "[--project <name>] [--copy] [--json]", "Where the project's repository stands, as the Files block shows it: branch, base, ahead and behind, changed files, the pull request, your access and whether the default branch is protected, and the line's one fact. Local state, plus what GitHub said at the last quiet fetch. --copy copies the branch name.",
              ui: ["Copy Branch Name"]),
        .init(.repoCheck, .repo, "[--project <name> | <owner/repo>]", "Whether the GitHub CLI is here and signed in (as whom), and what you can do in a repository: push, or read only (then pushes go to your fork), and whether its default branch is protected. Reads only.",
              ui: ["Try Again"], timeout: 30),
        .init(.repoLatest, .repo, "[--project <name>]", "Get Latest: bring in new commits on this branch from GitHub (merge, never rebase; your uncommitted files ride along). Stops at a conflict and says so.",
              ui: ["Get Latest", "Get Latest and Push"], timeout: 180),
        .init(.repoUpdate, .repo, "[--project <name>] [--from <branch>]", "Bring In Changes from the default branch (or --from), as GitHub's Update branch does: a merge, never a rebase.",
              ui: ["Bring In Changes from"], timeout: 180),
        .init(.repoPutBack, .repo, "[--project <name>]", "Put Back: undo a Get Latest that stopped at a conflict (git merge --abort). Your own changes are as they were.",
              ui: ["Put Back"]),
        .init(.repoPush, .repo, "[--project <name>] [--message <m>] [--files <f,…>] [--fork] --yes", "Commit the changed files (all, or --files) with the message, then push the branch (never forced). Publishes under the user's name, so without --yes it opens Duo's Push sheet for the user to confirm. --fork pushes to the user's fork (read-only access).",
              ui: ["Push…", "Push", "Push to GitHub…", "Fork and Push"], timeout: 600),
        .init(.repoPR, .repo, "[--project <name>] [--message <m>] [--title <t>] [--body <b>] [--draft] [--browser] [--fork] --yes", "Push and open a pull request into the default branch: with the GitHub CLI, or GitHub's own page filled in (--browser, or no CLI). Without --yes it opens Duo's Push sheet for the user to confirm.",
              ui: ["Push and Open PR", "Fork, Push and Open PR", "Push and Open in Browser"], timeout: 600),
        .init(.repoDraft, .repo, "[--message <m>] [--title <t>] [--body <b>]", "Fill in the open Push sheet's message, pull request title and description: how Claude answers Ask Claude to Write These. Doesn't push.",
              ui: ["Ask Claude to Write These"]),
        .init(.repoMoveToBranch, .repo, "<new branch> [--project <name>] --yes", "Move commits made on a protected branch to a new branch; the old one goes back to GitHub's only once the new one holds every commit. Then push it with `duo2 repo pr`.",
              ui: ["Move to a Branch…", "Move to a Branch and Push"]),
        .init(.repoSignin, .repo, "", "Sign in to GitHub: a shell tab running the GitHub CLI's browser sign-in (`gh auth login --web`, then `gh auth setup-git`). Duo never sees or keeps a token. Without the CLI, a shell tab with `brew install gh` typed.",
              ui: ["Sign In…", "Sign In in a Shell…", "Install in a Shell…", "Switch Account…"]),
        .init(.issueShow, .repo, "[<task|issue>] [--project <p>] [--refresh]", "The GitHub issue a task tracks (its `issue:` link, DL-226) and its state now: open or closed, labels, and why it can't be read without gh or access. <issue> is a URL, owner/repo#n or #n (the project's GitHub remote). With no argument, every task in the project that tracks one. Reads only.",
              ui: ["issue chip", "issue row", "Copy Issue Link"]),
        .init(.issueOpen, .repo, "<task|issue> [--project <p>]", "Open the issue on GitHub in the browser.", ui: ["Open Issue on GitHub"]),
        .init(.issueClose, .repo, "<task|issue> [--project <p>] --yes", "Close the issue on GitHub (`gh issue close`): the one change Duo makes to an issue besides reopening it. Needs --yes. Undo with `duo2 undo` reopens it.",
              ui: ["Close Issue", "Close #n too", "Close too"], timeout: 60),
        .init(.issueReopen, .repo, "<task|issue> [--project <p>] --yes", "Reopen the issue on GitHub (`gh issue reopen`). Needs --yes.", ui: ["Reopen Issue"], timeout: 60),
        .init(.issueNew, .repo, "--from-task <task> [--project <p>] --yes", "New Issue from Task: files the task as an issue in the project's GitHub repository, titled after it with its note's text as the body, and links it (`issue:`). Needs --yes (it publishes under the user's name); without it the user is asked in Duo. Undo with `duo2 undo` unlinks it; the issue stays on GitHub.",
              ui: ["New Issue from Task…"], timeout: 90),
        .init(.taskIssue, .sessions, "<task> <issue|--clear> [--project <p>]", "A task's issue link (DL-226): writes `issue:` with the full URL, quoted, by key (a task tracks one issue; the issue's state is read from GitHub, never copied into the note). <issue> is a URL, owner/repo#n or #n in the project's GitHub remote. --clear removes the link; nothing on GitHub changes. Through the editor when the note is open. Undo with `duo2 undo`.",
              ui: ["Link Issue…", "Change Issue…", "Unlink Issue"]),
        .init(.repoOpen, .repo, "[--project <name>] [--pr]", "Open the repository (its branch) or the branch's pull request on GitHub.",
              ui: ["Open on GitHub", "Open Pull Request #", "Open PR", "Open GitHub"]),
        .init(.docOpen, .docs, "<path> [--project <p>]", "Open a document in the right pane (Markdown in the editor, HTML as a page). A file outside every project opens as a tab in the project on screen (or --project).", ui: ["Open", "file row", "Open File…", "file dropped on the right pane", "Open CLAUDE.md"], everyday: true),
        .init(.docClose, .docs, "[path] [--others]", "Close a document tab (saved first), or every other one.", ui: ["Close Tab", "Close Other Tabs"]),
        .init(.docTabs, .docs, "", "The open document tabs, and which one shows."),
        .init(.docStatus, .docs, "<file>", "Whether a file is open in Duo's editor, unsaved or in conflict. Check before editing a file the user may have open.", everyday: true),
        .init(.docRead, .docs, "[path]", "A document's text as the editor has it (unsaved edits included); the showing document by default."),
        .init(.docSelection, .docs, "", "The text selected in the editor, with its file and lines."),
        .init(.docSelect, .docs, "<line> [to-line]", "Select lines in the showing document."),
        .init(.docSave, .docs, "", "Save the showing document now (it also autosaves).", ui: ["Save"]),
        .init(.docFormat, .docs, "bold|italic|strikethrough|code|link|heading1|heading2|heading3|task|properties",
              "Format the selection (bold, italic, strikethrough, code, a link waiting for its address), make its lines headings or tasks (again takes it off), or start the properties block.",
              ui: ["Bold", "Italic", "Strikethrough", "Code", "Link…", "Heading 1", "Heading 2", "Heading 3", "Task", "Add Properties"]),
        .init(.docTable, .docs, "insert|row-above|row-below|column-before|column-after|delete-row|delete-column|align-left|align-center|align-right|next|previous",
              "Edit the table at the caret as Markdown, its columns kept lined up: insert a 3 × 2 table, add or delete a row or column, align a column, or move to the next or previous cell (the last cell's next adds a row).",
              ui: ["Insert Table", "Add Row Above", "Add Row Below", "Add Column Before", "Add Column After", "Delete Row", "Delete Column",
                   "Left", "Center", "Right", "+ Row", "+ Column", "Align", "Delete"]),
        .init(.docFind, .docs, "<text>", "Find text in the showing document and select the next match.", ui: ["Find"]),
        .init(.docMode, .docs, "[source|preview|toggle]",
              "Show the document as its text (source) or rendered (preview), as View › Source Mode does; remembered per document. With nothing, says which it shows now (DL-167).",
              ui: ["Source Mode"]),
        .init(.docProp, .docs, "list | get <name> | set <name> <value> | remove <name> | type <name> <text|list|number|checkbox|date|datetime|link>",
              "The showing document's properties (frontmatter): read them, or change one line through the editor, highlighted as Claude's (DB-16). Lists: `set tags \"[a, b]\"`.",
              ui: ["Add a property", "property type menu", "Pick a date", "property checkbox"]),
        .init(.docMarkup, .docs, "[all|simple|none|original] [--comments on|off] [--show-resolved on|off] [--person <name>|everyone]",
              "On a Markdown document: the same modes for its suggestions and comments, with --show-closed on|off for closed threads (DL-237). The Word document showing: which markup its viewer draws, and change it, as the Markup menu does (DL-162). All Markup draws every change in its person's colour with the comments; simple accepts the changes and marks the margin where one was; none accepts them with no marks; original shows the text before them. --person shows only that person's marks. Kept per document while Duo runs. With nothing, says what it shows now and who is in the document.",
              ui: ["Markup", "All Markup", "Simple Markup", "No Markup", "Original", "Show Comments", "Show Resolved Comments", "Show Closed Comments"]),
        .init(.docReview, .docs, "[on|off|next|previous]",
              "The Markdown document's Suggest Edits switch (DL-237): on, every change anyone makes becomes a signed suggestion; kept in the file as `suggest-edits: true` in its frontmatter, written only while on. With nothing, says which it is. next and previous select the next or previous suggestion or comment in the document (the review bar's ‹ ›). Edit › Suggest Edits does the same as on and off.",
              ui: ["Suggest Edits", "Next Change", "Previous Change"]),
        .init(.docOutline, .docs, "<file.docx> [--json]",
              "A Word document's paragraphs, read from the file (no viewer needed): each with its w14:paraId (the id the viewer draws it under), style and heading level, its text with the tracked changes accepted, its tracked changes (kind, author, date, text) and the comments that end in it (thread, resolved). Then every comment thread. A picked paragraph's Send to Claude names the same ids."),
        .init(.docLayout, .docs, "<file.docx> [--json]",
              "A Word document's geometry, read from the file (no viewer, no renderer): each section's page size, orientation and margins, so its text width; each table's declared width and column widths against the room it has (the text width, or its cell's); each picture's size; and a warning for anything wider than its room, a percentage table width, or a width that disagrees with its columns. Sizes in points. No page numbers. Only a document open in a Duo tab or inside the session's project folder (C-115)."),
        .init(.docScreenshot, .docs, "[<file>] [--all] [--width <px>]",
              "Save PNGs of a document as Duo's viewer draws it and print their paths: the Word document named (or showing) at the pane's width, 460 px unless --width says otherwise (320–1600), tables at the document's own column widths. Without --all, the top of it (up to 1600 px); with --all, the whole document in 1600 px pieces, numbered. A Word document needn't be showing: Duo draws it out of sight, and the user's view doesn't change. A Markdown preview or a slide deck is captured only while it is showing. The PNGs go in .duo/screenshots/ in the session's folder. Only a document open in a Duo tab or inside the session's project folder (C-115).", timeout: 60),
        .init(.docPick, .docs, "[<paragraph id> | c:<comment id>]",
              "Start Select Text in the Word document showing, for the user to click a paragraph or a comment, or select the paragraph (its w14:paraId from `doc outline`) or comment (`c:<id>`) named.",
              ui: ["Select Text"]),
        .init(.docElement, .docs, "[<paragraph id> | c:<comment id>]",
              "Describe a paragraph or comment of the Word document showing (the picked one by default) as Send to Claude would send it: where it is, its text with changes accepted, its tracked changes and comments."),
        .init(.docComments, .docs, "[--resolved | --closed]",
              "The comments of the document showing. A Word document: from what its viewer drew, with author, date, text, replies and whether each is resolved (--resolved: only those). A Markdown document: its threads, read from the text as the editor has it, with author, date, text and replies; closed threads are left out unless --closed (DL-237)."),
        .init(.docInsert, .docs, "<text> [--line <n>]", "Insert text into the showing document through the editor (highlighted as added by Claude), at a line or the caret."),
        .init(.docReplace, .docs, "<find> <replacement>", "Replace text in the showing document through the editor (highlighted as added by Claude)."),

        .init(.docRevert, .docs, "[--all | --line <n>]", "Put back what Claude changed in the open document: the change at the caret or a line, or all of them since the user's last edit (ENH-4).",
              ui: ["Revert This Change", "Revert All of Claude's Changes", "Revert Claude's Change"]),
        .init(.docEdit, .docs, "--stdin", "Apply an Edit-tool-shaped change ({file_path, old_string, new_string, replace_all} or {file_path, edits} or {file_path, content}, as JSON on stdin) to a document open in Duo, through the editor, highlighted."),

        .init(.docResolve, .docs, "mine|theirs", "End a conflict in the showing document: keep the user's text (saved over the file) or take the file's. The other version stays in history. Only when the user asks.",
              ui: ["Keep Mine", "Use Theirs"]),
        .init(.docHistory, .docs, "[path]", "Versions Duo kept of a document (as opened, both sides of conflicts, before removal), newest last, with where each is stored."),


        // Review in Markdown (DL-236, DL-237): comments and suggestions as signed CriticMarkup. A file open in Duo's editor is changed through the
        // editor (as Claude's change); any other file on disk. Run from a Claude session the author is `claude`, else the user's Mac name; --as names one.
        .init(.commentAdd, .review, "<file> --at <line|text> [--as <name>] <text>",
              "Comment on a line (its number) or on a text that appears once: the text becomes a highlight and the signed comment follows it. A comment that names @claude is addressed to a session (`duo2 comment send`).",
              ui: ["Add Comment"]),
        .init(.commentList, .review, "<file> [--closed | --unsent]",
              "The file's comment threads: id, who and when, the text it is on, the comment and its replies. Closed threads are left out unless --closed (only those); --unsent lists the open ones that name @claude and have no reply."),
        .init(.commentReply, .review, "<id> <text> [--file <file>] [--suggest] [--as <name>]",
              "Reply in a thread (or to a suggestion) with the next number, `#c1.2`; a closed thread reopens. --suggest instead proposes the reply text as a replacement of the text the thread is on. Never rewrites anyone's comment. Without --file, the document showing."),
        .init(.commentSend, .review, "<id | --all> [--file <file>] [--to <session> | --new]",
              "Send a comment that names @claude to a session, quoted as data, when the person says to (DL-236 10): the turn is pasted and Returned through the idle-and-empty-prompt guard of `director send`, or waits (Queued) until the session is ready. Without --to, the thread's session, the document's last choice, the last to edit it through Duo, then the one on screen. --all sends every @claude comment not yet sent or answered. Never sent from the file on its own."),
        .init(.commentClose, .review, "<id> [--file <file>] [--as <name>]",
              "Close and Keep: add a closing line `{>>@name date #c1.2 closed<<}` after the thread's last comment; the highlight and comments stay (Q-262).",
              ui: ["Close and Keep"]),
        .init(.commentDelete, .review, "<id> [--file <file>]",
              "Delete the thread: its highlight markers and every comment go, the text stays."),
        .init(.commentReopen, .review, "<id> [--file <file>]",
              "Reopen a closed thread: its closing line goes.", ui: ["Reopen"]),
        .init(.commentStatus, .review, "<id> [--file <file>]",
              "One thread: open or closed, who is in it, whether it names @claude, whether Claude has replied, and where its delivery stands: not sent, queued, sent, replying, replied or not delivered, with the session."),
        .init(.suggestionList, .review, "<file>",
              "The file's suggestions: id, kind (insertion, deletion, substitution), who and when, the text."),
        .init(.suggestionAccept, .review, "<id | --all> [--file <file>] [--person <name>]",
              "Accept a suggestion: the change is made and its mark goes (--all: every one, or one person's). The person's call: only when they ask.",
              ui: ["Accept", "Accept All", "Accept All from"]),
        .init(.suggestionReject, .review, "<id | --all> [--file <file>] [--person <name>]",
              "Reject a suggestion: the text stays as it was and its mark goes. The person's call: only when they ask.",
              ui: ["Reject", "Reject All", "Reject All from"]),

        // HTML pages
        .init(.browserOpen, .html, "[url]", "A browser tab in the right pane (⌥⌘T). Sites not on the allow list show Allow or Open in Browser instead of loading (DL-3).",
              ui: ["New Browser Tab", "Open Location…", "Open in Browser", "Copy Address"]),
        .init(.browserAllow, .html, "<host>", "Ask the user to add a site to the allow list, so its pages open in Duo's browser tabs (and its subdomains). The user answers on a Duo sheet."),
        .init(.browserSites, .html, "", "The allow list: sites Duo opens in its own browser tabs; everything else opens in the system browser (DL-3).", ui: ["Edit…"]),
        .init(.browserTabs, .html, "", "Browser tabs open in Duo: id, project, title, address."),
        .init(.browserRead, .html, "[selector] [--tab <id>]", "The page's text (or one element's), with its title and address (LR-45). Allowed sites only."),
        .init(.browserClick, .html, "<selector> [--synthetic] [--tab <id>]", "Click the element a CSS selector names, scrolled into view: real mouse events at its centre, which apps like Google Docs need (DL-124). --synthetic sends element.click() instead (also used when the tab isn't on screen)."),
        .init(.browserFill, .html, "<selector> <text…> [--tab <id>]", "Type into an input, text area or editable element, as a person would (input and change events)."),
        .init(.browserWait, .html, "<selector> [--timeout <s>] [--tab <id>]", "Wait for an element to appear (default 10 s)."),
        .init(.browserScreenshot, .html, "[--full-page] [--tab <id>]", "Save a picture of the visible page as a PNG and print its path. --full-page takes the whole page top to bottom, scrolling and joining the pictures (up to 20000 px tall, then it says it stopped); the page is left where it was."),
        .init(.browserScroll, .html, "<top|bottom|up|down|<pixels>|<selector>> [--tab <id>]", "Scroll the page: to the top or bottom, up or down by a screen, by a number of pixels (negative goes up), or to the element a selector names. Says where the page is now, out of how tall."),
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
        // Voice input (DL-260): Apple's on-device recognizer; words land in the prompt, never sent
        .init(.voiceStart, .send, "[<id> | shell]", "Start voice input in a session (the one showing by default): words go into its chat composer, or its terminal prompt a phrase at a time; Return is never pressed. Needs the user to have allowed the microphone in Duo; never asks in a scripted or isolated Duo.",
              ui: ["Start Voice Input", "Voice Input"]),
        .init(.voiceStop, .send, "[<id> | shell]", "Finish voice input: the last phrases land, nothing is sent.", ui: ["Stop Voice Input"]),
        .init(.voiceStatus, .send, "[<id> | shell]", "Whether voice input is listening, downloading Apple's speech model, or off, and why."),
        .init(.voiceFile, .send, "<audio file> [<id> | shell]", "Feed an audio file (absolute path or ~) through voice input into a session's composer or prompt, as if spoken. The scripted twin of the mic; never touches the microphone.", timeout: 180),
        .init(.selection, .send, "", "What the user has selected or picked right now, in the editor or an HTML page.", everyday: true),

        // Director (DL-193 to DL-206): the exact parts of the duo-director skill. Each writes a line to
        // the project's .duo/director-log.jsonl, which the director's metrics are counted from.
        .init(.directorStatus, .director, "[--project <p>]", "Who directs this project (and whether you're its director, or one it replaced), its workers and their tasks with each one's state, the rules to read (the Director sections: Home's _HOME.md, then the project's _PROJECT.md), and what this Claude client can do: messaging, background sessions, Remote Control, hooks, Monitor. Works with Duo closed, from Claude's own files (DL-231)."),
        .init(.directorStart, .director, "<task> | --title <t> --request <the user's words> [--done-when <text>] [--suggest | --no-worker | --worker <session id> [--adopt]] [--adopt] [--in-duo] [--background] [--take-over] [--project <p>]",
              "Start a worker on a task this director directs (DL-194, DL-201): writes directed_by:, ## Request and ## Progress, then starts the worker in the background (`claude --bg`, with Remote Control) by default: it prints the command to run, and the worker is linked by its name when it starts. --in-duo starts it in Duo instead; so does a client without background sessions. Workers are reached by SendMessage, not by Duo (DL-257). --worker links an existing session; --background asks for the default explicitly. --suggest files it as suggested with no worker; --no-worker makes it a task the director does itself (organising work, DL-208). Refuses a task another director directs, and a project another director runs (--take-over replaces it; alone, it records a resumed director). A task or session of the user's needs --adopt: Duo then asks the user, and goes ahead only if they allow it.",
              timeout: 600),
        .init(.directorSend, .director, "<task> <message> [--handed-back] | --director <project> <message>",
              "Reach a task's worker (or, from Home, a project's director) the best way this client has, and log which (DL-199, DL-257): a live worker gets your own SendMessage (this prints the call; Duo can't make it for you, and it is held if your permission class and the worker's differ); a stopped background worker is resumed with the message (`claude --bg --resume`, no other flags); a stopped worker in Duo is reopened with it; else the user passes it on. Nothing is typed into a terminal. Every send goes into the task's ## Progress. A worker the user typed in is paused (DL-200): --handed-back makes Duo ask the user to hand it back. With Duo closed, the rungs that need it are left out, and --handed-back records the user's word in your own session (DL-231).",
              timeout: 600),
        .init(.directorRetire, .director, "[--project <p>]", "Stand this director down: .duo/director.json moves it to the retired list, and if it wakes later it's told to stop. Its workers stay on their tasks until a new director takes over. Works with Duo closed."),
        .init(.directorGuide, .director, "", "Print the duo-director skill, for a Claude client where personal skills are blocked.", local: true),
        .init(.directorWatch, .director, "[--project <p>] [--every <seconds>]", "One line per change to this director's workers (finished, needs you, working, stopped) or their task notes, until stopped: run it under Monitor to be woken (DL-199). It watches without Duo too (DL-231).", local: true),

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
        "Explain Tasks": "Help › Explain Tasks shows an explanation to a person at the screen (DL-172); `duo2 task new` is the action it explains",
        "Close Window": "window management",
        "@ menu in a margin comment": "input help while typing a comment (DL-251): it inserts the text `@claude`, and `duo2 comment add`/`reply` take that text as typed",
        "About Duo": "the standard macOS About panel, whose credits list the third-party notices (DL-176); system UI for a person at the screen",
        "Paste or drop a picture in the editor": "a gesture, not a menu item: the picture is saved beside the document and linked (LR-39); `duo2 doc insert` adds the same `![](name)` text, and `duo2 file move` puts a picture beside a note",
        "Anyone": "the task board's owner filter: view state; `duo2 task board` lists every card",
        "Me": "the task board's owner filter: view state; `duo2 task board` lists every card",
        "Enter Full Screen": "window management",
        "Exit Full Screen": "window management",
        "Toggle Right Pane": "not built yet",
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
        "Resolve…": "drafts the conflict's instruction into the project's Claude session, unsent (DL-149 board 11); the user presses Return. Claude is already the one resolving",
        "Ask Claude to Combine": "drafts the conflict's instruction into the project's Claude session, unsent (DL-149 board 11)",
        "Ask Claude to Remove It": "drafts an instruction about the refused secret into the project's Claude session, unsent (DL-149 board 10)",
        "Show the File": "opens the conflicted file, as `duo2 doc open` does",
        "Show Details": "dismisses a failure question whose details are already shown",
        "Save to Recreate": "writes the user's own text back after the file was removed on disk; Claude can do the same with `duo2 doc edit` (content) once the user asks",
    ]
}

// MARK: - Arguments

/// A parsed command line after the verb: positionals and `--flags` (`--flag value` or `--flag`).
public struct Invocation: Sendable {
    public var positional: [String] = []
    public var flags: [String: String] = [:]

    /// Flags that take no value.
    public static let switches: Set<String> = ["fork", "draft", "browser", "pr", "sheet", "use-folder", "json", "yes", "replace", "keep-both", "relative", "link", "copy", "others", "new", "markdown", "exact", "all", "full-page", "session", "open", "sessions", "keep-sessions", "synthetic", "resolved", "force", "session-only", "left", "right", "hidden", "anyway", "not-now", "no-interview", "cancel", "fetch", "background", "in-duo", "suggest", "closed", "unsent", "take-over", "handed-back", "no-worker", "adopt", "clear", "refresh", "no-open", "log", "add"]

    /// Flags whose value is optional: the next word is theirs unless it's another flag.
    public static let optionalValues: Set<String> = ["remote-control"]

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
    /// `sessionID` and `cli` (DL-256) add the session's `DUO_SESSION_ID` and the full path of its `duo2`,
    /// which a `/fork` copy inherits with the rest (the daemon gives it none of Duo's environment, C-110).
    /// No socket or token: `duo2` finds the running Duo through its endpoint file.
    public static func primer(sessionID: String? = nil, cli: String? = nil) -> String {
        var text = "You are running inside Duo, a Mac app that organizes the user's Claude Code sessions into projects and shows their documents. "
            + "The `duo2` command talks to Duo; it is on PATH and needs no approval. Everything the user can do in Duo, you can do with it "
            + "(`duo2 help`, then `duo2 help <family>`: " + ActionFamily.allCases.map(\.rawValue).joined(separator: ", ") + "). Everyday:\n"
            + all.filter(\.everyday).map { "- `\($0.usage)`: \($0.summary)" }.joined(separator: "\n")
            + "\nFor questions across projects, or about meaning rather than exact text, run `duo2 search \"<question>\"` before grep or reading folders. "
            + "Read only the lines it points to. Its scores only compare results within one search. Use `--exact` for identifiers."
            + "\nWhen the user says \"this\", \"here\" or \"what I selected\", run `duo2 selection` first."
            + "\nDocuments the user has open in Duo (`duo2 status` shows them) are theirs to see change: edit them with "
            + "`duo2 doc edit --stdin`, piping the JSON your Edit tool takes ({\"file_path\",\"old_string\",\"new_string\"}, or {\"file_path\",\"content\"} to rewrite), "
            + "not with Edit, Write or shell redirection. Duo applies it in the editor the user is looking at, highlighted, and merges it with their unsaved typing."
            + "\nTo check a Word document you made, fit the check to where it goes (for Google Docs, structure, not pixels): `duo2 doc outline` and `duo2 doc layout` (page and text width, tables and pictures against it), and `duo2 doc screenshot` to see it; the duo2 skill's \"Checking documents\" says more. Don't start soffice in the sandbox."
            + "\nTo track work, make Duo tasks (`duo2 task new`, one note each in the project's tasks/ folder) and set their status with `duo2 task status`; do not write a TASKS.md or a to-do list file."
            + "\nWhen you start substantial work, `duo2 session note \"<one line>\"`; when you hand back, `duo2 session next \"<one line>\"`."
        if let sessionID {
            let path = cli.map { "`\($0)`" } ?? "`duo2`"
            text += "\nIf `DUO_SESSION_ID` is empty in your shell (a /fork copy), run duo2 as `DUO_SESSION_ID=\"${CLAUDE_CODE_SESSION_ID:-\(sessionID)}\" \(cli ?? "duo2") …` so Duo knows which session is calling"
                + (cli != nil ? "; \(path) is the full path to duo2, for when it isn't on PATH." : ".")
        }
        return text
    }
}
