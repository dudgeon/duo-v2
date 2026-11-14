# Multi-window slice 1: regression test before 0.2.24 (2026-11-04)

Geoff (2026-11-04): "include multiwindow slice 1 -- but thoroughly test to make sure it has no regressions."

**Under test:** `main` at `09dd53cf` (slice 0 AppCore, slice 1 `9fe28eb9`, and later fixes), release build from `scripts/bundle.sh release` in the work tree `test/mw-slice1-regression`.
**Baselines:** v0.2.22 (the release users have) and v0.2.23 (pre-release). I added 0.2.23 because `main` is 195 commits past 0.2.22 and 57 past 0.2.23, so the 0.2.22 diff mixes in split view, the formatting bar, DL-315 and others. Diffing against 0.2.23 isolates what came after it, which is mostly multi-window.
**Known gaps, not failures:** slice 2 (windows restored on relaunch, C-153) and the rest of C-152.

Tools: [`2026-11-04-mw-slice1-regression/tools/`](2026-11-04-mw-slice1-regression/tools/) (set `OLD` and `OLD23` to the two baseline apps, see `lib.sh`). Captures: `2026-11-04-mw-slice1-regression/captures/`. The raw outputs (`raw/…` paths cited below) are **not committed**: the "isolated" instances read Geoff's real search index and archive (F-583), so their `search`, `doctor` and diff outputs hold his real paths and document text. They stay in the author's scratch folder; the tools regenerate them.

## Verdict

**Regressions: no, none in single-window behaviour.** Across the 124-verb `duo2` sweep, the menus, the fixture-state captures, the upgrade restore and the performance runs, one window on `main` behaves like 0.2.22/0.2.23 except for changes that trace to a decision (table below). **Performance is not a regression:** `check-scale` read 5.1% and 6.3% on `main`, 6.6% on 0.2.22 and 7.8% on 0.2.23, measured back to back in one exclusive hold.

**Defects in the new multi-window feature itself (not regressions, since 0.2.22 has no windows):**

| # | Severity | What |
|---|---|---|
| F-581 | Medium, unverified | `duo2` run with `DUO_SESSION_ID` set to a session shown in window 2 acted on window 1 (see below). Needs a live check from a real in-Duo terminal. |
| F-582 | Low | `duo2 open <project> --window N` for a project that lives in another window prints "Opened refunds." though it only brought that window forward. |
| Q-460 | Question | After "the last window hides", `window new` gives two windows, one of them the hidden one. |

**Coverage is not complete.** See "What this run did not cover" (C-160): live-workspace captures never left All projects, so project, document and split visuals were checked only through fixture states, and several flows in the brief were not run.

## Incident during this run (read this)

About 22:27 to 22:28 EST on 2026-11-03, my first `duo2` sweep of the `main` build ran against **Geoff's real Duo** (0.2.22, the one at `/Applications`) for about 60 s. A parallel capture run shared my scratch folder and wiped the isolated instance's `endpoint.json`. The harness did not check it, so `DUO_SOCKET` and `DUO_TOKEN` were empty, and a `duo2` with no socket reaches the running Duo (the CLAUDE.md warning). The 0.2.22 and 0.2.23 sweeps were isolated and unaffected.

Reported at once to director-duo-v2 with this list. Geoff then told me directly to run the repairs, so I did, minimally, before the director's stop arrived; the director confirmed carrying on isolated-only.

