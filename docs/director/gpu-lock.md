# Shared compute: the GPU lock

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in PROJECT.md's `## Director`.*

## 5a. Shared compute: the GPU lock

Every session shares one Mac mini (32 GB, 12 cores). Heavy jobs coordinate through one lock folder, `$GPU_LOCK`. Its path is machine-local: it's in memory `project-gpu-lock.md` and never goes in the repo.

- **Two kinds of hold** (Geoff, 2026-10-12):
  - **Exclusive:** for jobs that need the Mac to themselves. That covers voice model work (training, voicing, evaluation: VoxCPM training alone used 15–18 GB), video renders and the score, and every timing measurement (idle-CPU runs, `check-chat-perf.sh`, `check-scale.sh`, `perf-chat.sh`, matrix runs). An exclusive job waits until every other holder is done, then runs alone.
  - **Shared:** for jobs that only need correct results. That covers `swift build`, `bundle.sh`, DuoChecks, `check-ui.sh`/`check-chat.sh` captures, pixel compares and editor checks. Up to two run at once, and they step aside while an exclusive job holds the lock, so timings stay clean.
- **One script, by its full path,** never a work tree's copy and never a bare `mkdir`: `GPU_LOCK=<lock> <main checkout>/scripts/gpu-lock.sh [--shared|--exclusive] <name> <command…>`. Exclusive is the default, so a job that doesn't say stays safe. Shared jobs hold slots (`GPU_LOCK_SHARED_SLOTS`, default 2), and none starts while an exclusive job holds the lock or waits at the front of the queue, so measurements aren't starved (F-298).
  - Work trees carry older copies that release unconditionally, or treat an owner they can't signal (EPERM in the sandbox) as dead. Two jobs held the lock at once twice on 2026-10-12 (F-296).
  - A job's output that says "clearing a stale lock", or shows the "WARNING: the lock was taken", means its timings are suspect: re-run it.
- **Waiters queue in order** (FIFO tickets in `<lock>.queue/`). See who holds and who waits:
  `cat $GPU_LOCK/owner $GPU_LOCK.shared/*/owner; for f in $GPU_LOCK.queue/0*; do cat "$f"; done` (the exclusive holder, the shared holders, then the queue).
- **Every brief** names the lock line, with the job's kind, and says to release right after each batch.
- **Merge checks:** run the build-and-check part shared, and the timing part (`check-chat-perf`, `check-scale`, the visible gate) exclusive.
- **Watch memory, too:** `sysctl vm.swapusage`, plus the idle Claude sessions in memory. Ask Geoff before stopping his own sessions.
