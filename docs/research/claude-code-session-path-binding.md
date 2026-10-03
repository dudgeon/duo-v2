# Claude Code session ↔ folder binding: what breaks on move, and how Duo should handle it

Status: research input for design. Date: 2026-10-03. Claude Code CLI **2.1.288** (macOS, arm64).

Evidence labels used throughout:

- **[VERIFIED-LOCAL]**: reproduced on this machine against CLI 2.1.288. The tests ran in a throwaway `CLAUDE_CONFIG_DIR` under the session scratchpad, and nothing under `~/.claude` was modified.
- **[OBSERVED]**: read-only inspection of the existing `~/.claude` state on this machine.
- **[OFFICIAL]**: Anthropic docs or the CLI changelog (local cache `~/.claude/cache/changelog.md`, mirrors https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md).
- **[MAINT]**: an Anthropic maintainer said it in a GitHub issue.
- **[ISSUE]**: a user report not confirmed by staff.
- **[UNVERIFIED]**: inference or untested.

---

## TL;DR

1. **Claude Code keys session storage by the launch directory's absolute real path.** Transcripts go to `~/.claude/projects/<encoded-path>/<sessionId>.jsonl`, where `<encoded-path>` is the path with every non-`[A-Za-z0-9]` character replaced by `-`. Paths over 200 characters are truncated to 200 and get `-<base36 hash>` appended. Symlinks are resolved first. [VERIFIED-LOCAL]
2. **Moving or renaming a folder orphans its sessions for `claude --continue`, the default `/resume` picker, auto-memory, and per-project trust and settings.** After a rename, `-c` silently started a *new* session. [VERIFIED-LOCAL]
3. **Resuming by explicit ID still works after a move.** `claude --resume <session-id>` from any directory found the session, and so did `--resume <path/to/transcript.jsonl>`. It keeps appending to the *old* project directory's file, and new records carry the new `cwd`. [VERIFIED-LOCAL; OFFICIAL since about 2.1.223]
4. **Resume by ID fails when the same session ID exists in two project directories**, with `No conversation found with session ID`. Copying transcripts (rather than moving them) is therefore dangerous. [VERIFIED-LOCAL]
5. **There is a supported way to make the storage key path-independent.** Set `CLAUDE_CODE_PROJECT_DIR_NAME=<stable-name>`, which is **only honored when `CLAUDE_CONFIG_DIR` is also explicitly set**. With it, `-c` found the session after the folder was moved. [VERIFIED-LOCAL; OFFICIAL 2.1.234]
6. **Symlink anchors do not work as hoped.** Launching from a symlink records and keys on the *resolved* real path. [VERIFIED-LOCAL] The inverse layout works: a stable real directory with user-visible symlinks pointing at it.
7. **Transcripts are deleted after 30 days by default** (`cleanupPeriodDays`). Only sessions written by the Claude Desktop app are exempt. [OFFICIAL] A wrapper app that needs durable history must set retention itself, archive the transcripts, or both.
8. **Recommendation:**
   - Duo owns the binding. Give each project a stable ID in a project-local manifest, and track it with an app registry plus macOS bookmarks.
   - Always create sessions with `--session-id` and reopen them with `--resume <id>`. Never rely on `-c` or the picker.
   - Run Claude Code under a Duo-managed `CLAUDE_CONFIG_DIR` with `CLAUDE_CODE_PROJECT_DIR_NAME=<projectId>`, so a folder move needs **no** migration at all.
   - Set a long retention and archive the transcripts.
   - Keep a migrate-on-move routine only as a fallback, for projects that run under the user's default `~/.claude`.

---

## How Claude Code stores sessions

### Layout [OBSERVED]

```
~/.claude/
  projects/
    <encoded-launch-path>/
      <sessionId>.jsonl          # transcript, append-only JSON Lines
      <sessionId>/               # per-session sidecar dir (newer CLIs)
        subagents/agent-<id>.jsonl + agent-<id>.meta.json
        tool-results/<id>.txt    # large tool outputs spilled to disk
        custom-title.json        # {customTitle}
        ccr-tip.json             # {eventId, updatedAt}  (remote-control)
      memory/                    # auto-memory (MEMORY.md + topic files) — per PROJECT PATH
      bridge-pointer.json        # {sessionId, environmentId, source, pid, procStart} (remote bridge)
  history.jsonl                  # global prompt history: {display, pastedContents, project, sessionId, timestamp}
  sessions/<pid>.json            # live-process registry: {pid, sessionId, cwd, name, status, entrypoint, ...}
  session-env/<sessionId>/       # per-session env (keyed by session ID, not path)
  file-history/<sessionId>/      # edit backups for /rewind (keyed by session ID)
  shell-snapshots/, backups/, cache/, plugins/, skills/, uploads/<sessionId>/ ...
~/.claude.json                   # global config incl. "projects": { "<abs path>": {...} }
```

