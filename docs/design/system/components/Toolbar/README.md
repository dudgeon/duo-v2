The window's toolbar: where you are, what's waiting, and search.

**Status:** Designed; changed by decision: the search field reads `Search all projects ⇧⌘A` (DL-80), and the breadcrumb names the folder (DL-92). **In code:** `Shell/DuoToolbar.swift`: `SidebarToggle`, `AllProjectsTitle`, `ProjectBreadcrumb`, `SearchField`.

**All projects:** the left-pane toggle, `All projects` in `bodyEmphasis`, then the counts (`◆ 0 to review`, `○ 1 working`, `— 31 idle`), each glyph plus a number, `gapToolbarOverview` (16) apart.
**Inside a project:** `All projects` as an underlined link in `text2` › the project's folder in `text2` › the project in `bodyEmphasis` › the NeedsYouChip, `gapToolbarProject` (8) apart. The chevrons are 9 pt in `text2`.
**Right:** the search field, `searchFieldWidth` 300 × 24, with a magnifying glass, the label `Search all projects`, and the hint `⇧⌘A`.

**Don't:** put actions in the toolbar beyond these; the system draws its height (40 on macOS 27) and the traffic lights.
