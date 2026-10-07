# `@` in chat's composer, and open sessions at All projects (DL-133)

Canvas: https://claude.ai/artifact/2qhPnZG6qUpLWFsXKCYSzt. Geoff chose A for both, as drawn (2026-10-06), with no canvas comments.

## Screens

- `screens/composer-at.html` (ENH-3): typing `@` in chat mode's composer. The menu is the `/` commands menu's look (chat-mode-handoff `composer`): a page or folder mark, the name in mono, its folder in `text2` at the right, the selected row on `selected`. Hint while it's open: `↑↓ choose · ⏎ or tab adds it · esc closes`. At rest the hint adds `· @ files`. Nothing matching: one `text2` row, "No file or folder in ‹project› matches “‹query›”".
- `screens/composer-at-chosen.html` (ENH-3): **A is chosen**, `@docs/checkout-flow.md` as text, sent as typed (Claude Code's own mention). B, a chip, is not. A folder ends in `/`.
- `screens/tile-open.html` (ENH-7): **A is chosen** (the middle tile). "Today" and B are not.

## Spec

- **ENH-7:** a session with a tab open in Duo reads `working` (working) or `at prompt` (idle) in place of its wait time, on tiles as in the project's session list. One that needs you keeps its wait; ready for review shows no time, as before. Unselected, it sits on `activeTint`; selected, on `selected`, and the words still say it's open.
- **ENH-3:** matches come from the project's files and folders, as the file tree lists them (hidden and skipped folders out). Name matches first, then path matches; up to 8. ↑↓ move, ⏎ or tab adds, esc closes, a space ends the `@` word. What goes in: `@` + the path relative to Claude's folder, then a space.

## Build

- ENH-3: `Chat/FileMention.swift` (the `@` word, matching, the project walk) and `ChatMentionMenu` in `Chat/ChatComposerView.swift` (F-148). `build-compare-composer.png`: TARGET `composer-at` beside the `chat-text` fixture with `chat-cwd:<scratch project>` and `chat-type:…@chec`, then `@zzq`; TARGET `composer-at-chosen` (A) beside ↓ then tab. The rows' order is DL-133's rule, not the board's (its rows are illustrative).
- ENH-7: `SessionState.waitText(_:open:)`, used by `TileSessionRow` and the session list (F-147). `build-compare-tile.png`: TARGET (A, middle) beside the overview fixture with `open-sessions:PRD v2 edits+Teardown research+Interview synth+Copy review pass 2`.
