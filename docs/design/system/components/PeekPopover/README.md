"Needs you elsewhere": a popover from the toolbar chip listing sessions waiting in other projects.

**Status:** Designed. **In code:** `Navigation/PeekView.swift` `PeekView`, `PeekCard`.

**Anatomy:** a native popover, `peekPopoverWidth` 420, holding ActionCards (needs-you form) and a hint row in `text2` (`↑↓ to choose · ⌘↩ jump in · esc`).

**Behaviour:** ⇧⌘P or the chip opens it; ↑ ↓ select a card; ⌘↩ or `Jump into project` closes it and opens that session; esc or a click outside closes it and returns focus where it was, including a terminal.
