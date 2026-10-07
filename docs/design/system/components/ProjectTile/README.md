One project or folder on the map: what it's for, how it's going, and what's running in it.

**Status:** Designed (handoff §5); open sessions designed (DL-133); folder tiles and focus are stand-ins (DL-63). **In code:** `AllProjects/AllProjectsPanes.swift` `ProjectTile`, `TileSessionRow`, `NewProjectTile`.

**Anatomy:** padding 10 12 12, 1 `rule` border, `radiusCard`, lines `gapTileRows` (2) apart: the name in `bodyEmphasis`; the goal in `body` (a folder shows its path instead); health · next step in `text2` (empty parts dropped); then its live sessions as 24-high rows (glyph, name, wait), the first `gapCardContent`-ish 6 below, or `Nothing running` / `N past sessions` in `text2`. A session with a tab open in Duo reads `working` or `at prompt` in place of its wait (one that needs you keeps its wait) and, unselected, sits on `activeTint` (DL-133). Keyboard focus: a 2 `text` outline (`borderTileFocusOutline`).
**Folder tiles** add "No project file", or "Has CLAUDE.md · no project file".
**NewProjectTile:** 38 high, dashed (`borderDash`) `controlEdge`, `+ New project` centred in `text2`.

**Behaviour:** the whole tile opens the project; a session row opens it on that session. Right-click: Send to Claude, Make a Project (folders), Merge Into, Move into Home…, Archive Project. Tiles drag onto tiles to merge.

**Motion (DL-130):** A new tile fades in (`motionTileIn`). Dragged, the source sinks and the target rises (`motionLift`, no spring), and the landed fill and capsule take `motionLanded`. With Reduce Motion, it's at once.
