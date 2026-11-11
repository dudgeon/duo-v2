# A new user's first-use feedback, and how Claude learns it is inside Duo

Research only, 2026-11-11. Nothing is built. Records: F-660 to F-662, Q-510 to Q-514, ENH-343 to ENH-345.

Aram, a Duo user, sent Geoff first-use feedback. In short: the onboarding is too thin for how much Duo does (he doesn't know how to start director mode, or how tasks differ from sessions); he can't tell why Duo is sometimes a white, IDE-like window and sometimes a terminal; he wants the file list to fold, the right side to hide, and file names in Claude's replies to be clickable and open on the right; and the menu says "Window Colour".

## Summary

Most of what he asked for exists, and he couldn't find it. Three things explain nearly all of it:

1. **A new user's sessions open in the terminal.** Chat mode is where replies are formatted and file names are links that open on the right. A new install starts every project session in terminal mode until the user finds a small pill on the tab, so a new user gets the "terminal wrapper" with no clickable files. Home's session opens in chat, which is the "white" Duo he sometimes saw.
2. **The app teaches almost nothing.** There is no welcome, the Help menu doesn't link to the guide or the films, one feature (Tasks) has an explainer, and the director has no button, no menu item and no page in the guide.
3. **Claude is already told it is inside Duo**, at every session start, in a better way than Legacy Duo did it. What it isn't told is how to show a file. It doesn't need to be told how to write a file name: in the test below, Claude wrote paths the way Duo's chat already links them, with and without an instruction. The misses are in Duo's link rule, not in Claude's habits.

Recommendations, in the order I'd do them:

| | Decision | Recommendation |
|---|---|---|
| Q-510 | Which mode does a new user's first session open in? | Chat, for new installs. Existing users keep "the mode used last". |
| Q-511 | What onboarding to build first? | The cheap layer now (Help links to the guide and films, guide pages for the director and the two modes, three more explainers on the approved component); a designed first-run welcome as the next canvas round. |
| Q-512 | How does a user start the director? | A menu item, Project › Start Director, on the verb that already exists, plus the explainer. A drawn slot in the sidebar goes to the canvas round. |
| Q-513 | What more does Duo tell Claude? | One line: to show the user a file, `duo2 doc open`. No per-mode text and no file-name convention; fix the link rule in Duo and make the terminal's ⌘-click open in Duo. |
| Q-514 | "Window Colour" or "Window Color"? | American spelling in the app's own words: "Window Color". `duo2 window colour` stays as an alias. |

No decision needed, recommended as builds: the link fixes (ENH-343), the pane controls (ENH-344), the teaching items (ENH-345).

## 1. Per item: what is true today

Read in the code at `d8656529` unless a line says it was run.

### 1.1 "Sometimes white full IDE, other times a terminal wrapper"

**True today.**

- Every Claude tab can show as **Terminal** (Claude Code's own screen, always dark: `console` is #15171B even in light appearance) or **Chat** (a light grey ground with white cards). The two look like different apps. The appearance setting (Match System, Light, Dark, Classic) doesn't choose between them.
- How the mode is chosen (`Chat/ChatSession.swift:21-47`, DL-119, DL-120, DL-142):
  1. A session that has been switched keeps its own mode, across `/clear` and `/resume`.
  2. A new session in a project opens in **the mode used last, which starts as terminal**. One click on Chat and every later new session opens in chat.
  3. Home's session opens in **chat** (Settings › General has "Home opens in").
  4. `duo2 session chat --default last|chat|terminal` fixes the default for project sessions. Settings has no row for it.
  5. A chat session **falls back to the terminal** by itself when chat can't read the screen: a sign-in, a command with its own screen (`/usage`, `/config`), a dialog on a Claude Code version chat wasn't checked with. A bar above the terminal says why ("Chat mode can't show this screen, so here's the terminal.") with Back to Chat. The fallback stays until the user goes back (DL-154, DL-235).
- What tells the user: a pill, "Terminal | Chat", on the selected Claude tab after its name (DL-253); a glyph on the sidebar row (DL-174). The pill has no tooltip, there is no menu item and no shortcut, and nothing in the app says what the two are. The guide explains it (`docs/guide/sessions.md`, "Chat mode"); the app doesn't link to the guide.

**What he most likely saw** (inferred; not checked against his Mac): Home, or any session after he had clicked Chat, as the "white" Duo; new project sessions, and any fallback, as the "terminal wrapper". With the document pane open and chat showing, Duo is a light three-pane window; with the pane hidden and the terminal showing, it is a terminal with a sidebar.

**Root cause.** The default splits by place (Home chat, projects terminal), the switch is a small unlabeled pill, and nothing explains it. An earlier triage note found the same gap from another report: a user "may not know chat mode exists" (`docs/research/issues-triage-2026-10-19.md`). Geoff has hit the fallback half himself (DL-234: "it is not clear why").

**Options.**

- A. **New installs open project sessions in chat** (recommended, Q-510). The setting stays "the mode used last"; only its starting value changes, and only where no `chat.json` exists yet, so nobody's current behaviour changes. The first thing a new user sees is the formatted conversation with clickable files, and the pill is then the way *out* to the terminal for those who want it. Risk: chat falls back to the terminal on an unverified Claude Code version, so a user on an odd version sees more fallbacks; the bar already explains each one. The work Mac's pinned 2.1.284 is a verified 2.1.x.
- B. Keep terminal first, and teach: a tooltip on the pill, a Session menu item ("Show as Chat" / "Show as Terminal"), an explainer. Cheaper to reason about, but a new user still starts in the mode without links.
- C. Ask on the first session ("Chat or Terminal?"). A question before any value; needs a design.

Whatever is chosen for the default, B's teaching parts are worth building (they are in ENH-345): the pill gets a tooltip, the Session menu gets the item (DL-71 wants every action reachable; the verb `duo2 session chat` exists), Settings gets the "New sessions open in" row beside "Home opens in".

### 1.2 "The left nav should let me expand and contract the file list"

**True today** (`Project/ProjectPanes.swift`).

- A project's left pane is the sessions list over a Files tree.
- **Folders fold**: a click on a folder opens or closes it; folders start closed (DL-105, F-81). `duo2 view folder <folder> open|close`.
- **The Files section as a whole does not fold.** Its header is a plain "Files" label with the branch; no chevron (`ProjectPanes.swift:493-540`). Session groups above it do have chevrons (`duo2 view group <id> expand|collapse`).
- **Which folders are open is not remembered** over a relaunch (`expandedFolders` is in memory only).
- The whole sidebar hides: View › Toggle Sidebar, ⌃⌘S, the toolbar button, a drag, `duo2 view sidebar`.
- No decision says the Files section must not fold, and no record asks for it.

**Root cause.** Two readings fit his words: he wants to fold the Files section away to give the sessions the height (not possible today), or he didn't find that folders fold (possible, but the state is lost at relaunch, which reads as "it doesn't stick").

**Recommendation** (ENH-344, no decision needed beyond a mark on a board): a chevron on the Files header, the same one the session groups use, with `duo2 view files expand|collapse`; remember it and the open folders per project. The header chevron isn't drawn on any screen, so it is built as a stand-in on the session-group chevron and gets a [P] mark on the next canvas round.

### 1.3 "Right nav should be hideable"

**True today.** It is: the button at the toolbar's right end (tooltip "Hide Right Pane ⌥⌘0"), ⌥⌘0, dragging the divider, `duo2 view right show|hide|toggle` (DL-129). Opening a document shows it again. The state is saved.

**The gap:** the View menu has Toggle Sidebar and **no item for the right pane** (`Navigation/Commands.swift:466-469`; the comment says it was "left out until they work", and it has worked since DL-129). A user who looks in the View menu, where every Mac app keeps this, finds nothing. The toolbar button is an unlabeled icon.

**Recommendation** (ENH-344): View › Hide Right Pane / Show Right Pane, ⌥⌘0, under the sidebar item.

### 1.4 "Make file names and links Claude passes back clickable, and show up on the right"

**True today, chat mode.** Already built (`Chat/ChatMarkdown.swift:146-173`, `Chat/ChatToolViews.swift:461-470`, DL-132 g):

| Claude writes | Chat mode | Terminal mode |
|---|---|---|
| `docs/plan.md`, `src/app.py:42`, in code or plain | A link. Opens in the right pane, at the line; shows the pane if hidden. | ⌘-click only. Opens in the Mac's default app, no line, resolved against Duo's own folder, so a relative path usually fails. |
| `/Users/…/plan.md`, `~/notes/a.md` | A link, as above (a file outside the project opens as its own tab, DL-106). | ⌘-click opens the default app. |
| `https://…` or `[x](https://…)` | A link. An allowed site opens in a Duo browser tab, others in the browser (DL-3). | ⌘-click opens the browser. |
| `[x](docs/plan.md)` | A link. Opens in the pane, resolved against the project folder, not the session's folder; `:line` ignored. | Shown as typed. |
| `[x](file:///…)` | A link, but **opens the default app**, not Duo. | ⌘-click, default app. |
| a path with a space, `Meeting Notes/kickoff.md` | **Wrong link**: only `kickoff.md` is linked, to a file that isn't there; the click does nothing, silently. | Not a link. |
| `Makefile`, `.env`, `notes.mdx` (no extension, or one not on the list) | **Not a link** unless it has a slash. | Not a link. |
| a file that doesn't exist | A link that does nothing, no message. | The same. |
| the file names on Edit, Read and Write rows | Links. Open in the pane. | Not applicable. |
| `duo2://session/…`, `duo2://task/…` | Links. Go to the session or task. | Not handled. |

**True today, terminal mode.** Duo adds nothing. The terminal view's own behaviour applies (`Terminal/Terminals.swift:846` forwards to the library's default): ⌘-click on a web address, a link Claude Code marks itself, or a path that exists opens it with the Mac's default app. Nothing opens in Duo's pane. No check covers it. Not run: whether Claude Code 2.1.316's own screen marks file names as links.

**Root cause.** He was almost certainly in terminal mode (1.1), where none of this exists. The feature he asked for is built and he never saw it. Behind that, chat's link rule has real holes (spaces, no extension, `file://`, silent misses), and the terminal has no Duo link handling at all.

**What Claude actually writes** (run: four Haiku 5.5 turns, Claude Code 2.1.316, a scratch project and config, F-662). Asked where things are, Claude wrote every file as a path from the project folder inside backticks, with `:line` where it knew one, **with no instruction at all**. Replaying chat's link rule over the replies: `src/app.py:4`, `docs/plan.md`, `config.json` linked and resolved. `Makefile` and `Meeting Notes/2026-11-02 kickoff.md` did not. Adding an instruction (use a Markdown link for a path with spaces or no extension) **changed nothing**: Haiku kept the backticks. So the convention Duo wants is the one Claude already has, and the misses can only be fixed in Duo.

**Recommendation** (ENH-343):

1. **Chat: a code span that names a real file is a link, whole.** Claude puts paths in backticks, so the span's edges are known: if its text (less a `:line`) is a file that exists under the session's folder or the project, link all of it. This fixes spaces and missing extensions with no guessing, because existence is the test.
2. Chat: `file://` links, and the plan card's "Open plan in Duo", open in the pane; a Markdown file link resolves against the session's folder first and honours `:line` and `#L42`; a click on a missing file says so.
3. **Terminal: ⌘-click opens in Duo.** Route the terminal's open-link request through the same code as chat: a path resolves against the session's folder and opens in the right pane at its line; a web address follows Duo's link rule. This is the "terminal mode second" half, and it is small: one delegate method.
4. Checks for all of it (`ChatChecks`), since today one check covers four cases.

### 1.5 "Window Colour" in the menu

**True today.** The app says "Window Colour": Window › Window Colour, the toolbar swatch's tooltip, the popover's title, "Colour new windows automatically", and the verb `duo2 window colour` (`Shell/WindowViews.swift`, DL-312, DL-314). These six strings are the only place the app's own words use either spelling. The repo's prose leans British (decisions.md: 15 "colour", 2 "color"). No record sets a house spelling. Geoff's own words in DL-312 and ENH-319 are "colors".

**Root cause.** The strings were written in the docs' spelling. On a Mac set to US English every system menu beside it says "Color" (Show Colors, the colour picker), so "Colour" reads as a typo to a US user.

**Options** (Q-514).

- A. **American in the app's own words** (recommended): "Window Color", "Color new windows automatically"; `duo2 window color`, with `colour` kept as an alias so nothing breaks. Docs and code stay as they are. Record it as the house rule: the app's words follow US English, as macOS's own do.
- B. Keep "Colour". Consistent with the repo's prose; odd beside the system's menus.
- C. Localize (en-GB and en-US). Correct, and far more machinery than six strings deserve today.

## 2. Onboarding

### 2.1 What exists

- **First launch:** Duo opens on All projects with every Claude Code session on the Mac already listed. No welcome. Then one sheet, "Let Claude sessions outside Duo use it?" (installs the `duo2` command and two skills), and possibly two more about skill names and Legacy Duo. With no projects, All projects lists Home's folders with Make a Project (DL-212, a stand-in, Q-197).
- **In the app:** the Help menu has duo2 Reference, What's New in This Version, Explain Tasks, and Report an Issue. One explainer exists, for Tasks (DL-172): a popover after a long hover, three points, its "Learn more" hidden because it had no page to open (Q-177; the guide's tasks page has existed since). The empty task board says what a task is. Tooltips name the buttons.
- **Outside the app:** the README, a ten-page guide (`docs/guide/`: sessions, projects, tasks, where a session belongs, Home, topics, documents, what needs you, getting around, plain files), the intro film (9 min 34 s, v0.2.26) and the director film (6 min 47 s, v0.2.13). **The app links to none of them.**
- **The director:** a session, usually named `director-<project>`, that takes requests, makes a task for each, starts workers and checks what comes back. It starts when the user types "be the director" or `/director` in a session, which runs the installed skill, which runs `duo2 director start`. There is no button and no menu item, and **the guide has no page on it**; the film is the only explanation.
- **Tasks and sessions:** explained in `docs/guide/tasks.md` and the empty board. A session is one conversation with Claude; a task is an optional note that gathers the sessions working on one piece of work.
- **v1 scope** (build plan §3a) has no onboarding; DL-147 chose a getting-started explainer over a sample project; ENH-33 is the sample project, not scheduled.

