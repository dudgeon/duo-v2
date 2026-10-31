# Legacy Duo (Electron): Split View commit timeline

Source: `/Users/geoff/repos/duo` (1,133 commits on `main`, HEAD `5126c47`, 2026-09-20). Read-only archaeology; the app was never run.

Internal name **"aux"** (auxiliary slot); the label users see is **"Split View"**; the CLI verb is `duo split-view`. Tracker: **ENH-041** ("Split the canvas (right pane) into side-by-side panels").

## Method and noise

- Message grep on `main`: `split` (154 hits), plus `aux|split.view|ENH-041|side.by.side|subpane|focusPane|divider|dual|compare|beside` and every bug/ENH id found along the way (ENH-083/084/085/095/098/099/126, BUG-075/091–096/100/102/195/196/209/270, FOLLOWUP-013/045). The same grep on `--all --not main` found branch-only commits.
- Diff pickaxe (`-G`) over `renderer electron shared core cli` for `auxState|SplitViewDivider|AuxHeader|AuxBrowserSlot|inAux|auxTabId|onMoveTabToSplit|MoveBrowserTabToSplit|focusedSubpane|splitPct|clampAuxSplit|WORKING_AUX|split-view|splitOpen|Split View|focusPane..aux`: 47 commits.
- `git log --follow` on `renderer/components/AuxBrowserSlot.tsx` (3 commits) and `shared/split-view.ts` (1 commit). There are no renames: the split UI was never its own file. `AuxHeader`, `SplitViewDivider` and `buildAuxFileTab` live inline in `WorkingPane.tsx`.
- **False positives dropped: about 100 of the 154 `split` message hits.** They break down as:
  - doc and file splits: SKILL.md, README, tasks.md, session-log, the host-api refactor, skill splits;
  - the stage-19c / ENH-006 / ENH-044 **"split-button"** (a new-Claude/new-tab button that drops down, not Split View);
  - ENH-156 "HTML verb-split" and ENH-176 "split send-pill";
  - the ENH-191 multi-window teardown "split" refactors;
  - ENH-245 "dual-convention" filenames;
  - releases and docs that only mention the word.

  About 10 more are kept below only as **precursors**: the outer terminal|canvas split, its divider, and collapse.
- Note on `--all`: there are 175 `split` hits across all branches. The two that matter and never reached `main` are listed in the stranded-work section.
- Several features have **no commit of their own**. They were built in a working tree and landed inside a release commit: Phase 3c browser-in-aux, BUG-095/096 and ENH-095 in `a366c4e` v0.6.7; ENH-098 in `8b85677` v0.6.9; ENH-126 and ENH-099 in `5304732` v0.6.11. The ledger (`tasks-archive.md`) is the source for those details.

"Owner" below means Geoff. Quotes are verbatim from commit messages or the ledger.

---

## Phase 0: Precursors (the outer terminal | canvas split), Apr 22 to May 2

| sha | date | what changed / why |
|---|---|---|
| d1e4d84 | 2026-04-22 | Scaffold: two-column terminal-left / browser-right split with a drag handle. |
| f016060 | 2026-04-23 | Stage 10 phase 2: three-column shell (Files / Terminal / Working pane). The terminal and working pane are "split … via the existing drag handle". Adds `focusedColumn` and a focus-aware ⌘W. |
| 89d22d8 | 2026-04-23 | Stage 10 phase 3: tab strip hoisted into a polymorphic `WorkingPane` (the component that later hosts the split). |
| bbda3fc | 2026-04-24 | `min-w-0` cascade so flex children in the working pane don't overflow. The same trick is reused in the aux columns. |
| dfc152c | 2026-04-28 | **BUG-031**: the split divider can't be dragged right over a canvas iframe. The fix is a transparent overlay during the drag. It doesn't cover the browser WebContentsView, because "z-index can't push DOM above an Electron native view". That native-view-above-DOM problem comes back as BUG-102, BUG-195, BUG-209 and BUG-270. |
| b11a820 / 2a44766 | 2026-04-29 | ENH-014: preset pane sizes (View menu, ⌘⌥1/2/3/0/9, `duo split <pct\|preset>`), clamped to 20–80. Merged as PR #32. |
| 238de40, 8345a85, 6781d7b | 2026-05-02 | ENH-040 / ENH-066: collapse-pane buttons and a collapsed rail. An adjacent pane feature, cross-referenced from ENH-041. |

