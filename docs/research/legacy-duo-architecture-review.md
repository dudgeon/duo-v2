# Legacy Duo (v0.13.8) — architecture and integration review

Status: research input for v2 design · 2026-10-03 · Scope: `~/repos/duo` (read-only) — `CLAUDE.md`, `AGENTS.md`, `agents/duo.md`, `cli/`, `core/**`, `electron/**`, build config, tests. Product docs, CHANGELOG and `docs/research/` are covered by sibling reviews and are not repeated here.

All paths below are relative to `/Users/geoff/repos/duo/` unless prefixed with `~` or `/`.

---

## 0. Summary

Legacy Duo is one Electron main process (`electron/main.ts`, 6,452 lines) owning a `WindowRegistry` of `WindowContext`s, a shared `PtyManager` (node-pty), one app-scoped `SocketServer` (NDJSON over a Unix socket plus a TCP fallback), and per-window `BrowserManager` (Electron `WebContentsView`) + `CdpBridge` (Chrome DevTools Protocol via `webContents.debugger`). The renderer is React + xterm.js + TipTap. The agent talks back through a standalone esbuild-bundled CLI (`cli/duo.ts`, 4,189 lines, ~150 verbs) that connects to the socket. Claude Code integration is entirely **outside-in**: Duo never spawns `claude` with a known session id for ordinary tabs; it types `claude\n` into a zsh PTY, then infers everything (presence, session uuid, state) from `ps`, `lsof`, and scans of `~/.claude/projects/<encoded-cwd>/*.jsonl`. The attention badge is the one place a hook feeds state in, and it is tab-keyed via a `DUO_TAB` env stamp rather than session-keyed.

What held up well: the pure-core/Electron-shell split (`core/` has no Electron import and is heavily unit-tested); atomic tmp+rename writes with a write queue; the "no sidecar" discipline (§D9); the attention hook's fail-open shell script; the cron command builder's safety gates; the digest extractor's deterministic JSONL scan; the inspect-mode payload shape.

What was brittle: every session/state inference built on cwd → encoded project dir → freshest JSONL (documented "known limit" races in `electron/main.ts:5010`); the `ps`-polling presence probe; the PATH shim that wraps the user's `claude` binary; the CLI-over-socket design that fights Claude Code's sandbox; the 4-surface CLI sync tax; `main.ts` as a 6k-line god module.

v2's decisions (`docs/design/stack-recommendation.md` #4–#6: `--session-id` per session, hooks + `claude agents --json`, in-app MCP) directly remove the inference layer. The sections below say exactly what that layer computed so v2 can keep the *outputs* while discarding the *mechanisms*.

---

## 1. System map

### 1.1 Processes

| Process | Role | Evidence |
|---|---|---|
| Electron main (`out/main/index.js`) | Owns windows, PTYs, socket, CDP, every persisted store, cron scheduler, auto-updater | `electron/main.ts`; `package.json` `main` |
| Renderer (one per `BrowserWindow`) | React UI: xterm.js terminals, tab strips, TipTap editor, HTML canvas iframe, navigator, Home | `renderer/App.tsx` (~3k lines), `renderer/components/**`; preload exposes 40+ namespaces (`electron/preload.ts:84-1119`, `contextBridge.exposeInMainWorld('electron', api)` at line 1137) |
| `WebContentsView` per browser tab | Real Chromium pages, SSO-persistent partition `persist:duo-browser` | `electron/browser-manager.ts:1-20`, `core/constants.ts:44-45` |
| zsh PTY per terminal tab | node-pty spawn; `claude` is a child typed into the shell | `core/pty-manager.ts:129-209` |
| `duo` CLI (esbuild bundle, no Node needed) | Agent → app bridge over Unix socket / TCP | `cli/duo.ts`, `scripts/build-cli.mjs`; binary `cli/duo` is committed |
| Hook scripts (`/bin/sh`) | Claude Code `Stop`/`Notification`/`UserPromptSubmit`/`PreToolUse`/`SessionStart` → call `duo` | `skill/scripts/duo-attention.sh`, `skill/scripts/duo-open-file-guard.sh` |

### 1.2 Main-process services (where they live)

| Service | File | Purpose |
|---|---|---|
| `WindowRegistry` / `WindowContext` | `electron/window-registry.ts` | Map of windowId → {window, browserManager, cdpBridge, presence, tabsThatHostedClaude, activeWorkspace}. Resolution is "lowest-id primary, never focus" (`CLAUDE.md` locked decisions; `scripts/check-window-routing.sh` greps for `getFocusedWindow`). |
| `PtyManager` | `core/pty-manager.ts` | node-pty pool keyed by tab UUID; env stamps; owner-window routing (`core/pty-owner.ts`). |
| `ClaudePresenceProbe` | `core/claude-presence.ts` | 500 ms `ps -ax` poll of the front tab's process tree. |
| `SocketServer` | `core/socket-server.ts` (2,500 lines) | NDJSON request dispatch, ~110 `case` branches (`:934-2467`), `NavBridge` interface of ~90 callbacks into main. |
| `BrowserManager` | `electron/browser-manager.ts` (1,544) | Tab lifecycle, off-host routing, aux slot, file:// watchers, key forwarding. |
| `CdpBridge` | `electron/cdp-bridge.ts` (2,150) | CDP attach, 4 injected IIFEs, 6 `Runtime.addBinding`s, console/error/network ring buffers, DOM/AX/screenshot/eval. |
| `FilesService` | `electron/files-service.ts` | list/read/write/watch (chokidar), atomic write, history capture hook. |
| `FileHistoryService` | `core/file-history-service.ts` | Content-addressed append-only snapshots at `~/.claude/duo/file-history/`. |
| `SessionStateService` | `core/session-state-service.ts` | Debounced (250 ms) single-writer envelope at `~/.claude/duo/session-state.json`. |
| `InstallService` | `electron/install-service.ts` (2,138) | First-launch/boot self-install: skill, agent, CLI shim, `claude` PATH shim, hooks merge, CLAUDE.md managed block. |
| `CronService` / `CronStore` | `core/cron-service.ts`, `core/cron-store.ts` | In-app 30 s tick scheduler, `~/.claude/duo/cron-jobs.json`. |
| `SessionDigestStore` / `HomeStateStore` | `core/session-digest-store.ts`, `core/home-state-store.ts` | Catch-up board caches. |
| `home-snapshot` | `electron/home-snapshot.ts` | Enumerates `~/.claude/projects/*`, rolls up worktrees, builds Home + Catch-up boards. |
| `claude-session-tracker` | `electron/claude-session-tracker.ts` | JSONL primitives: `encodeProjectDir`, title ladder, head/tail seek reads, prior-session listing. |
| `session-digest` | `electron/session-digest.ts` | Deterministic per-session digest from JSONL (goal, todos, files, artifacts, attention reason). |
| `EventBus` | `core/event-bus.ts` | 200-entry ring + cursors; `duo events --follow`. |
| `ExternalDomainsService`, `BrowserHistoryService` | `core/external-domains-service.ts`, `core/browser-history-service.ts` | Off-host routing list; URL-bar autocomplete. |
| Vault core | `core/vault/**` (≈ 9k lines incl. tests) | OKF/Obsidian knowledge-graph; runs in-process inside the CLI, no app needed. |
| Git | `core/git/**` | `gh`/`git` wrappers: status, clone, pull, worktrees, share-back PR. |
| Updates | `core/update-checker.ts`, `electron/auto-updater.ts` | GitHub Releases banner + electron-updater. |

### 1.3 Data flows

