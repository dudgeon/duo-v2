# Pane focus and tab cycling handoff (DL-165, provisional)

Canvas: https://claude.ai/artifact/QgL8pHUtYL8KqK2mUmqiEb. Geoff asked for a design loop with options and a build of the recommendation, to confirm later on a desktop (2026-10-09). **Every mark is [P] until he does.** Alternatives: Q-165 (the look), Q-166 (the chord and ⌃Tab's edges).

## Screens

Each is a build-handoff target, unchanged, plus the rule. Compare with `compare.sh pane-focus-handoff/<screen> <png> --content-only`.

- `screens/pane-console.html`: inside a project, the terminal has the keyboard (the default on opening a project).
- `screens/pane-right.html`: the document has the keyboard.
- `screens/pane-left.html`: the session list is active.
- `screens/pane-home.html`: All projects, Home's terminal has the keyboard (the default there).

The canvas also draws the four looks (A top rule, B outline, C dim the others, D focus glow) in light and dark, the chord comparison, and the behaviour and menus board.

## Spec [P]

- **The rule:** 2 pt (`border.paneFocusRule`), full pane width, over the top 2 pt of the pane's tab strip or header, so nothing moves. `consoleText` on the dark console (a project's console, Home at All projects), `text` on a light pane (and on a console in chat mode, which is light). Not the accent. Always shown, also while Duo isn't the front app. Takes no clicks.
- **Which pane is active:** the one that holds the keyboard. A click anywhere in a pane makes it active; so does a pane chord, and ⌃Tab keeps it. A project opens with the console active; All projects with Home. A hidden pane is never active.
- **⌥⌘→ / ⌥⌘← (Go › Next Pane / Previous Pane):** left → middle → right, wrapping; hidden panes are skipped; while the task board covers the list and console it is one pane (the middle). The keyboard goes into the pane: the terminal or chat composer, the editor or page; the session list, map and action column have no keyboard path yet (ENH-58). On the board, the chords move a selected card a lane while a card is selected (Q-143).
- **⌃Tab / ⌃⇧Tab (Window › Show Next Tab / Show Previous Tab):** next and previous tab in the active pane, in the order drawn, wrapping. Console: sessions, then shells (tabs in the » menu count). Right pane: Project, the selected group, documents and browser tabs in the order opened, a read-only session. All projects: Home's sessions, then its shells. A pane without tabs: nothing. The keyboard follows into the tab. Duo takes both keys in terminals too (F-256, C-76). Sheets, search, the peek and the idle list keep their own keys.
- **duo2:** `view pane next|previous|left|middle|right`, `view tab next|previous`; `duo2 status` names the active pane.

## Tokens

`tokens-additions.json`: `border.paneFocusRule` = 2 (added to `build-handoff/tokens.json`).
