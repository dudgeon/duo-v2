# Reviewing, merging and records

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in _PROJECT.md's `## Director`.*

## 2. Reviewing and merging (standing rule D2)

You may merge without asking when a branch builds, passes the checks and leaves undrawn things logged as stand-in questions. Ask Geoff first when a merge would reverse a DL, or when two branches change the same behaviour differently.

For each branch:
1. **Look at the evidence yourself:** open its compare and strip PNGs (`Read`), and the diff for risky areas (core data paths, hooks, anything touching Geoff's real files). For anything that publishes to a public repo, check for personal details.
2. **Take a baseline:** `cp build/ui/{overview,project,flow-zoom-1,flow-zoom-2,flow-zoom-3,flow-zoom-4}.png /tmp/dir-base/`, and when chat is touched, every `build/ui/chat-*.png` capture (not `-compare`/`-board`) to `/tmp/dir-chatbase/`. After the merge, rerun `check-chat.sh` and `samepng.py` each one, reading its printed count (it always exits 0, so a loop on its exit code reports no differences; 2026-10-10): an existing board that changes is a regression until explained (2026-10-07: a lost composer caret revealed a focus bug). Also run `NO_BUILD=1 scripts/check-composer-focus.sh` (no composer of a chat that isn't on screen may hold the keyboard).
3. **Merge:** `git merge --no-ff -m "Merge <branch>: <what> (<records>)" <branch-or-sha>`.
4. **Record files merge without conflicts** (`.gitattributes` `merge=union`, 2026-10-08): both sides' lines are kept. Still run `scripts/check-records.sh`: a row both sides edited comes out twice, so delete the older copy. A union merge can also drop the blank line between findings sections (harmless). Older rule, for any conflict that still appears: **keep both sides, never one.** When both sides edited the same row, keep the newer content. A conflict hunk can hold many records from main (c6aa7c8 once dropped F-114 to F-119).
5. **Check, never in the main checkout's `build/`** (2026-10-12). Geoff's own Duo may run from `build/Duo.app`. That bundle is signed ad hoc, so every rebuild changes its identity to macOS, his privacy answers stop sticking, and the prompts repeat. Run every build and check in the director's own work tree, `.claude/worktrees/director-check`: `git -C .claude/worktrees/director-check checkout --detach <merge sha>`, then the scripts there. Its builds are `com.dudgeon.duo.test` (DL-151). Rebuild main's `build/Duo.app` only when Geoff asks.
   - **`scripts/merge-gate.sh <merge sha>` runs the list below as one command** (each gate under the main checkout's `gpu-lock.sh --shared`, one line per gate, non-zero on any failure). The list says what it covers; the baseline comparison, `check-launch-services.sh` and the timing checks stay by hand.
   - `scripts/check-records.sh` (every record id from both parents survives);
   - `scripts/check-hygiene.py --summary`: warnings only, never a failure (records whose text holds the answer, old stand-ins, stale task notes, design README against `surfaces.md`, the feature catalogue; ENH-281 to ENH-285). Every gate's result goes to a machine-local run log, and a gate that passes only on retry prints FLAKY (ENH-284). `MERGE_GATE_IDLE=1` adds the idle fitness function under the exclusive lock (ENH-286, opt-in);
   - `scripts/bundle.sh`;
   - `swift run DuoChecks` (and `DUO_CHECKS=chat` when chat is touched);
   - `NO_BUILD=1 scripts/check-ui.sh`, then `python3 scripts/samepng.py /tmp/dir-base/<s>.png build/ui/<s>.png` for the six states. A difference must be explained (an intended change) or it's a regression; check main without the merge before blaming the branch. Run the checks inside `scripts/check-background.sh -- …` (or plain `scripts/check-background.sh` for check-ui, check-chat and check-composer-focus together): it fails if a test Duo came to the front, ran as a Dock app or captured while active (F-227). With the screen locked it says the front-app part proves nothing.
   - `scripts/check-launch-services.sh` after every merge (and `--clean` if it fails): only main's build may be registered as Duo (DL-151). Branches made before 76fb3e6 must merge main before their next bundle.sh (C-55).
   - The editor and deck checks when relevant: `NODE_PATH=/tmp/pwc/node_modules node scripts/check-editor-selection.mjs` (also check-editor-motion and check-deck-motion). playwright-core lives in /tmp/pwc; `npm i playwright-core` there if it's missing.
6. **Keep the living docs current** (DL-240):
   - a branch that changes what a feature does updates its row (FEAT-n) in `docs/product/features.md`, the feature catalogue, or adds a row for a new feature (the next FEAT number; numbers are never reused, and a retired feature keeps its row marked `Status: retired (DL-n)`). `merge-gate.sh`'s hygiene line warns when `Sources/` changed and the catalogue didn't; a merge that isn't a feature change says so in its message;
   - a surface whose status changed updates `docs/design/system/surfaces.md` and the handoff's row in `docs/design/README.md` (the hygiene line warns on a mismatch);
   - after the merge, republish the design system if `docs/design/system/` changed.
7. **Push,** then remove the work tree and branch (local and origin), message the session ("merged, you're done").
8. **Never push a merge you haven't checked.** If you find a problem, `git reset --hard origin/main` (only for an unpushed local merge) and send it back with specifics.

## 3. Records

Record numbers are shared across sessions and collide easily. Before reserving numbers, `git fetch --all` and take the max over main and every branch. Give each parallel session its own range. If a session takes a number you'd given someone else, move the other session to the next free one at once. After every merge, `scripts/check-records.sh`.
