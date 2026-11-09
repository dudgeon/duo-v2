# Project knowledge pilot

*Hand-run pilot for ENH-325 and DL-322, following `docs/research/project-knowledge.md` §4 and §8. Does a fresh session answer clearly better with a project's `_knowledge/` pages? If not, we stop.*

## The result: stop

**Fresh sessions didn't answer clearly better with the pages, so the recommendation is to stop, as the study said we would.** Right answers, out of 10 per project, with the same answer scored by hand against a model answer:

| Project | Without pages | With pages | Gap |
|---|---|---|---|
| duo-v2 | **10** right | **7** right, 3 partly | 3 worse |
| The couch-spacers project | **7** right, 2 partly, 1 wrong | **8** right, 2 partly | 1 better |
| Both | 17 | 15 | 2 worse |

A dream costs far less than the study feared, the mechanics work, and pages cost almost nothing per answer. None of that matters without better answers. duo-v2's records are good enough that a session finds the answer by grep; the pages then became a second, staler place to look, and sometimes the session stopped there. Details are in §3 onward; §6 says what would be worth reopening it.

**The questions below were written and committed before any page existed** (965d85c6). They become the eval set for any later build (study §8).

## 1. Method, fixed before the runs

- **Two projects:** duo-v2 (its last 14 days) and the couch-spacers project (all of it, about six sessions).
- **Conditions:** *without* pages, the session has the project folder and `duo2 search`, as today; *with* pages, the same plus `index.md`'s text through `--append-system-prompt`, as the SessionStart hook would give it, and it reads pages itself.
- **Each question, in a new session with a minted id,** on Haiku 5.5: the question's text, plus the same instruction to answer in at most 120 words and say where the answer came from.
- **Scoring by hand against the model answer:** right, partly (a fact that matters is missing or hedged away), wrong (including "I can't find it"). A line of reason each.
- **What each session can do:** read, grep and glob; `git log`/`show`/`branch`; `duo2 search` only. Nothing writes.

**Keeping the test clean.** `duo2 search` indexes every work tree and every session, so this doc and the pilot's own session could hand a session its model answers. So:
- The *without* runs happen before any page is in the project folder, so they can't find one.
- During runs this work tree is detached at `origin/main`, so this doc isn't on disk.
- `duo2` in a session's path is a shim that allows only `search` and drops results from this pilot's work tree and session. Each session's tool calls are kept and scanned for leaks.
- Sessions run with `--no-session-persistence`: 80 test sessions and the dreams don't appear in Geoff's Duo, don't enter search, and can't be read by a later dream. The token figures come from the run's JSON result rather than a transcript file. A scratch `CLAUDE_CONFIG_DIR` isn't possible for real turns without copying credentials.

**A bias to keep in mind.** `CLAUDE.md` is loaded in both conditions, and in the couch-spacers project it imports the whole `_PROJECT.md`, so questions it answers tie by design. Some of each ten are answerable from the auto-loaded files on purpose (a page must not make these worse), the rest from other files and session text. I wrote them knowing the transcripts, not knowing the pages. Answers are scored from a shuffled sheet with the condition hidden, though an answer that cites a page gives itself away.

## 2. The questions

### duo-v2 (questions and model answers in full)

**D1. What is this project, what's its newest release, and where do builds and releases happen?**
A Mac app that organizes Claude Code sessions into projects. Newest release v0.2.26 (2026-11-05). Builds, tests and release builds run on Geoff's Mac mini, not in CI; `scripts/release.sh` through the release skill signs, notarizes and publishes.

**D2. My report to the director by SendMessage expired undelivered. Why, and what should I do?**
Messaging works within one permission class (F-421, DL-257): a message between a bypass session and any other is held and expires. Every session runs in Auto; never rely on `bypassPermissions`. The report also goes in the turn's last message and the task note.

**D3. A user's 0.2.23 bounced in the Dock forever at launch. What caused it, and was it a regression in 0.2.23?**
The main thread waited in `DuoApp.init` → `ClaudeLocator.resolve` → `lookUp` → `waitUntilExit`: the login-shell probe, when `claude` isn't in its four usual places and the login shell doesn't answer. Not a code regression: 0.2.22 hangs the same way (F-578, F-573), and the trigger most likely changed on the user's Mac. Fixed by a 3 s timeout (F-564); the hang monitor couldn't see it, so it now also watches the launch.

**D4. Why did Duo sit at about a full core while idle on 0.2.24?**
`SessionArchive.keepAlive` rewrote the date of every listed transcript older than 15 days every minute, because the boundary moved each minute. Each rewrite made the archive re-copy and search re-index them. Fixed with a margin, so each moves about once every two days (F-597).

