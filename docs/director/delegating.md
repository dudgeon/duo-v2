# Delegating to build sessions

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in PROJECT.md's `## Director`.*

## 1. Taking work from Geoff

- **A feature or bug goes to a NEW session,** never to your own edits (Geoff, 2026-10-06). Small follow-up fixes found in review can go back to the session that built the thing, or to an `Agent` with `isolation: worktree`.
- **Settle the scope first** if it's ambiguous: AskUserQuestion with buttons and your recommendation first. Geoff can't use document dropdowns. He often answers design choices by commenting on the Design canvas, so tell design sessions to act on comments.
- **Pick the model by the job** (CLAUDE.md, Model efficiency): a scoped build or fix starts on Sonnet (`claude --bg --model claude-sonnet-5-5 …`); a design study or research session starts on Opus (Duo's default, or `--model claude-opus-5-5`); test-only work on Haiku. When I run checks or sweeps myself, I use scripts or Haiku subagents (`Agent` with `model: haiku`).
- **Start the session outside Duo, as a background Claude session with Remote Control** (Geoff, 2026-10-07: "make all of these sessions, and all going forward, available for remote control unless I specify to run them on duo"). Write the task note in `tasks/` (the brief goes in its `## Brief`), then run `duo2 director start <task> --background` from the main checkout: it prints the `claude --bg` command with a name made for this start (`-n`, keep it). Add `--remote-control "<name>" --model <the job's model>` before its `--` and run it. Duo links the worker by that name when it starts: no link step, and never `--adopt` for your own workers. `claude agents --json` lists background sessions, `claude logs <id>` shows output, `claude stop <id>` ends one. Geoff follows them in the Claude app, and they survive Duo restarts and test builds. Find its peer name for SendMessage in `ListAgents` (kind `bg`). **Exception:** a session that must publish its own page, so Geoff's taps reach it, starts in Duo with `duo2 session new --project duo-v2 --remote-control <name> --prompt "<brief>"`. Background sessions have no Artifact tools (F-259).
  - **Design work runs in Duo** (Geoff, 2026-10-07): background sessions don't get the Artifact/Design canvas tools (the director, in Duo since DL-166, does), so any session with a design round (a canvas, boards for Geoff) starts with `duo2 session new --project duo-v2 --remote-control "<name>" --prompt "<brief>"`. A background session that turns out to need a canvas: `claude stop <id>`, then `duo2 session open <id>` resumes it in Duo.
  - **Run other sessions in Duo only when Geoff says so, or when the job needs it** (e.g. testing Duo's own session UI live, or something that needs Duo's terminal environment). Then tell Geoff why before starting it, and use `duo2 session new --project duo-v2 --remote-control "<short name>" --prompt "<brief>"` (DL-128).
- **The standing worker rules are in CLAUDE.md** ("Rules for every build session"): the work tree, no push, isolation, the GPU lock, models, visible runs, who to report to. Every session loads them, so a brief doesn't repeat them. **The brief is the job:**
  - Geoff's words, quoted, and `done_when:`;
  - the branch and the work tree name;
  - **reserved record numbers** (DL, F, Q, C, ENH), taken after checking main and every branch, and different for each parallel session;
  - which other sessions are working where (stay out of their files);
  - how to prove it (DuoChecks, `scripts/bundle.sh`, `NO_BUILD=1 scripts/check-ui.sh`, captures against the boards, the relevant check scripts) and which CLAUDE.md rules matter most for the job (never invent a design; build to the screens and prove it; the DL-71 duo2 verb; Xcode-free; generated tokens);
  - which model the job runs on, and which parts go to Sonnet and Haiku subagents;
  - for design work: a Design canvas with the Duo design system, every mark [P], one AskUserQuestion round, and a handoff exported to `docs/design/<x>-handoff/`;
  - "Message director-duo-v2 (SendMessage) with the branch, the full shas, the records and the checks when it's committed." For big jobs, ask for it in slices, so each merge is small.
- Then subscribe (`notify_when_idle`).
