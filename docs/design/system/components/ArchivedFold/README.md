Where archived things go: a rollup under the map for projects, a fold at the bottom of a project's list for sessions.

**Status:** Stand-in (ENH-6; DB-34). **In code:** `AllProjects/ArchivedProjects.swift` `ArchivedRollup`; `AllProjects/ArchivedSessions.swift` `ArchivedSessionsFold`.

**Anatomy:** a chevron and `Archived · n` in `text2` (`rowGroup`); open, plain rows (tiles for projects, SessionRows in idle state for sessions). Archiving is filing: out of lists and counts, still searchable; Unarchive from the right-click menu or ⌘Z.

**Open for design (DB-34):** folded and open looks, how archived items look, whether it stays visible above the map's footer.
