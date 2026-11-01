# Legacy Duo's Split View: its history and the reasons behind it

*Split view study, part 1 (research/split-view, 2026-10-31). Read only: legacy Duo is `~/repos/duo` (Electron, 1,133 commits, HEAD `5126c47`, v0.13.8-dev). Nothing there was run or changed. References are legacy commits (short sha) or legacy files (`path:line`). The detail behind this page is in `legacy/`: `commits.md` (every commit, by phase), `documents.md` (decisions, release notes, tasks, Geoff's words) and `code.md` (how the final code behaves).*

**Names.** In the code it is the **aux** slot ("auxiliary"), in the UI **Split View**, on the CLI `duo split-view`, in the ledger **ENH-041**. Of `git log -i --grep=split`'s 154 hits about 100 are something else (document splits, the "split-button", ENH-156 "verb-split", ENH-191 teardown splits); they were dropped (`legacy/commits.md` §Method).

## In one paragraph

One companion slot on the right of the canvas (the right pane), modelled on Slack's thread sidebar: terminal | main canvas with its tab strip | aux, one item, no tab strip (`docs/prd/canvas-split-view-research.html:479-492`, bb7e012). The aux held any file tab (Markdown, HTML page, image, PDF, JSON) or, from v0.6.7, a real browser tab (a second native WebContentsView, `renderer/components/AuxBrowserSlot.tsx`). A path was never open in both panes on purpose (bb7e012), though opening it again from the tree, ⌘O or `duo open` quietly made a second, independent editor in main (`legacy/code.md` §2). It was made by right-click (Move to Split View on a tab, Open in Split View on a file), ⌘/ and the CLI; resized by a 4 px divider clamped to 20–80 %; closed by ✕ or ⌘⇧/, which both put the file back in main; persisted per window. Focus never worked: which side you were in was never tracked, so ⌘W, the focus glow and the agent's "current document" all ignored the aux. Its real use turned out to be smoke-walk worksheets beside the thing under test, and a PRD beside its prototype (`docs/about-duo.md:108`, 6cd1394).

## What it was for

- The ask (ENH-041, `tasks.md:1913-1925`, f6ea608, 2026-05-02, from the Stage 27 walk): "split the canvas (right pane) into two side-by-side sub-panels … e.g. a markdown editor on the left … + a browser tab on the right … viewable simultaneously." Three uses were named: **compare-and-edit** (Markdown source left, generated HTML preview right, "edits on left, watch right repaint"), **reference while authoring**, and **lessons** (a lesson canvas beside the HTML being made).
- The research page (`canvas-split-view-research.html` §4.2) adds a persistent companion while main tabs cycle, any kind of item in the aux, and an agent-driven companion over the CLI.
- In use: the worksheet beside the app under test ("the user's natural gesture ('split view, walk on left, canvas on right')", BUG-092, `tasks-archive.md:6894-6908`); the smoke-walk skill opened walks in the aux (7f1871a); "the synthesis you're writing next to the raw interview notes it draws from" (`docs/about-duo.md:108`).
- **Source beside its preview was considered and deferred.** Option D, "linked twin views" (Markdown source with its live preview as a pair), was judged "complementary" to the aux and never built (`research.html` §3 D, §7). That is exactly the deck case now.

## Timeline

| When | What | Ref |
|---|---|---|
| Apr 22 – May 2 | Precursors: the terminal / canvas split and its drag handle; BUG-031, the divider stalls over an iframe (fixed by an overlay that can't cover a native view, the first sign of the problem that runs through the whole story); preset sizes ⌘⌥1/2/3; collapse buttons | d1e4d84, f016060, dfc152c, b11a820, 238de40 |
| May 2 | ENH-041 filed at Geoff's request. Geoff: "research on how slack handles sidebar/split view — does not allow infinite split view inception, just one aux sidebar, iirc; I want to do something like this in canvas" | f6ea608, `research.html:479` |
| May 2 | Research page: options A (single aux, recommended), B (aux with its own tabs, later), C (VS Code recursive, rejected by Geoff by name), D (linked twin views, "complementary") | 9f0b793 |
| May 2 | Option A locked by question rounds: move/open semantics, one path in one pane, "B-ready" state `aux {tabs[], activeIndex, splitPct}`, persistence, no pinning, ⌘\ / ⌘⇧\ | bb7e012, 5d87b2c |
| May 2–3 | Build: CLI and IPC, first UI (header, divider 20–80 %, double-click 50/50), per-link `data-duo-target="split"` and `<meta duo-path-target=split>`, entry points, persistence, the dirty-replace dialog | 40c9951, a0c144c, f7ff1fe, ed4d097, e5c8eb7, e54eb3b |
| May 3 | Styling round: Claude recommended B (accent rule, italic filename, "subordinate companion"); Geoff kept A, the plain symmetric header with SPLIT | 5506f06, ed4d097 |
| May 3 | Geoff's refinements: ⌘⇧\ promotes instead of closing; replacing the aux swaps the old file back to main | 511d8b8 |
| May 3 | v0.6.4 walk: 4 fails, the cut blocked; BUG-075, the chords ignored. v0.6.4 never tagged | 9546d55 |
| May 3 | BUG-075 fixed twice (e.key vs e.code in the matcher, then in the web view's key forwarder), then the real cause: 1Password takes ⌘\ system-wide. Chords moved to ⌘/ ⌘⇧/. The focus glow (ENH-084) tried three ways and backed out; Geoff: "this has wasted too much time this sprint." **v0.6.5 is the first release with Split View** | 8ac1507, f089048, 48d4cbd, d063b47, 09ea310 |
| May 4–5 | BUG-091/092: moving a scripted page into the aux put it in a sandboxed iframe and its buttons died. Fix: real browser tabs in the aux, a second native view. BUG-095 (clicking the aux browser switched main's tab), BUG-096 (closing main's last browser tab blanked the aux). The header shrinks to one ✕ that promotes. Geoff, on the cut: "you said you'd do these, you didn't, and now you're asking me to cut?" (v0.6.7) | 99826fa, a366c4e |
| May 6–18 | BUG-093, Move to Split View crashed the renderer (never reproduced; suspected setState across an await); the ⌘⇧A palette learns split tabs; BUG-100, no Send pill in the aux browser; BUG-102, the aux blanks while the palette is open; focus chords ⌘⇧L/;/' (v0.6.9); ENH-126 auto 33/33/33 and 50/50 on open (v0.6.11); ENH-084 v4, logging only | cc608ad, 66b2b31, 5a7e3e8, 7b45370, 8b85677, 5304732, d0fdc44 |
| May 21 – Jun 21 | Workspace files carry the aux; BUG-195, `split-view close` left a ghost native view painted over the UI; multi-window addressing (ENH-191); clipboard fallback because the aux view isn't the focused frame; BUG-209, the aux view covers modals | 9cd6bf8, 9276af6, 8ed3618, f117211, 3b05c96 → 66b9d87 |
| Sep 18 | BUG-270, the last fix. Geoff: "the width of the splitview appears pinned and it is occluding the main editing panel". After a renderer reload every native view kept painting at its old rectangle; the clamp had three drifting copies. Fixed and shipped in v0.13.7, the last legacy release | e9ac6cd, 52e8f51, 14adfbe, PR #139, 8d214f3 |

## How it worked at the end

| Question | Legacy's answer | Ref |
|---|---|---|
| Where | Only the canvas splits, never the terminal. Main + one aux on its right; no nesting, no left/top/bottom | `WorkingPane.tsx:673-1061` |
| What goes in a side | Any file tab (by the same `renderFileTab`), or one browser tab; not both. The state was shaped for several aux tabs but held one | `App.tsx:655, :674` |
| Same file twice | Forbidden by design (moving takes it out of main), but reopening it from the tree, ⌘O or `duo open` makes a second editor; each side then treats the other's saves as outside edits (reload if clean, conflict banner if dirty) | `legacy/code.md` §2, §6 |
| Making one | Right-click a tab: Move to Split View; right-click a file or pinned row: Open in Split View; ⌘/; `duo split-view open|open-browser`; links tagged for the split. Never built: drag to split, a menu item | ed4d097, f7ff1fe |
| Sizing | 4 px divider, the aux's share clamped 0.20–0.80, no minimum in points; double-click evens; opening always snaps to 50/50 (and 33/67 with the terminal); ⌘⌥4 three-way even | `shared/split-view.ts`, 5304732 |
| Closing | ✕ and ⌘⇧/ put the aux file back in main as a tab; the CLI's `close` discards instead. Swapping a dirty aux asks Cancel / Discard in a system alert, no Save. "Empty main promotes the aux" was specified, never built | 511d8b8, e54eb3b, `research.html:961` |
| Persistence | `aux {paths, activeIndex, splitPct}` per window in `~/.claude/duo/session-state.json` and in `.duo-workspace`; missing paths dropped; a browser aux not kept | e5c8eb7, 9cd6bf8 |
| Focus | Not tracked: `focusedSubpane` is frozen at main, the aux editor's `isActive` is always false, the glow never lit (ENH-084) | `WorkingPane.tsx:294-356` |
| ⌘W | Closes main's tab even with the caret in the aux | `App.tsx:4291-4313` |
| ⌘S / autosave | Per editor, whichever has the caret | `legacy/code.md` §5 |
| Find | ⌘F opens a find bar in every mounted editor, routed by main's tab kind | `MarkdownEditor.tsx:2121-2135` |
| Send to Claude / selection | `duo selection` returns whichever editor was touched last; each editor has its own Send pill and formatting bar, so both sides worked, except the aux browser (BUG-100, its fix stranded on a branch) | 1cb18a5 (unmerged) |
| Agent verbs | `duo doc read` with no path, `duo image insert`, View source, Suggesting mode and ProposeBar never reach the aux (they follow `isActive`); agents open in main unless the user says "alongside", "side by side", "in split" | f7ff1fe |
| Narrow windows | Nothing: either side could shrink to tens of points; the image viewer "squished" | `CHANGELOG.md:1312` |
| Multi-window | Split verbs act on the primary window while `state` reads the CLI's own | `legacy/code.md` §8 |
| Tests | Units only (the clamp, the chords, the reload contract, saving the state); nothing for move, swap, promote, the dirty prompt, restore, focus or ⌘W | `legacy/code.md` §9 |

## Decisions and their reasons

There is no Split View ADR: the research page promised one (`research.html:1039`) and it was never written. The decisions live in the PRD's question rounds, ENH-041 and the release notes (`legacy/documents.md` §1, SV-1 to SV-22).

| # | Decision | Reason given | Ref |
|---|---|---|---|
| SV-1 | One aux slot, right side only (A); B later; C rejected | Geoff's ask; "cognitive ceiling": terminal + canvas + aux "is three columns of attention … a fourth would compete"; C rejected as "infinite split view inception", drag-target ambiguity, tree-shaped persistence, "tools you reach for, not tools you configure" | `research.html:479-492, :776-830` |
| SV-3 | Never the same path in both panes; Move from a tab, Open from a file | One source of truth | bb7e012 |
| SV-4 | State shaped for many aux tabs, one in the UI | "near-zero migration cost when/if Option B ships" | `research.html` §5 |
| SV-6 | Empty main promotes the aux | Never leave empty main beside a full split. Not built | `research.html:961` |
| SV-7 | Ratio and aux persist | "find their split exactly as they left it". Undone in practice by SV-19 | e5c8eb7 |
| SV-8 | No pinning in the aux | Split is a "transient companion" | `research.html:963` |
| SV-9/16 | ⌘\ to split, ⌘⇧\ to promote; then ⌘/ and ⌘⇧/ | "Backslash … reads as split"; then 1Password takes ⌘\ | 511d8b8, d063b47 |
| SV-10 | Swap, not replace; dirty asks Cancel / Discard | The displaced file "lives on in main"; no Save because saves were per editor and async | 511d8b8, e54eb3b |
| SV-12 | Agents open in main unless told "alongside" | Keep the split for the user | f7ff1fe |
| SV-14 | Plain symmetric header (A) over the "subordinate" B | Geoff's pick; reason not recorded | ed4d097 |
| SV-17 | One ✕, and it promotes | The two buttons did the same thing; Geoff: ✕ always keeps the file | a366c4e |
| SV-18 | Real browser tabs in the aux | Sandboxed iframes killed scripted pages | `tasks-archive.md:6894-6908` |
| SV-19 | Opening redistributes to 33/33/33 or 50/50 | Geoff: "if all three (minus terminal) are open, then it should be 33/33/33; if terminal is collapsed, then the main pane and the split view should be 50/50" | `tasks-archive.md:7292` |

## Geoff's words

Verbatim, from `legacy/documents.md` §5:
- "does not allow infinite split view inception, just one aux sidebar, iirc; I want to do something like this in canvas" (`research.html:479`)
- "canvas sub pan focus needs to be improved; if I am active in the side pane, the sidepane should have the orange glow" and "inactive canvas pane still glow; whole point is for glow to show focus; when I click back from split view to main pane, split view should lose focus; and vice versa." (ENH-084)
- "glow never moves to split view -- please log the defect, incl failed attempts to fix it, then move on; this has wasted too much time this sprint." (ENH-084)
- "split plane title bar should have same context click verbs as main canvas tab" (ENH-085)
- "Split View should be feature parity with main pane; please scrutinize why this disparity exists" (`session-log.md:1423`)
- "opened claude session: pill DOES appear for selected text in main pane, but not in split view" (BUG-100)
- "split view goes blank when search is active" (BUG-102); "the width of the splitview appears pinned and it is occluding the main editing panel" (BUG-270); "occluded by split view if the window is small enough" (BUG-209)

## What broke, and why

Grouped by cause rather than by number (each bug and its fix: `legacy/commits.md` §Every bug):

1. **A second native view over web content** (BUG-031, 092, 095, 096, 102, 195, 196, 209, 270). The aux browser was a separate native view composited above the page, with its own bounds, focus, debugger and park/restore around every modal. Every later bug came from keeping two rectangles in step. *v2 lesson:* a side's content lives in the view tree like any other tab, never as an overlay positioned by hand. v2's web views are already ordinary subviews (F-120's snapshot rule is about captures, not layering).
2. **No model of which side is active** (ENH-084, ⌘W, `isActive`, `duo doc read`, the palette, BUG-100). Focus was guessed from DOM events after the fact; three fixes failed. *v2 lesson:* the active side is model state from day one, set by the same path as DL-165's active pane, and every command (⌘W, ⌘S, find, Send, voice, the formatting bar, `duo2` with no path) resolves through it.
3. **One path, two editors** (reopen from the tree; each side treating the other's saves as outside edits). *v2 lesson:* one document model per file, any number of views of it.
4. **Chords chosen without checking the machine** (BUG-075, 1Password and ⌘\). *v2 lesson:* any shortcut goes through DL-34's process and is checked against common system-wide grabbers.
5. **State shape drifting from behaviour** (`splitPct` documented as main's share, used as the aux's; three copies of the clamp; the saved ratio overridden by ENH-126). *v2 lesson:* one place owns the split's geometry, and saving it means restoring it.
6. **Async moves across several state updates** (BUG-093, never reproduced). *v2 lesson:* making, swapping and closing a split is one synchronous model change.
7. **No narrow rules** (squished image viewer, BUG-209 at small windows). *v2 lesson:* a minimum width per side and a defined fold, under DL-129.
8. **Behaviour tested by walks only.** *v2 lesson:* split's rules are DuoChecks from the start.

## Left unfinished

- ENH-041 was never closed ("actively building", `tasks.md:1888`); there's no ADR.
- ENH-084, the aux focus glow, never fixed; its `[ENH-084-v4]` logging is still in `WorkingPane.tsx`.
- BUG-093 and BUG-100's fixes exist only on `origin/claude/amazing-goodall-39846b` (cd1dcb1, 1cb18a5); BUG-102 and BUG-196 open.
- `App.tsx:~3882` TODO: ⌘⇧' can't focus a browser aux.
- Never built: several aux tabs (B), drag between panes, pinning, the aux full-screen, a first-run split, Save in the dirty dialog, empty-main promotes, and Option D, the paired source and preview.
- Stale: the aux header's tooltip still says ⌘⇧\.

## What v2 keeps, drops and fixes

- **Keep:** one split, two sides, no nesting (SV-1, Geoff's own ask); a file can't be lost by closing or swapping a side (SV-10, SV-17); split state persists and restores (SV-7); agents open in a split only when asked (SV-12); any kind of right-pane tab can be a side.
- **Drop:** a separate overlay for web content; a system alert for a dirty swap (v2 never shows one, and saves as you type); snapping to 50/50 over the saved ratio; a second editor on one file.
- **Fix:** the active side as model state with a visible mark (DL-165's rule) and every command routed by it; one document per file, so a source and its preview, or the same file twice, can't disagree; minimum widths and a fold for narrow windows; `duo2` verbs addressed by window; DuoChecks for make, swap, close, restore, focus and ⌘W.
- **New for v2:** Option D, the pair legacy deferred: a source beside its own rendering (deck, Markdown, HTML), with sync between them. See `options.md`.
