# Split view in v2: options, the recommendation, the Duo Decks interface, and a pre-mortem

*Split view study, part 2 (research/split-view, 2026-10-31). Everything here is proposed [P]; nothing is built. The canvas: https://claude.ai/artifact/8j6ukv88cvTqvdSEoHnEc1 (sources in `canvas/`). Part 1 is `legacy.md`; what v2 has today, with file:line references, is `v2-today.md`. Records: F-474 to F-479, Q-362 to Q-368, C-135 to C-137, ENH-301 to ENH-303; Geoff's answers become DL-275 to DL-278.*

## The job

Geoff, 2026-10-31: split view is "the correct way to handle the side-by-side of source editing and rendered preview", and Duo Decks is waiting on it. The same mechanism should serve:
1. a deck's Markdown beside its slides (the first customer, Duo Decks' R1 to R10);
2. a Markdown file beside its rendered preview;
3. an HTML file beside its page;
4. two different documents beside each other (legacy's case, LR §4 item 11, DL-11's "side-by-side later").

## What a split has to live with in v2 (`v2-today.md` §10)

- **Width.** The right pane is 360 to about 658 at 1440 with the sidebar showing, and at most about 498 at 1280. Halved, each side is 180 to 330: under the right pane's own 360 minimum, the review margin's 420 cut (DL-237), the formatting bar's table fold at 420 (DL-266), the browser bar's 360 truncation and Duo Decks' readable-slide floor of about 360. **A split that only divides today's right pane is too narrow to use** (F-475). Every option below has to make room.
- **One viewer of each kind.** AppModel holds one editor, one HTML viewer, one deck viewer and one Word viewer, each with one web view that is re-parented on every update (`AppModel.swift:216-225`, `DocumentEditor.swift:892-920`). Two editors on screen would steal one web view from each other (F-476). A source beside a *different kind* of viewer (Markdown editor + deck viewer) fits today's singletons. Two documents of the same kind need an editor per side, which is the refactor multi-window's slice 1 also needs (Q-99, F-167; C-135).
- **Focus has no side.** `DuoPane` is left, middle and right; `webFocus` is per kind (`none|editor|html`), not per view. ⌘W, ⌘S, Format, ⌘D and voice all reach the singleton editor (F-476). Legacy never modelled the active side, and it never worked (legacy.md "What broke" 2).
- **⌘W from a page, deck or browser tab may end the console's session today.** As read (`Commands.swift:183, :252-254`), ⌘W closes a document only when the *editor* has focus; otherwise it closes the visible session. Not confirmed by a run (F-479); a split must not build on it.
- **Viewers read disk.** The HTML and deck viewers poll the file once a second. A live preview of unsaved text needs the buffer pushed to it (Duo Decks R1, R2).
- **F-208 / F-212.** A nested split must not make the layout read changing state or replace a pane's root view (C-137).
- **Nothing is drawn yet.** Search's Tab menu already has "Open in split view ⌥⌘↩" (DL-79 e), disabled and a no-op (`SearchModel.swift:148, :169`; F-478).

## Rules every option keeps (from legacy's failures)

1. **The active side is model state**, set by the same path as DL-165's active pane and shown by its rule. Every command that acts on "the document" (⌘W, ⌘S, ⌘F, ⌘D, voice, the formatting bar, the review bar, `duo2` with no path) resolves through it.
2. **One document per file, any number of views.** A source and its preview share one buffer. A file is never open in two editable views (ENH-301 for later).
3. **Web content lives in the view tree like any tab.** No overlay positioned by hand.
4. **Nothing is lost by closing or swapping a side.** Closing a side leaves the other as an ordinary tab. Duo saves as you type; no "discard?" question, and never a system alert.
5. **Make room, then fold.** Opening a split widens the right pane (below). If a side would still fall under its minimum, the split folds to one side with a toggle, and unfolds when there is room again (Duo Decks R7).
6. **Persisted and restored as left** (Duo Decks R10): the sides, the divider and whether it's folded, in the restore file (not the project, for OKF and Obsidian).
7. **Agents split only when asked** (legacy SV-12): `duo2 open` opens a tab; `duo2 split` makes a split.
8. **DuoChecks from the start**: make, swap, close, restore, fold, focus routing and ⌘W.

### Making room (all options; Q-363)

**Geoff's rule (2026-10-31, mid-study; board 8 animates it):** "below a certain screen width, opening a split view collapses the left pane (sessions/files); the user can still peek at the left pane (slides it over the chat/terminal), but because split view is for focused work, this is an acceptable tradeoff. opening a split view should also shrink the width of the chat/terminal."

