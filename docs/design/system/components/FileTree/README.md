The project's files under its session list.

**Status:** Designed; folders that open and close, and hidden files, are stand-ins from decisions (DL-105, Q-40). **In code:** `Project/ProjectPanes.swift` `FileTreePane`, `FileRow`, `InlineNameField`; the listing in `Live/LiveSnapshot.swift` `treeFiles`.

**Anatomy:** under a 2 `controlEdge` divider: `FILES` (SectionLabel), the path in `monoPath` (11/20, `text2`), then rows `rowFile` (24) in `mono`: folders with a chevron, files indented; the selected file `selected`; a file Claude edited says `edited by Claude` in `text2` at the right.

**Behaviour:** a click opens the file in a right-pane tab (Markdown in the editor, HTML as a page). A click on a folder opens or closes it (chevron down or right); in a live project folders start closed and are read from disk when opened, and opening a document opens its folders. View › Show Hidden Files lists dotfiles, in `text2` with everything inside a hidden folder; `.git`, `.DS_Store`, `.duo`, `node_modules`, `build`, `.build` and `.claude/worktrees` never show (DL-105). Right-click: Open, Open With ▸, Rename, Duplicate, Move To…, Copy Path / Relative Path / as Link, Reveal in Finder, Find Similar, Send to Claude, Move to Trash; New Markdown File (⌘N), New Folder (⇧⌘N), New from Template ▸. Names are edited in place.

**Motion (DL-130):** A folder opens like a fold (`motionFold`), and is listed at once (Q-79). A drop target lights up over `motionDropIn`. With Reduce Motion, it's at once.
