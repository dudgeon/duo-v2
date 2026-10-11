# Duo v2 intro video: script

Oct 10, 2026 · @Geoff Dudgeon

About 2:30 in all: 70 seconds on why Duo exists, then 80 seconds walking through it. This doc is the source of truth; each build exports it to `video/script.md` and re-voices only the lines that changed.

## How this script works

- **Scenes** are the `###` headings. Keep the id at the front (`S5 · …`): it ties the scene to its shot in `video/shots.json`. Rename the rest freely.
- **Each bullet is one voiceover line,** voiced and checked on its own. Short lines voice best: one sentence or clause each.
- **Shot:** is a plain-English note on what we see. Claude turns it into captures and camera moves; the build fails if a scene has no shot.
- Times are targets. The real length comes from the voiced lines.
- Everything on screen is the real app on sample data, so say only what Duo actually does.

## Part 1 · Why Duo exists

Framed on [About Duo](https://github.com/dudgeon/duo/blob/main/docs/about-duo.md): working with Claude Code outside a code editor means juggling windows from several apps.

### S1 · The desk (about 25 s)

- Working with Claude Code outside a code editor means juggling windows.
- A terminal for every Claude session. A Markdown editor for the plan.
- Finder, to hunt for the right folder, then type its path into the terminal.
- A browser, for the page Claude just made.
- And then you describe it all to Claude: the third bullet, under the second heading, in prd dot md.

Shot: a cluttered Mac desktop drawn from sample data (the checkout-redesign project, never a real desktop): Terminal windows running Claude Code, a raw Markdown file, Finder, a browser showing an HTML page. A window piles on as each is named. The Finder hunt and the pasted path happen on screen; the long description is typed into a terminal, letter by letter.

### S2 · Many projects (about 20 s)

- Now multiply that by every project you're moving forward.
- A spec for one, research for another, a review for a third. Eleven sessions, in six folders.
- Come back tomorrow, and where were you? Which session was waiting on you? Where did that document go?

Shot: pull back from the desk to a desk per project, side by side and just as cluttered. In one, a terminal pulses with a question nobody saw; in another, a document scrolls out of sight.

### S3 · The turn (about 18 s)

- Duo v2 is built around your projects.
- Each one keeps its sessions, its documents and what needs you, together.
- So you can pick up where you left off, in any of them.
- And use Claude to move your own work forward.

Shot: each desk's windows fly together and settle into one Duo window, its three panes taking the place of the terminal, the editor and Finder. Pull back to All projects: every project's tile, with what needs you.

## Part 2 · A walk through

### S4 · Every session, found (about 12 s)

- Open Duo, and it finds every Claude Code session on your Mac, grouped by the folder it ran in.
- Nothing to set up. And it keeps them, so a conversation is never lost.

Shot: All projects, then a slow push in on the session list.

### S5 · Projects (about 18 s)

- A project is something you're trying to finish, kept in its own folder.
- It shows its goal and what's next, so coming back takes seconds, not a search.
- Its sessions sit on the left. The conversation is in the middle.
- And what Claude makes opens right beside it.

Shot: open checkout-redesign. Pan left to right across the three panes, landing on each as it's named.

### S6 · What needs you (about 18 s)

- Duo shows what every session is doing: working, ready for your review, or waiting on you.
- When Claude has a question, you see it here, and you answer it right there.

Shot: zoom to the "2 need you" chip in the toolbar, then follow it down to the session's question in chat.

### S7 · Documents (about 15 s)

- Documents open beside the conversation.
- What Claude adds is highlighted, so you can see what changed since you last looked.

Shot: push in on "What we heard", marked added by Claude, in prd-v2.md.

### S8 · Getting around (about 12 s)

- Jump to any project or session with Command K.
- Or search across every project, by meaning as well as by words.

Shot: the jump field opens and filters; then search results from several projects.

### S9 · Plain files, and Claude driving Duo (about 12 s)

- It's all plain files, in folders you own.
- And Claude can drive Duo too: it opens the document it just wrote, right beside you.

Shot: a document appears in the right pane as Claude finishes a turn.

### S10 · Close (about 12 s)

- Duo v2 is an early beta preview. Things will change, and some will break.
- Try it, and tell us what you find.

Shot: end card with the Duo icon, github.com/dudgeon/duo-v2, and Help › Report an Issue.

## The voice

A designed house voice from Qwen3-TTS for now. Later it moves to Geoff's own voice, trained in a separate private project; no recordings or weights go in this repo.

**Voice brief** (what the voice is designed from): a warm, calm, mid-pitched narrator in their thirties, unhurried but not slow, plain-spoken and friendly. A colleague showing you something useful, not an advert.

| Written | Said |
| --- | --- |
| Duo | Duo (respelling it made the voice stumble) |
| v2 | vee two |
| duo2 | duo two |
| Command K, ⌘K | command K |
| Claude Code | Claude Code |
| prd-v2.md | P R D vee two dot M D |

Add a row whenever a line comes out wrong; the build reads this table.
