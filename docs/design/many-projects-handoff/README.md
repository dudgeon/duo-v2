# Duo S4-1: All projects with many projects — design handoff

Status: picked by Geoff, 2026-10-05 (DL-101), and built (F-80). Options and notes: `docs/design/explorations/home-many-projects.html`; brief: `docs/design/design-brief-many-projects.md`.

Same shape as `slice2-handoff/`: `screens/map-many.html` is the target (`screens/manifest.json`), exported from the exploration's `pick` board with `?board=pick&target=1`. Its data is `fixture.json`, written by `scripts/make-many-fixture.py`; the app's `map-many` state loads it (`scripts/check-ui.sh map-many`). New tokens: `size.map` (header control 22, filter 200, row time column 34).

## What the screen settles

- A map header: `Filter folders` at the left, `Sort` and a `Recent / Name` popup at the right.
- Home's ★ tile first in the unlabelled column: goal, `Home · n sessions`, five sessions in attention order, `n more ›`, a `text` border.
- Home's projects and topic folders as tiles, as S2-2.
- `OUTSIDE HOME · 64` on a rule, then `ACTIVE OUTSIDE HOME · 3` with tiles for folders with a session that needs you or is working, then folders as rows grouped by parent folder, five a group, `+ n more`.

## Behaviour a picture can't show

- Recent orders by newest session activity; Name by name. Both apply to tiles in a column, rows in a group and the groups. Home's tile and the unlabelled column stay first.
- The order settles on arrival at All projects (and on the first scan) and doesn't move while the user looks.
- The filter narrows tiles and rows by name or path, ignoring case; groups with nothing left go; `n of m` counts what's left. Esc clears it.
- `+ n more` opens the group in place until relaunch.
- A row opens its folder as a project; right-click is the tile's menu (Make a Project, Move into Home…, Archive).
- Home's tile and its `n more ›` open Home as a project; a session opens Home on that session.

## Exempt from the comparison

The action column (unchanged from S2-6; the board's cards are illustrative, the fixture's needs-you sessions differ), the active tint on open sessions (the fixture state opens no terminals), and Home's goal wrapping one word differently (SwiftUI avoids a one-word last line, F-13).