### Directory-name encoding [VERIFIED-LOCAL]

The rule is `encoded = realpath(cwd).replace(/[^a-zA-Z0-9]/g, "-")`. When the result is longer than 200 characters, the name becomes `encoded.slice(0,200) + "-" + base36(abs(javaStringHash(realpath)))`.

| Launch path | Encoded dir name | Note |
|---|---|---|
| `/Users/geoff/repos/duo-v2` | `-Users-geoff-repos-duo-v2` | leading `/` → leading `-` |
| `…/w/a.b_c d` | `…-w-a-b-c-d` | `.`, `_`, space all → `-` |
| `…/w/A_B`, `…/w/A-B`, `…/w/A.B` | **all** `…-w-A-B` | **collision**: three different folders share one project dir. In the test it held 3 transcripts. |
| `…/w/ünï-côde` | `…-w--n--c-de` | each non-ASCII code point → one `-` (NFC input) |
| `/private/tmp/claude-501/-Users-…` | `-private-tmp-claude-501--Users-…` | `/-` → `--` |
| 435-char path | first 200 sanitized chars + `-z6muva` | Hash = `Math.abs(javaHash(rawPath)).toString(36)` computed over the **unsanitized** path. I reproduced it exactly with Node; this is reverse-engineered and could change. |
| `/tmp/...` (symlink to `/private/tmp`) or a custom symlink → `…/w/plain` | `…-w-plain` (the **target**) | Symlinks are resolved. The `cwd` field also records the real path. |

Implications:

- The encoding is lossy and not injective, so a folder name cannot be recovered from the dir name. Use the `cwd` field inside the transcript instead.
- Lookalike folders (`my_proj` vs `my-proj`) share a project dir. The CLI has added disambiguation for `-c` (2.1.239 [OFFICIAL]), but at the filesystem level they still share it.
- The docs describe the slug and the 200-char truncation as internal and subject to change [OFFICIAL, per web research]. Duo should not compute slugs itself unless it has to. If it must (for the migrate fallback), it should verify the result against the transcript's `cwd`.

### What is keyed to the folder

The project dir is keyed to the **launch** cwd, not the current one. [OBSERVED] The per-record `cwd` field follows the shell as it changes directory: one session here has 9 distinct `cwd` values in one file. The file stays filed under the launch path. `/cd` (interactive only, 2.1.169+) and worktree enter/exit *relocate* the transcript to the new cwd's dir. [OFFICIAL] `/cd` is not available in `-p` mode ("/cd isn't available in this environment"). [VERIFIED-LOCAL]

### Transcript (`.jsonl`) record shape [OBSERVED: field names only]

Every line is one JSON object with a `type` field. The types seen:

| `type` | Notable fields |
|---|---|
| `user`, `assistant` | `uuid`, `parentUuid` (the conversation is a tree, and resume follows the leaf), `sessionId`, **`cwd`**, **`gitBranch`**, `version` (CLI version), `entrypoint` (`cli` / `sdk-cli` / `claude-desktop`), `timestamp`, `isSidechain`, `userType`, `message` (API message; tool_use `input` holds **absolute paths** such as `file_path`), `toolUseResult` (e.g. `filePath`, `structuredPatch`, `originalFile`), `promptId`, `requestId`, `permissionMode`, `isMeta`, `isCompactSummary`, `remoteSourced` |
| `attachment` | `attachment.type` such as `edited_text_file` (`filename` is absolute, `displayPath` is relative to cwd), `file`, `environment`, reminders. Also `cwd`, `gitBranch`, `uuid`, `parentUuid` |
| `system` | `subtype`: `compact_boundary` (`compactMetadata`, `logicalParentUuid`), `stop_hook_summary`, `turn_duration`, `informational`, `local_command`, `away_summary`. Also `cwd`, `gitBranch` |
| `last-prompt` | `lastPrompt`, **`leafUuid`**, `sessionId` |
| `custom-title`, `agent-name` | `customTitle` / `agentName`, `sessionId` |
| `file-history-snapshot` | `messageId`, `snapshot.trackedFileBackups` (keyed by file path), `isSnapshotUpdate` |
| `permission-mode`, `mode`, `cost-state`, `queue-operation`, `atis-latch`, `pr-link` (`prNumber`, `prRepository`, `prUrl`) | session-level metadata, carrying `sessionId` and no `cwd` |

