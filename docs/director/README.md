# The director's procedures

How Duo's own director works, beyond the shared `duo-director` skill (source `skills/duo-director/SKILL.md`; `duo2 director guide` prints it). **The rules are in _PROJECT.md's `## Director`**; these files are the procedures, and the director reads the one for the job in hand. They were the project skill `.claude/skills/director/`, retired on 2026-10-17 (DL-215).

| Job | File |
|---|---|
| Every wake: `duo2 director status` first, then act on its red lines | The skill's "Your duties" |
| When something fails or Geoff complains: cause, duty, change, eval, ship. **Not a memory** | The skill's §11 |
| Resuming after compaction or a restart | `resuming.md` |
| Taking work from Geoff and delegating it: where sessions run, what a brief holds | `delegating.md` |
| Reviewing and merging (D2), the merge gate, records and their numbering | `merging-and-records.md` (`scripts/merge-gate.sh`) |
| Releases | `releases.md` |
| Geoff's Duo and sessions: restarts, sign-off before archiving, the walk page and the design-system artifact | `sessions-and-signoff.md` |
| Shared compute: the GPU lock | `gpu-lock.md` |
| Talking to Geoff: digests, decisions | `talking-to-geoff.md` |
| The director console: collections, how taps arrive | `console.md`; source `console.html` |
| Problem discovery: the daily scheduled run over GitHub issues, its page, and carrying out the actions Geoff queues there | `problem-discovery.md` (`discovery-gather.py`; page source `discovery.html`) |
| Dependencies: the geoff-voice repo | `voice-repo.md` |
| Recurring jobs (DL-240): the weekly tidy-up, the fortnightly deep review, and the one-off feature catalogue brief | `weekly-tidy.md` (`tidy-gather.py`), `deep-review.md`, `feature-catalogue-brief.md` |
| Lessons, and where things are | `lessons.md` |

`session-links.py [id-prefix...]` prints the phone link of each session (put it in the console's `threads` row).

## What the core's words mean here

| The core says | In duo-v2 it means |
|---|---|
| Accept | Merge under D2 (see `merging-and-records.md`) |
| The project's checks | `scripts/merge-gate.sh <sha>` |
| Decisions | DL-n in `docs/design/decisions.md` (no `## Decisions` section) |
| Done | Merged to main, plus Geoff's sign-off |
| Found work | A record: ENH-n, C-n or Q-n |
| Complete a task | Geoff's sign-off, never before |
| Archive a session | Only after sign-off, and only after reading its transcript for his own messages |
| A failure's change and its eval (§11) | A branch, and a case in `skills/duo-director/evals/` tagged `duty-Rn`. This repo is the upstream, so no issue is needed. A new duty also needs its row in the skill, a case in `DirectorRedLines` and a fixture in `DirectorDutyChecks`, which fails the build without them |
| Memory | Geoff's preferences and hard facts only |

Run `duo2 director` from the main checkout, not a work tree.

**The director skill in cloud sessions** (Geoff, 2026-11-07). Cloud sessions (claude.ai/code, and Code sessions started from the phone) read none of the Mac's `~/.claude`; they load skills from Geoff's claude.ai account. So the director keeps a copy there: when `skills/duo-director/SKILL.md` changes, build `director/SKILL.md` from it (the `{{FORMAT}}`/`{{REVISION}}` header replaced by one naming the account copy and the commit), zip the folder, and upload it at claude.ai › Customize › Skills (Add › Upload skill; replace the old one) with Claude in Chrome's file upload. Geoff doesn't do this step. The description may not contain anything that looks like an XML tag (`<project>`), or the upload is refused.
