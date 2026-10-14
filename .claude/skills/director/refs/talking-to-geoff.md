# Talking to Geoff, and the console

*Part of Duo's own director (`../SKILL.md`): Duo dev's habits on top of the shared duo-director core. Moved here unchanged from the single SKILL.md on 2026-10-14.*

## 6. Talking to Geoff

- **The console is the default channel** (Geoff, 2026-10-09: "the primary way that I interact with the Duo Director; I can still fall back to the chats but the duo director will default to use the artifact"). Put each decision, release call, delegation call or question for him on the console (§7) first, then post one line in chat pointing at it. Use AskUserQuestion only when the console can't reach him (it says "Director away") or he's answering in chat anyway. **On his phone, catching up** (2026-10-12; his console taps weren't arriving): pick the most important phone-friendly decisions and ask them **one at a time** by AskUserQuestion, numbered "n of ~N", recommendation first, with any artifact link inside the question. Leave desk-only reviews (the walk, paper cuts, many-board design picks) for a desk, and close the answered console cards afterwards.

- **End-of-block digest** (Geoff, 2026-10-08): after a stretch of work (merges, a release, a batch of reports), send one short digest instead of a running commentary:
  ```
  Done: <merged/released, one line each, with shas>
  Needs you: <decisions and looks, each with a link or button>
  Next: <what's running and what lands next>
  ```
  At most about 10 lines. Acknowledge stale idle notices in one line, or not at all.

- Lead with what happened and what's waiting on him. Explain the cause of any failure, including your own mistakes, plainly.
- Put decisions to him as console cards (buttons, recommendation first, plus his own words); AskUserQuestion buttons (at most 4 × 4, recommendation first) are the fallback. Never through doc dropdowns.
- Don't re-ask anything he has already given you (standing approvals: D2 merges, archiving, restarting Duo, sessions outside Duo with Remote Control by default, patch versions).

## 7. The director console

A private claude.ai page Geoff opens on his phone or desktop: https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka. Source: `.claude/skills/director/console.html`. Published from this session with `capabilities: {"db": {}, "comments": {}}` (DL-166).

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

**Phone links.** Every session you start has Remote Control on, so it has a `https://claude.ai/code/session_…` URL. `session-links.py` reads it from each transcript's `bridge_status` / `remote_session_change` line; put it in the thread's `link`. On Geoff's phone it opens in the browser, where the session works (F-259).

**Peer name.** Sessions reach the director by its peer name, which is the first line of `ListAgents` (F-259). **It changes whenever the director's session restarts** (`duo-v2-ef` until 2026-10-12, then `duo-v2-b0`). After any restart, message every active session with the new name, and put the current one in every brief. Sessions reply to the `from` of your latest message. **Never let sessions message `*DUO DIRECTOR*`:** the retired first director (e0127e51) was a Remote Control session that woke up when messaged. It was stopped on 2026-10-12. If it shows in `ListAgents` again, stop its process (find its pid in `~/.claude/sessions/*.json`).
