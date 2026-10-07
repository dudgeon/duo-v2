A row in a project's session list: a session, a thread of forks, a group, or a task.

**Status:** Designed for session, thread and group rows; the open tint and "at prompt"/"working" designed (DL-133); task rows (DL-93) are stand-ins. **In code:** `Project/ProjectPanes.swift` `SidebarRowView`, `SidebarLeafRow`.

**Anatomy:** session and thread rows are `rowSession` (26): a 10-wide chevron slot (threads) or space, the StateGlyph, the name in `body` (one line, tail truncated), a CountPill for threads, and the wait time (`text2`, never truncated); a session with a tab open in Duo reads `at prompt` or `working` instead and sits on `activeTint`. Group and task rows are `rowGroup` (28): chevron, glyph of their most urgent session, name in `bodyEmphasis`, `group · n` or `task · n` pill, a task's status (past open) in `text2`, wait. Selected: `selected` fill, `radiusSelection`, inset `selectionInset` (8). Open groups and tasks show their sessions under a 1.5 `controlEdge` rule at `threadRuleX`.

**Behaviour:** a row opens or focuses that session's console tab (resuming it); a group row opens its group tab; a task row opens its note. Right-click a session: Send to Claude, Find Similar, Copy Link, Make a Task, Add to Task ▸, Move to Project ▸, Archive Session, Delete Session…. Right-click a group: Make a Task; a task: Open Task Note, Status ▸.

**Motion (DL-130):** Opaque on the pane, so a row travelling past never overprints it. The state glyph swaps in place. With Reduce Motion, it's at once.
