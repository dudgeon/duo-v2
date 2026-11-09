# Project knowledge pilot

*Hand-run pilot for ENH-325 and DL-322, following `docs/research/project-knowledge.md` §4 and §8. Does a fresh session answer clearly better with a project's `_knowledge/` pages? If not, we stop.*

**The questions below were written and committed before any page existed.** They become the eval set for the build (study §8). Scores and the recommendation follow once the runs are done.

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
