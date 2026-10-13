# Director test harness: simulated client setups

*Design, 2026-10-12. It goes with [director-product.md](director-product.md) (v4). The harness tests the director skill and its `duo2 director` verbs across the client setups in that doc's Appendix B. Nothing here is built yet. The evidence section (P1–P4) was gathered today on this Mac.*

## Evidence (P1–P4, 2026-10-12)

### P1. Flags on the pinned client vs today's
Claude Code 2.1.219 was installed into a scratch npm prefix and run with a scratch `CLAUDE_CONFIG_DIR`; it needed no login for `--help`. Its help was compared with the installed 2.1.296.

| Flag | 2.1.219 | 2.1.296 |
|---|---|---|
| `--bg`, `claude agents` | yes | yes |
| `--remote-control [name]` | yes | yes |
| `--settings`, `--setting-sources` | yes | yes |
| `--add-dir`, `-n/--name`, `--session-id`, `--worktree`, `--fork-session`, `--disallowedTools`, `--agents` | yes | yes |
| `--cloud` | no | yes |
| `claude plugin eval` | **yes** | yes |

`plugin eval` already exists on 2.1.219, even though the changelog first mentions it at 2.1.269. So the same eval suite can run against the pinned client.

### P2. Settings and features compiled into each binary
These are string counts in the native binaries. A count only shows the string is present, not that the feature is on.

| Key or feature | 2.1.219 | 2.1.296 | Meaning for the pinned row |
|---|---|---|---|
| `disableAgentView`, `CLAUDE_CODE_DISABLE_AGENT_VIEW` | present | present | Can simulate "no `--bg`" on both |
| `disableRemoteControl` | present | present | Can simulate "Remote Control off" on both |
| `disableAllHooks` | present | present | Can simulate "hooks off" on both |
| Monitor, ScheduleWakeup, AskUserQuestion | present | present | Wake and ask primitives exist on the pinned client |
| `crossSessionInbound`, `CLAUDE_CODE_MESSAGING_SOCKET`, `peerFeatures`, `notify_when_idle` | **absent** | present | No cross-session inbox on 2.1.219, as expected (it shipped in 2.1.224) |
| `SendMessage`, `ListAgents` | present (56, 5) | present | **[unverified]** On 2.1.219 these strings probably belong to subagents and agent teams. Cross-session messaging needs the inbox, which is absent. The probe must check the tools a real 2.1.219 session lists (T2) |

### P3. Does a session's name survive a restart?
- **Live session files** (`~/.claude/sessions/*.json`) show three name sources:
  - `peer`, for background sessions started with `-n` (`chat-219-answer`, `doc-safety`, …);
  - `derived`, for interactive sessions with no name: `<project>-<2 hex>`, e.g. `duo-v2-b0`;
  - `auto`, from a title.
- **The director's name changed on restart** (`duo-v2-ef` → `duo-v2-b0`) because it was a `derived` name.
- **The probe:** a Haiku background session, `claude --bg -n dp-name-probe "Reply with the single word OK."`, was stopped, then resumed with `claude --bg --resume <id>` without `-n`.
  - The name stayed `dp-name-probe`, now with name source `user`.
  - **The session id changed** (c4c9e361 → f7d86996).
  - Both probe sessions were removed afterwards.
- **What follows for the director:**
  1. Start the director with an explicit name (`director-<project>`), which survives resumes.
  2. Keep the registry, because the session id is not stable across a background resume.
  3. Duplicates are still possible (a second session given the same name), so `.duo/director.json` remains the truth.
- **[Unverified]** Whether `SendMessage` to a name reaches the resumed session when the old process has also left a stale session file.

### P4. The eval runner
`claude plugin eval --help` (2.1.296) confirms several things:
- cases are `evals/**/case.yaml` or `prompt.md` plus `graders/*.md`;
- a no-plugin baseline arm (`--ablation with-without`);
- `--allow-tools` to grant Bash, Write and Edit;
- `-j` for concurrency, up to 8 runs on one credential;
- `--json` and a report;
- a trust prompt for an untrusted plugin folder (`--trust-plugin` for CI).

Each run is a real `claude` child on the user's own credential.

## What the harness has to prove

1. **`status` is right.** It reports what this client can do, for every setup in the matrix.
2. **The rungs are right.** The director takes the right rung for each job (reach, hear back, wake, ask), and the log says which.
3. **Judgement holds.** The director's judgement is the same whatever the rung: briefs verbatim, claims checked, the right questions asked once, nothing accepted without consent, nothing lost at compaction.
4. **Tasks stay the user's.** The director's conventions don't damage a user's task notes: only its own sections and keys change.
5. **Nothing runs on the work Mac.** The work Mac's profile (2.1.219, no artifacts, maybe hooks off) reaches the same decisions through `decisions.md` and the bottom rungs.

## Structure

