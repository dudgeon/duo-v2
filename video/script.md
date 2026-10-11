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

- Duo is a desktop client for the claude code c-l-i that makes it easier to stay organized and get work done.

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

- I found that when I was working with claude code, I would usually be juggling multiple terminals, finder windows, text editors, and browser tabs.
- I would often open a new terminal window for a quick task, and either take a bunch of time to pick the right starting directory, or lose track of where I opened which sessions if I wanted to come back to them later.

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
- Duo also shows you any sessions that are waiting for your input.

Shot: All projects in List view: every previous session in one list, with its project, title and when it last ran. On line 1 the camera runs down the list; nothing is clicked yet. On line 2 the camera moves right to the Needs you column, where a few sessions wait on a question or a permission.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S2:* app navigation, not a cut. S2 ends wide on shelf-scan; the camera pulls back, the cursor clicks **All projects** at the top of the left pane, and the camera pushes in on the list as it opens.
> - *Real, today:* on first launch Duo opens on every session, grouped by folder, with no setup (S2-3). All projects has Home on the left, **Board | List** in the middle and the Needs you column on the right. Clicking a session reopens it in its project with `claude --resume`.
> - *New captures needed:* All projects in List view on sample data, four or more projects with 15 to 20 sessions across Today, This week and Earlier, and two or three in Needs you (one question, one permission). (The state after the resume click belongs to S4.)
> - *Callouts:* italics on *previous claude code sessions*, *resume* and *waiting for your input* would pin the marker to those words.
> - *Hand-off to S4 (Geoff, Oct 11):* S3 stays on All projects and ends on the Needs you column. The resume click that carries us into the chat pane opens S4, not the word "resume" here.

### S4 · Sessions (about 15 s)

Topic: Agent Pane

- When you click a claude code session, it resumes right where you left off, in the terminal.
- Duo helps you keep track of many sessions at once. Close one and come back to it later, or archive or delete the ones you're done with to cut down on clutter.

Shot: from S3's Needs you column, the cursor clicks a session, and the camera pushes into its project as the terminal resumes with its history. On line 2 the cursor opens a session's right-click menu in the session list, with its real items, among them Archive Session and Delete Session…. One session folds into Archived; another is deleted through Duo's confirmation sheet.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S3:* app navigation. The resume click at the start of this scene is the transition, so S3 ends on All projects with nothing clicked (Geoff, Oct 11).
> - *Real, today:* resuming reopens the session with `claude --resume`. Archive Session and Delete Session… are in a session's right-click menu; there's no Close there (a session closes with its tab's ×, and the menu has no Close item, found Oct 11). Delete asks first, in Duo's confirmation sheet, then moves the transcript to the Trash; it never deletes a running session.
> - *Decided (Geoff, Oct 11):* keep Delete in the line and the shot. S4 covers sessions only; chat mode is S5.
> - *New captures needed:* the project with the resumed session in its terminal; the session list's right-click menu; the Archived fold with one more session in it; the confirmation sheet; and the list after the delete.
> - *Fixtures (asked of demo-fixtures, Oct 11):* a Needs you session with real history, a session to archive, an idle one to delete, and a few already archived.
> - *Leaving for S5:* S4 ends on the terminal, and S5 carries straight on from that picture. The chat-toggle click comes on S5's word "chat", so the flip lands as the narrator names it.

### S5 · Terminal pane (about 6 s)

Topic: same

- The terminal runs the full claude code terminal interface.

Shot: the same session as S4, in the terminal. The camera settles on the middle pane while Claude Code's own interface runs in it: its banner, the conversation with each tool call, and the prompt at the bottom. Nothing is clicked. The camera stays on the middle pane (Geoff, Oct 11: the right pane hasn't been introduced yet).

> **Notes for the build** (ignored by it):
>
> - *Getting here from S4:* carrying on from S4's last picture, the terminal, with no cut; the topic list comes up with Terminal pane highlighted.
> - *Split (Geoff, Oct 11):* S5 is the terminal pane only; chat mode moved to S6.
> - *Captures:* the resumed terminal from S4 (video-s4-resumed); nothing new.
> - *Leaving for S6:* S5 ends on the terminal; S6 pushes in on the chat-mode button.

### S6 · Chat mode (about 30 s)

Topic: Chat mode

- If you prefer something tidier, Duo also has a *chat mode*, which folds the steps Claude takes along the way, like tool calls and file edits, into rows you can open.
- Writing is easier in chat mode too: click and drag to select, use the Mac shortcuts you already know, and see a preview of any image or text you paste.
- Most slash commands, like skill invocations and model pickers, work in chat mode.

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
- Anything you can see or edit, claude can too. You can select text to show it to your claude agent, and claude can update the document with visible changes.
- This works in all document types that duo supports, like html or powerpoint.

