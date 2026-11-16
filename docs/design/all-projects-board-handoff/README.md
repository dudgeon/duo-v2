# All projects' Board, by activity — handoff (DL-347)

Geoff decided this on 2026-11-16 (DL-347; Q-539 to Q-545), in chat by button, all seven recommendations. Study page https://claude.ai/artifact/KssyGmv9iLu75RAtsAnkHV (boards B1, B2, T); sources in `../all-projects-board-study/` (`make_boards.py`, canvas boards in `canvas/project/`). The List grouped by project (DL-341) is unchanged: don't break it (DL-350).

## Screens (`screens/`; `png/<name>.png` at 1x, `@2x` at 2x)

| screen | size | what it sets |
|---|---|---|
| `B1-activity` | 1440×900 | Board with Group ⌄ › Activity: Pinned (★ home first), Now and Today as tiles, This week as rows (name, folder, status, when, +), Earlier and Archived folded; a folder with no project file sits in the same sections, marked "No project file", with Make a Project; the Needs you column |
| `B2-activity-wide` | 1900×1060 | the same at 1900: as many tiles across as fit at `mapColumnMin` 220 (six) |
| `T-tile-button` | 1440×900 | the tile's quiet last row "+ New session": rest, hover (+ tooltip naming project and folder), focused tile (⌘T shown), ★ home, no project file (Make a Project beside it), narrowest 220. T2 (a + in the name row) is the rejected alternative: don't build it |

Exempt from the pixel target: the yellow [P] notes, sample data, the toolbar and Needs you column (as built today), session glyphs (use `SessionGlyph`, DL-174).

## What to build (DL-347)

1. **B by activity.** Sections Pinned, Now (needs you, working, open or to review), Today as tiles; This week as rows; Earlier and Archived folded (closed by default). Sections by the last session's start, as the List's groups do. Each tile names its folder in a `monoPath` line. Home is no longer the organising principle; no "Outside Home" part.
2. **Group ⌄ on the Board:** Activity (default), Folder (today's folder bands, per DL-83's columns), None (flat). Replaces Sort on the Board. View › Group Projects By; `duo2 view group activity|folder|none`.
3. **Pins.** Tile and project menus › Pin to Top / Unpin; `duo2 project pin <p> [on|off]`. ★ home starts pinned when there is a Home; it can be unpinned.
4. **+ New session** as the tile's last row (24 pt under a `selected` hairline; + in the glyph column, text2 at 12; hover `selected` fill, text). Tooltip "New session in ‹project›" and its folder; accessibility label always that. It starts a session in the tile's folder and opens the project's page on it (`AppModel+StartSession.swift`); a folder with no project file gets Make a Project beside it. This-week rows have a + at the right end that widens to "+ New session" on hover, as DL-341's header +.
5. **⌘T** with a tile focused starts a session in that project, and its row shows ⌘T; otherwise DL-262's default.
6. **Folders with no project file** in the same sections, marked, with Make a Project.
7. **Columns:** as many as fit at `mapColumnMin` 220, lifting DL-83's three-column cap.

Leave room above the sections: the first-run welcome (DL-348) builds next, on this page.

## duo2 (DL-71)

New: `duo2 view group activity|folder|none`, `duo2 project pin <p> [on|off]`. Existing: `duo2 session new --project <p>` / `--folder <path>` (add "Board tile New session row" to its UI names). Folds are `Parity.uiOnly`. Regenerate `docs/cli/duo2.md`.

## Stand-ins (not drawn; Q-583 to Q-585)

- Dark and Classic: build from tokens; checked in all three, not drawn.
- Narrow windows below the 220 column minimum: one column; This-week rows hide the folder, then the when; the + stays.
- Empty states (no projects in a section hide the section); Group › Folder and None keep today's tile.
- Tiles moving between sections: a fade in place (`motionChipIn`, nearest token), Reduce Motion respected.

## Checks

DuoChecks (section assignment, pins, grouping, columns at widths, ⌘T target); fixture states captured with `scripts/check-ui.sh` and compared with `screens/png/*@2x.png` region by region in Light, Dark and Classic at 1440 and 1900; List-by-project's checks still pass. Keep comparison images in `checks/`.
