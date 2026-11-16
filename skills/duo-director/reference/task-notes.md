# The task note (§2 in full)

Read this before you write or restructure a task note. One request is one note, written before any work starts (SKILL.md §2).

**The task note** (everything else in it stays the user's; never restructure it):
- `## Request`: the user's words, copied exactly, plus anything you mustn't decide alone;
- `done_when:` in the frontmatter: how you'll both know it's finished;
- `directed_by:` your name (`director-<project>`), which makes it yours;
- `check_by:` when you'll look next. `duo2 director start` sets it to two hours unless you pass `--next`; for a job you know the length of, make it about half that (`--next 30m` for an hour's work). `duo2 director check` moves it. When you start work, tell the user the time you'll look, not just "when it's done". A promise to the user gets a `check_by` too, so nothing rests on your memory of it;
- `## Progress`: one dated line per step (what you asked, what came back, what you checked). `duo2 director send` appends one for every message;
- `depends_on:` and `waiting_on:` when they're real; read them before starting work;
- a folder `tasks/<slug>/` only when the task has files (pasted notes, inputs, deliverables). Nothing is required inside it.
