The list of resumable sessions, opened from the map's footer `N idle, resumable ›`.

**Status:** Designed (DB-1, surfaces-handoff). **In code:** `AllProjects/IdleList.swift` `IdleFooter`, `IdleListPopover`, `IdleRowView`.

**Anatomy:** a popover `idlePopoverWidth` 460 above the footer, arrow down, 16 from the map's left; padding 12 8 12; a heading and key row that stay put while the list scrolls; rows `idleRowHeight` (26), radius 6: glyph, session name, project (`text2`, at most `idleProjectColumnMax` 150), age (`idleAgeColumn` 30). Sessions open in Terminal show too (DL-98). `shadowPopover`.

**Behaviour:** ↑ ↓ and Return resume the chosen session in its project; esc closes. Newest first.
