# PRD — Legacy Session Inventory and Consolidation ("taming the backbook")

> **Status:** Draft v0.2, 2026-10-03. Standalone requirements document for one capability of Duo v2. Written to be lifted into the broader product plan without edits to its substance.
> **Fits with:** `docs/design/claude-design-handoff.md` (the v2 brief: vocabulary, panes, behaviours 1 to 6, decisions), `docs/research/claude-code-session-path-binding.md` (independent verification of the same storage facts, plus the session-identity rules adopted in § 6.2), `docs/research/agent-harness-landscape.md` § 8 (file layout and lifecycle). § 1.1 maps this document's objects onto the brief's.
> **Owner decisions:** eight answers locked via AskUserQuestion on 2026-10-03 (§ 4 L1–L8). Three further decisions are author recommendations awaiting owner confirmation (§ 4 R1, R2, R4); the document is written assuming they hold, and each is isolated so it can be flipped.
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

### 1.1 How this fits the v2 plan

The design brief fixes the vocabulary and several decisions this document must respect. The mapping:

| Brief (v2) | This document | Notes |
|---|---|---|
| **Topic**: an area folder such as `~/work/payments/`, light grouping, never completes | The parent directory a project folder lives in | Consolidation offers a topic folder as the destination parent when creating a project (FR-7.10.8). No topic object is modeled here. |
| **Project**: a folder, 1:1 with a Claude Code project, with `PROJECT.md` | **Project**: one root directory (L2) | Identical. Legacy buckets become projects by being assigned a root that has, or gets, the project files. |
| **Task**: a markdown file in `tasks/`, many-to-many with sessions, sessions may stay unlinked | **Task** (earlier drafts said "task group") | Consolidating a cluster files sessions under a project and optionally links them to a task (L7). |
| **Session**: a resumable Claude Code conversation; belongs to exactly one project | **Session**: same | For legacy sessions "the folder it started in" becomes "the project it is filed under"; the transcript may stay in its original bucket (pointer) or be relocated (§ 6.1). |
| **Home**: a triage project with a director agent | Not involved in consolidation beyond counts and a link (L8) | **`$HOME` the directory** is a different thing. This document calls `$HOME`-style buckets **catch-all buckets** to avoid the collision. |
| **Unfiled** (wireframe lane: "sessions started outside a project, so you can file them") | **Unfiled**: every session not present in any project's session index | Same lane, same verb: file. |
| Behaviour 5, "nothing is lost when folders move", and flow C5, "project moved" | § 7.5 tandem move and FR-7.5.9 external-move reconciliation | The brief's stable project id in a manifest is adopted (§ 6.2). |
| Behaviour 6, "state lives in readable files near the work" | § 8: project files are canonical; the app registry holds pointers only (L6) | Supersedes the earlier registry-centric draft. |

---

## 2. Goals and non-goals

### Goals

1. **Inventory.** On every launch, build a complete, live, trustworthy picture of every session on the machine: where it is, what it was about, when it last moved, whether a process holds it, whether its folder still exists, and whether its storage is in a degraded state (collision, duplicate id, stale index).
2. **Curation.** Give the user a manual curation surface to assign legacy sessions and buckets to intentional projects and to named tasks inside those projects. No automatic clustering; good sorting, filtering, and multi-select instead (L3).
3. **Resumability is sacred.** No action Duo offers may leave a session unresumable, and no action may create a second copy of a session id anywhere under `~/.claude/projects` (§ 6.3).
4. **Tandem moves.** When a user wants the folder itself moved or renamed, Duo offers to do it and moves folder, transcripts, and path-keyed settings as one journaled, verifiable, reversible transaction (L1, R2).
5. **Retire noise.** Archive and delete dead sessions with full visibility into what goes, and protect anything the user keeps from Claude Code's own retention sweep (R4).
6. **Ongoing, not one-shot.** New sessions created outside Duo (bare terminal, IDE extensions, Desktop) keep appearing in an Unfiled lane so the backbook never regrows unnoticed.

### Non-goals (this PRD)

- Automatic topic clustering or LLM-generated consolidation proposals (L3). Sorting by recency, size, root, and liveness is in scope; "these look related" is not.
- Content-level merging of two source trees into one. "Merge" here means moving one folder to live inside another project's root (§ 7.5.6).
- Cross-machine sync of sessions or of Duo's registry.
- Consolidating Claude Code's per-directory auto memory (`projects/<bucket>/memory/`). Flagged in § 10 as a follow-on.
- Replacing Claude Code's native `/resume` picker. Native parity is a stated benefit of one optional operation (§ 7.4), not a requirement of the system.
- Cloud sessions (`claude.ai/code`) and their teleport flow. Those have server-side identity and are not backbook.
- Generating model-written summaries for legacy sessions. The brief wants a durable per-session summary line inside the project; for legacy sessions this document uses the title chain (`/rename` title, then AI title, then first prompt) and leaves hook-driven summaries for new sessions to the broader plan.
- The Duo-owned `CLAUDE_CONFIG_DIR` profile (research option B). Not adopted for v2 (L5); may return as a setting.

---

## 3. Users and scenarios

Single persona: a heavy Claude Code user on one machine who has been working for months without a project discipline and now adopts Duo v2. Scenarios the design must handle, each referenced later by its tag:

| Tag | Scenario | What "good" looks like |
|---|---|---|
| S-RENAMED | `~/Desktop/foo-test` was renamed to `~/work/foo` months ago. Bucket `-Users-me-Desktop-foo-test` still holds 30 sessions. | User sees the bucket flagged "folder missing", assigns it to project `foo`, every session resumes from `~/work/foo`. |
| S-SCATTER | Project `foo` has sessions in the root bucket, in `foo/packages/api`, and in two worktrees. | All four buckets roll up under `foo` (one project, one root). Sessions keep their original cwd for resume. User groups eleven of them into task "auth refactor". |
| S-TRASH | 60 one-prompt sessions in `~`, `~/Downloads`, and `/tmp/x`. | Sorted by size and age, bulk-selected, archived or deleted in one confirmed action. |
| S-JUNK | The `$HOME` bucket holds 83 sessions. Most are unrelated one-offs, but nine of them were a thesis-formatting effort that edited files under `~/Documents/thesis`, and six were an unfinished CLI tool that lives nowhere yet. | The catch-all view shows per-session evidence (files touched, dates, branch, lineage). The user filters to the nine thesis sessions, sees that their touched files share `~/Documents/thesis`, and migrates them to the existing project rooted there. The user selects the six CLI sessions, creates a new project folder for them, and optionally moves the scattered files they produced into it. Sessions move one at a time; the bucket is never moved wholesale. Everything left is triaged with one decision each: archive, delete, or leave. |
| S-MOVE | User wants `~/Desktop/foo-test` (still exists) moved to `~/work/foo`. | Duo offers the move, previews every file operation, executes folder + transcripts + settings in tandem, verifies, and offers undo. |
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
| L2 | Shape of a project | **One root directory per project**, with named **tasks** inside it. Worktrees and subdirectories belong to the enclosing project. |
| L3 | How groupings are proposed | **Manual curation only.** Rich sort and filter; no automatic proposals. |
| L3a | Amendment proposed 2026-10-03 for the catch-all case (§ 7.10), pending owner confirmation | Duo may compute and display **deterministic evidence** per session (files it edited, their common ancestor directory, date clusters, branch, fork and continuation lineage, tags) and let the user filter and group by it. This is path and timestamp arithmetic, not a similarity judgment, and it never pre-selects or recommends a grouping. Without it, splitting an 83-session `$HOME` bucket by hand is impractical. |
| L4 | Safety posture | Owner asked for a research-backed recommendation, with two hard constraints: never duplicate session logs in ways that create new problems, and prioritize clustering related sessions while preserving resumability. Answered by R1 below and § 6. |
| L5 | Storage mode | **Duo shares the user's `~/.claude`** and relocates with Claude Code's own mechanics. The research doc's option B (a Duo-owned `CLAUDE_CONFIG_DIR` with `CLAUDE_CODE_PROJECT_DIR_NAME`) is not adopted for v2; see § 6.2 for what is adopted from that doc instead. |
| L6 | Metadata home | **Project files are canonical; the app registry holds pointers only.** Filing a session writes it into the project's session index. The registry keeps project id to path, migration journals, archive locations, and triage state for sessions that have no project yet. Supersedes the earlier R3. |
| L7 | Tasks | **File under the project; link to a task optionally, offered inline.** The dialog offers "link to existing task" or "create task" with a user-chosen status. Unlinked sessions stay visible as unlinked. |
| L8 | Home's role | **UI only.** Home may report the unfiled count and link to the consolidation view. It proposes nothing and files nothing. L3 stands. |

