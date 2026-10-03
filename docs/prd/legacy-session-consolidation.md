# PRD — Legacy Session Inventory and Consolidation ("taming the backbook")

> **Status:** Draft v0.1, 2026-10-03. Standalone requirements document. Written to be lifted into a broader Duo v2 product plan without edits to its substance.
> **Owner decisions:** four scoping answers locked via AskUserQuestion on 2026-10-03 (§ 4 L1–L4). Four further decisions are author recommendations awaiting owner confirmation (§ 4 R1–R4); the document is written assuming the recommendations hold, and each is isolated so it can be flipped.
> **Evidence base:** official Claude Code docs and changelog as of CLI 2.1.288, 20+ GitHub issues, five community relocation tools, a strings-level read of the installed 2.1.288 binary, a controlled resume experiment on 2.1.288 (Appendix A), and a code audit of Duo v1 (`dudgeon/duo` v0.13.8). Citations in Appendix C.
> **Version caveat:** the on-disk format and resume semantics changed at least seven times between 2.1.94 and 2.1.251. Every mechanical requirement in § 7 is version-gated (§ 11). Treat any statement here as true of 2.1.223–2.1.288 unless it says otherwise.

---

## 1. Problem

A Claude Code user accumulates sessions the way a desk accumulates paper. Each `claude` invocation writes a transcript under `~/.claude/projects/<encoded working directory>/<session-id>.jsonl`. The bucket a session lands in is decided by the directory the user happened to be in, not by any notion of what the work was about. Over months this yields:

- Dozens of buckets for what the user thinks of as a handful of projects. The v1 reference machine had 41 raw buckets, 844 MB of transcripts, roughly 20 distinct roots after rollup, and 6 to 12 "real" projects (v1 ENH-212 PRD § 2).
- Buckets for scratch directories, `~/Desktop`, `~/Downloads`, `$HOME` itself, deleted worktrees, and renamed folders. Sessions in a renamed folder look lost because the bucket name no longer matches any directory on disk.
- Related work scattered across buckets: the same feature pursued from the repo root, from a subdirectory, and from a worktree lands in three buckets.
- No way to say "these eleven sessions were the auth refactor" and keep them together.

The hard constraint underneath all of this: **a transcript's location is derived from a path, and resuming a session has historically required being in that path.** Move the folder and you sever the link between the session and its transcript. v1 Duo read this storage faithfully and surfaced it well (Home, Catch-up, the project rail), but never moved, grouped, archived, or re-attributed anything. It inferred a session's project from the recorded `cwd` and stopped there (Appendix D).

Duo v2 makes projects first-class and nests sessions inside them going forward. This document covers the other half: taking the existing mess, letting the user curate it into intentional projects, and doing so without breaking the user's ability to resume any session.

---

## 2. Goals and non-goals

### Goals

1. **Inventory.** On every launch, build a complete, live, trustworthy picture of every session on the machine: where it is, what it was about, when it last moved, whether a process holds it, whether its folder still exists, and whether its storage is in a degraded state (collision, duplicate id, stale index).
2. **Curation.** Give the user a manual curation surface to assign legacy sessions and buckets to intentional projects and to named task groups inside those projects. No automatic clustering; good sorting, filtering, and multi-select instead (L3).
3. **Resumability is sacred.** No action Duo offers may leave a session unresumable, and no action may create a second copy of a session id anywhere under `~/.claude/projects` (§ 6.3).
4. **Tandem moves.** When a user wants the folder itself moved or renamed, Duo offers to do it and moves folder, transcripts, and path-keyed settings as one journaled, verifiable, reversible transaction (L1, R2).
5. **Retire noise.** Archive and delete dead sessions with full visibility into what goes, and protect anything the user keeps from Claude Code's own retention sweep (R4).
6. **Ongoing, not one-shot.** New sessions created outside Duo (bare terminal, IDE extensions, Desktop) keep appearing in an Unsorted inbox so the backbook never regrows unnoticed.

### Non-goals (this PRD)

- Automatic topic clustering or LLM-generated consolidation proposals (L3). Sorting by recency, size, root, and liveness is in scope; "these look related" is not.
- Content-level merging of two source trees into one. "Merge" here means moving one folder to live inside another project's root (§ 7.5.6).
- Cross-machine sync of sessions or of Duo's registry.
- Consolidating Claude Code's per-directory auto memory (`projects/<bucket>/memory/`). Flagged in § 10 as a follow-on.
- Replacing Claude Code's native `/resume` picker. Native parity is a stated benefit of one optional operation (§ 7.4), not a requirement of the system.
- Cloud sessions (`claude.ai/code`) and their teleport flow. Those have server-side identity and are not backbook.

---

## 3. Users and scenarios

Single persona: a heavy Claude Code user on one machine who has been working for months without a project discipline and now adopts Duo v2. Scenarios the design must handle, each referenced later by its tag:

| Tag | Scenario | What "good" looks like |
|---|---|---|
| S-RENAMED | `~/Desktop/foo-test` was renamed to `~/projects/foo` months ago. Bucket `-Users-me-Desktop-foo-test` still holds 30 sessions. | User sees the bucket flagged "folder missing", assigns it to project `foo`, every session resumes from `~/projects/foo`. |
| S-SCATTER | Project `foo` has sessions in the root bucket, in `foo/packages/api`, and in two worktrees. | All four buckets roll up under `foo` (one project, one root). Sessions keep their original cwd for resume. User groups eleven of them into task group "auth refactor". |
| S-TRASH | 60 one-prompt sessions in `~`, `~/Downloads`, and `/tmp/x`. | Sorted by size and age, bulk-selected, archived or deleted in one confirmed action. |
| S-MOVE | User wants `~/Desktop/foo-test` (still exists) moved to `~/projects/foo`. | Duo offers the move, previews every file operation, executes folder + transcripts + settings in tandem, verifies, and offers undo. |
| S-LIVE | A terminal outside Duo currently runs `claude` in a bucket the user is curating. | The live session is marked, and any physical operation on it is refused until it ends. Pointer attribution still works. |
| S-COLLIDE | `~/work/my-project` and `~/work/my_project` both exist. Both encode to the same bucket. | Duo detects two distinct recorded cwds in one bucket, attributes each session by its own cwd, and warns before any physical operation touches the bucket. |
| S-OLDCLI | User's Claude Code is 2.1.150. | Duo detects the version, disables cross-directory resume by id, and falls back to resuming in the session's original cwd (v1 behavior) with an upgrade nudge. |
| S-RETAIN | `cleanupPeriodDays` is at its default of 30. | Duo shows what will be swept in the next 7 days and offers to archive it or raise the setting. |

---

## 4. Decisions

### Locked by owner (2026-10-03)

| # | Decision | Outcome |
|---|---|---|
| L1 | Scope of "consolidate" | Re-home session logs; archive or delete dead sessions; **and** offer folder moves, performed by Duo so that folders and logs move in tandem and connections are never broken. |
| L2 | Shape of a project | **One root directory per project**, with named **task groups** inside it. Worktrees and subdirectories belong to the enclosing project. |
| L3 | How groupings are proposed | **Manual curation only.** Rich sort and filter; no automatic proposals. |
| L4 | Safety posture | Owner asked for a research-backed recommendation, with two hard constraints: never duplicate session logs in ways that create new problems, and prioritize clustering related sessions while preserving resumability. Answered by R1 below and § 6. |

