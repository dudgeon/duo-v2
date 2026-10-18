# Paper cuts: Copy on code blocks, reordering tabs (DL-220)

Canvas: https://claude.ai/artifact/5DMeZMh58Lp7TdSif6VFza ("Paper cuts: code copy and tab order"). Geoff approved both designs on 2026-10-17 (director console: "approve -- build it"). Background: `docs/research/legacy-papercuts-audit.md`, legacy ENH-005 and ENH-042.

## Screens

The canvas's six boards, exported with no holes or loops to expand (each board's `.dc.html` without the canvas runtime's script line, plus a `design-size` meta for `compare.sh`):

- `screens/code-resting.html`: a code block in the editor at rest; its language (`bash`) top right.
- `screens/code-hover.html`: the pointer on the block: Copy (an icon and the word) after the language.
- `screens/code-copied.html`: just clicked: a check and "Copied".
- `screens/tabs-drag.html`: the right pane while `release-notes.md` is dragged: its place left empty, a lifted copy under the pointer.
- `screens/tabs-menu.html`: a document tab's right-click menu with Move Tab Left and Move Tab Right.
- `screens/console-drag.html`: the console while a session tab is dragged.

**Rendering note.** The boards' code box is `white-space: pre`, so Chrome draws the markup's line breaks and indentation as blank lines in the box and as padding inside the Copy button. The canvas doesn't; compare with whitespace between tags removed (`>\s+<` → `><`), as `proof/` does. The intended button is the tight one: 8, the 12 icon, 4, the word, 8.

## Spec

**Copy on code blocks (ENH-005).**
- At rest a fenced block shows its language at the top right, 10 in and 6 down, `text2` 11/16 (as before, S3-5). No button.
- With the pointer anywhere on the block, its head moves to 6 in and 5 down and shows, after the language (8 apart), a button: 22 high, radius 6, 1 `controlEdge` border on `pane`, padding 0 8, a 12 copy icon in `text2` (stroke 1.2), 4, "Copy" in `text` 12/16. Accessibility label "Copy code".
- Clicking copies the block's code without its fences and the button reads a check (stroke 1.6, `text`) and "Copied" for 1.5 s, even if the pointer leaves; then it goes back to rest. The caret doesn't move and the document doesn't change.
- A block without a language shows the button alone. With the caret on the opening fence (the fence shows raw) the language hides; Copy still shows under the pointer.

**Reordering tabs (ENH-042).**
- **Drag**, in the console and the right pane: the tab's place stays empty, its width kept, while a lifted copy follows the pointer: the tab's own glyph and name on its strip's ground (`pane`, or `console`), a hairline (`rule`, or `consoleRule`), radius 5, 24 high (`size.tabHover`), padding 0 8 (`size.tabDrag`), the popover shadow (on the console `shadow.consoleLift`, black at 50%). When the pointer passes a neighbour's middle the empty place moves there and the neighbours slide (`motionTabMove`). Let go, the tab is in its place.
- **Menu**, a right-pane document tab (`tabs-menu`): Close Tab, Close Other Tabs, then Move Tab Left and Move Tab Right between dividers, then the file verbs as before (the board shortens them to Reveal in Files and Copy Path). Move Tab Left is dimmed on the first document, Right on the last.
- The right pane's Project tab, a group page and a read-only session stay where they are; documents and browser tabs move among themselves (Q-210).
- `duo2 view tab-move left|right|<n> [tab] [--pane middle|right]` does the menu items and the drag (DL-71).
- The order is kept: the right pane's in the open documents, the console's in `consoleTabOrder`, both in the restore file (DL-107, LR-58).

## Stand-ins (Q-210)

Not drawn, so built as stand-ins: the console's menu items (a session tab's menu gets Move Tab Left / Right at its end; shell tabs have no menu, so they move by drag and `duo2`); the right pane's fixed tabs; no keyboard chord; a drag stays in its strip (no dragging across panes or into another project); the thin light strip over chat lifts the tab on `pane` with `rule`; Home's tabs don't move; chat's code blocks get no Copy.

## Build

F-332 (Copy), F-333 (reordering). Proof in `proof/`: `code-compare.png` (each board's code box beside the built editor in Chromium and WebKit, at rest, under the pointer and just copied), `tabs-compare.png` (the tabs-drag and console-drag boards beside the app's captures: held, and let go).