```
Claude Code TUI (child of zsh in a Duo PTY)
   │  runs `duo <verb>` (Bash tool)
   ▼
cli/duo.ts ──NDJSON──▶ ~/Library/Application Support/duo/duo.sock   (chmod 0700)
                └─fallback─▶ 127.0.0.1:<port> + token from duo.port  (sandbox case)
   ▼
core/socket-server.ts handle() ──▶ NavBridge callbacks in electron/main.ts
   ├─▶ BrowserManager / CdpBridge  (page read/drive)
   ├─▶ IPC to renderer (editor/canvas/json ops, tab moves)  ← renderer replies via PendingRegistry
   ├─▶ FilesService (disk-direct edits when the file is NOT open)
   └─▶ stores (pins, projects, cron, digests, home-state)

Hooks: claude ──Stop/Notification/UserPromptSubmit──▶ duo-attention.sh ──▶ `duo attention --tab $DUO_TAB` + `duo session digest $DUO_TAB`

Renderer ──IPC push──▶ main caches (nav state, selection, theme, projects snapshot, aux state) so CLI reads need no round-trip
Renderer ──IPC invoke──▶ main `window.__duoGetLayout()` / `__duoGetStatus()` executed back in the renderer for always-fresh reads
```

### 1.4 Where state lived

| Kind | Location | Notes |
|---|---|---|
| **Files, user-visible (Duo-owned)** | `~/.claude/duo/` | The convention: "user-visible state lives here" (`core/session-state-service.ts:27-31`). Full inventory in §3.1. |
| **Files, app-private** | `~/Library/Application Support/duo/` | `duo.sock`, `duo.port`, `browser-session/` (Chromium partition). `core/constants.ts:10-17,45`. |
| **Files, inside the user's `~/.claude`** | `settings.json` (hooks with `_duo` marker), `CLAUDE.md` (managed block), `skills/duo/`, `agents/duo.md` | `electron/install-service.ts:1-60`. |
| **Files, project-local** | `.duo-workspace` (user-chosen path), `<file>.duo.json` canvas sidecars, `<repo>/.claude/worktrees/<slug>`, vault folders | §3.2 |
| **Rebuildable cache** | `~/.claude/duo/session-digests.json` | §D9 test: delete → byte-identical rebuild (`electron/session-digest.test.ts:341`). |
| **In-memory only** | presence state, `tabsThatHostedClaude`, attention flags, event-bus ring, CDP console/error/network rings, renderer-pushed caches (`WindowKeyedCache`) | Attention is explicitly "transient; no main-side store" (`electron/main.ts:1677-1682`). |
| **Renderer localStorage** | theme, author, Return-key prefs, last new-tab kind, hidden files, per-file frontmatter collapse | `docs/CLI-COVERAGE.md` Appearance rows; `renderer/components/editor/docUiPrefs.ts` |
| **External source of truth read live** | `~/.claude/projects/**/*.jsonl`, git, process table | §D9 rule: pointers only, never mirrors (`CLAUDE.md` rule 12). |

---

## 2. How it integrated with Claude Code

### 2.1 PTY management

**What it did.** `PtyManager.create(id, shell, cwd, ownerWindowId)` spawns `$SHELL` (default `/bin/zsh`) via node-pty with `name: 'xterm-256color'`, 80×24, in a cwd resolved to the nearest existing ancestor (`core/cwd-utils.ts`). Env added to every PTY (`core/pty-manager.ts:149-167`):

```
PATH=~/.claude/duo/bin:$PATH     # SHIM_DIR first — claude wrapper + duo CLI
DUO_SESSION=1
DUO_SOCKET=~/Library/Application Support/duo/duo.sock
DUO_TAB=<tab uuid>
DUO_WINDOW=<owner window id>
DUO_VERSION=<app version>
TERM_PROGRAM=Duo
```

Claude is launched by the **renderer** typing into the PTY: `claude\n` (or `claude\n<cmd>\n` to seed a first message through the stdin buffer) after `waitForPtyReady` (`renderer/App.tsx:1993-2025`), gated on `isClaudeOnPath()` (`electron/main.ts:6372`). Resume is likewise a typed line: `claude --resume <uuid>\n` (`electron/main.ts:1662`, `electron/claude-session-tracker.ts:buildResumeCommand`). Only cron runs pre-allocate an id with `claude --session-id <uuid> "<instruction>"` (`core/cron-command.ts:buildFreshRunCommand`).

Resize guards: refuse `cols < 8 || rows < 1` because a 0×0 resize SIGHUPs the Claude TUI (`core/pty-manager.ts:233-254`, BUG-156/BUG-200). Renderer's Return-key overrides write `\x1b\r` for newline in Claude tabs (`renderer/components/TerminalPane.tsx:450-478`).

Tests: `core/pty-manager.test.ts` (env stamps, resize floors), `core/pty-owner.test.ts` (owner routing with sole-window fallback).

**What worked.** Env stamping as the "am I in Duo" signal is clean and the agent docs lean on it (`agents/duo.md:37-62`). The missing-cwd fallback with a yellow in-terminal note is good UX. Owner-window routing was solid.

**What was brittle.**
- Launching `claude` by typing into zsh means Duo never knows the session id at spawn; every downstream feature re-derives it (§2.3).
- `TERM_PROGRAM=Duo` is not on Claude Code's kitty-keys allow-list (v2 stack doc spike 1 flags this).
- The PATH shim (`~/.claude/duo/bin/claude`, `electron/install-service.ts:980-1030`) `exec`s the real binary with `--append-system-prompt "$(cat ~/.claude/duo/priming.md)"`. It inlines the resolved real path at install time, so a Claude upgrade that moves the binary silently breaks priming; it also shadows `claude` for every process in the PTY.
- Resolving the user's `claude` (`core/resolve-claude.ts`) required a well-known-dir walk plus three shell flag-set variants with 15 s timeouts because Finder-launched Electron inherits the LaunchServices PATH. Still necessary in v2 (same Finder problem) but should be done once at boot and cached per launch.

**v2 equivalent.** `forkpty` with the user's `claude` directly (not via zsh), `--session-id <duo-uuid>`, `--settings` for injected hooks, `--mcp-config` for the in-app MCP server, `--append-system-prompt` passed by Duo itself (no shim). Keep: env stamps (`DUO_SESSION`, `DUO_SESSION_ID` instead of `DUO_TAB`, `DUO_WINDOW`), the missing-cwd fallback, the resize floor. Drop: SHIM_DIR, priming.md, `isClaudeOnPath` shell dance (replace with a one-time resolver + Settings override).

### 2.2 Presence detection (`claude-presence`)