### Recommended by author, pending owner confirmation

| # | Decision | Recommendation | If flipped |
|---|---|---|---|
| R1 | Pointer vs physical move | **Pointer by default; physical relocation only when the path actually changes** (folder move or merge) or on explicit request. Rationale § 6.1. | "Always move": § 7.4 becomes mandatory on every re-home and the cwd-rewrite truthfulness problem (§ 6.1) must be accepted. "Never move": § 7.4, § 7.5 and R4's move-to-archive are cut; retention protection becomes a settings nudge only. |
| R2 | Who executes a move | **Deterministic migrator in Duo.** A Claude session may propose and explain a plan; it never performs the file operations. Rationale § 6.4. | A skill-driven agent executor needs the same journal and invariants, exposed as a `duo migrate` CLI; the agent is then one caller of it. |
| R3 | Where Duo's metadata lives | **A registry under `~/.claude/duo/` keyed by session id.** Nothing written into project folders. Rationale § 8. | In-folder manifests require a reconciliation story when the manifest and the registry disagree, and they re-introduce the sidecar drift v1's § D9 rule guards against. |
| R4 | Meaning of "archive" | **Preserve:** move out of Claude Code's sweep path into a Duo-owned archive, read-only, restorable. Rationale § 6.5. | "Hide only" is a registry flag and loses sessions to the sweep. "Delete" collapses § 7.6.1 into § 7.6.2. |

---

## 5. Research findings: how Claude Code binds sessions to folders

This section is the factual substrate for everything that follows. Each item carries a confidence and the version it was verified against.

### 5.1 Storage layout

