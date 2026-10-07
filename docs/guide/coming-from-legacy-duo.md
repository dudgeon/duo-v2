# Coming from Legacy Duo

For people who use Legacy Duo today: how the two relate, what moved, what's not here, and how to run both.

## One family, two jobs

Legacy Duo and Duo v2 tackle two halves of the same problem: doing real work with Claude without living in a terminal.

- **Legacy Duo is a shared desk.** One window holds your conversation with Claude, your files, a docs-style editor and a browser, so you and Claude work on the same thing side by side. It's at its best for writing and reviewing one document together.
- **Duo v2 is a home base.** It starts from everything you have going: every project and every conversation, what each one needs from you, and one click into any of them. Inside a project you still get the shared desk: Claude, your files and your documents, side by side.

Duo v2 is a new app, built from scratch as a native Mac app. It doesn't bring over Legacy Duo's settings, but it finds every Claude session you've had on this Mac, including the ones you ran in Legacy Duo, and your files stay where they are.

## Installing beside Legacy Duo

Both apps are called `Duo.app`. Dragging Duo v2 into Applications on a Mac that has Legacy Duo asks to replace it, and **Replace removes Legacy Duo**. To keep both:

1. In Applications, rename Legacy Duo first, for example to `Duo Legacy.app`.
2. Then drag Duo v2 in.

Legacy Duo keeps working under its new name. (A distinct name for v2's app is logged for later.)

## Where things went

| In Legacy Duo | In Duo v2 |
|---|---|
| The file navigator on the left | Each project's files, under its sessions |
| Terminal tabs and resume pills | Each project's sessions, all listed and resumable; live terminals in the middle, or [chat mode](sessions.md#chat-mode) |
| The project rail | The map on All projects |
| Home and the Catch-up board | All projects: Needs you, Ready for review, and the map |
| The "waiting on you" tab dot | The needs-you states, the toolbar chip, notifications |
| The markdown editor | The editor, with Claude's additions highlighted and revertible, and table editing |
| The Send → agent pill | Send to Claude (<kbd>⌘D</kbd>) from documents, pages, slides, files, sessions and projects |
| Workspaces (saved desks) | Each project reopens as you left it |
| The browser pane | Browser tabs for sites you allow, Google Docs included |
| The `duo` command | The `duo2` command; both can be installed |

## Not in Duo v2, or not yet

As of version 0.2.2.

**Planned:** a version history you can browse and restore from; Claude's edits as suggestions you accept or reject; two documents side by side; more than one window.

**Maybe later:** a JSON-aware editor (JSON opens as plain text today).

**Use Claude Code's own:** scheduled sessions. Claude Code can schedule work itself, and those sessions show up in Duo like any other.

**Not planned:** editing HTML pages in place (they open as live pages), playgrounds and lessons; git tools (worktrees, pull, GitHub); team distribution packs.

## Running both

- Both apps work on the same folders and the same Claude sessions; neither moves your files.
- Their commands differ: `duo` for Legacy Duo, `duo2` for Duo v2.
- Legacy Duo added instructions to Claude's global settings (a skill, an agent, hooks and a block in `~/.claude/CLAUDE.md`) that tell every Claude session about the old `duo` command. Duo v2 finds them and offers to turn them off, with a backup you can restore from Settings (`duo2 legacy`).

Back to [the guide](README.md)
