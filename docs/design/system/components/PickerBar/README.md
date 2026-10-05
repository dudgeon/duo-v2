The bar under a web page while picking an element to send to Claude.

**Status:** Stand-in, plain system look (DL-70, Q-21; DB-13). **In code:** `Project/ProjectPanes.swift` `PickerBar`; the outline in `Editor/HTMLPicker.swift`.

**Anatomy:** a native bar (`.bar` material) under the page: before a pick, "Click an element to select it. Esc to stop." and Cancel; after, `<tag#id.class>` in monospace, then Send to Claude (default), Send To ▸, Pick Another, Cancel. The hover and frozen outlines use the system highlight colour, never `needsYou`.

**Works on** local HTML pages and browser tabs (allowed sites). Open for design (DB-13).
