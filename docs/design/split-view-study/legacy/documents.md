# Legacy Duo (Electron) — Split View, what the documents say

Source: `/Users/geoff/repos/duo` (read-only; `main` @ 5126c47, v0.13.8-dev). Paths below are relative to that repo.
"Owner" in those docs = Geoff. Internal name for the second pane is **aux**; user-facing name is **Split View** (CLI `duo split-view`).

## 0. Shape of the feature in one paragraph

Split View is a **single "aux" companion slot on the right side of the working pane (canvas)**, Slack-thread-sidebar style: terminal column | main working pane (with tab strip) | aux (one tab, no tab strip). No nesting, no left/top/bottom aux, no multi-tab aux in v1. One file can never be open in both panes. The aux can hold any tab kind: file tabs (markdown, page/canvas, image, pdf) and, since v0.6.7, a **real browser tab** (separate WebContentsView), so scripted pages like smoke-walk worksheets work beside the thing being tested. The tracking item is ENH-041. The spec is `docs/prd/canvas-split-view-research.html`, and the styling options are in `docs/prd/canvas-split-view-styling.html`.

---

## 1. Decisions (number, date, text, reason)

**`docs/DECISIONS.md` has no Split View ADR.** The research PRD says "Owner-locked direction goes into docs/DECISIONS.md after the open-questions in §5 are answered" (`docs/prd/canvas-split-view-research.html:1039`), but no such ADR was ever written (grep of DECISIONS.md: only unrelated "split" hits at :355, :462, :496, :606, :640, :869, :898, :1039). The decisions live in the research PRD, in ENH-041 and in the release notes. Two ADRs govern parts of it:
- **Pane focus indicator: chrome-strip tint** (Locked 2026-04-26, `docs/DECISIONS.md:431-500`). New chrome strips "pass `focused` through and apply the same `accent-soft` tint". The aux header follows it (ENH-084).
- **WCV-occlusion remediation: native NSMenu + system sheets, not WCV-mute** (`docs/DECISIONS.md:672`). This is the background to BUG-102 and BUG-209.

Split View decisions (none are numbered D-n; they come from AUQ passes on 2026-05-02/03):

