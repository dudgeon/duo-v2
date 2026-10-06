# Motion audit (phase A, 2026-10-06)

Geoff asked which user actions would benefit from animation. This audit walks each action and proposes motion. Every proposal is [P] until DL-130.

It extends handoff §9 and DL-129, and doesn't redo DL-129's items: pane hide and show, search's scrim, a new map tile, the altitude cross-fade.

Duo's rule still holds: "state changes are noticeable but never animated for their own sake". Motion here has one of three jobs:
- **where** something came from or went;
- **cause and effect**, so the click visibly did something;
- **continuity**, so the eye doesn't lose its place.

Nothing animates a state glyph, a terminal's text, or a list the user is reading or typing into.

## How Duo is built, and what that means for motion

These facts come from a code survey of `claude/motion` at 271cf73.

1. **Every pane has its own `NSHostingView`** (`PaneSplit`).
   - A `withAnimation` or `.animation(value:)` in `RootView` never reaches inside a pane.
   - Each animation is declared in the pane's own view, as `.animation(anim, value: <model value>)`. That needs no `@State`: the value is read from the `@Observable` model. This fits ADR-0001.
2. **Most visible changes arrive on the 2 s live snapshot**, not in the click's own transaction:
   - archive and unarchive;
   - a new session or task;
   - Mark Complete;
   - a state change;
   - a folder's children.

   So animations have to key on what changed (for example, the ids in each section) and not on the click.
   - The value can't be the whole row, because wait times like `4m` change every snapshot.
   - Several actions also lag the click by up to 2 s. Applying them **optimistically** fixes more than motion would: show the change at once, then let the snapshot confirm it. See Q-78.
3. **Only `RootView` reads Reduce Motion.**
   - The map's drag springs and the chat scroll ignore it, and web content has no `prefers-reduced-motion`.
   - Proposal: `NSWorkspace.accessibilityDisplayShouldReduceMotion` becomes one model flag, and every animation is built through `DuoMotion.animation(_:)`, which returns `nil` when the flag is on. In the editor and deck pages, CSS uses `@media (prefers-reduced-motion: reduce)`, which WebKit takes from the system.
4. **SwiftTerm.**
   - Nothing animates a terminal's content, and nothing scales or fades over it. Scaling would blur the text, and the terminal is an AppKit view that is re-parented, not redrawn.
   - A pane holding a terminal changes size once, at the end (DL-129, LR-14).
5. **Web views** (CodeMirror, the deck) animate only with CSS inside the page.
   - The editor's CSS lives in `duo-editor.js`'s theme, so a change means rebuilding `Vendor/codemirror/build.sh`.
   - Scripted captures run off screen, where WebKit runs no `requestAnimationFrame` (F-102). CSS transitions still run, but they are proved in a browser page, not in a window capture.
6. **Captures today take one frame**, at least 1.5 s after the last action, and `cacheDisplay` draws model values, not frames in flight.
   - Proving the motion needs two harness changes:
     - `DUO_MOTION_SCALE=<n>`, which stretches every `DuoMotion` duration n times;
     - a `snap:<png>` action that captures at that moment, so `--then open:x,snap:a.png,wait:0.1,snap:b.png` gives a filmstrip.
   - Whether `cacheDisplay` shows mid-flight values for SwiftUI's own animations is checked first (Q-77). If it doesn't, the fallback is `screencapture -l <window>` under `DUO_SCREENCAPTURE=1`, which needs the one-time Screen Recording grant (F-54).

## The actions

**Priority:**
- **H**: helps understanding.
- **M**: helps continuity or polish.
- **L**: polish only.
- **No**: recommend no motion.

**Cost:**
- **S**: under half a day.
- **M**: about a day.
- **L**: two or more days.

All costs include frame proof.

**Reduce Motion:** "instant" means the change still happens, with no motion (DL-129).

### Infrastructure (needed by everything below)

