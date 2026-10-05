# Duo — Design, S4-1: All projects with many projects

Status: **picked (DL-104): A with the ★ tile**; handoff `many-projects-handoff/`, built (F-82) · 2026-10-05 · Owner: Geoff · Designed by Claude in the build session, with Duo's tokens.

Options page: `docs/design/explorations/home-many-projects.html` (open in a browser; `?board=<id>` shows one board at 1:1). Every mark is [P]. The design canvas tool wasn't available in this session, so the boards are HTML drawn with the tokens; on a pick they move to a canvas or straight to a handoff in the slice2 shape.

## The problem

Duo lists every folder Claude ran in (DL-82). On a normal Mac that's dozens: repos, Desktop, Downloads, temporary folders. S2-2 (DL-100) gives each a full tile under OUTSIDE HOME, so with the fixture's 64 outside folders the map runs to several thousand points and Home's six projects are a small part of it. Three asks from Geoff:

1. **Hierarchy:** projects in Home get more prominence than folders outside it.
2. **Sort:** by recency or alphabetically.
3. **Home's card:** Home will collect many sessions; its pane shows only the open ones, so Home needs a card on the map as well.

## Options

| | Outside Home | Sort | Home's card |
|---|---|---|---|
| **A (recommended)** | One 24-pt row per folder (name, sessions, last active) under its parent-folder heading, 5 per group then `+ n more`. A folder with a session that needs you or is working is promoted to a full tile in `ACTIVE OUTSIDE HOME`. | `Filter folders` field + `Sort: Recent / Name` popup in a map header; also View › Sort Projects By. | A full-width band: ★ name, goal, up to 8 sessions in attention order, `42 sessions · Open ›`. |
| **B** | Tiles as today; the 6 most recent (live first), then `Show all 64 folders outside Home`. | `Recent \| A–Z` segmented control. | A ★ tile first in Home's column, `text` border, 5 sessions then `37 more ›`. |
| **C** | A scope control: `Home` (Home's card, Home's tiles, live folders elsewhere) and `Everywhere` (a table grouped by parent folder). | Sortable table headings in Everywhere; the popup in Home. | One line: counts by state and `Open ›`. |

The three Home cards are interchangeable across options (board V).

## Rules all options share

- DL-83 holds: grouping by parent folder everywhere. Sort orders tiles within a column, rows within a group, and the groups; Home's unlabelled column and Home's card always come first.
- Recent means the newest session activity in the folder.
- The order settles when the user arrives at All projects; it doesn't reshuffle under the pointer.
- Nothing that needs you can be hidden by a fold, a scope or a filter: it's also in the action column, and A and C promote it on the map.

## Geoff's answers (2026-10-05, DL-104)

A · popup + filter · ★ tile · a session in Home's tile opens Home as a project on that session. The combined board is `pick`; its capture is `explorations/home-many-projects/1-picked-A-with-home-tile.png`.

## Questions asked (Q-35)

1. Rows (A), fold (B) or scopes (C) for folders outside Home?
2. Sort as a popup or an always-visible segmented control; with a filter field or without?
3. Which Home card: band, ★ tile or summary?
4. Does a session row in Home's card open it in Home's pane (stay at All projects) or open Home as a project on that session?