### 2.2 Root cause

Duo was built for one user who watched it being made. Every feature has a `duo2` verb and most have a guide page, but the app never points at them, and the two features he named are the two with the least: the director (nothing in the app, nothing in the guide) and tasks (one explainer, reachable only inside a project's Tasks).

### 2.3 Options, cheapest first

| | What | Cost | Needs design? |
|---|---|---|---|
| A | **Help menu points at what exists:** Duo Guide, Watch the Intro Film, Watch the Director Film; the Tasks explainer's Learn more opens the guide's tasks page (closes Q-177). | Hours. | No: menu items and links. |
| B | **Fill the guide's holes:** a Director page (what it is, how to start one, what the sidebar slot shows), a "Chat and Terminal" section that says why Duo falls back, a "Tasks and sessions" opener on the tasks page. Link the two films from the guide's first page. | A day, mostly writing and captures. | No. |
| C | **More explainers** on the approved component (DL-172): Director (on its slot, and on Project › Start Director), Chat and Terminal (on the pill), Home. Each: a title, one line, three points, Learn more to its guide page. | A day or two. | The component is approved; each explainer's words and anchor get a [P] and a look. |
| D | **A first-run welcome:** one sheet or a Home card on the first launch: the 90-second version of the intro film or its poster, then three things to try (open a project, switch a session to Chat, tell a session "be the director"), dismissible, reopened from Help › Welcome to Duo. | A canvas round, then two or three days. | Yes: a new surface. |
| E | **"Meet Duo" sample project** (ENH-33): a project with a few sessions, a task board and a director slot to poke at. | A week; it must stay true as Duo changes. | Yes. |
| F | **A short film per feature**, cut from the intro film's chapters with the existing pipeline, linked from the explainers. | Hours each once the chapters are marked. | No: reuses approved films. |

**Recommendation** (Q-511): **A, B and C now** as one build (ENH-345), since none needs a new design and together they answer both of his examples; **D as the next canvas round**; F as explainers get their pages; E stays unscheduled. A film alone doesn't fix this: the films exist and he still didn't know.

### 2.4 Starting the director

Typing "be the director" works, and nobody would guess it. Options (Q-512):

- A. **Project › Start Director** (recommended), on `duo2 director start`, which already exists: it starts a session named `director-<project>` with the skill's opening line, or goes to the director if the project has one. Plus the Director explainer from C. Menu items carry no drawn design, and DL-71 already wants the verb to have a UI.
- B. A, plus an empty director slot at the top of the sidebar's Pinned group ("No director · Start one"). The most discoverable, and a new mark on an approved screen, so it goes to the canvas round with D.
- C. Only teach the phrase (guide page and explainer). No new control; still hidden from anyone who doesn't read.

## 3. Claude knowing it is inside Duo

### 3.1 What Legacy Duo did

Legacy Duo (Electron; read at v0.13.8 in its repo) told Claude five ways at once:

1. **A wrapper around `claude`.** A script named `claude`, put first on PATH in Duo's terminals, that ran the real one with `--append-system-prompt "$(cat ~/.claude/duo/priming.md)"` when `DUO_SESSION` was set. Needed because Legacy Duo didn't start Claude itself: the user typed `claude` in a shell.
2. **The priming text** (about 15 lines): you're inside Duo; the `duo` command drives the browser, editor and canvas; prefer `duo view`/`duo edit` to `cat`/`open`; run `duo status` before editing and edit open files through Duo; never switch off the user's safety controls; `duo doctor` if it hangs. Copied once and never updated for existing users.
3. **A SessionStart hook in the user's own `~/.claude/settings.json`** that printed the same text, as a second route. The text could arrive twice.
4. **Environment:** `DUO_SESSION=1`, `DUO_SOCKET`, `DUO_TAB`, `DUO_WINDOW`, `DUO_VERSION`, `TERM_PROGRAM=Duo`.
5. **Installed for every session on the Mac:** a managed block in `~/.claude/CLAUDE.md`, a `duo` skill (828 lines until it was cut to about 250), a `duo` subagent, a warn-only hook when Claude edited a file open in Duo, and the `duo` command.

It gave Claude one convention about showing things: after creating a file, run `duo open --reveal` so the user sees it. It had no link convention and no link scheme, and it never told Claude what the user was looking at. v2's research called the wrapper and the double injection brittle (`docs/research/legacy-duo-architecture-review.md`), and LR-55 was written against the global installs.

### 3.2 What Duo v2 does

Duo v2 starts `claude` itself, so it needs no wrapper:

- **At every session start: `--append-system-prompt <primer>`** (`DuoAction.primer`, `Sources/DuoControl/Actions.swift:804-830`; DL-15, DL-74, DL-256). Generated from the verb list, so it never names a verb that doesn't exist. It opens: "You are running inside Duo, a Mac app that organizes the user's Claude Code sessions into projects and shows their documents. The `duo2` command talks to Duo…", then the everyday verbs (including `duo2 doc open <path>`: "Open a document in the right pane"), search before grep, `duo2 selection` for "this", edit open documents through `duo2 doc edit`, Word and PDF checks, Duo tasks not TASKS.md, and `session note` / `session next`.
- **A per-session settings file** (`--settings`, layered on the user's own, never written into them): hooks that tell Duo what the session is doing; a hook that applies an edit in the open editor (DL-78); and `duo2 hook context` on SessionStart and UserPromptSubmit, whose output **does reach Claude**: the project's brief and the session's task, then only what changed (DL-116). Also the socket's sandbox allowance and `Bash(duo2:*)`.
- **Environment:** `DUO_SESSION_ID`, `DUO_SOCKET`, `DUO_TOKEN`, `duo2` on PATH, `EDITOR`/`VISUAL` for chat's composer. Claude Code's own variables are scrubbed (DL-14).
- **For sessions started outside Duo, with consent** (DL-74, DL-75): a five-line `## Duo` block in `~/.claude/CLAUDE.md`, the `duo2` skill, the director skill, and a `duo2` link. Removal sticks.
- **Chat and terminal are the same process.** Chat is a view over the terminal (DL-118). Claude is not told which one the user is looking at, and the user can switch at any moment.

**What v2's primer doesn't say:** that file names in replies become links; when to open a file for the user; which view the user is in.

### 3.3 Proposal (Q-513)

**Where.** Keep the delivery exactly as it is: the primer at spawn. It is the right tier: it reaches only Duo's own sessions, it is rebuilt with each version of Duo, it touches none of the user's files, and it works on the work Mac's pinned Claude Code 2.1.284 (`--append-system-prompt` and `--settings` are what Duo already passes there). No new environment variable, no new file, no change to the CLAUDE.md block or the consent list (a change there would re-ask every user, DL-75). The skill gets the same line, for depth.

**What to add.** One sentence, mode-neutral:

> File names you write in a reply (`docs/plan.md`, `src/app.py:42`, a path from the project folder) are links the user can click to open the file beside the conversation; when you finish a document the user should read, open it for them with `duo2 doc open <path>`.

About 45 words. The first half costs little and stops Claude from doing worse things (pasting whole files, absolute paths); the second half is the part of his request that only Claude can do: making the file "show up on the right" without a click. Legacy Duo's `--reveal` rule was the same idea.

**What not to add, and why.**

- **No file-name convention beyond that.** The test (F-662) shows Claude already writes what Duo links, and that Haiku ignores a finer rule (Markdown links for paths with spaces). Tokens spent there buy nothing; the link rule in Duo is where the misses are fixed (ENH-343).
- **No per-mode text.** The primer is fixed when the session starts and the user can switch views at any moment, so a mode in the primer would often be wrong. The one route that could keep it current is `duo2 hook context` on each prompt, which would add tokens to every turn after a switch and make Claude write differently for the same question. Better that both views link the same things (ENH-343 item 3), so Claude never needs to know. If a real per-mode need appears later (say, tables that only chat can draw), `hook context` is the place, and `duo2 status` can already answer "which view?" on demand.
- **Nothing private.** The primer carries the session's id and the path to `duo2` (DL-256), no token, no socket, no project names. This adds none.

**Risks.**

| Risk | Answer |
|---|---|
| Token cost | One sentence in a primer of about thirty lines, once per session, cached. Not measured here: the exact count wants a built app. |
| The user's own CLAUDE.md says otherwise | It wins: an appended system prompt states defaults, and the user's instructions are read after it. The sentence is a fact and a suggestion, not a "must". |
| Overriding user settings | None touched; `--settings` layers, the primer is an argument. |
| Pinned CLI 2.1.284 | Same flag as today. |
| Session ids (DL-14) | Untouched. |
| Claude opens files the user didn't want | The wording limits it to a finished document the user should read; `duo2 doc open` doesn't steal focus from the conversation. Worth a real-turn check when built. |
| A `/fork` copy loses Duo's environment | Already handled in the primer (DL-256); the new sentence needs no environment. |

**Options for Q-513.**

- A. **The one sentence, plus the Duo-side link fixes** (recommended).
- B. Duo-side fixes only; tell Claude nothing new. Files are clickable, but never open by themselves.
- C. A fuller convention with per-mode variants through `hook context`. More tokens each turn, a wrong mode whenever the user switches between prompts, and the test says the finer rule isn't followed.

### 3.4 Response conventions, as they would stand

- **Files:** a path from the project folder, in backticks or plain, with `:line` when pointing at one. That is what Claude does unprompted and what both views will link. Absolute and `~` paths work too. Paths with spaces and names with no extension work once ENH-343 item 1 is built, when written in backticks.
- **Web addresses:** in full, with `https://`.
- **Sessions and tasks:** `duo2://session/<id>` and `duo2://task/<id>` (DL-87, DL-115), which `duo2` prints.
- **Terminal mode:** the same text, opened with ⌘-click once ENH-343 item 3 is built. A hover underline or a plain click isn't possible without taking over the terminal's mouse, which Claude Code's own screen uses.

## 4. What was run, and what was only read

- **Run:** four Haiku 5.5 turns (`claude -p`, Claude Code 2.1.316, a scratch project in `/tmp`, a scratch `CLAUDE_CONFIG_DIR`, Read/Glob/Grep only), two prompts with and without a convention in `--append-system-prompt`, plus one "say ok" turn to test the login; chat's link rule replayed over the replies in Python (the same two patterns and extension list as `ChatMarkdown.swift`). Details in F-662.
- **Read, not run:** everything else: the mode logic, the panes, the menus, the terminal's link handling, Legacy Duo's repo, the installer. No Duo was launched and no capture was taken. The exact look of what he saw is inferred from the code and the tokens.
- **Not checked:** his Mac, his Duo version or his Claude Code version; whether Claude Code's own screen marks file names as links; the primer's token count; whether Claude over-uses `duo2 doc open` when told about it.

## 5. A reply Geoff can send

> Thanks, this is exactly the kind of note I need. Short answers:
>
> - **White IDE vs terminal:** every session can show two ways, Chat (formatted replies, buttons) or Terminal (Claude Code's own screen). There's a small Terminal | Chat pill on the session's tab. Home starts in Chat and project sessions start in Terminal until you switch once, which is why it looked random. I'm changing that so new sessions start in Chat, and labelling it properly.
> - **Clickable files:** they already are, in Chat: click a file name in a reply and it opens on the right. In Terminal it's ⌘-click and it opens outside Duo today; I'm fixing that to open in Duo too.
> - **Right side:** ⌥⌘0 hides and shows it, or the button at the far right of the toolbar. It's missing from the View menu; adding it.
> - **File list:** folders fold when you click them, and ⌃⌘S hides the whole sidebar. Folding the Files section itself is coming.
> - **Colour:** you're right, it should be Color. Fixing.
> - **Director and tasks:** a task is a note for one piece of work, and it gathers the sessions working on it; a session is one conversation with Claude. To start a director, open a session in a project and type "be the director". There's a 7-minute film: [link]. You're right that the app doesn't teach any of this; a proper welcome, a Help menu that links the guide, and a Start Director menu item are next.
>
> And yes please, post anything else in the community channel.

## 6. Records

- **F-660** what is true today for the five items; **F-661** how Legacy Duo and Duo v2 tell Claude; **F-662** the convention test.
- **Q-510** to **Q-514** as in the table at the top.
- **ENH-343** links in both views; **ENH-344** pane controls; **ENH-345** the teaching layer.
