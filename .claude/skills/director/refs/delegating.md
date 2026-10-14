# Delegating to build sessions

*Part of Duo's own director (`../SKILL.md`): Duo dev's habits on top of the shared duo-director core. Moved here unchanged from the single SKILL.md on 2026-10-14.*

## 1. Taking work from Geoff

- **A feature or bug goes to a NEW session,** never to your own edits (Geoff, 2026-10-06). Small follow-up fixes found in review can go back to the session that built the thing, or to an `Agent` with `isolation: worktree`.
- **Settle the scope first** if it's ambiguous: AskUserQuestion with buttons and your recommendation first. Geoff can't use document dropdowns. He often answers design choices by commenting on the Design canvas, so tell design sessions to act on comments.
- **Pick the model by the job** (CLAUDE.md, Model efficiency): a scoped build or fix starts on Sonnet (`claude --bg --model claude-sonnet-5-5 …`); a design study or research session starts on Opus (Duo's default, or `--model claude-opus-5-5`); test-only work on Haiku. When I run checks or sweeps myself, I use scripts or Haiku subagents (`Agent` with `model: haiku`).
- **Start the session outside Duo, as a background Claude session with Remote Control** (Geoff, 2026-10-07: "make all of these sessions, and all going forward, available for remote control unless I specify to run them on duo"). From the repo root: `cd /Users/geoff/repos/duo-v2 && claude --bg --remote-control "<short name>" -n "<short name>" "$(cat <brief file>)"`. It prints a short id; `claude agents --json` lists them, `claude logs <id>` shows output, `claude stop <id>` / `claude rm <id>` end them. Geoff follows them in the Claude app, and they survive Duo restarts and test builds. Find its peer name for SendMessage in `ListAgents` (kind `bg`). **Exception:** a session that must publish its own page, so Geoff's taps reach it, starts in Duo with `duo2 session new --project duo-v2 --remote-control <name> --prompt "$(cat <brief>)"`. Background sessions have no Artifact tools (F-259).
  - **Design work runs in Duo** (Geoff, 2026-10-07): background sessions don't get the Artifact/Design canvas tools (the director, in Duo since DL-166, does), so any session with a design round (a canvas, boards for Geoff) starts with `duo2 session new --project duo-v2 --remote-control "<name>" --prompt "<brief>"`. A background session that turns out to need a canvas: `claude stop <id>`, then `duo2 session open <id>` resumes it in Duo.
  - **Run other sessions in Duo only when Geoff says so, or when the job needs it** (e.g. testing Duo's own session UI live, or something that needs Duo's terminal environment). Then tell Geoff why before starting it, and use `duo2 session new --project duo-v2 --remote-control "<short name>" --prompt "<brief>"` (DL-128).
- **The brief must include:**
  - "Read CLAUDE.md first", plus the CLAUDE.md rules that matter for the job (never invent a design; build to the screens and prove it; the DL-71 duo2 verb; Xcode-free; generated tokens);
  - Geoff's words, quoted;
  - the work tree: `git worktree add .claude/worktrees/<x> -b <branch> origin/main`, never commit on main;
  - **reserved record numbers** (DL, F, Q, C, ENH), taken after checking main and every branch, and different for each parallel session;
  - which other sessions are working where (stay out of their files);
  - how to prove it (DuoChecks, `scripts/bundle.sh`, `NO_BUILD=1 scripts/check-ui.sh`, captures against the boards, the relevant check scripts);
  - isolation for every scripted run (its own short `DUO_SUPPORT_DIR`, a scratch `CLAUDE_CONFIG_DIR`, no Google account, no real Claude turns except an approved real-login test, and any that run use Haiku 5.5 through DUO_MODEL or ANTHROPIC_MODEL);
  - **no focus stealing** (Geoff, 2026-10-08): test launches run in the background; any run that shows a window or takes focus (DUO_TEST_FOREGROUND=1, visible gates) needs Geoff's OK first, asked by AskUserQuestion with a warning of what will appear and for how long. The session asks through the director, or Geoff directly if he talks to it;
  - **models** (Geoff, 2026-10-08; CLAUDE.md, Model efficiency): Opus 5.5 plans (design, research, root-causing); Sonnet 5.5 executes well-scoped tasks (builds against an approved handoff, known-cause fixes); Haiku 5.5 runs tests and validation (test turns, check runs, sweeps). Say which in the brief, and tell the session to hand scoped parts and test loops to Sonnet and Haiku subagents. Never put model choice into Duo's code;
  - for design work: a Design canvas with the Duo design system, every mark [P], one AskUserQuestion round, and a handoff exported to `docs/design/<x>-handoff/`;
  - "Don't publish the design-system artifact or the walk page" (the director is their only publisher, DL-166);
  - "Message <the director's peer name, from your `ListAgents` first line, e.g. duo-v2-b0> (SendMessage) with the branch, the full shas, the records and the checks when it's committed." For big jobs, ask for it in slices, so each merge is small.
- Then subscribe (`notify_when_idle`) and log a row in the reviews doc.
