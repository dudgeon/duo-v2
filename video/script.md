# Duo v2 intro video: script v2

Oct 10, 2026 · @Geoff Dudgeon

A from-scratch rewrite. Each build reads this doc. The rules below are what the build understands; anything else is notes for us.

## How to write it

- **A scene is a `###` heading:** `### S1 · Title (about 20 s)`. Keep the `S` number at the front; it ties the scene to its shot. The time is a target; the real length comes from the voice.
- **Each bullet under a scene is one voiceover line,** voiced and checked on its own. One sentence or clause per bullet; long lines get rushed.
- **`Shot:` is a plain-English note of what we see.** Say what the viewer should notice, not how to animate it. I turn it into captures, camera moves and callouts.
- **Callouts:** if a line names a feature that should be pointed at, put the phrase in *italics*. That's where the cursor clicks and the marker lands.
- **Only real things.** Everything on screen is the real app on sample data, so say only what Duo actually does today.
- **Anything else** (a paragraph, a question, a `> note`) is ignored by the build. Use it freely.
- **Every Shot: note is a checklist.** The build lists each thing a Shot: note asks for, and its report names anything not built yet. A stand-in is never silent.
- **No shot ever cuts to the next.** If the next shot is somewhere else in the app, we get there by using the app: the camera pulls back, the cursor clicks where you'd click, and the camera pushes in on what opens. If it's a different idea, it gets a motion-graphics transition instead. The build picks one for every scene change and refuses to render a plain cut or dissolve; a Shot: note can ask for a particular one.
- **Topic:** is the scene's name in the topic list, the vertical list at the left that comes up at each scene change with the new scene highlighted. One short line under the heading, like `Topic: Chat mode`. Edit it freely; the heading's title is only for us. To keep a scene under the previous scene's topic, write `Topic: same`: the two share one entry, and no topic list comes up between them.

## The brief

Fill these four in first; I read them before every scene decision. (The build ignores this section.)

|  |  |
| --- | --- |
| **One sentence** the viewer should remember |  |
| **Who it's for** |  |
| **Length** |  |
| **How it should feel** (and what it must not feel like) |  |

## Scenes

> **Example, to copy and delete.** The build skips a scene whose title starts with "Example".

### S0 ·Intro

Topic: Intro

- Duo is a desktop client for claude code that makes it easier to stay organized and get work done.

Shot: the Duo logo builds itself in motion graphics, then settles beside the title "Duo" and the line "A complete workspace for your Claude Code sessions, projects, and files.", the three framed as one composition. That settled frame is the video's thumbnail, so it must read at a glance.

> **Options for the line under "Duo"** (Geoff, Oct 11: "descriptive and expansive", with no superlatives or subjective adjectives). It's also the thumbnail, so the main line stays short enough to read at a glance; options D and E add a smaller second line for the rest. Geoff chose his own line (Oct 11): "A complete workspace for your Claude Code sessions, projects, and files." It's now in the Shot: above; these options are kept for reference.
>
> - **A.** Projects, sessions and documents for Claude Code, in one Mac window
> - **B.** Every Claude Code session, organized by project, with its documents beside it
> - **C.** Work with Claude Code by project, not by terminal window
> - **D.** A desktop client for Claude Code, then a smaller line: *Projects · every session · terminal or chat · Markdown, HTML, PowerPoint and Word · what needs you · search*
> - **E.** Claude Code, organized by project, then a smaller line: *Your sessions, the files they work on, and what's waiting on you, in one window*
>
> What these draw on, all real today: every Claude Code session on the Mac, listed and kept past the 30-day cleanup; a folder and a PROJECT.md per project; terminal or chat mode; documents beside the conversation (Markdown, HTML, PowerPoint, Word), with Claude's changes highlighted; one Needs you queue across projects; search across everything; plain files; and duo2, so Claude can drive Duo.
>
> The voice line says nearly the same thing as the current subtitle, so if the subtitle changes, the voice line probably should too.

### S1 · (title) (about \_ s)

Topic: Too many windows

