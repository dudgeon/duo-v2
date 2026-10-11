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

## The voice

The house voice is M2, a warm baritone. The build reads this table: write the word as it appears in a line, and how it should be said. Add a row whenever a line comes out wrong.

| Written | Said |
| --- | --- |
| v2 | vee two |
| duo2 | duo two |
| Command K, ⌘K | command K |
| prd-v2.md | P R D vee two dot M D |
