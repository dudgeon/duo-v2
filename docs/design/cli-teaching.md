# How Claude sessions learn `duo2` (DL-74)

2026-10-04. Geoff: "review how legacy handles this, scrutinize, and then recommend some approaches; we likely do need a managed block in the user Claude.md and other things that legacy does; we likely need the install and update loop."

## What legacy does, and how it went

Legacy has six layers. Sources are in the legacy repo (`/Users/geoff/repos/duo`).

| Layer | What it is | What happened |
|---|---|---|
| `claude` wrapper | `~/.claude/duo/bin/claude`, first on PATH in Duo's terminals. When `DUO_SESSION` is set, it adds `priming.md` (about 450 tokens) with `--append-system-prompt`. | It worked. The path to the real `claude` was fixed at install time, so it broke if Claude moved. Adding the folder to the shell rc for outside terminals spread that risk to every terminal. (`install-service.ts:997-1029`, `cli/duo.ts:3828`) |
| SessionStart hook | Prints `priming.md` again. | A deliberate "safety net" that doubled the always-on cost. ENH-203 called it a defect; it was never fixed. An untagged leftover copy once tripled it (BUG-150). |
| Managed block in `~/.claude/CLAUDE.md` | About 260 words between `<!-- duo:managed-v… -->` and `<!-- duo:end -->`. It points to the skill, the subagent and troubleshooting docs. | Added because **sessions started outside Duo didn't know Duo existed** (ENH-088). It loads into every Claude session on the machine. "Edit freely" was untrue: edits are overwritten on the next install. A sticky flag records that you removed it; lose the flag and the block comes back. |
| Global skill and subagent | The skill is 446 lines (cut to 252, then grew back). The subagent is a 9,260-word Haiku agent. | In a fresh-Claude test the skill found the right verb 9 times out of 9. The subagent saved tokens but drifted (verbs it couldn't reach). |
| PreToolUse guard | Warns when Claude uses Edit/Write on a file open in Duo. | A patch over missing verbs. The real fix was adding them (ENH-195). |
| Install and update loop | A banner when the app version changes; you click Install or Update. | `priming.md` was only written if it was missing, so **fixes never reached installed users**. The shipped installer copied files that no longer existed and missed newer ones; only the dev `sync:claude` was right. There was no uninstall. The consent banner didn't mention the `settings.json` or `CLAUDE.md` edits. |

The root cause, in legacy's own audit (ENH-203): about 256 hand-written entries across 4 places, with no generation, so the always-on text taught verbs that didn't exist (`duo files`, `duo html update`).

**What made Claude actually use the CLI** (legacy has no evals; this is what its record shows):
1. Verbs for everything, so Claude never had to go around the CLI.
2. The key rule in the always-on layer, not only in an on-demand skill.
3. A short, well-structured skill.

## Where v2 is today

- Sessions Duo starts or resumes get a primer through `--append-system-prompt`, generated from the command table, so it can't drift (DL-15).
- `duo2` is on PATH only inside Duo's terminals.
- Nothing is installed into `~/.claude` (LR-55).
- Shell tabs where you type `claude` yourself get no primer: DL-8's auto-promote isn't built.
- Sessions started outside Duo (Terminal, an IDE) know nothing about Duo and can't run `duo2`.

## What v2 should keep from legacy, and what it should fix

- **Generate every piece from the one action registry (DL-72)**: the primer, the block, the skill, `duo2 help`. A check fails the build if any of them names a verb that doesn't exist.
- **Rewrite everything Duo owns at every launch, idempotently.** Never "write only if missing". A file whose hash no longer matches what Duo wrote was edited by you: leave it alone and say so in `duo2 doctor`.
- **One manifest of what was written** (`App Support/Duo/installed.json`). `duo2 uninstall` removes exactly what it lists and restores what it changed. Your edits outside Duo's markers are never touched.
- **Markers distinct from legacy's** (`<!-- duo2:begin v… -->` … `<!-- duo2:end -->`, a `_duo2` key). Legacy's regexes and v2's legacy detector must not match them. Legacy's "restore" copies whole files back; v2's restore must not undo v2's own entries.
- **No global `claude` wrapper.** Stale-path breakage is the risk. Inside Duo, the primer is already passed directly. For shell tabs, a wrapper that resolves `claude` when it runs can live in Duo's own `Helpers` folder, which is on PATH only in Duo's terminals.
- **No SessionStart double injection, no subagent, no edit guard.** Parity (DL-71) removes the reason for the guard.
- **Consent that names every file and line Duo will change**, asked once, and repeated only when that list changes.
- **Side-by-side builds:** the newest version owns the files. An older build never downgrades them.

## Approaches

**A. Minimal.** As today, plus the in-Duo `claude` wrapper for shell tabs. Nothing outside Duo knows about it. Zero footprint. Sessions started elsewhere miss out, which is legacy's ENH-088 gap.

**B. Block plus `duo2` on PATH.**
- A: everything above.
- B: a **small** block (about 60 words, always loaded): "Duo may be running. If so, `duo2` reaches it: run `duo2 help` for what it can do; prefer it for anything about projects, sessions or open documents."
- C: a stable `~/.local/bin/duo2` link to the app's `Helpers/duo2`, re-pointed at every launch.

Outside sessions can then reach Duo: `duo2` reads the endpoint file when the environment doesn't carry it, and from a sandboxed session outside Duo it needs the socket allowance that Duo's own sessions get through `--settings`. `duo2 doctor` explains that.

**C. B plus a generated skill** (recommended). `~/.claude/skills/duo2/SKILL.md` is generated from the registry at every launch. It is short: when to use which family, then a pointer to `duo2 help <family>` for details. That is legacy's one proven layer, without its drift.

Recommendation: **C**, with the install loop and principles above. It revises LR-55 (install nothing) and extends DL-15.
