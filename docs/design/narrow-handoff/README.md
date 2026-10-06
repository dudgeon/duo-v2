# Narrow windows handoff (DB-25, DL-129)

Canvas: https://claude.ai/artifact/Cn5T6UowtPnQR2Ezihnare. On 2026-10-06 Geoff chose all four recommendations by buttons; the canvas had no comments.

## Screens

`screens/manifest.json` lists them. The **targets** are whole windows at 1280×800, compared with `WINDOW=1280x800 scripts/check-ui.sh <state>` (states of the same name):

- `narrow-project`: inside a project, 300 | 520 | 460. The right-pane button sits at the toolbar's trailing end.
- `narrow-project-hidden`: the right pane hidden. The console takes the width.
- `narrow-project-min`: the right pane dragged wide. The console stops at 480 (300 | 480 | 500).
- `narrow-overview`: All projects at 340 | 600 | 340, with six groups packed two across. `vendor-review` sits directly in Home, under ★.
- `narrow-overview-hidden`: the action column hidden. The map packs three across.
- `narrow-search`: search at 160–1120 × 92–752.

The **boards** are spec sheets:

- `narrow-surfaces`: the newer surfaces at their minimums.
- `narrow-motion`: the motion table. The canvas board is interactive.
- `narrow-toggle-options` and `narrow-map-rows`: alternatives that weren't chosen.

## Spec

- **Resize:** side panes keep the width they have; the middle takes the change. Under the middle's minimum (console 480, map 440), the right pane gives way first, down to 360, then the left, down to 240 (project) or 280 (Home). A PTY never goes below 8×1 (LR-14).
- **The right-pane button:**
  - `sidebar.right` in `text2`, after the search field, at both altitudes.
  - Tooltip `Hide Right Pane ⌥⌘0` / `Show Right Pane ⌥⌘0`.
  - ⌥⌘0, View › Toggle Right Pane, and `duo2 view right show|hide|toggle` do the same.
  - Opening a document or a browser tab while the pane is hidden shows it again.
  - It comes back at the width it had.
- **Map:** topic columns go as many across as fit at `mapColumnMin` 220 (three at most). Each goes under the shortest column so far, in map order, leftmost on a tie.
- **Search** below 1440×900: width min(960, window − 96), 92 from the top, height at most window − 140, list 420.
- **Narrow surfaces:**
  - The chat composer drops hints from the right: first `⌘[ ⌘] your messages`, then `/ commands`.
  - The browser bar's zoom % never truncates; the address gives way.
  - Tabs past the width go into » n, and the deck's bars wrap (F-121), as built.
- **Motion** (`motion.*` tokens):
  - A pane slides its width over 200 ms, ease-in-out, and the terminal is resized once, at the end.
  - Search's scrim and modal fade together, 120 ms in and 100 ms out.
  - A new tile fades in over 150 ms.
  - The altitude cross-fade takes 150 ms.
  - Reduce Motion makes all of it instant.

## Build

F-128 to F-130.

- `build-narrow-*-compare.png`: target, build and difference for each target.
- `build-right-hidden-window.png`: the window with the button and the pane hidden.
- `build-chat-480.png`: the composer at a 480 console.
- `before/`: today's build at 1280×800 before DL-129.

The remaining differences are fixture content: the document's typography, and the map's group order, which follows the Recent sort.
