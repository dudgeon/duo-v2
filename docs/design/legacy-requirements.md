# Duo v2 — Requirements carried forward from legacy Duo

Status: proposed · 2026-10-03 · **Open questions in §4 were answered on 2026-10-03; see `decisions.md` (DL-1 to DL-20).**

> **Later decisions win (2026-10-05).** Some LRs were revised: LR-7 by DL-59, LR-15 by DL-45, LR-55 by DL-74, LR-44 and LR-45 by DL-3 and F-72. `decisions.md` wins where they differ.

Consolidates three reviews of `~/repos/duo` (v0.1.0 → v0.13.7, 1,133 commits, Apr–Sep 2026):

- **[P]** `docs/research/legacy-duo-product-review.md`: VISION, DECISIONS, PRDs, UX docs, help (41 requirements, 15 questions)
- **[A]** `docs/research/legacy-duo-architecture-review.md`: `core/`, `cli/`, Electron main process, tests (28 requirements, 10 questions)
- **[C]** `docs/research/legacy-duo-changelog-and-studies.md`: CHANGELOG (185 BUG / 201 ENH / 28 FOLLOWUP) and ~60 research studies (42 invariants `LDI-n`, 36 requirements, 12 questions)

Each requirement below cites its sources; follow them for evidence. Where a requirement changes a decision already in `claude-design-handoff.md` (the brief) or `stack-recommendation.md` (the stack), it is listed in §1 first.

---

## Summary

Legacy Duo spent most of its effort on four problems: keeping an editor honest against a disk that Claude, git and iCloud also write to; keeping a terminal alive while Claude's TUI owns it; making a web view coexist with native chrome; and giving the agent a precise way to drive the app [C]. Its biggest structural costs came from inferring things it could have owned. It typed `claude` into zsh and guessed the session from the freshest transcript; it polled `ps` for liveness; it round-tripped markdown through TipTap. v2's decisions to mint `--session-id`, read `claude agents --json`, edit markdown text directly, and talk to the agent over MCP remove those layers by construction [A].

What survives is a set of **behavioural rules learned the hard way**. They are mostly about attention, resume, file reconciliation and terminal safety, and v2 should adopt them as spec, not rediscover them.

---

## 1. Where legacy evidence changes a v2 decision

