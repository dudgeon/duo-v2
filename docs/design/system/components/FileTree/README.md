The project's files under its session list.

**Status:** Designed. **In code:** `Project/ProjectPanes.swift` `FileTreePane`, `FileRow`, `InlineNameField`.

**Anatomy:** under a 2 `controlEdge` divider: `FILES` (SectionLabel), the path in `monoPath` (11/20, `text2`), then rows `rowFile` (24) in `mono`: folders with a chevron, files indented; the selected file `selected`; a file Claude edited says `edited by Claude` in `text2` at the right.

**Behaviour:** a click opens the file in a right-pane tab (Markdown in the editor, HTML as a page). Right-click: Open, Open With ▸, Rename, Duplicate, Move To…, Copy Path / Relative Path / as Link, Reveal in Finder, Find Similar, Send to Claude, Move to Trash; New Markdown File (⌘N), New Folder (⇧⌘N), New from Template ▸. Names are edited in place.
