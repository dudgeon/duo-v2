# Duo: select several sessions and act on them — design handoff

Status: approved by Geoff (DL-247), by buttons on 2026-10-29, every recommendation taken. The canvas is https://claude.ai/artifact/6FH9QMZrJS5bVTasHoaqb1.

The screens are copies of the canvas boards, rendered to static HTML by `scripts/dc-render.py`, with `png/` at 2x. They're presentation boards, so build only what the table names. The canvas sources are in `canvas/`, and the boards draw their panes through `Pane.dc.html` (the sidebar-hierarchy pane with selection added) and `Glyph.dc.html`. Names and data are illustrative.

## Targets

| Screen | Build | Not chosen |
|---|---|---|
| `00-click-model` | The clicks, what a selection is, and what happens after an action. | — |
| `01-selected-rows` | **A: joined runs.** | B: each row its own fill |
| `02-selection-menu` | The selection's menu, in one project and across projects; `menuTarget` on every selected row while it's open. The menu is native, so match its contents and order. | — |
| `03-delete-sheet` | Delete n Sessions…: one sheet, four states. | Refusing the whole delete when one session runs outside Duo |
| `04-lists-and-duo2` | Which lists select, and the duo2 verbs. | Tiles selecting |

## The clicks (`00`)

- **Click:** opens the session as today, and clears the selection. The row becomes the anchor.
- **⇧-click:** selects every session row from the anchor to this one, in the order on screen. Task lines, fold rows, section labels and folded rows aren't selected. A new ⇧-click replaces the last ⇧ range, as in Finder.
- **⌘-click:** adds the row to the selection or takes it out. It becomes the anchor.
- **Neither ⇧- nor ⌘-click opens, resumes or changes the console.** That holds for parked sessions too.
- **⌃-click or right-click** on a selected row opens the selection's menu. On a row outside the selection, the selection moves to that row and its own menu opens.
- **Clearing:** Esc, or a click on empty pane space, clears the selection.
- **⌘A:** while the list has the keyboard, selects every session row showing in it. In a terminal, ⌘A stays the terminal's.
- **What a selection holds:**
  - Sessions only, across sections. One list at a time: switching project or altitude clears it.
  - A selected session that changes section stays selected. One that leaves the list leaves the selection.
- **After an action:** the selection clears. Archive, Park, Add to Task and Move to Project act at once and undo with ⌘Z. Delete asks first.
- **VoiceOver** says "n sessions selected", and each selected row reads "selected".

## The look (`01`, A)

- **Neighbouring selected rows join into one `selected` block.** Its corners are rounded 6 only at the top of the first row and the bottom of the last, with the row's usual 8 inset.
- **A row that isn't a session breaks a run.** A fold row, a task line or a section label between selected rows splits the fill into separate blocks.
- **Selection wins over `activeTint`.** A selected open row is `selected` and still reads "at prompt" or "working".
- **One selected row looks exactly as today.**
- **No new tokens.** Dark mode takes the tokens' dark values.

## The menu (`02`)

The order, with a divider between each group:

1. Make a Task · Add to Task ›
2. Move to Project ›
3. Archive n Sessions · Unarchive n Sessions · Delete n Sessions…
4. Park n Session(s)

How the items behave:
- **Each item names how many sessions it will act on.**
  - Archive n counts the unarchived ones and Unarchive n the archived ones. An item with nothing to act on isn't shown.
  - Park counts the sessions that can park. With none, it reads "Park Sessions", dimmed.
- **Make a Task** makes one task linking all of them. **Add to Task ›** adds all of them to the task you pick. Across projects, both are dimmed.
- **Left out for many:** Send, Find Similar, Copy Link, Resume as a Fork, Keep Running and End Session.
- **While the menu is open,** every selected row takes `menuTarget` (Q-147).

## Delete n Sessions… (`03`)

- **One Duo sheet** through SheetCenter, drawn like Delete Task… (DL-115).
  - The title reads "Delete n sessions?".
  - Under it, the item count and size. Then a box naming each session with its state, in mono `text2`: `idle · 1h`, `running in Duo: Duo ends it first`, `running outside Duo: not deleted`.
  - Then "You can put them back from the Trash, but Duo can't undo this."
  - The buttons are Cancel and **Move to Trash** (the default).
  - The box scrolls past about five rows.
- **A session running outside Duo is left out.** The sheet names it and n counts only the rest. When every selected session runs outside Duo, there's no sheet; a notice says why.
- **Only the selected sessions are touched.** Each delete is planned by session id before the sheet shows.

## Lists (`04`)

- **These lists select:**
  - a project's session pane, in every section (Archived's menu offers Unarchive n and Delete n);
  - Home's session pane;
  - All projects › List;
  - All projects' action column;
  - the idle list, where a plain click still resumes.
- **These don't:**
  - Map tiles. A ⇧- or ⌘-click on a tile's row does nothing.
  - Tab strips, search results and the task board's cards.

## duo2 (DL-71)

- `duo2 session delete <id>…` asks once in Duo, then names any id it skipped and why.
- `duo2 session archive|unarchive <id>…` undoes in one `duo2 undo`.
- `duo2 session park <id>…`
- `duo2 session move <id>… --to <project>`
- `duo2 task add <task> <session>…`
- `duo2 task make <session>…`
- `duo2 view select <id>… | --add <id>… | --all | --clear` acts on the list in front. With no arguments, `duo2 view select` prints the selection.

## For the build

- **DuoChecks:** range, toggle, clear, anchor, the parked rule (a modified click never opens), and runs (which rows join).
- **A fixture with parked, live and archived sessions mixed:** deleting several never touches one outside the selection.
- **Harness actions** for a range selection, the menu fill and the sheet, for `scripts/check-ui.sh`.