- **Bucket name.** The absolute working directory, symlink-resolved, with **every character outside `[A-Za-z0-9]` replaced by `-`**. `/Users/me/proj` becomes `-Users-me-proj`. Names over 200 characters are truncated and suffixed with a hash whose algorithm is undocumented. *Official docs; high confidence.*
- **The encoding is lossy and collisions are real.** `/a/b-c`, `/a/b/c`, `/a/b_c`, `/a/b.c` all share one bucket. Non-ASCII path segments collapse to runs of dashes. Anthropic has closed collision reports as "not planned" at least five times (issues #7009, #21085, #35162, #40946, #93743). v1 Duo's encoder only replaced `/` and `.`, so it looks in the wrong bucket for paths with underscores or spaces (Appendix D). *High confidence.*
- **Per-session files.** `<id>.jsonl` (main transcript); `<id>/subagents/agent-<id>.jsonl` (sidechains; older 2.0.x builds wrote these as siblings in the bucket); `<id>/tool-results/` (large outputs); `<id>.jsonl.superseded-<ts>` and `<id>.orphaned-<ts>-<suffix>.jsonl` (set-aside copies written since 2.1.251 instead of overwriting); `<id>/ccr-tip.json` (remote-session sync tip, observed locally). *Official docs plus local observation; high confidence.*
- **Per-bucket files.** `memory/` (auto memory, never swept); `sessions-index.json` (an undocumented cache with `sessionId, fullPath, fileMtime, firstPrompt, summary, messageCount, created, modified, gitBranch, projectPath, isSidechain`; contains absolute paths; repeatedly observed stale or empty, issues #24729, #25032, #22205). *Community sources; medium confidence on schema.*
- **Every record** carries `type, uuid, parentUuid, timestamp, sessionId, cwd, gitBranch, version, isSidechain, userType`. Non-message record types include `summary` (with `leafUuid`), `custom-title` (from `/rename`, last one wins), `ai-title`, `file-history-snapshot` and `file-history-delta` (which embed `realParentDir` and `trackingPath`), `attachment` (whose `snapshot.workingDirectory` is a path), `last-prompt`, `queue-operation`, `permission-mode`, worktree binding records. *Verified on the live 2.1.288 transcript in this session; high confidence.*
- **A single transcript can contain mixed `cwd` values.** Resuming from another directory appends records carrying the new cwd to the same file (Appendix A). So "the session's cwd" is really "the session's first cwd" and "the session's latest cwd", and they can differ.

### 5.2 Resume semantics by version

| Entry point | Behavior (2.1.223+) | Older behavior |
|---|---|---|
| `claude --continue` | Most recent session **in the current directory's bucket only.** Verified: did not find a session stored under a sibling bucket (Appendix A, test 3). | Same. |
| `claude --resume <id>` | Searches the current bucket and its git worktrees, then **every other bucket on the machine, succeeding only if exactly one other bucket holds a transcript with messages for that id.** A hand-copied duplicate yields "not found" by design. Verified cross-bucket on 2.1.288: resumed, appended in place to the original file with new records carrying the new cwd (Appendix A, test 2). | Before 2.1.223: current bucket and worktrees only; otherwise `No conversation found with session ID` (issues #5768, #27473, #58591). |
| `claude --resume <absolute path to .jsonl>` | Resumes that file regardless of location. | Not available on older builds; exact introduction version not pinned. |
| `claude --resume` / `/resume` picker | Default scope is the current worktree plus sessions that `/add-dir`'d the current directory. `Ctrl+W` widens to all worktrees of the repo; `Ctrl+A` to every project. Picking a session from another project copies a `cd … && claude --resume` command to the clipboard rather than resuming; if that directory no longer exists, it resumes in the current one (2.1.239). **Since 2.1.239 the picker filters colliding buckets by the recorded cwd**, so a transcript whose `cwd` fields do not match the directory is hidden from that directory's picker. | 2.1.94 to 2.1.108: scope flip-flopped between worktree-only and all-projects. |
| `/cd <path>` (2.1.169+) | Relocates the **live** session's storage to the new directory's bucket; stays out of the old picker after 2.1.196; 2.1.251 fixed a silent overwrite when the target bucket already had a same-id file. Not retroactive. | Not available. |
| `EnterWorktree` / `--worktree` | Records a worktree binding in the transcript and relocates storage like `/cd` (2.1.198+). On resume, re-enters the worktree if its git metadata checks out; if the worktree is gone, resumes in the launch directory and records a binding clear. | Each worktree was simply its own bucket. |
| `--fork-session` | New id, copied history, starts in the launch directory. | Same. |
| SDK `resume` | Same lookup as the CLI it bundles. SDKs that bundle an older CLI are cwd-scoped. | — |

*Official docs with changelog version pins; high confidence. The in-place append observed in Appendix A was in `-p` mode; whether interactive resume from another directory additionally relocates the file the way `/cd` does is not documented and is tracked in § 10.*

### 5.3 State keyed by path versus by session id

| Location | Key | Contents | Must move with a folder? |
|---|---|---|---|
| `~/.claude.json` → `projects["<abs path>"]` | path | `allowedTools`, `mcpServers`, `enabledMcpjsonServers`, `hasTrustDialogAccepted`, `hasCompletedProjectOnboarding`, `lastSessionId`, `lastCost`, `exampleFiles`, legacy `history` | Yes (re-key). This file also holds auth and global state; touch only the `projects` key, atomically. Rotating backups in `~/.claude/backups/` keep the old key. |
| `~/.claude/history.jsonl` | path (`project` field per line) | prompt history, plaintext; never swept, grows unbounded | Yes (rewrite lines) if prompt history should follow the folder. |
| `projects/<bucket>/` | encoded path | transcripts, sidecars, memory, sessions-index | Yes. |
| `projects/<bucket>/sessions-index.json` | contains `fullPath`, `projectPath` | cache | Delete and let Claude rebuild, or rewrite. Historically sessions missing from it were invisible to the picker, so deletion is safer than partial rewrite. |
| `<folder>/.claude/settings.local.json` | lives in the folder | local permissions; worktree approvals are saved to the main checkout's copy (2.1.211+) | Travels with the folder for free. |
| `~/.claude/file-history/<sessionId>/` | session id | rewind snapshots; but the transcript's snapshot records embed `realParentDir` | No move; path rewrite inside the transcript if the folder moved, or `/rewind` degrades. |
| `~/.claude/tasks/`, `debug/<sessionId>.txt`, `session-env/<sessionId>/`, `plans/` | session id | portable | No. |
| `~/.claude/sessions/<pid>.json` | process id | **live-session beacon:** `sessionId`, `cwd`, `pid`, `status` (busy/idle), `name`, `startedAt`, `entrypoint`, socket path. Observed on 2.1.288. | No. This is the liveness signal v1 lacked (§ 7.1.4). |
| `~/.claude/todos/`, `statsig/`, `image-cache/` | legacy | no longer written in 2.1.27x | No. |
| `usage-data/session-meta/*.json` | has `project_path` | undocumented | Optional. |

### 5.4 Format stability and retention

- Anthropic's position, verbatim from the sessions page: "The entry format is internal to Claude Code and changes between versions, so scripts that parse these files directly can break on any release." The supported surfaces are `/export`, hooks' `transcript_path`, `claude -p --resume`, and the SDK's `listSessions`, `getSessionMessages`, `renameSession`, `tagSession`. None of those surfaces move anything.
- **Retention sweep.** `cleanupPeriodDays` (default 30, minimum 1, `0` rejected since 2.1.89) deletes at startup: transcripts, superseded and orphaned copies, `subagents/`, `tool-results/`, `file-history/<id>`, `plans/`, `debug/`, `session-env/`, `tasks/`, `shell-snapshots/`, `backups/`. It spares `memory/`, `history.jsonl`, and `~/.claude.json`. Deletion is a hard unlink with no trash (issue #59248). Desktop and Cowork transcripts have a separate `desktopSessionCleanupPeriodDays` (2.1.248). The sweep is by file age, so **copying a transcript resets its clock and rewriting it in place does too unless mtimes are preserved deliberately.**
- `claude purge <path>` (2.1.288) deletes one project's transcripts, memory, tasks, debug, file-history, history lines, and its `~/.claude.json` entry. It is the only official bulk-delete primitive and is path-scoped.

### 5.5 Official and community relocation primitives

Official:

1. `--resume <id>` from anywhere (2.1.223+), subject to the uniqueness rule.
2. `--resume <transcript path>`.
3. `/cd` for a live session; worktree enter/exit for a live session.
4. `CLAUDE_CONFIG_DIR` plus `CLAUDE_CODE_PROJECT_DIR_NAME` (2.1.234+): pins the bucket name independent of cwd, but only when `CLAUDE_CONFIG_DIR` is also set, which relocates the entire config tree. Evaluated and rejected as a Duo mechanism (§ 6.6).
5. `claude purge <path>`.

Community (all unofficial, all parsing the internal format): `claude-mv`, `claudepath`, `claude-move`, `claude-move-project`, `claude-sesh-mover`, plus a widely copied gist. They converge on one recipe: rename the bucket to the new encoding (merging if the target exists), rewrite `cwd` and other absolute-path strings line by line with path-boundary anchoring, re-key `~/.claude.json`, rewrite `history.jsonl`, fix or delete `sessions-index.json`, leave session-keyed directories alone, and back up first. Their issue trackers document the fields they missed as the format evolved: `attachment.snapshot.workingDirectory`, `toolUseResult.persistedOutputPath` and friends, `file-history-snapshot.realParentDir`, `file-history-delta.trackingPath`, and encoded bucket names embedded inside scratchpad and tool-result paths (claude-sesh-mover #127, against 2.1.277).

### 5.6 Hazards specific to a wrapper

- **Inherited session id.** A `claude` process started from inside a Claude Code session inherits `CLAUDE_CODE_SESSION_ID` and writes its transcript under the parent's id (Appendix A, test 3 wrote into the live session's id). Any Duo code path that spawns `claude` must scrub `CLAUDE_CODE_*` and `CLAUDECODE` from the child environment.
- **Credentials override.** `ANTHROPIC_API_KEY` set to a bogus value did not prevent network calls in this environment because host-managed credentials took precedence. Verification steps must not assume a dry run is free.
- **Symlinks.** Symlinked bucket directories stopped being followed by the picker at 2.1.104. Symlinked working directories are realpath-resolved before encoding (`/tmp/x` becomes `-private-tmp-x` on macOS). Symlinks are not a usable relocation primitive.
- **Mid-session `cd`.** v1's liveness check re-encoded a process's current cwd and so marked sessions as closed when `claude` changed directory, leading to a second resume writing to the same file (FOLLOWUP-054). The sessions beacon (§ 5.3) removes the guesswork.

---

## 6. Safety model and the central recommendation

### 6.1 R1: pointer by default, physical move only when the path changes

The owner's constraints (L4) were: no duplication that creates new problems, and clustering plus resumability above all. The research reframes the premise. **On 2.1.223 and later, re-homing a session does not require moving its transcript.** Duo can record "session X belongs to project P, task group T" and resume X from P's root with `claude --resume X`; Claude finds the transcript wherever it is, as long as there is exactly one copy. That is the whole clustering goal with zero writes to internal-format files.

What a pointer does **not** give:

- Native `/resume` parity in the project root for users who also use the bare CLI.
- A truthful bucket layout once a folder has actually been moved (the old bucket name refers to nothing).
- Protection from the retention sweep.

Physical relocation gives those three things at the price of rewriting internal-format files. There is a further subtlety that decides the default: a physical move must rewrite `cwd` to the new bucket's path, and **that rewrite is only truthful if the folder really moved.** Relocating a session from `~/Desktop/foo-test` into `~/projects/foo` while `foo-test` still exists on disk would make the transcript claim it ran somewhere it did not, while every file path the model remembers still points at `foo-test`. Hence:

- **Re-home without a folder move** (S-RENAMED after the fact, S-SCATTER, S-COLLIDE): pointer. Resume runs from the session's own recorded cwd when it still exists, else from the project root (§ 7.7).
- **Folder move or merge** (S-MOVE): folder, transcripts, and settings move together as one transaction (§ 7.5). Here the rewrite is truthful, the target bucket is new or explicitly chosen, and leaving transcripts behind under a dead bucket name would be the misleading option.
- **Explicit "Relocate storage"** (§ 7.4) stays available as an advanced action for native parity, with the truthfulness caveat shown in the confirmation.

Copy-based safety nets were considered and rejected: a copy left anywhere under `projects/` makes `--resume <id>` fail by design, and a copy elsewhere is a backup, which is what the journal (§ 6.3) provides more cheaply.

### 6.2 Why not symlinks, why not `CLAUDE_CODE_PROJECT_DIR_NAME`

Symlinked buckets are no longer followed by the picker (§ 5.6). `CLAUDE_CODE_PROJECT_DIR_NAME` would let Duo name buckets by project instead of by path going forward, but it is ignored unless `CLAUDE_CONFIG_DIR` is also set, which would move the user's entire `~/.claude` (auth, settings, plugins) under Duo's control and break every other client. Rejected for v2; revisit if Anthropic decouples the two (§ 10).

### 6.3 Invariants every physical operation must hold

1. **Uniqueness.** After the operation, each session id appears in exactly one bucket under every configured `projects/` root, or in the Duo archive, never both.
2. **Atomicity per file.** Target written to a temp name in the destination directory, fsynced, renamed into place, source unlinked last. Same-filesystem renames only; cross-filesystem moves are copy, verify by hash, then unlink, and are flagged in the plan.
3. **Write-ahead journal.** The full plan is persisted before the first mutation. Each step records old path, new path, byte size, content hash before and after rewrite, and mtime. A crash leaves a journal that the next launch detects and either completes or reverts.
4. **Liveness guard.** Refuse to touch any transcript whose id appears in a live beacon (`~/.claude/sessions/*.json` with a running pid) or whose bucket is the cwd of any running `claude` process, or any folder that is a cwd of any Duo tab or any process (checked with `lsof`).
5. **Encoder self-calibration.** Before any physical operation, Duo verifies its encoder against the machine: for every bucket that has a readable first `cwd`, `encode(cwd)` must equal the bucket name. One mismatch disables physical operations and reports the offending bucket. This catches a silent encoding change in a new CLI release before it costs the user anything.
6. **Version gate.** Physical operations are enabled only when the installed CLI is within the tested compatibility range (§ 11). Outside it, pointer operations remain available and the UI says why the rest is off.
7. **Mtime policy.** Rewritten transcripts keep their original mtime by default so the retention clock is unchanged and the user's sort order survives. Archive-to-preserve is the one operation that deliberately takes files out of the sweep's reach instead.
8. **Verification before success.** Every moved transcript is re-parsed; every record must parse as JSON; session id uniqueness is re-scanned; a sample of path fields is spot-checked against the plan. Only then does the journal entry flip to `committed`. An optional live smoke test (`claude -p --resume <id> "reply with OK"`) is offered, never run silently, because it costs tokens and emits a model call.
9. **Undo window.** Journals are retained for 30 days or until the user clears them; undo replays the journal in reverse, subject to the same invariants.

### 6.4 R2: a deterministic migrator, not an agent, performs moves

The owner's phrasing was that "the agent should ask the user" and then do the move so folders and logs move in tandem. Two readings exist. Recommended reading: Duo (the harness) is the agent that asks and executes, with a deterministic, tested code path. A Claude session can be the conversational front end that proposes a plan in natural language, but the plan is a data structure that the migrator validates and executes. Reasons: the invariants in § 6.3 are mechanical and must hold every time; an agent performing the operation is itself writing a transcript while rewriting transcripts, which is the kind of reentrancy that produced S-LIVE bugs in v1; and a failure needs a journal, not a conversation log. If the owner prefers the agent-executes reading, the migrator is exposed as `duo migrate plan|apply|verify|undo` on the socket CLI and the agent becomes one of its callers through a skill.

### 6.5 R4: archive means preserve

Claude Code's sweep deletes everything older than 30 days by default, without a trash. A Duo "archive" that is only a flag would leave the user with a tidy list of sessions that vanish on the next CLI start. Archive therefore moves the transcript and its sidecar directory to `~/.claude/duo/archive/<bucket>/<id>…`, which Claude never sweeps, keeps the registry pointer, shows it read-only, and restores by moving it back (uniqueness holds because it is a move). An archived session can still be resumed through `--resume <transcript path>` on the restore path (§ 7.6.1). Delete is separate, explicit, and lists exactly what goes (§ 7.6.2).

### 6.6 Rejected alternatives summary

| Alternative | Why not |
|---|---|
| Always physically move on re-home | Untruthful cwd when the folder did not move; touches internal format on every action; collision risk on merge. |
| Copy, verify, delete later | Duplicate ids break resume by design; the "later" delete is the risky step anyway. |
| Symlink buckets | Not followed by the picker since 2.1.104. |
| `CLAUDE_CODE_PROJECT_DIR_NAME` | Requires taking over `CLAUDE_CONFIG_DIR`. |
| In-folder manifests as source of truth | Sidecar drift; conflicts with registry; v1 § D9. |
| Agent executes file moves | Reentrancy, non-determinism, no journal. |

---

## 7. Functional requirements

Numbering is stable; downstream plans should reference these ids. "Must" is required for the first shippable increment of the feature; "should" is required before the feature is called complete; "may" is a documented option.

### 7.1 Inventory

- **FR-7.1.1** Duo must scan every bucket under `~/.claude/projects/` and under every directory named by `CLAUDE_CONFIG_DIR` (comma-separated, as ccusage does) on launch and on filesystem change (watcher on the projects root, debounced).
- **FR-7.1.2** For each top-level `<id>.jsonl`, the inventory must capture: session id (from filename), first `cwd`, latest `cwd`, `gitBranch` (first and latest), CLI `version` (first and latest), first user prompt (cleaned as v1 did), latest `custom-title`, latest `ai-title`, first and last record timestamps, file mtime, byte size, presence of `<id>/subagents`, `<id>/tool-results`, superseded and orphaned siblings, presence of worktree binding records, and `isSidechain` records (which are skipped as sessions). Head and tail reads only (16 KB each, as v1), never a full parse, for files over a threshold.
- **FR-7.1.3** For each bucket, the inventory must derive: the set of distinct first-cwds observed (more than one means **collision**, S-COLLIDE); whether each cwd exists on disk (**orphan** if not); the resolved project root for each cwd using v1's rollup rule (git root via `.git` file or dir, worktree main repo via the `gitdir:` pointer, else the deepest ancestor holding `CLAUDE.md` or `.claude/`, else the cwd itself; `$HOME` and `/` never qualify); presence and staleness of `sessions-index.json`; presence of `memory/`.
- **FR-7.1.4** Liveness must be computed from `~/.claude/sessions/*.json` beacons (pid alive check plus `sessionId`), falling back to v1's process walk only for CLIs that predate the beacon. A session is **live** if a beacon names it. The beacon's `cwd` and `status` are surfaced.
- **FR-7.1.5** The inventory must detect **duplicate ids** (same session id in more than one bucket) and present them as a repair task, because they already break `--resume <id>` on the user's machine today.
- **FR-7.1.6** The inventory must read the installed CLI version (`claude --version`, cached per binary mtime) and the effective `cleanupPeriodDays` from settings, and compute for each session the date it becomes eligible for the sweep.
- **FR-7.1.7** Inventory is never persisted as a cache that claims to be current. It is recomputed live (v1 § D9). A short-lived in-memory index with a content-hash invalidation is acceptable.
- **FR-7.1.8** The inventory must tolerate truncated or partially written lines, non-JSON lines, and files being appended during the scan, and must never hold a transcript open for writing.

### 7.2 Projects, task groups, and the Unsorted inbox

- **FR-7.2.1** A **project** is a registry record with a stable id, a display name, a color, and exactly one root directory (L2). Roots must be unique across projects. A project whose root is missing on disk is shown as **detached**, not deleted.
- **FR-7.2.2** A **task group** is a registry record with a stable id, a display name, a parent project, and an optional note. Task groups are flat within a project in this PRD; nesting is deferred (§ 10).
- **FR-7.2.3** A **session ref** is a registry record keyed by session id with an optional project id, optional task group id, provenance (`manual`, `inferred-from-cwd`, `created-by-duo`), timestamps, an optional user note, and an archive marker. A session ref never stores the transcript path; the path is resolved live from the inventory by id.
- **FR-7.2.4** Every session in the inventory with no manual session ref is **Unsorted**. The Unsorted inbox must show them grouped by resolved project root by default (this is display grouping, not a proposal), with alternate groupings by bucket, by month, by size, and flat.
- **FR-7.2.5** When a Duo-created project's root encloses a session's resolved root (same root, a subdirectory, or a worktree of it), the session must be displayed under that project with provenance `inferred-from-cwd` and a `subPath` or `worktree` badge, without being removed from Unsorted until the user confirms. Confirmation may be bulk ("accept all 34 inferred").
- **FR-7.2.6** Sessions Duo itself starts inside a project are attributed at creation (`created-by-duo`) and never enter Unsorted.
- **FR-7.2.7** Unsorted must surface a count in the primary navigation so new strays are noticed (goal 6).

### 7.3 Curation surface (manual)

- **FR-7.3.1** A full-width curation view listing buckets and sessions with columns: title, project (if any), task group, first cwd, latest cwd (if different), branch, last activity, size, live indicator, and badges for orphan, collision, duplicate id, worktree, subPath, sweep-eligible-within-N-days, superseded-copies-present.
- **FR-7.3.2** Sorting by any column; filters for live, orphan, collision, size over N, older than N, bucket, branch, text search over title and first prompt.
- **FR-7.3.3** Multi-select with shift and command ranges and select-all-in-filter. Every action in § 7.3.5 operates on the selection.
- **FR-7.3.4** Drag a session, a selection, or a whole bucket onto a project or task group in a side rail to assign it. Drop on a project assigns without a task group.
- **FR-7.3.5** Actions: Create project from bucket (root pre-filled from the bucket's resolved root; editable); Assign to project; Assign to task group (create inline); Remove from project (back to Unsorted); Archive; Delete; Offer folder move (only when the bucket's cwd exists, § 7.5); Relocate storage (advanced, § 7.4); Repair duplicates; Open transcript read-only; Resume.
- **FR-7.3.6** Keyboard-first: every action reachable without the mouse; a command palette entry per action.
- **FR-7.3.7** The view must render usable within 1 s for 100 buckets and 2,000 sessions on the reference machine, with titles loading lazily.
- **FR-7.3.8** No automatic proposals of any kind (L3). The only suggestion-like element permitted is the display grouping by resolved root in FR-7.2.4 and the inferred attribution in FR-7.2.5, both of which are deterministic facts about paths, not similarity judgments.

### 7.4 Relocate storage (physical, explicit)

- **FR-7.4.1** Relocate moves selected transcripts into the bucket for the target project's root. It is an advanced action, off the primary path, and its confirmation states: that it rewrites internal-format files, that the recorded cwd will become the target root, and that file paths the session remembers will not change.
- **FR-7.4.2** Relocate must execute through the migrator with all § 6.3 invariants, as a plan with one step per file: `<id>.jsonl`, `<id>/` sidecar directory, any `<id>.jsonl.superseded-*` and `<id>.orphaned-*` siblings.
- **FR-7.4.3** Rewrite scope per transcript: the top-level `cwd` on every record; `attachment.snapshot.workingDirectory` and `scratchpadDirectory`; `file-history-snapshot.realParentDir`; `file-history-delta.trackingPath`; `toolUseResult.persistedOutputPath`, `transcriptDir`, `scriptPath`, `filePath`; and any string value that begins with the old root followed by a path separator or end of string. Rewrites are anchored at path boundaries so `/proj` never matches `/proj-2`. The list is a versioned table in code with a test fixture per CLI version.
- **FR-7.4.4** If the target bucket already contains a same-id transcript, the plan must stop and show both files (size, first and last timestamp) and offer: keep target and archive source, keep source and archive target, or cancel. Never overwrite, never leave both.
- **FR-7.4.5** After relocation, the source bucket's `sessions-index.json` and the target's are deleted (Claude rebuilds). If the source bucket is now empty except for `memory/`, it is left in place and flagged; memory consolidation is out of scope.
- **FR-7.4.6** Relocate is refused for live sessions and for sessions whose transcript mixes cwds in a way the plan cannot rewrite coherently (first cwd outside the folder being moved); such sessions are listed with the reason.

### 7.5 Folder move with tandem relocation

- **FR-7.5.1** When a selected bucket's cwd exists on disk and is not already a project root, the curation surface offers **Move folder into a project**. The offer is explicit; nothing moves without the user choosing a destination and confirming a plan.
- **FR-7.5.2** Destination options: rename in place to a new path; move under a chosen parent directory; move inside an existing project's root as a subfolder (**merge**, § 7.5.6). The destination must not exist, or must be an empty directory.
- **FR-7.5.3** Preconditions, all checked immediately before execution and again after the journal is written: no live session in any bucket whose cwd is inside the folder; no Duo tab, terminal, or canvas rooted inside the folder; no process with a cwd inside the folder (`lsof +D` on macOS and Linux); folder and destination on the same filesystem unless the user opts into copy-and-verify; encoder self-calibration passes; CLI version in range.
- **FR-7.5.4** The plan must list, as discrete reviewable steps: the folder rename; for every bucket whose cwd is inside the folder (the root, subdirectories, and worktrees that live inside it), the bucket rename or merge into the new encoding and the per-transcript rewrites (§ 7.4.3) using the old-root to new-root mapping; re-keying of every `~/.claude.json` `projects[...]` entry whose key is inside the folder; rewriting `history.jsonl` lines whose `project` is inside the folder (opt-out available); deletion of affected `sessions-index.json`; `git worktree repair` for any git worktrees whose checkout lives inside the folder or whose main repo does; a note for worktrees of this repo that live outside the folder (their `.git` files point at the old path and `git worktree repair` from the new root fixes them); a note that `.claude/settings.local.json` travels with the folder; and registration of the new path as a project root (or as a subfolder of the merge target).
- **FR-7.5.5** Execution order: journal written; folder renamed first (so a crash leaves the user with a renamed folder and un-relocated transcripts, which 2.1.223+ can still resume by id, rather than relocated transcripts pointing at a folder that did not move); then transcripts; then settings; then index deletion; then verification; then journal commit. On any failure after the folder rename, the migrator attempts a reverse replay and reports precisely what state remains if reversal also fails.
- **FR-7.5.6** **Merge** is moving folder B to `A/<name>/` where A is a project root. Sessions from B are attributed to project A with `subPath` badges; the user may then group them into task groups. Content-level merging of trees is out of scope; if `A/<name>` exists and is non-empty, the move is refused.
- **FR-7.5.7** After commit, Duo must show a verification report: transcripts moved, records rewritten, settings re-keyed, worktrees repaired, and any warnings (for example, a session whose latest cwd was outside the folder).
- **FR-7.5.8** Undo replays the journal in reverse and is offered in the report and in a Migrations list under settings for 30 days.

### 7.6 Archive and delete

- **FR-7.6.1 Archive (preserve).** Moves `<id>.jsonl`, its sidecar directory, and superseded or orphaned siblings to `~/.claude/duo/archive/<bucket>/`, preserving mtimes, via the migrator. The registry marks the session archived with its original bucket. Archived sessions are listed under their project in an Archived section, open read-only, and offer **Restore** (move back to the original bucket, or to the project root's bucket if the original cwd is gone, with the same collision handling as FR-7.4.4). Archive is refused for live sessions. Archive is bulk-capable.
- **FR-7.6.2 Delete.** Permanently removes the transcript, its sidecar directory, superseded and orphaned siblings, and the session-keyed directories under `file-history/`, `tasks/`, `debug/`, `session-env/`, `plans/`. The confirmation lists every path and total bytes, requires typing the count for selections over 10, and is journaled so the list of what was deleted survives even though the content does not. Delete never touches `~/.claude.json`, `history.jsonl`, or `memory/`; a separate **Forget folder** action wraps `claude purge <path>` for users who want the official behavior.
- **FR-7.6.3 Retention awareness.** A banner on the curation surface states the effective `cleanupPeriodDays`, how many unsorted and sorted sessions will become sweep-eligible within 7 days, and offers to archive those or to open the setting. Duo must never change `cleanupPeriodDays` on its own.

### 7.7 Resume behavior

- **FR-7.7.1** Resuming a session from Duo runs `claude --resume <id>` with the child environment scrubbed of `CLAUDE_CODE_*` and `CLAUDECODE` variables.
- **FR-7.7.2** Working directory for the resume, in order: the session's latest recorded cwd if it exists on disk and is inside the project root; else the session's first recorded cwd if it exists and is inside the project root; else the project root. The chosen directory and the reason are shown in the terminal header. (v1 always used the recorded cwd and failed when it was gone, ENH-232.)
- **FR-7.7.3** On a CLI older than 2.1.223, resume must run from a directory whose bucket holds the transcript (the recorded cwd); if that directory is gone, Duo offers Relocate (which is the only way to make the session resumable on that CLI) and shows an upgrade nudge.
- **FR-7.7.4** Resuming a live session focuses the owning Duo tab if there is one; if a process outside Duo holds it, Duo offers `--fork-session` with an explanation, as v1 did, and never starts a second writer on the same transcript.
- **FR-7.7.5** Resuming an archived session restores it first (FR-7.6.1), then resumes.
- **FR-7.7.6** After a resume, the inventory must re-scan the affected buckets within 5 s, because 2.1.223+ may relocate storage during resume (§ 10, Q1), and pointers must keep resolving.

### 7.8 Repair tasks

- **FR-7.8.1 Duplicate ids.** Show both copies with size and time range; actions: archive the older, archive the smaller, open both read-only. Never auto-pick.
- **FR-7.8.2 Collisions.** When a bucket holds sessions from two or more distinct cwds, attribution and resume operate per session on its own cwd. Physical operations on the bucket are refused until the user chooses which cwd's sessions the operation applies to; the migrator then moves only those files, never the whole bucket.
- **FR-7.8.3 Stale index.** If `sessions-index.json` lists a session that is not on disk, or omits one that is, offer to delete the index.
- **FR-7.8.4 Interrupted migration.** On launch, any journal not in `committed` or `reverted` state blocks physical operations until the user chooses complete or revert; the UI shows the step reached.

### 7.9 Agent-facing surface

- **FR-7.9.1** Every read in § 7.1 and every action in § 7.3.5 is available on Duo's socket CLI (`duo sessions list|show`, `duo projects …`, `duo migrate plan|apply|verify|undo`, `duo archive`, `duo delete`), with JSON output, so a Claude session running inside Duo can propose a consolidation plan and hand it to the user for approval in the curation surface. The CLI enforces the same invariants and never bypasses confirmation for physical operations.
- **FR-7.9.2** A Duo skill may teach Claude to read the inventory and draft a plan in prose plus a plan JSON. The skill must not instruct Claude to run file operations under `~/.claude/projects` directly.

---

## 8. Data model

Registry at `~/.claude/duo/registry.json`, written atomically, schema-versioned, with rotating backups. Keyed by Duo ids and session ids, never by transcript paths. This is a Duo-owned concept the external system does not track (projects, task groups, membership, archive state) plus pointers (session ids) that resolve live, which is the v1 § D9 test.

```jsonc
{
  "version": 1,
  "projects": [
    { "id": "prj_01…", "name": "foo", "root": "/Users/me/projects/foo",
      "color": 3, "createdAt": "…", "note": "" }
  ],
  "taskGroups": [
    { "id": "tg_01…", "projectId": "prj_01…", "name": "auth refactor",
      "createdAt": "…", "note": "" }
  ],
  "sessions": {
    "466c9002-2caf-5b25-88f4-4fb1aea99f97": {
      "projectId": "prj_01…", "taskGroupId": "tg_01…",
      "provenance": "manual",           // manual | inferred-from-cwd | created-by-duo
      "attributedAt": "…", "note": "",
      "archive": null                    // or { "bucket": "-Users-me-Desktop-foo-test", "archivedAt": "…" }
    }
  }
}
```

Migration journals at `~/.claude/duo/migrations/<timestamp>-<id>.json`:

```jsonc
{
  "id": "mig_01…", "kind": "folder-move",   // folder-move | relocate | archive | restore | delete
  "state": "planned",                       // planned | applying | committed | reverting | reverted | failed
  "cliVersion": "2.1.288", "encoderCalibration": "ok",
  "mapping": { "from": "/Users/me/Desktop/foo-test", "to": "/Users/me/projects/foo" },
  "steps": [
    { "n": 1, "op": "rename-dir", "from": "…", "to": "…", "done": true },
    { "n": 2, "op": "rewrite-move", "from": "…/-Users-me-Desktop-foo-test/<id>.jsonl",
      "to": "…/-Users-me-projects-foo/<id>.jsonl", "bytesBefore": 1, "sha256Before": "…",
      "sha256After": "…", "mtime": "…", "recordsRewritten": 212, "done": true },
    { "n": 3, "op": "rekey-claude-json", "key": "/Users/me/Desktop/foo-test", "newKey": "…", "done": false }
  ],
  "verification": null,
  "startedAt": "…", "finishedAt": null
}
```

Archive layout: `~/.claude/duo/archive/<original bucket>/<id>.jsonl` plus `<id>/`, mtimes preserved.

Nothing is written inside project folders. The in-folder `.claude/settings.local.json` is Claude Code's, and it already travels with the folder.

---

## 9. Non-functional requirements

- **NFR-1** Read paths never block the UI; inventory of 2,000 sessions completes within 2 s cold on the reference machine using head and tail reads.
- **NFR-2** Physical operations are serialized machine-wide with a lock file under `~/.claude/duo/` and refuse to start while any Claude Code process is mid-startup sweep (detectable by `~/.claude/.last-cleanup` changing within the last few seconds).
- **NFR-3** All transcript parsing is tolerant: unknown record types and unknown fields are preserved byte-for-byte on rewrite (rewrites edit string values in parsed JSON and re-serialize only lines that changed; unchanged lines are copied verbatim).
- **NFR-4** No telemetry of transcript content. Journals store paths, hashes, sizes, and counts, never prompt text.
- **NFR-5** Everything in § 7 works with `~/.claude` on a case-insensitive filesystem (macOS default) and with paths containing spaces, unicode, and symlinks.
- **NFR-6** Platform: macOS first, Linux second. Windows bucket encoding (`C--Users-…`) is read-only supported; physical operations on Windows are out of scope for this PRD.

---

## 10. Open questions

| # | Question | Why it matters | Proposed way to close |
|---|---|---|---|
| Q1 | On 2.1.223+, does an **interactive** `--resume <id>` from another directory relocate the transcript the way `/cd` does, or append in place as observed in `-p` mode (Appendix A)? | Decides whether pointer-attributed sessions silently migrate between buckets over time and how aggressive FR-7.7.6 rescans must be. | One interactive experiment on 2.1.288 with an isolated `CLAUDE_CONFIG_DIR`; then read the binary around the resume path. |
| Q2 | Which version introduced `--resume <transcript path>`? | Sets the floor for FR-7.6.1 restore-and-resume and the S-OLDCLI fallback. | Changelog bisect. |
| Q3 | Does `--resume <id>` from another directory require `cwd` fields to match anything, or is the 2.1.239 cwd filter picker-only? | If resume itself filters, pointer re-homes of S-COLLIDE sessions could fail. Appendix A suggests resume does not filter. | Experiment with a transcript whose cwd is a path that does not exist. |
| Q4 | Should prompt history (`history.jsonl`) follow a folder move by default? | Privacy (plaintext prompts) versus continuity of up-arrow history. | Owner call; default proposed: yes, with opt-out in the plan. |
| Q5 | Auto memory per bucket: leave, or offer a merge into the project root's `memory/`? | Memory fragmentation is the same chaos one level down (issue #34437). | Follow-on PRD; in this one, surface the fact in the bucket detail. |
| Q6 | Task group nesting and cross-project task groups. | L2 fixes one root per project; nothing yet says whether a task group can span projects. | Defer; flat per project in v2.0. |
| Q7 | Should Duo set `CLAUDE_CODE_PROJECT_DIR_NAME` for sessions it launches if Anthropic decouples it from `CLAUDE_CONFIG_DIR`? | Would make Duo-created sessions path-independent from day one. | Watch the changelog; revisit. |
| Q8 | Which of R1–R4 does the owner confirm or flip? | Each flips a section of § 7. | Owner review of this draft. |

---

## 11. Compatibility matrix and version gates

| Capability Duo relies on | Minimum CLI | Behavior below minimum |
|---|---|---|
| Cross-bucket `--resume <id>` | 2.1.223 | Resume only from the recorded cwd; Relocate offered when that cwd is gone (FR-7.7.3). |
| Picker filters colliding buckets by cwd | 2.1.239 | Relocated transcripts with correct cwd are visible either way; un-rewritten ones may show in the wrong picker. Informational. |
| No silent overwrite on same-id relocation | 2.1.251 | Duo's own FR-7.4.4 check protects regardless; the gate exists for `/cd` done by the user. |
| `/cd` relocation of live sessions | 2.1.169 | Duo never depends on it; informational in the session detail. |
| Live-session beacons in `~/.claude/sessions/` | observed 2.1.288; introduction version unpinned | Fall back to v1 process walk. |
| `claude purge <path>` | 2.1.288 | Forget-folder action hidden. |
| Tested physical-operation range | 2.1.223 to the last version the rewrite table (FR-7.4.3) has fixtures for | Physical operations disabled with an explanation; pointers, archive-by-move of whole files without rewrite, and delete remain enabled. |

Duo reads `claude --version` once per binary change. A CLI newer than the tested range puts physical operations in **caution mode**: enabled only after encoder self-calibration passes and the user acknowledges a one-time notice.

---

## 12. Phasing

| Phase | Delivers | Exit criterion |
|---|---|---|
| P0 Inventory | § 7.1, § 7.8 detection only, retention banner (FR-7.6.3), beacon-based liveness. Read-only. | Reference machine's 41 buckets inventoried with zero crashes; every collision and orphan on it correctly flagged. |
| P1 Curate | Registry (§ 8), projects and task groups (§ 7.2), curation surface (§ 7.3) minus physical actions, pointer re-home, resume rules (§ 7.7), Unsorted inbox, socket CLI reads. | S-RENAMED and S-SCATTER walk end to end; every re-homed session resumes from its project. |
| P2 Retire | Archive by move and restore (FR-7.6.1), delete (FR-7.6.2), migrator core with journal, undo, interrupted-migration repair (FR-7.8.4). | S-TRASH and S-RETAIN walk; kill-during-archive test leaves a repairable journal. |
| P3 Move | Folder move with tandem relocation (§ 7.5), rewrite table and fixtures (FR-7.4.3), encoder self-calibration, collision-aware partial moves (FR-7.8.2), `git worktree repair`. | S-MOVE, S-LIVE refusal, S-COLLIDE partial move pass; undo restores byte-identical state. |
| P4 Advanced | Explicit Relocate (§ 7.4), duplicate repair UI (FR-7.8.1), agent-facing plan hand-off (§ 7.9), caution mode. | A Claude session inside Duo drafts a plan that the user approves and the migrator applies. |

---

## 13. Acceptance and test strategy

- **Encoder conformance.** A table-driven test of the encoder against paths with dashes, dots, underscores, spaces, unicode, symlinks, Windows drive letters, and the 200-character boundary, plus the runtime self-calibration (§ 6.3 item 5) run against real buckets in CI fixtures.
- **Fixture corpus.** Anonymized transcripts captured from each CLI version in the compatibility range, including mixed-cwd files, subagent layouts old and new, superseded siblings, worktree bindings, and `custom-title` records. The rewrite table test asserts that after a relocate, zero string values in the file begin with the old root.
- **Round trip.** Relocate then undo yields byte-identical files and identical mtimes. Archive then restore likewise.
- **Crash injection.** Kill the migrator after each step of a folder move; on relaunch the journal is detected and either completion or reversal yields a consistent state with uniqueness intact.
- **Uniqueness fuzz.** Random sequences of relocate, archive, restore, and folder move across randomly colliding paths never produce a duplicate id under `projects/`.
- **Liveness.** With a `claude` process running in a bucket, every physical action on that bucket is refused and pointer actions succeed.
- **Resume matrix.** For CLI versions 2.1.150, 2.1.223, 2.1.239, and current: resume by id from project root, from original cwd, with original cwd deleted, and after relocate, with the expected outcome per § 11. Model calls in this matrix run only in an opt-in CI lane.
- **Performance.** Inventory of a synthetic 2,000-session, 1 GB corpus within NFR-1.

---

## 14. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Internal format changes break the rewrite table | High over a year | Hidden or unresumable sessions after a relocate | Version gate, encoder calibration, fixtures per version, caution mode, pointers never depend on the table |
| Anthropic ships native relocation | Medium | Duo's migrator becomes redundant | Keep the migrator thin; prefer official primitives as they appear; pointers remain valuable regardless |
| User runs an older CLI in some client (Desktop, IDE) | Medium | Cross-bucket resume fails there | Detect every installed binary we can find; show which clients can resume a given session |
| Retention sweep deletes sessions mid-curation | Medium | Loss | Retention banner first in P0; archive by move is the user's defense |
| Collision bucket partially moved | Low | Wrong sessions relocated | FR-7.8.2 per-cwd moves; never move a collided bucket wholesale |
| Second writer on one transcript | Low after beacons | Corruption | Liveness guard plus FR-7.7.4 fork path |

---

## Appendix A — Experiment log (CLI 2.1.288, 2026-10-03)

Setup: isolated `CLAUDE_CONFIG_DIR`; a synthetic two-record transcript with id `1111…5555` placed under the bucket for `dirA`; `dirB` an empty sibling directory. `-p` mode. Host credentials were active, so each test made one real model call.

| Test | Command (cwd) | Result on disk |
|---|---|---|
| 1 | `claude -p --resume 1111… "reply with one word"` (dirA) | Resumed. Appended to `dirA` bucket file with `cwd=dirA`. |
| 2 | same (dirB) | **Resumed.** No file created under the `dirB` bucket. New records appended to the **original file under the `dirA` bucket** with `cwd=dirB`. One transcript now carries two cwds. |
| 3 | `claude -p --continue "reply"` (dirB) | Did **not** find the `dirA` session. Started a fresh session. The fresh transcript was written under the `dirB` bucket **with the parent harness's session id**, because `CLAUDE_CODE_SESSION_ID` was inherited from the environment. |

No `sessions-index.json` was produced in `-p` mode. The environment also contained `CLAUDE_CODE_SESSION_ID`, `CLAUDECODE`, and `CLAUDE_CODE_ENTRYPOINT`, all of which a wrapper must scrub (FR-7.7.1).

## Appendix B — Path-bearing fields known as of 2.1.277–2.1.288

Top-level `cwd` on every record; `attachment.snapshot.workingDirectory`; `attachment.snapshot.scratchpadDirectory`; `attachment.snapshot.additionalWorkingDirectories[]`; `file-history-snapshot.realParentDir`; `file-history-delta.trackingPath`; `toolUseResult.persistedOutputPath`; `toolUseResult.transcriptDir`; `toolUseResult.scriptPath`; `toolUseResult.filePath`; tool inputs and outputs containing absolute paths (not rewritten by default; see FR-7.4.3's generic prefix rule); bucket names embedded inside scratchpad and tool-result paths (for example `/tmp/claude-0/-home-user-duo-v2/…`), which must be rewritten with the encoded old and new bucket names as well. `sessions-index.json`: `fullPath`, `projectPath`, `originalPath`. `~/.claude.json`: `projects` keys. `history.jsonl`: `project`.

## Appendix C — References

Official: `code.claude.com/docs/en/sessions`, `…/claude-directory`, `…/worktrees`, `…/permissions`, `…/agent-sdk/sessions`, `…/env-vars`, `…/claude-code-on-the-web`; `anthropics/claude-code` `CHANGELOG.md` entries 2.1.94, 2.1.98–2.1.108, 2.1.169, 2.1.196, 2.1.198, 2.1.211, 2.1.223, 2.1.224, 2.1.234, 2.1.239, 2.1.248, 2.1.251, 2.1.288.
Issues: #5768, #7009, #21085, #24271, #24729, #25032, #22205, #27473, #33634, #34437, #35162, #40946, #41591, #46784, #51488, #58591, #59248, #79215, #80906, #86713, #88603, #93743, #96323, #98575.
Community tools: `tsvikas/claude-mv`, `Mahiler1909/claudepath`, `NotebookNomad/claude-move`, `wsagency/claude-move-project`, `Sertelegger/claude-sesh-mover` (issue #127), `daaain/claude-code-log`, `ccusage` directory detection docs, `frederick-douglas-pearce/claude-code-sessions`, the samkeen gist on `~/.claude.json` project entries, `scenee` on `CLAUDE_CODE_PROJECT_DIR_NAME`.

## Appendix D — What Duo v1 already has (reusable) and lacks

Reusable from `dudgeon/duo` v0.13.8: `claude-session-tracker.ts` head and tail readers (`readSessionHeadMeta`, `readSessionTailMeta`, `listTopLevelSessions`) and the title preference chain (`custom-title` > `ai-title` > cleaned first prompt > uuid prefix); `home-snapshot.ts` `rollupProjects` (worktree fold via `gitdir:`, deepest enclosing git or marker root); `buildResumeCommand`; the socket CLI pattern; the `~/.claude/duo/` atomic JSON store pattern; `docs/DECISIONS.md` § D9 (no sidecar) as the governing rule for § 8.

Lacking in v1 and required here: an encoder that replaces all non-alphanumerics (v1 replaced only `/` and `.`); per-session cwd attribution in collided buckets (v1 applied the newest session's cwd to the whole bucket); liveness by session id (v1 guessed from process cwd, FOLLOWUP-054); any grouping, archiving, manual attribution, or migration code; handling of a missing cwd on resume (ENH-232); dismiss or archive (ENH-233).

## Appendix E — Glossary

- **Bucket:** a directory under `~/.claude/projects/`, named by encoding a working directory.
- **Transcript:** a session's `<id>.jsonl` plus its sidecar directory and set-aside siblings.
- **Project:** Duo's first-class record; one root directory; owns task groups.
- **Task group:** a named set of sessions inside one project.
- **Re-home (pointer):** recording a session's project and task group in Duo's registry without touching its transcript.
- **Relocate:** physically moving a transcript into another bucket with path rewrites.
- **Tandem move:** a folder move that relocates its transcripts and path-keyed settings in the same journaled transaction.
- **Beacon:** `~/.claude/sessions/<pid>.json`, written by a running Claude Code process.
- **Sweep:** Claude Code's startup deletion of files older than `cleanupPeriodDays`.