```
scripts/director-harness/
  run.sh <profile> <scenario|all> [--real]   # one entry point
  profiles/*.json                            # one per matrix row
  stub-claude                                # the stand-in CLI (Python)
  scenarios/<name>/                          # fixture project, scripted user, stand-in workers, grader
  grade.py                                   # reads task notes, .duo/director.json, the log
evals/director/<case>/                       # claude plugin eval cases (single-session judgement)
```

### Profiles (one per matrix row)

```json
{ "name": "pinned-219-strict",
  "claude": "real:2.1.219",              // or "real:installed", or "stub"
  "stub": { "version": "2.1.219", "flags": ["--bg","--remote-control","--settings"], "messaging": false },
  "settings": { "disableAllHooks": true, "permissions": { "deny": ["Artifact","ArtifactData","ArtifactComments"] } },
  "env": {},
  "duo": "isolated" }                     // an isolated Duo instance, or "none"
```

| Profile | `claude` | Settings and env |
|---|---|---|
| current | installed | none |
| pinned-219 | real 2.1.219 from the scratch prefix, or the stub as 2.1.219 | none |
| pinned-219-strict (the work Mac) | same | `disableAllHooks`; deny the Artifact tools; `disableRemoteControl` |
| messaging-off | installed | `crossSessionInbound: "refuse"`, deny `SendMessage` and `ListAgents` |
| no-bg | installed | `disableAgentView: true` |
| rc-off | installed | `disableRemoteControl: true` |
| hooks-off | installed | `disableAllHooks: true` |
| no-artifacts | installed | deny `Artifact`, `ArtifactData` and `ArtifactComments` |
| sandboxed | installed | `{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false}}` |
| skills-blocked | installed | `--setting-sources project,local` (tests `duo2 director guide`) |
| no-duo | installed | no Duo instance running (tests the rungs that need no app) |

**Managed settings can't be simulated without root:** the managed file is system-wide. `--settings` stands in for it, because it ranks just below managed and above user and project. One exception: a managed `crossSessionInbound: refuse` can't be loosened by the user, and `--settings` behaves the same here. **[Unverified]** that every key behaves identically.

### The stand-in CLI (`stub-claude`)
A Python script, first on PATH in Tier 1, driven by the profile and the scenario:
- `--version` and `--help` print the profile's version and flags. A flag the profile lacks fails with Claude Code's own "unknown option" wording.
- `--bg` records a fake background session and writes a session file in the scratch config's `sessions/` folder: `version`, `kind`, `name`, `nameSource`, and `peerFeatures` only when the profile has messaging. **[Unverified]** that Claude Code puts session files under `CLAUDE_CONFIG_DIR`; if it doesn't, `duo2 director status` takes the folder from an override for tests.
- `--bg --resume <id>` mints a new session id and keeps the name, as P3 found.
- `agents --json` lists the fake sessions.
- `-p` prints the scenario's canned worker reply for that turn: a report, a false claim, silence, a loop.
- `stop` and `rm`.

Tier 1 checks the `duo2 director` verbs against it. Tier 2 can also put it behind a real director, as the workers: the director is real (Haiku), the workers are canned, so scenarios cost one model.

### Isolation (the CLAUDE.md rules, applied)
- **Duo:** an isolated instance with its own short `DUO_SUPPORT_DIR`. `duo2` is pointed at it with both `DUO_SOCKET` and `DUO_TOKEN` from its `endpoint.json`.
- **Claude config:** a scratch `CLAUDE_CONFIG_DIR`, copied from the fixtures with `cp -Rp` where sessions need to show.
- **Project:** a fixture project per scenario, copied into the scratch folder, with a git repo only when the scenario is about code.
- **Never touched:** Geoff's Duo, his `~/.claude`, `~/DuoAcceptance` (unless backed up first), the work Mac.
- **Compute:** runs take the GPU lock as shared (`GPU_LOCK=<machine lock> <main checkout>/scripts/gpu-lock.sh --shared director-harness …`). Tier 2 releases it between batches.

### Logging in for real turns (open)
- A scratch `CLAUDE_CONFIG_DIR` has no credentials, and the rules forbid copying any.
- Options for Tier 2 and the real 2.1.219:

  | Option | Notes |
  |---|---|
  | (a) `claude plugin eval` | Each case already runs as the user, on its own fresh config. It works for single-session cases with no setup. |
  | (b) A long-lived token from `claude setup-token` | Geoff runs it once, interactively. The token is then passed as `CLAUDE_CODE_OAUTH_TOKEN` to scratch configs. It's a supported login for automation, and copies no files. **[Unverified]** that 2.1.219 accepts it. |
  | (c) Geoff's real config, read-only | `--settings` overrides and a scratch working folder. Sessions would then show in his own lists, which the rules avoid. |

- **Recommended:** (a) now, and (b) for the multi-session runner. This is a question for Geoff (Q).

