# Shared compute: the GPU lock

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in _PROJECT.md's `## Director`.*

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
- **A hold has a time limit** (F-510), from when the command starts. A caller that sets `GPU_LOCK_MAX_MIN=<minutes>` or `GPU_LOCK_ENFORCE=1` gets it enforced (60 min exclusive, 45 shared): the script TERMs, then KILLs, the command's own process group, releases, prints `gpu-lock: <owner> exceeded <n> min; ended` and appends to `<lock>.log` (exit 124). A caller that sets neither (a long film render from another repo) is only warned, at that limit and every 15 min after, and is ended at a 6 h backstop. `GPU_LOCK_MAX_MIN=0` and `GPU_LOCK_MAX_REASON=<why>` (voice fine-tunes) turn the limit and the backstop off; the reason is logged. duo-v2's `merge-gate.sh` enforces, and timing runs go through `scripts/timing-lock.sh <name> <command…>` (exclusive, enforced). `gpu-lock.sh --status` lists holders and waiters with ages.
- **Every brief** names the lock line, with the job's kind, and says to release right after each batch.
- **Merge checks:** run the build-and-check part shared, and the timing part (`check-chat-perf`, `check-scale`, the visible gate) exclusive.
- **Watch memory, too:** `sysctl vm.swapusage`, plus the idle Claude sessions in memory. Ask Geoff before stopping his own sessions.

**Reading `--status` (F-658).** An `exclusive holder` line with a `shared holder` line beside it is normal while the exclusive job says "waiting for shared jobs to finish": it has the lock directory and is waiting for the shared jobs already running, and nothing new starts. Only "running, alone" means its command has begun. `scripts/check-gpu-lock-race.sh [rounds]` is the repro.
