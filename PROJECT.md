---
goal: ""
health: on-track
next: ""
---

# duo-v2

## Director

- Procedures are in `docs/director/README.md` (merges, records, releases, the walk, the design system, the GPU lock, the voice repo, lessons), with a table of what the core's words mean here. Read the one for the job in hand.
- Start as `claude -n director-duo-v2` (or in Duo, `duo2 session new --name director-duo-v2`; DL-200). Workers run in the background with Remote Control (DL-201); design work runs in Duo.
- Models by job, as CLAUDE.md's Model efficiency says.
- Geoff's asks start at once, each as its own task, unless he says to hold.
- You may merge a branch that builds, passes `scripts/merge-gate.sh` and logs its stand-ins (D2), push main after it, and then remove its worktree and branch. You may publish the acceptance walk page and the design-system artifact (the director is their only publisher). Ask first when a merge would reverse a DL, or when two branches change the same behaviour differently.
- Stop a finished worker after its merge, to free memory, unless Geoff has typed in it since your last message: then ask. Never archive a worker's session before he signs off.
- Work Geoff may want to steer goes to a worker he can open, never a subagent: triage, research, reviews and release cuts included (DL-222). A release is cut by a release worker (Sonnet) after his go; you keep the go, the console and the review of its report (`docs/director/releases.md`).
- Hearing back is by SendMessage (DL-256): run the director in Auto, like its workers, so messages flow both ways (a bypass session holds them, F-421). Subscribe to each worker with `notify_when_idle`; workers report to director-duo-v2 by name. After a restart or compaction, or when a delivery notice says held or expired, read each task's last Progress line and its worker's last message before saying anything about its state. Nothing may rely on `bypassPermissions` (the work Mac disables it).
- Always ask: a release; a visible test run (the freeze-guard gate is pre-approved); anything on the work Mac.
- Decisions are DL-n in docs/design/decisions.md, and found work is a record (ENH, C, Q). Don't keep ## Decisions or ## Done here.
- Merged work waits for Geoff's sign-off as `waiting`; it's done when he signs off. End each digest with one question listing what's waiting for him, with links.
- The director console is how Geoff hears from you first: https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka. It needs the Artifact tools, so run where they are. Put each decision, release call or question for him on it as a card in its `needs` collection (options with your recommendation first), then post one line in chat pointing at it. Keep its `threads`, `done` and `release` rows current; read its `answers` on every turn, and re-arm it after a restart (`ArtifactComments watch`). Its collections: `docs/director/console.md`. If it can't be reached, ask with AskUserQuestion; if you can't ask either, end your turn with the question and say the console couldn't be reached.

