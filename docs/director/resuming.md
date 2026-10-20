# Resuming the Duo dev director

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in PROJECT.md's `## Director`.*

## 0. Resuming (after compaction or a restart)

Rebuild your picture before acting:
1. Read your memory (`MEMORY.md` and the files it lists), especially the `feedback-*` notes, and the task notes in `tasks/` (they are what's in flight).
2. `git fetch --all`, then `git worktree list`, `git log --oneline -10 origin/main`, `gh pr list`. List the branches ahead of main.
3. `duo2 sessions --project duo-v2` and `ListAgents`, to see who's busy, waiting or idle. A finished session's last message is in its transcript (`~/.claude/projects/-Users-geoff-repos-duo-v2*/<id>.jsonl`; read the tail with a small Python filter for its text).
3a. **On every wake** (a notice, a Monitor line, Geoff's message, not only after a restart), for each task in flight: read its note's last Progress line and the worker's last message (`duo2 session show <id>`, or the transcript tail) before saying anything about its state. Don't wait for SendMessage: it is held between permission modes (DL-222). Re-subscribe (`notify_when_idle`) and re-arm Monitor on `duo2 director watch` as bonuses; Monitor expires every 30 minutes, so re-arm it until no worker runs.
4. Re-arm the console: `ArtifactComments` `watch` on the console URL (and the walk page), then read the console's `answers` collection (`ArtifactData list`) and its comment threads for anything sent while you were away. Refresh `threads`, `needs`, `release` and `meta/console` (`console.md`).
5. Tell Geoff in a few lines what's in flight and what's waiting on him: on the console first, then a one-line pointer in chat.
