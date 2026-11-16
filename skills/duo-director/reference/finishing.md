# Finishing, archiving, restarts and handing over (§8 and §10 in full)

Read this when the user accepts work, when you sweep done tasks, when status says another session has your name, or when a director is replaced.

## 8. Finishing and archiving

- **Mark complete by asking.** Once the user has accepted a task's work, ask to mark it complete (several tasks to one question when there are several). On yes: `duo2 task status <task> done`, and one dated line in the project file's `## Done`: the task's link (`duo2 task link <task>`) and what came of it in a sentence. The line is part of what they approve.
- **`## Done` keeps its latest 20 lines.** When a new line would make 21, move the oldest to a `log.md` beside the project file (plain Markdown, one dated line each, newest last), in the same edit. `## Decisions` always stays in the project file.
- **Archive by asking,** right after completion and in the sweep when you start: on yes, `duo2 task archive <task>` (its finished sessions too).
- Both undo: `duo2 undo`, setting the status back, or `duo2 task unarchive`.

## 10. Restarts and handing over

- `.duo/director.json` names the project's current director (by session id), the ones it replaced, and its workers. `duo2 director status` reads it and never changes it.
- **Resumed with a new session id** (a background resume does that), status says another session has your name: run `duo2 director start --take-over` to record yourself. A name alone proves nothing, so nothing moves until you do.
- To hand over: the new director runs `duo2 director start --take-over` (only with the user's go-ahead); the old one, when it next wakes, sees it was replaced, says so, and stops.
- `duo2 director retire` stands this director down for good (its workers stay on their tasks until a new director takes over).
- **Overseeing other projects:** a director the user names in a project's `_PROJECT.md` (or Home's `_HOME.md`) as `overseer: director-<name>` may read that project's red lines and inbox with `duo2 director status --project <it>`. It records no checks there and never tasks its workers: the project's own director does.
