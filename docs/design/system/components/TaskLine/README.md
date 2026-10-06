A task as a single line: a box, its title, its status. Used for tasks with no sessions yet and for open tasks at All projects.

**Status:** Designed (DL-100, slice2 `map-folders.html`, `session-rows.html`); the hover + is designed (DL-112, stand-ins `q43-hover.html`). **In code:** `Model/AppModel+Tasks.swift` `TaskLine`, `TasksFold`, `TaskStatusMenu`, `NewSessionInTaskButton`, `TaskRowHover`.

**Anatomy:** `rowSession` (26): a drawn task box (8 pt rounded square, stroke 1.3, in a 10 box; `TaskBox`) in `text2`, the title in `body`, at All projects the project in `text2`, then the status in `text2` when it's past `open`. Inside a project they sit in a `Tasks · n` fold under the history, indented 18 under the fold; at All projects under an **Open tasks · n** label after Ready for review.

**Hover (DL-112):** the row takes a `selected` fill (`radiusSelection`, inset `selectionInset` and from the fold's indent) and a + replaces its status: a `rowActionSize` (18) square, `rowActionRadius` (4), the + at `rowActionGlyph` (14) in `text2`, no fill of its own, the system tooltip "New Session in Task". A group-style task row shows the same + at its trailing end, where a wait would sit, with no hover fill.

**Behaviour:** click opens the task's note (going to its project first); the + is New Session in Task (`duo2 task session`): a Claude session linked from the note, with `@tasks/<note>.md` typed into its prompt once Claude is ready and not sent (DL-112). Right-click: Open Task Note, New Session in Task, Status ▸ (open, in-progress, waiting, review, done, dropped). Done and dropped tasks leave the lists.

**Open for design (S2-5):** the box, status display, and whether Home's list belongs in the action column.
