The left pane at All projects: Home's own Claude sessions, the terminal you triage in.

**Status:** Designed; with no Home folder it shows a stand-in prompt (DL-84; DB-37, S2-3). **In code:** `AllProjects/AllProjectsPanes.swift` `HomePane`.

**Anatomy:** `paneOverviewHome` 340 on `console`. A 36-high header: `★ <home>` in `bodyEmphasis` `consoleText` (clicking it opens Home as a project) and its path in `mono` `consoleText2`; a `homeSessionTabsHeight` (32) strip of Home's session tabs and shells; then the terminal. With no Home folder: "★ Home", an empty strip, and a ConsoleMessage, "No Home folder yet" · Choose Home Folder….

**Behaviour:** ⇧⌘H focuses it from anywhere. Home starts a session when it has none (C-15).
