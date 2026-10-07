# Where a session belongs

**A session belongs to the project around the folder it ran in.**

## The problem

Claude Code files each conversation under the folder it started in. A conversation started in the wrong place is as good as lost: it won't be there when you look in the right one.

## In Duo

Duo follows the same rule, so nothing surprises you. Start Claude inside a project's folder, or any folder inside it, and the session is that project's. Start it from the project in Duo (**+ New session**, or <kbd>⌘T</kbd>) and it always lands in the right place.

Started somewhere else? The session shows under that folder on the map. Drag it onto the right project, or right-click it and choose **Move to Project…**. Duo files it there straight away, and Claude's own copy follows the next time you open the session.

```
payments/checkout/            ← a project (it has a PROJECT.md)
├── PROJECT.md
├── "PRD v2 edits"            started in checkout/            → checkout's
└── research/
    └── "Teardown research"   started in checkout/research/   → checkout's too

~/Desktop/
└── "Saved-cards notes"       started on the Desktop          → shows under ~/Desktop
                                                                 until you move it
```

*Where you start Claude decides where the session belongs. The closest project around a folder wins. If it started in the wrong place, move it.*

## Good to know

- Moving or renaming a project folder in Finder doesn't lose its sessions. Duo notices and offers to reconnect them.
- Every move tells you exactly what will move before it happens, and Edit › Undo puts it back.
- Two folders that are really one piece of work? Drag one tile onto the other to merge their sessions. Files stay where they are.
- Dragging files works too: drop files from Finder onto a project's file list to move them there (with Undo), or onto a terminal to type their paths for Claude.

## For power users

A session's transcript lives under its folder in `~/.claude/projects/`, which is why `claude --resume` only shows a folder's own sessions. When you move a session, Duo resumes it in its old folder and sends Claude's own `/cd` command, so Claude moves the transcript itself; nothing is rewritten. `duo2 session move <id> --to <project>`, `duo2 project merge`, `duo2 undo`.

Next: [Home](home.md)