| # | Date | Decision | Stated reason | Ref |
|---|---|---|---|---|
| SV-1 | 2026-05-02 | **Option A, Slack-style: one aux slot, right side only.** Option B (aux with its own tab strip) kept for v2, Option C (VS Code n-way recursive split) **explicitly rejected**, Option D (linked twin views, e.g. md source↔preview) "complementary". | "Matches owner's explicit ask"; simplest; reversible; **cognitive ceiling**: "one terminal column + one canvas pane + one aux pane is three columns of attention, which is at the edge of what most users can hold. A fourth would compete." Option C is rejected because the owner rejected "infinite split view inception" by name, plus drag-target ambiguity, tree-shaped persistence, and it "defeats Duo's 'tools you reach for, not tools you configure' ethos". | research.html:479-492, :776-830, §6 :981; commit bb7e012 |
| SV-2 | 2026-05-02 | User-facing label **"Split View"**; code keeps "aux". | — | research.html:483-; tasks.md:1907 |
| SV-3 | 2026-05-02 | **Single source of truth.** Right-click on a tab = *Move to Split View* (it closes in main). Right-click on a file or link = *Open in Split View*; if the file is already in main, that tab moves. "Never two tabs for the same path across panes." | consistency | research.html:483-492; tasks.md:1905 |
| SV-4 | 2026-05-02 | **B-ready internals:** `aux: { tabs: WorkingTab[], activeIndex, splitPct } \| null`; the v1 UI is single-slot. | "near-zero migration cost when/if Option B ships" | research.html §5, §7 |
| SV-5 | 2026-05-02 | **Page-link surface:** any local-path `<a href>` in a page gets "Open in Split View" (non-file hrefs filtered out). | — | research.html §5 pass 1 |
| SV-6 | 2026-05-02 | **Empty main:** closing the last main tab while the split is open promotes the aux to main. | "Preserves work without leaving an empty-main + populated-split state." | research.html:961 |
| SV-7 | 2026-05-02 | **Persistence:** `splitPct` and aux `tabs[]` persist in `~/.claude/duo/session-state.json`. | "User reopens Duo to find their split exactly as they left it." | research.html:962 |
| SV-8 | 2026-05-02 | **No pinning in aux in v1.** | "Split = 'transient companion'; pinning fights replacement semantics." | research.html:963 |
| SV-9 | 2026-05-02 → revised 05-03 | **Chords:** `⌘\` moves the active main tab to aux. `⌘⇧\` was first "close split", revised to **promote** (close the split *and* keep the file as a main tab); pure discard is left to ✕. | "the user wanted the chord to preserve the file, not discard it"; "Backslash is unbound elsewhere and reads as 'split.'" | research.html:964; commit 511d8b8 |
| SV-10 | 2026-05-03 | **Swap, not replace, when aux is occupied:** the displaced aux file is promoted back to main as a new tab. If it is dirty, a native Cancel/Discard dialog appears (no Save button in v1). | "the displaced aux file lives on in main where the user can keep working with it"; there is no Save because saves are per-editor and async, with no save-by-path dispatch | research.html:489; 511d8b8 |
| SV-11 | 2026-05-03 | **Capability deltas main↔aux: NONE in v1** (same TipTap/canvas surfaces; dirty, save and Send→Duo all the same). | — | tasks.md:1904; RELEASES.md:1446 |
| SV-12 | 2026-05-03 | **Agents default to main.** They open in split only when the user uses trigger words: "in split / in split view / in the split / alongside / side by side / as a companion / in the side panel". | — | commit f7ff1fe (CLI-COVERAGE row); roadmap.html:185; RELEASES.md:1428 |
| SV-13 | 2026-05-03 | **Keyboard focus:** `⌘`` cycle is 2-way (terminal ↔ working pane, last-focused side); `⌃Tab` cycles only within the focused pane; `⌘W` targets the focused pane's active tab. | — | tasks.md:1906; research.html Option A behaviour |
| SV-14 | 2026-05-03 | **Styling: Option A locked** (the slim, symmetric 28px paper-deep header with an all-caps "SPLIT" label that had already shipped). Claude had recommended B (accent left rule + italic serif filename, more "subordinate companion"). | The owner picked the current one at the start of the session; no reason recorded | RELEASES.md:1446; roadmap.html:185; session-recaps/2026-05-03 ("owner picking … the slim symmetric chrome that had already shipped"); styling.html:982-983 |
| SV-15 | 2026-05-03 | **FTUX auto-split deferred:** no auto-split on first launch; "revisit before the cohort cut". | "easy to retrofit, doesn't affect core architecture" | research.html:971 |
| SV-16 | 2026-05-04 (v0.6.5) | Chord **re-picked to `⌘/` (move) and `⌘⇧/` (promote)**, matched on `e.code === 'Slash'`. | 1Password grabs Cmd+\\ system-wide; with Shift held, `e.key` is `\|`. The owner picked ⌘/. | tasks-archive.md:6528-6547; CHANGELOG.md:1552 |
| SV-17 | 2026-05-05 (v0.6.7) | **Single ✕ on the aux header** = "Move back to main" (it promotes). The ⇤ button was dropped. | The two buttons did the same thing in browser-aux. "owner directive was to make X always do the latter" (promote) | tasks-archive.md:9908-9914; CHANGELOG.md:1454 |
| SV-18 | 2026-05-04/05 (v0.6.7) | **Browser tabs live in aux natively** (Phase 3c). File-aux and browser-aux are mutually exclusive. | Canvas iframes are sandboxed without `allow-scripts`, so worksheets died when promoted to a canvas. "The right architectural fix was to make the aux slot tab-kind-aware" | tasks-archive.md:6894-6908; RELEASES.md:1311 |
| SV-19 | 2026-05-09 (v0.6.11) | **Auto-redistribute when a split opens** (ENH-126): terminal visible → 33/33/33; terminal collapsed → main and split 50/50. Inner main/aux always snaps to 50/50. | Owner spec (verbatim, §5) | tasks-archive.md:7279-7300 |
| SV-20 | 2026-05-07 | **Focus chords:** ⌘⇧L terminal / ⌘⇧; main / ⌘⇧' aux; with no aux open, the aux chord is a no-op plus a console hint (not a toast). | ⌘⌥ was intercepted by window managers (Raycast) | tasks-archive.md:2759-2778 |
| SV-21 | 2026-06-07 | **BUG-093:** wrap the swap in `flushSync` as structural hardening even without a repro ("owner-approved"). | It removes the un-batched setState-across-await pattern | commit cd1dcb1 (unmerged PR #75) |
| SV-22 | 2026-06 (ENH-212 Home) | The Home tab is excluded from "Pin" and "Move to split". | Either would persist the `duo://home` sentinel into the aux-split SessionState and break restore | docs/prd/enh-212-home.md:118-127 |

## 2. Release notes / changelog lines

CHANGELOG.md:
- :1584 **v0.6.4/0.6.5, Split View (ENH-041):** "the canvas (right pane) can host two files side-by-side." Opened via the CLI, right-click Move/Open in Split View (tabs, FileTree, PinnedNav), the `⌘\` chord, or the per-page `<meta name="duo-path-target" content="split">`. Closed with `⌘⇧\` or ✕; ⇤ promotes. The divider drags (clamped 20–80%) and double-click resets it to 50/50. State persists across launch.
- :1580 v0.6.4 chapter "Split View v1 + idle-thoughts sweep"; cut blocked on BUG-074 and BUG-075.
- :1529 ENH-085 aux header right-click menu (Reveal / Rename / Copy path / Move back to main / Move to Trash).
- :1540 ENH-083 collapse rail plus the new-tab/globe/collapse-canvas cluster.
- :1552 BUG-075 chord re-pick to ⌘/ and ⌘⇧/.
- :1632 v0.6.4 "filed for v0.6.5": Phase 3c-iii (dirty-replace dialog) and Phase 3c-iv (browser-in-aux). Note: 3c-iii actually landed as e54eb3b on 2026-05-03 (roadmap.html:185 lists it as shipped), so these notes contradict each other.
- :1442/:1451/:1453 **v0.6.7, browser tabs in the Split View aux** (BUG-092 / Phase 3c), plus `duo split-view open-browser`.
- :1454 ENH-095 single ✕. :1471/:1472 BUG-091 (Move to Split View on browser tabs). :1476/:1481 BUG-093 instrumentation; known issue.
- :1410 ENH-080 ⌘⇧A palette: aux tabs carry a "Split" badge and route to aux.
- :1388/:1389/:1394/:1436/:1438 known issues BUG-100, BUG-102, FOLLOWUP-013.
- :1366 `data-duo-workingpane-aux` marker. :1362 ENH-098 focus chords.
- :1331 BUG-091 verified. :1345/:1344 BUG-093 owner-blocked; BUG-100 deferred.
- :1312 the image-render misdiagnosis turned out to be "split-view squished image-viewer pane".
- :1277 ENH-126 auto-redistribute. :1278 ENH-099 ⌘⌥4 / `duo split 3way`.
- :1022 BUG-093 queued again.
- :407 BUG-195: `split-view close` orphaned the aux browser WCV.
- :388 macOS last-window "split teardown".
- :318/:266 BUG-209: the aux WCV occludes modals (filed, then fixed #104).
- :41/:31 **v0.13.7, BUG-270:** aux width pinned and occluding the editor; `duo split-view resize` drives browser-aux (#139).

docs/RELEASES.md:
- :1420-1446 the v0.6.4 narrative and locked decisions, including "styling option A locked".
- :1376-1392 v0.6.5 "navigator + Split View polish".
- :1299-1317 **v0.6.7, "the Split-View-actually-works cut — worksheets, smoke walks, and dashboards live in real Chromium tabs on either side of the divider"**; BUG-093 "diagnostic-armed".
- :1271/:1281/:1289 v0.6.9–0.6.8 chords, palette, BUG-100.
- :1214/:1223/:1225/:1237 v0.6.11 ENH-126 and ENH-099 ("the long-asked-for split-pane auto-redistribute").
- :1261 split-view squish misread. :981-983 v0.6.16 queue (BUG-093, ENH-084 v4). :796-798, :717 carry queues.
- :849 v0.7.0 BUG-133/134: "click no-op on aux pane" for the CDP pill fixed.
- :650 v0.? workspace file restores "splits".
- :391 ENH-188 terminal-tab menu (move-to-split skipped).
- :330 v0.9.1 BUG-195. :266 BUG-209 not fixed in that cut. :253 PR #75 "needs … its own BUG-100 live check".
- :30 v0.13.7 "a Split View whose aux pane sat pinned over the editor and could not be moved (BUG-270)".

Other user-facing docs:
- `docs/legacy/faq.html:129, :163, :171, :180, :187, :191-215, :238-258` ("What's new" mirrors of the above).
- `docs/roadmap.html:134` (v0.13.7), :173-185 (v0.6.4/0.6.5 Split View row with the full locked-behaviour list).
- `docs/about-duo.md:31, :108, :115`: "**Split view** puts two things side by side — the synthesis you're writing next to the raw interview notes it draws from", with screenshots `images/about-duo/main-window.png` ("a PRD beside the prototype it specifies") and `split-view.png`. Commit 6cd1394 "restage about-duo hero shot — PRD + prototype split view".
- `docs/research/docs-deep-clean-decisions.html:702`: walkthrough entry "split-view-two-files · two docs side-by-side".

CLI docs: `docs/CLI-COVERAGE.md:131` (`duo split-view` with sub-verbs `open <path>`, `open-browser <id>`, `close`, `promote`, `resize <pct>`, `state`), :132/:330 (`duo focus-pane`); `skill/references/cli-reference.md:189, :217, :219`; `agents/duo.md:244, :246`. The related verb `duo split <pct|preset|3way>` (terminal/canvas ratio) is in CHANGELOG.md:1839.

## 3. Task items and status

On `main` (tasks.md; open):
- **ENH-041** (tasks.md:1888-1932): 🚧 header frozen at 2026-05-03. 3a-i ✅ 40c9951, 3a-ii ✅ a0c144c, polish ✅ f7ff1fe, styling ⏳ "Owner pick pending" (stale: A was locked), 3b ⏳, 3c ⏳, FTUX 🔵 deferred. Never closed or archived, although 3a/3b/3c-i/3c-iii/3c-browser all shipped (ed4d097, e5c8eb7, e54eb3b, v0.6.7).
- **BUG-093** Move to Split View crashes the renderer (tasks.md:2177-2214): 🟡 instrumented in v0.6.7, priority High. On the unmerged PR #75 branch it is 🟢 FIXED via `flushSync` (cd1dcb1); it "does not reproduce on current code".
- **FOLLOWUP-013** BUG-093 clean repro (tasks.md:3024-): 🟡 carried; the Sprint 16 CLI repro failed.
- **BUG-100** Send→Duo pill missing in the aux browser (tasks.md:2867-2877): 🟡 open/deferred on main. Fix 1cb18a5 is on unmerged PR #75 (the observer was armed on the wrong webContents). PRD in `docs/prd/stage-15-send-to-duo.md` §9 (on that branch).
- **BUG-102** split view goes blank under the ⌘⇧A palette (tasks.md:2841-2857): 🟡 open, Low. The recommended fix is bounds-aware aux muting (about half a day).
- **BUG-196** reloading an aux-pinned browser tab may crash the dev app (tasks.md:597-612): 🆕 needs repro.
- **FOLLOWUP-045** `duo split` clamps 20–80, so the CLI can't collapse a pane (tasks.md:468): 🆕 (adjacent: the outer split, not aux).
- **ENH-084** aux focus glow (tasks-archive.md:9414-): 🟢 "v4 INSTRUMENTATION PASS shipped … awaiting owner click-around walk". v1-v3 failed; **never finished**.

Archived (tasks-archive.md):
- ✅ BUG-270 (:49-96, PR #139, 2026-09-18).
- ✅ BUG-209 (:973-981, v0.11.2).
- ✅ BUG-195 (:1253-1267, 2026-06-06; follow-on renderer-mount re-sync done in BUG-270).
- ✅ ENH-098 (:2759).
- ✅ ENH-099 (:2798; it was first marked "Recommend deferring" and then shipped).
- ✅ BUG-075 (:6528).
- ✅ BUG-091 (:6878).
- ✅ BUG-092 (:6894).
- ✅ BUG-095 (:6912).
- ✅ BUG-096 (:6926).
- ✅ ENH-126 (:7279).
- ✅ ENH-083 (:9388).
- ✅ ENH-085 (:9501).
- ✅ ENH-095 (:9908).
- Also: about:blank spawn loop when the only other tab is in aux (:8163); AuxBrowserSlot had no context menu, fixed walk-1 (:7015, commit 41d00d6); ENH-042 tab reorder, where cross-pane drag is "a v2 concern" (:5216, :5222).

## 4. What it's FOR (PRD / UX)

- The original ask (ENH-041, filed 2026-05-02 from the Stage 27 walk-2 owner request; tasks.md:1913-1925; first text in commit f6ea608): "split the canvas (right pane) into two side-by-side sub-panels … e.g. a markdown editor on the left … + a browser tab on the right … viewable simultaneously." Why: **compare-and-edit** (source md left, generated HTML preview right: "edits on left, watch right repaint"); **reference-while-authoring**; **multi-canvas lessons** (lesson canvas + the HTML being created). The original framing gave **each sub-panel its own tab strip** and drag-between; the spec narrowed this to a single slot.
- Research §4.1 use cases (research.html:880-): edit markdown with live preview; take notes on what you're reading (article + scratch.md); **compare two versions** (v1.md / v2.md, or a diff tab); lesson + playground; reference doc + working file (tasks.md + faq.html); comments rail (future).
- §4.2 capabilities: side-by-side reading and writing ("the most-asked pattern"); a **persistent companion** while main tabs cycle; type-agnostic aux; **agent-driven companion** via the CLI (FTUX "welcome.html in main, walkthrough in aux"); resizable with memory.
- §4.3 deliberate limits: no nesting; right side only; single slot; nothing dragged from the terminal; aux replaces rather than queues.
- In practice its biggest use was **smoke walks**: the worksheet in aux, the thing under test in main (BUG-092 "Why this matters": "the user's natural gesture ('split view, walk on left, canvas on right')"; the smoke-walk skill runs walks in the aux, session-log.md:534).
- about-duo.md:108: the synthesis beside the raw interview notes; hero shot: a PRD beside its prototype.
- Styling intent: "transient companion" vs a peer pane (styling.html §1-3). The owner kept the peer-looking Option A.
- Used by later designs: the ENH-208 vault rollup "must work in both canvas and split-view ('should be trivial')" (tasks.md:333; enh-208-vault.md:46, :178); ENH-221 history-view option C "Split-view aux pane", rejected as it "commandeers the aux slot users want for files/browser" (enh-221-history-view.html:226-296); Home study 13 assumes "Home will often be pinned in a split pane beside a terminal" (home-screen-study-13.html:240, :368); obsidian-vault-research.md:29 "Split View if the user wants two side by side".

## 5. Geoff's own words (verbatim)

- "Pull into this sprint: research on how slack handles sidebar/split view — does not allow infinite split view inception, just one aux sidebar, iirc; I want to do something like this in canvas; this sprint you do the research and spec it out." (research.html:479, 2026-05-02)
- "kb shortcut just ignored" (BUG-075, tasks-archive.md:6547)
- "we need to move the collapse terminal, collapse canvas buttons -- they should be with the new terminal button cluster and the new canvas tab cluster respectively" (ENH-083, :9392)
- "split plane title bar should have same context click verbs as main canvas tab; eg I should be able to move the file in split view to trash via context click" (ENH-085, :9505)
- "canvas sub pan focus needs to be improved; if I am active in the side pane, the sidepane should have the orange glow" (ENH-084, :9414-)
- "glow never moves to split view -- please log the defect, incl failed attempts to fix it, then move on; this has wasted too much time this sprint." (ENH-084, 2026-05-04)
- "inactive canvas pane still glow; whole point is for glow to show focus; when I click back from split view to main pane, split view should lose focus; and vice versa." (ENH-084 v2 verdict)
- "tried to move that canvas to split view (right click tab) and it caused a render error that forced reload of the whole app" (BUG-093, tasks.md:2179)
- "when closed faq.html from main tab, it blanked (dark brown) the split view where I was looking at/working with the smoke walk" (BUG-096, :6928)
- "click on smoke w…" (BUG-095, filed from the rev4 walk; the full quote is truncated in the entry at :6914)
- "when I open a file in split view, the panes should redistribute; if all three (minus terminal) are open, then it should be 33/33/33; if terminal is collapsed, then the main pane and the split view should be 50/50" (ENH-126, :7292, 2026-05-09)
- "opened claude session: pill DOES appear for selected text in main pane, but not in split view" (BUG-100, tasks.md:2869); "non blocking, add to backlog"
- "split view goes blank when search is active; this is a small annoyance and I want to fix in a future sprint -- non urgent" (BUG-102, tasks.md:2843)
- "Split View should be feature parity with main pane; please scrutinize why this disparity exists" (session-log.md:1423, 2026-05-09). Claude's answer: no render disparity; single slot, hardcoded `focusedSubpane='main'` and the simpler header are intentional v1.
- "you said you'd do these, you didn't, and now you're asking me to cut?" (session-log.md:1525, on browser-in-aux before v0.6.7)
- "a bug with sidebar/splitview rendering; the width of the splitview appears pinned and it is occluding the main editing panel" (BUG-270, tasks-archive.md:53, 2026-09-18); "merge but do not cut"
- "the modal 'Close' button is non-functional/no-op; the 'x' works" / "occluded by split view if the window is small enough" (BUG-209, :975, :899)
- vault D2: "must work in both canvas and split-view ('should be trivial')" (tasks.md:333)

## 6. Bugs / issues (all split-related)

BUG-074 (light-mode contrast; co-blocker of the v0.6.4 cut). The rest:
- **BUG-075** ⌘\\ chords ignored (e.key vs e.code; 1Password).
- **BUG-091** tab menu missing the entry.
- **BUG-092** scripted pages dead in a canvas aux.
- **BUG-093** swap crash (un-batched setStates across an await; the aux uses path-derived ids while main uses uuids, so a move is unmount/remount, not key-preserving; tasks.md:2202, PRD on PR #75).
- **BUG-095** an aux click stole main.
- **BUG-096** closing a main tab blanked the aux.
- **BUG-100** aux pill.
- **BUG-102** palette blanks the aux.
- **BUG-134** aux pill click no-op (v0.7.0).
- **BUG-195** close leaves a ghost WCV.
- **BUG-196** aux reload crash.
- **BUG-209** aux WCV occludes modals.
- **BUG-270** pinned aux width after a renderer reload; the WCV has one publisher (a React effect) and survives a reload.
- ENH-084 focus glow defect.
- The about:blank loop (tasks-archive.md:8163).
- Layout misread ("split-view squish", CHANGELOG.md:1312), which led to ENH-124 `duo layout`.

The recurring pattern: **the browser-aux is a second native WebContentsView**, which paints over DOM, needs its own bounds and park/restore, and its own CDP attach. That is the root of BUG-095/096/100/102/195/196/209/270. Regression checks: `docs/dev/smoke-checklist.md:162-178` §4a.

## 7. Planned but never finished

- **Option B, multi-tab aux with its own strip**: queued for v2, with the state shape ready (research.html §7, :1021). Never built.
- **Drag a tab to the right edge to create a split**, and drag between panes (research.html:1021-; ENH-041 scope 3; ENH-042 tasks-archive.md:5216).
- **Aux "expand to fullscreen"** (Slack's secondary affordance), out of scope for v1.
- **Pinning in aux**: "revisit if/when Option B ships".
- **FTUX auto-split welcome**: "Revisit before the cohort cut". Never revisited.
- **Option D twin views** (md source↔preview pair): "complementary". Never built.
- **Save button in the dirty-swap dialog**: waiting on save-by-path dispatch.
- **ENH-084 aux focus glow**: v4 instrumentation only; the fix was never designed. (Code: `AuxHeader` takes a `focused` prop, `renderer/components/WorkingPane.tsx:950-958`.)
- **BUG-093 and BUG-100 fixes**: stranded on open **PR #75** (`claude/amazing-goodall-39846b`, since 2026-06-07). On main they are still open.
- **BUG-102** (bounds-aware mute) and **BUG-196** (repro): never done.
- **ENH-191 multi-window**: `duo split-view` / `focus-pane` need `--window` addressing and per-window `auxTabId`/`splitPct` (enh-191-multi-window.md:313, :332, :847, :967; "Split-pane/split-view/focus-pane as coverage:none"). The status of that item was not traced further.
- The **styling Option B** recommendation was not taken (A locked). ENH-041's header still says "Owner pick pending" and the item was never closed.
- **Stale leftovers.** The code tooltip still says "Move back to main (⌘⇧\\)" although the chord is ⌘⇧/ (`WorkingPane.tsx`, AuxHeader). The PR #75 branch notes "⌘/ chord does not forward from the canvas iframe" (filed separately; the move never fires from canvas focus).

## Sources searched

`docs/DECISIONS.md`, `docs/RELEASES.md`, `CHANGELOG.md`, `docs/prd/*`, `docs/ux/*` (layout-options.html: only the terminal/working split), `docs/design/*` (atelier: only `splitPct` props), `docs/research/*`, `docs/legacy/faq.html`, `docs/about-duo.md`, `docs/roadmap.html`, `docs/dev/{session-log,active-sprint,smoke-checklist}.md` + session-recaps, `tasks.md`, `tasks-archive.md`, `agents/duo.md`, `skill/`, `docs/CLI-COVERAGE.md`.
- No hits in VISION.md, duo-brief.md, README.md, CLAUDE.md, AGENTS.md or help/.
- No deleted docs matched split/aux (`git log --all --diff-filter=D`).
- GitHub: issues search returned nothing. Relevant PRs: #139 (merged), #75 (OPEN), #70, #104, #32.
- Key commits: f6ea608 (filed), 9f0b793/bb7e012/5d87b2c (research), 40c9951, a0c144c, 5506f06, f7ff1fe, ed4d097, e5c8eb7, e54eb3b, 511d8b8 (all v0.6.4); 8ac1507, 48d4cbd, d063b47 (v0.6.5); 99826fa (BUG-091); v0.6.7 Phase 3c; 9276af6 (BUG-195); 3b05c96 (BUG-209); e9ac6cd (BUG-270); cd1dcb1 and 1cb18a5 (PR #75 only).