- I find that when I work with claude code, I am usually juggling multiple terminals, finder windows, text editors, and browser tabs.
- I often open a new terminal window for a quick task, and either take a bunch of time to pick the right starting directory, or lose track of where I opened which sessions if I want to come back to them later.

Shot: the High Sierra desktop starts empty, then fills window by window: dark-mode Terminal windows running Claude Code, Finder windows on different project folders, a Markdown editor, a browser showing a polished, realistic checkout prototype, a PowerPoint deck and a Word doc. Each opens on top of the last until you can't tell which terminal belongs to which project.

> **Notes for the build** (a quote, so the build ignores it; a bullet here would be voiced):
>
> - *Drawn, not captured:* these are third-party apps, so they're the 75%-fidelity stand-ins from `lib/Clutter.tsx`, with sample project names in the title bars (checkout-redesign, refunds-api-spec, onboarding-v3, pricing-experiment-q4).
> - *Line 1 timing:* each kind of window appears on its word: terminals on "terminals", Finder on "finder windows", the editor on "text editors", the browser on "browser tabs". PowerPoint and Word arrive in the gap before line 2.
> - *Line 2 beats:* a new terminal opens and a `cd` path is typed, wrong, then retyped; then the camera drifts over the pile hunting for an older session and doesn't find it.
> - *Hand-off to S2:* the scene ends on the full pile, held about 1 s, so S2 can pull these same windows into Duo.

### S2 · (title) (about \_ s)

Topic: One window

- Duo brings all the tools you need together into a single window: a pane for managing files and projects, a terminal or chat view for working with claude, and a flexible editor for viewing and working with files.

Shot: an animated transition, not a cut: the S1 windows morph into one real Duo window. The Finder windows morph into the left pane; the dark terminals morph into session tabs in the middle pane; the Markdown file, the browser prototype, the PowerPoint deck and the Word doc morph into tabs in the right pane. Each pane gets a callout as the narrator names it.

Middle pane, on "a terminal or chat view": the terminals have folded into session tabs. The cursor clicks from one tab to the next (real sessions on sample data), and the last one flips to chat view on the words "chat view".

Right pane, on "flexible editor": the Markdown file, the browser prototype, the PowerPoint deck and the Word doc are now editor tabs. The cursor clicks through them in that order.

> **Notes for the build** (ignored by it):
>
> - *Left pane, on "managing files and projects":* the Finder windows land as the project list and file tree.
> - *New captures needed:* one project with three or more terminal tabs, the last in chat view, and the editor with four tabs open: a Markdown file, the prototype in a browser tab, a .pptx and a .docx.
> - *Word and PowerPoint:* Duo opens .pptx and .docx (Geoff, Oct 10), so the same deck and doc from S1 appear as real tabs here.
> - *Callouts:* putting *a pane for managing files and projects*, *a terminal or chat view* and *flexible editor* in italics in the line would pin the three callouts to those words.

### S3 · All projects (about 12 s)

Topic: All projects

- The first time you open Duo, you'll see all of your previous claude code sessions, and you can resume any of them.
- Duo also calls out any sessions that are waiting for your input.

Shot: All projects in List view: every previous session in one list, with its project, title and when it last ran. On line 1 the camera runs down the list; nothing is clicked yet. On line 2 the camera moves right to the Needs you column, where a few sessions wait on a question or a permission.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S2:* app navigation, not a cut. S2 ends wide on shelf-scan; the camera pulls back, the cursor clicks **All projects** at the top of the left pane, and the camera pushes in on the list as it opens.
> - *Real, today:* on first launch Duo opens on every session, grouped by folder, with no setup (S2-3). All projects has Home on the left, **Board | List** in the middle and the Needs you column on the right. Clicking a session reopens it in its project with `claude --resume`.
> - *New captures needed:* All projects in List view on sample data, four or more projects with 15 to 20 sessions across Today, This week and Earlier, and two or three in Needs you (one question, one permission). (The state after the resume click belongs to S4.)
> - *Callouts:* italics on *previous claude code sessions*, *resume* and *waiting for your input* would pin the marker to those words.
> - *Hand-off to S4 (Geoff, Oct 11):* S3 stays on All projects and ends on the Needs you column. The resume click that carries us into the chat pane opens S4, not the word "resume" here.

