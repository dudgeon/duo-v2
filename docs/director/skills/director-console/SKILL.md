---
name: director-console
description: Write to the Duo director console (https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka) the same way every time - needs cards, In flight rows, done rows, recurring-agent rows, the release card and the headline - and run its Refresh scrub. Use whenever the duo-v2 director adds, updates or clears anything on the console, answers a console comment, or Geoff presses Refresh. Local to Geoff's Mac; a copy is kept in duo-v2 at docs/director/skills/director-console/.
---

# The director console

The console is Geoff's default channel with the director (`docs/director/console.md` in duo-v2 is the background; this skill is the house style). Its page reads seven `ArtifactData` collections on https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka (code URL https://claude.ai/code/artifact/a4dcf25a-8bf3-4be4-bab6-d563a6a9680f). Every write: read first, pin existing docs with `if_version`, batch when you write more than two.

## Before any card: look up the worker

`python3 -I ~/.claude/skills/director-console/worker-links.py [name|id-prefix …]` prints, for each background worker, its state, its **Remote Control link** (`https://claude.ai/code/session_…`, which opens the session on Geoff's phone) and the **artifacts it has open** (canvases, pages, review pages). Use it for every card and row below. A worker in state `blocked` is usually waiting on Geoff: read its screen (`claude logs <id>`) or transcript before you say so (memory: verify before "needs you").

## Every question carries its links (Geoff, 2026-10-31: "Always ALWAYS … repeat the link to artifacts if accessing those artifacts is necessary to answer your questions — do this immediately before asking the question")

Whenever Geoff needs to see something to answer (a canvas, board, page, film, session), put its link in the chat text **immediately before** the question: a line like "Open the voice canvas: <url> (boards: …)" right above the AskUserQuestion call, and the link inside the question text too. Opening the artifact for him (`Artifact open`) doesn't replace this: he may be on his phone, or the pane may show something else. Console cards already carry `links`; this is for chat and AskUserQuestion.

## No stranded workers (Geoff, 2026-10-30: "we CANNOT have stranded workers")

- The director session runs in **Auto**, never Bypass (_PROJECT.md and delegating.md already said so; Geoff, 2026-10-30: "YOU ARE NOT SUPPOSED TO RUN IN BYPASS MODE"). First thing on every wake: `get_session self`. If `permissionMode` isn't `auto`, switch with `set_session_permission_mode self auto` before anything else.
- Keep `~/.claude/skills/director-console/watch-workers.sh` running in the background at all times: it wakes the director when any duo-v2 worker stops, including ones started after it. Re-arm it on every wake.
- On every wake, `worker-links.py` lists every worker's state. A `done` or `blocked` worker with no console row or task-note line is stranded: read its last report, act on it, and put it on the console.

## needs: what Geoff decides or looks at

```json
{"title": "<n> · <the decision as a question, or what to look at>", "kind": "decision|release|delegation|help|look|info",
 "status": "open", "order": <n>, "refs": "Q-n · DL-n · <branch or sha>",
 "body": ["<what's true now>", "<the choice and its trade-off>", "<what happens after he answers>"],
 "options": [{"id": "x", "label": "<1-5 words>", "recommended": true, "desc": "<one line>"}, {"id": "y", "label": "…"}],
 "links": [{"label": "Open the <worker> session", "url": "<Remote Control link>"}, {"label": "<artifact title>", "url": "<artifact url>"}]}
```

Rules (each is something Geoff asked for):
- **A linked session must be running** (Geoff, 2026-10-30, about a card whose session "shows as disconnected so I can't work with it (I'm angry about this)"). `worker-links.py` gives `running`. Before linking a session, and on every Refresh, wake any linked session that isn't running: `claude --bg --resume <full-id> "<why, and what Geoff wants from it>"`, with no flags, so it keeps its Remote Control link. Never stop a session while a card links it.
- **Every card links its worker's session** ("the decision panes should always include a clickable link to the worker session, esp when there are artifacts to review", 2026-10-30), and every artifact there is to review (canvas, page, film), first in `links`. No worker: link the record, release or page it's about.
- **Recommendation first**, as an option with `recommended: true`; 2-4 options; labels are the button text. Questions a phone can answer in seconds; say the time ("10 s", "~5 min") in the title when it's more than a tap.
- **Only what's true now.** Check the record on main, the worker's transcript and its pending question before writing "waits on you". Never a card for something already answered.
- **Clean as you go**: delete a card as soon as it's answered or done (the `answers` collection keeps the history); delete a release card when that release ships; never leave `status: closed|done` cards behind.
- `order` 0 is the most urgent. Cards from recurring agents use their own ids (`discovery`, `tidy`) and orders (5, 6).

## threads: In flight

`{"name", "state": "working|waiting|needs-you|review|blocked", "summary": "<Geoff's ask in a line, then where it stands>", "branch", "model", "where": "background, Remote Control", "updated": "<ISO>", "link": "<Remote Control link>", "extra": [{"label": "<artifact>", "url": "…"}]}`. One row per live piece of work (a multi-worker project may be one row). Delete the row when the work is merged and signed off, or the worker is stopped for good.

## done: Recently done

`{"at": "<ISO>", "text": "<one or two sentences: what's now true, with sha or release link>"}`, id like `<topic>-<what>`. The page shows the newest 15.

## jobs: Recurring agents

`{"name", "order", "schedule", "next", "page", "pageLabel", "card": "<needs id>", "lastRun": {"at", "status": "ran|stuck|failed", "headline", "link"}}`. Each scheduled run updates its own `lastRun`; the director marks a run `stuck` when `list_task_runs` shows it sitting on a permission prompt, and adds a row when a new job is scheduled.

## release/current and meta/console

- `release/current`: `current` (newest release, its link, one line of what's in it, the DMG sha prefix and scale-gate result), `unreleased` (one bullet per user-visible thing on main since then), `next`, `gate`. Update on every merge and release.
- `meta/console`: `headline` (Markdown: the date, what changed, what's working, what's cleared) and `updated`. Rewrite it on Refresh and whenever the picture changes.

## Refresh (the header button)

Geoff's "Refresh" sends "Console · Refresh: …". Do the full scrub in `docs/director/console.md` § Refresh: every needs card checked against main and the workers (with links added where missing), In flight against `worker-links.py` and `claude agents --json --all`, the release card, the headline, the recurring-agent rows and stuck scheduled runs. Then reply in the thread with what changed, in a few lines.

## Comments on the console

Geoff's comments arrive "sent to Claude". Make the change on the page or in the data, reply in the thread (`ArtifactComments reply`), and leave it for him to resolve unless he asked you to. Changes to the page itself: edit the saved source and republish to the same URL (capabilities carry forward); the page is the director's to publish.

## Keeping this skill in step

When Geoff adds a console rule, add it here and copy the skill to duo-v2's `docs/director/skills/director-console/` (SKILL.md and worker-links.py) in the same commit as any doc change.
