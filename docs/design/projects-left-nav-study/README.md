# Duo: where projects live in the window — design study

Status: **study, waiting on Geoff** (Q-527 to Q-531). Nothing is built. Asked for by DL-339 (6), Q-515: a canvas round first on where projects live in the window (ENH-146, ENH-341), with ENH-347's items drawn and built with it.

The canvas is https://claude.ai/artifact/MMAaxkzezLUu8LEBGUpbpQ, with the Duo design system (its `tokens.json` installed on the canvas). `canvas/project/` holds its files as published (hand-written `.dc.html` boards and the index). Board labels and the yellow notes are the board's, not the app's; names and data are the home-evolution study's sample data. Today's window, for reference, was captured from main (`scripts/check-ui.sh project list-1440`, isolated, background).

## The problem

Two new users could not tell which project they were in or what a project is (ENH-146, 2026-10-14; F-663 and `docs/research/aram-feedback.md` §1.6, 2026-11-12). A project is a folder with a `_PROJECT.md`, and a session belongs to the nearest one at or above where it started; the app says neither. All projects has no left pane since DL-336. Inside a project the folder shows once, unlabelled, under FILES, and the sidebar's "+ New Claude Code session" doesn't say where it starts.

## Directions

- **A, recommended: a Projects pane, one level up from a project** (boards A1, A2). All projects gets its left pane back as Projects: ★ home, then every project under its topic in the map's order, each expanding to its folder and the sessions that matter now (needs you, open, today; five at most), with **+ New session** in that folder; a + on a row's hover; **+ New project** at the foot; a project open in another window shows that window's colour. Inside a project the sidebar is today's plus one row at its top, **‹ Projects**, which slides the same list in over it. ⇧⌘O opens the list with its filter focused. Keeps the approved sidebar whole; uses the width DL-336 freed (260 | 840 | 340 at 1440; 260 | 680 | 340 at 1280, F-679); Home as the list's first row is ENH-341's lightest way back.
- **B: one tree in every left pane** (board B1). The Claude app's shape: the open project is the open branch, its sidebar's sections nested under it. Closest to what the first user named; costs about 100 points of height and 28 of width in every project's sidebar and reopens DL-217's order.
- **C: no list, a switcher on the name** (board C1). The toolbar's project name becomes a popup with a filter, the projects by attention, New Project…. Smallest; meets neither user's ask for a list that stays.

## In every direction (board L)

ENH-347, drawn: the toolbar name's tooltip gives its folder and a click opens `_PROJECT.md`; the sidebar's button names its project, "+ New session in checkout-redesign", with the folder and ⌘T in its tooltip; FILES' path line is named in its tooltip; a **Projects explainer** on DL-172's component (long hover on the name, Help › Explain Projects, and the one-line version in the New project sheet that DL-147 decided).

## Boards

| Board | What it shows |
|---|---|
| `Main` (00) | The ask, what's true today, the three directions, the recommendation, the decisions |
| `L1-legible` (L) | ENH-347's items in every direction: toolbar name tooltip and explainer, New project sheet line, the button's words at 300 and 240, FILES' path tooltip |
| `K-keys-verbs` (K) | Every action's keys, menu item and `duo2` verb, per direction; what is new |
| `A1-allprojects` (A1) | Recommended: All projects with the Projects pane at 1440 |
| `A2-inside` (A2) | Inside a project: ‹ Projects, the list slid in, ⇧⌘O with a filter |
| `B1-tree` (B1) | The tree inside a project, its costs |
| `C1-switcher` (C1) | The switcher popup on the project's name |

## New marks, all [P]

- A: the Projects pane (260, drag 220 to 340), its rows (project, expanded folder line, child session rows under the thread rule, + New session row, hover +, window swatch, folder-without-project rows, Archived fold, + New project footer, Go to project filter); the ‹ Projects row with "n elsewhere"; the slide; the sidebar button back at All projects.
- B: the tree's PROJECTS section and the nested branch.
- C: the name's ⌄ popup, its head (folder, Open _PROJECT.md), filter and sections.
- Every direction: the tooltips, "+ New session in ‹project›", the Projects explainer's picture and three lines, the New project sheet's line.

## Decisions (console-ready)

Each with the canvas link, https://claude.ai/artifact/MMAaxkzezLUu8LEBGUpbpQ, and the board to open.

1. **Q-527 · Where do projects live in the window?** Boards 00, A1, A2, B1, C1. **A, a Projects pane (recommended)** · B, one tree · C, a switcher only.
2. **Q-528 · All projects' left pane: shown, with its sidebar button and ⌃⌘S back there?** Board A1. **Shown for everyone, hidden once you hide it (recommended)** · Shown for new installs only · Hidden by default, opt-in (ENH-341's way). Amends DL-336 (4); `duo2 view sidebar` works at All projects again.
3. **Q-529 · What does an expanded project show?** Board A1. **Its folder, then needs you, open and today's sessions, five at most, then + New session (recommended)** · Its tasks, then sessions · Everything its sidebar shows.
4. **Q-530 · A new shortcut, Go to Project… ⇧⌘O?** Boards A2, K. **Yes, ⇧⌘O (recommended)** · No chord: the menu item and search (⇧⌘A) only. DL-34 locks the map.
5. **Q-531 · Does the sidebar's New session button name its project?** Board L, section 3. **Yes: "+ New session in ‹project›", folder in the tooltip (recommended)** · Keep "+ New Claude Code session" and add only the tooltip (ENH-347 as written).

After the answers: export the chosen boards to `docs/design/projects-left-nav-handoff/screens/` and write the build brief; ENH-347's items (board L) can be built first, whatever Q-527 says.
