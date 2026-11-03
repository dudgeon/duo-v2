# Multi-window slice 1: two windows, each with its project and its colour

Status: **target** for multi-window slice 1 (DL-311), exported 2026-11-02 from the studies canvas https://claude.ai/artifact/46yWPpDZn16Qtfrfhbuaw1 as Geoff decided it: DL-141, DL-308, DL-311, DL-312, DL-313. Built on `build/multi-window-slice1` (F-552).

The study is `../multi-window-studies/` (its README lists every board and decision). This handoff keeps only what slice 1 builds. Pinning (boards 2, 3), a session or document in two windows (6, 7), needs-you across windows (8) and the Window menu's marks (9 A) are later slices.

## Screens

Each is a picture written in HTML, rendered by `canvas/make.sh` from the boards in `canvas/` (a copy of the canvas as of DL-313). Build to what they draw; don't port the markup. `screens/png/` has each at 2×.

| Screen | Board | What slice 1 takes from it |
|---|---|---|
| `board-1-new-window.html` | 1 · How a new window opens | **Option A only.** File › New Window ⌥⌘N, at the top of the File menu, opens a window at All projects. Project › Open in New Window (and the same item on a map tile's and a sidebar project row's right-click menu, as the caption says) opens that project in a new window. No pin (slice 3): the caption's "pinned to it" is dropped by DL-311. |
| `board-4a-prime-colours.html` | 4a′ · Twelve window colours, direction C | **The palette** (DL-313): six hues × a light and a deep step, light and dark appearance. Which surfaces take the colour, and the order new windows take them in. Values: `../build-handoff/tokens.json` `windowColour` (from `../multi-window-studies/palette/palette.json`). |
| `board-4b-new-colour.html` | 4b · A new window's colour, and changing it | **Option A.** The first window stays None; each new window takes the first colour in DL-313's order that no open window has. The swatch after the project's name, its popover (colours and "Colour new windows automatically"), and Window › Window Colour ▸ with a check on the window's own. The board's four colour names (Sky, Sage, Lilac, Sand) are superseded by 4a′'s twelve; the popover and menu for twelve are board 4b′ A, and the swatch's place at All projects 4b″ A (DL-314, below). |
| `board-4c-classic.html` | 4c · Window colours and Classic | **Option A.** Classic turns window colours off: every window draws Classic, the swatch leaves the toolbar, Window › Window Colour opens with the line (board 4c′ A, DL-314, below), and Settings › General › Appearance shows the line under the popup. Each window gets its colour back when Classic is turned off. |
| `board-9-window-menu.html` | 9 · The Window menu | **Option C for slice 1** (DL-311: "the system Window menu and ⌘\`"): the system's items, with each Duo window listed by its title. A's swatches and needs-you marks are slice 2. Window Colour ▸ (board 4b) is added above the window list. |
| `board-10-home.html` | 10 · What happens to Home | **Option B** (DL-311, Q-431): every window has All projects. Home's pane is live in one window; the others draw the dark pane naming Home's window, with Show Here (moves Home's terminal to this window) and Go There: board 10′ A (DL-314, below). Until Q-98 D10 adds chat there. |
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
- **The swatch** (4b″ at full size) is an 11 pt circle with a 1 pt `controlEdge` ring, filled with the colour's `swatch` (None: plain `pane`), then a chevron (`symbol.swatchChevron`, 7 pt) in the crumb colour, 3 apart, 2 × 4 padding; outlined in `controlEdge`, radius 4, while its popover is open (4b′). It ends the breadcrumb (4b″ A). Hidden under Classic.

## The order and the rule [G] DL-312, DL-313

Blue, Ochre, Purple, Green, Coral, Teal, then Deep blue, Deep ochre, Deep purple, Deep green, Deep coral, Deep teal. A new window takes the first that no open window has. With all twelve taken, it takes the one the fewest open windows have, first in the order. The first window opens None. The switch "Colour new windows automatically" (on by default) turns this off: new windows open None. A window keeps its colour until it closes (restore is slice 2).

## Titles, menus and `duo2` [G] DL-311

- A window's title is its project's name, or "Duo" at All projects (and in Home). macOS lists the windows by title in the Window menu and moves between them with ⌘\`. Duo draws nothing for this.
- A project lives in one window (DL-308): opening it anywhere else (a tile, the sidebar, search, the peek's jump, a notification, `duo2 open`, `duo2 session open`, Open in New Window) brings that window forward instead.
- Close Window (⇧⌘W) closes a second window. Its projects' tabs and sessions stay. The last window hides as today; Duo doesn't quit.
- Every action has a verb (DL-71): `duo2 window list | new [<project>] | focus <n|project> | close [<n|project>] | colour <name|none|auto on|off>`. The on-screen verbs take `--window <n|project>`. With no `--window`, a verb acts on the window that shows the caller's session, else the primary window (the oldest open), never the key window (Q-430).

## The four stand-ins, decided (DL-314)

Slice 1 first built four stand-ins (Q-444 to Q-447). Geoff chose option A on each, on boards drawn for them: `screens/png/board-4b-prime.png`, `board-4b-double-prime.png`, `board-4c-prime.png`, `board-10-prime.png` (rendered from `../multi-window-studies/standins/`; canvas boards 4b′, 4b″, 4c′, 10′). These are the targets:

| Board | Decided (DL-314) |
|---|---|
| 4b′ A · the swatch's popover | "Window Colour"; None on its own row, the window's colour named at the right; one column per hue (Coral, Ochre, Green, Teal, Blue, Purple), named once on top, with Light and Deep rows; the window's own ringed in `text`; then "Colour new windows automatically". The swatch is outlined while its popover is open. Window › Window Colour: None, the six light, the six deep, each with a 12 pt swatch image, ticked on the window's own. |
| 4b″ A · the swatch at All projects | The swatch always ends the breadcrumb: after "All projects" at All projects, after the project's name inside one. |
| 4c′ A · Window Colour under Classic | Stays enabled. The submenu opens with 4c's line ("Window colours are off while Classic is on. Each window gets its colour back when you choose another appearance."), then every colour dimmed with the window's own ticked, then Appearance Settings… (`duo2 settings appearance`). |
| 10′ A · naming Home's window | "Home is showing in the ‹Blue› window", the name on a chip of that window's toolbar colour; Show Here and Go There (`duo2 window home`, `duo2 window focus`). A window with no colour, or under Classic, is named by where it is: "Home is showing in another window, at refunds" (or "at All projects"). ENH-322: Geoff wants the Home pane itself revisited later; not in slice 1. |