**State-changing commands that reached the real Duo, in order** (the sequence is steps 1 to 124 of `tools/sweep.sh`; timestamps were not logged, and I deleted that run's raw output while redoing it):
`settings claude-path <stub>`; `go all`; `view home list|board`; `view sort name|recent`; `view filter`; `view sidebar hide|show`; `view right hide|show`; `view hidden on|off`; `peek open|close`; `open checkout`; `doc open` (prd, windows-notes, mixed-endings, field-trial-review deck, checkout.html); `doc mode`; `doc insert "regression line"`, `doc save`, `doc revert --all`; `view tab next|previous`; `view pane next|left`; `doc close --others`, `doc close`; `comment add prd.md`; `task new "Regression task"`, `task status`, `task rename`; `group new`; `file new`/`file rename` (these landed in my work tree, not Geoff's); `session new --project checkout --name "Regress session"`; `shell new`; `session chat --default last`; `settings notify off`; `settings appearance dark|classic|system`; `settings explainers reset`; `go home`; `project archive reading` (timed out, no effect), `project unarchive`; `undo` (undid only my "New Group"). The rest were read-only.

**Repaired:** claude-path back to `auto`; notify back to `on`; comment c1 deleted from `~/DuoAcceptance/workspace/payments/checkout/docs/prd.md` (its frontmatter `---` was wrapped in comment markup; it is intact again); "Regression task 2" note gone; session `cc7c21c0` gone; stray file in my work tree removed.

**Not recoverable or unknown:** Geoff's dismissed explanations (the reset ran; the old list is unknown); the old values of `session chat --default` and claude-path (guessed `auto`); his view state (ended on Board, sort by recent; several document tabs and a shell remain open in his `checkout` project).

**Fixes in the harness:** it now aborts unless `DUO_SOCKET` and `DUO_TOKEN` are set and the socket is inside that run's own folder, every run has its own `/tmp/mwr-<tag>` folder, and read-only support folders are made writable before cleanup (the old cleanup failed and let state leak between launches). The director is finishing the `duo2` isolation guard (F-529); once merged, set `DUO_ISOLATED=1` on every run.

**Also found:** even a correctly isolated instance reads Geoff's real data. Its `duo2 doctor` reports his real session archive (399 sessions, 4 GB) and `search-status` lists his 87 real projects. This is the same in 0.2.22, so it is not a regression, but an "isolated" run is not fully isolated for reads (F-583).

## 1. One window against 0.2.22 / 0.2.23

Same scripted flows on each app: its own support folder, scratch `CLAUDE_CONFIG_DIR`, the acceptance fixtures copied from `scripts/acceptance/fixtures.py` into a scratch HOME, a stand-in `claude`. "=" means identical after normalising ids, times and scratch paths.

| Flow | 0.2.22 | 0.2.23 | main | Verdict |
|---|---|---|---|---|
| `duo2` sweep, 124 verbs: output and exit codes (`raw/diff-*.txt`) | baseline | 101 same, 24 differ | 105 same, 20 differ vs 0.2.23 | All differences explained below |
| Verbs new since 0.2.22 (`view format-bar`, `split*`, `window*`) | unknown command, rc 64 | `view format-bar`, `split` exist | `window*` exist too | Intended (DL-275, DL-317, DL-311..314) |
| `status` pane at launch | `left` | `left` | `middle` | Intended: DL-315, All projects starts with the sidebar collapsed (F-558) |
| `help` / `help --markdown` | | | adds a Windows family and 11 lines | Intended |
| `settings`, `projects`, `sessions`, `tasks`, `groups`, `files`, `doc *`, `comment *`, `task *`, `file *`, `session new`, `search`, `undo`, bad-argument errors | | = | = | No difference. Row order of same-age sessions varies in every run, including 0.2.22 against itself: noise. |
| Menus, text with enabled/dim state (`raw/menus-*.txt`) | 201 lines | 211 | 232 | Only additions: New Window ⌥⌘N, Open in New Window, Window Colour (13 colours), and the Window menu names a window by its project. Nothing removed, nothing newly dimmed. Intended (DL-311, DL-312) |
| Fixture states ×6, light, dark, Classic (`raw/pix-*.txt`) | | `overview`, `flow-zoom-1`, `-4`: 0.176% differ, in the breadcrumb strip | `project`, `flow-zoom-2`, `-3`: 0.144% in the breadcrumb strip | One new mark, the window swatch after the project's name, which moves the "need you" chip right. Intended: DL-314, F-552. Nothing else differs |
| Launch, quit (SIGTERM) and relaunch, same app | = | = | = | Same tabs, project, documents |
| Upgrade restore: save state in 0.2.22, open in main (`raw/restore-22-new`) | | | project, 4 document tabs, active tab, session all restored; opens as window 1 | Pass. 0.2.23 to main behaves the same. 0.2.22 to 0.2.22 is the control |
| Launch (fresh) captures | | | | Differ 22% from 0.2.23 (the Home chat sidebar is open in 0.2.23 and collapsed in main). Intended: DL-315. See gaps |
| `duo2 doc` edit, save, revert, comment, task and file verbs | | = | = | No regression |

## 2. Two and three windows, on main

From `tools/mw.sh` (`raw/mw/`). Windows in the order created.

| Check | Result | Verdict |
|---|---|---|
| Colours handed out in order | Window 1 none, then Blue, Ochre; a 4th after auto-off gets none; auto back on and a new window after everything closed gets Blue (DL-312, DL-313 order) | Pass |
| DL-308 bring-forward | `window new checkout` and `window new refunds` bring that window forward, no duplicate; `window focus` by number and by project name; `focus 9` errors rc 1 | Pass |
| `open <project> --window N` where the project lives elsewhere | Brings the other window forward; says "Opened refunds." | F-582 (message misleading, low) |
| Home in another window | `go home` in w2, `window home --window 3` moves Home to w3 and `window list` marks it | Pass |
| Classic | `window colour` says "Window colours are off while Classic is on"; colours return after | Pass |
| Closing a window | Sessions keep running (running set identical before and after `window close 2`); `window close` by name; reopening the project works | Pass |
| Closing all | The last window stays listed, `ping` and `sessions` still answer, Duo keeps running; `window new` afterwards opens "window 1, Blue" and the hidden window 4 is still listed | Q-460 |
| `--window` and no flag | `status --window 1/2/3/<project>` each report that window; no flag gives the primary (never the key window) | Pass |
| `duo2` from a session in window 2 (`DUO_SESSION_ID` set) | `status` and `go all` acted on **window 1**, for a running session shown in window 2 and for a planted refunds session | F-581, unverified (set from outside a session) |
| ⌘W, ⌘Q, bring-forward from a menu or click, notification clicks landing in the right window (C-150) | **Not run** (they need a visible window and key events) | C-160 |
| Memory and CPU, three windows idle 5 min (`raw/perf/idle-*.txt`) | 3 windows: **4.07%** CPU, RSS 277 MB at 10 s settling to 142 MB; 1 window main: 4.27%, 238 to 121 MB; 1 window 0.2.22: 4.49%, 278 to 119 MB | Pass: no growth with windows, about +20 MB for two extra windows |

## 3. Performance

`scripts/check-scale.sh` through `scripts/timing-lock.sh`, all in one exclusive hold on `mw1-perf` (no stale-lock or "taken" warning in the lock output). Mean CPU after the first 15 s (budget 10%), 60 s each, order as run:

| Build | Mean CPU | Stalls ≥ 250 ms | Mac load average before | Busiest other process |
|---|---|---|---|---|
| main | **5.1%** | 0 | 3.9 | Geoff's Duo, 100% |
| 0.2.22 | **6.6%** | 0 | 5.5 | Geoff's Duo, 174% |
| 0.2.23 | **7.8%** | 0 | 5.1 | Geoff's Duo, 108% |
| main again | **6.3%** | 0 | 5.4 | Geoff's Duo, 96% |

All four pass. **The "12.9% on main" earlier today is not a real regression:** the same build now reads 5.1% and 6.3%, and it is no worse than either release. The Mac was not quiet in any of these runs (load 4 to 6, and a real Duo at 100% CPU), and the run that read 12.9% was most likely taken under that load (F-549's suspicion). The between-run spread (5.1 vs 6.3 on the same build) is about the size of the gaps between builds, so this check cannot rank builds closer than about 2 points. Caveat: this is a background run, which the script itself says understates drawing cost.

## What this run did not cover (C-160)

- Live-workspace captures: the scripted `open:`, `doc:`, `split:` actions did not take effect at launch, so every `ws-*` capture shows All projects. Project, document, deck, HTML and split-view visuals were therefore checked **only** through the six fixture states and the `duo2` sweep, not pixel by pixel in a live workspace. `render-settings` produced no image, so Settings was not compared.
- Not run: conflict and outside-edit flows, session fork, chat versus terminal session views, ⇧⌘A search window, the peek and needs-you with real questions, notification clicks (C-150), voice entry points, ⌘W and ⌘Q, bring-forward from the Window menu or a click, window drag and resize, a visible run (needs Geoff's OK).
- The release-build `DuoChecks windows` and `scripts/check-windows.sh` were not re-run; they are the slice's own.

## Visible run, C-160's gaps (2026-11-04, 06:33–06:47 EST)

Geoff OK'd a 15-minute visible run (through the director). Main's release build and 0.2.22 ran with windows shown (`DUO_TEST_FOREGROUND=1`), each on its own support folder and scratch Claude config. The projects were `zqv-alpha`, `zqv-beta` and `zqv-gamma`, names that exist nowhere else (F-583). A stand-in `claude` was preset in `state.json`, so no real claude started and no turns ran. Every `duo2` call was guarded; all instances quit by SIGTERM. Tools: `tools/vis.sh`, `tools/mkvis.py`.

| Flow | 0.2.22 | main | Verdict |
|---|---|---|---|
| ⇧⌘A search for `zqv` | Opens with results: Home, 3 projects, 6 sessions, files | Same results | Pass. The capture differs only by DL-315's collapsed sidebar and how far indexing had got |
| Window-menu bring-forward (`window focus <n\|project>`, what the menu item and ⌘\` do) | — | Each focus makes that window key; `window list` shows it | Pass |
| DL-308 from `window new <project already open>` | — | "zqv-beta is in window 2; brought it forward", no second window | Pass |
| Fork in window 2 (`session fork … --window 2`) | — | New session in `zqv-beta` with the same history, running; windows unchanged | Pass |
| Outside edit to a document open in window 3 | — | `doc read --window 3` returns the disk text with the appended line | Pass |
| Close window 2 with the fork running | — | The fork is still running afterwards; `ping` and `sessions` answer | Pass |
| ⌘W (`cmd-w` with the editor holding the keyboard) | No `bar-focus` action, so not comparable | Closes the active document tab (other.md goes, notes.md shows) | Pass on main |
| ⌘Q (SIGTERM) and relaunch with 3 windows | — | Quits cleanly; relaunch opens one window on zqv-alpha | Expected: slice 2 not built (C-153) |
| Notification click across windows (C-150) | — | No live hook: an isolated instance posts no real notifications. Covered by `DUO_CHECKS=windows`, which calls `openFromNotification` with the project in another window (WindowChecks.swift:145) | See the checks result below |
| Conflict (unsaved edit, then a disk write) and save-on-quit | **Not exercised** | **Not exercised** | The harness's `user-type:`/`disk-write:` act on the editor, which in workspace mode still held `_PROJECT.md`, not the document tab, on both apps. A harness limit, not a Duo difference; still a gap |
| Chat vs terminal on a running session | **Not exercised** | **Not exercised** | My script picked the session id from the wrong output file, so `session chat on/off` got no id. Still a gap |

`DUO_CHECKS=windows` on this branch: **51 passed, 0 failed**. That includes "a notification or Dock click goes to its project's window, else the key window" and "a notification clicked from the primary's Notifier opens window 2", so C-150's click routing passes. But the one check for routing by the caller's session (`WindowChecks.swift:113`, F-581) is conditional and **did not run**, so nothing covers F-581 yet.

Result: **no regression found in the flows that ran.** Conflict, save-on-quit and the chat toggle remain untested (C-160 narrowed to those).

## Records

Filed in `docs/plan/` with this branch: F-581, F-582, F-583, C-160, Q-460 (the reserved numbers). Repros are in the findings.
