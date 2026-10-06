# Motion handoff (DL-130)

Canvas: https://claude.ai/artifact/G1bcwo5qQRZmNLfHehGbgj. Geoff approved every motion on 2026-10-06, high and medium, along with the tokens as drawn. He changed one thing: Mark Complete holds for 5 s, not 600 ms.

This handoff extends handoff §9 and DL-129 (the narrow-handoff motion board). `audit.md` is the phase A walk: every action, what was proposed and why, and what stays still.

## Screens

`screens/` holds the canvas's boards as their `.dc.html` sources. The motion is in their scripts, so open the canvas to play them. Each board has Play, Slow ×5 and Reduce Motion buttons.

| Board | Shows |
|---|---|
| `Main.dc.html` | 0 · the token table, the rules, what stays still |
| `Sheets.dc.html` | 1 · Duo's sheets and questions hang from the toolbar |
| `SessionList.dc.html` | 2 · rows move between sections, appear and leave; held while the pointer is in the list |
| `TaskComplete.dc.html` | 3 · Mark Complete: checked, struck through, grey; 5 s hold; leaves |
| `ReviewCard.dc.html` | 4 · the chat review card docks in place of the composer and leaves |
| `Folds.dc.html` | 5 · folds and the file tree |
| `DragDrop.dc.html` | 6 · drag and drop on tokens, honouring Reduce Motion |
| `Medium.dc.html` | 7 · tabs, notices, the chip, the editor highlight, the deck, project to project |

## Spec

### Tokens

Durations are in seconds, in `motion`. Easings are in `motionEase`, as `out`, `in` or `inOut`.

The rule: arriving eases out, leaving eases in, and moving between two places eases in and out.

| Token | s | Ease |
|---|---|---|
| `rowIn`, `rowOut` | 0.15, 0.15 | out, in |
| `rowMove` | 0.2 | inOut |
| `rowHold` | 5.0 | a delay |
| `fold` | 0.18 | inOut |
| `sheetIn`, `sheetOut`, `sheetSwap` | 0.2, 0.15, 0.12 | out, in, inOut |
| `cardIn`, `cardOut` | 0.2, 0.15 | out, in |
| `lift`, `landed` | 0.2, 0.4 | out |
| `tabIn`, `tabOut`, `tabMove` | 0.15, 0.12, 0.15 | out, in, inOut |
| `noticeIn`, `noticeOut` | 0.15, 0.12 | out, in |
| `chipIn`, `count` | 0.15, 0.2 | out |
| `highlightIn`, `highlightOut` | 0.2, 0.6 | out, inOut |
| `slide`, `outline` | 0.25, 0.08 | inOut, out |
| `messageIn`, `dropIn` | 0.12, 0.1 | out |

DL-129's tokens (`paneToggle`, `scrimIn`, `scrimOut`, `tileIn`, `altitude`) stay as they are and get easings too: `paneToggle` is `inOut`, the rest `out`.

### Reduce Motion

Reduce Motion makes all of Duo's own motion instant. It comes from one model flag (`NSWorkspace.accessibilityDisplayShouldReduceMotion`), and every animation is built through `DuoMotion`. The editor and deck pages use `prefers-reduced-motion`.

Mark Complete still holds for 5 s with Reduce Motion on; it then goes at once.

### Each motion

- **Sheets and questions:**
  - They hang down from under the toolbar: `translateY(-100%)` to 0, `sheetIn`, then `sheetOut` back up.
  - The content dims as today (55%) with `scrimIn` / `scrimOut`.
  - The next question in SheetCenter's queue cross-fades its content in the same sheet (`sheetSwap`).
- **Session list:**
  - Rows keep one identity across sections, so they travel (`rowMove`). The state glyph and counts change at once.
  - New rows fade in (`rowIn`). Archived rows fade out (`rowOut`) and the rest close up (`rowMove`).
  - While the pointer is in the list, changes in order wait until it leaves (Q-80). Glyphs, counts and wait times still update.
- **Folds** (Archived, Earlier, a group or task's sessions, file-tree folders, the properties block's chevron):
  - The chevron turns 90° (`fold`). Children fade in while the rows below make room.
  - A folder is listed the moment it opens (Q-79).
- **Mark Complete:**
  - At once (Q-78): the task box is checked, the title struck through, and title and status are in `text2`, with status `done`.
  - It holds for `rowHold` (5 s). ⌘Z or Mark Open during the hold keeps the row.
  - Then `rowOut`, and the rows close up.
- **Archive, unarchive, + New task** apply at once (Q-78), with `rowOut` / `rowIn`. If the next snapshot disagrees, it wins.
- **The chat review card:**
  - The dock grows from the composer's height to the card's (`cardIn`), and the composer fades out.
  - Once Claude has taken the answer (the screen changes), it shrinks back (`cardOut`).
  - The feed stays pinned to the bottom.
- **Drag and drop:**
  - F-51's look is unchanged: the source at 35% and 96%; the target at 103% with a 2 pt outline and the popover shadow; the landed fill and capsule.
  - Timing is `lift` / `landed` ease-out, with no spring. The capsule fades and doesn't scale.
  - With Reduce Motion, nothing scales.
  - A tree drop target fades in (`dropIn`).
- **Tabs:**
  - A new tab fades in (`tabIn`) and closes with `tabOut`. The others slide (`tabMove`), keyed by tab id.
  - The hover × stays instant.
- **Notices** (`NoticeBar`, the chat fallback bar): they slide down from under the tab strip and push the content (`noticeIn`). OK slides them up (`noticeOut`).
- **The needs-you chip:**
  - It fades in and out (`chipIn`) in a kept slot.
  - The count rolls (`count`, numeric text transition).
- **The editor:**
  - `.duo-added` fades in (`highlightIn`).
  - On the next user edit, highlights take a `duo-fading` class, fade out (`highlightOut`), and are then removed.
- **The deck:**
  - ‹ › and Slide n scroll by script over `slide`, ease-in-out.
  - The picker outline transitions left, top, width and height (`outline`).
- **Project to project:** the `altitude` cross-fade.
- **Chat items:** a new item fades in, in place (`messageIn`).

### Stays still

- glyphs;
- the hover × and +;
- search results and their selection;
- chat streaming and its scroll;
- the Terminal/Chat swap;
- map order;
- the peek's rows;
- the editor's task box;
- a tile growing into its project.

## Proof (Q-77)

- `DUO_MOTION_SCALE=<n>` stretches every duration n times.
- `snap:<png>` takes a frame through Duo's own capture path at that point in `--then`.
- Each motion is shown as a filmstrip at set times, with Reduce Motion on and off.
- No screencapture(1).