### Recommended by author, pending owner confirmation

| # | Decision | Recommendation | If flipped |
|---|---|---|---|
| R1 | Pointer vs physical move | **Pointer is always the source of truth. Physical relocation uses Claude Code's own `/cd` mechanics** (move transcript and sidecar, append a `relocated` record, rewrite nothing) and is applied automatically inside a folder move, by default for buckets whose directory no longer exists, and on request otherwise. Native picker parity for whole buckets that stay put is offered through `.session-aliases` instead of a move. Rationale § 6.1. | "Always move": § 7.4 runs on every re-home; cheap now that no rewrite is involved, but every re-home then touches Claude's storage and the picker shows the session only in the project root. "Never move": § 7.4, § 7.5 and R4's move-to-archive are cut; retention protection becomes a settings nudge only. |
| R2 | Who executes a move | **Deterministic migrator in Duo.** A Claude session may propose and explain a plan; it never performs the file operations. Rationale § 6.4. | A skill-driven agent executor needs the same journal and invariants, exposed as a `duo migrate` CLI; the agent is then one caller of it. |
| ~~R3~~ | Where Duo's metadata lives | Superseded by L6 (project files canonical, registry for pointers). The reconciliation rules the earlier draft worried about are specified in § 8. | — |
| R4 | Meaning of "archive" | **Preserve:** move out of Claude Code's sweep path into a Duo-owned archive, read-only, restorable. Rationale § 6.5. | "Hide only" is a registry flag and loses sessions to the sweep. "Delete" collapses § 7.6.1 into § 7.6.2. |

---

## 5. Research findings: how Claude Code binds sessions to folders

This section is the factual substrate for everything that follows. Each item carries a confidence and the version it was verified against.

### 5.1 Storage layout