### S4 · Sessions (about 20 s)

Topic: Agent Pane

- When you click a claude code session, it resumes right where you left off, in the terminal.
- Duo helps you keep track of many sessions at once. You can close one and come back to it later,
- or archive or delete the ones you're done with to cut down on clutter.

Shot: from S3's Needs you column, the cursor clicks a session, and the camera pushes into its project as the terminal resumes with its history. On "close one" the cursor clicks a session tab's × in the middle pane and the tab closes (Geoff, Oct 11: show the tab's ×, since the menu has no Close). This beat runs slower: the camera pulls back to the session list in the left pane, where the closed session is still listed. On "come back to it later" the cursor clicks it there, and its tab reopens in the middle pane with its history, right where it was. Hold on the reopened tab for a beat before line 3 (Geoff, Oct 11). On "archive or delete", the cursor opens a session's right-click menu in the session list, with its real items, among them Archive Session and Delete Session…. One session folds into Archived; another is deleted through Duo's confirmation sheet.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S3:* app navigation. The resume click at the start of this scene is the transition, so S3 ends on All projects with nothing clicked (Geoff, Oct 11).
> - *Real, today:* resuming reopens the session with `claude --resume`. Archive Session and Delete Session… are in a session's right-click menu; there's no Close there (a session closes with its tab's ×, and the menu has no Close item, found Oct 11). Delete asks first, in Duo's confirmation sheet, then moves the transcript to the Trash; it never deletes a running session.
> - *Decided (Geoff, Oct 11):* keep Delete in the line and the shot. S4 covers sessions only; the terminal is S5 and chat mode S6.
> - *New captures needed:* the project with the resumed session in its terminal; the session list's right-click menu; the Archived fold with one more session in it; the confirmation sheet; the list after the delete; and the closed tab reopened from the session list.
> - *Fixtures (asked of demo-fixtures, Oct 11):* a Needs you session with real history, a session to archive, an idle one to delete, and a few already archived.
> - *Leaving for S5:* S4 ends on the terminal, and S5 carries straight on from that picture. The chat-toggle click comes in S6, on "chat mode", so the flip lands as the narrator names it.

### S5 · Terminal pane (about 6 s)

Topic: same

- The terminal pane runs the full claude code  interface.

Shot: the same session as S4, in the terminal. The camera settles on the middle pane while Claude Code's own interface runs in it: its banner, the conversation with each tool call, and the prompt at the bottom. Nothing is clicked. The camera stays on the middle pane (Geoff, Oct 11: the right pane hasn't been introduced yet).

> **Notes for the build** (ignored by it):
>
> - *Getting here from S4:* carrying on from S4's last picture, the terminal, with no cut. It shares S4's topic (Topic: same), so no topic list comes up.
> - *Split (Geoff, Oct 11):* S5 is the terminal pane only; chat mode moved to S6.
> - *Captures:* the resumed terminal from S4 (video-s4-resumed); nothing new.
> - *Leaving for S6:* S5 ends on the terminal; S6 pushes in on the chat-mode button.

### S6 · Chat mode (about 30 s)

Topic: Chat mode

- If you prefer something tidier, Duo also has a *chat mode*, which collapses the steps Claude takes along the way, like tool calls and file edits, into rows you can open.
- Writing is easier in chat mode too: click and drag to select, use the Mac shortcuts you already know, and see a preview of any image or text you paste.
- Most slash commands, like skill invocations and the model picker, work in chat mode.

Shot: carrying on from S5's terminal. On *chat mode* the camera pushes in on the chat-mode button at the top right of the middle pane, and the cursor clicks it as the pane flips to chat. Then a short exchange plays out: Sam sends a message, Claude replies with its steps folded into rows, Sam follows up and Claude answers; the cursor opens one folded row to show the tool call inside. On the writing line, the cursor drag-selects a sentence in the composer, then pastes a block of user feedback, which folds into a "Pasted text · n lines" block, and a screenshot from that user, which shows as a preview. On the slash-commands line, Sam types `/` and the start of the demo skill's name; the composer's menu lists the skill, Return runs it, and its run shows as a row. Then `/model` opens the model picker and a model is picked. The camera stays on the middle pane throughout: the session list and the right pane stay at the frame's edges or out of it, and nothing opens in the editor (Geoff, Oct 11: the right pane hasn't been introduced yet).

> **Notes for the build** (ignored by it):
>
> - *Getting here from S5:* app navigation, carrying on from S5's last picture. The topic list comes up with Chat mode highlighted as the camera pushes in on the button; the click lands on "chat mode".
> - *Split from S5 (Geoff, Oct 11):* S5 is the terminal pane; chat mode, with its turns, writing and slash commands, is this scene.
> - *New captures needed:* the chat after each turn; one folded row closed and open; the composer with a drag selection, the folded paste and the image preview; the `/` menu listing the demo skill; the skill's run as a row; the `/model` picker.
> - *Fixtures (asked of demo-fixtures, Oct 11):* the session's history; a block of user feedback long enough to fold (over 12 lines) and a screenshot from that user; a demo skill for shelf-scan; Claude Code's `/` menu and `/model` screens; two or three short turns between Sam and Claude.
> - *Skill autocomplete:* any problem found with it while building goes to the director to fix (Geoff, Oct 11).

### S7 · Editor Pane

Topic: File Viewer/Editor

- Duo includes a single pane to view and edit most of the file-types you would want to interact with: markdown, html, powerpoint, and documents.
- Markdown editing is simple -- most keyboard shortcuts are the same, like command-b to bold, and command-k to add a link. Your changes are visible in real time -- no toggling between raw and rendered markdown.
- Anything you can see or edit, claude can too. You can select text to show it to your claude agent,
- and claude can update the document with visible changes.
- This works in all document types that duo supports, like html or powerpoint.
- Pick an element in a prototype and ask for a change.
- Or pick a paragraph on a slide and ask for bullets.

Shot: the camera moves right to the viewer pane, its first time in the video. On line 1 the cursor clicks through the tabs open there, each on its word: the PRD (Markdown) on "markdown", the scan-review prototype (HTML) on "html", the team-review deck on "powerpoint", and the interview synthesis (Word) on "documents". Each tab opens in its real viewer, and the camera stays on the viewer pane while the tabs change.

On line 2 the cursor goes back to the PRD tab and makes a run of edits in the Markdown editor, each on its words, with a small keycap showing each shortcut as it's pressed:

1. On "command-b": it drag-selects "Fewer than 3% wrong books" in Goals, and ⌘B bolds it in place.
2. On "command-k": it selects "review step" in What we heard, and ⌘K (Format › Link) makes the words a link to the prototype, prototype/scan-review.html.
3. On "real time": it types a new sentence at the end of What we heard, "Owen (P8) stopped after two wrong books in two scans.", which renders as it's typed.
4. On "no toggling": it adds a bullet under Open questions, and the camera pulls back enough to show there is only one view of the file, with no raw/preview switch.

The camera stays on the viewer pane throughout.

On lines 3 and 4, still on the PRD, played slower for emphasis (Geoff, Oct 11):

1. On "select text": the camera zooms in on the What we heard paragraph until it fills the frame, with nothing selected yet. The cursor, an I-beam over the text, presses before the paragraph's first word and drags to its last; the highlight grows behind it word by word, as a real selection does. It lets go and right-clicks the selection. The editor's menu opens with its real items, the cursor moves down to **Send Selection to Claude**, the item highlights, and it clicks. The menu closes, and the picture holds about a second on the selection.
2. On "show it to your claude agent": the camera moves to the middle pane and pushes in on the Auto-add decision chat's composer, empty at first. The selection lands in it as a reference to those lines, and the picture holds a beat. Then Sam types "Update this with the latest tester feedback in research/feedback" at a normal typing pace: one character at a time, with the small uneven pauses of real typing (about 50 words a minute, so roughly 15 s), never filled in at once. Sam presses Return to send. The narration waits after line 3 until it's sent.
3. On "visible changes": Claude's reply folds its steps into rows (it reads the feedback files and edits prd-v2.md), and the camera moves back to the editor. There the paragraph has changed in place, with Claude's edit highlighted the way Duo marks Claude's changes.

> **Notes for the build** (ignored by it):
>
> - *The menu:* drawn, like S4's, because macOS draws context menus outside the window capture. Its items are the editor's real ones (Send Selection to Claude, Send Selection To ▸, then the system's).
> - *Slowed (Geoff, Oct 11):* line 3 is split after "agent," (same words), so the selection, the menu and Sam's typing play out between lines 3 and 4; the later lines move down one. New captures needed: the composer empty, then holding only the selection reference, before Sam types.
> - *Fixtures (made by demo-fixtures, Oct 11):* the chat turn (the composer with the sent selection as Duo formats it, Sam's message, and Claude's reply with its rows); the PRD after Claude's edit, a What we heard paragraph updated from the triage log (Denise's glare, Owen's two wrong books); and the editor showing that edit highlighted.

On lines 5–7, the same pattern twice more, each ending on the change visible in its own viewer (lines 6 and 7 added Oct 11, so each demo has its own line):

1. On "html" and line 6: the cursor clicks the scan-review.html tab, picks the "Fix" button on the prototype's review screen with the element picker, started from the page's right-click menu (Select Element), which outlines it, and sends it to Claude. Sam asks "Make this button say 'Fix this book' and make it bigger", and the prototype reloads with the change.
2. On line 7: the cursor clicks the team-review-oct15.pptx tab and goes to slide 3, "What the eval found", and picks its paragraph with the deck viewer's Select Shape button. Sam asks "Turn this into three bullets", and the slide redraws with the bullets.

> **Notes for the build** (ignored by it):
>
> - *Real, today:* the HTML viewer's element picker and a picked slide shape both go to Claude through Send to Claude (`duo2 send element`). Claude edits the file and the viewer shows the new version.
> - *Fixtures (made by demo-fixtures, Oct 11):* for each, the chat turn (the picked element or shape as Duo sends it, Sam's message, Claude's reply with its rows) and the file after Claude's edit (scan-review.html with the bigger button; the deck with that slide in bullets). The deck needs a slide with a plain paragraph to turn into bullets.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S6:* app navigation. The camera pulls back from the chat, and the topic list comes up for this topic.
> - *Tabs:* the four files open in S2 (prd-v2.md, scan-review.html, team-review-oct15.pptx, beta-interview-synthesis.docx) are still open in the right pane, so the clicks walk the real tab strip.
> - *New captures needed:* the right pane on each of the four tabs, in the 1800×1100 window S3–S6 use.

### S8 · Projects Background

Topic: Claude Code Projects

- Projects are a little harder to explain and something I need to work on in the app. Let's start with some fundamentals.
- Claude Code itself operates on a concept called "projects" -- wherever you open Claude Code, Claude assumes that that folder is a project, and any future Claude code session opened in the same folder is part of the same project.
- Claude code assumes you have one folder for each of the projects in your life—and that you consistently change the working  directory into the "right" project folder before each session.
- Claude code cli does not show you your projects or make it easy to navigate between them.
- many users don't change directories before starting claude code, so all projects stack up in the same directory and are hard to tell apart
- Projects are a really useful construct in claude code, but they can be hard to manage.

Shot: on "Let's start with some fundamentals", Duo's window fades away to the bare desktop. On the "projects" line, two simulated windows appear, side by side, drawn like S1's: a dark Terminal and a Finder window on Sam's home folder (Desktop, Documents, Downloads, work…). The Terminal's prompt reads `sam@mbp ~ %`, and Sam types `claude` with no `cd`. Claude Code's banner comes up showing `~` as its folder, and a marker circles that path as the narrator says it's the project, with the Finder window showing the same folder beside it.

On line 3 ("one folder for each of the projects in your life"), the windows step aside for a motion graphic on the paper ground: a row of folders under `~`, namely `work/little-shared-library/shelf-scan`, `beta-feedback`, `taxes-2026`, `maya-birthday` and `router`. Each holds its own small stack of session cards, the way Claude Code files sessions by folder, one stack per folder. This is the ideal Claude Code assumes. On line 4 ("does not show you your projects"), every stack except the one for the folder you're in greys out and its folder name fades, since Claude Code only shows the sessions of the folder you started in. Then the graphic folds back into the Terminal.

On the "many users don't change directories" line, still in the Terminal at `~`, Sam runs `claude --resume`. Claude Code's session picker opens on a long list of unrelated sessions, all started in `~`: the shelf-scan PRD next to a tax-receipts tidy-up, a birthday-party plan, a fix to a home router, a cover letter, and so on. Sam scrolls down through a screenful or two, can't find the one wanted, and gives up, leaving the pile on screen. The list is in Claude Code's own picker format.

> **Notes for the build** (ignored by it):
>
> - *Drawn, not captured:* the Terminal is a stand-in from `lib/Clutter.tsx`, with the real Claude Code banner text as S2's terminals show it.
> - *Transition:* a motion graphic (Duo fades to the desktop), as Geoff asked; it's a change of idea, not app navigation.

> - *Visual plan (Geoff, Oct 11, by buttons):* the folder map for the one-folder-per-project line; the resume picker's pile is Sam's own sessions, the shelf-scan work mixed with life stuff (23 sessions, real 2.1.296 picker text from demo-fixtures, `terms/s8-resume-*.txt`).
> - *Ending (Geoff, Oct 11):* the scene ends on the pile, still on screen. The next scene opens by fading the pile out and Duo back in.

### S9 · Duo Projects

Topic: Duo Projects

- Duo tries to help you manage projects and use them to make progress in your own work.
- Duo finds every Claude code session from your history and organizes them by the project folders where they were created --  making it easy to see what you were working on and where.
- Each project shows up as its own card, and lists the sessions from that project underneath it.
- When you click on an existing session, you enter a view for its parent project.
- Here, you can see the sessions that share a project, and the files and folders in that project's directory.
- You can always leave the project view and return — and find all of the sessions and files from that project right where you left them. This helps make switching between many different projects a little easier. 

Shot: the resume picker's pile from the scene before fades out, and Duo's window fades back in on the desktop exactly as we last saw it at the end of S7: shelf-scan open, the Auto-add decision chat in the middle, and the deck in the right pane on its new bulleted slide.

On "finds every Claude code session from your history", the cursor clicks **All projects** at the top left, then **Board** in the Board | List switch. The Board view opens: a map of project tiles grouped in columns by area (APP, COMMUNITY), each tile listing its project's sessions (shelf-scan, beta-feedback, steward-onboarding, neighborhood-map, Home). On "what you were working on and where", the camera glides across the columns, so each project's sessions read as its own stack: the opposite of the pile in `~`.

On "its own card", the camera settles on the shelf-scan column, and a marker runs down its session cards. On "click on an existing session", the cursor clicks one of them, and Duo opens shelf-scan's project view (app navigation, as in S3 to S4). On "sessions that share a project", the camera zooms in on the project's session list at the top of the left pane (Today, This week, Archived), so its rows fill the frame. On "files and folders in that project's directory", the camera moves down the left pane to the file navigator below the sessions (FILES, the project's path, then PROJECT.md, docs/, eval/, prototype/, research/…) and zooms in on it, as the cursor opens one folder. On "You can always leave the project view and return", the camera pulls back, and the cursor clicks **All projects** in the breadcrumb; the Board view comes back. Then it clicks a shelf-scan card again, and the project view returns exactly as it was left: the same tabs, chat and files ("right where you left them"). On "switching between many different projects" the camera eases back to the whole window.

> **Notes for the build** (ignored by it):
>
> - *Transition:* a motion graphic, the pile out and Duo in (Geoff, Oct 11). Its first picture is S7's last capture (video-s7-pptx-after), so nothing in Duo changes across the gap.

### S10 · Tasks

Topic: Tasks

- Tasks are an experimental, optional feature that you can use to add structure to a project.
- Usually, a project has an overarching goal, and includes multiple tasks to achieve that goal. The project persists over time, but tasks come and go.
- In my own work, I found that most of my Claude code sessions mapped to a task, so I made tasks to help me provide more context to claude about the task goal, and attribute the claude code sessions that are related to it.
- In duo, you can make a task in the project view, then add some details -- these are available to the user and any agents that work with them.
- Then, duo makes it easy to attribute sessions to that task. You can collapse them or show them.
- Imagine a project with several work-streams; instead of searching through dozens of sessions, they are tidily organized by the task they support.
- Because tasks are a defined primitive in duo, we can create view that make it easy to see, manage, and return to tasks.
- Best of all, when you complete a task, you can archive all of the sessions that related to that task so they are out of the way.

Shot: in shelf-scan's project view, with the camera on the left pane.

On line 1 ("experimental, optional… add structure"), the session list starts flat, as it has looked all along. On "add structure", the project's **Tasks** fold opens above it and the sessions regroup under their tasks: Auto-add decision, Deck for Thursday, Spine eval: glare cases. Each group holds the sessions that worked on it, and anything without a task stays below.

On line 2 ("an overarching goal, and includes multiple tasks"), the camera rises to the project's header (its health and next step, "On track · Team review Thu Oct 15"; the goal itself lives in PROJECT.md and on the All projects tile), then runs down the task rows, tracing the tasks that serve it. On "tasks come and go" it settles on the complete one (Beta interview synthesis, done).

On line 3 ("more context to claude about the task goal, and attribute the sessions"), the cursor opens the Auto-add decision task's note in the right pane. It's a plain Markdown file: its goal and done-when at the top, then its sessions listed by name. A marker circles the goal on "context to claude", then the sessions on "attribute".

On "you can make a task in the project view", the cursor picks **New Task** (File › New Task). Duo opens a new note as "Untitled task" with its heading selected (the + New task row at the end of the Tasks fold does the same), and Sam types the name, "Warn about glare before the photo"; the file takes the name's slug. The new task note opens in the right pane's editor (tasks/warn-about-glare-before-the-photo.md, the slug New Task makes), and on "add some details" Sam types a few lines under it: the goal (no glare reads at glass-door boxes), what done looks like, and a link to Denise's feedback. On "available to the user and any agents", the camera pulls back to show the task listed in the project beside its sessions.

On "attribute sessions to that task", Sam right-clicks the new task in the project's Tasks fold and picks **New Session in Task** from its menu (its real items: Open Task Note, New Session in Task, Add Session ›, and the rest). A new session opens in the middle pane, grouped under the task in the session list, and Sam starts working: types "Draft the glare warning copy for the scan screen" and sends. Claude's first reply begins, already knowing the task's goal from its note.

On "You can collapse them or show them", the cursor clicks the new task's disclosure arrow: its session folds up under it, then unfolds again.

On the work-streams line ("Imagine a project with several work-streams…"), the camera pulls back to shelf-scan's whole session list with every task expanded: four tasks with two or three sessions under each, the complete one marked done, so the sessions read as tidy groups rather than one long list (Geoff, Oct 12).

On "views that make it easy to see, manage, and return to tasks", the cursor opens the project's task board: a kanban with columns by status and shelf-scan's tasks as cards, among them the new glare task, the auto-add decision and the team-review deck. Each card shows its sessions. The cursor clicks a different task's card (Deck for Thursday), its sessions show, and it clicks one of them; that session resumes right where it left off.

On the last line ("Best of all, when you complete a task…"), back in the session list, the cursor right-clicks the complete task (Beta interview synthesis), picks **Archive Task…** from its real menu, and Duo's own question asks whether to archive its sessions too; the cursor clicks **Archive Task and Its Sessions**, and the task and its sessions fold into Archived, out of the way.

> **Notes for the build** (ignored by it):
>
> - *Real, today:* Archive Task… asks "Archive Task Only" or "Archive Task and Its Sessions" (AppModel+TaskMenu.swift); collapse and show are the task row's disclosure.
> - *Fixtures (asked of demo-fixtures, Oct 12):* shelf-scan with four tasks of two or three sessions each, one complete (Geoff).

> **Notes for the build** (ignored by it):
>
> - *Real, today:* a task is one Markdown file per task, `tasks/<slug>.md` with `type: task` frontmatter (DL-6, DL-13), made with File › New Task, which names it first (DL-93). It is a plain file, so Claude reads it like any other.
> - *Fixtures (asked of demo-fixtures, Oct 11):* shelf-scan's PROJECT.md goal; three task notes (Auto-add decision, Deck for Thursday, Spine eval: glare cases), each with a goal, done-when, a status for the board's columns and its sessions linked; the new task note before and after Sam's lines; the New Session in Task chat turn (Sam's first request and Claude's reply, which uses the task's goal); and the Deck for Thursday session's history for the resume.

### S11 · Conclusion

Topic: Conclusion

- Duo is still under very active development, and I will try to keep this video up to date for major feature additions.
- The core is working well for me in my own work, but I have a lot of work to do to make projects and tasks more intuitive. And I'm mindful of the balance in making them useful, vs not over-fitting to my own ways of working, so I would appreciate any feedback you have on how you use or want to use claude code in your own workflows -- and how I can improve how duo could work to help you.
- Please give duo a try and open up a github issue if there are bugs, features you would like me to add, or ways I could improve the experience.

Shot: out of the app and onto the paper ground, a bookend to S0.

1. On "under very active development", Duo's window pulls back, shrinks and slides off as a thumbnail to the left, and a release line draws itself across the frame: one dot per real release, read from GitHub at build time (0.2.0 on Oct 6 to 0.2.11 today, so it grows with every build). On "keep this video up to date", a last dot past the newest stays open and dashed, labelled "next", with a small mono stamp under the line: "This video was built from Duo 0.2.11 on Oct 11, 2026".
2. On "the core is working well", the topic list from the scene changes comes back, full height and centred: every topic gets a ✓, but Projects and Tasks are circled with the marker, as still in progress. On "any feedback you have", the list slides up, and a few blank feedback cards drop into a stack beside it, each with a cursor's blinking caret, as an invitation and not real messages.
3. On "give duo a try", the cards clear. Just before, on "open up a github issue", we're briefly back in Duo for the real way in: the cursor opens the Help menu in the menu bar and picks Report an Issue…, and a browser window slides up with GitHub's new-issue form for duo-v2, Duo's version and macOS already filled in. Then the browser shrinks away, and the video ends where it began: S0's opening card (the Duo logo, "Duo" and its subtitle), exactly as the thumbnail shows it, held about 3 s after the last line (Geoff, Oct 11).

> **Notes for the build** (ignored by it):
>
> - *Drawn, not captured:* all motion graphics in the paper language (`lib/Paper.tsx`). The releases come from `gh release list` at build time, so the line stays true as Duo ships. The repo URL is the real public one.
> - *Open for Geoff:* whether the feedback cards are too much. (Decided, Oct 11: the end card is the opening card.) Real, today: Help › Report an Issue… opens GitHub's new-issue form, filled in, for the user to edit and submit (DuoLinks.newIssue). The menu is drawn (it's outside the window capture) and so is the browser.

## The voice

The narrator is Geoff's own voice, a zero-shot clone at tempo 1.05 (Oct 11; the house voice, B-light-133, is kept to switch back). The build reads this table: write the word as it appears in a line, and how it should be said. Add a row whenever a line comes out wrong.

| Written | Said |
| --- | --- |
| v2 | vee two |
| duo2 | duo two |
| Command K, ⌘K | command K |
| prd-v2.md | P R D vee two dot M D |
