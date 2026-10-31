# Legacy Duo (Electron) — Split View, as built at HEAD

Repo: `/Users/geoff/repos/duo` at `5126c47` ("chore: bump to v0.13.8"). Read-only study; nothing run.
Feature id **ENH-041**. User-facing name "Split View"; internal name **"aux"**. Locked spec:
`docs/prd/canvas-split-view-research.html` (Option A, "Slack-style, one aux pane"); styling options
`docs/prd/canvas-split-view-styling.html`; backlog entry `tasks.md:1888`.

All paths below are relative to `/Users/geoff/repos/duo`.

---

## 1. What could be split, how many sides, orientation

- **Only the canvas (the right-hand working pane).** The terminal column never splits ("No drag from terminal
  column. Aux is a CANVAS-side companion", spec §4.3). Layout = terminal | main canvas | aux.
- **Exactly two sides: main + one aux.** No nesting, no second aux (Option C, recursive split, rejected by name).
- **Side by side only, aux always on the right.** `WorkingPane.tsx:755` switches the pane to a horizontal flex
  when `splitOpen`; main column `:762-768`, `SplitViewDivider` `:771`, aux column `:775-823`
  (`border-l`, marked `data-duo-workingpane-aux="1"`).
- **The aux is a single slot with no tab strip.** State is shaped for several tabs from the start (`paths[]` / `tabs[]`,
  "B-ready") but v1 holds 0 or 1 (`shared/types.ts:585-608`, `App.tsx:642-662`). The aux shows a slim
  header: a "Split" label, the file name and one ✕ (`WorkingPane.tsx:848-983`).

## 2. What could go in each side

- **Main:** the normal tab strip with every kind (editor, page/HTML canvas, markdown-preview, image, pdf, json, home,
  vault, rollups, browser).
- **Aux, two kinds that exclude each other:**
  - **File aux** (`auxState.paths`, `App.tsx:655`). Rendered by `buildAuxFileTab(path)` (`WorkingPane.tsx:833-846`),
    which builds a synthetic `FileTab` with id `aux:<path>` and passes it through the same `renderFileTab`
    (`:576-670`). So any file kind works: markdown editor (TipTap), HTML page canvas, preview, image, PDF, JSON.
  - **Browser aux** (`auxBrowserTab`, `App.tsx:674-679`; added in "Sprint 7 Phase 3c"). A real Chromium
    WebContentsView, pinned by `BrowserManager.moveTabToAux` (`electron/browser-manager.ts:1010`), so its
    scripts keep running. `AuxBrowserSlot.tsx` pushes the view's bounds (`setAuxBounds`, ResizeObserver,
    `:~95-125`). The tab drops out of the main strip through `inAux: true` (`browser-manager.ts:625-626`,
    `WorkingPane.tsx:270`).
  - Putting a file in clears a browser pin, and pinning a browser tab promotes the aux file
    (`App.tsx:3980-3989`, `4133-4146`).
- **The same file twice:** by design, never. "Single source of truth per file": moving a file into aux removes
  its tab from main (`App.tsx:4040`). **But it isn't enforced on the open path.** `openFile`/`openFileSmart`
  (`App.tsx:2275`, `2326`) look only at `fileTabs`, and the aux file has been removed from `fileTabs`. So opening an
  aux file again from the navigator, ⌘O or `duo open` mounts a **second, independent editor** on the same
  path in main (see §6).

## 3. Making, resizing, closing and swapping a split

**Making a split** (every route ends in `splitViewMoveTabByPath(path)`, `App.tsx:3962-4079`):
- Tab right-click → "Move to Split View" (`WorkingTabStrip.tsx:723-734`, handler `:252`). File tabs send their path;
  browser tabs go to `splitViewMoveBrowserTab` instead.
- Navigator file row → "Open in Split View" (`FileTree.tsx:1366-1372`; files only). Pinned-nav row
  (`PinnedNav.tsx:106-109`).