**D5. What is the weekly tidy allowed to delete?**
`.build`, `build`, `node_modules` and `.venv` inside a duo-v2 work tree idle over 7 days with nothing running in it. It never removes a work tree: stale trees are listed on its card for the director to remove after sign-off (DL-323).

**D6. Which Claude Code version must Duo work on at Geoff's work, and what does that mean for a new feature?**
Management pins it, at 2.1.284 since 2026-10-28, and it will always be months behind; 2.1.219 is the old floor. Chat and hook features get tested against the pinned version, and no default may assume a recent CLI without a working fallback.

**D7. `/fork` says "Workspace not trusted". Why, and what does Duo do about it?**
Claude Code's own trust check stops at the git root. When a folder above the repo is already trusted, Duo shows a "Trust this folder" notice; its action asks in a Duo sheet, then Duo writes the one key `hasTrustDialogAccepted = true` for the repo's top in Claude Code's `.claude.json` (DL-227, DL-229).

**D8. What's in flight on project knowledge, the director's learning loop and recurring jobs, and where does each stand?**
The learning loop's design (slice 1) is merged (DL-319 to DL-321) and slice 2 is being built on a branch. Project knowledge is direction only (DL-322), with this pilot running and nothing built. Recurring jobs' design is finished on `feature/recurring-jobs`, not merged, nothing built; the dream would be its first customer but doesn't depend on it yet.

**D9. How does a finished branch get onto main: who does it, what checks run, and where's the procedure?**
The director reviews, merges and pushes; a build session doesn't push. `scripts/merge-gate.sh <merge sha>` runs the gates (records, hygiene, bundle, DuoChecks, check-ui) in the director's own work tree, never the main checkout's `build/`. Standing rule: it merges without asking unless a merge reverses a DL or two branches change the same behaviour differently. Procedure: `docs/director/merging-and-records.md`.

**D10. What did ⌘W do with the keyboard in a browser tab or HTML page, and what does it do now?**
It fell through to `closeVisibleSession()` and ended the console's Claude session, because only the Markdown editor's focus counted. Now the keyboard being in the right pane sends ⌘W to that pane's tab (F-495).

D1, D2 and D6 are the ones the auto-loaded files mostly answer.

### The couch-spacers project (titles only)

Questions and model answers are in a machine-local file, `~/.duo-knowledge-pilot/couch-model-answers.md`, and never enter this repo.

- C1. What the project is
- C2. Standard label rule
- C3. Cut size for a square leg
- C4. Labels after a custom cut
- C5. Blank Personalization
- C6. What custom pairs weigh
- C7. space-jam branch state
- C8. What's in flight
- C9. Sending a buyer reply
- C10. What's untested in triage

C1, C2, C3, C4 and C9 are the ones the auto-loaded files mostly answer.

**Two changes after the commit.** D7's text became "The /fork command says…", because a leading `/fork` ran as a slash command and returned nothing; both conditions used the new text. D8's model answer went stale during the runs, when `feature/recurring-jobs` merged to main, so D8 was scored against the fact at scoring time.

## 3. Scores

