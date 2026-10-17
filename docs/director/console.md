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