Other observations:

- No legacy `{"type":"summary"}` lines exist in this CLI version. The title comes from `custom-title` and `last-prompt` entries and the `custom-title.json` sidecar. [OBSERVED]
- `sessionId` always equals the filename stem. [OBSERVED] Session IDs are UUIDs: v4 for most sessions, while some SDK or remote sessions use deterministic v5-style UUIDs.
- Absolute paths appear in `cwd`, in tool inputs and results, and in attachments. Rewriting every `cwd` cannot make the *conversation content* path-correct. On resume, the model will still "remember" old absolute paths in earlier tool calls. [OBSERVED / UNVERIFIED impact]

---

## Everything keyed by path

| Location | Keyed on | Contents (structure only) | Breaks on move? |
|---|---|---|---|
| `~/.claude/projects/<encoded>/` + `*.jsonl` + `<sid>/` sidecars | encoded **launch realpath** | transcripts, subagent transcripts, tool-results, title | **Yes for `-c` and the default picker.** Resume by ID still works. [VERIFIED-LOCAL] |
| `~/.claude/projects/<encoded>/memory/` | encoded path | auto-memory (`MEMORY.md` + topic files) | **Yes**: memory silently stops loading at the new path. The 30-day sweep does not clean it, so it leaks. [OBSERVED dir; OFFICIAL cleanup scope] |
| `~/.claude/projects/<encoded>/bridge-pointer.json` | encoded path | remote-control bridge pointer | Yes (minor) |
| `~/.claude.json` → `projects["<abs path>"]` | **raw absolute path** | `hasTrustDialogAccepted`, `allowedTools`, `mcpServers`, `enabledMcpjsonServers`/`disabledMcpjsonServers`, `lastSessionId`, `last*` cost/usage stats, `exampleFiles`, `hasClaudeMdExternalIncludesApproved`, `mcpContextUris`, ... | **Yes**: trust prompt and MCP approvals re-asked, `lastSessionId` lost. [OBSERVED keys] |
| `~/.claude.json` → `githubRepoPaths["owner/repo"]` | repo → list of abs paths | path list | Stale entry (minor) |
| `~/.claude/history.jsonl` | `project` field = abs path | up-arrow prompt history | **Yes**: prompt history is per-project. [OBSERVED] |
| `~/.claude/sessions/<pid>.json` | pid | `cwd`, `sessionId`, `name`, `status` | Live processes only. #83146 [ISSUE] reports a stale `cwd` leaking into new sessions after a rename. |
| `~/.claude/session-env/<sid>/`, `file-history/<sid>/`, `uploads/<sid>/` | session ID | per-session data | No (the key is not a path). `trackedFileBackups` inside snapshots hold absolute file paths. [UNVERIFIED: whether `/rewind` breaks after a move] |
| `~/.claude/todos`, `tasks/` | session ID | not present on this machine | No |
| `~/.claude/shell-snapshots/` | timestamp | shell env snapshot | No |
| Project-local `<project>/.claude/` (`settings.json`, `settings.local.json`, `skills/`, `rules/`, `launch.json`), `CLAUDE.md`, `.mcp.json` | travels **with the folder** | config | No. They move with the folder. They can contain absolute paths in permission rules; none were found on this machine. |
| **Claude Desktop app** `~/Library/Application Support/Claude/claude-code-sessions/<acct>/<org>/local_<id>.json` | its own session ID | `cliSessionId`, **`cwd`**, **`originCwd`**, `gitAnchors{gitRoot, commonDir, trustedAt}`, `title`, `model`, `permissionMode`, ... | Stale `cwd` (the Desktop app's own binding). Note the precedent: Anthropic's own wrapper keeps its own index pointing at CLI session IDs. [OBSERVED] |

`claude purge [path] --dry-run` (formerly `claude project purge`) enumerates the state Claude Code itself considers per-project: "transcripts, tasks, file history, config entry". [OFFICIAL 2.1.126 / 2.1.288] It is a useful oracle when building a migration routine. I did not run it.

---

## What breaks on move (empirical, CLI 2.1.288) [VERIFIED-LOCAL]

All tests ran with an isolated `CLAUDE_CONFIG_DIR`. `claude -p` was unauthenticated, so each call failed at the API but still wrote a full transcript, which was enough to observe the storage behavior.

| # | Scenario | Result |
|---|---|---|
| 1 | Create session in `proj/`, then `mv proj proj-renamed`, then `claude -p -c` in `proj-renamed/` | **New session created**. The old one was not found. A new project dir was created for the new path. |
| 2 | Same, then `claude -p --resume <id>` in `proj-renamed/` | **Resumed** (same session ID). New records were appended to the **old** `…-proj/<id>.jsonl`, and `cwd` in the new records = `proj-renamed`. The file now mixes `cwd` values. |
| 3 | `--resume <id>` from an unrelated dir | **Resumed**, again appending to the old file with `cwd` = the unrelated dir. An empty project dir was created for the unrelated path. |
| 4 | `--resume /abs/path/to/<id>.jsonl` from an unrelated dir | **Resumed** (same behavior). |
| 5 | `cp -R src src-copy`, then `--resume <id>` from `src-copy` | **Both folders now share one transcript.** Copy-side turns go into the original's file. |
| 6 | Same as 5 with `--fork-session` | A new session ID is created **under `src-copy`'s project dir**, with history copied and `cwd` = `src-copy` in its records. This is effectively an official "re-home into the current folder" primitive, at the cost of a new ID. |
| 7 | `mv mig mig2`, plus `mv projects/<enc(mig)> projects/<enc(mig2)>` with **no** rewrite of `cwd`, then `-c` in `mig2` | **Found and resumed.** Renaming the project dir alone is enough for `-c` in print mode. [UNVERIFIED for the interactive picker: it may display or filter on `cwd`] |
| 8 | Same session ID present in two project dirs, then `--resume <id>` from an unrelated dir | **`No conversation found with session ID: …`**. From inside the project that owns it, the resume succeeded. |
| 9 | `CLAUDE_CONFIG_DIR=X CLAUDE_CODE_PROJECT_DIR_NAME=duo-proj-123`, create session, move folder, `-c` from the new location | **Found and resumed.** Storage lives in `X/projects/duo-proj-123/` regardless of folder path. |
| 10 | `CLAUDE_CODE_PROJECT_DIR_NAME` **without** `CLAUDE_CONFIG_DIR` | **Ignored.** The normal encoded-path dir was used. |
| 11 | `CLAUDE_CONFIG_DIR` set explicitly to `$HOME/.claude` plus `CLAUDE_CODE_PROJECT_DIR_NAME` | Honored. **However**, global config then lives at `$CLAUDE_CONFIG_DIR/.claude.json` instead of `$HOME/.claude.json`, so it is a *different* global config file. |
| 12 | Launch via a symlink (`/tmp → /private/tmp`, and a custom `anchor → w/plain`) | Keyed and recorded under the **resolved real path**. |
| 13 | Unauthenticated under any non-default `CLAUDE_CONFIG_DIR` | "Not logged in" [UNVERIFIED cause]. Credentials appear to be scoped per config dir, through the keychain entry and/or `oauthAccount` in that dir's `.claude.json`. Expect to need a separate login, or `apiKeyHelper`/`ANTHROPIC_API_KEY`, for a Duo-managed config dir. |

Things that degrade silently after a move, under the default config:

- `-c` starts a fresh conversation.
- The picker shows nothing by default. Ctrl+A shows the session as "from a different directory" (#81603 [MAINT]).
- Auto-memory is not loaded.
- The trust prompt reappears, and `.mcp.json` approvals and `allowedTools` are re-asked.
- Up-arrow prompt history is empty.
- If a *new* folder is later created at the old path, or at any path that encodes the same way, it inherits the orphaned sessions and memory.

---

## Known issues and official guidance

Web research summary. Issue states and dates are as reported on 2026-10-03. I did not open every issue myself, and they are cited as the research agent reported them.

**No supported migrate command exists.** Requests for one are open:

- #96323 "Sessions should follow a moved or renamed project folder" (OPEN, 2026-09-23). It consolidates #79215, #88903 and #55831. https://github.com/anthropics/claude-code/issues/96323
- #96018 proposes `claude project mv` (OPEN, 2026-09-22). It inventories all path-keyed state and compares community migration scripts. https://github.com/anthropics/claude-code/issues/96018
- #86713, history hidden after a rename (OPEN). The manual fix is to copy or move the slug dir and rewrite the path. A commenter warns that a naive find-and-replace corrupts sibling paths (`/p/foo` also matches `/p/foo-docker`). https://github.com/anthropics/claude-code/issues/86713
- #70248, auto-migrate on move (CLOSED as dup of #69752). https://github.com/anthropics/claude-code/issues/70248
- #83146, stale `cwd` in `sessions/<pid>.json` after a rename (OPEN). https://github.com/anthropics/claude-code/issues/83146

**Resume across directories:**

- #28745 (CLOSED, completed). [MAINT]: "`claude --resume <session-id>` can be run from any directory … then in every other project on the machine." https://github.com/anthropics/claude-code/issues/28745
- #5768, the original "No conversation found" report from another cwd (OPEN, effectively superseded). https://github.com/anthropics/claude-code/issues/5768
- #81603, folder moved mid-session (OPEN). [MAINT] confirms that resume by ID works and that the picker does not. https://github.com/anthropics/claude-code/issues/81603
- #97003 [ISSUE]: `-c` picks the globally most recent session. Not reproduced here: `-c` in a renamed folder started a new session. https://github.com/anthropics/claude-code/issues/97003
- Docs: https://code.claude.com/docs/en/sessions#resume-a-session and https://code.claude.com/docs/en/cli-reference. Resume by ID searches the current project and its worktrees, then all projects (2.1.223+). Resume by `.jsonl` path is supported.
- Changelog [OFFICIAL]:
  - 2.1.239 "`/resume` in all-projects mode … deleted directory … now resume in the current directory".
  - 2.1.239 "`claude -c` … picking up sessions from a different directory whose path differed only by `_`, `-`, or `.`".
  - 2.1.224 ">200 char project paths resolving to another project's session directory".
  - 2.1.251 "transcripts … silently overwritten when a directory change relocated a session onto an existing same-ID transcript".
  - 2.1.118 "`--continue`/`--resume` now find sessions that added the current directory via `/add-dir`".
  - 2.1.169 "Added `/cd` … move a session to a new working directory".
  - 2.1.196 "sessions moved with `/cd` reappearing in the old directory's resume list".

**Symlinks:**

- Changelog 2.1.50 [OFFICIAL]: "resumed sessions could be invisible when the working directory involved symlinks, because the session storage path was resolved at different times during startup".
- #86575 [MAINT]: a symlinked launch shows the physical path. https://github.com/anthropics/claude-code/issues/86575
- #74043 (symlink vs real path mismatch) and #99066 (symlinked slug dir, picker lists zero) are open. https://github.com/anthropics/claude-code/issues/74043 , https://github.com/anthropics/claude-code/issues/99066
- #98342: the Desktop app stores the resolved path. https://github.com/anthropics/claude-code/issues/98342

**Encoding collisions:**

- #70076 [MAINT] confirms the `[^a-zA-Z0-9] → -` slug and its collisions. https://github.com/anthropics/claude-code/issues/70076
- #93960: non-ASCII characters collapse. https://github.com/anthropics/claude-code/issues/93960
- Windows: `C:\X Y\Z` → `C--X-Y-Z`. Case-sensitivity and UNC issues are tracked in #90588 and #89283. https://github.com/anthropics/claude-code/issues/90588

**Storage configuration:**

- `CLAUDE_CONFIG_DIR` relocates all of `~/.claude`.
- `CLAUDE_CODE_PROJECT_DIR_NAME` (2.1.234): "hosts that give each session its own config directory can choose a short name for the per-project transcript directory". It is only honored with `CLAUDE_CONFIG_DIR` [VERIFIED-LOCAL]. https://code.claude.com/docs/en/sessions#where-transcripts-are-stored

**Retention:**

- `cleanupPeriodDays` defaults to 30. 0 is rejected (2.1.x). The sweep deletes transcripts, `subagents/` and `tool-results/`, plus tasks, shell-snapshots and backups, but not `memory/`.
- Desktop-written sessions are exempt (2.1.248, `desktopSessionCleanupPeriodDays`). https://code.claude.com/docs/en/claude-directory
- **Sessions launched by Duo (entrypoint `sdk-cli`/`cli`) are not exempt.** [UNVERIFIED: whether the exemption is detected by entrypoint or by some other mechanism]

**Agent SDK:**

- `continue` is cwd-scoped. `resume` gets the cross-directory lookup on 2.1.223+.
- The docs say a session file can be restored "inside any directory under `~/.claude/projects/`" and resumed by ID. https://code.claude.com/docs/en/agent-sdk/sessions#resume-across-hosts

**Official migration guidance:**

- None for moved projects. The transcript format is documented as internal and version-dependent.

**Community tools:** claude-mv variants, claude-migrate, claude-move, claude-rehome. Per #96018, quality varies: several do unsafe substring path rewrites, and none fix the Desktop app's own index. They are untested here and are not recommended as dependencies.

---

## Mitigation options

| Option | How | Pros | Cons / risks | Verdict |
|---|---|---|---|---|
| **A. Explicit session IDs, always** | Duo generates a UUID, launches `claude --session-id <uuid>`, records it, and reopens only with `claude --resume <uuid>` (`--resume <transcript path>` as a fallback). Never uses `-c` or the picker. | Survives moves today with zero migration [VERIFIED-LOCAL]. Simple. Supported flags. | Transcript stays filed under the stale key, so terminal `claude -c` and the picker in the folder don't see it. Memory, trust and history don't follow. Breaks if the same ID ends up in 2 project dirs. | **Required baseline** |
| **B. Path-independent storage via `CLAUDE_CONFIG_DIR` + `CLAUDE_CODE_PROJECT_DIR_NAME=<projectId>`** | Duo runs Claude Code with its own config dir (e.g. `~/Library/Application Support/Duo/claude/`) and pins the project dir name to the project's stable ID. | Moves and renames need **no migration**. Transcripts, memory and `-c` all follow the project [VERIFIED-LOCAL]. Officially supported env vars. Isolation from the user's personal `~/.claude` (retention, settings, plugins) is under Duo's control. Avoids slug collisions and long-path hashing. | Separate global config: separate login (or API key / `apiKeyHelper`), MCP servers, plugins and user `CLAUDE.md`. The user's terminal `claude` won't see Duo sessions unless Duo ships a shim (`duo claude` / env export). `~/.claude.json`-style `projects[<abs path>]` trust entries (inside Duo's config) are **still path-keyed**, so the trust prompt reappears after a move unless Duo pre-seeds or updates them [UNVERIFIED in interactive mode]. The env var is relatively new (2.1.234), so a minimum CLI version must be pinned. | **Recommended primary** |
| **C. App-mediated move (migrate default storage)** | When Duo performs (or detects) a move, it renames `projects/<enc(old)>` → `projects/<enc(new)>` (merging if the target exists), renames the `~/.claude.json` `projects` key, rewrites `history.jsonl` `project` fields, and optionally rewrites the `cwd` field. | Keeps the user's normal `~/.claude`. Restores `-c`, picker, memory and trust for terminal users. A dir rename alone was enough for `-c` [VERIFIED-LOCAL]. | Writes to files Claude Code owns, in an internal, versioned format. It must not run while a session for that project is live (check `sessions/*.json`). Merge conflicts with an existing target dir, including the slug collision case. Must compute the slug exactly (200-char hash rule) or discover it by scanning `cwd`. `~/.claude.json` is rewritten often by running CLIs, so Duo's edits can race and be lost. A `cwd` rewrite must be boundary-safe (exact field match, never substring). Doesn't fix the Desktop app's own index. | **Fallback** for projects on default storage. Rename dirs; skip the `cwd` rewrite unless needed. |
| **D. Stable symlink anchor** (launch from `~/…/.anchors/<id>` → real folder) | Keep a symlink per project and always `cd` into the symlink. | None in practice. | **Defeated**: Claude Code resolves the realpath for both storage key and `cwd` [VERIFIED-LOCAL]. | **Reject** |
| **D'. Inverse anchor** (real folder at a stable hidden location; user-visible symlinks or aliases) | Projects physically live in e.g. `~/Duo/.store/<id>/`. Finder sees symlinks. | The realpath never changes, so everything just works, including terminal `claude`. | Fights user mental model ("where are my files?"). Cloud-sync tools (iCloud Drive, Dropbox, Google Drive) and some apps don't follow symlinks. Users can move the real dir. Finder "Move to Trash" on the symlink confuses. | Not for PM users. Possibly an internal implementation detail. |
| **E. Project-local session index** | `<project>/.duo/sessions.json` (and/or a human-readable `SESSIONS.md`) listing session IDs, titles, linked tasks, created/last-used dates, and the CLI version. | Travels with the folder, including copies, zips, git and cloud sync. Human-legible. Lets Duo (or a person) resume by ID from anywhere. Survives Duo's own DB loss. | Only *points* to transcripts; it doesn't contain them, so if `~/.claude` (or Duo's config dir) is cleaned or on another machine, the IDs dangle. Copies duplicate the index, so the same session can be claimed by two projects (see copy semantics). Should be git-ignorable or committed by explicit choice. | **Recommended** (with A and B) |
| **F. Move detection via stable project ID** | `<project>/.duo/project.json` holds `{projectId, createdAt, ...}`. Duo keeps a registry `projectId → lastKnownPath + macOS bookmark`. On launch, or via FSEvents, it resolves the bookmark. If the path changed, it re-associates; if a manifest with a known ID appears at a new path, it offers to relink. | Bookmarks (`NSURL bookmarkData`) track renames and moves on the same volume natively. The manifest ID handles cross-volume moves and restores. Robust and user-visible. | Copies produce **two folders with the same projectId**. Duo must detect duplicates (both paths exist) and mint a new ID for the copy. FSEvents can coalesce or miss events while Duo isn't running, so reconcile on launch. Moves to another volume are copy-plus-delete. | **Recommended** |
| **G. Copy vs move of transcripts** | n/a | Moving a transcript between project dirs is safe. | Copying a `.jsonl` so the same ID exists in two project dirs makes `--resume <id>` fail from other dirs [VERIFIED-LOCAL]. Resuming from a copied *project folder* writes into the original's transcript [VERIFIED-LOCAL]. For a duplicated project, use `--fork-session` on first resume to give the copy its own lineage (new ID, filed under the copy's path). | **Rule**: never duplicate session IDs. Fork on copy. |
| **H. Rewrite `cwd` inside transcripts** | Boundary-safe rewrite of `.cwd` fields (old prefix → new prefix). | Cosmetic and display consistency. May matter for the interactive picker or Desktop UI [UNVERIFIED]. | Not needed for `-c` or `--resume` [VERIFIED-LOCAL]. Tool inputs and results still contain old absolute paths, so the content stays stale anyway. Risk of corrupting an append-only log, and the format is internal. A live session appending concurrently would conflict. | **Avoid** unless a specific consumer needs it. |
| **I. Durable archive + retention** | Set `cleanupPeriodDays` high in Duo's config (B makes this Duo's own `settings.json`). Additionally copy closed transcripts plus sidecars into Duo's own archive keyed by projectId and sessionId. | Protects against the 30-day deletion, CLI format churn, and user `claude purge`. Enables Duo's own search and summaries. | Storage growth (transcripts here reach about 50 MB). The archive is a *copy*, so never place it back under `projects/` alongside the original (see G). | **Recommended** |