Scored from a shuffled sheet with conditions and page names hidden, written down before the key was opened. An answer that mentions a page can still give itself away, and one person scored. Haiku 5.5 ran every turn (checked in each run's `modelUsage`).

### duo-v2

| Q | Without | With | Reason where they differ |
|---|---|---|---|
| D1 Project, release, builds | right | right | |
| D2 Expired SendMessage | right | right | |
| D3 0.2.23 launch hang | right | right | |
| D4 A core at idle on 0.2.24 | right | **partly** | With: led with the refresh and named keep-alive without why it burned a core. The page's first paragraph is the refresh |
| D5 Weekly tidy | right | right | With: checked the decision and noticed the page was out of date |
| D6 Claude Code version at work | right | right | |
| D7 `/fork` not trusted | right | right | |
| D8 In flight | right | **partly** | With: repeated the page's stale state of the learning loop and a question already decided (DL-323) |
| D9 Branch onto main | right | **partly** | With: answered from the page, didn't open the procedure, and lost the standing rule and most of the gates |
| D10 ⌘W | right | right | |

### The couch-spacers project

| Q | Without | With | Reason where they differ |
|---|---|---|---|
| C1 What the project is | right | right | |
| C2 Standard label rule | right | **partly** | With: the rule, then hedged away as "disputed". A recorded decision; the dispute is the dream's error (§5) |
| C3 Cut size for a square leg | right | right | |
| C4 Labels after a custom cut | right | right | |
| C5 Blank Personalization | **wrong** | right | With: the page carries a lesson that sits deep in a long skill file, which the session without pages didn't open |
| C6 What custom pairs weigh | right | right | |
| C7 space-jam branch state | right | right | |
| C8 What's in flight | **partly** | right | Without: wrongly let a director start several tasks on its own. With: the page holds who owns what |
| C9 Sending a buyer reply | **partly** | right | Without: missed one step of the rule |
| C10 What's untested in triage | right | **partly** | With: called three things unproven that ran live, following a stale page |

**How firm is it?** Counting a partly as half gives duo-v2 10 against 8.5, and the couch-spacers project 8 against 9. Fixing the filter bug in §5 would plausibly turn C2 right, making that project 9 against 7. Even that is two questions in ten, on one small project, with duo-v2 going the other way. No fair reading gives the visible gap the stop rule asks for.

**A bias against the pages.** I checked each duo-v2 model answer against the records, so those answers are findable in the repo by construction. A question whose answer lives only in a transcript would favour pages, but no such question in either set decided a score: the only transcript-sourced fact, C6, was also in a task note. That's weak evidence of how much of what matters stays only in transcripts, not proof.

**What the baseline actually was.** No session in either condition ever ran `duo2 search`. All 40 answers came from the auto-loaded files, grep, reading files, `git` and `gh`. So this doesn't test search against pages: sessions did this well without it.

## 4. Cost

| Dream | Input | Turns on Haiku | Wall time | Tokens: cache write / cache read / output | CLI's list figure |
|---|---|---|---|---|---|
| The couch-spacers project | 6 sessions, 83 KB filtered from 30 MB; 21 task notes; 4 memory files | 21 (5 subagents) | 4 min 50 s | 0.21 M / 0.91 M / 0.11 M | $0.10 |
| duo-v2, run 1 (killed at my 55-minute limit, no pages) | 114 sessions, 3.7 MB filtered from 2.25 GB; 57 task notes; 22 memory files | 71 subagents, 52 min analyzing | 55 min | 3.70 M / 11.61 M / not reported | none: a killed run gives no total |
| duo-v2, run 2 (Organize only, from run 1's files) | 1 MB of run 1's analysis | 141 | 10 min 15 s | 0.29 M / 10.72 M / 0.14 M | $1.18 |

**Input folders for duo-v2:** the main transcript folder and every work-tree folder beside it, which is why this is 114 sessions against the study's 50. The filter kept 0.17% of the raw bytes, close to the study's 0.14%.

A dream is cheap on money and heavy on quota and time: the study's "about $270" for raw input isn't close, but a first dream of 14 busy days took over an hour and more than 26 million tokens, mostly cached. The study's cap of 20 closed tasks per run (§4a) is needed: without one, a first dream doesn't finish in a turn.

| Per answer, mean | Tokens in all | Output tokens | CLI's list figure | Wall time |
|---|---|---|---|---|
| duo-v2 without | 63,215 | 1,278 | $0.0041 | 8.2 s |
| duo-v2 with | 55,383 | 1,016 | $0.0039 | 7.0 s |
| The couch-spacers project, without | 35,027 | 1,127 | $0.0026 | 8.1 s |
| The couch-spacers project, with | 39,411 | 1,028 | $0.0028 | 6.5 s |

Pages neither save nor cost anything that matters per answer. Sessions opened a page in 6 of 10 duo-v2 answers and 8 of 10 in the other project.

Token figures come from the runs' JSON results, not transcript files, because the runs were not persisted (§1). The CLI's dollar figures aren't consistent with one price list across runs, so read tokens first.

## 5. What the pages got right and wrong

**Right, and better than I expected from Haiku.** Pages were one topic each, stated what's true now rather than telling a story, and cited records. They kept the corrections Geoff made and what was tried and failed, which is the part a log buries. The GPU leak and launch-hang pages are good summaries. In the couch-spacers project, the pages surfaced a lesson (C5) and who owns which task (C8).

**Wrong:**

1. **The filter loses what the user types mid-turn.** Those messages are stored as `queued_command` attachments, not user messages, so §3's filter drops them. It dropped 58 of Geoff's messages in 20 sessions of duo-v2's window, and these are often corrections. In the couch-spacers project this produced a false dispute: the page called a recorded decision unconfirmed because its source message was invisible, which cost C2.
2. **The dream wasn't given the project file.** `gather` as §4 lists it doesn't include `_PROJECT.md`, so the dream couldn't see the decision that would have settled that dispute under its own trust order.
3. **Too many disputes, some false.** 8 of duo-v2's 25 pages are `disputed`. Some conflicts are real. Others are noise it could have resolved in one read: it disputes which of two paths holds the decisions log, and whether a hold limit is what the script says. A dispute goes to the user, so this is where the human touchpoint fails.
4. **In-flight pages go stale at once.** The window closed hours before the runs and D8 still suffered. Worse, duo-v2 keeps moving: a page's "unanswered" became a decided question the same day. `stale_after` at 14 days doesn't help a fact that lasted hours. C10's error is the same: a page said a cut wasn't confirmed when a later session shows it was.
5. **`sources` lost provenance.** Most sources are analysis batch ids (`S10.26`), which mean nothing after the run, not session ids.
6. **`checked` overstates.** Every page says "by reading its sources"; run 2's report admits it worked from digests and spot-checked two facts.
7. **Pages substitute for primary sources.** In D9 a session read the page and stopped, though the page names less than the procedure does. Being on the index makes a shorter, older answer look sufficient (study §7).
8. **The index cap bites.** 25 pages came to 5,698 characters. Meeting 4,096 meant cutting every description to 80 characters, which removes the concrete terms a session uses to choose a page.
9. **A date trap:** transcripts are in UTC, so the dream flagged evening facts as "after today".
10. **Privacy:** one page named a private folder, in a rule about not naming it. The check caught it, and it's the only edit I made to the dreams' text. I applied everything else as written, including the errors, because the study applies dreams without review and this should measure what a dream really produces.

## 5a. Mechanics

| Check | Result |
|---|---|
| `git status` with `_knowledge/` in `.git/info/exclude` | **Clean.** Checked with a probe folder in this work tree, which shares the exclude file (`git check-ignore -v` names it), and in the couch-spacers repo, which holds the real pages. A session guard stops this work tree running git against the main checkout, but Duo's own Files header below reads that checkout: "up to date with GitHub" |
| `duo2 search` finds a page's text | **Yes,** in both projects, within minutes. Index "complete" at 2,673 duo-v2 files. So search reads `.git/info/exclude`d files, as the study read from the code |
| Duo's file tree shows the folder | **Yes.** `_knowledge/` is listed in the Files pane in an isolated, background capture (kept on this Mac) |

`build/Duo.app` in the main checkout is **old**: version 0.0.1 from Oct 12, before the isolation guard. As the brief says, I didn't build it, and I didn't run a binary without the guard. The tree check used the director's own current build (`v0.2.26-49-g42b3a5f5`), launched directly so Launch Services doesn't register it (DL-151), under the shared GPU lock. As the brief's `--workspace <duo-v2>` opens no project (a workspace's children are its projects), the capture used the parent folder and opened duo-v2.

**The study's limits (§7; the brief calls it §9) as seen here.**
- *It may not help:* it didn't.
- *Accreted knowledge can be confidently wrong:* seen, in a false dispute and stale in-flight facts.
- *A bad dream reaches every session:* seen in small: C2's false dispute reached the answer.
- *Injection:* no sign of one in these runs, and none was attempted; it wasn't tested.
- *The work-tree path:* not tested. All answers ran at the main checkout.
- *Kept out of git, on one Mac:* confirmed as designed.

**Other departures from the brief.** A script, not a Sonnet subagent, did the filtering, and Haiku alone drafted the pages, so the cost figure is Haiku's. A dream's batches ran per session rather than per closed task, because the duo-v2 window's work isn't all in closed tasks. The couch-spacers repo has no remote, so pages could have just sat there; I used its `.git/info/exclude` as well, to keep Geoff's `git status` clean.

## 6. Recommendation

**Stop.** Don't build `duo2 knowledge`, the hook or duty R10. The gap the study required isn't there: 2 fewer right answers across both projects, and 3 fewer in the project with the most history, which is the one the feature was meant to serve.

**Clean up on Geoff's yes:** delete `_knowledge/` from both project folders and its line from each `.git/info/exclude`. Left in place, the pages keep appearing in grep and search, and they're already going stale.

**What would reopen it, with this eval set kept:** evidence that fresh sessions miss knowledge that exists only in transcripts, which these questions barely test. A retry needs the fixes in §5 first: keep `queued_command` messages, give the dream the project file, keep in-flight facts out of pages (a page shouldn't hold what `tasks/` and git answer live), resolve a dispute by reading before raising it, and keep real session ids as sources. The small gain in the couch-spacers project hints that a project with few records may benefit more than one with many, but one point in ten on one project isn't a finding. Its gain could also come more cheaply from moving those lessons into the project file a session already loads.

