# Tabs with many open (DL-225)

Canvas: https://claude.ai/artifact/6c1sHmzDmboFzMoxgagWdm ("Tabs with many open"). Geoff asked for the study on 2026-10-19 ("tabs have some weird quirks that show up when too many tabs are open, eg focused tab not always visible in tab bar; tabs showing adjacent to active tab not always the 'real' adjacent tab"). The same day, by buttons, he picked **B, a strip that scrolls** over A (a run of real neighbours with « n / » n counts, recommended) and C (shrink, then A). He picked shells titled by command or folder (Q-224), and Q-210's stand-ins and the shared rules as proposed. He approved B's boards for this handoff. Why: F-346, F-347, C-101.

## Screens

The canvas's approved boards, exported with no holes or loops (each board's `.dc.html` without the canvas runtime's script line, plus a `design-size` meta for `compare.sh`):
- `screens/right-pane.html`: the right pane with 12 documents. At the start, in the middle, the selected tab scrolled into view, the all-tabs menu open, a drag held at an edge, everything fitting, and the narrowest pane.
- `screens/console-chat-home.html`: the console with a needs-you tab out of view, its all-tabs menu, the thin light strip over chat, and Home.
- `screens/pinned-and-menus.html`: Project and a group page pinned; a session tab's menu; a shell tab's new menu.
- `screens/shell-titles.html`: shell titles. Option **A** (the middle strip: command, else folder) was picked; B (numbered) was not.

`alternatives/` holds the boards not chosen, plus the quirks as built (`today-quirks.html`), for the record. `proof/` holds strips cropped from the reproduction runs (isolated build of `6b52031`, F-346): the false neighbour, ⌃Tab before and after, the console, and Home's clipped row.

## Spec

**One strip, three places.** The console, the right pane and Home all use it, and so does the thin light strip over chat (DL-136). The scrolling part sits between the pinned tabs (right pane only) and the trailing controls.

- **Tabs** keep today's look: their widths, gaps (18 console, 16 Home and the chat strip, `gapPaneTabs` 24 right pane), fonts, the hover × and fill (DL-126, DL-134), the Keep Running pin. Titles still cap at 24 characters (`consoleTabTitleMax`). Nothing shrinks further, and nothing goes into a `» n` menu: `» n` and `MoreTabsMark` go.
- **When every tab fits**, the strip is as today: no fades and no all-tabs button, with `+` (or `+ ⌄`) after the last tab.
- **When they don't fit**, the tabs scroll sideways inside the strip. There's no scroll bar. Trackpad swipes scroll it, and a scroll wheel with ⇧ does too; a vertical wheel doesn't. Tabs never change places by scrolling; only the view moves.
  - **Fades.** At an edge with more beyond it, a 24-wide fade from the strip's ground (`console`, `ground` on the chat strip, `pane` on the right pane) to clear covers the tabs. No fade at an edge with nothing beyond.
  - **A needs-you tab out of view** puts a 6 needs-you dot (`needsYouOnConsole` on the console and Home, `needsYou` on light) in that edge's fade, 5 in from the edge and centred on the label line. Clicking it scrolls to that tab, without selecting it. Its accessibility label is "‹n› more tabs to the left, one needs you". The right pane has no states, so no dot.
  - **All tabs, `n ⌄`.** It sits after the scrolling part and before `+`, behind a hairline (`consoleRule`, or `rule` on light) the strip's height less its border. It shows the number of tabs that scroll (not Project or a group page) and a down chevron, in `consoleText2` / `text2` and the strip's font, with padding 0 10 0 12. It only shows while something is out of view. It opens a pop-up menu (as `» n` did) of every scrolling tab in strip order. Console and Home rows carry the state glyph in light colours, or the prompt mark for a shell; the selected tab is checked. Choosing a tab selects it and scrolls to it. Duo verb: `duo2 view tab` / `session open` as now (DL-71).
- **The selected tab is always in view, whole.** Whenever the selection changes (a click, ⌃Tab or ⌃⇧Tab, a choice from `n ⌄`, a close, Move Tab Left / Right, a drag, a project switch, a relaunch) and on any resize, the strip scrolls the least distance that shows the selected tab plus 32 of its next neighbour on the side it came from beyond the fade. Where there's no neighbour, it shows to the edge. The scroll uses `motionTabMove` (instant with Reduce Motion), and it never scrolls while the pointer is dragging the strip by trackpad. If the selected tab is wider than the scrolling part, it fills it with its title cut at the end.
- **Dragging a tab selects it** (DL-225). It lifts as `papercuts-copy-tabs-handoff/` draws it. Held within 32 of either end of the scrolling part, the strip scrolls that way at a steady pace (about one tab every 0.3 s) and the tab's place keeps moving. Let go anywhere along the strip. Drags stay in their strip.
- **Pinned (right pane, Q-210 2).** Project, and a group page after it, sit left of the scrolling part. They never scroll or move, and nothing can be dropped before them. Documents, browser tabs and a read-only session scroll and move among themselves.
- **Order** is the strip's order everywhere, as moved, and kept across relaunch (DL-220). ⌃Tab / ⌃⇧Tab step through it, wrapping (DL-165). Home's tabs follow an order too, and move like the console's (Q-210 7).
- **Closing a tab selects its left neighbour,** or the next one if it was first, in all three strips, as documents already do (ENH-144). Separately a plain fix, `tasks/tabs-bugfixes.md`.
- **Menus.** A session tab's menu keeps Move Tab Left / Right at its end, after Close Tab (Q-210 1). A **shell tab** gets a menu of Close Tab, a divider, Move Tab Left, Move Tab Right (`session close`, `view tab-move`). Move Tab Left dims on the first tab and Right on the last. A move scrolls to keep the tab in view. No chord (Q-210 3).
- **Shell titles (Q-224 A).** While a command runs in a shell (its foreground process group isn't the shell, as DL-127 already reads), the tab reads the command's name and arguments as typed, capped at 24 characters (`npm test`, `git log`, `tail -f`). Otherwise it reads the name of the shell's current folder (`alpha`, `~` for home). When two shells in a strip would read the same, the later ones take " 2", " 3" in strip order. The title updates as the shell changes, without moving the tab. A session's title is unchanged.
- **After a relaunch**, a console whose saved tab is gone (a shell) selects its first tab (F-347).

**Tokens to add** (`tokens.json`, then the generators): `size.tabFade` 24, `size.tabPeek` 32, `size.tabEdgeScroll` 32, `size.tabNeedsYouDot` 6.

**Accessibility.** The scrolling part is one group with "Tabs" as its label. Each tab stays a button with its selected trait. VoiceOver's scroll actions scroll the strip, and `n ⌄` reads "All tabs, ‹n›".

## Stand-ins and questions

None open on the boards. Two build questions are for the builder to answer and log: how a shell's folder is read (`OSC 7` from the shell, or the process's cwd), and the exact edge-scroll pace (to be tuned in a visible gate with Geoff's OK).

## Build

Not built. A suggested build note: `tasks/tabs-scrolling-strip.md`. It replaces `TabStripFit` (`Project/ConsoleTabStrip.swift`) and the right pane's `layout` (`Project/ProjectPanes.swift`), adds Home's strip (`AllProjects/AllProjectsPanes.swift`), and touches `Model/AppModel+TabOrder.swift` and the close and restore paths.