### Discussion

- **The core insight** is that Claude Code has two independent lookups. **(1) Resume by ID or path** is effectively global and already move-proof. **(2) Path-scoped features** cover `-c`, the picker, auto-memory, trust, MCP approvals and prompt history. Duo can control (1) completely by owning session IDs. (2) can only be made move-proof by **B** (pin the storage name) or patched after the fact by **C** (migrate).
- **B vs C** is really a choice between "Duo runs its own Claude Code profile" and "Duo shares the user's `~/.claude`".
  - For a PM-targeted desktop app, an isolated profile is likely a feature: predictable settings, retention and plugins, and no interference with the user's engineering setup.
  - The main costs are a second login and the user's terminal `claude` not seeing Duo sessions. A small "Open in Terminal" action that exports `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_PROJECT_DIR_NAME` and runs `claude --resume <id>` resolves the second.
- **Trust and path-keyed config remain path-keyed even under B.** Under B, Duo controls the config dir, so it can manage the trust entry for the new path. That can mean writing `hasTrustDialogAccepted` (fragile, internal) or simply letting the trust prompt reappear once after a move. That needs a decision and an experiment (see open questions).
- **The Desktop app precedent**: Anthropic's Claude Desktop already keeps its own `local_<id>.json` index pointing at `cliSessionId` plus `cwd`/`originCwd`/`gitAnchors`. Wrapper-owned indexing is the established pattern, and Duo should do the same, but key it by projectId instead of path.

