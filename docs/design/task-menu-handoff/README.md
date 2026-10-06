# Duo: the task right-click menu — design handoff

Status: approved by Geoff, 2026-10-06 (DL-115), and built (F-97). The boards were drawn on the Design canvas https://claude.ai/artifact/6i7mSyfa771bvhcykczetN with the Duo design system (every mark a [P]), and are exported here as static HTML with PNGs in `screens/png/`.

## What the boards settle

- `task-menu` (board A): one menu wherever a task is listed (a line in the Tasks fold, a task group in the session list, Open tasks at All projects). **Open Task Note, New Session in Task, Add Session ›** — **Rename, Mark Complete, Set Status ›** — **Copy Link, Reveal in Finder, Move to Project ›** — **Archive Task…, Delete Task…**.
- `task-menu-archived` (board B): archived tasks sit in the project's **Archived** fold after the archived sessions; the fold's count is both. Their menu: **Open Task Note** — **Copy Link, Reveal in Finder** — **Unarchive Task, Delete Task…**.
- `task-questions` (board C): Archive, Delete and Move ask first in a Duo question, listing the task's sessions (its `sessions:` list) in the box. Buttons: **Cancel**, **… Task Only**, **… Task and Its Sessions**. Archive and Move default to taking the sessions; **Delete defaults to Delete Task Only**, since deleting a session can't be undone. A running session is named in the note and is never archived or deleted.

## Behaviour a picture can't show

- **Rename** opens the note with its name selected, as + New task does. Typing renames `title:` and the heading together (F-87). The file follows: `tasks/<slug of the new name>.md` (`-2`, `-3` when taken) once the note is saved and nobody has typed in it for 3 seconds (C-24). `duo2 task rename` does both at once, with one undo.
- **Mark Complete** is Set Status › done.
- **Copy Link** copies `[Title](duo2://task/<id>)`. The id is written once into the note's frontmatter (`id:`), so the link survives renames and moves.
- **Archive** writes `archived: true`; nothing moves on disk; the task stays searchable. **Unarchive Task** brings back the sessions archived with it. One undo covers the task and its sessions.
- With no sessions, Archive and Move happen at once (undoable). Delete still asks: Cancel or Move to Trash.
- **Move to Project ›** lists projects, not plain folders. The note goes to that project's `tasks/`.
- Every item has a `duo2 task …` verb (DL-71): `rename`, `status`, `add`, `session`, `link`, `reveal`, `move`, `archive`, `unarchive`, `delete`.

## Exempt from the comparison

The menus are native: macOS draws them, and window captures don't (`--then task-menu:<path>` prints a task's menu as text). Names, sessions and times are illustrative.
