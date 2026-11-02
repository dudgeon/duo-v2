# Duo: split view, slice 1 (a file beside its preview) — design handoff

**Superseded in part by DL-306 (Geoff, 2026-11-02, "Squeeze others first"):** the minimums below are now the console 400 and each side 300, and the sidebar folds only under about 1,300 (1,303 with the dividers), not 1,464. At 1440 the sidebar stays; at 1280 it folds. Every 480, 340, 470, 391 and 1,464 on this page and on its screens is the earlier rule; the rail, the peek, the unfold and the fold are unchanged.

Status: approved by Geoff, 2026-10-31 (DL-275 to DL-278). Build after 0.2.22. Duo Decks' viewer is the first customer and waits on this.

The boards were drawn on the Design canvas https://claude.ai/artifact/8j6ukv88cvTqvdSEoHnEc1 with the Duo design system; every new mark is a [P]. Geoff chose option C, a split tab, in two slices. The boards are exported here as static HTML (`screens/`, listed in `screens/manifest.json`), with PNGs at 2x in `screens/png/`.

Read the study first: `docs/design/split-view-study/`. `legacy.md` covers what legacy's Split View got wrong. Each rule below answers one of those failures (board 11 of the canvas, `options.md` §Pre-mortem). `v2-today.md` gives the file:line facts this build changes.

**Build:**
- `split-deck` is the target.
- `making-room` (DL-276) is an animation; the PNG is its first frame, so open the HTML.
- `split-themes` is the target for Dark and Classic.
- `routing-verbs` and `preview-provider` are behaviour.
- `split-docs` is **slice 2**: not this build. It shows where the model must leave room.

On each board, numbered notes are the spec. Names and documents are illustrative.

## What slice 1 is

A file that has a preview (a deck, a Markdown file, an HTML file) can show its source and its preview side by side, in **one tab** of the right pane. There is one document and one buffer: the preview renders from the unsaved text. Two different documents side by side is slice 2 (DL-278).

## The split tab (`split-deck`)

- **In the strip:** one tab, its two names joined by the split mark: an 11 × 9 outline, radius 2, stroke 1.2, divided at 3.5, in `text2`. The names are `body`. The active side's name is semibold in `text`; the other is `text2`. Example: `field-trial-review.md ⫼ Slides`. For Markdown the preview side is named `Preview`; for HTML, `Page`.
  - Each name has its own hover × (DL-126's look). Closing the preview leaves the source as an ordinary tab. Closing the source closes the whole split, because the preview has no file of its own.
  - The tab's menu (DL-108's names): Close Tab, Close Split View, Swap Sides, then the usual Move Tab Left / Right and the file verbs.
  - ⌃Tab steps over the split as one tab. Dragging moves the pair together (DL-220).
- **Sides:** the source on the left by default; Swap Sides puts it on the right. A 1 pt `rule` divider runs between them, the same as the pane dividers.
  - Drag it to resize; the ratio is clamped so neither side goes under `splitSideMin` 340 (new token; Q-366, Geoff: "340 is fine as a starting point"). Double-click evens it.
  - Saved per split.