- **Bucket name.** The absolute working directory, symlink-resolved, with **every character outside `[A-Za-z0-9]` replaced by `-`** (`replace(/[^a-zA-Z0-9]/g,"-")` in the 2.1.288 binary; case preserved). `/Users/me/proj` becomes `-Users-me-proj`. Names over 200 characters are truncated to 200 and suffixed with `-` plus a base-36 hash of the full path whose hash function is internal. `CLAUDE_CODE_PROJECT_DIR_NAME` (`[A-Za-z0-9_-]{1,64}`) overrides the name, but only when `CLAUDE_CONFIG_DIR` is also set. The computed bucket is cached per cwd for the life of the process. *Official docs plus binary read; high confidence.*
- **The encoding is lossy and collisions are real.** `/a/b-c`, `/a/b/c`, `/a/b_c`, `/a/b.c` all share one bucket. Non-ASCII path segments collapse to runs of dashes. Anthropic has closed collision reports as "not planned" at least five times (issues #7009, #21085, #35162, #40946, #93743). v1 Duo's encoder only replaced `/` and `.`, so it looks in the wrong bucket for paths with underscores or spaces (Appendix D). *High confidence.*
- **Per-session files.** `<id>.jsonl` (main transcript); `<id>/subagents/agent-<id>.jsonl` (sidechains; older 2.0.x builds wrote these as siblings in the bucket); `<id>/tool-results/` (large outputs); `<id>.jsonl.superseded-<ts>` and `<id>.orphaned-<ts>-<suffix>.jsonl` (set-aside copies written since 2.1.251 instead of overwriting); `<id>/ccr-tip.json` (remote-session sync tip, observed locally). *Official docs plus local observation; high confidence.*
- **Per-session sidecars inside `<id>/`** also include `custom-title.json` (the `/rename` title is dual-stored there and as a tail record), `precompact.json`, `sent-prefix.json`, and `.cast` recordings. *Binary read, 2.1.288; high confidence.*
- **Per-bucket files.** `memory/` and `tiny_memory/` (auto memory, never swept); `.session-aliases` (newline-separated absolute paths of other buckets whose sessions should appear in this directory's `/resume` picker; written by `/add-dir`); `bridge-pointer.json`, `cloud-snapshots/`. **There is no `sessions-index.json` in 2.1.288**: the string does not occur in the binary, and listing is a directory read plus `stat` plus a regex scan of the first and last 64 KB of each file. Earlier builds did write a `sessions-index.json` cache (observed in 2 of about 30 buckets on the v1 reference machine; schema `sessionId, fullPath, fileMtime, firstPrompt, summary, messageCount, created, modified, gitBranch, projectPath, isSidechain`), and it was often stale (issues #24729, #25032, #22205). A tool must tolerate finding one and must not depend on it. *Binary read plus community sources; high confidence.*
- **The `relocated` record.** `{"type":"relocated","sessionId":"<id>","relocatedCwd":"<path>"}` appended to the tail of a transcript. The code reads `relocatedCwd ?? head cwd` as the session's project path for the picker, for slug-collision filtering, and for long-path validation. This is how `/cd` and worktree enter/exit relocate a session without rewriting history. *Binary read; high confidence. This is the single most important primitive in this document.*
- **Every record** carries `type, uuid, parentUuid, timestamp, sessionId, cwd, gitBranch, version, isSidechain, userType`. Non-message record types include `summary` (with `leafUuid`), `custom-title` (from `/rename`, last one wins), `ai-title`, `file-history-snapshot` and `file-history-delta` (which embed `realParentDir` and `trackingPath`), `attachment` (whose `snapshot.workingDirectory` is a path), `last-prompt`, `queue-operation`, `permission-mode`, worktree binding records. *Verified on the live 2.1.288 transcript in this session; high confidence.*
- **A single transcript can contain mixed `cwd` values.** Resuming from another directory appends records carrying the new cwd to the same file (Appendix A). So "the session's cwd" is really "the session's first cwd" and "the session's latest cwd", and they can differ.

### 5.2 Resume semantics by version

| Entry point | Behavior (2.1.223+) | Older behavior |
|---|---|---|
| `claude --continue` | Most recent session **in the current directory's bucket only.** Verified: did not find a session stored under a sibling bucket (Appendix A, test 3). | Same. |
| `claude --resume <id>` | Resolver order read from the binary: (1) the current bucket, plus the `CLAUDE_CODE_PROJECT_DIR_NAME` alternate and, for over-200-character paths, sibling buckets sharing the prefix validated by transcript cwd; (2) the buckets of every sibling git worktree (`git worktree list`); (3) **a scan of every bucket on the machine that succeeds only if exactly one holds `<id>.jsonl` with messages.** Two copies anywhere make step 3 return nothing and the user sees "No conversation found with session ID". Resume **does not filter by recorded cwd, does not move the file, and does not rewrite any record**; it appends new records carrying the new cwd to the file it found. Verified empirically on 2.1.288 (Appendix A, test 2) and in code (the resume path only loads `relocatedCwd` into memory). | Before 2.1.223: steps 1 and 2 only; otherwise `No conversation found with session ID` (issues #5768, #27473, #58591). |
| `claude --resume <absolute path to .jsonl>` | Resumes that file regardless of location. | Not available on older builds; exact introduction version not pinned. |
| `claude --resume` / `/resume` picker | Default scope is the current bucket plus every bucket listed in its `.session-aliases` file (which is how sessions that `/add-dir`'d the current directory appear). `Ctrl+W` widens to all worktrees of the repo; `Ctrl+A` to every project. Picking a session from another project copies a `cd … && claude --resume` command to the clipboard rather than resuming; if that directory no longer exists, it resumes in the current one (2.1.239). **The collision filter (2.1.239+) hides a session only when `relocatedCwd ?? head cwd` resolves to a different real directory with the same slug.** A transcript whose cwd has a different slug is not filtered. Also hidden: sidechains, daemon and SDK entrypoints, `/loop` sessions, sessions continued elsewhere. | 2.1.94 to 2.1.108: scope flip-flopped between worktree-only and all-projects. |
| `/cd <path>` (2.1.169+) | Relocates the **live** session: parks appends, renames `<id>.jsonl` and the `<id>/` sidecar directory into the new bucket (falling back to a recursive copy on cross-device or busy errors), sets aside any same-id file already there as `<id>.jsonl.superseded-<ms>` (2.1.251), repoints task-output symlinks, re-homes settings watchers and permission anchors, and appends a `relocated` record. Does not rewrite earlier records, `history.jsonl`, or `~/.claude.json`. Not retroactive. | Not available. |
| `EnterWorktree` / `--worktree` | Records a worktree binding in the transcript and relocates storage like `/cd` (2.1.198+). On resume, re-enters the worktree if its git metadata checks out; if the worktree is gone, resumes in the launch directory and records a binding clear. | Each worktree was simply its own bucket. |
| `--fork-session` | New id, copied history, starts in the launch directory. | Same. |
| SDK `resume` | Same lookup as the CLI it bundles. SDKs that bundle an older CLI are cwd-scoped. | — |

*Official docs with changelog version pins, confirmed against the 2.1.288 binary; high confidence. The resume code path applies `relocatedCwd` in memory only and never calls the relocation routine, so interactive resume behaves like the `-p` run in Appendix A.*

### 5.3 State keyed by path versus by session id

| Location | Key | Contents | Must move with a folder? |
|---|---|---|---|
| `~/.claude.json` → `projects["<abs path>"]` | path | `allowedTools`, `mcpServers`, `enabledMcpjsonServers`, `hasTrustDialogAccepted`, `hasCompletedProjectOnboarding`, `lastSessionId`, `lastCost`, `exampleFiles`, legacy `history` | Yes (re-key). This file also holds auth and global state; touch only the `projects` key, atomically. Rotating backups in `~/.claude/backups/` keep the old key. |
| `~/.claude/history.jsonl` | path (`project` field per line; newer lines also carry `sessionId`) | prompt history, plaintext; never swept, grows unbounded; writes take a lock | Yes (rewrite lines) if prompt history should follow the folder. |
| `projects/<bucket>/` | encoded path | transcripts, `<id>/` sidecars, `memory/`, `.session-aliases` | Yes. |
| `projects/<bucket>/sessions-index.json` | contains `fullPath`, `projectPath` | legacy cache, not written by 2.1.288 | Delete if present; nothing current reads it. |
| `projects/<bucket>/.session-aliases` | absolute paths of other buckets | picker aliasing | Rewrite any line that names a bucket being moved. |
| `/tmp/claude-<uid>/<bucket>/<sessionId>/` | encoded path and session id | scratchpad and task outputs; `/cd` repoints task-output symlinks into it | No move; accept that scratch paths in old records point at the old slug. Swept with the session. |
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
4. **The `relocated` tail record** (§ 5.1), which is the mechanism behind item 3 and is equally valid when appended by an external tool to a non-live transcript: move `<id>.jsonl` and `<id>/`, append one line, done. No historical rewrite is required because every reader prefers `relocatedCwd`.
5. **`.session-aliases`**: one line per aliased bucket inside a bucket; makes the aliased bucket's sessions appear in this directory's picker without moving anything. The file is in the reserved set the sweep never deletes. Undocumented, but the mechanism `/add-dir` relies on.
6. `CLAUDE_CONFIG_DIR` plus `CLAUDE_CODE_PROJECT_DIR_NAME` (2.1.234+): pins the bucket name independent of cwd, but only when `CLAUDE_CONFIG_DIR` is also set, which relocates the entire config tree. Evaluated and rejected as a Duo mechanism (§ 6.6).
7. `claude purge <path>`.

Community (all unofficial, all parsing the internal format): `claude-mv`, `claudepath`, `claude-move`, `claude-move-project`, `claude-sesh-mover`, plus a widely copied gist. They converge on one recipe: rename the bucket to the new encoding (merging if the target exists), rewrite `cwd` and other absolute-path strings line by line with path-boundary anchoring, re-key `~/.claude.json`, rewrite `history.jsonl`, fix or delete `sessions-index.json`, leave session-keyed directories alone, and back up first. Their issue trackers document the fields they missed as the format evolved: `attachment.snapshot.workingDirectory`, `toolUseResult.persistedOutputPath` and friends, `file-history-snapshot.realParentDir`, `file-history-delta.trackingPath`, and encoded bucket names embedded inside scratchpad and tool-result paths (claude-sesh-mover #127, against 2.1.277).

### 5.6 Hazards specific to a wrapper

- **Inherited session id.** A `claude` process started from inside a Claude Code session inherits `CLAUDE_CODE_SESSION_ID` and writes its transcript under the parent's id (Appendix A, test 3 wrote into the live session's id). Any Duo code path that spawns `claude` must scrub `CLAUDE_CODE_*` and `CLAUDECODE` from the child environment.
- **Credentials override.** `ANTHROPIC_API_KEY` set to a bogus value did not prevent network calls in this environment because host-managed credentials took precedence. Verification steps must not assume a dry run is free.
- **Symlinks.** Symlinked bucket directories stopped being followed by the picker at 2.1.104. Symlinked working directories are realpath-resolved before encoding (`/tmp/x` becomes `-private-tmp-x` on macOS). Symlinks are not a usable relocation primitive.
- **Mid-session `cd`.** v1's liveness check re-encoded a process's current cwd and so marked sessions as closed when `claude` changed directory, leading to a second resume writing to the same file (FOLLOWUP-054). The sessions beacon (§ 5.3) removes the guesswork.

---

## 6. Safety model and the central recommendation

### 6.1 R1: pointers are the truth; relocation copies Claude's own `/cd`

The owner's constraints (L4) were: no duplication that creates new problems, and clustering plus resumability above all. The research reframes the premise twice.

First, **on 2.1.223 and later, re-homing a session does not require moving its transcript.** Duo can record "session X belongs to project P, task T" and resume X from P's root with `claude --resume X`; Claude finds the transcript wherever it is, as long as there is exactly one copy. That is the whole clustering goal with zero writes to internal-format files. The registry pointer is therefore always written and is always the source of truth for membership.

Second, **when a transcript does need to move, Claude Code already defines how.** `/cd` renames `<id>.jsonl` and the `<id>/` sidecar into the new bucket and appends one `relocated` record; every reader prefers `relocatedCwd` over the head `cwd`. Nothing historical is rewritten. The earlier worry that a relocation must falsify `cwd` dissolves: a `relocated` record is an honest statement that the session now lives at a new path, which is exactly what the user asked for. Duo's relocation is defined as "do what `/cd` does to a session that is not running" and nothing more. The community tools' line-by-line path rewriting is rejected (§ 6.6); Claude itself does not do it, and it is the part of those tools that breaks on every release.

What a pointer alone does **not** give, and when relocation is therefore applied:

- **A folder move or merge** (S-MOVE): transcripts move with the folder in the same transaction (§ 7.5). Leaving them under a dead bucket name would mislead every other client.
- **An orphaned bucket** (S-RENAMED after the fact: the cwd no longer exists): relocation into the project root's bucket is the default when the user assigns the bucket, because the old bucket can never be a working directory again. The user can decline and keep a pointer only.
- **Native `/resume` parity for a bucket that stays where it is** (S-SCATTER subdirectories, scratch folders the user keeps): offered as an **alias**, by adding the bucket to the project root's `.session-aliases` (§ 7.4.7), which moves nothing. Explicit relocation remains available for users who want one bucket.
- **Protection from the retention sweep**: archive by move (R4).
- **A catch-all bucket** (S-JUNK: `$HOME`, `~/Desktop`, `~/Downloads`, `/tmp`, or any directory that can never be a project root): sessions are relocated **individually** into the destination project's bucket when assigned. Pointer-only would work for resume, but the catch-all bucket stays in daily use, so leaving the session there keeps it in the wrong picker forever, and aliasing is unusable because it would pull the whole drawer into the project. Per-session relocation is the only operation that splits a bucket.

Resume for a pointer-only session runs from the session's own recorded or relocated cwd when it exists, else from the project root (§ 7.7).

Copy-based safety nets were considered and rejected: a copy left anywhere under `projects/` makes `--resume <id>` fail by design, and a copy elsewhere is a backup, which is what the journal (§ 6.3) provides more cheaply.

### 6.2 Storage mode (L5) and the session-identity rules adopted from the path-binding research

The path-binding research doc reached the same storage facts independently and recommended a different posture: run Duo's sessions under a Duo-owned `CLAUDE_CONFIG_DIR` with `CLAUDE_CODE_PROJECT_DIR_NAME=duo-<projectId>`, so that a folder move needs no migration (its option B), with a rename-the-bucket migration as a fallback (its option C). The owner chose the shared `~/.claude` mode (L5). Reasons, in order:

1. The research doc's experiment 7 (rename the bucket, no rewrite) and its option H discussion predate the `relocated` record finding. With that record, relocation is a two-rename-plus-one-line operation that Claude Code itself performs for `/cd`, which removes most of the cost option B was avoiding.
2. A separate config dir means a separate login or API key, separate plugins and settings, and a terminal `claude` in the project folder that cannot see Duo's sessions. For a PM whose other tooling is the terminal, that is a visible regression.
3. Consolidation under option B would be a one-way import out of `~/.claude`; under shared mode it is an in-place reorganization that the terminal benefits from too.

The isolated profile remains a possible later setting (§ 10). Symlinked buckets are not followed by the picker (§ 5.6), so symlink anchors are out under either mode.

The following rules from that doc **are** adopted, because they hold in shared mode and make consolidation safer:

- **A. Explicit ids.** Duo creates every session with `--session-id <uuid>` and reopens only with `--resume <uuid>`. Duo never relies on `--continue` or the picker programmatically (FR-7.7.7).
- **F. Stable project identity.** Every project gets `<project>/.duo/project.json` with a `projectId`. The app registry maps `projectId` to last known path plus a macOS security-scoped bookmark, so a move or rename done in Finder is detected and reconciled (FR-7.5.9).
- **G. Never duplicate ids; fork on copy.** A second folder carrying a known `projectId` is a copy. Its inherited sessions are opened with `--fork-session` on first resume, and the new ids are recorded in the copy's index (FR-7.8.5).
- **I. Durability.** Archive by move (R4) plus an explicit, consented retention change (FR-7.6.3).

### 6.3 Invariants every physical operation must hold

1. **Uniqueness.** After the operation, each session id appears in exactly one bucket under every configured `projects/` root, or in the Duo archive, never both.
2. **Atomicity per file.** Target written to a temp name in the destination directory, fsynced, renamed into place, source unlinked last. Same-filesystem renames only; cross-filesystem moves are copy, verify by hash, then unlink, and are flagged in the plan.
3. **Write-ahead journal.** The full plan is persisted before the first mutation. Each step records old path, new path, byte size, content hash before and after rewrite, and mtime. A crash leaves a journal that the next launch detects and either completes or reverts.
4. **Liveness guard.** Refuse to touch any transcript whose id appears in a live beacon (`~/.claude/sessions/*.json` with a running pid) or whose bucket is the cwd of any running `claude` process, or any folder that is a cwd of any Duo tab or any process (checked with `lsof`).
5. **Encoder self-calibration.** Before any physical operation, Duo verifies its encoder against the machine: for every bucket that has a readable first `cwd`, `encode(cwd)` must equal the bucket name. One mismatch disables physical operations and reports the offending bucket. This catches a silent encoding change in a new CLI release before it costs the user anything.
6. **Version gate.** Physical operations are enabled only when the installed CLI is within the tested compatibility range (§ 11). Outside it, pointer operations remain available and the UI says why the rest is off.
7. **Mtime policy.** Rewritten transcripts keep their original mtime by default so the retention clock is unchanged and the user's sort order survives. Archive-to-preserve is the one operation that deliberately takes files out of the sweep's reach instead.
8. **Verification before success.** Every moved transcript is re-parsed; every record must parse as JSON; the byte content before the appended `relocated` record must hash identically to the source; the `relocated` record must be the last line and name the planned path; session id uniqueness is re-scanned. Only then does the journal entry flip to `committed`. An optional live smoke test (`claude -p --resume <id> "reply with OK"`) is offered, never run silently, because it costs tokens and emits a model call.
9. **Undo window.** Journals are retained for 30 days or until the user clears them; undo replays the journal in reverse, subject to the same invariants.

### 6.4 R2: a deterministic migrator, not an agent, performs moves

The owner's phrasing was that "the agent should ask the user" and then do the move so folders and logs move in tandem. Two readings exist. Recommended reading: Duo (the harness) is the agent that asks and executes, with a deterministic, tested code path. A Claude session can be the conversational front end that proposes a plan in natural language, but the plan is a data structure that the migrator validates and executes. Reasons: the invariants in § 6.3 are mechanical and must hold every time; an agent performing the operation is itself writing a transcript while rewriting transcripts, which is the kind of reentrancy that produced S-LIVE bugs in v1; and a failure needs a journal, not a conversation log. If the owner prefers the agent-executes reading, the migrator is exposed as `duo migrate plan|apply|verify|undo` on the socket CLI and the agent becomes one of its callers through a skill.

### 6.5 R4: archive means preserve

Claude Code's sweep deletes everything older than 30 days by default, without a trash. A Duo "archive" that is only a flag would leave the user with a tidy list of sessions that vanish on the next CLI start. Archive therefore moves the transcript and its sidecar directory to `~/.claude/duo/archive/<bucket>/<id>…`, which Claude never sweeps, keeps the registry pointer, shows it read-only, and restores by moving it back (uniqueness holds because it is a move). An archived session can still be resumed through `--resume <transcript path>` on the restore path (§ 7.6.1). Delete is separate, explicit, and lists exactly what goes (§ 7.6.2).

### 6.6 Rejected alternatives summary

| Alternative | Why not |
|---|---|
| Always physically move on re-home | Touches Claude's storage on every action for no gain the pointer does not already provide; removes the session from the picker of a directory the user may still use. |
| Line-by-line rewrite of path fields (the community-tool recipe) | Claude's own `/cd` does not do it; the field inventory changes every release (claude-sesh-mover #127); a missed field or an over-eager match silently damages a transcript. Degradations it would fix (`/rewind` snapshots after a folder move) are the same ones Claude accepts for `/cd`. |
| Copy, verify, delete later | Duplicate ids break resume by design; the "later" delete is the risky step anyway. |
| Symlink buckets | Not followed by the picker since 2.1.104. |
| `CLAUDE_CODE_PROJECT_DIR_NAME` | Requires taking over `CLAUDE_CONFIG_DIR`. |
| App registry as the source of truth for membership | Contradicts the brief's behaviour 6 (readable files near the work). Superseded by L6; § 8 gives the reconciliation rules that keep the project files and the registry from drifting. |
| Duo-owned `CLAUDE_CONFIG_DIR` profile (research option B) | Separate login, plugins and settings; terminal cannot see Duo sessions; consolidation becomes a one-way import. Not adopted for v2 (L5); possible later setting. |
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

### 7.2 Projects, tasks, and the Unfiled lane

- **FR-7.2.1** A **project** is a folder (L2) carrying `PROJECT.md` (human: goal, status) and `.duo/project.json` (machine: `projectId`, `schema`, `createdAt`). Creating a project from a legacy bucket writes both files into the chosen root after confirmation. Roots must be unique across projects. The app registry maps `projectId` to the last known path and a bookmark; a project whose root cannot be resolved is shown as **detached**, not deleted.
- **FR-7.2.2** A **task** is a markdown file in `<project>/tasks/` with frontmatter (`status`, `owner`, `waiting_on`, `done_when`, as the brief defines). This document only creates and links tasks; the task model itself belongs to the broader plan.
- **FR-7.2.3** The **session index** `<project>/.duo/sessions.json` is the canonical record of which sessions are filed under a project. Each entry: `sessionId`, `title` (user-editable), `tasks` (list of task file names; this side is canonical, task frontmatter `sessions:` is derived), `provenance` (`manual`, `inferred-from-cwd`, `created-by-duo`, `forked-from-copy`), `filedAt`, `note`, `storage` (`original` or `relocated`), `movedPaths`, `resumeNotePending`. It never stores the transcript path; the path is resolved live by id. A readable `sessions/index.md` is regenerated from it on every write, and the UI offers "show the file" for both.
- **FR-7.2.3a** A session is **Unfiled** when no project's index lists it. A session listed in two projects' indexes (a copied folder, a hand edit) is flagged for the user and treated as filed under the one whose folder holds the newer `project.json` bookmark resolution until resolved (FR-7.8.5).
- **FR-7.2.4** Every session in the inventory that no project's index lists is **Unfiled**. The Unfiled lane must show them grouped by resolved project root by default (this is display grouping, not a proposal), with alternate groupings by bucket, by month, by size, and flat.
- **FR-7.2.5** When a Duo-created project's root encloses a session's resolved root (same root, a subdirectory, or a worktree of it), the session must be displayed under that project with provenance `inferred-from-cwd` and a `subPath` or `worktree` badge, without being removed from Unfiled until the user confirms. Confirmation may be bulk ("accept all 34 inferred").
- **FR-7.2.6** Sessions Duo itself starts inside a project are attributed at creation (`created-by-duo`) and never enter Unfiled.
- **FR-7.2.7** Unfiled must surface a count in the primary navigation so new strays are noticed (goal 6).
- **FR-7.2.8** A configurable list of **non-project directories** (default: `$HOME`, `/`, `/tmp`, `~/Desktop`, `~/Downloads`, `~/Documents`) can never be a project root. Buckets for these directories are **catch-all buckets**: their sessions are always Unfiled until triaged, they are never offered Create-project-from-bucket, bucket-level alias or relocation, or folder move, and they get the split flow in § 7.10 instead. Subdirectories of a non-project directory (for example `~/Documents/thesis`) are ordinary candidates.

### 7.3 Curation surface (manual)

- **FR-7.3.1** A full-width curation view listing buckets and sessions with columns: title, project (if any), task, first cwd, latest cwd (if different), branch, last activity, size, live indicator, and badges for orphan, collision, duplicate id, worktree, subPath, sweep-eligible-within-N-days, superseded-copies-present.
- **FR-7.3.2** Sorting by any column; filters for live, orphan, collision, size over N, older than N, bucket, branch, text search over title and first prompt.
- **FR-7.3.3** Multi-select with shift and command ranges and select-all-in-filter. Every action in § 7.3.5 operates on the selection.
- **FR-7.3.4** Drag a session, a selection, or a whole bucket onto a project or task in a side rail to assign it. Drop on a project assigns without a task.
- **FR-7.3.5** Actions: Create project from bucket (root pre-filled from the bucket's resolved root; editable); Assign to project; Assign to task (create inline); Remove from project (back to Unfiled); Archive; Delete; Offer folder move (only when the bucket's cwd exists, § 7.5); Relocate storage (advanced, § 7.4); Repair duplicates; Open transcript read-only; Resume.
- **FR-7.3.6** Keyboard-first: every action reachable without the mouse; a command palette entry per action.
- **FR-7.3.7** The view must render usable within 1 s for 100 buckets and 2,000 sessions on the reference machine, with titles loading lazily.
- **FR-7.3.8** No automatic proposals of any kind (L3). The only suggestion-like element permitted is the display grouping by resolved root in FR-7.2.4 and the inferred attribution in FR-7.2.5, both of which are deterministic facts about paths, not similarity judgments.

### 7.4 Relocate storage and alias buckets

- **FR-7.4.1** Relocate moves selected transcripts into the bucket for the target project's root (or, for S-SCATTER, into the bucket of the session's own cwd when that differs from the project root and still exists). Its confirmation states: that the session will appear in the target directory's picker and leave the source directory's, that the session's history is not modified, and that file paths the session remembers will not change.
- **FR-7.4.2** Relocate must execute through the migrator with all § 6.3 invariants, as a plan with one step per path: `<id>.jsonl`, the `<id>/` sidecar directory, and any `<id>.jsonl.superseded-*`, `<id>.orphaned-*`, `<id>.ccr-tip.json`, and `<id>.precompact.json` siblings.
- **FR-7.4.3** The only content change is appending one `relocated` record, `{"type":"relocated","sessionId":"<id>","relocatedCwd":"<target directory>"}`, to the moved `<id>.jsonl`, after the rename, exactly as `/cd` does. **No other record is modified.** The known consequences are documented in the confirmation and in the session detail: `/rewind` snapshots recorded under the old folder path may not apply after a folder move; scratch and tool-result paths in old records point at the old bucket slug. A deep path rewrite is explicitly out of scope (§ 6.6).
- **FR-7.4.4** If the target bucket already contains a same-id transcript, the plan must stop and show both files (size, first and last timestamp) and offer: keep target and archive source, keep source and archive target, or cancel. Never overwrite, never leave both. (Claude's own `/cd` sets the existing file aside as `.superseded-<ms>`; Duo does not, because that leaves two readable copies in one bucket.)
- **FR-7.4.5** After relocation, any legacy `sessions-index.json` in the source or target bucket is deleted. Any `.session-aliases` line anywhere that names the source bucket is left as is (aliasing an empty bucket is harmless) unless the source bucket is removed. If the source bucket is now empty except for `memory/`, it is left in place and flagged; memory consolidation is out of scope.
- **FR-7.4.6** Relocate is refused for live sessions. A transcript whose latest cwd differs from its first cwd is relocatable; the `relocated` record simply states the new location.
- **FR-7.4.7 Alias.** When a whole bucket is assigned to a project and the user wants its sessions in the project root's native picker without moving them, Duo appends the bucket's absolute path to `<project root bucket>/.session-aliases` (creating the file if needed, one path per line, idempotent). The reverse action removes the line. Aliasing is offered for buckets whose directory still exists; orphaned buckets get relocation by default (§ 6.1). The confirmation says that the aliased sessions resume in their own directory, not the project root, when picked natively.
- **FR-7.4.8** Relocation is gated on the installed CLI understanding the `relocated` record. Duo verifies this by checking the binary for the `relocatedCwd` string once per binary change; absent that string, relocation and aliasing are disabled and pointers remain.

### 7.5 Folder move with tandem relocation

- **FR-7.5.1** When a selected bucket's cwd exists on disk and is not already a project root, the curation surface offers **Move folder into a project**. The offer is explicit; nothing moves without the user choosing a destination and confirming a plan.
- **FR-7.5.2** Destination options: rename in place to a new path; move under a chosen parent directory; move inside an existing project's root as a subfolder (**merge**, § 7.5.6). The destination must not exist, or must be an empty directory.
- **FR-7.5.3** Preconditions, all checked immediately before execution and again after the journal is written: no live session in any bucket whose cwd is inside the folder; no Duo tab, terminal, or canvas rooted inside the folder; no process with a cwd inside the folder (`lsof +D` on macOS and Linux); folder and destination on the same filesystem unless the user opts into copy-and-verify; encoder self-calibration passes; CLI version in range.
- **FR-7.5.4** The plan must list, as discrete reviewable steps: the folder rename; for every bucket whose cwd is inside the folder (the root, subdirectories, and worktrees that live inside it), the per-session relocation (§ 7.4.2 and § 7.4.3) into the bucket of the mapped new path, with `relocatedCwd` set to the mapped path of that session's own cwd; moving the source bucket's `memory/`, `tiny_memory/`, and `.session-aliases` into the new bucket when the source bucket becomes empty; re-keying of every `~/.claude.json` `projects[...]` entry whose key is inside the folder (keys are realpath-normalized); rewriting `history.jsonl` lines whose `project` is inside the folder under the file's own lock (opt-out available); rewriting `.session-aliases` lines in other buckets that name a moved bucket; deletion of any legacy `sessions-index.json`; `git worktree repair` for any git worktrees whose checkout lives inside the folder or whose main repo does; a note for worktrees of this repo that live outside the folder (their `.git` files point at the old path and `git worktree repair` from the new root fixes them); a note that `.claude/settings.local.json` travels with the folder; and registration of the new path as a project root (or as a subfolder of the merge target).
- **FR-7.5.5** Execution order: journal written; folder renamed first (so a crash leaves the user with a renamed folder and un-relocated transcripts, which 2.1.223+ can still resume by id, rather than relocated transcripts pointing at a folder that did not move); then transcripts; then settings; then index deletion; then verification; then journal commit. On any failure after the folder rename, the migrator attempts a reverse replay and reports precisely what state remains if reversal also fails.
- **FR-7.5.6** **Merge** is moving folder B to `A/<name>/` where A is a project root. Sessions from B are attributed to project A with `subPath` badges; the user may then group them into tasks. Content-level merging of trees is out of scope; if `A/<name>` exists and is non-empty, the move is refused.
- **FR-7.5.7** After commit, Duo must show a verification report: transcripts moved, records rewritten, settings re-keyed, worktrees repaired, and any warnings (for example, a session whose latest cwd was outside the folder).
- **FR-7.5.8** Undo replays the journal in reverse and is offered in the report and in a Migrations list under settings for 30 days.
- **FR-7.5.9 External move detected.** When a project's bookmark resolves to a new path, or a `.duo/project.json` with a known `projectId` appears at a new path while the old path is gone, Duo shows the brief's "project moved" notice: old path, new path, the number of sessions whose transcripts still sit under the old bucket, and one action, **Reconcile**, which runs FR-7.5.4 minus the folder rename (the folder already moved) under the same journal and guards. Until reconciled, the project's sessions keep resuming by id from the new root (pointer behavior), so nothing is lost in the meantime. The user may decline and keep pointers.

### 7.6 Archive and delete

- **FR-7.6.1 Archive (preserve).** Moves `<id>.jsonl`, its sidecar directory, and superseded or orphaned siblings to `~/.claude/duo/archive/<bucket>/`, preserving mtimes, via the migrator. The app registry's archive map records the original bucket, and the project's index entry, if any, is kept with `storage: archived`. Archived sessions are listed under their project in an Archived section, open read-only, and offer **Restore** (move back to the original bucket, or to the project root's bucket if the original cwd is gone, with the same collision handling as FR-7.4.4). Archive is refused for live sessions. Archive is bulk-capable.
- **FR-7.6.2 Delete.** Permanently removes the transcript, its sidecar directory, superseded and orphaned siblings, and the session-keyed directories under `file-history/`, `tasks/`, `debug/`, `session-env/`, `plans/`. The confirmation lists every path and total bytes, requires typing the count for selections over 10, and is journaled so the list of what was deleted survives even though the content does not. Delete never touches `~/.claude.json`, `history.jsonl`, or `memory/`; a separate **Forget folder** action wraps `claude purge <path>` for users who want the official behavior.
- **FR-7.6.3 Retention.** The brief commits Duo to raising retention. In shared mode that means editing the user's `~/.claude/settings.json`, so Duo asks once, during onboarding and again whenever the value is found below Duo's floor, with the exact edit shown (`cleanupPeriodDays` to a configurable default of 365) and a one-click accept. Duo never changes the value silently. Independently, a banner on the curation surface states the effective value and how many unfiled and filed sessions become sweep-eligible within 7 days, and offers to archive those.

### 7.7 Resume behavior

- **FR-7.7.1** Resuming a session from Duo runs `claude --resume <id>` with the child environment scrubbed of `CLAUDE_CODE_*` and `CLAUDECODE` variables.
- **FR-7.7.2** Working directory for the resume, in order: the transcript's `relocatedCwd` if present and existing on disk; else the session's latest recorded cwd if it exists on disk and is inside the project root; else the session's first recorded cwd if it exists and is inside the project root; else the project root. The chosen directory and the reason are shown in the terminal header. (v1 always used the recorded cwd and failed when it was gone, ENH-232.)
- **FR-7.7.3** On a CLI older than 2.1.223, resume must run from a directory whose bucket holds the transcript (the recorded cwd); if that directory is gone, Duo offers Relocate (which is the only way to make the session resumable on that CLI) and shows an upgrade nudge.
- **FR-7.7.4** Resuming a live session focuses the owning Duo tab if there is one; if a process outside Duo holds it, Duo offers `--fork-session` with an explanation, as v1 did, and never starts a second writer on the same transcript.
- **FR-7.7.5** Resuming an archived session restores it first (FR-7.6.1), then resumes.
- **FR-7.7.6** The inventory must re-scan on filesystem change under `projects/`, because the user can relocate a live session with `/cd` or worktree enter/exit at any time; pointers keyed by session id keep resolving regardless of which bucket the file is in.
- **FR-7.7.7** Every session Duo starts is created with `--session-id <uuid>` minted by Duo and written to the project's session index before the process launches, so Duo never has to guess which transcript a tab produced (v1's newest-file guess) and never depends on `--continue` or the picker. (Research option A.)

### 7.8 Repair tasks

- **FR-7.8.1 Duplicate ids.** Show both copies with size and time range; actions: archive the older, archive the smaller, open both read-only. Never auto-pick.
- **FR-7.8.2 Collisions.** When a bucket holds sessions from two or more distinct cwds, attribution and resume operate per session on its own cwd. Physical operations on the bucket are refused until the user chooses which cwd's sessions the operation applies to; the migrator then moves only those files, never the whole bucket.
- **FR-7.8.3 Legacy index.** If a bucket contains a `sessions-index.json` (written by older CLIs, unused by 2.1.288), offer to delete it; on an older CLI that still reads it, warn that it is stale when it lists a session not on disk or omits one that is.
- **FR-7.8.4 Interrupted migration.** On launch, any journal not in `committed` or `reverted` state blocks physical operations until the user chooses complete or revert; the UI shows the step reached.
- **FR-7.8.5 Copied project.** When two folders carry the same `projectId`, the one the bookmark resolves to is the original and the other is a **copy**. Duo mints a new `projectId` for the copy after confirmation, keeps its `sessions.json` but marks every entry `forked-from-copy` pending, and on first resume of such a session runs `--resume <id> --fork-session` from the copy's root and records the new id in the copy's index. The original's sessions are never relocated into the copy. (Research option G.)

### 7.9 Agent-facing surface and Home (L8)

- **FR-7.9.1** Every read in § 7.1 is available on Duo's socket CLI (`duo sessions list|show`, `duo projects list`), with JSON output. The write actions in § 7.3.5 are also exposed (`duo migrate plan|apply|verify|undo`, `duo archive`, `duo delete`, `duo file`) for Duo's own UI and for scripting by the user; every physical operation still goes through the migrator's confirmation and guards, and the CLI refuses to run them when invoked from inside a Claude Code session (detected by `CLAUDECODE` in the environment) so that an agent cannot drive consolidation.
- **FR-7.9.2** Home may read the unfiled count and the catch-all bucket list through the CLI and surface them as an inbox item or a status line that deep-links into the consolidation view. Home does not propose destinations, create tasks for legacy sessions, or file anything. If that changes later, the proposal path is an amendment to L3 and L8, not a silent extension.

### 7.10 Splitting a catch-all bucket (S-JUNK)

The catch-all bucket is the hardest case because the bucket is correct for most of its sessions and wrong for the clusters inside it, and because the clusters may have no home directory yet. Everything here operates on a **selection of sessions**, never on the bucket.

**Evidence (requires L3a)**

- **FR-7.10.1** Opening a catch-all bucket shows a per-session table with evidence columns in addition to § 7.3.1: **files edited** (count and the common ancestor directory), **date cluster**, **lineage** (forked-from, continued-in, continued-from), **tag** records, branch, first prompt, and the resolved **candidate home** (FR-7.10.3).
- **FR-7.10.2 Files edited** are extracted deterministically from the transcript: `file-history-snapshot` and `file-history-delta` records (`trackingPath`, `realParentDir`), `tool_use` inputs of the file-editing tools (`file_path`, `notebook_path`, `path`), and `toolUseResult.filePath`. Read-only tool calls and shell commands are excluded (too noisy to be evidence). Extraction is a streaming full-file parse run on demand for the opened bucket only, bounded by a per-file size cap with a "partial" marker beyond it, cached in memory keyed by file mtime and size, and never persisted (§ D9).
- **FR-7.10.3 Candidate home** of a session is the deepest directory that contains every file it edited, computed after discarding paths under the bucket's own directory root, system and temp directories, and `~/.claude`. If that directory is inside an existing project root, the project is named. If no files were edited, the column is empty. This is shown as a fact per session; Duo never pre-selects sessions or proposes a group.
- **FR-7.10.4 Date clusters** group sessions by activity gaps: sessions whose active intervals are within a configurable gap (default 48 hours) of each other form one cluster, labeled by date range. Deterministic and explained in a tooltip.
- **FR-7.10.5** Facets and filters over all of the above: by candidate home, by date cluster, by lineage chain, by tag, by edited-path prefix (typed), by text in first prompt and titles. Filters compose. The selection follows the filter, so "all sessions whose candidate home is `~/Documents/thesis`" is two clicks, and the user still confirms the selection by eye before acting.

**Destinations for a selection**

- **FR-7.10.6 Existing project.** Assign the selection to a project and optional task. Because the source is a catch-all bucket, each session is also relocated (§ 7.4.2 and § 7.4.3) into the bucket of the project root, with `relocatedCwd` set to the project root. The user may choose a subdirectory of the root instead (for example the candidate home when it is inside the project), in which case `relocatedCwd` is that subdirectory and the session shows a `subPath` badge. A "pointer only, leave the file" override exists but is not the default here.
- **FR-7.10.7 Existing folder that is not yet a project.** When the candidate home or a user-picked directory exists on disk but has no project, the dialog offers **Create project from this folder** inline (root pre-filled, name editable) and continues as FR-7.10.6.
- **FR-7.10.8 New project folder.** When the cluster has no home, the dialog offers **Create a new project folder**: name; a **topic** (the parent folder) picked from existing topic folders under the workspace root or typed new, defaulting to the workspace root itself (default `~/work`, created on first use after confirmation); options to `git init` (off by default, most PM projects are plain folders), to seed `CLAUDE.md`, and the project files from FR-7.2.1 which are always written. Duo creates the directory, writes `PROJECT.md` with the name and an empty goal, registers the project, and relocates the selection into its bucket as in FR-7.10.6. The destination must not already exist or must be an empty directory. This is the same "create project" flow the brief specifies (flow C4), entered with a selection in hand.
- **FR-7.10.9 Task on the way in (L7).** Every destination dialog has an optional task field: pick an existing task from the project's `tasks/` or create one inline with a title and a status the user chooses (done for finished work, open or in progress for unfinished). Linking writes the task names into the session index entries; task frontmatter is updated as a derived view. Sessions filed without a task show as unlinked in the project, per the brief.
- **FR-7.10.10 Settings carry-over.** The dialog offers to copy `allowedTools`, `mcpServers`, and `enabledMcpjsonServers` from the catch-all bucket's `~/.claude.json` project entry into the destination root's entry, defaulting to off. Trust (`hasTrustDialogAccepted`) is never copied; the first resume in a new folder goes through Claude's own trust prompt.

**Moving the work product (optional, per path)**

- **FR-7.10.11** After a destination is chosen, if the selection's edited files lie outside every project root, Duo lists them grouped by their common ancestors and offers to **move** chosen paths into the destination root, preserving relative structure below the chosen ancestor. Each path is a checkbox, default unchecked. Refused: paths inside another project's root, inside a git repository other than the destination (the user is pointed at Folder move § 7.5 for whole repos), inside system or application-support directories, or currently open in any Duo tab or held by any process. Moves are journaled and undoable with the session relocations in the same journal.
- **FR-7.10.12** Moving files does not modify transcripts (§ 6.6). Duo records the path mapping in the session's index entry, shows it in the session detail, and on the next resume of an affected session passes a short note through `--append-system-prompt` listing the old and new locations, so the model learns where its files went. The note is omitted once the user clears it or after the first resume completes.

**The remainder**

- **FR-7.10.13** After each split, the catch-all view shows what remains and offers per-session or bulk **Archive**, **Delete**, or **Leave** (a triage state in the app registry's unfiled map meaning "noise, let retention handle it"). Leave removes the session from Unfiled without moving it and is reversible. Sessions marked Leave are excluded from the retention banner's counts.
- **FR-7.10.14** A catch-all bucket's live sessions (a terminal is open in `$HOME` right now) are shown but cannot be relocated until they end; they can be pointer-assigned.
- **FR-7.10.15** Lineage integrity: when a session is relocated, sessions linked to it by fork or continuation are highlighted in the selection dialog so the user can take the chain together. Duo never auto-includes them.

---

## 8. Data model

Two stores, with a clear division (L6). **Project files are canonical for everything about a project and its sessions.** The **app registry** holds only what has no project yet or what is machine-local by nature: project id to path resolution, migration journals, archive locations, triage state of unfiled sessions, and settings.

**In each project folder** (readable, travels with the folder, may be committed or synced):

```
<project>/
  PROJECT.md                 # human: name, goal, status (brief)
  tasks/<task>.md            # human: frontmatter status, owner, waiting_on, done_when; sessions: derived
  .duo/project.json          # { "schema": 1, "projectId": "<uuid>", "createdAt": "…" }
  .duo/sessions.json         # canonical session index, see FR-7.2.3
  sessions/index.md          # generated, readable mirror of sessions.json
```

`sessions.json` entry:

```jsonc
{ "sessionId": "466c9002-…", "title": "Interview synth",
  "tasks": ["draft-prd-v2.md"],
  "provenance": "manual",               // manual | inferred-from-cwd | created-by-duo | forked-from-copy
  "filedAt": "…", "note": "",
  "storage": "relocated",               // original | relocated   (where the transcript lives relative to this project's bucket)
  "movedPaths": [{ "from": "~/notes/cli.md", "to": "~/work/tools/cli/notes/cli.md", "at": "…" }],
  "resumeNotePending": true }
```

**App registry** at `~/.claude/duo/registry.json`, written atomically, schema-versioned, with rotating backups:

```jsonc
{
  "version": 2,
  "projects": {
    "<projectId>": { "lastKnownPath": "/Users/me/work/payments/checkout-redesign",
                     "bookmark": "<base64 security-scoped bookmark>", "lastSeenAt": "…" }
  },
  "unfiled": {
    "<sessionId>": { "triage": "leave", "at": "…" }      // only sessions with no project; FR-7.10.13
  },
  "archive": {
    "<sessionId>": { "bucket": "-Users-me-Desktop-foo-test", "projectId": "<projectId or null>", "archivedAt": "…" }
  },
  "settings": {
    "workspaceRoot": "/Users/me/work",
    "nonProjectDirectories": ["~", "/", "/tmp", "~/Desktop", "~/Downloads", "~/Documents"],
    "dateClusterGapHours": 48,
    "retentionFloorDays": 365
  }
}
```

**Reconciliation rules** (so the two stores cannot drift in ways that matter):

1. Membership is read from the project files on every inventory pass; the registry never caches membership.
2. A session listed by two projects is a conflict surfaced to the user (FR-7.2.3a), never silently resolved.
3. A registry `projects` entry whose path and bookmark both fail to resolve marks the project detached; the entry is kept until the user removes it or the manifest reappears.
4. A `.duo/project.json` found by scan with an unknown `projectId` is adopted into the registry as a project (the folder was created elsewhere or synced in).
5. The archive map is the only place that knows where an archived transcript went; losing the registry loses archive locations, so the archive directory layout also encodes bucket and session id, and a rebuild scans it.

This satisfies the v1 § D9 litmus: project files are Duo-owned concepts the external system does not track; the registry holds pointers and machine-local state; nothing mirrors Claude Code's storage.

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
| Q1 | ~~Does interactive `--resume <id>` from another directory relocate the transcript?~~ **Closed 2026-10-03:** no. The resume path loads `relocatedCwd` into memory and never calls the relocation routine; only `/cd` and worktree enter/exit move files. | — | — |
| Q2 | Which version introduced `--resume <transcript path>`, and which introduced the `relocated` record (presumably with `/cd` in 2.1.169)? | Sets the floor for FR-7.6.1 restore-and-resume, the S-OLDCLI fallback, and the FR-7.4.8 gate. | Changelog bisect; FR-7.4.8's binary probe covers the record regardless. |
| Q3 | ~~Does resume itself filter by recorded cwd?~~ **Closed 2026-10-03:** no. The cwd filter is picker-only and triggers only on same-slug collisions; the id resolver never inspects cwd except to validate over-200-character sibling buckets. | — | — |
| Q10 | Does the owner accept L3a (deterministic evidence facets) for the catch-all case? | Without it § 7.10 degrades to a sortable list of 83 first prompts. | Owner review; the facets are additive and can be hidden behind a toggle if preferred. |
| Q11 | Should the `--append-system-prompt` note about moved files (FR-7.10.12) be used more broadly, for example after any folder move, to tell the model its paths changed? | Same mechanism, wider benefit; also a wider surface for confusing the model. | Ship for catch-all file moves first; measure. |
| Q9 | How stable is `.session-aliases`? It is undocumented, read by the picker, and in the sweep's reserved set. | FR-7.4.7 writes it. If a release changes its format or stops reading it, aliases silently stop working (no data loss). | Treat as best-effort; the inventory verifies each alias line still resolves and reports dead ones; probe the binary for the filename as FR-7.4.8 does for `relocatedCwd`. |
| Q4 | Should prompt history (`history.jsonl`) follow a folder move by default? | Privacy (plaintext prompts) versus continuity of up-arrow history. | Owner call; default proposed: yes, with opt-out in the plan. |
| Q5 | Auto memory per bucket: leave, or offer a merge into the project root's `memory/`? | Memory fragmentation is the same chaos one level down (issue #34437). | Follow-on PRD; in this one, surface the fact in the bucket detail. |
| Q6 | Task nesting and cross-project tasks. | L2 fixes one root per project; nothing yet says whether a task can span projects. | Defer; flat per project in v2.0. |
| Q7 | Should Duo set `CLAUDE_CODE_PROJECT_DIR_NAME` for sessions it launches if Anthropic decouples it from `CLAUDE_CONFIG_DIR`? | Would make Duo-created sessions path-independent from day one. | Watch the changelog; revisit. |
| Q8 | Which of R1–R4 does the owner confirm or flip? | Each flips a section of § 7. | Owner review of this draft. |

---

## 11. Compatibility matrix and version gates

| Capability Duo relies on | Minimum CLI | Behavior below minimum |
|---|---|---|
| Cross-bucket `--resume <id>` | 2.1.223 | Resume only from the recorded cwd; Relocate offered when that cwd is gone (FR-7.7.3). |
| Picker filters colliding buckets by cwd | 2.1.239 | Relocated transcripts with correct cwd are visible either way; un-rewritten ones may show in the wrong picker. Informational. |
| No silent overwrite on same-id relocation | 2.1.251 | Duo's own FR-7.4.4 check protects regardless; the gate exists for `/cd` done by the user. |
| `/cd` relocation and the `relocated` record | 2.1.169 presumed (Q2); verified per binary by FR-7.4.8 | Relocation and aliasing disabled; pointers, archive, delete remain. |
| `.session-aliases` read by the picker | observed 2.1.288; introduction unpinned; verified per binary | Aliasing hidden. |
| Live-session beacons in `~/.claude/sessions/` | observed 2.1.288; introduction version unpinned | Fall back to v1 process walk. |
| `claude purge <path>` | 2.1.288 | Forget-folder action hidden. |
| Tested physical-operation range | 2.1.223 to the last version with fixtures (§ 13) | Physical operations enter caution mode; pointers, archive-by-move, and delete remain enabled. |

Duo reads `claude --version` once per binary change. A CLI newer than the tested range puts physical operations in **caution mode**: enabled only after encoder self-calibration passes and the user acknowledges a one-time notice.

---

## 12. Phasing

| Phase | Delivers | Exit criterion |
|---|---|---|
| P0 Inventory | § 7.1, § 7.8 detection only, retention banner (FR-7.6.3), beacon-based liveness. Read-only. | Reference machine's 41 buckets inventoried with zero crashes; every collision and orphan on it correctly flagged. |
| P1 Curate | Project files and app registry (§ 8), projects and tasks (§ 7.2), catch-all detection (FR-7.2.8), curation surface (§ 7.3) minus physical actions, pointer re-home, resume rules (§ 7.7), Unfiled lane, socket CLI reads, catch-all evidence table and facets (FR-7.10.1 to 7.10.5), new-project-folder creation (FR-7.10.8) with pointer assignment. | S-RENAMED and S-SCATTER walk end to end; every re-homed session resumes from its project; S-JUNK walks with pointers only. |
| P2 Retire and relocate | Migrator core with journal, undo, interrupted-migration repair (FR-7.8.4); per-session relocation with the `relocated` record (§ 7.4); archive by move and restore (FR-7.6.1); delete (FR-7.6.2); Leave triage (FR-7.10.13); catch-all split with relocation (FR-7.10.6 to 7.10.10). | S-TRASH, S-RETAIN and S-JUNK walk end to end; kill-during-archive test leaves a repairable journal; a relocated catch-all session appears in the project root's native picker and no longer in `$HOME`'s. |
| P3 Move | Folder move with tandem relocation (§ 7.5), encoder self-calibration, collision-aware partial moves (FR-7.8.2), `git worktree repair`, work-product moves for catch-all clusters (FR-7.10.11 and 7.10.12). | S-MOVE, S-LIVE refusal, S-COLLIDE partial move pass; undo restores byte-identical state. |
| P4 Advanced | Explicit Relocate (§ 7.4), duplicate repair UI (FR-7.8.1), agent-facing plan hand-off (§ 7.9), caution mode. | A Claude session inside Duo drafts a plan that the user approves and the migrator applies. |

---

## 13. Acceptance and test strategy

- **Encoder conformance.** A table-driven test of the encoder against paths with dashes, dots, underscores, spaces, unicode, symlinks, Windows drive letters, and the 200-character boundary, plus the runtime self-calibration (§ 6.3 item 5) run against real buckets in CI fixtures.
- **Fixture corpus.** Anonymized transcripts captured from each CLI version in the compatibility range, including mixed-cwd files, subagent layouts old and new, superseded siblings, worktree bindings, `relocated` records, `custom-title` records and sidecars, and buckets with `.session-aliases`. The relocation test asserts that the moved file equals the source plus exactly one appended `relocated` line, and that the real CLI's picker (driven headlessly where possible, else the SDK `listSessions`) reports the session under the target directory.
- **Parity with `/cd`.** For each fixture, relocating with Duo and relocating by running the real CLI's `/cd` must produce the same bucket layout and an equivalent tail record.
- **Round trip.** Relocate then undo yields byte-identical files (the appended record removed) and identical mtimes. Archive then restore likewise. Alias then unalias leaves `.session-aliases` byte-identical.
- **Crash injection.** Kill the migrator after each step of a folder move; on relaunch the journal is detected and either completion or reversal yields a consistent state with uniqueness intact.
- **Uniqueness fuzz.** Random sequences of relocate, archive, restore, and folder move across randomly colliding paths never produce a duplicate id under `projects/`.
- **Liveness.** With a `claude` process running in a bucket, every physical action on that bucket is refused and pointer actions succeed.
- **Catch-all evidence.** Fixtures with known edited-file sets assert the extraction in FR-7.10.2 (including snapshot records, each editing tool, and a truncated oversize file marked partial), the candidate-home computation (FR-7.10.3) across nested, disjoint, and system-path cases, and date clustering (FR-7.10.4) at the gap boundary. A synthetic 83-session `$HOME` bucket must render its evidence table within 3 s.
- **Catch-all split.** Relocating a selection out of a bucket leaves every unselected session untouched byte for byte, leaves the bucket's `memory/` and `.session-aliases` in place, and the relocated sessions list under the destination in the real CLI's picker. New-project creation refuses a non-empty destination. Work-product moves refuse paths inside other project roots and foreign git repositories, and undo restores both files and transcripts.
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

Listed for completeness and for the inventory's collision and orphan checks. **Duo does not rewrite any of them** (FR-7.4.3); this is the inventory of what a deep-rewrite tool would have to track, and why that approach was rejected.

Top-level `cwd` on every record; tail `relocated.relocatedCwd` (authoritative when present); `attachment.snapshot.workingDirectory`; `attachment.snapshot.scratchpadDirectory`; `attachment.snapshot.additionalWorkingDirectories[]`; `file-history-snapshot.realParentDir`; `file-history-delta.trackingPath`; `toolUseResult.persistedOutputPath`; `toolUseResult.transcriptDir`; `toolUseResult.scriptPath`; `toolUseResult.filePath`; tool inputs and outputs containing absolute paths (not rewritten by default; see FR-7.4.3's generic prefix rule); bucket names embedded inside scratchpad and tool-result paths (for example `/tmp/claude-0/-home-user-duo-v2/…`), which must be rewritten with the encoded old and new bucket names as well. `sessions-index.json`: `fullPath`, `projectPath`, `originalPath`. `~/.claude.json`: `projects` keys. `history.jsonl`: `project`.

## Appendix C — References

Official: `code.claude.com/docs/en/sessions`, `…/claude-directory`, `…/worktrees`, `…/permissions`, `…/agent-sdk/sessions`, `…/env-vars`, `…/claude-code-on-the-web`; `anthropics/claude-code` `CHANGELOG.md` entries 2.1.94, 2.1.98–2.1.108, 2.1.169, 2.1.196, 2.1.198, 2.1.211, 2.1.223, 2.1.224, 2.1.234, 2.1.239, 2.1.248, 2.1.251, 2.1.288.
Issues: #5768, #7009, #21085, #24271, #24729, #25032, #22205, #27473, #33634, #34437, #35162, #40946, #41591, #46784, #51488, #58591, #59248, #79215, #80906, #86713, #88603, #93743, #96323, #98575.
Community tools: `tsvikas/claude-mv`, `Mahiler1909/claudepath`, `NotebookNomad/claude-move`, `wsagency/claude-move-project`, `Sertelegger/claude-sesh-mover` (issue #127), `daaain/claude-code-log`, `ccusage` directory detection docs, `frederick-douglas-pearce/claude-code-sessions`, the samkeen gist on `~/.claude.json` project entries, `scenee` on `CLAUDE_CODE_PROJECT_DIR_NAME`.

## Appendix D — What Duo v1 already has (reusable) and lacks

Reusable from `dudgeon/duo` v0.13.8: `claude-session-tracker.ts` head and tail readers (`readSessionHeadMeta`, `readSessionTailMeta`, `listTopLevelSessions`) and the title preference chain (`custom-title` > `ai-title` > cleaned first prompt > uuid prefix); `home-snapshot.ts` `rollupProjects` (worktree fold via `gitdir:`, deepest enclosing git or marker root); `buildResumeCommand`; the socket CLI pattern; the `~/.claude/duo/` atomic JSON store pattern; `docs/DECISIONS.md` § D9 (no sidecar) as the governing rule for § 8.

Lacking in v1 and required here: an encoder that replaces all non-alphanumerics (v1 replaced only `/` and `.`); per-session cwd attribution in collided buckets (v1 applied the newest session's cwd to the whole bucket); liveness by session id (v1 guessed from process cwd, FOLLOWUP-054); any grouping, archiving, manual attribution, or migration code; handling of a missing cwd on resume (ENH-232); dismiss or archive (ENH-233).

## Appendix E — Glossary

- **Bucket:** a directory under `~/.claude/projects/`, named by encoding a working directory.
- **Catch-all bucket:** the bucket of a directory that can never be a project root (`$HOME`, `~/Desktop`, `/tmp`). Not to be confused with **Home**, the brief's triage project.
- **Transcript:** a session's `<id>.jsonl` plus its sidecar directory and set-aside siblings.
- **Topic:** a parent folder that groups projects (brief). Not modeled here beyond being the destination parent when a project is created.
- **Project:** a folder with `PROJECT.md` and `.duo/project.json`; one root directory; owns tasks and a session index.
- **Task:** a markdown file in the project's `tasks/`; many-to-many with sessions.
- **Session index:** `<project>/.duo/sessions.json`, the canonical list of sessions filed under a project, mirrored to `sessions/index.md`.
- **Unfiled:** a session no project's index lists.
- **File (verb) / re-home (pointer):** adding a session to a project's index without touching its transcript.
- **Relocate:** physically moving a transcript into another bucket with path rewrites.
- **Tandem move:** a folder move that relocates its transcripts and path-keyed settings in the same journaled transaction.
- **Beacon:** `~/.claude/sessions/<pid>.json`, written by a running Claude Code process.
- **Sweep:** Claude Code's startup deletion of files older than `cleanupPeriodDays`.