## Phase 1: Filing, research and spec lock (Sprint 3), May 2

| sha | date | what changed / why |
|---|---|---|
| f6ea608 | 2026-05-02 | **ENH-041 filed** during the Stage 27 walk (owner request): "split the canvas (right pane) into side-by-side panels". Use cases in the ledger: compare-and-edit (markdown left, HTML preview right), reference-while-authoring, lesson canvas beside work. The same commit fixes the vocabulary: "canvas" means the right-pane slot. |
| 9f0b793 | 2026-05-02 | Research page `docs/prd/canvas-split-view-research.html` (600+ lines). "Pulled into Sprint 3 by owner: research how Slack handles its sidebar/aux view, spec a single-aux pattern for Duo's canvas, no infinite split inception." Four options: **A** Slack-style single aux slot (recommended); **B** aux with its own tab strip (v2); **C** VS Code n-way recursive ("REJECTED — owner explicit"); **D** linked twin views. Eight open questions. |
| bb7e012 | 2026-05-02 | **Option A locked** by AskUserQuestion. Decisions: Move semantics on tab right-click, Open semantics on file/link right-click, and "never two tabs for the same path across panes"; replacing aux content is silent when clean and asks with a dialog when dirty; "B-ready internals" (`aux: { tabs[], activeIndex, splitPct }`); any local-path `<a href>` can open in split. Label "Split View"; the code says "aux". |
| 5d87b2c | 2026-05-02 | Full lock, 7 of 8 questions. Closing the last main tab promotes aux to main; splitPct and aux tabs persist in session-state; **no pinning in v1** (split is a "transient companion"); chords **⌘\\** open and **⌘⇧\\** close. Deferred: FTUX default split content. |

## Phase 2: Build v1 (Sprint 3, aiming at v0.6.4), May 2–3