- **The active side** is model state (`RightPane`'s `activeSide`, never inferred from DOM focus). It's set by a click or by typing in a side, by **⇧⌘[ / ⇧⌘] (Previous / Next Side of Split View, View menu; DL-277)**, and by `duo2 split focus`. ⌥⌘← → stay pane-to-pane and land on the active side; they never step between sides (Geoff, Q-368).
  - While the right pane is the active pane, DL-165's 2 pt `paneFocus` rule spans only the active side's width, at the top of the strip. Nothing moves.
- **The source side** is today's Markdown editor, with its review bar in its own stack and the DL-266 formatting bar over it while it has the keyboard.
  - A 2 pt `controlEdge` mark in the left margin (8 in, radius 1) shows the lines of the anchor the caret is in (slide 3's lines). It's drawn by the editor from the provider's anchor map.
- **The preview side** is the provider's view with the provider's own bar. For the deck, that's DeckViewer's 44 bar: under 460 it already reads `3/10`. Split view draws no bar on a side.
  - The Markdown preview is the rendered document, read only, on `pane`, in the editor's reading styles. It has no bar.
  - The HTML page is the HTML viewer, fed the buffer.
- **Folded** (`fold`, board 12, animated; Geoff on Q-366: "when a splitview auto collapses, it should have a far right bar to bring it back (use the same convention as the collapsed left pane); otherwise it will be very hard for the user to re-find that file. when the user clicks on it, the chat/terminal pane will shrink down to bring the editor/split view below the folding break point"):
  - When the right pane is narrower than 2 × 340 + 1, the active side fills the pane.
  - The other side becomes **the split's rail**: 16 wide (`sidebarRail`, the same token as the sidebar's), at the right pane's far right, on `pane`, with a 1 `rule` on its left. The split mark (11 × 9, `text2`) sits 10 from its top.
  - The whole rail is one button: `selected` under the pointer, tooltip "Show ‹name› in Split View".
  - The split tab keeps both names; the hidden one is in `controlEdge`.
  - **Clicking the rail, or the dimmed name, unfolds:** the console narrows just enough for two 340 sides (never below its 480 minimum), over `motionPaneToggle`, and the hidden side becomes active.
  - Making the room yourself also unfolds it.
  - ⇧⌘[ / ⇧⌘] while folded swap which side shows, and the rail then stands for the other one.
  - At Duo's 1280 minimum window each side is still 391, so only widening the console folds a split.
  - Verb: `duo2 split unfold`. This is also Duo Decks' fallback, so there's nothing separate to build.

## Making room (`making-room`, DL-276)

- Opening a split narrows the console to its 480 minimum.
- If the sidebar, the console's 480 and two 340 sides don't fit (under about 1,464 pt with a 300 sidebar), the sidebar **folds to a rail**. Both use `motionPaneToggle` (200 ms, the terminal resized once at the end, LR-14).
- **The rail** (Geoff, on board 8: "we need an affordance to make the collapsed left pane not fully invisible, and a mouse clickable way to peek"):
  - 16 wide (new token `sidebarRail`), on `pane`, with a 1 `rule` on its right.
  - At its top, 10 down: the sidebar glyph, 12, in `text2` (`sidebar.left`).
  - Under it, 8 below: the 6 pt `needsYou` dot, shown while any session needs you, so a folded sidebar never hides a needs-you. A stand-in; it says "needs you" to VoiceOver.
  - The whole rail is one button: `selected` fill under the pointer, tooltip "Show Sidebar ⌃⌘S". A click peeks; a second click, Esc or a click away closes the peek.
  - Action: `duo2 view sidebar peek`.
- **Peek:** a click on the rail, ⌃⌘S or the toolbar's sidebar button slides the sidebar in over the console, from the rail's right edge, at its own width, with `shadowPopover`, over `motionPaneToggle`. The split does not move.
  - Picking a session or file, Esc, a click outside or the rail closes it.
  - It never changes the split's widths. The PNG of this state is `making-room-peek.png`.
- Closing the split (or Close Split View) gives back exactly what it took: the console's width and the sidebar's shown state as they were.
- Results: at 1440 × 900, rail 16, console 480 and sides of 470; at 1280 × 800, rail 16, console 480 and sides of 391.

## Making a split

**The words** (Geoff, on the canvas: "I don't like the 'beside' language. slack and even claude have established language for 'split view'"). The layout is **Split View** in menus (Title Case, DL-108) and "split view" in prose, as Slack, the Claude desktop app and Chrome call it. Slack's item is "Open in split view"; Chrome uses "New split view with current tab" and "Add tab to new split view".
- **Open in Split View** on a file in the tree, a tab's menu (▸ the open tabs) or a search result. This is slice 2, apart from a file's own preview.
- **Show Preview in Split View** ⌥⌘P for a file with a preview.
- **Close Split View** ends the split and keeps both as tabs (for a preview, the source tab stays).
- **Swap Sides.**
- Nothing says "beside".

- **Show Preview in Split View** (View menu, the tab's menu, ⌥⌘P: DL-277, joining DL-34's map) toggles the showing file's preview. Before building it, check ⌥⌘P against 1Password, Raycast, Rectangle and macOS defaults, and record the result as a finding.
- **A deck opens split** when there's room, and folded on the source when there isn't (Q-367, duo-decks).
- `duo2 split <file>`.
- Search's ⌥⌘↩ "Open in split view" (DL-79 e) waits for slice 2. In slice 1 it stays dimmed, or it does Show Preview in Split View when the result has a preview. The builder should log a stand-in and a question.

## What acts on what (`routing-verbs`)

| Command | In a split |
|---|---|
| ⌘W | Closes the active side. The preview side closes the preview; the source side closes the split. **Never** the console's session (F-479). |
| ⌘S | Saves the document (one buffer, either side) |
| ⌘F | Finds in the active side |
| ⌘D | Sends the active side's selection; on a deck preview, the picked shape with its slot |
| ⇧⌘D | Dictation into the source, whichever side is active |
| Formatting bar | Over the source only, while it has the keyboard |
| `duo2 doc read`, `doc screenshot`, `slide …`, `status` | Take `--side left|right`; with none, the active side |

**Verbs (DL-71):**
- `duo2 split <file>` makes a split.
- `duo2 split` reports the sides, active side, ratio, folded, and whether the split folded the sidebar.
- `duo2 split close [--side left|right]`, `split focus left|right`, `split swap`, `split ratio <0.2–0.8>`.
- `split --with` and `split separate` are slice 2.

Every control names one. Regenerate `docs/cli/duo2.md`.

## The PreviewProvider interface (`preview-provider`, agreed with duo-decks)

- **The provider** (deck viewer, Markdown preview, HTML viewer) implements:
  - `canPreview(file, frontmatter)`;
  - `render(text, rev)`;
  - `reveal(anchor, reason)`;
  - and it emits `anchorMap(rev, [AnchorRange])`, `activate(anchor)`, `current(anchor)`, `problems(rev, [SourceProblem])`, `comments(rev, [CommentAnchor])`.
  - `AnchorRange` maps source lines to an anchor: `slide 3`, `slide 3/value`, a Markdown heading or block, or an HTML element id.
- **Split view** owns the policy:
  - caret-follow on, scroll-follow off by default;
  - render 250 ms after typing pauses;
  - loop suppression (origin + revision on every event; a reveal never echoes);
  - and the panes, divider, fold, room, persistence and verbs.
- **The editor** owns the caret, visible lines, revealing and marking lines, DL-77's reconcile, the review margin and Add Comment.
- **Revisions:** a provider drops a render older than its newest. Split view ignores maps, problems and comments whose revision isn't the editor's current one.
- **On a change on disk:** the editor reconciles first, then one normal render.
- **Rendering never writes a file.**
- **Comments on a preview** (Duo Decks R11, R12; Geoff's ask, 2026-10-31):
  - **R11:** `openThread(anchor)` from a preview pin opens the thread in the source's review margin. Folded to the preview, it opens as DL-237's narrow popover.
  - **R12:** `addComment(anchor)` runs the editor's Add Comment (⌥⌘M) on the anchor's lines without taking focus from the preview.
  - Split view only routes these two requests. The pins are the provider's.

## Persistence (Duo Decks R10)

- Each split tab is saved in the restore file (`RestoreState`, new optional fields, validated on restore as `rightTab` is): source, preview kind, ratio, active side, folded, and whether the split folded the sidebar.
- Nothing goes in the project folder (OKF/Obsidian).
- A file opened in split reopens in split, with the divider where it was left.

## Rules the build must keep (from legacy, `legacy.md`)

1. The active side is model state; one routing table; a DuoCheck per command × side.
2. Sides are ordinary subviews inside the right pane's own AppKit split (no overlay positioned by hand); visibility is watched inside AppKit, as `cover` is (F-208/F-212, C-137).
3. One document per file. Slice 1 uses today's single editor beside a different viewer, so there's no editor refactor (C-135 is slice 2's).
4. Make, swap, close and fold are one synchronous model change.
5. One `SplitGeometry` owns the ratio and the clamp; restore reproduces what was saved.
6. The preview renders from the buffer off the main thread. Time it under the GPU lock (`--exclusive`) before merge (C-136).
7. DuoChecks: make, close each side, swap, fold and unfold, restore, routing, ⌘W, making room and giving back. Fixture states for `split-deck` and the fold, compared with these screens.
8. Never a system alert.

## Tokens (new, [P])

`splitSideMin` 340; `sidebarRail` 16. The split mark's size (11 × 9). The source-lines mark: 2 wide, `controlEdge`, 8 in. Everything else reuses existing tokens: `rule`, `paneFocus`, `selected`, `shadowPopover`, `motionPaneToggle`.

## Open

Nothing in slice 1's design is open: Q-366 and Q-368 are answered (DL-275, DL-277). **Slice 2 (DL-278) is built alongside slice 1**: two documents both editable, with an editor per side (C-135, shared with multi-window). Slice 1 must leave room for it: `activeSide` and the routing table take any viewer on either side, not only "source" and "preview".
