# duo2: everything you can do in Duo, Claude can do

`duo2` is Duo's command line. It's mainly for Claude, the agent in each terminal, and works for you too. The rule (DL-71): **any action a person can take in Duo has a `duo2` verb**, and a check enforces it. The full, generated reference is [`docs/cli/duo2.md`](../cli/duo2.md). How it was built: F-47 and F-48.

## Using it

```bash
duo2 help
```

`duo2 help` shows the everyday verbs and the 10 families. `duo2 help <family>` gives one family's verbs with their arguments.

- **Families:** `app`, `view`, `projects`, `sessions`, `files`, `docs`, `html`, `send`, `search` and `setup`.
- **Output:** readable text by default. Every verb takes `--json`. Errors go to stderr with a non-zero exit.
- **Where file verbs act:** without `--project`, in the project holding the folder you run them from (Claude's own project), else the one showing. Replies name the project.
- **What needs you:** moving a session and merging projects show Duo's confirmation sheet, and the command waits for your answer. `duo2 undo` reverses the last move, merge or Make a Project.

## How it stays complete

- **One registry:** every action is defined once, in `Sources/DuoControl/Actions.swift`. The CLI, `duo2 help`, the reference, the primer each Duo session gets, the `duo2` skill and the `CLAUDE.md` block are all generated from it, so none of them can name a verb that doesn't exist.
- **A new verb without app support won't compile:** the app handles verbs in a `switch` with no default.
- **Every UI action needs a verb:** `swift run DuoChecks` fails when a button, menu item, click or drag isn't tied to a verb, unless it's listed in `Parity.uiOnly` with a reason (Close Window, items not built yet, consent questions).

## How Claude sessions learn it

- **Duo's own sessions** get a short primer at start, generated from the registry.
- **Claude sessions anywhere on this Mac** need the install below (DL-74). Duo asks once before installing, listing every change, and asks again only if that list changes (DL-75).
  - **A short block in `~/.claude/CLAUDE.md`,** between `<!-- duo2:begin … -->` and `<!-- duo2:end -->`. It says Duo exists and to run `duo2 help`.
  - **A `duo2` skill** in `~/.claude/skills/duo2/`.
  - **`~/.local/bin/duo2`,** linked to the app.
- **Kept current:** each piece is rewritten when Duo starts.
  - Anything you edit is left alone.
  - A block you delete stays deleted.
  - `duo2 uninstall` removes all of it.
  - `duo2 install` installs it if you said Not Now.
  - `duo2 doctor` shows the state of each piece.

Why this shape, and what legacy Duo taught: [`docs/design/cli-teaching.md`](../design/cli-teaching.md).
