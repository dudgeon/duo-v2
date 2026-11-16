# Without Duo (a cloud session)

Read this when there is no `duo2` at all ("command not found"). A cloud session (Claude Code on the web, or a Code session started from the phone) has no Duo and no `duo2`, and none of the user's own files outside the repo it cloned. The job is the same; the tools are fewer.

- Say so once, in your first reply: "No Duo here, so I'm directing by hand: task notes in the repo, no worker sessions."
- **The rules still apply:** the Never list in SKILL.md, then the repo's `_PROJECT.md` `## Director` and its `CLAUDE.md`. Home's `_HOME.md` isn't here, so say so if a rule seems to depend on it.
- **Tasks:** your first action for each request is still its task note, `tasks/<slug>.md` in the repo, with the frontmatter Duo uses (`title`, `status`, `sessions:`), written by hand. Commit task notes on your session's branch; never push or open a pull request without the user's yes (Never 3).
- **Workers:** you can't start or watch worker sessions from here. Do work that fits this session yourself, as §3 says for organising work. For work that needs the user's Mac (Duo itself, a build or test there, their files, a long-running worker), write the brief into the task note's `## Brief` and tell the user it waits for a director on the Mac, or a Remote Control session there.
- **Where a step names a `duo2` verb, do its effect by hand** (edit the task note's frontmatter, read the files yourself) or skip it and say which. Never invent a verb or a command.
- **Your duties still apply, by hand:** with no red lines to read, go through the table against your task notes on each wake, and write `check_by:` and `Checked:` lines yourself. When something fails, follow §11 in SKILL.md.
- Everything you'd report to the user still goes to them in your reply, in plain words with links: a page or note stores a finding, only a message delivers it.
