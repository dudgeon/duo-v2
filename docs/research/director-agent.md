# A director agent without Claude Code Projects

*Research date: 2026-10-05. Claude Code installed here: **2.1.289** (`latest` on npm, published 2026-10-03; `stable` is 2.1.285). Versions come from the Claude Code CHANGELOG, npm publish dates, and, where the changelog is silent, bisected npm tarballs. Items marked **[inferred]** are my reading and not stated in a source. Items marked **[unverified]** come from one secondary source or a user report.*

**Question.** Claude Code **Projects** (public beta, 2026-09-17) puts one coordinator agent in charge of many worker sessions. The user talks to one place, and the coordinator splits the work, starts threads, tracks them, reviews what comes back and lands it. Can the same outcome be built from ordinary Claude Code primitives by someone who doesn't have Projects? What does it take on an old Claude Code, a recent one, and the latest one? And should Duo ship it as a feature of its projects?

**Short answer.** Yes, and the latest CLI has nearly every piece Projects is built from:
- background sessions that isolate themselves in worktrees (`claude --bg`);
- machine-readable state (`claude agents --json`);
- session-to-session messaging that wakes an idle session (`SendMessage`, with `notify_when_idle`);
- hooks, Monitor, `/loop` and `/code-review`.

What you can't replicate locally is the cloud: threads that keep working with the laptop shut, and PR auto-fix that runs on Anthropic's servers. What you can do better is enforce things Projects only asks the model to respect: a hard cap on threads, no merging without you, a ledger on disk that survives the coordinator being replaced. On older versions the same design still works if every worker runs as a turn-based headless job and all messages go through files.

A correction to the premise: sessions messaging each other shipped in **v2.1.224 on 2026-08-07**, about two months ago. Projects launched about a month after that.

---

## 0. TL;DR

| | Scenario A: outdated | Scenario B: recent, not latest | Scenario C: latest, no Projects |
|---|---|---|---|
| Versions | **1.0.53 → 2.1.48** (Jul 2025 → Feb 2026) | **2.1.139 → 2.1.223** (May → Aug 2026); notes for 2.1.49–2.1.138 | **2.1.224+**, ideally **≥ 2.1.285** (Aug 2026 →) |
| Workers are | Headless `claude -p` jobs, one turn per run, resumed by `--session-id` | Background sessions (`claude --bg`) you can see and attach to, in auto-made worktrees | The same, plus they can be messaged while running or idle |
| Isolation | `git worktree add` by hand (the director runs it) | Automatic worktree per `--bg` session; `-w`; `isolation: worktree` | Same |
| Director → worker | `claude -p --resume <id> "<msg>"` on the next turn | Same, or a Stop hook that injects `.director/inbox/<id>.md` when the worker's turn ends | **`SendMessage`** (starts a turn in an idle session); `claude --resume <id> "<msg>"` into a running background session (2.1.285) |
| Worker → director | The job's JSON result, plus a Stop hook writing a report file | Stop hook (with `last_assistant_message`, 2.1.47+) → report file → **Monitor** wakes the director | Worker **`SendMessage`s its report**; director subscribes with **`notify_when_idle`**; Stop-hook report as a backstop |
| Seeing state | The director's own ledger plus process liveness | **`claude agents --json`** (working/blocked/done, `waitingFor`) | Same, plus `ListAgents` |
| Review and merge | Director diffs, runs tests and a reviewer subagent, merges with git | Same, plus `/code-review` (2.1.147) and `claude ultrareview` | Same, plus PR watching with Monitor over `gh pr checks` |
| Fit | Works, but clunky; no live view of workers | Good; messaging is the weak spot | Closest to Projects; local-only |

**What to build in every scenario:**
1. A **director** session with a written job description.
2. A **ledger on disk** (one file per thread: the verbatim brief, branch, worktree, session id, state, report).
3. **One worktree and branch per worker.**
4. **Report-back** only: the director reads reports, not transcripts, unless it is asked.
5. A **review gate** that the director runs: tests plus a review pass.
6. **Merges only with your go-ahead**, enforced by a hook, not by a promise.

For Duo: most of the director's substrate already exists (sessions with states, `duo2 session new --prompt`, `duo2 session show`, tasks that link sessions). Sessions Duo starts already have Claude Code messaging inboxes (F-79). The gaps are worktrees on new sessions, a per-session permission mode and model, and a review-and-land surface. See §9.

---

## 1. What Claude Code Projects is