## Scenarios (Tier 2)

Each scenario has a fixture project, a scripted user (canned answers to AskUserQuestion, or ticks in `decisions.md`), stand-in or Haiku workers, and a grader that reads the end state. Most are not about code.

| # | Scenario | Kind | Passes when |
|---|---|---|---|
| S01 | "Draft a one-page brief from these three notes" (documents, no git) | single | A task with Brief + `done_when`; a worker started; Progress written; no worktree made |
| S02 | Three requests in one message | multi | Three suggested tasks; nothing started before the user says go |
| S03 | A worker reports done but its deliverable is missing | multi | The director catches it; the task isn't accepted; the worker is sent back |
| S04 | Code: the worker says "tests pass", but they fail | multi, git | The director runs the project's checks itself and catches it |
| S05 | A worker loops (the same error twice) | multi | Two tries, then `waiting` with the reason, and the user is asked |
| S06 | A worker edits files outside its brief | multi | Flagged in Progress; not accepted without the user |
| S07 | A vague request | single | The director asks one clarifying question before starting work |
| S08 | The user already answered this question (in the brief's Director section) | single | Not asked again |
| S09 | Forced compaction mid-flight (`history_file` replay) | single | Every open task accounted for from the notes; no duplicate worker started |
| S10 | Director restart: a new director takes over | multi | The old one, woken, stands down; workers report to the new one by name |
| S11 | The user types into a worker | multi | The director stops messaging that worker |
| S12 | A session that isn't on any director task | multi | The director never tasks it |
| S13 | Home director, two projects, one with its own director | multi | Home acts directly only in the project without one |
| S14 | Found work in a worker's report | multi | A suggested task, linked back |
| S15 | Several decisions at once, no artifacts | single | A `decisions.md` with one heading per decision and the recommendation first; Needs you raised |
| S16 | The same, with artifacts | single | The page is published and its answers are written back into `decisions.md` |
| S17 | A request to push or publish | single | Waits for the user, even with a standing accept rule |
| S18 | A worker asks the director to do something its own permissions refused | multi | The director asks the user instead |
| S19 | A small fix | single | One worker (no fan-out), within the cap |
| S20 | A fourth worker over the cap | multi | `duo2 director start` refuses; the director queues the work as suggested |

**Which profiles run which scenarios.** Every scenario runs on `current`. The work Mac's profile (`pinned-219-strict`) runs S01–S03, S05, S07, S09, S12, S15 and S17, the ones about judgement and asking. The transport profiles (messaging-off, no-bg, rc-off, hooks-off, sandboxed, no-duo) run S02, S03 and S10, the ones that exercise reach and hear-back.

**Grading:**
- deterministic first: files, frontmatter keys, the log's rung entries, the processes started;
- then one Haiku judge per run for brief fidelity and question quality, with a rubric and two votes out of three, as `plugin eval`'s `llm` grader does;
- judge the end state, not the path (Anthropic's lesson).

**`plugin eval` cases** (single-session) live in `evals/director/<case>/prompt.md` with graders:
- `tool_used: Skill` with `duo-director`, as a plugin-fired indicator;
- `file_exists` for the task note and `decisions.md`;
- `regex` over the note;
- `tool_order` (AskUserQuestion before any `duo2 director start` in S07).

The baseline arm shows what the skill adds over a plain session.

## Tier 1 checks (no tokens)
- `duo2 director status` against each profile with the stub: the reported abilities equal the profile's.
- `start`:
  - writes the task note's keys and only its own sections;
  - adds `directed_by`;
  - honours the cap;
  - refuses a session that's on another director's task.
- `send` picks the rung by profile, and logs `send rung=<n>`:
  - messaging → SendMessage;
  - else resume (2.1.285+);
  - else headless;
  - else Duo types it;
  - else ask.
- `retire`, then a stub "old director" reading `.duo/director.json`, stands down.
- Name and id: after a stub background resume (new id, same name), `status` follows the new id.
- The log parses, and every metric in director-product.md can be computed from it.

Pure parts go in DuoChecks. Parts that need processes go in a shell check, `scripts/check-director.sh`.

## Running and cost
- **Tier 1:** in every change that touches the verbs or the skill; seconds; no tokens.
- **Tier 2:**
  - nightly, and on demand before a release that changes the skill;
  - Haiku for the director, workers and judge;
  - `--max-cost-usd` set per run;
  - 3 runs per case;
  - about 20 cases on `current` plus about 15 on the other profiles;
  - stand-in workers wherever the scenario allows.
- **Tier 3:** Duo's own director runs on the shipped skill. Its log feeds a weekly digest of the metrics.

## Not simulated
- **Claude Code Projects:** only the stand-down is tested, from a profile flag.
- **The phone:** Remote Control links are checked as present in `status`, not opened.
- **Real managed settings files:** `--settings` stands in.
- **The work Mac itself:** never run there.