---

## Recommendation

Use a combination of **A + B + E + F + I**, with **C** as a fallback mode and **G** as a hard rule.

1. **Project identity (F).**
   - Every Duo project gets `<project>/.duo/project.json` = `{ "projectId": "<uuid>", "createdAt": …, "schema": 1 }`.
   - Duo's registry stores `projectId → { lastKnownPath, bookmarkData, volumeId }`.
   - On launch, and on FSEvents, Duo resolves bookmarks, scans known roots for manifests, and reconciles.
   - When two folders carry the same projectId, Duo treats the newer or non-bookmarked one as a **copy**: it mints a new projectId for it and marks its inherited sessions "fork on next open".
2. **Session ownership (A + E).**
   - Duo always creates sessions with `--session-id <uuid>` and resumes with `--resume <uuid>`. It never uses `-c` or the picker programmatically.
   - Duo writes `<project>/.duo/sessions.json` (machine) and optionally `SESSIONS.md` (human). Each entry carries `{sessionId, title, linkedTasks, createdAt, lastOpenedAt, cliVersion}`.
   - The index contains no transcript content.
3. **Path-independent storage (B).**
   - Duo runs Claude Code with `CLAUDE_CONFIG_DIR=<Duo app support>/claude` and `CLAUDE_CODE_PROJECT_DIR_NAME=duo-<projectId>`.
   - A folder move or rename then needs no Claude-side changes at all. Duo just launches with the new `cwd`.
   - Pin a minimum CLI version (≥ 2.1.234 for the env var; ≥ 2.1.251 for the relocation-overwrite fix) and check `claude --version` at startup.
