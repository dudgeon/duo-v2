# Tab close button handoff (DL-126)

Canvas: https://claude.ai/artifact/BcUBs8KZcpEpPF3EhHt6GT. Geoff chose option A, as drawn (2026-10-06).

## Screens

- `screens/console-tabs-close.html`: console and Home tabs. Under the pointer the state glyph (or a shell's prompt mark) becomes the ×; on the × a 16 pt square; pressed; the selected tab.
- `screens/right-pane-tabs-close.html`: right-pane document and browser tabs. The × sits in the gap before the title; Project, group pages and a read-only session get none.
- `screens/alternatives-not-chosen.html`: B and C, not chosen.

## Spec

- × 7 pt across in a 10 pt box, stroke 1.5, round caps (`size.tabClose`). `consoleText2` / `text2`, or `consoleText` / `text` on the selected tab and while the pointer is on it.
- On the ×: a 16 pt square, radius 4, `consoleRule` / `selected`. Pressed: `tuiInputBorder` / `rule`. Tooltip "Close Tab".
- Nothing moves when it shows.
- It runs what ⌘W or Close Tab runs for that tab, and asks nothing ⌘W doesn't (Q-71).
- No unsaved dot. No × for keyboard focus: ⌘W, and a "Close Tab" accessibility action.

## Build

`Project/TabClose.swift` (F-124). `build-compare.png` shows the project fixture's two strips: at rest, then `hover-tab:` on an unselected and the selected console tab, on the ×, pressed, then the same for `docs/prd-v2.md`, then over Project (no ×).