Shot: the camera moves right to the viewer pane, its first time in the video. On line 1 the cursor clicks through the tabs open there, each on its word: the PRD (Markdown) on "markdown", the scan-review prototype (HTML) on "html", the team-review deck on "powerpoint", and the interview synthesis (Word) on "documents". Each tab opens in its real viewer, and the camera stays on the viewer pane while the tabs change.

On line 2 the cursor goes back to the PRD tab and makes a run of edits in the Markdown editor, each on its words, with a small keycap showing each shortcut as it's pressed:

1. On "command-b": it drag-selects "Fewer than 3% wrong books" in Goals, and ⌘B bolds it in place.
2. On "command-k": it selects "review step" in What we heard, and ⌘K (Format › Link) makes the words a link to the prototype, prototype/scan-review.html.
3. On "real time": it types a new sentence at the end of What we heard, "Owen (P8) stopped after two wrong books in two scans.", which renders as it's typed.
4. On "no toggling": it adds a bullet under Open questions, and the camera pulls back enough to show there is only one view of the file, with no raw/preview switch.

The camera stays on the viewer pane throughout.

On line 3, still on the PRD:

1. On "select text": the cursor drag-selects the What we heard paragraph, right-clicks it, and picks **Send Selection to Claude** from the editor's menu, among its real items.
2. On "show it to your claude agent": the camera moves to the middle pane, where the selection has landed in the Auto-add decision chat's composer as a reference to those lines. Sam types "Update this with the latest tester feedback in research/feedback" and sends.
3. On "visible changes": Claude's reply folds its steps into rows (it reads the feedback files and edits prd-v2.md), and the camera moves back to the editor. There the paragraph has changed in place, with Claude's edit highlighted the way Duo marks Claude's changes.

> **Notes for the build** (ignored by it):
>
> - *The menu:* drawn, like S4's, because macOS draws context menus outside the window capture. Its items are the editor's real ones (Send Selection to Claude, Send Selection To ▸, then the system's).
> - *Fixtures (to ask of demo-fixtures):* the chat turn (the composer with the sent selection as Duo formats it, Sam's message, and Claude's reply with its rows); the PRD after Claude's edit, a What we heard paragraph updated from the triage log (Denise's glare, Owen's two wrong books); and the editor showing that edit highlighted.

On line 4, the same pattern twice more, quicker, each ending on the change visible in its own viewer:

1. On "html": the cursor clicks the scan-review.html tab, picks the "Fix" button on the prototype's review screen with the element picker (it outlines as the pointer passes over it), and sends it to Claude. Sam asks "Make this button say 'Fix this book' and make it bigger", and the prototype reloads with the change.
2. On "powerpoint": the cursor clicks the team-review-oct15.pptx tab and picks the paragraph of text on a slide that holds a paragraph of findings. Sam asks "Turn this into three bullets", and the slide redraws with the bullets.

> **Notes for the build** (ignored by it):
>
> - *Real, today:* the HTML viewer's element picker and a picked slide shape both go to Claude through Send to Claude (`duo2 send element`). Claude edits the file and the viewer shows the new version.
> - *Fixtures (to ask of demo-fixtures):* for each, the chat turn (the picked element or shape as Duo sends it, Sam's message, Claude's reply with its rows) and the file after Claude's edit (scan-review.html with the bigger button; the deck with that slide in bullets). The deck needs a slide with a plain paragraph to turn into bullets.

> **Notes for the build** (ignored by it):
>
> - *Getting here from S6:* app navigation. The camera pulls back from the chat, and the topic list comes up for this topic.
> - *Tabs:* the four files open in S2 (prd-v2.md, scan-review.html, team-review-oct15.pptx, beta-interview-synthesis.docx) are still open in the right pane, so the clicks walk the real tab strip.
> - *New captures needed:* the right pane on each of the four tabs, in the 1800×1100 window S3–S6 use.

## The voice

The house voice is a warm, medium-low baritone, friendly and a little quicker (B-light-133, chosen Oct 11). The build reads this table: write the word as it appears in a line, and how it should be said. Add a row whenever a line comes out wrong.

| Written | Said |
| --- | --- |
| v2 | vee two |
| duo2 | duo two |
| Command K, ⌘K | command K |
| prd-v2.md | P R D vee two dot M D |
