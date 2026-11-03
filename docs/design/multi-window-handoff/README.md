# Multi-window slice 1: two windows, each with its project and its colour

Status: **target** for multi-window slice 1 (DL-311), exported 2026-11-02 from the studies canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1 as Geoff decided it: DL-141, DL-308, DL-311, DL-312, DL-313. Built on `build/multi-window-slice1` (F-552).

The study is `../multi-window-studies/` (its README lists every board and decision). This handoff keeps only what slice 1 builds. Pinning (boards 2, 3), a session or document in two windows (6, 7), needs-you across windows (8) and the Window menu's marks (9 A) are later slices.

## Screens

Each is a picture written in HTML, rendered by `canvas/make.sh` from the boards in `canvas/` (a copy of the canvas as of DL-313). Build to what they draw; don't port the markup. `screens/png/` has each at 2×.

| Screen | Board | What slice 1 takes from it |
|---|---|---|
| `board-1-new-window.html` | 1 · How a new window opens | **Option A only.** File › New Window ⌥⌘N, at the top of the File menu, opens a window at All projects. Project › Open in New Window (and the same item on a map tile's and a sidebar project row's right-click menu, as the caption says) opens that project in a new window. No pin (slice 3): the caption's "pinned to it" is dropped by DL-311. |
| `board-4a-prime-colours.html` | 4a′ · Twelve window colours, direction C | **The palette** (DL-313): six hues × a light and a deep step, light and dark appearance. Which surfaces take the colour, and the order new windows take them in. Values: `../build-handoff/tokens.json` `windowColour` (from `../multi-window-studies/palette/palette.json`). |
| `board-4b-new-colour.html` | 4b · A new window's colour, and changing it | **Option A.** The first window stays None; each new window takes the first colour in DL-313's order that no open window has. The swatch after the project's name, its popover (colours and "Colour new windows automatically"), and Window › Window Colour ▸ with a check on the window's own. The board's four colour names (Sky, Sage, Lilac, Sand) are superseded by 4a′'s twelve: see Q-444. |
| `board-4c-classic.html` | 4c · Window colours and Classic | **Option A.** Classic turns window colours off: every window draws Classic, the swatch leaves the toolbar, Window › Window Colour is dimmed with the line, and Settings › General › Appearance shows the line under the popup. Each window gets its colour back when Classic is turned off. |
| `board-9-window-menu.html` | 9 · The Window menu | **Option C for slice 1** (DL-311: "the system Window menu and ⌘\`"): the system's items, with each Duo window listed by its title. A's swatches and needs-you marks are slice 2. Window Colour ▸ (board 4b) is added above the window list. |
| `board-10-home.html` | 10 · What happens to Home | **Option B** (DL-311, Q-431): every window has All projects. Home's pane is live in one window; the others draw the dark pane with "Home is showing in window 1" and a Show Here button, which moves Home's terminal to this window. A stand-in until Q-98 D10 adds chat there (Q-447). |
| `mini-window-coloured.html` | The mini window, twelve colours (component) | Where a colour goes, Blue in light: the toolbar ground, the sidebar, the tab strips and right pane, chat's ground and tool output. |

## What a window colour changes [G] DL-313

A window colour overrides four surfaces, in that window only, and nothing else:

| Token it overrides | Where | Light | Dark |
|---|---|---|---|
| `ground` | The toolbar | The colour at real chroma (L 0.86 light step, 0.72 deep) | L 0.50 / 0.36 |
| `pane` | The sidebar, the tab strips, the right pane's ground, the Home and All projects panes | A pale tint, L 0.965 | L 0.235 |
| `chatGround` | Chat's ground | L 0.945 | L 0.18 |
| `toolOutputFill` | Tool output in chat | L 0.975 | L 0.215 |

- **Never changes:** the console (terminals), text, rules, the selected row, cards, fields and buttons, the document's page (editor, HTML, decks), menus and popovers, and the needs-you orange.
- **On a coloured toolbar, `text2` draws as `text`:** the breadcrumb, the swatch's chevron, the toolbar's own labels. The search field keeps its own white field and its `text2` placeholder.
- **The needs-you chip keeps a solid `pane` fill (the plain one, white or Ink) on a coloured toolbar,** in light and dark.
- **The swatch** is an 8 pt circle with a 1 pt `controlEdge` ring, filled with the colour's `swatch` (None: plain `pane`), then a 5 × 4 chevron in the crumb colour, 2 apart, 1 × 3 padding, radius 4; after the project's name in the toolbar.

## The order and the rule [G] DL-312, DL-313

Blue, Ochre, Purple, Green, Coral, Teal, then Deep blue, Deep ochre, Deep purple, Deep green, Deep coral, Deep teal. A new window takes the first that no open window has. With all twelve taken, it takes the one the fewest open windows have, first in the order. The first window opens None. The switch "Colour new windows automatically" (on by default) turns this off: new windows open None. A window keeps its colour until it closes (restore is slice 2).

## Titles, menus and `duo2` [G] DL-311

- A window's title is its project's name, or "Duo" at All projects (and in Home). macOS lists the windows by title in the Window menu and moves between them with ⌘\`. Duo draws nothing for this.
- A project lives in one window (DL-308): opening it anywhere else (a tile, the sidebar, search, the peek's jump, a notification, `duo2 open`, `duo2 session open`, Open in New Window) brings that window forward instead.
- Close Window (⇧⌘W) closes a second window. Its projects' tabs and sessions stay. The last window hides as today; Duo doesn't quit.
- Every action has a verb (DL-71): `duo2 window list | new [<project>] | focus <n|project> | close [<n|project>] | colour <name|none|auto on|off>`. The on-screen verbs take `--window <n|project>`. With no `--window`, a verb acts on the window that shows the caller's session, else the primary window (the oldest open), never the key window (Q-430).

## Stand-ins (not drawn; each has a Q row)

| What | Stand-in as built | Q |
|---|---|---|
| The swatch's popover and Window › Window Colour with twelve colours (4b draws five) | The popover keeps 4b's look: "Window Colour", then None alone, then the six light steps in a row and the six deep steps under them, both in 4a′'s hue order (Coral, Ochre, Green, Teal, Blue, Purple), each a 22 pt swatch with its name under it in 11 pt `text2`, the window's own ringed in `text`; then 4b's checkbox. The menu lists None, a rule, the six light, a rule, the six deep, each with a 12 pt swatch image, ticked on the window's own. | Q-444 |
| The swatch at All projects, where the toolbar has no project name | After "All projects", as after a project's name. | Q-445 |
| Window › Window Colour while Classic is on ("dimmed, with the same line") | The submenu item is disabled and its tooltip is 4c's line: "Window colours are off while Classic is on." | Q-446 |
| Home's stand-in names "window 1" | "Home is showing in window ‹n›", n being that window's place in the order windows were opened (the primary is 1); Show Here as drawn. Until Q-98 D10. | Q-447 |
