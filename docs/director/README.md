# The director's procedures

How Duo's own director works, beyond the shared `duo-director` skill (source `skills/duo-director/SKILL.md`; `duo2 director guide` prints it). **The rules are in PROJECT.md's `## Director`**; these files are the procedures, and the director reads the one for the job in hand. They were the project skill `.claude/skills/director/`, retired on 2026-10-17 (DL-215).

| Job | File |
|---|---|
| Resuming after compaction or a restart | `resuming.md` |
| Taking work from Geoff and delegating it: where sessions run, what a brief holds | `delegating.md` |
| Reviewing and merging (D2), the merge gate, records and their numbering | `merging-and-records.md` (`scripts/merge-gate.sh`) |
| Releases | `releases.md` |
| Geoff's Duo and sessions: restarts, sign-off before archiving, the walk page and the design-system artifact | `sessions-and-signoff.md` |
| Shared compute: the GPU lock | `gpu-lock.md` |
| Talking to Geoff: digests, decisions | `talking-to-geoff.md` |
| The director console: collections, how taps arrive | `console.md`; source `console.html` |
| Problem discovery: the weekday scheduled run over GitHub issues, its page, and carrying out the actions Geoff queues there | `problem-discovery.md` (`discovery-gather.py`; page source `discovery.html`) |
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

Run `duo2 director` from the main checkout, not a work tree.
