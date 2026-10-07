The left pane at All projects: Home's own Claude sessions, the terminal you triage in.

**Status:** Designed, with and without a Home folder (DL-100, slice2 `no-home.html`); changed by decision (DL-142, home-evolution `home-chat` board 10): new Home sessions open in chat, and while Home's tab shows chat its header (35 + a `rule`, on `ground`, `★ home` semibold then the path in mono `text2`, 10 apart) and tab strip (DL-136's thin light strip, 27 + a `rule`, the light Terminal/Chat pill) are light, its divider too; a terminal tab, or chat fallen back to the terminal, keeps them dark. **In code:** `AllProjects/AllProjectsPanes.swift` `HomePane`, `HomeRule`, `AppModel.homeShowsChat`; the default in `Chat/ChatSession.swift` `ChatPrefs.mode(for:home:)`.

**Anatomy:** `paneOverviewHome` 340 on `console`. A 36-high header: `★ <home>` in `bodyEmphasis` `consoleText` (clicking it opens Home as a project) and its path in `mono` `consoleText2`; a `homeSessionTabsHeight` (32) strip of Home's session tabs and shells; then the terminal. With no Home folder: "★ Home", no session strip, then "Choose a Home folder", one paragraph, the console buttons Choose Home Folder… and Not Now, and a footnote naming File › Choose Home Folder…. Not Now collapses the pane at All projects until a Home is chosen.

**Behaviour:** ⇧⌘H focuses it from anywhere. Home starts a session when it has none (C-15).