**What it did.** `ClaudePresenceProbe` watches ONE pid (the front terminal's shell) and polls `ps -ax -o pid,ppid,comm` every 500 ms, BFS-ing the descendant tree for a process whose `comm` basename is `claude` (`core/claude-presence.ts:1-150`). States: `no-pty | shell | claude | starting` (1.5 s grace after a `kind:'claude'` tab spawn). Parked when there is no target. The ADR is `docs/DECISIONS.md:565-620` ("process-tree probing, not tab-kind heuristics").

Two wider variants serve Home: `probeAllTabs(rootPids)` and `mapLiveClaudeOwners(duoPtyPids)` (one `ps` parse → every live `claude` on the box, attributed to the Duo PTY that owns it or `null` for external) (`core/claude-presence.ts:150-336`).

Consumers: the "Send → agent" pill gate (`cdpBridge.setClaudeLive`, `browserManager.broadcastClaudeLive`, `electron/main.ts:1060-1081`), `tabsThatHostedClaude` (gates session-id capture), Return-key behaviour, `duo term close` refusal.

**What worked.** It correctly handles "user typed `claude` into a shell tab" and "user `/exit`ed". It is per-window isolated (`core/claude-presence.test.ts`).

**What was brittle.** One `ps` spawn every 500 ms while any tab is focused; macOS-only flags; a 500 ms stale window; only the *front* tab is probed, so background tabs' liveness is only known via the heavier Home join.

**v2 equivalent.** Not needed. v2 owns the child pid from `forkpty` (`waitpid` / SIGCHLD gives exit), and `claude agents --json` gives per-session status. Keep one idea: "Claude running in a plain shell tab" will still exist if v2 offers shell tabs; a cheap `proc_listchildpids` check on focus (not a poll) covers it.

### 2.3 Session identity and state (`claude-session-tracker`, `session-state`, `session-envelope`, `session-digest`)

**Session ↔ tab binding (what it did).** There was no binding at spawn. The tracker encodes the cwd as Claude does (`realpath` then `[/.] → -`; `electron/claude-session-tracker.ts:encodeProjectDir`, BUG-158) and picks the **most-recently-modified `<uuid>.jsonl`** in `~/.claude/projects/<encoded>/`:

- `detectLatestClaudeSession(cwd, maxAge 24h)` — the enrich-before-persist hook stamps `terminals[i].lastClaudeSession = {id, capturedAt}` into session-state at every autosave, gated on the tab having hosted Claude (`electron/main.ts:640-720`). Tabs are matched to PTYs **positionally by cwd** (`listIdsByCwd` + a `consumed` set) because the persisted terminal list carries no tab id.
- `sessionIdForTab(tabId)` — cwd → freshest JSONL (`electron/main.ts:5010-5040`). Documented known limit: two Claude tabs in the same cwd collide; the fix noted is "thread Claude Code's own `session_id` / `transcript_path` from the hook's stdin" — which is exactly v2's plan.
- `buildHomeOpenJoin()` — one `ps` + one `lsof -a -d cwd -p <pid>` per live claude → group by cwd → the N freshest JSONLs in that cwd are "open", Duo-hosted first, remainder "external" (`electron/main.ts:4880-4950`, `electron/home-snapshot.ts:attributeOpenSessions`). The older "newest JSONL mtime ≤ 2 min" heuristic is explicitly banned (D13).

Note: the encoding in the tracker does **not** implement the >200-char truncation+hash rule that v2's `claude-code-session-path-binding.md` verified; it was a latent bug.

**Title ladder.** `readBannerTitle`: latest `custom-title` → latest `ai-title` → first user message cleaned (`cleanAndTruncate` strips `<ide_opened_file>`, `<command-*>`, `<system-reminder>` wrappers, fillers, 60-char cut) → short uuid. Large files are read head+tail (1 MB each) or via seek-based 16 KB head / 64 KB→2 MB tail ladders (`readSessionHeadMeta`, `readSessionTailMeta`). Tests: `electron/claude-session-tracker.test.ts`.

**Session state file.** `~/.claude/duo/session-state.json` is a v2 envelope `{version:2, savedAt, appVersion, windows:[WindowState]}` where each window holds `terminals[{cwd, kind:'shell'|'claude', title, lastClaudeSession?}]`, `browserTabs[{url,title}]`, `fileTabs[{path,type,mime}]`, `activeWorking`, `navigatorPath`, `aux`, `bounds`, `activeWorkspace` (`shared/types.ts:840-980`; migration in `core/session-envelope.ts`; v1 backup `.v1.bak`). Single serialized writer, 250 ms debounce, unique tmp paths. Tests in `core/session-state-service.test.ts` cover concurrent-flush lost-update negative controls. What is **not** persisted: live shell cwd (only spawn cwd; `lsof` recovers it on demand), unsaved buffers, browser scroll/form state.

**Digest.** `extractSessionDigest(jsonlPath, uuid)` is a pure scan (no clock, no network) producing `{goal, youAsked, todos (latest TodoWrite), files (Edit/Write/MultiEdit/NotebookEdit; `created` only when `toolUseResult.type==='create'`), artifacts (PR only when `gh pr create`/`create_pull_request` ran AND a pull URL appears in a tool result; tests pass/fail from runner output only), attention: plan-to-approve | blocked | question, gitBranch, lastActivityAt = file mtime}` (`electron/session-digest.ts`). Goal ladder: custom-title → ai-title → compact-summary "Primary Request and Intent" → `/<command>` → first prompt. Cached in `session-digests.json`, refreshed on Stop hook, re-extracted when mtime is newer (`readOrExtractDigest`).

**What worked.** The JSONL shape knowledge (record types `user`/`assistant`/`custom-title`/`ai-title`/`last-prompt`, `isSidechain`, `isCompactSummary`, `toolUseResult`, `cwd`, `gitBranch`, `sessionId`), the bounded seek reads (sessions reach 270 MB), the deterministic digest with its §D9 rebuild test, and the `attributeOpenSessions` pure function are all reusable in v2 almost verbatim (port to Swift).

**What was brittle.** Everything upstream of the JSONL path: cwd-freshest inference, positional tab matching, `lsof` per pid, 24 h stale caps, "tab hosted Claude" sets. The enrichment hook runs on every autosave. Worktree/nested-cwd rollup (`electron/home-snapshot.ts:rollupProjects`) reads `.git` `gitdir:` pointers to fold worktrees into main repos — useful, but it is a lot of filesystem probing per Home refresh.

**v2 equivalent.** Duo mints the uuid, so `sessionId → transcript path` is `~/.claude/projects/<encoded>/<uuid>.jsonl` (or `CLAUDE_CONFIG_DIR`-relative), no inference. `claude agents --json` replaces the open-join. Keep the JSONL readers, title ladder, and digest scanner as a `DuoClaude.Transcript` module; keep the §D9 "cache is a rebuildable index" discipline for the SQLite index.

### 2.4 Attention (`attention`, `duo-attention.sh`, hooks merge)

See §4 for the model. Mechanics: `InstallService` copies `skill/scripts/duo-attention.sh` to `~/.claude/duo/hooks/` and merges into `~/.claude/settings.json`:

```
hooks.Stop             += { _duo: "managed-v<ver>", hooks:[{type:'command', command:'$HOME/.claude/duo/hooks/duo-attention.sh set'}] }
hooks.Notification     += … set
hooks.UserPromptSubmit += … clear
hooks.PreToolUse       += { matcher:'Edit|Write|MultiEdit', … duo-open-file-guard.sh }   (warn-only)
hooks.SessionStart     += { … cat priming.md }                                           (belt-and-braces priming)
```

`planManagedHooksMerge` is pure and idempotent: it drops prior entries by `_duo` marker **or** exact command match, appends one fresh entry, never touches foreign hooks (`electron/install-service.ts:385-417`; tests in `install-service.test.ts`). The hook script never reads stdin JSON; it keys on `$DUO_TAB` and `exit 0`s on every path (`skill/scripts/duo-attention.sh`; behaviour test `electron/duo-attention-hook.test.ts`).

**Brittle:** writes into the user's global `settings.json` (enterprise-locked settings tolerated but hooks then silently absent); `Notification` fires for every notification type, not just permission prompts; hook needs the `duo` binary on PATH or at `~/.local/bin/duo`.

**v2 equivalent.** Per-session hooks injected via `--settings <tmpfile>` (no global mutation) posting JSON to Duo's localhost HTTP endpoint with `session_id` from stdin — v2 stack doc #5. Keep the fail-open contract (always exit 0, bounded timeout).

### 2.5 The CLI and socket (`duo` ↔ app)

**Transport.** NDJSON `{id, cmd, args, windowId?}` → `{id, ok, result|error}` (`core/socket-server.ts:1-10`). Unix socket primary (chmod 0700); TCP fallback on `127.0.0.1:<ephemeral>` with a per-launch 32-byte token published in `duo.port` (mode 0600), first line `{"token":…}` (`core/socket-server.ts:485-560`; CLI side `cli/duo.ts:594-790`). Default timeout 10 s with per-verb overrides. `duo events --follow` is the one streaming verb. `duo doctor` probes both transports and compares CLI vs app version (`ping` returns `appVersion`).

Why TCP exists: Claude Code's Seatbelt sandbox blocks Unix-socket connects by default but allows loopback TCP (`docs/DECISIONS.md:885-960`). This whole ADR disappears under MCP-over-HTTP.

**Dispatch.** `handle()` is a 1,500-line `switch` over ~110 verbs calling a `NavBridge` of ~90 closures that main.ts wires (`core/socket-server.ts:66-430`, `electron/main.ts:1600-1700`). Many verbs round-trip to the renderer via `PendingRegistry` IPC with a reply id (editor/canvas/json ops, new-tab). Reads that must be fresh call `webContents.executeJavaScript('window.__duoGetLayout()')`.

**Verb families** (`docs/CLI-COVERAGE.md`, `agents/duo.md:175-330`): browser (navigate/open/tabs/text/ax/dom/click/fill/type/key/eval/screenshot/console/errors/network/wait/inspect), navigator (reveal/ls/nav state/file rename|trash/nav pin), editor (`doc read|write|edit|goto|find|insert|delete|substitute|highlight|comment|accept|reject`, CriticMarkup), canvas (`html new|query|get|set|replace|append|remove|attr|click|comment`), json (`set|merge`), layout (`split`, `split-view`, `focus-pane`, `layout`, `status`), terminal (`new-tab`, `term tabs|tab|close`, `send`), sessions (`session list|resume|open|digest|note|next`), home (`home show|state|mode|catchup`), cron, attention, projects, workspace, windows, git (`clone`, `pull`, `pr`, `worktree`, `git-status`, `gh-auth`), vault/graph/base/rollup (in-process, no socket), packs, history, theme/author/prefs.

Per-process maintenance rule: every verb must be mirrored in `cli/duo.ts`, `skill/SKILL.md`, `agents/duo.md`, `docs/CLI-COVERAGE.md`, enforced by `scripts/check-skill-currency.mjs` (`CLAUDE.md` rule 3).

**What worked.** The agent-side ergonomics were good: orient verbs (`url`+`title`, `status`, `layout`), idempotent `navigate`, `--reveal`, structured JSON errors, `duo doctor`. The subagent prompt (`agents/duo.md`) with its session guard, external-domain routing, "never Write a file that's open in Duo" rule, and failure protocol is worth mining for MCP tool descriptions.

**What was brittle.** Sandbox fights; CLI binary version skew vs app (`duo doctor` exists because of it); the renderer being the source of truth for tabs forces main↔renderer request/reply plumbing for every verb; `main.ts` grew every `NavBridge` closure.

**v2 equivalent.** MCP tools replace verbs 1:1 where the agent needs them (`browser.*`, `editor.*`/`doc.*`, `tasks.*`, `project.*`, `sessions.*`). Keep a thin `duo` CLI only for humans and for hooks if the hook endpoint is not HTTP. Drop the 4-surface sync; the MCP schema is the single spec.

### 2.6 Cron / scheduled sessions

`CronService` (`core/cron-service.ts`) ticks every 30 s **while Duo is open**, computes next fire from presets or 5-field cron (`core/cron-schedule.ts`, DST gap known-skip), fires `runner.spawn({cwd, command})` which opens a **background** terminal tab typing `claude --session-id <uuid> '<instruction>'\n` (fresh) or `claude --resume <uuid> '<instruction>'\n` (same, if the JSONL still exists, else `fresh-fallback`). Shell jobs (`kind:'shell'`) type a raw single-line command. Headless `-p/--print/--bare/--output-format` is refused by `assertInteractiveCommand` unless `FEATURE_HEADLESS_CRON` (`shared/feature-flags.ts`). Catch-up on launch: one run if an occurrence was missed, collapsing multiples; scheduler starts only after the renderer's `SESSION_STATE_RESTORE_SETTLED` or a 20 s timeout (`electron/main.ts:1965-1980`). Store: `~/.claude/duo/cron-jobs.json` (§3.1). Tests: `core/cron-{service,schedule,store,command}.test.ts` (fake timers, lost-update, DST).

**Worked:** the command builder's quoting + control-char stripping; `lastSessionId` pointer; background landing paired with the attention badge. **Brittle:** firing requires the app open and a renderer-mounted tab; "no window" → `missed`.

**v2:** keep the schedule model and the fresh/same semantics; spawn a session object directly (no renderer tab dance); consider `launchd` only if "fires while closed" becomes a requirement.

### 2.7 Priming / skill / agent install

`InstallService.install()` writes: `~/.claude/skills/duo/**`, `~/.claude/agents/duo.md`, `~/.claude/duo/priming.md`, `~/.claude/duo/bin/{claude,duo}`, hooks, `installed.json`, and a managed block in `~/.claude/CLAUDE.md` delimited by `<!-- duo:managed-v<ver> -->…<!-- duo:end -->` with "user removed it → never re-add" semantics (`planClaudeMdMerge`, `electron/install-service.ts:250-320`). Boot-time `ensureCliShim()` self-heals the `duo` symlink to the in-bundle binary so auto-update carries the CLI forward (`docs/DECISIONS.md:769`).

**v2:** with `--append-system-prompt` and `--mcp-config` passed at spawn, none of the global `~/.claude` writes are needed. The CLAUDE.md managed-block merge logic is a good pattern if v2 ever needs a global footprint (e.g. telling non-Duo sessions that Duo exists).

---

## 3. File conventions

### 3.1 `~/.claude/duo/` inventory (Duo-owned state)

| File / dir | Schema (version) | Writer | Keep in v2? |
|---|---|---|---|
| `session-state.json` (+ `.v1.bak`) | `{version:2, savedAt, appVersion, windows:[WindowState]}` — `shared/types.ts:907-980` | `core/session-state-service.ts` | **Redesign.** v2 keys sessions by Duo uuid; a `.duo/sessions.json` per project + app registry replaces it. Nothing in it is worth migrating except terminal cwd + `lastClaudeSession.id` pairs, which could seed "resume" offers once. |
| `pins.json` | `{version:1, pins:[{kind:'browser'|'file', ref, title?}]}` — `core/pins-service.ts` | PinsService | Later. Could import as v2 "pinned tabs". |
| `nav-pins.json` | `{version:1, pins:[{path, kind:'file'|'folder', title?}]}` — `core/nav-pins-service.ts` | NavPinsService | Should import into v2 sidebar pins (trivial). |
| `projects.json` | `{version:1, pins:[absRoot…]}` — `core/projects-service.ts` | ProjectsService | Should import as v2's initial project registry seed. |
| `settings.json` | `{multiWindow, homeMode, frontmatterDefaultExpanded, lastVaultFormat}` — `core/settings-service.ts` | SettingsService | Drop (v2 uses `UserDefaults`/own file). |
| `cron-jobs.json` | `{version:1, jobs:[CronJob], settings:{defaultCatchUpOnLaunch}}`; `CronJob` = base `{id, name, cwd, schedule, catchUpOnLaunch, enabled, lastRunAt, lastRunState, createdAt}` + `kind:'claude'{instruction, session:'fresh'|'same', lastSessionId}` or `kind:'shell'{command}` — `shared/types.ts:700-840` | CronStore | Should import if v2 ships scheduling. |
| `session-digests.json` | `{version:1, digests:[SessionDigest]}` — `shared/types.ts:1848` | SessionDigestStore | Drop; rebuild into SQLite index. |
| `home-state.json` | `{version:1, watermark?, annotations:[{uuid, note?, next?, reviewedAt?}]}` | HomeStateStore | Should import annotations (agent notes are not rebuildable). |
| `browser-history.json` | `{version:1, entries:[{url,title,lastVisited,visitCount}]}` cap 1000 | BrowserHistoryService | Later; `WKWebView` has no history store, so v2 needs its own anyway — same schema is fine. |
| `workspace-history.json`, `active-workspace.json` | recent `.duo-workspace` files; `{path,name}` | ENH-167 services | Drop with workspaces-as-files. |
| `open-recents.json` | `{version:1, recents:[{target,label,kind:'local'|'github-file'|'github-repo'|'url',lastOpenedAt}]}` cap 10 | OpenRecentsService | Later. |
| `external-domains.json` | `{domains:[ "host" | "*.suffix" | {host, reason} ]}` — `core/external-domains-service.ts:22-30` | bootstrapped from `fork.config.json`, user-edited | **Keep schema** for v2's off-host routing list (user-curated). |
| `file-history/index/<sha256(abspath)>.json` + `file-history/blobs/<sha256(abspath)>/<contentHash>` | index `{version:1, path, snapshots:[{id:'<ts>-<hash8>', ts, hash, size, source:'save'|'agent'|'restore'|'open'|'external'}]}`, deduped content blobs, 200 cap, 90 s coalescing — `core/file-history-service.ts:70-110` | FilesService write hook | Should re-implement (same policy); do not import old blobs. |
| `update-check.json`, `installed.json`, `installed-packs.json` | caches | update-checker, install-service | Drop. |
| `priming.md`, `bin/claude`, `bin/duo`, `hooks/*.sh`, `help/`, `packs/`, `extra-packs/`, `distros/`, `checkouts/<owner>-<repo>@<ref>/`, `logs/{install-shim.log,last-conflict.log}` | install artefacts, lesson packs, managed GitHub checkouts | install-service, distro-pack-service, open-checkout | Drop (packs/lessons/checkouts are out of v2 scope). |

Also: `~/Library/Application Support/duo/{duo.sock, duo.port, browser-session/}`.

**Compatibility verdict:** a v1 user's *folders* contain almost nothing Duo-specific — the state tree lives under `~/.claude/duo/`, not in projects. So v1 projects open in v2 unchanged by construction. The only project-local artefacts are below.

### 3.2 Project-local conventions

| Convention | Where | v2 |
|---|---|---|
| **Project qualification**: a folder is a project iff `(git work-tree root || CLAUDE.md || .claude/)` and something is "working in" it; membership = deepest qualifying ancestor; `$HOME` and `/` excluded; colour = djb2(root) % 6 | `shared/projects.ts`, `core/projects-service.ts:hasMarker` | **Keep the qualification rule** as v2's auto-discovery; v2 adds `PROJECT.md`/`.duo/project.json` as the explicit marker. Keep hash-stable colours. |
| `.duo-workspace` files | `{schemaVersion:1, name, savedAt, appVersion, state:SessionState}` — `core/workspace-file-service.ts` | Drop. |
| `<file>.duo.json` sidecar beside an HTML canvas | `{version:1, scripts?, comments?[], recentEdits?[], resolvedThreads?, properties?}` — `renderer/components/Page/sidecar.ts` | Drop (no HTML canvas in v2). Note it contradicts the no-sidecar rule and was tolerated as "Duo-owned concept". |
| Worktrees at `<repo>/.claude/worktrees/<slug>` on branch `claude/<slug>` | `core/git/worktree.ts:198-230` | Should keep — matches Claude Code's own worktree location so `/resume` finds them. |
| Reserved frontmatter namespace `duo.*` | `docs/DECISIONS.md:251` | Keep the reservation for `tasks/*.md`. |
| CriticMarkup for tracked changes, comments as `{>>id:…\|author:…\|ts:…\|reply-to:…\|body<<}` | `core/markdown/criticmarkup.ts`, `docEdit.ts` | Later. Pure, well-tested; portable if v2 wants agent "suggestions" in the editor. |
| Frontmatter split/join (`---` fences, CRLF-aware, body after a blank line) and non-throwing YAML parse | `core/markdown/frontmatter.ts`, `frontmatterParser.ts` | Keep semantics for `tasks/*.md`. |
| `image-<YYYYMMDD-HHMMSS>-<hash>.<ext>` beside the doc for inserted images | `electron/files-service.ts:277-291` | Keep. |
| **Vault (graphbook)**: OKF mode = root `_index.md` (legacy `index.md`) with `okf_version:` frontmatter, standard relative md links, `_log.md`, `output/` (legacy `out/`); Obsidian mode = `.obsidian/` + wikilinks + `.base`. Folders `templates/`, `inbox/`, `people/`, `themes/`, `initiatives/`, `notes/YYYY/MM/`, `rollups/`. Typing key is frontmatter `type:`; templates declare `folder`/`filingParent`/`filingLoose`/`folderNote`. Default vault pointer + `knownVaults` in a prefs file (`core/vault/default-vault.ts`). | `core/vault/**`, `.claude/rules/vault.md` | **Open question** (§7). The code is pure fs and CLI-resident; v2 could ship it unchanged as a separate CLI/MCP later. v2's `tasks/*.md` with frontmatter is a strict subset of this model (`type: task`). |

### 3.3 Write discipline (keep)

- Atomic `write tmp → rename`, unique tmp `${path}.${pid}.${rand}.duo.tmp` (`core/write-queue.ts:uniqueTmpPath`).
- One `createWriteQueue()` per store to serialize read-modify-write (lost-update test `core/write-queue.test.ts`).
- Defensive, field-by-field validation on read; corrupt = empty, never crash.
- Autosave 800 ms; conflict detection by normalized baseline compare (`core/html/duo-normalize.ts`), with a diagnostic dump to `logs/last-conflict.log` (`duo doc conflict-log`). v2's SHA-256 echo suppression is the simpler version of this.
- Watcher quirks already solved: resolve symlinks before watching and map events back (`electron/files-service.ts:72-90`, `/tmp` → `/private/tmp`); watch the parent dir too because editors save via rename (`:434-441`).

---

## 4. Attention model as implemented

**Signals.**

| Signal | Source | Effect |
|---|---|---|
| `Stop` hook | Claude finished a turn | `needsAttention = true` for `$DUO_TAB` |
| `Notification` hook | any Claude notification (permission prompt, idle nudge, …) | `true` |
| `UserPromptSubmit` hook | user sent a message | `false` |
| `duo attention --tab <id> --state set\|clear` | agent/CLI | explicit |
| tab becomes active | renderer | `false` (focus clear) |
| unknown event string | — | `true` (fail toward attention; `core/attention.ts`) |

**States.** Per tab, a single boolean in renderer memory (`attentionByTabId`, `renderer/App.tsx:2822-2845`); never persisted; lost on relaunch. Rendered as an amber dot on non-active tabs only (`renderer/components/TabBar.tsx:133`).

**Transitions / debouncing.** None beyond: (1) a SET targeting the *active* tab is ignored (you are looking at it), (2) a CLEAR always applies, (3) activating a tab clears it. No timers, no coalescing.

**False positives / gaps observed in code.**
- `Notification` fires for non-actionable notifications, so a session that merely posted "still working" gets flagged.
- `Stop` fires on every turn end including sub-second tool turns in long agent loops? No — `Stop` is end-of-response only, but a response that ends with a question vs. one that ends "done" both set the flag; no distinction between *waiting for input* and *finished*.
- The Catch-up board derives a richer reason from the transcript instead: `plan-to-approve` (last `ExitPlanMode` with no human turn after), `blocked` (last tool_result `is_error` or a `toolUseResult` string starting `Error`), `question` (ends on assistant text with no pending tool_use) (`electron/session-digest.ts:extractAttentionReason`). Column model: **Needs you** (attention, full card) · **In progress** (live = full; closed-resumable = compact) · **Done** (finished = PR opened, `.md`/`.html` created, or all todos completed; removed-worktree sessions land here struck through). A 7-day window applies only to closed sessions (`electron/home-snapshot.ts:666-790`).
- Liveness for the board = "a `claude` process with this cwd exists", attributed Duo vs external; a session whose cwd was deleted is `cwdGone`.

**What to take into v2's fleet board.** The four-state vocabulary the legacy code converged on is right: `needs-you` (with reason: permission | question | plan | blocked), `working`, `idle/done`, `gone`. v2 gets `busy/waiting/idle` + `waitingFor` straight from `claude agents --json` (authoritative), and hook events (`Stop`, `Notification` with `notification_type`, `PermissionRequest`, `UserPromptSubmit`) as low-latency edges. Keep: "never badge the focused session", "focus clears", "fail toward attention". Add: a short grace (≈1 s) before flipping to `needs-you` after `Stop` so a chained follow-up turn does not flicker; distinguish `Notification.permission_prompt` from other notification types; persist the last reason so the board survives relaunch.

---

## 5. Browser integration

### 5.1 BrowserManager (`electron/browser-manager.ts`)

- One `WebContentsView` per tab, all attached to `window.contentView`; inactive views shrunk to 1×1; stable 1-based numeric ids; `about:blank` new tab; closed-tab stack (cap 10) for reopen; aux (split) slot holds one tab with separate bounds.
- Persistent partition `persist:duo-browser` for logged-in sites.
- **Three browser modes** (`isLocalUrlForBrowserMode`, `routeOffHostIfMatched`): `local-only` (default for new installs: only `file://`, `localhost`, `127.0.0.1`, `[::1]`, `about:`, `devtools:` render; everything else → `shell.openExternal` + an `EXTERNAL_REDIRECTED` banner), `filtered` (consult `external-domains.json`), `unfiltered` (`--i-understand`). Intercepts `will-navigate` and `will-redirect` so a redirect hop onto a listed SSO host bounces too.
- `navigateOrFocus(url)` normalizes (strip hash + trailing slash) and reuses an open tab; `openTab` dedups `file://` URLs only.
- `file://` tabs get a chokidar watcher (250 ms debounce) and auto-reload on change (BUG-130).
- Key forwarding: `before-input-event` intercepts Duo-owned ⌘ shortcuts inside the page and replays them to the renderer (`wireKeyForwarding`).
- History recorded on `did-navigate` + `page-title-updated`; skips `about:`, `chrome:`, `devtools:`, help pages.
- Find-in-page via Electron `findInPage` with `found-in-page` result forwarding.

### 5.2 CdpBridge (`electron/cdp-bridge.ts`)

Attaches `webContents.debugger` ('1.3') to every tab ever shown; enables `Page`, `Runtime`, `Log`, `DOM`, `Accessibility`, `Network`. Registers six bindings and injects four IIFEs on attach and on every `Page.frameNavigated`:

| Injected script | Binding | Purpose |
|---|---|---|
| `SELECTION_OBSERVER_IIFE` | `duoSelectionPush`, `duoSendToDuoClick` | `selectionchange`/scroll/resize → `{snapshot:{kind:'browser', url, text, surrounding(≤1k), selector_path}, rect}`; renders an in-page "Send → agent" pill (page-side because WCV composites above renderer DOM); pill hidden unless `window.__duoClaudeLive` |
| `INSPECT_OBSERVER_IIFE` | `duoInspectClick` | hover overlay (orange outline, tag/dims tooltip); click **freezes** the element and shows a pill; pill click ships `{tag, selector_path, headingTrail, innerText(≤2000), attrs(id, role, aria-label, aria-labelledby, href, src, name, type, data-testid, data-duo-id)}`; ESC exits (null sentinel); gated by `window.__duoInspectActive` |
| `PATH_LINK_FORWARDER_IIFE` | `duoOpenPath`, `duoOpenPathSplit` | `[data-duo-path]` links on `file://` pages open files in Duo (main or split) |
| `PLAYGROUND_RUNTIME_IIFE` | `duoPlaygroundAction` | `data-duo-action` buttons on `file://` pages (lesson packs; `terminal:send`, `claude:spawn`, …) |

Selector algorithm (shared by selection and inspect): walk up to `body`, `tag#id` short-circuits when the id is a valid identifier, else `tag:nth-child(n)`, joined with ` > ` (`cdp-bridge.ts:303-325`). Heading trail = deepest H1–H6 per level that precede the element in document order.

Event rings: console (`Runtime.consoleAPICalled` + `Log.entryAdded`, 500), errors (`Runtime.exceptionThrown`, 200), network (stitched `requestWillBeSent`/`responseReceived`/`loadingFinished`/`loadingFailed`, 300).

Agent-facing operations: `getDOM`, `getText(selector)` (innerText), `getAxTree(selector)` + `axToMarkdown` (needed for Google Docs/Figma canvases), `click`, `fill`, `focus`, `insertText`, `dispatchKey(name, modifiers)`, `evalJS`, `screenshot(selector?)` (base64 or file), `waitForSelector`, `getBrowserSelection`, plus the three rings.

### 5.3 How a selected element reached the agent

1. User hits ⌘⇧C in the page or the agent runs `duo inspect --on` → `cdp.setInspectMode(true)` flips `__duoInspectActive` in every attached page and pushes `BROWSER_INSPECT_MODE` to the renderer (`browser-manager.ts:953-970`).
2. Click → freeze → pill → `duoInspectClick(json)` → `Runtime.bindingCalled` → `onBrowserInspectClick` listener → IPC `BROWSER_INSPECT_CLICK` to the renderer (`electron/preload.ts:262`).
3. Renderer formats with `formatInspectA` (`renderer/components/editor/sendFormat.ts:296-340`):
   ```
   > <inspect> button#submit  @ https://example.com — "Form Page"
   > section: Sign up > Step 2
   > selector: html > body > form > button:nth-child(3)
   > attrs: role=button, aria-label="Continue"
   ````text
   Continue
   ````
   ```
   and writes it to the active PTY **without Enter** (the user confirms). Three formats exist for text selections: A quoted+provenance (default), B literal, C opaque token `<<duo-sel-…>>` expanded via `duo selection` (`sendFormat.ts:1-20`). 5,000-char cap. Prompt-injection hardening: CR/LF/U+2028/9 stripped from single-line fields; code fences sized longer than any backtick run inside (`sendFormat.ts:36-60`, tests tagged `[security]`).
4. The agent can follow up with `duo dom <selector>`, `duo screenshot --selector`, `duo click <selector>`.

Editor selections carry `{path, text, paragraph, heading_trail[], start, end}` (ProseMirror positions) so `doc write --replace-selection` is exact (`shared/types.ts:1143`).

### 5.4 Capabilities v2 must replicate on WKWebView (no CDP)

Must:
1. Persistent logged-in profile + a private profile; `localhost` and `file://`/folder serving (`WKURLSchemeHandler`).
2. Off-host routing: a user-curated host list (keep `external-domains.json` schema) + the three-mode switch; intercept at `decidePolicyFor navigationAction` **and** redirects; show the "opened externally" banner.
3. Element inspector: hover overlay, click-to-freeze, pill, ESC; payload = tag, selector path (same algorithm), heading trail, innerText cap, allow-listed attrs, **plus** v2's additions: outerHTML, computed styles, bounding rect, element screenshot via `takeSnapshot(with:)`. Deliver to the focused session as a structured paste (no Enter) *and* expose it via `browser.get_selected_element` MCP.
4. Text-selection observer with provenance + surrounding block + selector; the same three send formats are overkill — ship format A only.
5. Page driving: `navigate`, `reload`, `back/forward`, `click(selector)`, `fill`, `focus`, `type`, `key(name, modifiers)`, `eval`, `wait(selector, timeout)`, `read_page` (innerText + an AX-tree-to-markdown fallback for canvas apps), `screenshot(selector?)`, tab list/switch/close/open-or-focus.
6. Console and uncaught-error capture (`WKUserScript` wrapping `console.*` and `window.onerror`; no CDP `Log` domain) — ring buffers with `since` cursors.
7. `file://` auto-reload on change; find-in-page; Duo shortcut forwarding when the web view has focus.

Should: network request log (WKWebView has no network domain; approximate with `fetch`/XHR monkey-patching in a user script or skip), `[data-duo-path]` link handling for Duo-authored HTML.

Later/drop: playground runtime, lesson packs, `duo html *` canvas ops, aux-slot browser.

Re-injection rule to copy: every script is idempotent (`if (window.__duoX) return`) and re-applied on every navigation; state flags (`__duoClaudeLive`, `__duoInspectActive`) are pushed to all tabs, not just the active one (BUG-133/134 were about forgetting this).

---

## 6. Requirements

### 6.1 Pull forward

| # | Requirement | Evidence | Priority | v2 note |
|---|---|---|---|---|
| 1 | Every Duo-spawned process carries `DUO_SESSION=1` + a session id env stamp so agents and hooks can self-identify | `core/pty-manager.ts:149-167`, `agents/duo.md:37-62` | must | `DUO_SESSION_ID=<uuid>` replaces `DUO_TAB`. |
| 2 | Spawn into a missing cwd falls back to the nearest existing ancestor and tells the user | `core/cwd-utils.ts`, `pty-manager.ts:169-208` | must | |
| 3 | Never send a <8-col or 0-row resize to the PTY | `pty-manager.ts:233-254` | must | SwiftTerm hidden views: freeze size, do not resize to zero. |
| 4 | Resume semantics: plain `--resume` for a closed session; `--resume --fork-session` only when the session is live elsewhere; never attach two writers | `claude-session-tracker.ts:buildResumeCommand`, `main.ts:5810-5870` | must | Use `claude agents --json` to detect "live elsewhere". |
| 5 | Session title ladder: custom-title → ai-title → compact-summary intent → `/command` → cleaned first prompt → short uuid; strip harness wrapper tags and fillers | `claude-session-tracker.ts:cleanAndTruncate`, `session-digest.ts:extractGoal` | must | Port to Swift; feeds the fleet card title. |
| 6 | Bounded transcript reads (seek head/tail ladders, per-file timeout, concurrency cap); never slurp a JSONL | `claude-session-tracker.ts:readSessionTailMeta`, `home-snapshot.ts:99-130` | must | Sessions reach 270 MB; iCloud-evicted files stall. |
| 7 | Deterministic session digest (todos, files, artifacts, attention reason, git branch) with the "no inference, rebuildable" invariant and a test that proves cache-delete → identical rebuild | `electron/session-digest.ts`, `.test.ts:331-350` | should | Lives in the SQLite index; refresh on `Stop`. |
| 8 | Attention contract: set on Stop/Notification, clear on UserPromptSubmit and on focus; never badge the focused session; unknown events fail toward "needs you"; hook scripts always exit 0 and are bounded | `core/attention.ts`, `skill/scripts/duo-attention.sh`, `renderer/App.tsx:2822-2845` | must | Add reason + grace; see §4. |
| 9 | Catch-up columns and finished-ness rules (PR opened / doc created / all todos complete; `cwdGone` struck through; open sessions bypass the age window) | `home-snapshot.ts:666-790` | should | Fleet board "Done" semantics. |
| 10 | Process-primary liveness: a session is open iff a live `claude` process is attributed to it; Duo-hosted = focusable, external = fork-only | `home-snapshot.ts:attributeOpenSessions`, `main.ts:4880-4950` | must | Replace `ps`/`lsof` with pid from `forkpty` + `agents --json`. |
| 11 | Element inspector payload shape and prompt-injection sanitization | §5.3; `sendFormat.ts:36-60` | must | Same algorithm for selector path. |
| 12 | Browser off-host routing with a user-editable host list (exact + `*.suffix` + `{host, reason}`), intercepting redirects, with a visible banner | `core/external-domains-service.ts`, `browser-manager.ts:879-932` | must | Keep file schema. |
| 13 | Pill/affordances for "send to agent" only when a Claude session is live to receive it | `cdp-bridge.ts:1013-1050`, DECISIONS "Claude-presence gating" | must | Gate on focused session status. |
| 14 | Agent edits to an *open* file go through the app, not the filesystem; a direct write is detected, not clobbered | `agents/duo.md:79-98`, `skill/scripts/duo-open-file-guard.sh`, `core/socket-server.ts:isPathOpenAs` | must | MCP `editor.*` tools + SHA echo suppression + dirty-buffer merge (v2 spike 5). |
| 15 | Atomic writes + per-store write queue + unique tmp names + defensive reads | `core/write-queue.ts` and every `*-service.ts` | must | |
| 16 | Durable file history: content-addressed, append-only, captured off the save path, 90 s coalescing for autosaves, agent/restore snapshots never coalesced, `restore` is itself captured | `core/file-history-service.ts` | should | Also protects `tasks/*.md` from agent mistakes. |
| 17 | Watcher hygiene: realpath before watch and map back; watch parent dir for rename-saves; 250 ms debounce | `electron/files-service.ts:72-90, 424-470` | must | v2 FSEvents impl. |
| 18 | Project auto-discovery rule (git root or `CLAUDE.md`/`.claude/`; deepest ancestor; exclude `$HOME`), hash-stable colours, pinned projects survive close-all | `shared/projects.ts`, `core/projects-service.ts` | must | Add `PROJECT.md`/`.duo/` as markers. |
| 19 | Worktrees under `<repo>/.claude/worktrees/<slug>`, branch `claude/<slug>`; fold worktree sessions into the main repo on the board | `core/git/worktree.ts`, `home-snapshot.ts:rollupProjects` | should | |
| 20 | Scheduled sessions: presets + cron, fresh/same with `lastSessionId` pointer, interactive-only gate, catch-up-once on launch, background landing + badge | `core/cron-*.ts`, `shared/feature-flags.ts` | later | Import `cron-jobs.json`. |
| 21 | Agent self-narration (`note`/`next`) stored Duo-side keyed by session uuid, surviving tab close | `core/home-state-store.ts` | should | MCP `sessions.annotate`. |
| 22 | Resolve the user's `claude` binary without relying on the GUI PATH (well-known dirs, then login shell) and surface "not installed" clearly | `core/resolve-claude.ts` | must | Once per launch + Settings override. |
| 23 | Orientation reads for the agent: status (open files, dirty, active), layout, selection | `duo status/layout/selection` in `socket-server.ts` | must | MCP `project.status`, `browser.state`. |
| 24 | Fail-open hook merge that identifies its own entries by a marker and never touches foreign hooks (if v2 ever writes global settings) | `install-service.ts:385-417` | later | Prefer `--settings` per session. |
| 25 | Frontmatter split/join rules (CRLF, blank-line after fence) and non-throwing YAML parse with "must be a mapping" error | `core/markdown/frontmatter.ts`, `frontmatterParser.ts` | must | `tasks/*.md`. |
| 26 | Reserve the `duo.*` frontmatter namespace | `docs/DECISIONS.md:251` | should | |
| 27 | Image insert convention `image-<stamp>-<hash>.<ext>` beside the doc | `files-service.ts:277-291` | should | |
| 28 | Browser history with recency×frequency ranking for the address bar | `core/browser-history-service.ts` | later | |

### 6.2 Do not carry forward

| Item | Evidence | Why |
|---|---|---|
| Launching `claude` by typing into zsh, and all cwd→freshest-JSONL inference (`detectLatestClaudeSession`, `sessionIdForTab`, positional tab matching, `tabsThatHostedClaude`) | `renderer/App.tsx:2010`, `main.ts:640-720, 5010-5040` | v2 mints `--session-id`; the whole layer and its documented races vanish. |
| `ps`-polling presence probe | `core/claude-presence.ts` | Owned child pid + `agents --json`. |
| `claude` PATH shim + `priming.md` + SessionStart priming hook + CLAUDE.md managed block | `install-service.ts:1-60, 980-1030` | `--append-system-prompt` at spawn; MCP tool descriptions carry the "how to use Duo" knowledge. |
| Global `~/.claude/settings.json` hook merge | `install-service.ts:1100-1300` | Per-session `--settings`. |
| Unix-socket/TCP-token CLI transport, `duo doctor`, sandbox ADR | `core/socket-server.ts:485-560`, `DECISIONS.md:885` | MCP over localhost HTTP; sandbox allows loopback. |
| The ~150-verb CLI as the agent API, 4-surface sync, committed `cli/duo` bundle | `cli/duo.ts`, `CLAUDE.md` rule 3/9 | MCP schema is the spec; keep at most a tiny human CLI. |
| Renderer-as-source-of-truth for tabs with `PendingRegistry` round-trips for every agent op | `main.ts` dispatchers, `socket-server.ts` NavBridge | Native app: one model in Swift. |
| 6k-line `main.ts` and 2.5k-line `socket-server.ts` | — | Package boundaries (`DuoCore/DuoClaude/DuoWeb/DuoMCP`). |
| HTML canvas (`duo html *`, `data-duo-id` injection, `.duo.json` sidecars, CriticMarkup-in-HTML), playgrounds, lesson packs, distro packs, pack-builder | `renderer/components/Page/**`, `core/pack-loader.ts`, `electron/distro-pack-service.ts`, `shared/playground-actions.ts` | Out of v2 scope; large surface, contradicted the no-sidecar rule. |
| Workspaces-as-files (`.duo-workspace`, active/recent workspace stores, multi-window envelope) | ENH-167/191 services | v2 state is per project + app registry; multi-window is a later concern. |
| TipTap/ProseMirror editor and `tiptap-markdown` round-trip (not byte-faithful; BUG-085 autosave fights) | `package.json` deps, `agents/duo.md:79-89` | v2 decided CM6 live preview with text as source of truth. |
| Managed GitHub checkouts + share-back PR flow (`~/.claude/duo/checkouts/`, `duo pr`) | `core/open-checkout.ts`, `core/git/share-back.ts` | Niche; revisit only if PMs ask for "open just this doc from GitHub". |
| xterm.js/Electron-specific: WCV bounds reconciliation, key forwarding, overlay muting, `once-guard`, `safe-send`, `window-resolve` | `electron/*.ts` | Electron artefacts. |
| Three "send format" variants (B literal, C opaque token) and `selection-format` verb | `sendFormat.ts` | Format A only; the agent reads the full selection via MCP. |
| Auto-update via `electron-updater`, fork config injection, `electron-builder.yml` | `electron/auto-updater.ts`, `electron.vite.config.ts` | Sparkle or a plain "new version" check for a notarized DMG. |

---

## 7. Open questions for Geoff

1. **Vault/graphbook.** `core/vault/**` is ~9k lines of pure, tested TypeScript that runs with no app (OKF format, rollups, relink). Is graphbook in or out of v2's product scope? If "later", should v2's `tasks/*.md` frontmatter be designed as an OKF-compatible subset (`type: task`, slug filenames, relative md links) so a vault can later wrap a project folder without migration?
2. **Shell tabs.** v2 says "every session keeps a live terminal". Do you also want plain shell tabs (no Claude)? If yes, "Claude typed into a shell" detection (requirement 10's exception) and the cron `shell` job kind come back.
3. **Scheduled sessions.** Keep ENH-223 cron in v2 v1, or defer? If kept: in-app timer (fires only while open, as today) or `launchd`?
4. **Off-host default.** Legacy defaulted new installs to `local-only` (everything non-local opens in Safari/Chrome) because sites misbehaved in Electron and because of managed-Mac policy. v2's brief wants logged-in third-party sites inside Duo. Confirm `unfiltered` + an opt-in blocklist is the v2 default, and whether the enterprise/"never circumvent IT controls" posture (`agents/duo.md:100-112`) still matters.
5. **Attention reason granularity.** Do you want the board to distinguish permission-prompt vs. question vs. plan-approval vs. blocked (legacy's Catch-up did; its tab badge did not)?
6. **Migration.** Should v2 read `~/.claude/duo/{projects.json, nav-pins.json, cron-jobs.json, home-state.json, external-domains.json}` once on first launch to seed itself, or start clean? (`session-state.json` is not worth importing.)
7. **Track changes.** CriticMarkup suggestions (`doc insert/delete/substitute/comment/accept/reject`) were a differentiator for PM review flows. In v2's CM6 editor, is agent "suggest mode" a v1 requirement, later, or dropped?
8. **Multi-window.** Legacy shipped it (ENH-191) with a lot of complexity. Single window for v2 v1?
9. **File history.** Keep the 200-snapshot / 90 s-coalesce policy, or rely on git + Claude's `/rewind`?
10. **Landmine confirmation.** `encodeProjectDir` never implemented the >200-char hash rule; if v2 runs under the user's default `~/.claude` (not a managed `CLAUDE_CONFIG_DIR`), it must. Also confirm whether any legacy users have long paths that would have broken resume.

---

## Appendix A — Test files that encode intended behaviour (read before porting)

- `core/attention.test.ts` — clear/set contract.
- `electron/duo-attention-hook.test.ts` — runs the real hook script; badge must fire even if digest fails; no `DUO_TAB` → no-op.
- `electron/claude-session-tracker.test.ts` — `encodeProjectDir` (incl. symlink resolution), title ladder, wrapper-tag stripping.
- `electron/session-digest.test.ts` — PR only from tool results, tests chip only from runner output, attention reasons, goal ladder, no `Date.now()`, §D9 rebuild.
- `electron/home-snapshot.test.ts` — worktree fold, home-dir non-swallow, open attribution, perf bound (85 sessions < 100 ms, never `readFile` a JSONL), catch-up columns/tiers/dedup.
- `core/session-state-service.test.ts` — concurrent-flush lost-update negative control, v1→v2 migration + `.v1.bak`.
- `core/write-queue.test.ts` — lost-update negative control.
- `core/cron-schedule.test.ts` / `cron-service.test.ts` / `cron-command.test.ts` — DST, catch-up collapse, headless gate, quoting.
- `core/socket-server.test.ts` — boot-race contract (ping works before windows exist), window addressing, verb routing.
- `electron/cdp-bridge.test.ts` — IIFE invariants (pill gated on `__duoClaudeLive`).
- `renderer/components/editor/sendFormat.test.ts` — `[security]` prompt-injection cases.
- `core/pty-manager.test.ts`, `core/pty-owner.test.ts`, `core/claude-presence.test.ts` — env stamps, resize floors, per-window isolation.
- `core/markdown/*.test.ts`, `core/vault/*.test.ts` — editor/vault semantics if either is pulled forward.