4. **Durability (I).**
   - In Duo's config `settings.json`, set `cleanupPeriodDays` to a large value.
   - After each session ends, snapshot the transcript and sidecars to `<Duo app support>/archive/<projectId>/<sessionId>/`.
   - Never restore an archive copy next to a live copy.
5. **Copy semantics (G).**
   - Never copy `.jsonl` files between project dirs.
   - For a duplicated project folder, open inherited sessions with `--resume <id> --fork-session`, then record the new ID in the copy's index.
6. **Fallback (C), only for projects intentionally run under the user's default `~/.claude`.**
   - This covers, for example, a user preference to "share sessions with my terminal".
   - On a detected move, while no live `sessions/*.json` references the old path, rename `projects/<enc(old)>` → `projects/<enc(new)>`.
   - Refuse and ask if the target exists. Discover `enc(old)` by scanning for dirs whose transcripts' first `cwd` equals the old path, rather than recomputing the slug.
   - Also rename the `~/.claude.json` `projects` key and the `history.jsonl` `project` values.
   - Do not rewrite transcript `cwd` fields.
7. **Optional:** after a move, inject a short note on the next resume ("this project moved from X to Y"). Earlier tool calls in the history reference old absolute paths, and the model may otherwise try to use them. [UNVERIFIED benefit]

