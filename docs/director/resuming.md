# Resuming the Duo dev director

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in _PROJECT.md's `## Director`.*

## 0. Resuming (after compaction or a restart)

**Status first; act on the red lines.** `duo2 director status` from the main checkout, on every wake (the skill's "Your duties" defines a wake) as well as here. Clear what you can in that turn, and anything you can't goes in your next message to Geoff, in plain words with links. Then, after a restart or compaction, rebuild the rest:

1. `gpu-lock.sh --status` and `issue-watch.py` (`_PROJECT.md`). These are duo-v2's own, so status doesn't cover them. Read your memory for Geoff's preferences and hard facts.
2. `git fetch --all`, then `git worktree list`, `git log --oneline -10 origin/main`, `gh pr list`. List the branches ahead of main.
3. `worker-links.py` and `ListAgents`, for sessions the registry doesn't know: status's R1 sees only workers started through `duo2 director start`. A finished session's last message is in its transcript (`~/.claude/projects/-Users-geoff-repos-duo-v2*/<id>.jsonl`; read the tail with a small Python filter for its text).
3a. Idle subscriptions are gone. For each task in flight, subscribe again (`SendMessage(to: "<name>", notify_when_idle: true)`, no message; it answers at once if the worker is idle). After that, workers' reports and idle notices wake you (DL-257). Read the note and last message again whenever a `[Cross-session delivery notice]` says held, expired or refused. Monitor on `duo2 director watch` is only for when `duo2 director status` says messaging can't carry.
4. Re-arm the console: `ArtifactComments` `watch` on the console URL (and the walk page), then read the console's `answers` collection (`ArtifactData list`) and its comment threads for anything sent while you were away. Refresh `threads`, `needs`, `release` and `meta/console` (`console.md`).
5. Tell Geoff in a few lines what's in flight and what's waiting on him: on the console first, then a one-line pointer in chat.

**When something fails, or Geoff complains:** the skill's §11, not a new memory. Here the change is a branch and the eval goes in `skills/duo-director/evals/`, tagged with the duty.
