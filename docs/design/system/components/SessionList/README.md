A project's left pane: its heading, its sessions by what needs you and what's open, then history, then FILES.

**Status:** Changed by decision (DL-91, DL-93); the new sections' look is a stand-in (S2-1). **In code:** `Project/ProjectPanes.swift` `ProjectSidebarPane`; `Model/SidebarModel.swift` `SidebarRow.sections`.

**Anatomy:** the heading: project name in `title`, health · next in `text2` (clicking it opens the Project tab). Then sections, each a SectionLabel and SessionRows: **Needs you** (`needsYou` label) · **Open · n** · **Today** · **This week** · **Earlier · n** (a fold) · **Tasks · n** (a fold of TaskLines) · **Archived · n** (a fold). Then `+ New session` and `+ New task` Buttons, then the FileTree under a 2 `controlEdge` divider.

**Rules:** needs-you sessions stay on top whether open or not; Open is about Duo's tabs, not Claude's activity; history is by last use, newest first. Task and group rows mix with sessions by urgency.

**Open for design (S2-1):** Open against Needs you; the wording "at prompt"/"working"; task rows against group rows; where "Resume a session" (in `project.html`) goes.

**Motion (DL-130):** A row that changes section travels there (`motionRowMove` 200 ms), lifted above the rows it passes. New rows fade in (`motionRowIn`), and rows that go fade out (`motionRowOut`). While the pointer is in the list, it holds its order (Q-80). Another project's list replaces it at once. With Reduce Motion, it's at once.