---

## Open questions / experiments to run

1. **Interactive behavior under B.** Does the interactive TUI, not just `-p`, honor `CLAUDE_CODE_PROJECT_DIR_NAME` for `/resume`, `-c`, auto-memory load and write, and `/rewind`? These tests were all `-p`.
2. **Trust and per-project config under B.** After a move, does the interactive trust dialog reappear? Which `projects["<path>"]` keys in `$CLAUDE_CONFIG_DIR/.claude.json` matter for a PM user (trust, `.mcp.json` approvals, `allowedTools`)? Can Duo supply them via `--settings` / managed settings instead of editing `.claude.json`?
3. **Auth in a Duo-owned config dir.** Confirm why the sandbox runs reported "Not logged in": a keychain entry scoped by config-dir hash, or a missing `oauthAccount`? Decide between a separate `/login`, `apiKeyHelper`, or an SDK-provided token.
4. **Picker and Desktop dependency on `cwd`.** After experiment C (dir rename without a `cwd` rewrite), does the interactive `/resume` picker list the session under the new folder? Does it show the old path? Is a `cwd` rewrite ever needed?
5. **Agent SDK.** If Duo embeds the Agent SDK rather than spawning the CLI, verify that `resume`, `sessionId`/`forkSession` and the env vars behave the same, and check which CLI version the SDK bundles.
6. **Retention exemption.** Confirm `cleanupPeriodDays` in Duo's own `settings.json` is respected under `CLAUDE_CONFIG_DIR` and that the sweep never touches sessions Duo still lists. Check whether the desktop exemption keys on entrypoint (if so, Duo can't rely on it).
7. **Cross-volume and cloud-sync folders.** Test whether bookmark resolution and FSEvents handle iCloud Drive, Dropbox and Google Drive folders, external disks, and case-only renames (`Foo` → `foo` on case-insensitive APFS: same realpath? same slug?).
8. **Unicode normalization.** Folders created by other apps may be NFD. Check whether the cwd (and hence the slug) differs between NFC and NFD spellings of the same name.
9. **Concurrent sessions per project.** Two Claude processes in the same project appending to different session files is fine. Verify that relocation or migration never runs during a live session: use the `sessions/<pid>.json` registry plus a lock in `.duo/`.
10. **Version drift.** The slug rule, the hash function (reverse-engineered here as `Math.abs(javaHash(path)).toString(36)` over the unsanitized path) and the transcript schema are internal. Add a startup self-test: create a throwaway session in a temp config dir, assert where it lands, and disable the fallback C mode if the assumptions break.
11. **Worktrees.** If Duo ever uses `--worktree` or git worktrees, sessions relocate on worktree enter and exit [OFFICIAL]. Confirm the interaction with `CLAUDE_CODE_PROJECT_DIR_NAME`.

### Reproduction notes

The experiments used `CLAUDE_CONFIG_DIR=<scratch>/cfg2` and `claude -p hi --model haiku --output-format json </dev/null`. They ran unauthenticated, so each call ended `terminal_reason=api_error` but still persisted a transcript. A process can be checked against its project dir with `jq -r 'select(.cwd)|.cwd' <file> | sort -u` and `ls $CLAUDE_CONFIG_DIR/projects`. Nothing under `~/.claude` was modified.
