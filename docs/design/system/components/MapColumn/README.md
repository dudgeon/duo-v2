A column of project tiles on the map, headed by the folder it represents.

**Status:** Designed (DL-100, slice2 `map-folders.html`); the folder mark is still a stand-in (DB-38). **In code:** `AllProjects/AllProjectsPanes.swift` `MapColumn`, `ProjectMapPane`.

**Anatomy:** a label (SF Symbol `folder` 9 pt in `text2`, then `sectionLabel` with the folder's own name and a slash: `payments /`), then ProjectTiles `gapTileToTile` (10) apart; Home's columns come first; folders outside Home follow a full-width `OUTSIDE HOME` section label on a `rule` hairline, labelled by path, a long path keeping its first and last parts (`~/Desktop/…/interviews`). The NewProjectTile ends the map. Columns sit `gapMapColumns` (14) apart, side by side while each gets 220; past that they wrap into rows.

**Order:** projects directly in Home first, in a column with no label; then Home's topic folders; then folders outside Home, labelled by path (`~/repos /`).

**Open for design (S2-2):** long path labels (truncated today); a break between Home's columns and outside ones; single-tile columns in a wrapped row.