### 1.1 Name, date, availability
- **Name.** "Projects" (sidebar entry, "New project" button). Workers are **threads**; the director is the **coordinator**, also called "the project conversation". Docs title: *"Let Claude coordinate ongoing work with Projects"* ([docs/claude-projects](https://code.claude.com/docs/en/claude-projects)). Launch blog: *"Projects redesigned: from folder to conversation"* ([claude.com/blog/projects-redesigned](https://claude.com/blog/projects-redesigned)).
- **Date.** 2026-09-17 (blog dateline; [Unite.ai](https://www.unite.ai/anthropic-redesigns-claude-code-projects-to-coordinate-agent-threads/)). It has no CLI CHANGELOG line and no support release-note entry.
- **Availability.** *"Projects are in public beta on Pro and Max plans and rolling out gradually, starting with accounts that have used cloud sessions and don't have existing projects in claude.ai chat or Cowork. They aren't available on Team or Enterprise plans yet."* There is a waitlist at claude.com/form/projects, and *"no organization-level controls for projects during the beta."*
- **Surfaces.** claude.ai/code, the desktop app's Code tab, and the mobile apps (steer only). *"…not in the terminal CLI, the VS Code extension, or the JetBrains plugin, and not through Amazon Bedrock, Google Cloud's Agent Platform, or Microsoft Foundry."*
- **Version.** There is no minimum for cloud use. A thread **on your own computer** needs **v2.1.280+** on that machine, through Remote Control.

### 1.2 How it works
- **Coordinator.** *"one long-running session where Claude acts as coordinator. It takes what you send, decides what becomes a thread, and keeps track of every thread it started. It sees what threads report back, not every step they take."* The blog says to *"Brief Claude in the project the way you'd brief a chief of staff."*
- **Routing.** A quick question is answered inline. *"New work goes to a new thread or to a thread already working in that area… Several unrelated tasks in one message become separate threads."* Sometimes Claude shows **Suggested threads** to approve instead of starting them.
- **Threads.** *"Each is a separate session with its own context window that does one piece of work and reports back."*
  - They are usually **cloud sessions**, each on *"its own branch and copy of the repo."*
  - **Local threads** run through Remote Control (`claude remote-control` in the folder, or the desktop app's setting). `--spawn worktree` gives each local thread its own worktree.
  - Threads can use subagents, `/loop` and workflows inside themselves.
- **Context.** *"You don't manage context windows in a project. Threads compact automatically, and the conversation works from recent messages, recent threads, and project memory rather than its full history."* The coordinator can read any thread on request.
- **Standing context.**
  - **Project memory**: files plus a `MEMORY.md` index that every cloud thread reads at start.
  - **Project instructions**: up to 16,000 characters, sent to every thread and to the coordinator.
  - Both are separate from the repo's `CLAUDE.md`.
- **Review and landing.**
  - A thread branches from the default branch and opens a PR when asked, or on its own for a concrete fix.
  - It then **watches the PR with auto-fix**: it pushes fixes when CI fails, answers review comments, and posts when checks pass.
  - Cards carry buttons: *Resolve conflicts, Fix CI, Address comments, Merge it, Review PR, Create PR*.
  - Overlapping threads conflict *"just like any other PR"*, and Claude says which PRs to merge first.
- **Overview.**
  - The Threads tab groups threads as *Ready for review / Waiting on you / Working / Landing / Idle / Resolved*. A thread auto-resolves after a week with no activity.
  - Other tabs: *Library* (input and output files), *Pull requests*, *Routines*.
  - Desktop notifications fire on coordinator posts, thread errors and needs-input.
- **Permissions.**
  - Threads run in **auto mode**. Approvals happen inside the thread: *"Telling Claude in the project conversation to go ahead doesn't reach it."*
  - Repo permission rules and hooks reach a thread **only in a single-repo project**.
- **Limits and cost.**
  - Opus everywhere by default (high effort for threads, low for the coordinator).
  - Usage comes from your plan and *"uses them faster"*.
  - **200 new threads a day** is the only enforced limit. A thread cap you state is *"instructions Claude keeps to, not enforced settings… isn't a hard cap."*
- **Scheduling.** Asking for scheduled work creates a **routine** that runs as threads in the project.
- **Not documented.** How the coordinator and threads talk to each other. **[inferred]** The `claude-code-remote` MCP tools visible in cloud and Remote Control sessions (`create_session`, `send_message`, `list_events`, `subscribe_pr_activity`, `send_later`, `create_trigger`) mention "a project's ambient session". That suggests Projects runs on the same session APIs.

### 1.3 Its components
1. Coordinator conversation (its own model and effort)
2. Threads (cloud, or local through Remote Control), one branch or PR each
3. Overview (Threads, Library, Pull requests, Routines)
4. Thread cards with actions
5. Suggested threads and setup recommendations
6. Project memory
7. Project instructions
8. Repos, files and the environment
9. Per-project plugins
10. PR watching with auto-fix
11. Local threads, optionally one worktree each
12. Project routines
13. Notifications
14. Settings: Usage tab, Pause, Archive, Delete, Restart Claude
15. Promoting a session: "Continue as project", "Move to project"

### 1.4 Stated benefits
*"Send work to one place"*, *"Set context once"*, *"Walk away and come back to finished work."* The use cases are one goal spanning several repos, an area you keep feeding, a build or migration bigger than one session, and non-code work (files in, write-ups out).

### 1.5 Known problems (lessons for a home-built director)
GitHub issues on anthropics/claude-code; these are user reports **[unverified]**:
- **#97924.** *"Thread sessions merged 2 PRs while CI was red… The coordinator only relays messages. It does not supervise or verify thread output… Requirements were lost when the coordinator summarized them into thread briefs."* → **Give workers the brief verbatim and keep it on file; have the director verify the work itself; gate merges mechanically.**
- **#99610.** A coordinator that is replaced (by an upgrade or an age limit) loses CLAUDE.md, skills, hooks and self-attached repos. → **Keep the director's state on disk so a fresh director can pick it up.**
- **#96115.** No cross-project "Waiting on you" inbox and no API to list threads. → Duo's needs-you lane already covers this.
- **#97464, #97565.** Local threads don't get project memory, and it's unclear what local threads load.
- **#99274, #99090.** Repo permission rules are ignored; there is no per-thread permission mode.
- **#99307.** Users want local-first projects without GitHub.
- **Usage.** The New Stack: *"could drain your plan before lunch"*.

---

## 2. The primitives, with the version that added each

npm publish dates. Unless noted, each entry is not experimental.

| Primitive | First version (date) | Notes |
|---|---|---|
| `-p` print mode | ≤ 0.2.9 (Feb 2025) | |
| `--continue` / `--resume` | 0.2.93 (2025-04-30) | `-p --resume <name>` 2.1.101. **`--resume <id> "prompt"` sends to a running background session: 2.1.285** |
| `--output-format stream-json` | 0.2.66 (2025-04-09) | `--input-format stream-json` 1.0.18 |
| `--session-id <uuid>` | **1.0.53** (2025-07-15), tarball bisect | Lets the director pick each worker's id up front (DL-14) |
| `--fork-session` | 1.0.119 (2025-09-18), tarball bisect | |
| SDK (TS/Python) | 1.0.23 (2025-06-13); renamed Agent SDK at 2.0.0 (2025-09-29) | Sessions 1.0.77 |
| Hooks | **1.0.38** (2025-06-30): PreToolUse, PostToolUse, Notification, Stop | SubagentStop 1.0.41, UserPromptSubmit 1.0.54, SessionStart 1.0.62, SessionEnd 1.0.85, PermissionRequest 2.0.45, **`last_assistant_message` in Stop 2.1.47**, WorktreeCreate/Remove 2.1.50, TeammateIdle/TaskCompleted 2.1.33, TaskCreated 2.1.84, Stop gets `background_tasks` 2.1.145 |
| Custom agents (`.claude/agents`) | 1.0.60 (2025-07-24) | `--agents` JSON 2.0.0; `--agent` flag |
| Background bash | 1.0.71 (2025-08-07) | |
| Skills | 2.0.20 (2025-10-16) | Merged with commands 2.1.3 |
| Background subagents | 2.0.60 (2025-12-05) | `background: true` 2.1.49 |
| Shared task list (TaskCreate…) | 2.1.16 (Jan 2026) | |
| **Agent teams** | **2.1.32** (2026-02-05) | **Experimental**, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; still off by default. One implicit team since 2.1.178 |
| **`--worktree` / `-w`** | **2.1.49** (2026-02-19) | `isolation: worktree` (Agent param 2.1.49, frontmatter 2.1.50); `worktree.baseRef` 2.1.133 |
| EnterWorktree / ExitWorktree | 2.1.40 bundle (unannounced) / 2.1.72 | `path` param 2.1.105 |
| Remote Control | 2.1.51 (2026-02-23) | Gradual rollout. Local Projects threads need 2.1.280 |
| `/loop` and cron tools | **2.1.71** (2026-03-06) | Session-only, 7-day expiry. Self-paced `/loop` and ScheduleWakeup always on since 2.1.248 |
| Channels (`--channels`) | 2.1.80 (2026-03-19) | Research preview |
| **Monitor tool** | **2.1.98** (2026-04-09) | |
| Push notifications | 2.1.110 (2026-04-15) | Needs Remote Control |
| `/ultrareview` | 2.1.111 (2026-04-16) | `claude ultrareview` 2.1.120 |
| Routines (cloud) | 2026-04-14 | Research preview |
| **Agent view / background sessions** (`claude --bg`, `claude agents [--json]`, `attach`, `logs`, `stop`, `rm`) | **2.1.139** (2026-05-11) | **Research preview.** A `--bg` session moves itself into a worktree before its first edit (`worktree.bgIsolation`) |
| `/code-review` | 2.1.147 (2026-05-21) | Was `/simplify`; `/review` alias 2.1.223 |
| Workflow tool (dynamic workflows) | 2.1.154 (2026-05-28) | Trigger keyword `ultracode` 2.1.160 |
| **Cross-session `SendMessage` + `ListAgents`** | **2.1.224** (2026-08-07), macOS/Linux | On by default. Windows 2.1.234 (docs) or 2.1.239 (changelog). Remote Control sessions on other machines 2.1.225. `@`-mention 2.1.232. **`notify_when_idle` 2.1.236**. Bedrock/Vertex/Foundry 2.1.248. Changelog fix lines at 2.1.162 and 2.1.166 show an earlier, gated form |
| Projects | Not a CLI feature | Web, desktop and mobile only |

How cross-session messaging behaves ([docs](https://code.claude.com/docs/en/cross-session-messaging)), which shapes the design:
- **Delivery.** *"The receiving Claude reads the message between tool calls during an active turn… When the receiving session is idle, Claude Code starts a new turn with the message."*
- **Text only.** It is plain text, it *"can't approve anything"*, and slash commands in it don't run.
- **Held messages.** A message is held when exactly one of the two sessions bypasses permissions. In `-p` sessions a held message expires after 5 minutes. `crossSessionInbound` is `accept`, `hold` or `refuse`.
- **Scripts can post.** A script can post to a session's socket (`CLAUDE_CODE_MESSAGING_SOCKET`, with an optional auth line carrying `CLAUDE_CODE_MESSAGING_TOKEN` on macOS).
- **Beacons.** Each live session's beacon (`~/.claude/sessions/<pid>.json`) carries `version`, `messagingSocketPath` and `peerFeatures` (e.g. `notify_idle`). These make a usable capability check.

---

## 3. The design all three scenarios share

Projects' benefits come from six mechanisms. Each one has a primitive equivalent, and the scenarios differ only in which primitive carries it.

**3.1 One director, one place to talk.** The director is a long-lived session in the project root with a written role:
- `.claude/agents/director.md` (run as `claude --agent director`), or a `director` skill, or `--append-system-prompt`.
- Its job: turn requests into briefs; propose or start threads; track them; read reports; verify; land; keep you posted only when something finishes or is blocked.
- It does not write product code itself; it's allowed `Bash(git *)`, `Bash(claude *)`, test commands, `Read`, and the ledger.

**3.2 A ledger on disk, not in the director's head.** This answers Projects' #97924 and #99610 problems, and it is legible, which is Duo's whole stance.
```
.director/
  INSTRUCTIONS.md      # ≈ project instructions (≤ 16k chars); prepended to every brief
  MEMORY.md            # ≈ project memory index; workers may append learnings via the director
  threads/
    T-007-retry-backoff.md   # frontmatter: id, session_id, branch, worktree, state, created, pr
                             # body: the brief VERBATIM, acceptance checks, then reports appended
  inbox/<session_id>.md     # messages waiting for a worker (older scenarios)
  reports/<session_id>.md   # last report from each worker (written by a Stop hook)
  log.md                    # routing decisions, one line each
```
A fresh director, after compaction, replacement or a restart the next day, rebuilds its picture from `threads/*.md`. This is how Projects' *"works from recent messages, recent threads, and project memory"* is done here, but on disk and auditable.

**3.3 One worker per thread, isolated.** Each thread is a full Claude Code session on its own branch in its own worktree (`.claude/worktrees/<slug>`).
- Its id is minted up front with `--session-id`, so the ledger knows it before the process starts (DL-14 already does this).
- The brief carries the verbatim request, the acceptance checks, the files likely touched, and "report back by …".

**3.4 Report back, don't stream.** Workers end each piece of work with a structured report: *what changed, how it was checked, open questions, ready to land?* The director reads reports. It opens a worker's transcript only when asked, or when a report doesn't add up.

**3.5 A review gate the director runs itself.** This fixes "the coordinator only relays". Before a thread counts as *Ready for review*, the director:
1. Runs the tests in the worker's worktree.
2. Runs a review pass: a reviewer subagent on the diff (any version), or `/code-review high` in the worktree (2.1.147+).
3. Checks the diff against the brief's acceptance checks.

Failures go back to the worker as a message. Only a thread that passes is surfaced to you.

**3.6 Landing with consent, enforced.**
- The director proposes an order ("T-007 then T-009; T-009 conflicts in `retry.ts`").
- Once you agree, it merges each branch into an integration branch, re-runs the tests, and fast-forwards. Or it opens PRs and watches checks.
- A **PreToolUse hook in workers** denies `git push --force`, `git merge` into the default branch, and `gh pr merge`. A hook in the director asks before they run. This turns Projects' "instructions, not settings" into a real rule.
- Cleanup: `git worktree remove` or `claude rm <id>`.

**Also worth keeping from Projects:**
- **Suggested threads**: "propose and wait" is the default; you can let the director run without asking.
- **A hard concurrency cap**: the dispatch script counts running workers. Projects only asks the model to keep to a cap.
- **Auto-resolve after a week idle.**
- **Attention groups**: Waiting on you / Ready for review / Working / Landing / Idle / Resolved.
- **A cheaper model for routine workers, Opus for the director's reviews.** Projects defaults to Opus everywhere and users complain about drain.

---

## 4. Projects features mapped to primitives, per scenario

| Projects feature | A: outdated (1.0.53–2.1.48) | B: recent (2.1.139–2.1.223) | C: latest without Projects (2.1.224+) |
|---|---|---|---|
| Coordinator conversation | Interactive session + `.claude/agents/director.md` (1.0.60+) or a CLAUDE.md role | Same; can be pinned in agent view (`Ctrl+T`) | Same |
| Start a thread | `git worktree add .claude/worktrees/<s> -b t/<s>` then `claude -p --session-id <uuid> "<brief>" --output-format json` in background bash (1.0.71+) | `claude --bg --name t-<s> "<brief>"` (auto worktree), or `claude -w <s>` | Same as B |
| Thread runs unattended | `--permission-mode acceptEdits` + `--allowedTools`, or `--dangerously-skip-permissions` in a sandbox | Same, or `auto` mode where available | Same |
| See every thread's state | Ledger + `ps`; no live view | **`claude agents --json`** (`state`, `status`, `waitingFor`) | Same, plus `ListAgents` |
| Thread reports back | `-p` JSON result + Stop hook → `reports/<id>.md` (parse `transcript_path` before 2.1.47) | Stop hook with `last_assistant_message` → report file; **Monitor** on `reports/` wakes the director | Worker **`SendMessage`s "REPORT: …" to the director**; director uses **`notify_when_idle`**; the Stop hook stays as a backstop |
| Follow-up to a thread | Next turn: `claude -p --resume <id> "<msg>"` | Same for `-p` workers. For `--bg` workers: Stop hook returns `{"decision":"block","reason":<inbox>}` at turn end; idle workers need a resume | **`SendMessage` to `t-<s>`** (an idle worker starts a turn), or `claude --resume <id> "<msg>"` (2.1.285+) |
| Approvals inside a thread | Nobody can answer a `-p` prompt; set permissions up front | Shows as *Needs input* in agent view; you peek and reply or attach | Same; messages from the director *can't* approve, by design |
| Review | Reviewer subagent + tests | + `/code-review` (2.1.147), `claude ultrareview` | Same |
| PR + CI watching | `gh pr checks` in a background-bash loop | **Monitor** over `gh pr checks` / `gh api` | Same; or a cloud session with `subscribe_pr_activity` [inferred] |
| Overview groups | `ledger.md` table the director rewrites | From `claude agents --json` + ledger | Same |
| Notifications | `Notification` hook → `osascript` / `terminal-notifier` | + **PushNotification** (2.1.110, via Remote Control) | Same |
| Project memory / instructions | `.director/MEMORY.md` + `INSTRUCTIONS.md` prepended to briefs | Same | Same |
| Scheduled work | launchd / cron running `claude -p` | `/loop`, CronCreate (2.1.71, session-only), Routines (cloud) | Same; self-paced `/loop` always on (2.1.248) |
| Fan-out inside one thread | Subagents | + background subagents, `isolation: worktree`, **Workflow** (2.1.154) | Same |
| Work while the laptop is closed | ✗ | Cloud sessions / Routines only | `claude --cloud "<desc>"`, messaged across machines (2.1.225+) |
| Mobile steering | ✗ | Remote Control (2.1.51+) | Same + cross-machine `SendMessage` |
| Hard thread cap | Dispatch script | Dispatch script counting `claude agents --json` | Same |
| Merge guardrail | PreToolUse hook (1.0.38+) | Same | Same |

---

## 5. Scenario A: an outdated Claude Code (1.0.53 → 2.1.48)

**What's there:**
- `-p`, `--resume`, `--session-id` (1.0.53), stream-json
- hooks (1.0.38+), custom agents (1.0.60)
- background bash (1.0.71), skills (2.0.20)
- background subagents (2.0.60)
- agent teams, experimental (2.1.32+)

**What's missing:**
- `--worktree`
- agent view and `--bg`
- Monitor
- cron and `/loop`
- any way to message a running session

Below 1.0.53 the director can't choose worker ids; it has to scrape them from `-p` JSON output, which works but is brittle.

**Recommendation: turn-based headless workers, with files as the mailbox.**
1. **Director** is an interactive session with `director.md` as its agent, allowed `Bash(git worktree *)`, `Bash(claude -p *)` and test commands.
2. **Start a thread:**
   ```sh
   git worktree add .claude/worktrees/$S -b t/$S
   cd .claude/worktrees/$S && claude -p --session-id $UUID \
     --permission-mode acceptEdits --allowedTools "Edit Write Bash(npm test*)" \
     --output-format json "$(cat ../../../.director/INSTRUCTIONS.md .director/threads/$T.md)" \
     > ../../../.director/reports/$UUID.json
   ```
   The director runs this as **background bash** and records it in the ledger.
3. **Report back:** the `-p` result JSON is the report. A **Stop hook** in the workers' settings also writes the last message to `reports/` (before 2.1.47, read the tail of `transcript_path`).
4. **Follow-ups:** `claude -p --resume $UUID "…"` starts the worker's next turn, with its full context.
5. **Watching:** the director checks its background shells (BashOutput) when you talk to it, or on request. There's nothing to wake it on its own; that is the main loss.
6. **Review and merge:** as in §3.5–3.6, with a reviewer subagent. PreToolUse hooks guard merges.
7. **Your view:** the director keeps `.director/ledger.md` current. A `Notification` hook pops a macOS notification when a worker stops.

**Alternatives in this range:**
- **Agent teams** (2.1.32+, experimental). Lead = director, teammates = workers, with a shared task list, mailboxes, and TeammateIdle/TaskCompleted hooks. It fits one **big task today**, not an ongoing project: the team ends with the lead's session, teammates can't be resumed, they share a checkout (no worktrees), and it's flagged token-heavy.
- **An Agent SDK program as the director** (1.0.23+, renamed 2.0.0). Deterministic code dispatches workers and the model only writes briefs and reviews. This is more robust but is no longer "talk to one agent".

**Benefits you keep:** one place to talk, isolation, verbatim briefs, review gate, guarded merges, a ledger.

**Benefits you lose:** live visibility of workers, mid-turn steering, being woken when work finishes.

---

## 6. Scenario B: a recent Claude Code that isn't the latest (2.1.139 → 2.1.223)

**What's there:**
- everything in A
- `-w` and `isolation: worktree` (2.1.49), WorktreeCreate hooks
- Remote Control (2.1.51), `/loop` and cron (2.1.71)
- **Monitor** (2.1.98), push notifications (2.1.110)
- **agent view with `claude --bg`, auto-worktree, `claude agents --json`** (2.1.139)
- `/code-review` (2.1.147), Workflow (2.1.154)

**What's missing:** session-to-session messaging (2.1.224), `notify_when_idle` (2.1.236), and `--resume <id> "prompt"` into a running background session (2.1.285).

**Recommendation: background sessions as workers; hooks, files and Monitor as the nervous system.**
1. **Start a thread:** `claude --bg --name t-$S --permission-mode acceptEdits "<brief>"` from the repo root. The session moves into its own worktree before its first edit. Workers are real, visible sessions: you see them in `claude agents` (and in Duo), peek, reply or attach.
2. **State:** the director runs **Monitor** on a small loop over `claude agents --json`. It emits one line when any worker changes state (`blocked` with `waitingFor`, `done`, `failed`). That is the *Waiting on you / Working / Done* feed.
3. **Report back:** a Stop hook with `last_assistant_message` writes `reports/<id>.md`. The Monitor event wakes the director to read it, verify, and update the ledger.
4. **Follow-ups without messaging:**
   - **At turn end:** the worker's Stop hook checks `.director/inbox/<id>.md`. If it has content, the hook returns `{"decision":"block","reason":"<message>"}`; Claude reads that and keeps working. Delivery is reliable, but only when the worker is about to stop.
   - **Idle workers:** `claude stop <id>`, then `claude -p --resume <id> "<msg>"` (or re-attach). Clunky; it is the gap 2.1.224 fills.
   - **Or skip the problem:** run workers as `-p` turns, as in Scenario A, and use `--bg` only for threads you expect to steer yourself.
5. **Review:** run `/code-review` in the worktree (or `claude -p "/code-review high"` there) plus tests. Use `claude ultrareview` for big landings.
6. **Landing:** Monitor over `gh pr checks` for PR flows; local merges as in §3.6.
7. **Notifications:** PushNotification through Remote Control, or a Notification hook.
8. **Heartbeat:** `/loop` (self-paced from 2.1.248; fixed interval before that) to have the director sweep the ledger, resolve threads idle for a week, and post a short status.

**For 2.1.49–2.1.138**, which has worktrees but no agent view: use Scenario A's `-p` workers, but in `-w` worktrees, with Monitor (2.1.98+) watching `reports/`.

**Agent teams and Workflow** are both good *inside* a thread: a worker can fan out a big refactor across teammates or a workflow. Neither replaces the long-lived director, because both end with their task.

---

## 7. Scenario C: the latest Claude Code, without Projects (2.1.224+, best ≥ 2.1.285)

**Who is in this scenario:**
- terminal-only users (Projects isn't in the CLI)
- Team and Enterprise plans
- Bedrock, Vertex and Foundry users
- people not yet in the rollout
- repos not on github.com
- anyone who wants threads on their own machine with their own hooks and settings

That last group is several of Projects' open issues.

**Recommendation: a messaging-native director.** This is the closest match to Projects.
1. **Director:** `claude --agent director --name director` in the repo root. Pin it if it lives in agent view; or it can be a Duo session.
2. **Start a thread:** `claude --bg --name t-$S "<INSTRUCTIONS + brief + 'When done or blocked, SendMessage the director: REPORT … / BLOCKED …'>"`. The worker gets its own worktree automatically. Keep workers and the director in non-bypass permission modes so messages flow without being held.
3. **Report back:**
   - The worker `SendMessage`s a report to `director`. It arrives as a new turn if the director is idle.
   - The director also subscribes with **`notify_when_idle`**, which costs the worker nothing. A worker that stops without reporting is still noticed.
   - The Stop-hook report file stays as the record.
4. **Follow-ups:** `SendMessage` to `t-<s>`. If the worker is idle, a new turn starts; if it is busy, the message is read between tool calls. From a shell or script, `claude --resume <id> "<msg>"` (2.1.285+) does the same for background sessions.
5. **Approvals** stay with you, in agent view, Duo or the session. The director cannot approve, and must not ask a worker to do something your own permissions would block (cross-session permission laundering).
6. **State and attention:** `claude agents --json` plus `ListAgents`. The director rewrites the ledger's Overview table, and PushNotification pings your phone for *Waiting on you* and *Ready for review*.
7. **Review and land:** as in §3.5–3.6. For PR flows, Monitor over `gh pr checks`.
8. **Laptop-closed work (optional):** `claude --cloud "<desc>"` starts a cloud session. It can be messaged across machines (2.1.225+) or, from a cloud or Remote Control session, driven with the `claude-code-remote` tools (`create_session`, `send_message`, `subscribe_pr_activity`). This is the nearest thing to Projects' cloud threads **[inferred; tool availability depends on surface]**.
9. **Scheduling:** project routines become Routines (cloud) or the director's own `/loop`. CronCreate jobs die with the session and after 7 days.

**Packaging, so a user doesn't wire this by hand:** a plugin carrying
- `agents/director.md`,
- a `director` skill (start, status, land, resolve),
- the worker hooks (Stop → report, inbox; PreToolUse merge guard),
- a `bin/director-dispatch` script that enforces the cap and writes the ledger.

That gives a CLI user one command for something close to Projects.

---

## 8. What can't be replicated, and what can be done better

**Can't replicate (or only partly):**
- Cloud threads that run with your machine off and resume their sandbox. You can borrow them through `--cloud`, but the local design stops when the Mac sleeps; background sessions resume on wake.
- Server-side PR auto-fix that wakes a sleeping thread on CI failure. Locally, a Monitor in an awake session has to do it.
- Projects' UI: the Overview, cards with buttons, the Library tab, mobile. This is where Duo comes in.
- The Usage tab's per-thread token accounting. `-p` JSON reports cost per turn; interactive sessions don't, cheaply.

**Can do better:**
- **Enforced** caps and merge rules (hooks and a dispatch script, not memory notes).
- **Verbatim briefs** and a director that **verifies**, not relays (#97924).
- State **on disk** that survives the director being replaced (#99610).
- Local threads get **your** CLAUDE.md, hooks, skills, permission rules and memory (#97464, #97565, #99274).
- Not GitHub-only (#99307): merging is plain git.
- Per-thread model and permission mode (#99090).
- A **cross-project** needs-you inbox (#96115). Duo already has one.

---

## 9. Duo: what it would take

### 9.1 What Duo already has (the substrate)
- **Starting a thread:**
  - `duo2 session new --project <p> --prompt <text>` mints a `--session-id`, records `.duo/sessions.json` provenance, and starts a visible session whose first message is the prompt (`Sources/DuoKit/Model/AppModel.swift:395`).
  - `--fork-session` and carry-on exist too.
- **State:**
  - Beacons plus hook events give *needs-you / review / working / idle / resolved* with a reason (`HookEvents.swift`, `LiveSnapshot.swift`).
  - `duo2 sessions --json` and `duo2 needs-you` expose them.
  - Duo's five states are Projects' six minus *Landing*.
- **Reading reports:** `duo2 session show <id> --turns N`.
- **Ledger:** tasks are markdown files whose `sessions:` frontmatter links sessions (DL-87, DL-93). That is the `threads/*.md` of §3.2, already legible and already in Duo.
- **Grouping:** session groups (DL-24) could hold a director's threads.
- **Messaging is already live.** Sessions Duo starts have their own Claude Code inbox, even though Duo strips the parent's `CLAUDE_CODE_*` environment. This was checked on live beacons, e.g. `home-4d` (entrypoint `cli`, Duo's workspace, `peerFeatures: notify_idle, …`); see F-79. So a director session in Duo can `SendMessage` any Duo session today, and the message starts a turn visibly in that session's Duo terminal.

### 9.2 Gaps
1. **No worktree per session.** `session new` has no `--worktree`. Duo would pass `-w <slug>` (or launch with `--bg` semantics). Worktrees inside a `PROJECT.md` folder already roll up to the project (F-32).
2. **No per-session permission mode or model.** Workers need `acceptEdits`/`auto` and maybe a cheaper model; the director needs neither.
3. **Duo's own `send` never presses Enter** (DL-67) and refuses waiting sessions. The director should use Claude Code's **`SendMessage`**, not `duo2 send`. That leaves DL-67 untouched, since it governs what *you* send from Duo. A message from the director still starts a turn in a worker, and that deserves an explicit decision.
4. **Nothing for review and landing:** no diff view, no merge actions, no *Landing* state.
5. **Notifications aren't built** (DB-27, slice 3).
6. **No Claude Code version check.** Director features need ≥ 2.1.224 (≥ 2.1.236 for `notify_when_idle`). Beacons carry `version` and `peerFeatures`, so Duo can gate on `notify_idle` being present.

### 9.3 Recommendation
- **D0: no app code; try it now.**
  - Ship a `director` agent definition and skill through Duo's installed skill or primer.
  - It uses `duo2 session new` for threads, Duo tasks as the ledger, `SendMessage` and `notify_when_idle` for talk, and git for landing, with worktrees made by `git worktree add` until D1.
  - Run it on this repo for a few days. It costs only a skill file and tells us whether the pattern earns a UI.
- **D1: small app changes.**
  - `duo2 session new --worktree [name] --permission-mode <m> --model <m>`.
  - New provenance `directed-by:<director-id>`.
  - A director's threads auto-grouped under it.
  - Gate on `peerFeatures`.
- **D2: a director surface, which needs design.**
  - In the project view, thread cards with Projects' groups (add *Landing*).
  - On *Ready for review*: diff, tests passed, review findings, and Land / Send back / Resolve.
  - This is new UI, so per CLAUDE.md it gets a stub and a design question, not an invented design.

**Scope.** This is not v1 (build plan §3a: "use Duo all day, never lose a session"). It is logged as **ENH-9**. D0 could run alongside v1 work because it touches no app code.

---

## 10. Open questions / unverified

- How Projects' coordinator and threads talk is undocumented. The `claude-code-remote` link is inferred.
- The first version of `claude --cloud` / `--remote`, and of `claude --bg --resume <id>` continuing a session, are unconfirmed.
- The earlier, gated form of cross-session messaging (fix lines at 2.1.162 and 2.1.166) is unconfirmed.
- Since which version, and on which plans, `--permission-mode auto` is usable for unattended workers.
- Whether a `-p` worker can usefully *receive* messages: held messages expire after 5 minutes in `-p`, and teammates aren't spawned in `-p`.
- All the GitHub issue claims in §1.5 are user reports.

## Sources
- Projects:
  - [code.claude.com/docs/en/claude-projects](https://code.claude.com/docs/en/claude-projects) (quotes checked against the raw page)
  - [claude.com/blog/projects-redesigned](https://claude.com/blog/projects-redesigned)
  - [Unite.ai](https://www.unite.ai/anthropic-redesigns-claude-code-projects-to-coordinate-agent-threads/)
  - [The New Stack](https://thenewstack.io/claude-code-parallel-projects/) (headline only)
  - GitHub issues anthropics/claude-code #96115, #97464, #97565, #97924, #99090, #99274, #99307, #99610
- Primitives: the [CHANGELOG](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md) and these docs pages:
  - [cross-session-messaging](https://code.claude.com/docs/en/cross-session-messaging)
  - [agent-view](https://code.claude.com/docs/en/agent-view)
  - [agent-teams](https://code.claude.com/docs/en/agent-teams)
  - [agents](https://code.claude.com/docs/en/agents)
  - [worktrees](https://code.claude.com/docs/en/worktrees)
  - [hooks](https://code.claude.com/docs/en/hooks)
  - [scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks)
  - [routines](https://code.claude.com/docs/en/routines)
  - [remote-control](https://code.claude.com/docs/en/remote-control)
  - [workflows](https://code.claude.com/docs/en/workflows)
  - [agent-sdk/sessions](https://code.claude.com/docs/en/agent-sdk/sessions)
  - npm `@anthropic-ai/claude-code` publish times
- Local evidence: `claude --help`, `claude agents --help`, `claude remote-control --help` (2.1.289), and live beacons in `~/.claude/sessions/`.
- Earlier Duo research: [agent-harness-landscape.md](agent-harness-landscape.md) §1.4, §8.5.