1. **The console narrows to its 480 minimum** whenever a split opens (DL-129's minimum). Split view is for focused work on the document.
2. **The sidebar folds away** when the sidebar, the console's 480 and two sides of 340 don't fit: under about 1,464 pt with a 300 sidebar. That covers the 1440 design size and the 1280 minimum. On a wider window it stays. The fold uses a pane's own motion (`motionPaneToggle`, the terminal resized once at the end).
3. **Peek:** while the split folded it, ⌃⌘S or the sidebar button slides the sidebar *over* the console, with the popover shadow. The split doesn't move. Picking a session or file, Esc or a click outside closes it. (Open: whether ⌃⌘S should instead bring the sidebar back for good and fold the split, Q-363.)
4. **Closing the split gives back exactly what it took**: the console's and the sidebar's widths as you had them.

At 1440 × 900: console 480 · right pane 959, two sides of 479. At 1280 × 800: console 480 · right pane 799, two sides of 399. If the user later narrows things so a side would go under 340, the split folds instead of squeezing. This is legacy's ENH-126 ("the panes should redistribute") without its flaw: it keeps the user's own widths and gives them back.

## The options

| | A · Paired view in a tab | B · Two tab groups | **C · Split tab (recommended)** | D · Companion pane |
|---|---|---|---|---|
| Where | Inside one document tab: the viewer's bar gets Source · Both · Preview | Inside the right pane: two sides, each with its own tab strip | Inside the right pane: one tab in the strip holds two sides | A fourth pane right of the right pane |
| What can be a side | Only a file's own preview | Anything, any tabs | A file and its preview, or any two right-pane items | Anything, one item |
| Deck (source + slides) | Yes, the best fit | Yes | Yes | Yes, but the pair is split across two panes |
| Doc beside doc | No | Yes | Yes (slice 2) | Yes |
| How you make one | Both in the bar; a deck opens in Both | Drag a tab to the other side; Move to Other Side | Show Preview in Split View (bar, menu, ⌥⌘P [P]); Open in Split View (tree, tab menu, search ⌥⌘↩); drag a tab onto the pane's right half | Open in Companion (menus, search ⌥⌘↩) |
| Narrow | Folds to Source or Preview | Two strips at ~340 each: cramped; folds one group away | Folds to one side; the tab becomes a two-way toggle | The companion collapses like a pane |
| Active side | Inside the tab (no pane rule change) | The pane rule over the active group's strip | The pane rule shortens to the active side | It's a pane: DL-165 as is |
| ⌃Tab | Unchanged | Cycles the active group | The split is one tab | Unchanged per pane |
| Persistence | A mode per file | Two groups and their tabs | A pair per split tab, ratio, folded | The companion's item and width |
| Legacy's issues | Avoids most (one buffer, no second view) but leaves doc-beside-doc unserved | Reopens focus and two-strip complexity legacy deferred (its Option B) | Avoids each (pre-mortem) | Revives the "aux" model and its persistent-companion confusion; changes DL-129's three-pane rule and F-9 code |
| Cost (one builder) | ~4 days | ~12–15 days | ~5 days (slice 1, pairs) + ~5 days (slice 2, doc beside doc) | ~8–10 days |

### A · Paired view in a tab

The split is a mode of one document tab. A file that has a preview (a deck, Markdown, HTML) gets **Source · Both · Preview** at the end of its bar, exactly Duo Decks' first sketch. Cheapest, and decks' whole case, but it never serves two different documents, so LR item 11 stays open, and the control lives in each viewer's own bar, so Markdown and HTML need bars they don't have today.

### B · Two tab groups

The right pane holds up to two groups, each with its own strip, like an editor's "split right". It's the most general. It's also the most expensive: per-side strips, ⌃Tab per group, drop zones, and two strips at about 340 each that already truncate. Legacy kept this as "Option B, later" for good reason.

### C · Split tab (recommended)

**One tab, two sides.** The right pane's strip shows a split as one tab with two names joined by the split mark: `field-trial-review.md ⫼ Slides`, `interview-notes.md ⫼ synthesis.md`. Selecting it shows both sides with a 1 pt `rule` divider between them. The tab model stays one key per tab, a file stays in one place, ⌃Tab steps over the split as one tab, and the pair travels as a unit through close, drag and restore.

- **Making one.**
  - *A file beside its own preview:* **Show Preview in Split View** in View, on the tab's right-click menu, in the deck bar, and on ⌥⌘P [P] (a new chord, DL-34; Q-364). A deck opens split by default when there's room (Duo Decks' call, Q-367).
  - *Two items:* **Open in Split View** on a file in the tree, a right-click on a tab (Open in Split View ▸ open tabs), search's existing ⌥⌘↩ (DL-79 e), or by dragging a tab onto the right half of the pane, where a dashed `controlEdge` half-pane shows where it lands.
- **Sides.** The left side is the tab's original item; the right side is what was put beside it. **Swap Sides** is on the tab's menu.
- **Closing.** Each name in the split tab has its own hover × (DL-126's look): closing a side leaves the other as an ordinary tab. ⌘W closes the **active side**. Right-click › Close Split View makes them two tabs; Close Tab closes both.
- **Active side.** Clicking or typing in a side makes it active. When the right pane is the active pane, DL-165's 2 pt rule spans **only the active side**, across the top of the strip, so the rule moves with the keyboard and nothing else changes. In the split tab, the active side's name is semibold.
- **Divider.** Drag it to resize. Double-click evens it. Each side's minimum is 340 [P] (Q-366); the ratio is kept per split.
- **Folded.** Under 2 × 340, only the active side shows. The split tab's two names become a two-way toggle (the selected name with `selected` fill). Widening the pane or the window unfolds it.
- **Cost, in two slices.**
  - *Slice 1 (~5 days): pairs.* The source in the existing editor beside its preview: decks (the deck viewer fed from the buffer), Markdown (a read-only rendered view), HTML (the HTML viewer fed from the buffer, with the editor opening `.html` as text). This fits today's singletons. It needs the active side in the model, the routing table below, the fold, persistence and the verbs.
  - *Slice 2 (~5 days): doc beside doc.* Two editors (an editor per side), with the same refactor multi-window needs (C-135). After slice 2, a browser tab or an HTML page can be either side as well.

### D · Companion pane

A fourth pane, right of the right pane, holding one item: legacy's aux as its own pane. Focus falls out of DL-165 for free (it's a pane), but the companion stays while the tabs beside it change (legacy's "persistent companion"), so a deck's source and its slides can drift apart when you switch tabs. It also changes DL-129's three-pane rule, F-9's collapse code and the motion.

## The recommendation: C, built in two slices

C serves all four uses with one tab model. Slice 1 unblocks Duo Decks in about a week without the editor refactor. It keeps every rule legacy learned. A is C's slice 1 in a different place (the viewer's bar instead of the strip); choosing C over A costs about a day more and leaves room for doc-beside-doc without moving the control later.

## What acts on what (C)

| Command | In a split |
|---|---|
| ⌘W | Closes the active side; the other side becomes an ordinary tab. Never the console's session (fixes F-479 for splits; the general fix is its own task) |
| ⌘S | Saves the active side's document; on a preview side, its source |
| ⌘F | Finds in the active side (the responder chain already routes it) |
| ⌘D | Sends the active side's selection; on a deck preview, the picked shape with its slot (Duo Decks R4) |
| ⇧⌘D voice | Into the active side's editor; with a preview active, into its source (R8) |
| Formatting bar (DL-266) | Over the editor side only, while it has the keyboard; never over a preview |
| Review bar | In the editor side's own stack |
| ⌃Tab | Steps the right pane's tabs; the split is one tab |
| ⌥⌘← / → | Panes, then the split's sides as sub-panes: sidebar → console → left side → right side (Q-368) |
| `duo2 doc …` with no path | The active side's document |

## duo2 (DL-71)

`duo2 split <file> [--with <file|url|preview>]` makes a split (`--with preview` is the default for a file with a preview); `duo2 split` reports the sides, the active side, the ratio and whether it's folded; `duo2 split close [--side left|right]`; `duo2 split swap`; `duo2 split focus left|right`; `duo2 split ratio <0.2–0.8>`. Verbs that act on "the showing document" (`doc read`, `doc screenshot`, `slide …`, `status`) take `--side`. `duo2 deck …` and `deck go <n>` stay Duo Decks'. Every control above names one; `Parity.uiOnly` gets nothing new.

## The interface with Duo Decks (proposed, sent to duo-decks)

Duo Decks' proposal (requirements R1 to R10, `SourcePreview`) stands, with these changes:

- **Name:** `PreviewProvider` (a viewer that can be the other side of a source). `canPreview(file, frontmatter)`; `render(text, revision)`; `reveal(anchor, reason)`; and callbacks `anchorMap([AnchorRange])`, `activate(anchor)`, `current(anchor)`, `problems([SourceProblem])`. `AnchorRange` is a source line range → an anchor (`slide 3`, `slide 3/value`; for Markdown a heading or block; for HTML an element id).
- **Ownership:** the provider owns the anchor map (only it parses the file). Split view owns the policy: caret-follow, scroll-follow (off by default), the debounce (250 ms after typing pauses, R2), loop suppression (every event carries its origin and revision; a reveal never echoes), the panes, divider, fold, persistence and `duo2 split`. The editor owns the caret, visible lines, revealing and marking lines.
- **Events:** editor → split: `textChanged(rev)`, `caretMoved(line)`, `visibleLines(range)`, `selection`. Split → provider: `render(text, rev)`, `reveal(anchor, reason)`. Provider → split: `anchorMap`, `activate`, `current`, `problems`. Split → editor: `reveal(lines)`, `mark(problems)`.
- **Revision rule:** a provider drops a render older than its newest; split view ignores an `anchorMap` whose revision isn't the editor's current one.
- **Rendering never writes a file**, and renders from the buffer, not disk (R1). On a change on disk, the editor reconciles first (DL-77), then a normal `render` follows.
- **The preview's own bar stays the provider's**: ‹ › Slide n of N, problems, Select Shape, Export ⌄ and the export state (R6, R8). Split view draws no bar of its own on a side.
- **Answers to Duo Decks' five questions:**
  1. The shape works, with the changes above.
  2. Split view provides the split tab, sizing, fold and persistence, active-side routing, the sync policy and the verbs.
  3. Each side's minimum is 340 (Q-366; 360 if Geoff prefers slides roomier). Under it the split folds to the active side, and the tab's names toggle.
  4. Same file, two views (source + its preview) **is** slice 1. Two editable views of one file is not (ENH-301).
  5. The canvas is above.

## Pre-mortem: it's six months on and split view failed. Why?

| # | How it failed | Legacy's version | How C avoids it |
|---|---|---|---|
| 1 | The preview drew over the editor or a sheet after a reload or a modal | BUG-195, 209, 270: a second native view positioned by hand | Each side is an ordinary subview in the right pane's AppKit split; sheets cover it like any view. A DuoCheck walks the view tree for a side outside its pane |
| 2 | ⌘W, ⌘S or Send acted on the wrong side | ENH-084, `isActive` false in the aux, ⌘W always main | `activeSide` is model state; one routing table; a DuoCheck per command × side |
| 3 | The focus mark lied | ENH-084 v1–v4, three failed fixes | The mark is drawn from `activeSide`, not inferred from DOM focus; a capture per side |
| 4 | Two copies of one file disagreed | Reopening from the tree made a second editor | One document per file; Open in Split View on a file already in a split selects it |
| 5 | The split was unusably narrow | "squished" image viewer, BUG-209 at small windows | Make room, then fold at 2 × 340; never squeezes |
| 6 | The shortcut never fired | BUG-075, 1Password owns ⌘\ | No backslash; ⌥⌘P checked against macOS, 1Password, Raycast and Rectangle defaults before DL-277 |
| 7 | The width came back wrong | ENH-126 overrode the saved ratio; three clamps | One `SplitGeometry` owns ratio and clamp; restore reproduces what was saved; Duo returns only what it took |
| 8 | Moving or swapping crashed | BUG-093, async state across an await | Make, swap, close and separate are one synchronous model change |
| 9 | Live preview made typing slow | (new) | Render 250 ms after typing pauses, off the main thread; drop stale revisions; measured with check-chat-perf-style timing under the GPU lock |
| 10 | Sync looped (caret → slide → caret) | (new) | Events carry origin and revision; split view suppresses echoes |
| 11 | A layout change hung the app | F-208 class | Visibility watched inside AppKit, as `cover` is; the F-212 guard extended to the split's file |
| 12 | Agents put things in a split nobody asked for | SV-12 rule | `duo2 open` never splits; only `duo2 split` |
| 13 | The split broke in a second window | ENH-191 addressing | Splits live in per-window state from day one; verbs take `--window` when multi-window lands |
| 14 | Tests missed it | Units only | DuoChecks for make, swap, close, separate, fold, restore and routing; fixture states for captures |
| 15 | Decks shipped their own split first | Option D deferred, then built twice | The decks viewer waits for slice 1 (agreed with duo-decks); the fallback, Source · Slides in one tab, is the folded split itself |

## Decisions for Geoff

- **DL-275 (Q-362): which option.** C, split tab, in two slices (recommended) · A, paired view only · B, two tab groups · D, companion pane.
- **DL-276 (Q-363): making room.** Geoff's rule as drawn on board 8: the console narrows to 480, the sidebar folds below about 1,464 pt and peeks over the console, and everything comes back on close (recommended) · the same, but ⌃⌘S brings the sidebar back for good and the split folds · split only today's right pane and fold more often.
- **DL-277 (Q-364): the chord.** ⌥⌘P Show Preview in Split View, plus search's ⌥⌘↩ as approved (recommended) · menus, right-click and drag only.
- **DL-278 (Q-365): the same file twice.** One editable view per file, its preview as the second view (recommended) · two editable views of one buffer now.

Smaller open questions, stand-ins until answered: Q-366 (side minimum 340 or 360), Q-367 (a deck opens split by default: Duo Decks' call, recommended yes), Q-368 (⌥⌘← → stepping into sides: recommended yes). Scope: C's slice 2 brings DL-11's "side-by-side later" forward; build plan §3a needs a line when Geoff picks.
