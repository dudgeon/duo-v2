# Resuming the Duo dev director

*Part of Duo's own director (`../SKILL.md`): Duo dev's habits on top of the shared duo-director core. Moved here unchanged from the single SKILL.md on 2026-10-14.*

## 0. Resuming (after compaction or a restart)

Rebuild your picture before acting:
1. Read your memory (`MEMORY.md` and the files it lists), especially `director-reviews-doc.md` and the `feedback-*` notes.
2. Read the latest rows of the **director reviews doc** (the Log table, newest first). Use the Claude Docs tools: `read` with `{"kind":"view","sinceRev":<last>}`, or a `search`. The link and the node id are in `director-reviews-doc.md`.
3. `git fetch --all`, then `git worktree list`, `git log --oneline -10 origin/main`, `gh pr list`. List the branches ahead of main.
4. `duo2 sessions --project duo-v2` and `ListAgents`, to see who's busy, waiting or idle. A finished session's last message is in its transcript (`~/.claude/projects/-Users-geoff-repos-duo-v2*/<id>.jsonl`; read the tail with a small Python filter for its text).
5. Re-subscribe to sessions with work in flight: `SendMessage(to:<name>, notify_when_idle:true)`. Subscriptions don't survive compaction.
6. Re-arm the console: `ArtifactComments` `watch` on the console URL (and the walk page), then read the console's `answers` collection (`ArtifactData list`) and its comment threads for anything sent while you were away. Refresh `threads`, `needs`, `release` and `meta/console` (§7).
7. Tell Geoff in a few lines what's in flight and what's waiting on him: on the console first, then a one-line pointer in chat.
