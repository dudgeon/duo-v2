A task as a single line: a box, its title, its status. Used for tasks with no sessions yet and for open tasks at All projects.

**Status:** Stand-in (DL-93; S2-1, S2-5). **In code:** `Model/AppModel+Tasks.swift` `TaskLine`, `TasksFold`, `TaskStatusMenu`.

**Anatomy:** `rowSession` (26): SF Symbol `square` 9 pt in `text2` in the glyph slot, the title in `body`, at All projects the project in `text2`, then the status in `text2` when it's past `open`. Inside a project they sit in a `Tasks · n` fold under the history; at All projects under an **Open tasks · n** label after Ready for review.

**Behaviour:** click opens the task's note (going to its project first); right-click: Open Task Note, Status ▸ (open, in-progress, waiting, review, done, dropped). Done and dropped tasks leave the lists.

**Open for design (S2-5):** the box, status display, and whether Home's list belongs in the action column.