| sha | date | what changed / why |
|---|---|---|
| 40c9951 | 2026-05-02 | **Phase 3a-i plumbing**: `'split-view'` command; `WorkingAuxState` / `WorkingAuxSnapshot` / `WorkingAuxOp`; 5 IPC channels `WORKING_AUX_OPEN/CLOSE/PROMOTE/RESIZE/STATE_PUSH`; NavBridge `splitViewOpen/Close/Promote/Resize/getSplitViewState`; CLI `duo split-view {state,open,close,promote,resize}`; `auxState` in App.tsx. Resize accepts 0.20–0.80 or 20–80, clamped in main. Opening in aux drops the path from main `fileTabs`. |
| a0c144c | 2026-05-02 | **Phase 3a-ii, the first visible UI**: WorkingPane switches to a horizontal flex (main `1-splitPct`, aux `splitPct`) with `AuxHeader` (36px; basename, "⇤ to main", ✕) and `SplitViewDivider` (drag overlay per BUG-031, clamp [0.20, 0.80], double-click resets to 0.5). The aux tab's id is `aux:<path>`. |
| 5506f06 | 2026-05-03 | Styling options page `docs/prd/canvas-split-view-styling.html`: A (shipped, symmetric slim), **B** (recommended: italic serif filename, accent left rule), C, D, E. "Owner asked to step back on Split View styling before Phase 3b." **Outcome: the owner kept A** (ed4d097 says "styling option A is locked"). |
| f7ff1fe | 2026-05-03 | Per-page `<meta name="duo-path-target" content="split">` and per-link `data-duo-target`; a CDP `duoOpenPathSplit` binding; the smoke-walk generator opts in. Agent trigger words: "in split / alongside / side by side / as a companion / in the side panel …"; the agent default is always main. Owner locks: the ⌘\` cycle is 2-way, ⌃Tab cycles only the focused pane, and main and aux have the same capabilities. |
| 4b0236f | 2026-05-03 | Breadcrumbs: ENH-041 progress block (see the "Last state" section). |
| 4ec0742 | 2026-05-03 | Idle-thoughts sweep. BUG-071: return focus to the main window after a path-link click on the main and split routes. |
| ed4d097 | 2026-05-03 | **Phase 3b invocation surfaces**: ⌘\\ `splitViewToggle` and ⌘⇧\\ `splitViewClose` (also forwarded through the WCV `before-input-event`); "Move to Split View" on file tabs; "Open in Split View" in FileTree and PinnedNav. All of them call one primitive, `splitViewMoveTabByPath`. |
| e5c8eb7 | 2026-05-03 | **Phase 3c-i persistence**: optional `SessionState.aux` (no version bump). Restore drops missing paths. `validateAux` coerces bad shapes to null and clamps splitPct. |
| ac59e8f, 17866f6 | 2026-05-03 | Release-notes draft and docs refresh (README, roadmap, what-duo-does). |
| e54eb3b | 2026-05-03 | **Phase 3c-iii dirty-replace dialog**: a `dirtyPaths` set keyed by path across main and aux. Replacing a dirty aux asks Cancel / Discard (no Save). `splitViewMoveTabByPath` becomes async. All five entry points go through the gate. Why: it "closes the data-loss surface … silently replacing a dirty aux file … lost the user's unsaved edits." |
| 511d8b8 | 2026-05-03 | **Owner refinements (reversals)**: (1) **⌘⇧\\ changed from close to promote** (close the split but keep the file as a main tab); "pure-discard close is reserved for the ✕ button". (2) **Replace becomes swap**: the old aux content is promoted back to main, never discarded. The PRD keeps "originally specified as X; refined Y" breadcrumbs. Also files ENH-080 (⌘⇧A palette; owner: "think hard about the menu occlusion issues"). |
| 9546d55 | 2026-05-03 | **v0.6.4 walk: 10 PASS, 4 FAIL, 4 SKIP; cut blocked.** **BUG-075** (HIGH): ⌘\\ / ⌘⇧\\ ignored. The dirty dialog couldn't be tested because autosave (about 800ms) beats the tester (FOLLOWUP-006). Persistence deferred to a DMG restart. Filed ENH-083/084/085. **v0.6.4 was never tagged**, so Split View first shipped in **v0.6.5** (`git describe`: v0.6.5~38). |

## Phase 3: Close-out and bug fixes (Sprint 4, v0.6.5), May 3

| sha | date | what changed / why |
|---|---|---|
| 929061f | 2026-05-03 | Sprint 4 plan. Phase 3 is the "Split View close-out". |
| 8ac1507 | 2026-05-03 | **BUG-075 v1**: the matcher checked `e.key === '\\'` with shift, which can't happen ("Shift+\\ produces `e.key === '\|'`"). Switched to `e.code === 'Backslash'` and added 5 regression tests. **ENH-085**: AuxHeader right-click (Reveal / Rename / Copy path / Move back to main / Move to Trash). **ENH-084 v1**: aux focus glow via `focusedSubpane` and `onMouseDownCapture`. ENH-083: collapse buttons moved into the tab clusters. |
| f089048 | 2026-05-03 | Walk fallout. **BUG-075 v2**: the WCV key forwarder had the same `key==='\\'` bug, switched to `input.code`. **ENH-084 v2**: removed the main gate after a regression where "main strip stops glowing", so both glow. BUG-076 v2: cycle race, ref updated optimistically. |
| 48d4cbd | 2026-05-03 | **ENH-084 v3** (document-level `focusin`, because "onMouseDownCapture doesn't fire when a click lands inside an iframe"). Owner: "inactive canvas pane still glow; whole point is for glow to show focus; when I click back from split view to main pane, split view should lose focus; and vice versa." |
| d063b47 | 2026-05-03 | **ENH-084 v3 backed out (reversal)**. Owner: "glow never moves to split view -- log the defect, incl failed attempts, then move on; this has wasted too much time this sprint." **Self-inflicted crash**: the half-reverted module left `ref={mainColRef}` with no declaration, giving `ReferenceError` (render crash under HMR); fixed in the same commit. **BUG-075 final: chord changed to ⌘/ and ⌘⇧/ (reversal of the spec'd ⌘\\)**. Root cause: "1P's system-level Cmd+\\ grab eating the keystroke"; the owner picked ⌘/. Six tests, including a negative test that ⌘\\ no longer matches. |
| 09ea310 | 2026-05-03 | **Release v0.6.5**: first shipped Split View. |

## Phase 4: Browser tabs in aux (Sprint 6–7, v0.6.7), May 4–5

| sha | date | what changed / why |
|---|---|---|
| 99826fa | 2026-05-04 | **BUG-091**: "Move to Split View" excluded browser tabs; lifted for local-file browser tabs. This over-broad lift caused **BUG-092**: a scripted worksheet page promoted into the script-blocked canvas iframe, so its buttons died. |
| (working tree) → a366c4e | 2026-05-05 | **Release v0.6.7 carries Sprint 7 Phase 3c, browser-in-aux** (the fix for BUG-092): `auxBrowserTab` state; `BrowserManager.auxTabId`, `moveTabToAux`, `releaseAuxTab`, `setAuxBounds`; IPC `BROWSER_AUX_BOUNDS`, `BROWSER_MOVE_TAB_TO_AUX`, `BROWSER_RELEASE_AUX_TAB`, `WORKING_AUX_OPEN_BROWSER`; new `AuxBrowserSlot.tsx` (bounds pushed by a ResizeObserver over a second native WCV); `duo split-view open-browser <id>`. Why: "The user's natural gesture ('split view, walk on left, canvas on right') was being silently broken." The session log says the owner insisted it ship: "you said you'd do these, you didn't, and now you're asking me to cut?". The same release carries: **BUG-095** (clicking into the aux browser stole main focus and switched main's tab; fixed with a `{tabId, slot}` focus payload and an act-only-on-`slot==='main'` guard); **BUG-096** (closing the last main browser tab made the aux tab main-active and overwrote its bounds, blanking aux; fixed with a `findNonAux` picker that spawns `about:blank`); **ENH-095** (aux header reduced to a single ✕ that **promotes back to main**, which reverses 511d8b8's "✕ = pure discard"; the ⇤ button was removed); **BUG-093 instrumentation** (inline `ErrorBoundary` around WorkingPane and `[BUG-093]` traces in `splitViewMoveTabByPath`). |

## Phase 5: Polish and adjacent bugs (Sprints 8–17), May 6–18

| sha | date | what changed / why |
|---|---|---|
| cc608ad | 2026-05-06 | **BUG-093** ("tried to move that canvas to split view (right click tab) and it caused a render error that forced reload of the whole app"): code-side analysis, no repro. Suspects a 4-setState cascade across `await` (batching broken), a stale `fileTabs` closure, and PageTab unmount races. Three fix candidates deferred. FOLLOWUP-013 filed. |
| 66b2b31 | 2026-05-06 | ENH-080 palette walk-1: the synthetic forwarded KeyboardEvent lost `code`. That also silently broke **⌘⇧/ split-view promote from browser focus** (latent, now fixed). `setOverlayMuted` extended to mute the **aux WCV** too. Split-view tabs get a "Split" badge in palette results. |
| 5a7e3e8 | 2026-05-06 | Files **BUG-100** (no Send → Duo pill on selections in the aux browser) in tasks.md. |
| 7b45370 | 2026-05-06 | v0.6.8 release. Files **BUG-102** ("split view goes blank when search is active … non urgent"), a side effect of 66b2b31's aux mute. |
| 41d00d6 | 2026-05-07 | BUG-105: AuxBrowserSlot had no right-click menu; added Copy path/URL and Move back to main. |
| 880e97e | 2026-05-07 | BUG-091 marked likely fixed. **BUG-100 deferred**: needs a CdpBridge multi-attach refactor (about 3–4h). |
| (working tree) → 8b85677 | 2026-05-07 | v0.6.9 carries **ENH-098**, focus chords ⌘⇧L / ⌘⇧; / **⌘⇧' (focus split view)** and `duo focus-pane`. Walk-1 had to re-pick ⌘⌥ to ⌘⇧ (window-manager clash). Owner: "carat landed!" |
| (working tree) → 5304732 | 2026-05-09 | v0.6.11 carries **ENH-126**: opening aux redistributes the panes (inner 50/50 every time, so a saved aux ratio is no longer reused, a behaviour change; outer 33/67 unless the terminal is collapsed). Owner: "if all three (minus terminal) are open, then it should be 33/33/33; if terminal is collapsed, then the main pane and the split view should be 50/50." Also carries **ENH-099** ⌘⌥4 "3-way even". |
| 2053a11 | 2026-05-10 | BUG-121: BUG-096's spawn-`about:blank` guard caused an infinite respawn loop. It now leaves `activeIndex = -1`; the aux-bounds protection is kept. (This partly reverses BUG-096's fix.) |
| d0fdc44 | 2026-05-11 | **ENH-084 v4: instrumentation only** (`[ENH-084-v4]` focusin/mousedown/blur logs, `mainColRef`/`auxColRef`). "Sunset: remove instrumentation in the same commit as the v4 fix." **There never was a v4 fix**, so the instrumentation is still in the final code. |
| 1513268 | 2026-05-18 | BUG-091 verified shipped (carry-forward sweep). |

## Phase 6: Persistence, multi-window, smaller fixes, May 21 to June 21

| sha | date | what changed / why |
|---|---|---|
| 9cd6bf8 | 2026-05-21 | ENH-167 workspace-as-file: the `.duo-workspace` round-trip includes the "split aux". |
| 4e66419 | 2026-05-25 | ENH-182 audit. "Phase 3c-browser" here is project-rail auto-switch naming, **not** Split View (name collision); it only touches the aux-aware browser code. |
| 9276af6 | 2026-06-06 | **BUG-195**: `duo split-view close` orphaned the aux browser WCV, leaving a "ghost" composited over the UI and desynced state (`inAux:true` vs `aux:null`). Cause: release was gated on `auxBrowserTabRef`, which a renderer reload clears while main keeps `auxTabId`. Fix: call `releaseAuxTab()` unconditionally. The documented follow-on (re-sync when the renderer mounts) wasn't built until BUG-270. In v0.9.1. |
| 7f1871a | 2026-06-06 | Smoke-walk skill now opens the walk sheet in the split-view aux ("the owner's workflow"). Records the `duo eval` vs `duo dom` and stale-aux gotchas. |
| 13c874d | 2026-06-06 | Files **BUG-196** on main (ported from stranded branch `claude/enh-191-p0`): reloading an aux-pinned browser tab with `duo eval "location.reload()"` may crash the dev app. Needs a repro. |
| 8ed3618, 36c171f, b529771 | 2026-06-07/08 | ENH-191 multi-window refactor: `splitView*` sends resolved through the window registry; `split-view open-browser` addressed to window N. |
| 6cd1394 | 2026-06-10 | about-duo hero shot restaged as "PRD + prototype split view" (`docs/images/about-duo/split-view.png`). |
| f117211 | 2026-06-14 | Worksheet: `execCommand` fallback for Copy results / Send in the split-view aux, because "the aux WebContentsView isn't the focused frame, so navigator.clipboard.writeText rejects". |
| f712bbb | 2026-06-15 | Files **BUG-209**: the aux WCV occludes the New Vault / Clone / History modals (the F6 park covered only the main pane). Owner: "occluded by split view if the window is small enough; MORE concerning the modal 'Close' button is non-functional/no-op; the 'x' works." |
| 3b05c96 (branch) → **66b9d87** | 2026-06-20 → 06-21 | **BUG-209 fix**: AuxBrowserSlot listens for `duo-wcv-park` / `duo-wcv-restore` and parks the aux WCV at 1×1 while a modal is open. Landed on main inside ENH-221 PR #104 (`66b9d87`), released in v0.11.2. |

## Phase 7: The last fix, BUG-270 (Sept 18, v0.13.7)

| sha | date | what changed / why |
|---|---|---|
| 16f9bf2 | 2026-09-18 | Ledger entry for BUG-270. Root-caused with read-only `duo` probes showing a three-way desync (`inAux:true`, `aux:null`, `browserTabsCount:0`). |
| e9ac6cd | 2026-09-18 | **BUG-270 fix.** Owner: "the width of the splitview appears pinned and it is occluding the main editing panel". There were two defects. (1) After a **renderer reload**, every WCV kept painting at its pre-reload rectangle, because the renderer's ResizeObserver cleanup is the only thing that ever hides a view. New `shared/wcv-bounds.ts` contract; `BrowserManager.reconcileForHostRendererReload()` wired to `did-start-loading` (parks every view at 1×1, resets the cached bounds, drops the aux pin); the renderer pulls `browser.getTabs()` on mount. "Also closes the BUG-195 ghost at its source." (2) `duo split-view resize` only drove the **file** aux slot and now drives both. The clamp was centralised in new **`shared/split-view.ts`** (`clampAuxSplitFraction`, which handles a drag past the edge (more than 1 means max), and `clampAuxSplitPct` for CLI input). Before this, three copies of the clamp had drifted. 15 tests. |
| 52e8f51 | 2026-09-18 | BUG-270: also clear the BUG-047 overlay mute on reload. A latched mute had left the browser pane blank forever. |
| 14adfbe | 2026-09-18 | BUG-270: the session-state and workspace-file loaders use the shared clamp, "so 'one clamp' is actually true". |
| db8b66a, 288e492, da6d82e | 2026-09-18 | Ledger and sprint pointer. Live-verified on the dev build ("reload un-pins, CLI resize moves the divider, child loads safe"). Adds `docs/dev/smoke-checklist.md` §4a. |
| 93975f4 | 2026-09-18 | Merge PR #139 (`claude/duo-split-view-width-pinned`). |
| 8d214f3 | 2026-09-20 | **Release v0.13.7**: the last release; it carries BUG-270. |

---

## Reversals (decisions undone)

1. **Chord ⌘\\ / ⌘⇧\\ to ⌘/ / ⌘⇧/** (5d87b2c spec, then d063b47). The spec'd chord collided with 1Password's system-level grab. It took two e.key-vs-e.code fixes (8ac1507, f089048) before the real cause was found.
2. **⌘⇧\\ "close" became "promote"** (511d8b8).
3. **Replace (with a dirty dialog) became swap**, with the displaced aux promoted to main (511d8b8).
4. **✕ "pure discard" became ✕ "promote back to main"**, and the ⇤ button was removed (511d8b8, then ENH-095 in a366c4e).
5. **ENH-084 aux focus glow**: v1 (8ac1507), then v2 removed the gate (f089048), then v3 used focusin (48d4cbd), then v3 was **backed out** (d063b47), then v4 added instrumentation only (d0fdc44). It never shipped.
6. **Styling**: option B was recommended (5506f06); the owner kept A.
7. **Saved aux splitPct**: persisted and restored (e5c8eb7), but ENH-126 (v0.6.11) forces 50/50 every time aux opens.
8. **BUG-091 lift** (99826fa) caused BUG-092. Superseded by browser-in-aux rather than reverted.
9. **BUG-096's spawn-about:blank** removed by BUG-121 (2053a11).

## Every bug and its fix

| bug | symptom | fix |
|---|---|---|
| BUG-031 (precursor) | divider drag stalls over a canvas iframe | dfc152c (overlay); WCV not covered |
| BUG-075 | split chords ignored | 8ac1507 (matcher e.code), f089048 (WCV forwarder e.code), d063b47 (re-pick ⌘/ because of 1Password) |
| (unnumbered) | `ReferenceError: mainColRef` render crash from the half-reverted ENH-084 v3 | d063b47 |
| BUG-091 | no "Move to Split View" on browser tabs | 99826fa (lift), verified 1513268 |
| BUG-092 | scripted pages dead when moved into aux (sandboxed iframe) | Phase 3c browser-in-aux, a366c4e |
| BUG-093 | right-click → Move to Split View crashed the renderer | instrumentation a366c4e; analysis cc608ad; **flushSync fix cd1dcb1 only on branch `origin/claude/amazing-goodall-39846b`, never merged**; still 🟡 open in tasks.md with FOLLOWUP-013 |
| BUG-095 | clicking the aux browser stole main focus and switched main's tab | a366c4e |
| BUG-096 | closing the last main browser tab blanked aux | a366c4e; reworked by 2053a11 (BUG-121) |
| BUG-100 | no Send → Duo pill on aux selections | deferred 880e97e; **fix 1cb18a5 (thread the attaching webContents through `injectSelectionObserver`) only on branch `amazing-goodall`, never merged**; still open |
| BUG-102 | aux goes blank while the ⌘⇧A palette is open (aux mute too aggressive) | **open**; a bounds-intersection fix was designed but never built |
| BUG-105 | no right-click menu on AuxBrowserSlot | 41d00d6 |
| (latent) | ⌘⇧/ promote dead from browser focus (synthetic event had no `code`) | 66b2b31 |
| BUG-195 | `split-view close` left a ghost aux WCV | 9276af6; source fixed by e9ac6cd |
| BUG-196 | reloading the aux browser may crash the app | **open**, unconfirmed (13c874d) |
| BUG-209 | aux WCV occludes modals; footer Close unclickable | 3b05c96, landed via 66b9d87 |
| (aux clipboard) | Copy results / Send fail in aux (not the focused frame) | f117211 |
| BUG-270 | aux width pinned and occluding the editor after a renderer reload; CLI resize ignored for browser aux | e9ac6cd, 52e8f51, 14adfbe (PR #139) |

## Unfinished, stranded, or never built

- **ENH-041's ledger status was never closed.** `tasks.md` still reads "🚧 v1 … actively building in Sprint 3 … Phase 3b (queued) … Phase 3c (queued)", which was stale from 2026-05-03 on.
- **ENH-084** aux focus glow was never fixed. The `[ENH-084-v4]` console instrumentation is still live in `WorkingPane.tsx` (lines ~294–356). `focusedSubpane` is frozen at `'main'`, so the AuxHeader glow never lights.
- **TODO in `renderer/App.tsx` ~3882 (ENH-098 `focusAux`)**: there is no IPC to focus the aux **browser** WCV, so ⌘⇧' with a browser in aux is a no-op ("Click into the aux pane to focus").
- **Stranded on `origin/claude/amazing-goodall-39846b`**: cd1dcb1 (BUG-093 flushSync) and 1cb18a5 (BUG-100 pill). Also the PRD `docs/prd/bug-093-split-view-move-crash.md` exists only on that branch and on `enh-221-file-history`.
- Still open: BUG-093/FOLLOWUP-013, BUG-100, BUG-102, BUG-196. FOLLOWUP-045 (outer `duo split` can't collapse to 0/100) is adjacent.
- **Never built** (deferred in the spec): Option B multi-tab aux with its own strip (the internals are "B-ready" with `paths[]`/`activeIndex`, v1 ≤ 1), dragging tabs between panes, pinning in aux, an aux on the left/top/bottom, recursive splits (rejected), FTUX default split content, a Save button in the dirty dialog, and the FOLLOWUP-006 autosave-delay knob.

## Last state (HEAD 5126c47)

- Single aux slot on the right, holding **either** one file (`auxState {paths[], activeIndex, splitPct}`) **or** one pinned browser tab (`auxBrowserTab {browserTabId, splitPct}`); the two are mutually exclusive.
- The aux column's ratio is clamped to 0.20–0.80. Opening aux snaps it to 50/50 and the outer layout to 33/67. Double-clicking the divider or pressing ⌘⌥4 evens it.
- Entry points: right-click "Move to Split View" (file and browser tabs), "Open in Split View" (FileTree, PinnedNav), `data-duo-target="split"` / `<meta duo-path-target>` links, **⌘/** (move the active tab to split), **⌘⇧/** (promote back), **⌘⇧'** (focus split), the ✕ in the aux header (promote), aux right-click (Reveal, Rename, Copy path, Move back to main, Trash), and the ⌘⇧A palette with a "Split" badge.
- CLI: `duo split-view {state|open <path>|open-browser <id>|close|promote|resize <pct>}` and `duo focus-pane aux`.
- Persisted in `session-state.json` and in `.duo-workspace` files.

## File paths of the split code (legacy repo)

- `renderer/components/WorkingPane.tsx`: layout; inline `AuxHeader`, `SplitViewDivider`, `buildAuxFileTab`; ENH-084 leftovers.
- `renderer/components/AuxBrowserSlot.tsx`: browser-in-aux chrome and bounds push; BUG-209 park.
- `renderer/App.tsx`: `auxState`, `auxBrowserTab`, `splitViewMoveTabByPath` (with `[BUG-093]` traces), `splitViewPromote`, `splitViewMoveBrowserTab`, `focusPane`, IPC subscribers, the BUG-270 `getTabs()` pull.
- `shared/split-view.ts` (+ `.test.ts`): clamp constants and helpers. `shared/wcv-bounds.ts`: reload-reconcile contract.
- `shared/types.ts` (WorkingAux* types, SessionStateAux, IPC `WORKING_AUX_*`, `BROWSER_AUX_BOUNDS`, …), `shared/host-api.ts`, `electron/preload.ts`.
- `electron/browser-manager.ts` (`auxTabId`, `moveTabToAux`, `releaseAuxTab`, `setAuxBounds`, `setOverlayMuted` aux mute, `reconcileForHostRendererReload`, key forwarder `code==='Slash'`), `electron/main.ts` (NavBridge `splitView*`), `electron/cdp-bridge.ts` (`duoOpenPathSplit`).
- `core/socket-server.ts` (`case 'split-view'`), `cli/duo.ts`, `core/session-state-service.ts` (`validateAux`), `core/workspace-file-service.ts`.
- `renderer/keyboard/globalShortcuts.ts` (+ test), `renderer/hooks/useKeyboardShortcuts.ts`, `renderer/components/WorkingTabStrip.tsx`, `FileTree.tsx`, `PinnedNav.tsx`, `TabSearchPalette.tsx`.
- Docs: `docs/prd/canvas-split-view-research.html` (locked spec), `docs/prd/canvas-split-view-styling.html`, `docs/dev/smoke-checklist.md` §4a, `tasks.md` (ENH-041, BUG-093/100/102/196, FOLLOWUP-013/045), `tasks-archive.md` (BUG-075/091–096/195/209/270, ENH-084/085/095/098/099/126), `docs/images/about-duo/split-view.png`.
