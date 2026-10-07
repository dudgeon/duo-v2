# Plain files, and Claude driving Duo

**Everything Duo knows is in files you can read, and everything you can do in Duo, Claude can do too.**

## Plain files

Projects are `PROJECT.md`, Home is `HOME.md`, tasks are notes in `tasks/`. Open them in Finder, Obsidian or any editor and Duo picks up your changes. Duo's own notes sit in a `.duo` folder in each project and in `~/Library/Application Support/Duo/`; delete Duo and your work is still all there.

| File | What it is |
|---|---|
| `PROJECT.md` | A project's brief: `goal`, `health`, `next`, then any notes. See [Projects](projects.md). |
| `HOME.md` | Marks your Home folder. See [Home](home.md). |
| `tasks/<name>.md` | A task: `status`, the `sessions` linked to it, your notes. See [Tasks](tasks.md). |
| `CLAUDE.md` | Claude Code's own file, not Duo's: Claude reads it in the folder it starts in and every folder above. |
| `<project>/.duo/` | Duo's notes about the project's sessions. |
| `~/.claude/projects/` | Claude Code's own transcripts. Duo reads them and never rewrites them. |

## Claude can drive Duo

Every button in Duo has a `duo2` command, and Claude sessions can use it once Duo has installed it (Duo offers on first launch; `duo2 install` does it too). So you can just ask Claude:

- "Open the checkout project and show me the PRD."
- "File this session under refunds."
- "What's waiting on me?"

When Claude edits a document you have open, it goes through Duo's editor, so you see the change highlighted and your unsaved typing is kept.

## For power users

`duo2 help` lists the command families; the full reference is [docs/cli/duo2.md](../cli/duo2.md). `duo2 doctor` says how a terminal finds Duo and what Duo installed. `duo2 search "<question>"` works even when the app isn't running.

Back to [the guide](README.md)