- Keyboard: **⌘/** = move the active main file tab into the split (`globalShortcuts.ts:487-489`, `splitViewToggle`
  `App.tsx:4089-4097`). The spec says ⌘\; it was re-picked to ⌘/ under BUG-075 because 1Password grabs ⌘\
  (`globalShortcuts.ts:469-486`). The comments in `useKeyboardShortcuts.ts:66` and in the AuxHeader tooltip
  (`WorkingPane.tsx:975`, "⌘⇧\\") are stale.
- Page links: only inside **browser** tabs on `file:` pages. An injected CDP click forwarder routes
  `[data-duo-path]` clicks to split when the link has `data-duo-target="split"` or the page has
  `<meta name="duo-path-target" content="split">` (`electron/cdp-bridge.ts:835-875`, `main.ts:1016-1029` →
  `splitViewOpen`). The spec's "right-click any local `<a href>` → Open in Split View" was **never built**.
- CLI: `duo split-view open <path>` and `duo split-view open-browser <id>` (see §8).
- **No drag-to-split and no menu-bar item** (the spec deferred drag to v2).

**Side effects of opening (ENH-126):** the aux ratio snaps to 50/50 (`App.tsx:4060-4068`). The outer
terminal/working split snaps to 33/67 unless the terminal or canvas is collapsed (`:4069-4076`).

**Resizing:**
- `SplitViewDivider` (`WorkingPane.tsx:990-1061`): a 4px bar. Dragging puts a full-window transparent overlay over
  everything so iframes and WebContentsViews can't swallow mousemove (BUG-031). Ratio = `(right − x)/width`.
  Double-click resets to 50/50.
- `splitPct` is the **aux** column's share of the width, held between **0.20 and 0.80** by one shared clamp
  (`shared/split-view.ts:11-45`). Columns are `flex: <pct*100> 0 0%` with `min-w-0` (`WorkingPane.tsx:765,778`).
  There is **no minimum in pixels**.
- Other routes: ⌘⌥4 or View ▸ Pane size ▸ "3-way even (33/33/33)" (`main.ts:~4090`), and `duo split 3way`
  (`App.tsx:4558-4570`), which set outer 33 and aux 0.5. `duo split-view resize <pct>` (`App.tsx:4819-4830`) takes a
  fraction, or a percentage when the value is >1.

**Closing and promoting:**
- In the UI, **✕ and ⌘⇧/ both promote**: the aux file comes back as a new main tab and becomes active.
  `onAuxClose` and `onAuxPromote` are both wired to `splitViewPromote` (`App.tsx:5548-5549`, `4107-4125`; "Sprint 7
  rev6 single ✕" comment `WorkingPane.tsx:964-969`). The aux header's right-click menu: Reveal in navigator,
  Rename…, Copy path, Move back to main, Move to Trash… (`WorkingPane.tsx:889-947`; trash →
  `App.tsx:5591-5598`).
- **CLI `duo split-view close` discards instead**: it clears the aux without promoting (`App.tsx:4782-4792`).
  `duo split-view promote` promotes (`:4793-4817`). So the UI and the CLI mean different things by close.
- Spec rule "close the last main tab → the split moves into main": **not implemented**. `closeFileTab`
  (`App.tsx:2443-2481`) never reads `auxState`. Home can't be closed anyway.

**Swapping (the aux already holds a file):** the incoming file takes the aux, and the old aux file is promoted to a
new main tab, which becomes active if the incoming file was the active main tab (`App.tsx:3995-4058`). If the old aux
file is dirty, a native `dialog.confirm` asks Cancel / "Discard changes", with no Save button
(`:4002-4030`). That breaks Duo v2's no-system-alert rule. A path that's already in the aux is a no-op (`:3990`).

## 4. Persistence

- **What's saved:** `aux: {paths[], activeIndex, splitPct}` in the session snapshot (`App.tsx:1077-1086`), on a 500 ms
  debounce (`:1089-1099`). It's written to **`~/.claude/duo/session-state.json`**
  (`core/session-state-service.ts:73`). Since multi-window (ENH-191 P4, schema v2) it's stored **per window**:
  `WindowState.aux` (`shared/types.ts:953-968`).
- **Checked on load:** `validateAux` (`session-state-service.ts:486-507`) drops bad shapes and clamps the ratio. On
  restore, paths no longer on disk are dropped and the split closes silently (`App.tsx:916-937`).
- **Browser aux isn't persisted.** On relaunch it's back in the main strip (`shared/types.ts:888-893`, `App.tsx:665-673`).
- **Also saved in `.duo-workspace` files** (ENH-167 "Save Session"; `core/workspace-file-service.ts:109-118`), so it's
  per saved workspace. It isn't per project and isn't per Claude session.
- The "remember the last drag" promise is broken: every open snaps to 50/50 (ENH-126). A resize with no split open is
  a no-op and isn't remembered (`App.tsx:4826`).

## 5. Focus and what each command acts on

- There's no real record of which side has focus. App tracks `focusedColumn` (terminal/files/working) only.
  `WorkingPane`'s `focusedSubpane` is a `useState('main')` whose setter is never used (`WorkingPane.tsx:304`). So the
  aux header's focus glow **never lights** (ENH-084: three fix attempts failed, then instrumentation only, gated
  behind `localStorage duo.debug.focus`, `:295-360`).
- **`isActive` is always false for the aux editor**, because `isFileActive('aux:<path>')` never matches
  `activeWorking` (`WorkingPane.tsx:573-574`). Things gated on `isActive` therefore **never reach the aux editor**:
  - `duo doc read` with no path (`MarkdownEditor.tsx:1839`)
  - `duo image insert` (`:2410`)
  - View source ⌘⌥V (`:2360`)
  - Suggesting toggle ⌘⌥T (`:1810`)
  - ProposeBar (`:2839`)
  - the JSON `duo json set` gate
  - PageTab `focused`/`isActive` (`:1871`, `:1926`), so an aux HTML canvas never takes focus programmatically.
  - BUG-271's suspend fires on the aux editor's wiki/@ popovers, because it is "inactive".
- **Jumping focus:** ⌘⇧L / ⌘⇧; / ⌘⇧' jump to terminal / main / aux (`globalShortcuts.ts:397-411`;
  `focusPane`, `App.tsx:3828-3895`). Aux focus finds the contenteditable inside `[data-duo-workingpane-aux]`
  (`findVisibleWorkingPaneCE`, `App.tsx:376-388`). For a browser aux it does nothing (a TODO). There's a CLI twin:
  `duo focus-pane aux`.
- **⌘W** closes the **main** active tab whenever the working column has focus, even with the caret in the aux
  (`App.tsx:4291-4313`). It never closes the aux. The spec's "⌘W targets the focused pane" isn't met.
- **⌘S** works per editor: each MarkdownEditor saves when `document.activeElement` is inside its own host
  (`MarkdownEditor.tsx:2526-2540`), so it saves whichever side has the caret. Autosave (800 ms, on by default) runs
  per editor and flushes on unmount (`:1394-1403`).
- **⌘F / ⌘G** pick the event by the **main** active tab's kind (`App.tsx:4410-4430`). The editor listener isn't
  gated (`MarkdownEditor.tsx:2121-2135`; its comment wrongly says only one editor is mounted). So ⌘F opens the find
  bar in *every* mounted editor, main, aux and hidden ones alike. With a browser tab as the main surface, the aux
  editor gets no find.
- **Send to Claude / selection:** there's one selection cache in main, and the last editor to push wins. Each editor
  pushes on selectionUpdate, focus, blur and update (`MarkdownEditor.tsx:1434-1465`), so `duo selection` returns
  whichever side was touched last. Unmount pushes `null`. The Send → Duo pill belongs to each editor and shows only
  while that editor `isFocused`, so it works on either side. The "Claude is reading" glow lights the whole working
  column, not the side (`App.tsx:4505-4535`).
- **Formatting toolbar:** each MarkdownEditor/PageTab has its own toolbar, so the aux editor has its own.
- **⌘⇧A tab palette:** aux file tabs are meant to carry a "Split" badge. But `inAux` is computed from `fileTabs`
  (`App.tsx:3613-3620`) and the aux path has been removed from `fileTabs`, so **aux files don't appear in the palette
  at all**. Only browser-aux entries are badged.

## 6. Disk reconciliation

- It's done per editor instance: `renderer/hooks/useDiskReconciliation.ts` (ENH-195: chokidar watch, echo set,
  byte-exact baseline, "changed on disk" banner). There's nothing aux-specific. The aux editor is a full
  MarkdownEditor/PageTab, so it reloads Claude's and other external edits like main does: it reloads if clean and
  banners if dirty.
- **No shared buffer.** If the same path is open in main *and* aux (possible, as §2 shows), there are two separate
  TipTap documents with two watchers. A save from one side is an external write to the other: the other side
  reloads if clean, or shows a conflict banner if dirty.
- Dirty state is tracked by path in `dirtyPaths`, so aux tabs (`aux:` ids) are counted (`App.tsx:2525-2565`). Its only
  user is the swap gate. **Promote/✕ has no dirty check**. The move unmounts and remounts the editor, and unsaved
  edits survive only through the unmount autosave flush, so they're lost when autosave is off. The aux header shows
  no unsaved dot.

## 7. Narrow windows

Nothing specific. Columns can shrink to nothing (`min-w-0`), with only the 20–80 % limit, so a small window can leave
the aux tens of pixels wide (`tasks.md:~2287`: "image-viewer squished to ~80px"). Slack's fall-back to an overlay on
narrow screens was noted in the research and not built. Opening the ⌘⇧A palette blanks the browser aux WebContentsView
(it's muted to 1×1 along with main; `browser-manager.ts:1156`; open item `tasks.md:2843-2859`).

## 8. CLI and agent verbs

- `duo split-view [state]` and `open <path>`, `open-browser <id>`, `close`, `promote`, `resize <pct>`
  (`cli/duo.ts:381-386`, `1548-1600`; `core/socket-server.ts:1785-1838`; `electron/main.ts:5912-6062`). The state
  query reads a cache in main that the renderer pushes to (`WORKING_AUX_STATE_PUSH`, `main.ts:3549`,
  `App.tsx:4840-4879`). It returns `{aux:null}` or `{aux:{activePath, activeKind, splitPct}}`. IPC channels are at
  `shared/types.ts:2630-2653`; the preload bridge at `preload.ts:760-780`.
- Related: `duo split <pct|even|3way…>` (the outer terminal/canvas split), `duo focus-pane <terminal|main|aux>`, and
  `duo layout` (a JSON snapshot that includes `aux`, `App.tsx:4590-4640`).
- **No `duo open --split`. No MCP tools** (no MCP server in electron/core/cli).
- Agent guidance (`agents/duo.md:246`, `skill/references/cli-reference.md:217`): "Default opening location is ALWAYS
  main — never autonomously open in split". The words that route to split are "in split / alongside / side by side
  / as a companion".
- Multi-window: every split-view verb sends to `windowByIdOrPrimary(undefined)`, the **primary** window
  (`main.ts:5922`, `5947`, `5965`, `6035`, `6049`). The state query, however, reads `cliDefaultWindowId()` (`:6061`).
  So with two windows, a `duo split-view` from window 2's terminal changes window 1 and reports window 2.

## 9. Tests

- `shared/split-view.test.ts`: the clamp. In-range values pass through; dragging past the left edge gives max aux,
  past the right edge gives min; non-finite input gives 0.5; >1 is read as a percentage; the main column's grow factor
  is always positive.
- `renderer/keyboard/globalShortcuts.test.ts:58-95`: ⌘/ → `splitViewToggle`, ⌘⇧/ → `splitViewPromote`, and the
  shifted chord doesn't fall through to toggle (BUG-075).
- `shared/wcv-bounds.test.ts`: after a renderer reload, every view including the aux pin is parked at 1×1 and the aux
  pin is dropped so main and renderer agree. These are the BUG-195/BUG-270 "ghost" tests.
- `core/session-state-service.test.ts:188-193`: aux round-trips per window through the v2 envelope.
  `core/session-envelope.test.ts:31,58,77`: aux carried through the v1→v2 migration.
- `.claude/skills/worksheet/generate.test.ts:518-532,867`: generated worksheets emit `duo-path-target=split`; there's a
  clipboard fallback for the aux view.
- **No renderer or component tests of the split itself**: no test of move, swap, promote, the dirty gate, restore,
  focus or ⌘W. The spec relied on a manual smoke walk for those.

## 10. Hacks, TODOs and rough edges in the code

- `[BUG-093]` `console.log` traces fire at every step of `splitViewMoveTabByPath` (`App.tsx:3971-4078`). They were left
  in because "Move to Split View can crash the renderer" (`tasks.md:2177-2214`; it was never cleanly reproduced). The
  suspected cause is several setStates around `await`, which defeats React batching and leaves half-swapped renders.
- ENH-084 aux focus glow: dead state, plus instrumentation only (`WorkingPane.tsx:294-360`).
- TODO: no IPC to focus the aux browser view (`App.tsx:3876-3886`).
- `splitPct` doc comments contradict each other. `WorkingAuxState` says "Main-pane width as fraction"
  (`shared/types.ts:605`) and so does `App.tsx:660`. The divider and the layout treat it as the **aux** fraction
  (`WorkingPane.tsx:1019-1026`).
- The ✕ promotes but CLI `close` discards (above). The spec says ✕ discards; "Sprint 7 rev6" changed the UI only.
- The aux editor's id is `aux:<path>`, so callbacks such as `onCommitNewFile` and `onCancelNew → closeFileTab(aux:…)`
  get an id that isn't in `fileTabs`.
- Browser aux promote: `releaseAuxTab` makes the released tab the active main tab in BrowserManager
  (`browser-manager.ts:1063-1088`). The renderer doesn't set `activeWorking` to browser (`App.tsx:4108-4112`), so if
  main is showing a file, the released tab sits hidden.
- BUG-195 (fixed): close/promote call `releaseAuxTab()` unconditionally, so a renderer reload can't leave an orphaned
  aux WebContentsView "ghost" over the UI (`App.tsx:4769-4800`).
- BUG-196 (open): reloading a browser tab pinned in the aux (`duo eval location.reload()`) may crash the app
  (`tasks.md:597-609`).
- BUG-270 (fixed): the clamp used to be re-typed in three places, and the CLI resize reached only the file aux.
- The dirty-swap dialog is a native system alert with no Save.
- Fragile focus targeting: DOM queries over every mounted editor, filtered by `offsetParent` and the aux marker
  (`App.tsx:376-388`), because BUG-046 keeps every tab's editor mounted with `display:none`.
