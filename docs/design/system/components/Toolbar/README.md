The window's toolbar: where you are, what's waiting, and search.

**Status:** Designed; changed by decision: the search field reads `Search all projects ⇧⌘A` (DL-80), and the breadcrumb names the folder (DL-92); the right-pane button ends it (DL-129). **In code:** `Shell/DuoToolbar.swift`: `SidebarToggle`, `AllProjectsTitle`, `ProjectBreadcrumb`, `SearchField`, `RightPaneToggle`.

**All projects:** the left-pane toggle, `All projects` in `bodyEmphasis`, then the counts (`◆ 0 to review`, `○ 1 working`, `— 31 idle`), each glyph plus a number, `gapToolbarOverview` (16) apart.
**Inside a project:** `All projects` as an underlined link in `text2` › the project's folder in `text2` › the project in `bodyEmphasis` › the NeedsYouChip, `gapToolbarProject` (8) apart. The chevrons are 9 pt in `text2`.
**Right:** the search field, `searchFieldWidth` 300 × 24, with a magnifying glass, the label `Search all projects`, and the hint `⇧⌘A`. Then the right-pane button (DL-129): `sidebar.right` in `text2`, the mirror of the sidebar button, hiding and showing the right pane at either altitude, as ⌥⌘0 and `duo2 view right` do; tooltip `Hide Right Pane ⌥⌘0` / `Show Right Pane ⌥⌘0`.

**Don't:** put actions in the toolbar beyond these; the system draws its height (40 on macOS 27) and the traffic lights.

## Window colours (DL-313, DL-314)

With a window colour the toolbar takes the colour's `ground` at full chroma (a band under the system toolbar, whose background steps aside), `text2` draws as `text`, the needs-you chip keeps a plain `pane` fill, and the window swatch ends the breadcrumb (after "All projects" or the project's name), outlined while its popover is open. Hidden under Classic. Built: `Shell/DuoToolbar.swift`, `Shell/WindowViews.swift` (F-552, F-553).
