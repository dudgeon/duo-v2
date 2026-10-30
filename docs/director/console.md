# The director console

*Part of Duo's director procedures (`README.md`). The rule (the console is how Geoff hears from the director first) is in PROJECT.md's `## Director`; this is the collections table and how taps arrive. Moved from the project skill on 2026-10-17.*

## 7. The director console

A private claude.ai page Geoff opens on his phone or desktop: https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka. Source: `console.html` (this folder). Published from this session with `capabilities: {"db": {}, "comments": {}}` (DL-166).

**How a tap reaches you.** Every Send on the page writes Geoff's answer to the `answers` collection and calls `comments.sendToClaude`, which posts a comment thread "sent to Claude". It reaches **the session that published the page** while that session's watch says "auto-replies armed" (`ArtifactComments watch` with no url lists it). What actually happens (F-259): the platform's auto-reply posts a short reply in the thread in this session's name within a minute, then queues a `<task-notification>` (`artifact-auto-react`) for you naming the thread. That reply only acknowledges. The decision is yours to act on, so read `answers` and the thread, act, and `resolve` it. Don't post a second reply. On every turn, and at least after each block of work, also read `answers` for anything newer than you've handled: a notice can be missed while you're busy, and an answer saved while no session listened sends nothing. If the watch is gone (a restart, compaction), run `ArtifactComments watch` on the URL; while no session is listening the page says "Director away; answers are saved", and `answers` holds them for you. Only the publishing session receives sends, so only the director publishes this page.

**What the page shows** (all from the `db`, so update rows with `ArtifactData`; republish only to change the page's code):

| Collection / doc | Fields | Shown as |
|---|---|---|
| `needs/<id>` | `kind` (decision, release, delegation, look, help), `title`, `body` (paragraphs; an array is a bullet list; `code`, `**bold**`, `[label](url)`), `options` [{`id`, `label`, `desc`, `recommended`}], `links` [{`label`, `url`}], `refs`, `order`, `status` (open or closed) | **Needs you** cards (kind `help`: **Director needs guidance**), recommendation first, plus a free-text box |
| `answers/<id>` | written by the page: `choice`, `label`, `text`, `at` (and `msg-…` docs for free messages) | the card's "Your answer" line |
| `threads/<id>` | `name`, `state` (working, waiting, needs you, review, idle; `gone` hides it), `branch`, `model`, `where`, `summary`, `link` (the Remote Control URL), `extra` [{label, url}], `updated`, `order` | **In flight**, each with **Open thread** and a note box |
| `done/<id>` | `title`, `sha`, `at` | **Recently done** (newest 15, sha linked to GitHub) |
| `release/current` | `current`, `unreleased` [..], `next`, `gate` | **Release** |
| `meta/console` | `headline`, `updated` | the line under the title |

**Keeping it current.** After every merge, release, delegation or report: update the thread row, add a `done` row, set the answered need's `status: "closed"` (pin writes with `if_version`), bump `meta/console.updated`. Batch the writes (`ArtifactData batch`). Then the digest in chat is one line plus the console link.

**Phone links.** Every session you start has Remote Control on, so it has a `https://claude.ai/code/session_…` URL. `session-links.py` (this folder) reads it from each transcript's `bridge_status` / `remote_session_change` line; put it in the thread's `link`. On Geoff's phone it opens in the browser, where the session works (F-259).

## Refresh: a full scrub (Geoff, 2026-10-30)

The console's header has a **Refresh** button (Geoff: "please make a refresh button that causes the duo director to do a full scrub of the page, clearing old content (like the outdated version cut question)"). It saves an `answers/refresh-<time>` row and sends "Console · Refresh: …" to the director. When it arrives, the director does all of this before replying:

1. **Needs:** delete every card that's answered, done or out of date (the `answers` collection keeps the history), and delete a release card once that release ships. For each card left, check that its record is still open on main and that what it says is still true. Correct it or delete it.
2. **In flight:** compare every `threads` row with `claude agents --json --all` and the task notes. Delete rows for finished work, add rows for workers that are running or waiting on Geoff, and fix each state and summary.
3. **Release:** `release/current` gets the newest release, what's on main and unreleased, the last gate, and what's next.
4. **Headline:** rewrite `meta/console`'s headline and `updated` with the date and what changed.
5. **Recurring jobs:** check that their latest cards (problem discovery, the weekly tidy-up) aren't stale, and that no scheduled run is stuck on a permission prompt (`list_task_runs`). Each job has a row in `jobs` (Geoff, 2026-10-30: "a section that lets me jump to the output artifacts for the recurring agents … including the last run"): name, schedule, next, its page, its card, and `lastRun` {at, status, headline, link}, which each run updates itself. Mark a stuck run's status "stuck". A new recurring job gets its row when it's scheduled.

The director also deletes needs cards as it goes, not only on Refresh: once a card is answered, and as soon as a release ships.

## The director-console skill (Geoff, 2026-10-30)

Geoff: "we are adding a lot of heuristics to the console; you should probably make a skill to ensure consistency, then the director can just call the skill; this is not a skill we will bundle with duo -- just one I'll use locally (but sync a copy to the repo)". The skill lives in `~/.claude/skills/director-console/` on Geoff's Mac; `docs/director/skills/director-console/` is its copy. It holds the card, row and link conventions (every card links its worker's session and the artifacts to review), and `worker-links.py`, which reads each background worker's Remote Control link and open artifacts from `~/.claude/jobs/*/state.json`. Change the skill first, then copy it here.