| # | v2 today | Legacy evidence | Proposed change | Needs Geoff? |
|---|---|---|---|---|
| D1 | **"Home"** names the triage *project folder* (brief §3.1). | Legacy "Home" was the re-entry / attention *screen* [P §1.1; C ENH-212]. Users and docs used the word for that for five months. | Keep **Home = the triage folder**. Name the attention surface something else: **Inbox** or **Board**. | Yes: pick the name |
| D2 | Five session states shown as five groups (brief §3.3). | Legacy converged on **three attention columns: act / wait / review**. Blocked, permission, question and plan-to-approve are *reasons* under Needs you. Closed-but-resumable is a compact tier *under* In progress, not its own column. **Done means a real deliverable** (a `.md`/`.html` produced, plan complete), not "stopped" [P 1; A §4; C LDI-23, -26]. | Keep five states in the model; show **three columns** with reason chips; idle/resumable as a tier; tighten "Ready for review" to "produced a deliverable". | No; update the brief |
| D3 | `.duo/sessions.json` in the project holds the session index (stack #10). | The owner locked **"no Duo sidecar for session metadata"** in May 2026 (ENH-183 D9) to avoid drift from Claude's own data. It then had to be exempted repeatedly because reading transcripts live on every render was too slow (ENH-231 D8) [P Q2; C LDI-1]. | Split the data. **Claude-authoritative facts** (title, last prompt, todos, files touched) are derived into the rebuildable SQLite index and never written to `.duo/`. **Duo-owned facts** (session ↔ task links, agent `note`/`next`, user star, archive flag) live in `.duo/sessions.json`. Test: delete the index → identical UI. | **Yes: confirms reversing D9** |
| D4 | Browser must hold logged-in third-party sites in-app (stack constraints). | Legacy defaulted new installs to **`local-only`**: every non-local URL bounced to Safari/Chrome with a banner. Reasons: Electron misbehaving with SSO, and a managed corporate Mac [A Q4; P Q6; C LDI-40]. | Default to **in-app for everything**, keep the `external-domains.json` schema as an **opt-in list** of hosts that open externally (SSO, policy). Spike 7 re-tests Google SSO in WKWebView, the one reason Electron was chosen that was never re-tested. | Yes: is v2 used on a managed laptop? |
| D5 | Every session belongs to a project folder with `PROJECT.md` (brief §3.2). | Legacy insisted **"work in any folder; projecthood is derived, never a front door"**. Folders with `.git` or `CLAUDE.md` plus activity counted; deepest wins; `$HOME` and `/` never qualify [P Q3; A 18; C LDI-27]. The derived model also caused a flicker loop (BUG-269). | Explicit `PROJECT.md` stays the definition of a project. **Folders with Claude history or markers but no manifest show as "unregistered"** and can be adopted in one click. That serves "find before you create" without the flicker. Sessions in unregistered folders appear as **Unfiled**. | Yes: confirm |
| D6 | Stack spike 8 tests the in-app MCP server over localhost HTTP. | Claude Code's sandbox **blocks Unix sockets**; legacy needed a TCP fallback and a `duo doctor` diagnostic to explain failures [P 36; A; C LDI-36]. | Add to spike 8: run a sandboxed session and confirm loopback HTTP MCP works; ship a one-line diagnostic in the app. | No |
| D7 | Stack spike 1 lists `TERM_PROGRAM` variants. | Legacy set `TERM_PROGRAM=Duo`; Claude Code only enables the kitty keyboard protocol for allow-listed values [C Q10; stack research]. | Keep in spike 1; decide whether to present as an allow-listed terminal. | No |
| D8 | Stack #11: config-dir strategy undecided. | Legacy's `encodeProjectDir` **never implemented the >200-char truncate+hash rule**, so long paths would break resume [A landmine]. Legacy also installed hooks, a skill, a subagent, a PATH shim and a managed `CLAUDE.md` block into `~/.claude`, and spent dozens of entries on upgrade, orphan and locked-settings edge cases [C Q12; P Q11]. | Strengthens the case for a **Duo-managed config dir**, and for a principle: **v2 installs nothing into `~/.claude`.** Everything is per session via `--settings`, `--mcp-config`, `--append-system-prompt`. If v2 ever uses the default config dir, implement the long-path rule. | Yes: part of #11 |
| D9 | Brief prompt B shows "Claude's additions marked". | Legacy had three meanings: an **ephemeral just-added highlight** (until your next edit), **CriticMarkup suggestions** with accept/reject, and a **history diff** [P Q5]. | v1 = the ephemeral highlight (must). History diff = should. CriticMarkup suggest mode = later. | Yes: confirm |
| D10 | Stack: one window implied, not stated. | Multi-window took three releases and a registry refactor (ENH-191) [P; C]. | **Ship one window.** Design state window-aware (resolve defaults by identity, not focus). | No |

---

## 2. Requirements to pull forward

Priority: **M** = v1 must, **S** = should (v1 if cheap), **L** = later. IDs are stable for the spec (`LR-n`).

### 2.1 Sessions and attention (the fleet board)

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-1 | **Three attention columns.** Needs you (reason chip: permission / question / plan-to-approve / blocked; longest wait first) · In progress (live sessions as full rows; closed-but-resumable as a compact tier) · Done (real deliverable only, leading with the artifact). A needs-you session is never demoted to a one-liner. Open sessions never age out; closed ones drop after 7 days. | M | P 1; A 9; C LDI-23, -26, 14–15 |
| LR-2 | **Attention signals.** Set on `Stop` and on `Notification` *only for actionable types* (`permission_prompt`, `PermissionRequest`), clear on `UserPromptSubmit` and on focus. Never badge the focused session. Unknown events fail toward needs-you. ~1 s grace after `Stop` so chained turns don't flicker. Persist the last reason so the board survives relaunch. Hooks always exit 0 and are time-bounded. | M | A 8, §4; P 7; C 12 |
| LR-3 | **State is authoritative from `claude agents --json`**, hooks are the low-latency edges, correlated by `sessionId`. Keep a `ps` fallback keyed on the PTY child pid. | M | A 10; stack #5 |
| LR-4 | **Pre-hydrated digest per session, zero inference at open.** Goal (title ladder), "You asked" (last human turn, machinery stripped), next steps (latest todo list), files in flight, artifacts, attention reason. Captured at `Stop`/`Notification`, refreshed at `UserPromptSubmit`. Fallback is the last assistant block; never fabricate. | M | P 2; A 7; C LDI-24, 13 |
| LR-5 | **Agent self-narration**: MCP `sessions.note` / `sessions.next`, shown verbatim, stored Duo-side (`.duo/sessions.json`), surviving tab close. | M | P 3; A 21 |
| LR-6 | **Session title ladder**: custom-title → ai-title → compaction-summary intent → slash-command name → cleaned first prompt → short uuid. Strip harness wrapper tags. **Read titles; never write them** (no `/rename` injection). | M | P 4; A 5; C 10 |
| LR-7 | **Resume by default.** Starting a session in a project with history shows prior sessions first: 3 visible + "show all", message count and recency per row, dismissed on first message. | M | P 5 |
| LR-8 | **Never two writers.** Re-check liveness at click time. Duo-hosted and live → focus it. Live outside Duo → offer `--resume --fork-session` with a warning. Closed → `--resume <uuid>` in the session's recorded cwd (realpath first). | M | P 6; A 4; C LDI-25 |
| LR-9 | **Bounded transcript reads**: seek head/tail, per-file timeout, concurrency cap, never slurp. Sessions reach 270 MB; iCloud-evicted files stall. | M | A 6 |
| LR-10 | **Agent affordances gate on live agent presence** ("Send to session" only when a session can receive it), with a regression test: this regressed four times. | M | A 13; C LDI-22 |
| LR-11 | Empty-console placeholder for a focused project with no session: "No session in ‹project› · Start Claude here". | S | P 9 |
| LR-12 | **Scheduled sessions**: presets + cron with an English preview, app-open only, skip missed runs by default, land in background, app-minted `--session-id`. | L | P 10; A 20; C 30 |

### 2.2 Console (terminal)

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-13 | **Hiding or collapsing never kills or unmounts a terminal.** Keep the PTY and buffer; stop drawing. | M | P 29; C LDI-14 |
| LR-14 | **Never resize a PTY below 8 cols / 1 row**; guard at the PTY boundary. A transient 0×0 killed Claude and the shell (BUG-156). | M | A 3; C LDI-13 |
| LR-15 | **Never inject keystrokes into a running Claude session.** Seed with the positional prompt; paste strips the trailing newline and never auto-submits; drag-drop inserts a quoted path with a trailing space and no newline. | M | P 26–27; C LDI-15 |
| LR-16 | **Shift+Enter = newline; don't remap Return.** A Return remap was reverted, re-shipped and defaulted back. | M | C LDI-16, 11 |
| LR-17 | **Send selection to the focused session** as a quoted block with a provenance line (path · heading trail, or URL · title), no Enter, length-capped, with prompt-injection hardening (strip CR/LF/U+2028 from single-line fields; size code fences longer than any backtick run). | M | P 28; A 11 |
| LR-18 | Missing cwd at spawn falls back to the nearest surviving ancestor, with an in-stream notice. Membership follows the live shell cwd. | M | A 2; C LDI-17 |
| LR-19 | **Resolve the user's `claude` binary** without trusting the GUI `PATH` (well-known dirs, then login shell); clear "not installed" state; Settings override. | M | A 22 |
| LR-20 | Every spawned process carries `DUO_SESSION_ID=<uuid>` so hooks and tools self-identify. | M | A 1 |
| LR-21 | Console typography as a global setting (size, line height, padding, max width); never letter-spacing. | S | P 25; C LDI-16 |

### 2.3 Projects and organisation

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-22 | **Focus is a lens, not a switcher.** Focusing a project hides, never closes; "All" releases; opening something in another project switches focus; starred items stay visible. | M | P 11; C LDI-28 |
| LR-23 | **Stale references self-heal.** A vanished or moved folder yields a banner and a revert to a valid state, never a crash; per-pane error isolation. This is the base for the "project moved" flow. | M | P 14; C LDI-30, 20 |
| LR-24 | **Realpath before mapping a folder to Claude's storage**; resume is project-dir-scoped. | M | P 8; C LDI-18 |
| LR-25 | **Unified ⌘K / ⌘O**: empty shows recents + starred; typing fuzzy-finds projects, tasks, sessions, files; a pasted path or URL opens it; "Create new project" always present; recents self-heal. | M | P 15; C 34 |
| LR-26 | **Never mutate a folder you didn't create on open**; refuse to clobber existing marker files; prefer the enclosing project over nesting a new one. | M | C 35 |
| LR-27 | Hash-stable project colour from a palette that **excludes the attention accent**; colour never the only signal; collision-free initials. No manual override (removed in legacy). | S | P 12; C LDI-29 |
| LR-28 | Star projects and sessions; starred sort and restore first. | S | P 13 |
| LR-29 | Focused-project card shows its context files (`PROJECT.md`, `tasks/`, `CLAUDE.md`) in plain language, never raw `~/.claude` paths. | S | P 16 |

### 2.4 Files and editor

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-30 | **Byte-faithful saves**; never normalize untouched markdown; a save-path backstop refuses any serialize that loses table rows or collapses length. | M | P 17; C LDI-6 |
| LR-31 | **One reconciliation primitive for every file surface** (editor, HTML view, task index): conflict baseline = raw disk bytes last seen; echo-suppress own writes by hash registered *before* the write, consumed once, no timers. | M | P 18; C LDI-3, -5, -7 |
| LR-32 | **Reconciliation state machine** (ENH-195 §3.1): clean + small external change → silent reload + highlight; clean + destructive (>50%) → Keep mine / Load new / View diff; dirty + real divergence → conflict banner; dirty + cosmetic → ignore; rename/delete → recoverable affordance. Pause autosave while a decision is pending. | M | P 18; C LDI-4, -9, 3, 5 |
| LR-33 | **Just-added highlight** on agent-written ranges, until the user's next edit. | M | P 19; C 3 |
| LR-34 | **Agent writes to an open file go through the app** (MCP `doc.edit`, buffer-routed, cursor-preserving); `doc.status` answers "open? dirty?"; a fail-open `PreToolUse` hook *warns* on raw `Edit`/`Write` to an open file. | M | P 20; A 14; C LDI-8, 4 |
| LR-35 | **Atomic writes** (unique tmp + rename), per-store serialized write queue, defensive reads, versioned state with a pre-migration `.bak`, idempotent writers that are byte-equal when nothing changed. | M | A 15; C LDI-31, -39, 21 |
| LR-36 | **Watcher hygiene**: realpath before watch, watch the parent dir for rename-saves, ~250 ms debounce, walks off the main thread, stale-while-revalidate during agent write bursts. | M | A 17; C LDI-41 |
| LR-37 | **Frontmatter properties panel** (expanded by default; typed one-click edits with undo; body untouched by property edits). This *is* the task editor for `tasks/*.md`. Non-throwing YAML parse; CRLF-safe split/join; reserve the `duo.*` namespace. | M | P 22; A 25–26; C 7 |
| LR-38 | **File history**: content-addressed, off the save path, 90 s autosave coalescing, agent and restore snapshots never coalesced, restore through the normal write path. Protects `tasks/*.md` from agent mistakes too. | S | P 21; A 16; C LDI-10, 6 |
| LR-39 | Paste/drop images → saved beside the doc as a relative path, block-level; HEIC converted. | S | A 27; C 28 |
| LR-40 | Trash, never delete; inline rename; reveal in Finder. | M | P 23 |
| LR-41 | Files > 1 MB open read-only. | S | C LDI-41 |
| LR-42 | **CriticMarkup comments and suggest mode** (transaction-level, accept-all = new doc, reject-all = old doc exactly). | L | P 24; C LDI-11, -12, 8 |

### 2.5 Browser

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-43 | **Persistent logins across relaunch**; a cold-launched Google Doc renders without an SSO bounce. Private profile available. | M | P 30; A §5.4 |
| LR-44 | **Element inspector**: off → hover outline → click to freeze → explicit send; ESC exits; selection observer paused while inspecting. Payload: tag, selector path (legacy algorithm), heading trail, innerText (capped), allow-listed attributes, **plus** outerHTML, computed styles, rect and an element screenshot. Delivered as a quoted paste (no Enter) and via MCP `browser.get_selected_element`. | M | P 32; A 11, §5.3–5.4; C 24 |
| LR-45 | **Page driving tools**: navigate, back/forward, reload, click, fill, type, key, eval, wait-for-selector, read_page (innerText + **accessibility-tree fallback for canvas apps** like Docs, Sheets, Figma), screenshot, tab list/switch/open-or-focus/close. | M | A §5.4; P 31 |
| LR-46 | **Agent navigation never steals the user's tab or focus**; it focuses a matching tab or opens a new one. Agent-created artifacts are revealed only when asked. | M | C LDI-21 |
| LR-47 | Console and uncaught-error capture via user scripts, ring buffers with `since` cursors. | S | A §5.4 |
| LR-48 | Scripts are idempotent and re-injected on every navigation; state flags pushed to every tab. | M | A §5.4 (BUG-133/134) |
| LR-49 | Local HTML auto-reloads on change; zero tabs is valid; find-in-page; app shortcuts forwarded when the web view has focus. | M | A §5.4; C 24 |
| LR-50 | Opt-in external-hosts list (`host`, `*.suffix`, `{host, reason}`), checked on navigation **and** redirects, with a "sent to your browser" banner. | S | A 12; P 34; §1 D4 |
| LR-51 | Network request log (approximated via fetch/XHR patching). | L | A §5.4 |

### 2.6 Agent integration (MCP)

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-52 | **Every UI action has an agent tool; deliberate asymmetries are written down. The MCP tool list is the spec**; docs are generated from it. | M | P 35; C LDI-33 |
| LR-53 | **Orientation tools**: `app.status` (open docs + dirty flags, focused session, layout), `browser.state`, `doc.status`. | M | A 23; C 25 |
| LR-54 | **Transport survives the Claude Code sandbox** (loopback HTTP); one-line diagnostic when it doesn't. | M | P 36; §1 D6 |
| LR-55 | **Install nothing into `~/.claude`.** Hooks, MCP config and the "how to use Duo" prompt are passed per session. | M | §1 D8 |
| LR-56 | Short tool descriptions + one short skill on *when* to use them; contradictory or missing guidance is treated as a bug. | S | C LDI-34, 26 |
| LR-57 | Public or irreversible agent actions require explicit consent. | M | C (`duo pr create --yes`) |

### 2.7 Platform, persistence, keyboard, quality

| ID | Requirement | Pri | Sources |
|---|---|---|---|
| LR-58 | **Restore on relaunch**: sessions, open docs, browser tabs, layout; flushed on quit; versioned envelope with graceful downgrade. | M | P 37; C 29 |
| LR-59 | **Native menus, sheets and popovers** above web views; never DOM overlays a web view can occlude. | M | C LDI-20, 22 |
| LR-60 | **One shortcut registry**; terminal and web views forward. Avoid `⌘\` (1Password) and `⌘⌥L/;/'` (Raycast). `⌘W` closes a tab, never the window; `⌘R` never reloads the app; `⌘Z` goes to text undo inside text. **Lock the chord map in the spec once.** | M | C LDI-19, 23; P Q14 |
| LR-61 | **Distribution**: notarized direct download, Sparkle updates, a **launch validator in the release cut** (a DMG that crashed on launch passed signing and notarization), single version source, no telemetry. | M | P 38; C LDI-37, 31 |
| LR-62 | **Assume enterprise Macs**: no admin, no Homebrew, sandboxed sessions, locked settings. Fail open; detect → validate → guide. | M | C LDI-36 |
| LR-63 | Both themes first-class; contrast checked in both; attention never colour-only; roles on tab strips. | M | C LDI-42, 32 |
| LR-64 | Visibility-gated polling; expensive reads lazy for the visible top-N. | M | C LDI-41, 33 |
| LR-65 | **Verify the artifact on disk before fixing a reported symptom** (process rule for the build). | M | C LDI-35 |
| LR-66 | One-time import of legacy `~/.claude/duo/{projects, nav-pins, cron-jobs, home-state, external-domains}.json` on first launch. | S | A Q6 |

---

## 3. Deliberately not carried forward

| Drop | Why | Sources |
|---|---|---|
| Typing `claude` into zsh and inferring the session (freshest transcript in cwd, `ps` polling, `lsof` joins) | v2 mints `--session-id` and reads `agents --json`; the whole layer and its documented races disappear. | A |
| `duo` CLI over Unix socket/TCP (~110–150 verbs), PATH shim, priming file, SessionStart hook, managed `CLAUDE.md` block, global `settings.json` merge, Haiku subagent | Replaced by in-app MCP + per-session flags. Keep only "the tool list is the spec". | A, P, C |
| TipTap/ProseMirror + `tiptap-markdown`, the six-times-grown echo-normalization regex, separate JSON editor | Not byte-faithful by construction; v2 edits text (CM6). | A, P, C |
| HTML canvas, playgrounds, lesson/distro packs, fork config, pack builder, `.duo.json` sidecars, `data-duo-id` | Authoring and cohort infrastructure outside v2's scope; HTML is view-only. | A, P, C |
| Vault / OKF / Obsidian serializers / Bases engine / rollups as a feature | A second product. Keep the *patterns*: typed frontmatter edits, views derived from frontmatter. | P, C |
| Workspaces-as-file and the workspace switcher | Defeatured once projects existed. | P, C |
| Git for PMs: worktrees UI, clone, pull, propose-changes PR, repo chips | Code-shaped; brief §1. Keep the "folder vanished" recovery pattern and fail-closed probes. | P, C |
| Auto-`/rename`, session banners, Duo-generated titles, Return remapping | Reverted in legacy; Claude already does it. | C |
| Manual project colour overrides; per-tab cozy mode; FAQ as landing page; `~/.claude` settings pane in the navigator | Removed or superseded in legacy. | C, P |
| Atelier visual system | Brief §7 asks for a fresh system. | P |
| Multi-window in v1 | Expensive; design window-aware, ship one. | P, C |
| Electron artefacts (WCV occlusion mutes, key-forwarding allow-lists, EPIPE guards, fsevents teardown order) | Platform-specific. | A, C |

---

## 4. Open questions for Geoff

Deduplicated and ordered by how much they change the spec.

1. **Reverse ENH-183 D9?** Confirm the split in §1 D3: Claude-derived facts in a rebuildable index, Duo-owned facts (task links, notes, stars) in `.duo/sessions.json`.
2. **Name of the attention surface** now that Home is a folder (§1 D1). Inbox? Board?
3. **Browser default** (§1 D4): in-app for everything with an opt-in external list? Will v2 run on a managed corporate laptop?
4. **Unregistered folders** (§1 D5): show folders with Claude history but no `PROJECT.md` as adoptable, and their sessions as Unfiled?
5. **"Claude's additions marked"** (§1 D9): ephemeral highlight in v1, history diff should, CriticMarkup later?
6. **Task model depth.** You daily-drove typed vault entities (initiative, milestone, person) and rollups. Should `tasks/*.md` link to people and milestones, be OKF-compatible so a vault can wrap a project later, and should a cross-project task view group by waiting-on or milestone? [P Q12; A Q1; C 36]
7. **Google Docs**: is "the agent reads the Doc I have open" (accessibility-tree read) v1 must, should or later? It sets spike 7's scope. [P Q4]
8. **Plain shell tabs** (no Claude) in v1? [A Q2]
9. **Scheduled sessions**: v1, or does the Home agent cover "every morning"? In-app timer or `launchd`? [P Q7; A Q3; C Q8]
10. **Import legacy state** on first launch (projects, pins, cron jobs, external domains)? [A Q6]
11. **Doc beside doc** (legacy Split View): is a single right-pane document enough for v1? [P Q9]
12. **Licence**: legacy README says MIT, PRIVACY.md says GPL-3.0. Which for v2? [P Q10]

---

## 5. Proposed edits to existing v2 docs (pending your answers)

- **Brief §3.3 / §6 / prompts**: three attention columns with reason chips; "Done/Ready for review" = deliverable produced; rename the attention surface (Q2). *Note: if Claude Design is already working from the brief, these can go in as canvas feedback instead of a re-brief.*
- **Stack rec**: add LR-55 ("install nothing into `~/.claude`") as a principle; add sandbox loopback to spike 8; add long-path encoding to spike 10; add "resolve the `claude` binary" (LR-19) and "never resize below 8×1" (LR-14) to spike 1 acceptance; make the reconciliation primitive (LR-31/32) an explicit `DuoCore` service.
- **New: chord map** (LR-60) as a short spec section before the design component sheet.
