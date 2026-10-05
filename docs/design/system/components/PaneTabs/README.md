Tab strips: the console's (dark, mono), Home's session tabs, and the right pane's (light).

**Status:** Designed (handoff §5, surfaces DB-4). **In code:** `Project/ConsoleTabStrip.swift`; `Project/ProjectPanes.swift` `RightPane`; Home's tabs in `AllProjectsPanes.swift` `HomePane`.

**Console:** `tabStripHeight` 36 on `console`; each tab a StateGlyph (console colours) and the title in `mono`, the selected one `monoActiveTab` in `consoleText`, others `consoleText2`; shell tabs show the prompt mark (`assets/Icons/shellPrompt.svg`); `+ ⌄` opens New Claude Session (⌘T) / New Shell (⇧⌘T); overflow collapses into the more-tabs mark; titles cap at 24 characters. Home's strip is the same at 32.
**Right pane:** 36 high on `pane`, tabs `gapPaneTabs` (18) apart in `body`, the selected in `bodyEmphasis`: Project, a group, documents (file names), browser tabs (page titles), a read-only session; `+` makes a Markdown file, right-click `+` offers New Markdown File and New Browser Tab.

**Behaviour:** ⌘W closes the focused tab, never the window. Right-click a document tab: Close Tab, Close Other Tabs, then the file verbs.