| Item | Proposal | Cost |
|---|---|---|
| One Reduce Motion flag and `DuoMotion` helpers | The model flag above; `DuoMotion.animation(.rowIn)` and the like, built from the tokens; the drag springs moved onto it | S |
| Proof harness | `DUO_MOTION_SCALE`, `snap:<png>`, and a `motion` check that runs each motion at scale 10 with Reduce Motion on and off | M |

### 1. Tabs (console strip, right pane, Home)

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| A tab opens (⌘T, a document, a session needing you) | The new tab fades in, `tabIn` 150 ms ease-out. Tabs to its right slide over, `tabMove` 150 ms ease-in-out. | Instant | M | M (the strip's own layout and `» n` overflow can re-shorten every title, so the slide is keyed on tab ids only) |
| A tab closes | It fades out, `tabOut` 120 ms; the rest close the gap, `tabMove`. | Instant | M | with the above |
| Reorder | Not built: tabs have no drag reorder. | — | — | — |
| Hover × (DL-126) | **None.** It's a pointer affordance, so it must be there the moment the pointer is. The tab-close handoff says "nothing moves when it shows". | — | No | — |

### 2. The session list (project sidebar)

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| A session moves between sections (Needs you → Open → Today) | **Rows move to their new places**, `rowMove` 200 ms ease-in-out. For that, a row needs one identity across sections: one flat `ForEach`, with section labels as rows. The state glyph swaps in place. **Held while the pointer is in the list**, as the map holds its order (`mapSettled`), so a row never moves under a click. | Instant | **H** | M |
| A new session appears (+ New session, ⌘T, Claude started one) | The row fades in, `rowIn` 150 ms; rows below slide down with `rowMove`. | Instant | **H** | S (once rows move) |
| Archive or unarchive | The row fades out, `rowOut` 150 ms, and the gap closes. The Archived count ticks. If the fold is open, the row fades in there. | Instant | **H** | S, plus optimistic apply (Q-78) |
| The Archived and Earlier folds, group rows | The chevron turns 90°, `fold` 180 ms ease-in-out. Children fade in as the rows below slide down. Closing is the reverse. | Chevron flips, rows show at once | **H** | S |

### 3. Tasks

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| + New task | The row fades in, `rowIn`, and the note opens in the editor. | Instant | M | S |
| Mark Complete (menu) | The row shows `done` at once, holds for `rowHold` 600 ms, then leaves, `rowOut`. Without the hold, the row just vanishes and the user can't tell whether it worked. | Shows `done`, then leaves at once after the hold | **H** | S |
| Archive a task | As archiving a session. | Instant | M | S |
| Hover + (DL-112) | **None**, for the same reason as the hover ×. | — | No | — |
| The task box in the editor | **None.** The checkbox is redrawn on every toggle, so CSS can't animate it without a rework, and the check is immediate anyway. | — | No | — |

### 4. Attention

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| The needs-you dot (any glyph) | **None.** "Never animate a glyph" stands. | — | No | — |
| The "N need you" chip appears or goes | It fades, `chipIn` 150 ms. The breadcrumb beside it doesn't jump, because its slot is kept. | Instant | M | S |
| Its count changes | The digits roll, `count` 200 ms (`.contentTransition(.numericText())`). This shows the count changed and in which direction. | Instant | L | S |
| A session newly needs you, on screen | **Not recommended:** no pulse and no flash. The chip, the Dock badge and the notification already say it. A flash is the kind of motion "for its own sake" the brief rules out, and with six sessions it would never stop. | — | No | — |

### 5. Peek, sheets, questions

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Peek opens or closes | The system popover's own animation (§9). Rows changing under it don't animate. | System | — | — |
| A Duo sheet or question appears | **It hangs down from the toolbar the way a system sheet does**, `sheetIn` 200 ms ease-out, while the window dims, `scrimIn` 120 ms. Today it pops in at once. These sheets are drawn by Duo (`SheetOverlay`), not the system, so §9's "system animation" never applied. | Fades only, at once | **H** | S |
| It's answered | It slides back up, `sheetOut` 150 ms ease-in, and the dim lifts. | Instant | **H** | with the above |
| The next queued question | The text cross-fades inside the same sheet, `sheetSwap` 120 ms. It doesn't drop again. | Instant | M | S |

### 6. Notices (download, docx summary and progress, conversion failure, editor conflict, the chat fallback bar)

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| A notice arrives | It slides down from under the tab strip, `noticeIn` 150 ms ease-out, and the content below moves down with it. | Instant | M | S (one `NoticeBar` serves them all) |
| It's dismissed (OK) | It slides up, `noticeOut` 120 ms ease-in. | Instant | M | with the above |
| The update notice | This is a question sheet (SheetCenter), so it follows section 5. | — | — | — |

### 7. Chat mode

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Switching Terminal ↔ Chat | **None, an instant swap.** The terminal is a re-parented AppKit view, so a cross-fade would composite live terminal text. The toggle's own selection moves. | — | No | — |
| Messages streaming in | **None per word.** The text appends as it arrives, with the caret (chat-mode handoff). The view stays pinned to the bottom and scrolling stays instant: smooth scroll on every flush (0.15 s) judders. | — | No | — |
| A new item (your prompt, a tool card, Claude's reply) | It fades in, `messageIn` 120 ms, in place. It doesn't rise. | Instant | L | S |
| A review card docks (a permission, AskUserQuestion) | **It rises in place of the composer**, `cardIn` 200 ms ease-out, from the composer's top edge. This shows the question took the place where you type. | Instant | **H** | S |
| …and leaves after an answer | It sinks, `cardOut` 150 ms ease-in, and the composer fades back. The leave waits on the screen-scrape, so the motion confirms Claude took the answer. | Instant | **H** | with the above |
| The fallback bar | As a notice (section 6). | Instant | M | with section 6 |

### 8. The editor

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Claude's edit arrives | The `selected` highlight fades in, `highlightIn` 200 ms, so the eye finds it. | Instant | M | S (CSS keyframe on `.duo-added`) |
| The highlight clears on your next edit (DL-5) | It fades out, `highlightOut` 600 ms, so the text doesn't seem to blink. | Instant | M | M (a two-step clear: a `duo-fading` class, then the marks removed after the fade) |
| The properties block folds | The chevron turns, `fold`. The block swaps at once: CodeMirror replaces it as one block widget, so animating its height would mean measuring DOM against CM's layout. | Instant | L | S (chevron only) |

### 9. Drag and drop (DL-117, F-51)

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Map: the source sinks, the target rises, the landed pulse | **Already built**, as springs (0.28 s). Proposal: keep the look, but take timings from tokens (`lift` 200 ms ease-out, `landed` 400 ms) and honour Reduce Motion, which they ignore today. | Instant (a fix) | **H** | S |
| File tree: a folder lights up under a drag | The drop highlight fades in, `dropIn` 100 ms. | Instant | L | S |
| Onto a terminal or the right pane | No feedback exists to animate. Adding feedback would be design work, out of scope (ENH). | — | — | — |

### 10. Search

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Opening and closing | Done (DL-129). | — | — | — |
| Results while typing | **None.** The list is replaced on every keystroke and again when the index answers. Motion there would only slow reading. | — | No | — |
| Selection moving (↑ ↓) | **None.** Keyboard selection must be immediate. | — | No | — |

### 11. The PowerPoint viewer

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| ‹ › or Slide n | A smooth scroll to the slide, `slide` 250 ms ease-in-out (script-driven, since CSS `smooth` has no duration). Scrolling with the trackpad is unchanged. | Instant jump (today's) | M | S |
| The picker outline moving between shapes | It glides, `outline` 80 ms ease-out, on left/top/width/height. That's fast enough not to lag the pointer. | Instant | L | S |

### 12. The file tree

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| A folder opens or closes | As the folds (section 2): the chevron turns and the children fade in as the rows below slide. **But** in live mode the children arrive on the next snapshot, up to 2 s after the chevron turns. The fix is to list that folder at once (as `toggleFolder` does), not to animate the wait. | Instant | **H** | S, plus the immediate listing (Q-79) |

### 13. The map and jumping into a project

| Action | Motion | Reduce Motion | Pri | Cost |
|---|---|---|---|---|
| Zoom in and out | Done (DL-129, the 150 ms cross-fade). | — | — | — |
| Where it went (the tile grows into the project) | **Not recommended now.** Both altitudes are AppKit-backed `PaneSplit`s with terminals. Scaling them blurs terminal text, and matched geometry can't cross hosting views. A **direction hint** would be cheap: the incoming altitude scales 0.98 → 1 on zoom in and 1.02 → 1 on zoom out, inside the 150 ms cross-fade. It needs a check that SwiftTerm stays sharp. | Cross-fade only (none) | L | M (risk: terminal text) |
| Project A → project B (peek jump, breadcrumb) | The same cross-fade, `altitude`. Today the content swaps without one. | Instant | M | S |

## What's recommended for the first build (the high-priority items)

1. Reduce Motion everywhere, plus the proof harness (infrastructure).
2. Sheets and questions hang from the toolbar (5).
3. The session list: rows move, appear and leave; the folds open (2, and 12's folds).
4. Mark Complete holds, then leaves (3).
5. The chat review card docks and leaves (7).
6. Drag and drop on tokens, honouring Reduce Motion (9).

Medium, if wanted: tabs (1), notices (6), the chip (4), the editor highlight (8), slide change (11), project A → B (13).

Low or none: everything marked L or No above.

Rough total: about 4 days for the high items with proof, and 3 to 4 more for the medium ones.

## Tokens proposed (seconds, extending DL-129's `motion`)

| Token | Value | Easing | Used by |
|---|---|---|---|
| *DL-129:* `paneToggle` | 0.2 | ease-in-out | panes |
| *DL-129:* `scrimIn` / `scrimOut` | 0.12 / 0.1 | ease-out | search, and now sheets |
| *DL-129:* `tileIn` | 0.15 | ease-out | map |
| *DL-129:* `altitude` | 0.15 | ease-out | zoom, project → project |
| `rowIn` / `rowOut` | 0.15 / 0.15 | ease-out / ease-in | session, task rows |
| `rowMove` | 0.2 | ease-in-out | rows changing section, gaps closing |
| `rowHold` | 0.6 | — (a delay) | Mark Complete |
| `fold` | 0.18 | ease-in-out | chevrons, folds, the file tree |
| `tabIn` / `tabOut` / `tabMove` | 0.15 / 0.12 / 0.15 | out / in / in-out | tab strips |
| `sheetIn` / `sheetOut` / `sheetSwap` | 0.2 / 0.15 / 0.12 | out / in / in-out | Duo sheets and questions |
| `noticeIn` / `noticeOut` | 0.15 / 0.12 | out / in | notice bars |
| `cardIn` / `cardOut` | 0.2 / 0.15 | out / in | chat review card |
| `messageIn` | 0.12 | ease-out | chat items |
| `chipIn` / `count` | 0.15 / 0.2 | ease-out | needs-you chip |
| `highlightIn` / `highlightOut` | 0.2 / 0.6 | out / in-out | editor |
| `lift` / `landed` | 0.2 / 0.4 | ease-out | drag and drop |
| `dropIn` | 0.1 | ease-out | tree drop target |
| `slide` / `outline` | 0.25 / 0.08 | in-out / out | deck |

**Easing rule (new):** things arriving ease out, things leaving ease in, and things moving between two places ease in and out. In the tokens this is a `motionEase` map from each token to `out`, `in` or `inOut`. Every token is instant under Reduce Motion.

## Questions raised

- **Q-77:** can the harness capture mid-flight SwiftUI frames with `cacheDisplay`, or does motion proof need `screencapture` and the Screen Recording grant?
- **Q-78:** should archive, unarchive, Mark Complete and new task apply optimistically, so the change and its motion follow the click and not the next 2 s snapshot?
- **Q-79:** should opening a folder list its children at once, instead of on the next snapshot?
- **Q-80:** should the session list hold its order while the pointer is in it, as the map does?
