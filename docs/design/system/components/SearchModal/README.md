Search everything (⇧⌘A): names of projects, groups and sessions first, then files and sessions by meaning and by words.

**Status:** Designed (search-handoff), with Jump merged in and no ⌘K (DL-80, DL-81). **In code:** `Search/SearchView.swift` (SearchOverlay, SearchPanel, SearchFieldRow, SearchFilterRow, FilterChip, ResultList, ResultRow, SearchPreview, SearchFooter, ActionMenu).

**Anatomy:** `scrim` over the window; a `searchModalWidth` 960 panel, `searchModalTop` 92 from the top, `radiusPopover`, `shadowPopover`. The field row (`searchModalFieldRowHeight` 52, `searchField` 17/24), filters (scope, kind, project, date; Exact ⌘E), a `searchModalListColumnWidth` 420 result list (a "Go to" block of names, then results with kind icon, title, meta and a 2-line snippet) beside a preview, and a footer of key hints. Tab opens the action menu (`actionMenuWidth` 300).

**Behaviour:** Return opens a file at its lines or resumes a session; ⌘D sends results to Claude; ⇧⌘A again narrows to this project; esc steps back a level. The full set of 16 states is in `docs/design/search-handoff/screens/` (skip `search-jump.html`, superseded).
