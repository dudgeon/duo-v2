# Agent harness & AI work-app landscape: how they model projects, tasks, sessions, parallelism, and attention

*Research date: 2026-10-03. This space moves weekly. Every claim has a date or version where one was available. Items marked **[unverified]** come from a single secondary source, or I could not confirm them in primary docs.*

**Purpose.** We are building a desktop app for **product managers** that wraps Claude Code. Its user model is topics → projects → tasks, sessions linked to tasks many:many, a "home/director" agent, and legible files on disk. This doc looks at how ~35 adjacent products model the same problems, then pulls out what we can borrow. Ideas that only make sense for code (worktrees, PRs, diffs, CI) are flagged as **[code-only]**, with a non-code equivalent where one exists.

---

## 0. TL;DR: the ten concepts most worth borrowing

1. **Sort by attention state, not by recency.** Every mature harness has converged on the same small set of states: *Needs input → Ready for review → Working → Idle/Done → Resolved/Archived*. Claude Code Agent View, Claude Code Projects "Overview", Warp, Linear agent sessions and Nimbalyst all do this. Make "what needs me" the default lens, across all projects.
2. **A coordinator conversation that spawns worker threads.** Claude Code Projects, Devin "managed Devins" and Factory Missions all have one long-lived conversation where you dump work. It routes each item to a new or existing thread and sees the reports, not every step. This is our home agent, and it also works at project level.
3. **Peek-and-reply without attaching.** From the dashboard you can read a waiting session's exact question and answer it inline (Claude Code Agent View). This is the core loop when you run six or more sessions.
4. **One-line live summary per session, plus "waiting N min."** A small model writes a status sentence per row. Nimbalyst ranks sessions by how long each has waited on you.
5. **A triage inbox with explicit verbs.** Linear has accept / decline / duplicate / snooze. Codex and ChatGPT "Triage/Scheduled" holds automation findings and auto-archives runs that found nothing. This is the home agent's input queue.
6. **Delegation, not assignment.** In Linear a task keeps a *human owner* and gains one or more *delegated agent sessions*. That is the right semantics for many:many tasks↔sessions.
7. **Tasks as plain markdown files with frontmatter, plus a "Ready" view.** Backlog.md, Kiro `tasks.md`, Beads `bd ready`, Claude Code Tasks with dependencies, Nimbalyst "waiting on" + Ready view, and Conductor `.context/` all keep work legible on disk. That fits our file-legibility constraint.
8. **Layered standing context per project.** Instructions (`CLAUDE.md`) are separate from agent-written memory (`MEMORY.md` + notes) and from a deliverables "Library". Claude Code Projects, Cowork Projects and ChatGPT project-only memory work this way, with no memory bleed between projects.
9. **Areas never finish; projects do; both get reviewed.** GTD, Things, PARA and OmniFocus treat Areas (our *topics*) as ongoing. Projects have an outcome and an end, and everything has a review cadence. Add Linear-style health (On track / At risk / Off track) that the home agent drafts.
10. **Recurring work as files that land in the inbox.** Claude Desktop scheduled tasks are `SKILL.md` files. Codex distinguishes *thread automations* (heartbeat in the same thread) from *standalone automations* (fresh run → Triage). Notion Custom Agents run on triggers.

Runners-up: Amp-style **handoff** and **thread references** instead of endless compaction. **Side chats** for questions that shouldn't pollute the thread. **Spawn-task chips** for out-of-scope discoveries. **Cross-session messaging + notify-when-idle**. A **/goal completion condition** as a task's definition of done. **Trust ramps** for approvals (Lindy, Jules).

---

## 1. Anthropic's own surfaces (most important: they are our substrate)

### 1.1 Claude Code CLI primitives (as of v2.1.28x, Sep–Oct 2026)

| Concept | What it is | Where state lives | Notes for us |
|---|---|---|---|
| **Project** | Any working directory. Sessions are stored per directory. | `~/.claude/projects/<path-with-dashes>/<session-id>.jsonl` | JSONL format is "internal… changes between versions". Use `/export`, `claude -p --resume … --output-format json`, hooks' `transcript_path`, or the SDK, not raw parsing. [docs/sessions](https://code.claude.com/docs/en/sessions) |
| **Session** | Resumable conversation tied to a directory. `--continue` (most recent here), `--resume <id/name/path>`, `/resume` picker, `/branch` / `--fork-session` | Same JSONL | **Transcripts are deleted after 30 days by default** (`cleanupPeriodDays`). Our app must raise this and/or keep its own legible per-session summary. Names: `claude -n`, `/rename`. Unnamed sessions get a Haiku-written title. Since v2.1.223, `--resume <id>` works from any directory. |
| **CLAUDE.md / AGENTS.md** | Human-written standing instructions, loaded hierarchically | In repo/folder | Already legible. Our "project instructions". |
| **Auto memory** | Agent-written learnings with a `MEMORY.md` index | `~/.claude/projects/<project>/memory/` (hidden in a system dir) | Good *shape*, wrong *location* for us. Mirror or relocate into the project folder. [docs/memory](https://code.claude.com/docs/en/memory) |
| **Subagents** | Workers inside one session that return a summary | `.claude/agents/*.md` (definitions) | Within-session delegation, not user-visible parallelism. |
| **Background sessions / Agent View** (`claude --bg`, `/bg`, `claude agents`), research preview since **2026-05-11** | Dashboard of detached sessions run by a per-user supervisor daemon | `~/.claude/daemon/`. Machine-readable via `claude agents --json` | **Best reference UI for our attention model** (see 1.2). |
| **Agent teams** (experimental, off by default) | Lead + teammates + shared task list + mailbox | `~/.claude/teams/`, `~/.claude/tasks/` ("don't edit by hand" [unverified secondary]) | Shows Anthropic's own task-list + messaging primitives. |
| **Tasks (TaskCreate/TaskList)** replacing TodoWrite (~Jan 2026) | File-based to-dos with dependencies. Shareable across sessions via `CLAUDE_CODE_TASK_LIST_ID` | `~/.claude/tasks/` [secondary sources; reportedly inspired by Beads] | Interesting prior art for cross-session task lists. A reported bug says task lists aren't restored on `--resume` [unverified]. |
| **/goal** (since **2026-05**) | Completion condition. A small model judges after each turn whether it's met, impossible, or not yet. Survives resume. | In transcript | Maps neatly to a task's **definition of done**. [docs/goal](https://code.claude.com/docs/en/goal) |
| **/loop, scheduled tasks, routines** | `/loop` = in-session interval. Desktop scheduled tasks = local cron that starts fresh sessions. Routines = cloud cron/API/GitHub triggers. | Desktop tasks: `~/.claude/scheduled-tasks/<name>/SKILL.md` (prompt in body). Schedule/folder/model are *not* in the file. | Half-legible. [docs/desktop-scheduled-tasks](https://code.claude.com/docs/en/desktop-scheduled-tasks) |
| **Cross-session messaging** (v2.1.224+) | `ListAgents` / `SendMessage` between your sessions (local socket, or via Remote Control for cloud/other machines). `@session-name` mentions. **notify_when_idle** subscriptions. Inbound policy accept/hold/refuse. A message never counts as user consent. | Per-session inbox socket | **This is the transport for our home agent** to poke project sessions and get "tell me when done". [docs/cross-session-messaging](https://code.claude.com/docs/en/cross-session-messaging) |
| **Channels** (research preview) | MCP servers *push* events (Telegram/Discord/iMessage/webhooks/CI) into a running session. Optional permission relay. | Plugin config under `~/.claude/channels/` | A way for an always-on home session to receive inbox items. [docs/channels](https://code.claude.com/docs/en/channels) |
| **Remote Control / Dispatch / mobile push** | Drive a local session from your phone. Dispatch (Apr 2026) creates *new* work from your phone and routes it to a Code or Cowork session. Push when done or blocked. | Account | Dispatch is a primitive "director": one persistent thread that routes. |
| **Worktrees** **[code-only]** | `.claude/worktrees/<id>`. Background sessions move into a worktree *before their first edit* | Repo | Non-code analog: a **draft/sandbox copy** of a doc folder, or "proposed changes" files reviewed as a diff before being applied. |

### 1.2 Agent View (Claude Code CLI), the best reference for attention UX
Source: [docs/agent-view](https://code.claude.com/docs/en/agent-view), [blog 2026-05-11](https://claude.com/blog/agent-view-in-claude-code)

- **States:** Working, **Needs input** (question, permission or MCP input), Idle, Completed, Failed, Stopped. Process liveness is shown separately by icon shape (alive / exited-but-resumable / sleeping `/loop`).
- **Default grouping:** Pinned → **Ready for review** (has open PR **[code-only]**) → **Needs input** → Working → Completed. An alternate grouping by directory (`Ctrl+S`) is effectively "by project".
- **Row contents:** state icon, name (with user color), **one-line Haiku-generated summary** of current activity or result, age, PR label.
- **Peek (`Space`)** shows the exact pending question, the result, or a full status sentence, plus **"waiting Nm"**. **Reply inline**: type an answer, pick a numbered choice, `!cmd`, or `/stop`. `→` attaches.
- **Pinning** keeps a session's process warm. Unpinned idle sessions are stopped after ~1h but stay resumable.
- **`claude agents --json`** returns `state` (`working|blocked|done|failed|stopped`), `status` (`busy|waiting|idle`), **`waitingFor`** (`permission prompt`, `input needed`…), `name`, `sessionId`, `cwd`. **Our app can read this directly** instead of scraping terminals.

### 1.3 Claude Desktop "Code" tab (redesign 2026-04-14; ongoing)
Source: [docs/desktop](https://code.claude.com/docs/en/desktop)

- Session = conversation + project folder. Sidebar lists all sessions, filters by **status / project / environment**, and can **group by project**. Pinned, unread, sections and groups exist (visible in the app's own tool surface).
- **OS notification when a session finishes and you aren't viewing it.**
- **Side chat** (`Cmd+;` / `/btw`): ask a question using the session's context *without adding to the main thread*. Not saved to disk.
- **Claude can list, read, message, rename and archive your other sessions** ("which session touched X?", "tell the payments session the schema changed").
- **Task chips:** when Claude spots out-of-scope work it offers a chip that starts a new session. The current one continues.
- **Auto-archive** when a PR merges **[code-only]**. Non-code analog: auto-resolve when the linked task is marked done or the deliverable is accepted.
- **Scheduled** section in the sidebar collects runs of scheduled tasks. A run that stalls on a permission waits there.
- Dispatch-spawned sessions get a **Dispatch badge** (provenance).

### 1.4 Claude Code **Projects**: the coordinator/threads pattern (public beta, Pro/Max, 2026)
Source: [docs/claude-projects](https://code.claude.com/docs/en/claude-projects). This is the closest existing analog to our "home agent + projects".

- **Objects:** *project conversation* (one long-running coordinator session) + **threads** (worker sessions, usually cloud, optionally on your machine via Remote Control) + **Overview** pane with tabs *Threads*, ***Library*** (input files and thread-produced files), *Pull requests*, *Routines*.
- **Routing:** "Claude decides where each message you send in the conversation goes": a quick answer inline, a new thread, or an existing thread in that area. Several unrelated tasks in one message become separate threads. Sometimes it shows **Suggested threads** for you to start.
- **The coordinator "sees what threads report back, not every step they take."** Context is managed for you: the conversation works from recent messages, recent threads and project memory.
- **Overview thread groups:** **Ready for review** (PR open), **Waiting on you** (reply, approval or failure), **Working**, **Landing** (PR approved/queued), **Idle**, **Resolved** (by you, by Claude after the last step, or **auto after a week of inactivity**). A dot shows on the Overview button when something waits on you. Desktop notifications fire on coordinator posts, thread errors and needs-input. Per-turn notifications are optional, per project.
- **Standing context table:** *Project memory* (agent-written files, `MEMORY.md` index), *Project instructions* (≤16k chars sent to every thread), *Repositories/files/environment*. Explicitly separate from repo `CLAUDE.md`.
- **Tuning by conversation:** "propose threads and wait for my go-ahead", "run at most two at a time", "only post when something finishes or is blocked". Claude saves these to memory, but **"they're instructions Claude keeps to, not enforced settings."**
- **Promote a session:** "Continue as project" / "Move to project" turns an ad-hoc session into managed work. This is our **"attach session to task"** move.
- **Non-code use is explicitly supported:** "a folder of contracts or a support-ticket export… threads deliver each write-up as a file on the project's Library tab."
- Caveat: uploads are **copies** ("a change you make on your computer afterward doesn't reach the project"). That anti-pattern does not apply to a local-folder app.

### 1.5 Claude Cowork (launched 2026-01-12; Projects ~2026-03; Dispatch ~2026-04)
Sources: [support: Cowork projects](https://support.claude.com/en/articles/14116274-organize-your-tasks-with-projects-in-claude-cowork), [support: get started](https://support.claude.com/en/articles/13345190-get-started-with-cowork), [fast.io review](https://fast.io/resources/claude-cowork-review-2026/)

- **Unit = task** (describe an outcome, step away, come back to finished files). A live progress/todo panel shows steps. Approval modes: *Manually approve / Automatically approve (with safety review) / Skip approvals*.
- **Cowork Projects** = instructions + scheduled tasks + context (a local folder, a linked Chat project, or URLs) + **project-scoped memory** (no bleed across projects).
- **"Folder instructions"** that Claude can update itself [wording from support doc; file format unverified].
- Projects created from local folders "stay on that computer and aren't saved to your Claude account". **On 2026-10-06 new Cowork tasks move to cloud execution** and the "Only on your computer" option is removed (per support doc). That makes a local-first, file-legible PM tool differentiated.
- **Dispatch** (in the Cowork tab) is a persistent phone↔desktop thread that "decides" whether a request is coding (spawns a Code session) or other work (handled in Cowork). It is a lightweight **director**. Critics note it gives "no board or log" ([MindStudio, 2026-04-03](https://www.mindstudio.ai/blog/vibe-kanban-vs-paperclip-vs-claude-code-dispatch)).

### 1.6 Claude.ai (Chat) Projects
Instructions + knowledge files (RAG when large) + **per-project memory summaries (since ~2026-03)**. Chats can be moved in or out of projects to control memory scope ([secondary: aimemory.pro](https://aimemory.pro/blog/claude-projects-guide)). Server-side; not legible on disk.

---

## 2. OpenAI

### 2.1 Codex app → merged into the ChatGPT desktop "superapp" (2026)
Sources: [Codex desktop automations deep-dive, 2026-04-08](https://codex.danielvaughan.com/2026/04/08/codex-desktop-automations/), [thread automations, 2026-05-15](https://codex.danielvaughan.com/2026/05/15/codex-proactive-teammate-thread-automations-scheduled-monitoring-durable-views/), [learn.chatgpt.com/docs/automations](https://learn.chatgpt.com/docs/automations?surface=app), [Wikipedia](https://en.wikipedia.org/wiki/OpenAI_Codex_(AI_agent))

- **Timeline:** Codex macOS app 2026-02-02. Windows 2026-03-04. A merger of ChatGPT + Codex + Atlas into one desktop app was announced internally 2026-03-16. Codex docs now redirect to `learn.chatgpt.com`, and the app ships Chat, Work and Codex tabs.
- **Objects:** **Project** (= a directory) → **threads** (= tasks). Each thread runs in **Local**, **Worktree** **[code-only]**, or **Cloud** mode. Threads can be pinned and archived.
- **Automations**, two kinds:
  - **Thread automation**: a "heartbeat-style recurring wake-up call attached to a specific thread" that keeps context ("learned priorities"). Good for a *weekly status thread* that remembers what mattered last time.
  - **Standalone automation**: fresh run on a schedule or trigger, can span projects, **reports to the Triage inbox**, and **auto-archives if there's nothing to report**.
  - Triggers: schedule, events (Gmail, Slack, GitHub PR), manual. Skills can be invoked from automations (`$skill-name`), and skills can create or update automations.
- **Triage/Scheduled view** = inbox of runs with findings, unread indicator, filter all/unread.
- State: Codex CLI sessions are JSONL under `~/.codex/sessions` (referenced in docs). Worktrees under `$CODEX_HOME/worktrees`, keeping the 15 most recent [secondary].

### 2.2 ChatGPT Projects / ChatGPT Work / Agent
- **Projects:** instructions + files + **project-only memory** (2025-08-22). Since a 2026-08 update this can be toggled on existing projects ([memx.app](https://memx.app/blog/chatgpt-project-only-memory-control/)). In project-only mode it doesn't read global memory and doesn't leak out.
- **ChatGPT Work** (2026): an agent for long-running business tasks. Chat and Work conversations sit together in **Recents** (sort, filter, pin). **Scheduled Tasks** run once, repeat, respond to an event, or **monitor for changes** ([OpenAI help: ChatGPT Work and Codex](https://help-lb.openai.com/en/articles/20001275-chatgpt-work-and-codex)).
- **Manage-your-inbox use case** ([learn.chatgpt.com](https://learn.chatgpt.com/use-cases/manage-your-inbox)): scheduled runs at 8am/4pm sort mail into *needs attention / routine / optional*, draft replies in your voice, and wait for approval. A textbook **chief-of-staff** loop.

---

## 3. Parallel-agent harnesses (mostly code-centric)

| Product | Core objects & hierarchy | Unit of work ↔ session | Attention model | State location | Notable affordances |
|---|---|---|---|---|---|
| **Conductor** (Mac; Conductor Cloud 2026) [site](https://www.conductor.build/docs/guides/parallel-agents/run-multiple-claude-code-sessions) | Repository → **Workspace** (worktree + branch) → chat tabs | 1 workspace = 1 branch/PR **[code-only]**. Multiple chats per workspace | Sidebar shows git status, CI, deploys, **todos** per workspace | `conductor.json` (committed scripts: setup/run/**archive**). **`.context/`** per workspace (gitignored) holds attachments, plans, notes, chat summaries, Linear issues ([changelog 0.28](https://www.conductor.build/changelog/0.28.0-workspaces-page-claude-s-context-interactive-planning-keyboard-nav-and-more)) | `.context/` = a legible **handoff folder between chats**. An archive hook script. Import from Linear/GitHub issues. |
| **Crystal → Nimbalyst** (OSS, MIT; v0.79 2026-09-29) [changelog](https://www.nimbalyst.com/changelog/) | Workspace → sessions + **tracker items** (task/bug/feature/idea, as full docs) + markdown/mockup/diagram editors | Items link to sessions *and* files. Launch a session or worktree *from* an item. Sessions that launched other sessions get an icon (lineage). | **Session kanban** (backlog/planning/implementing/complete). macOS menu-bar fleet with running/blocked/failed. **iPhone Live Activity ranking sessions by how long each has waited on you**. Trackers record **what an item is waiting on** plus a **Ready view** (unblocked work). Triage inboxes. | Mix: docs are repo files. App uses a local database (changelog mentions "database backups") [tracker storage format unverified] | **Explicitly targets PMs** ("[Claude Code for Product Managers](https://nimbalyst.com/claude-code-for-product-managers/)"). WYSIWYG markdown with **red/green diff review of agent edits to docs**, the strongest non-code "review" analog. "Crew" (alpha): persistent agent teammates on scheduled shifts within token budgets. **Closest competitor**. |
| **Sculptor** (Imbue) [docs](https://docs.imbue.com/features/containers) | Repo → agents, each in a Docker container with its own branch | 1 agent = 1 container | Per-agent status | Containers | **Pairing Mode**: sync an agent's container into your IDE to co-edit. Non-code analog: "open this draft in my editor". |
| **Vibe Kanban** (Bloop; hosted version wound down 2026-04, OSS continues) [virtuslab](https://virtuslab.com/blog/ai/vibe-kanban/) | Project → **Tasks (cards)** → **Attempts** (each a workspace: branch + worktree + terminal + dev server) | **Task : Attempt = 1 : many** (retry with a different agent or prompt). Follow-ups within an attempt. | Columns To Do / In Progress / **In Review** / Done. Inline diff + comments the agent can act on. | Local (SQLite [unverified]). Exposes board as an MCP server so other agents can create and move cards. | **Task ≠ session** separation (attempts) is good prior art. "Board as MCP server" lets the home agent manipulate tasks. |
| **Superset** [superset.sh](https://superset.sh/compare/superset-vs-sculptor) | Workspace (worktree) per agent. Runs any CLI agent | 1 workspace = 1 agent | Unified monitor + "notified when they need attention" | Worktrees. App state [unverified] | Agent-agnostic terminal host, similar to our wrapper approach. |
| **Claude Squad** [README](https://raw.githubusercontent.com/smtg-ai/claude-squad/main/README.md) | TUI: instances = tmux session + worktree | 1:1 | List with status; attach/detach | tmux + worktrees; config in home dir [unverified] | Minimal; proves tmux-persistent terminals as session hosts. |
| **Terragon** (cloud Claude Code orchestrator; now OSS "terragon-oss", hosted service appears discontinued [unverified]) | Task → cloud sandbox → PR | 1:1 | Dashboard with CI status | Cloud | "Trust it to work independently, check in when done." |
| **Warp** (2.0 "Agentic Development Environment") [docs](https://docs.warp.dev/agent-platform/capabilities/agent-notifications/) | Tabs/panes with agent conversations; **Agent Management Panel** | Conversation per pane | **Notification types: Complete / Request (blocked: approval, permission, idle prompt) / Error**. Works across tabs and apps. | Warp Drive (cloud) for rules and notebooks | The clean three-way notification taxonomy is worth copying. |
| **Amp** (Sourcegraph spinout) [threads docs](https://ampcode.com/docs/threads), [Thread Map 2025-12-18](https://hackernoon.com/too-many-agent-chats-amps-new-thread-map-shows-what-connects-to-what?source=rss) | **Threads** (server-side `ampcode.com/threads/T-…`), **labels**, visibility (private/workspace/unlisted) | Thread per line of work. **Handoff** spawns a fresh thread with distilled context instead of compacting forever. **`@T-…` thread references** let a thread pull what matters from another. | Activity feed. **Thread Map** graph of references, continuations and handoffs | Server | Handoff + references + map = **session lineage** concepts that apply to non-code work. Labels over folders. |
| **Cursor 3 Agents Window** (2026-04-02) [DataCamp](https://www.datacamp.com/blog/cursor-3) | Agents across local/SSH/worktree/cloud in one sidebar, including agents started from Slack, GitHub, Linear, mobile | Agent tab per task. `/best-of-n` **[code-only]** | Active/running/completed | Cursor cloud + local | **Single list regardless of where the agent was launched.** Cloud↔local handoff. |
| **Zed** parallel agents [docs](https://zed.dev/docs/ai/parallel-agents) | **Threads Sidebar grouped by project**. Agent threads and **terminal threads** side by side | Thread per task, any ACP agent | Status indicator per thread | Local | Archive → Thread History → restore. Terminal threads as first-class siblings of agent threads, which fits a terminal-centric app. |
| **VS Code Agent Sessions view** (1.106 2025-11 → 1.129 2026-07) [blog](https://code.visualstudio.com/blogs/2026/02/05/multi-agent-development) | Unified list of local chat sessions + background agents (Copilot coding agent, Copilot CLI, Claude, Codex) | Session per task | Sections by provider or single unified view | Mixed | Aggregates *other* harnesses' sessions, the same as our wrapper's job. |
| **GitHub Agent HQ / Mission Control** (Universe 2025-10; [guide 2025-12-01](https://github.blog/ai-and-ml/github-copilot/how-to-orchestrate-agents-using-mission-control/)) | Task → agent session → PR, across repos | Assign issue → session | Live session logs. Steer, pause, restart. Guidance on *what signals mean intervene* (repeated failures, scope creep, circular troubleshooting) | GitHub | Advice to run parallel for independent research/docs/analysis but **stay sequential when tasks have dependencies**. `agents.md` custom agents. |
| **Google Jules** [InfoQ](https://www.infoq.com/news/2025/08/google-jules) | Task → cloud VM → PR | 1:1 | **Plan approval before execution** (configurable/auto). **Proactive suggestions** mined from TODOs. Scheduled tasks | Google cloud | "Agent proposes work, human approves" queue. |
| **Devin** [advanced capabilities](https://docs.devin.ai/work-with-devin/advanced-capabilities) | Sessions, **Knowledge** (auto-recalled notes), **Playbooks** (reusable procedures from successful sessions), Schedules | **Coordinator session → managed child Devins** (isolated VMs). Coordinator scopes, monitors, messages children, resolves conflicts, compiles results, sets self-reminders | Sessions **sleep instead of ending** and can be woken. Session analysis | Cloud | **Playbooks distilled from successful sessions.** Coordinator self-reminders. |
| **Factory Missions** [docs](https://docs.factory.com/missions/overview) | Mission → Plan → **Milestones** → Features → **fresh worker session per feature** → validation phase per milestone | Orchestrator + workers | Asks for help when stalled, over time thresholds, failed retries or repeated QA failures. "Pause the orchestrator, describe what you see, ask it to recover." | Factory cloud [storage unverified] | **Milestone validation gates**. Fresh context per unit of work. Factory admits that parallelization effectiveness is "still under investigation". |
| **Paperclip** (OSS, 2026-03-04) [docs](https://docs.paperclip.ing/) | **Company → org chart of agents → goals → projects → tasks**. Budgets, approvals, activity log | Agents wake on **heartbeats** and check for work. Delegation flows up and down the org chart | Approvals + audit trail | Node server + DB | "Every task traces back to the company mission" (goal ancestry). Per-agent budgets. A director pattern taken to the extreme. |

---

## 4. Non-coding agent & work tools

| Product | Core objects | Unit of work ↔ agent run | Attention / review | State | Borrowable |
|---|---|---|---|---|---|
| **Linear** ([agents](https://linear.app/docs/agents-in-linear.md), [triage](https://linear.app/docs/triage), [triage intelligence](https://linear.app/docs/triage-intelligence), [updates](https://linear.app/docs/initiative-and-project-updates)) | **Initiatives → Projects → Issues**. Team **Triage** inbox. Personal **Inbox** | **Delegation:** an issue keeps a human assignee and gains a *delegated agent*. An **agent session** tracks an interaction with states *waiting for input / working / completed / errored* ([Agent Interaction SDK, 2025-07](https://linear.app/changelog/2025-07-30-agent-interaction-guidelines-and-sdk)) plus Agent Activity (reasoning, tool use, clarifying prompts) | Triage verbs: **accept (1), duplicate (2), decline (3), snooze (H)**. **Triage Intelligence** suggests team/project/assignee/labels with an explanation, optionally auto-applied. **Project updates** have **health: On track / At risk / Off track / no recent update** | Server | Triage verbs. Delegation semantics. Suggested-properties-with-reasons. Health + update cadence. Initiative layer ≈ our *topic* when it is goal-shaped. |
| **Notion Custom Agents** (GA 2026-02-24; credits 2026-05-04) [Matthias Frank guide](https://matthiasfrank.de/en/notion-custom-agents/), [Notion 3.0 2025-09-18](https://www.notion.com/releases/2025-09-18) | Agent = **instructions page** + **triggers** (schedule, Slack, email, calendar, DB change, meeting notes) + scoped permissions + model | Each trigger fires a run. "Recent activity" lists runs, and you can reopen any run and continue the conversation | Pattern: an **Agent Run Log database** recording what was done, confidence, and knowledge gaps | Notion pages/DBs (legible *inside Notion*) | **Instructions live in an ordinary page**, which suggests our agent config should be an ordinary markdown file. A run log as a document. Triage and weekly-status agent examples. |
| **Manus** [timeline](https://www.scriptbyai.com/manus-ai-timeline/) | **Projects** (2025-12: reusable instructions + files across tasks) → tasks. **Wide Research** (100+ parallel sub-agents). Scheduled tasks | Task = run | Replay / share | Cloud | Fan-out research as a single task with many workers. |
| **Lindy** [assistant](https://www.lindy.ai/assistant) | Agent = trigger + skills + prompt | Run per trigger | **"Confirm before sending" → switch specific skills to fully automated once trust is established.** Approvals via Slack or web | Cloud | **Trust ramp per action type.** Classify, then draft or auto-reply or escalate. |
| **Perplexity** Spaces / Computer (Computer launched 2026-02-27) [overview](https://beginnersinai.org/whats-new-perplexity-2026/) | Spaces (instructions + files + threads) + scheduled tasks inside a Space | Thread per question | Scheduled results | Cloud | Scheduled task *scoped to a Space* ≈ a scheduled task scoped to a project. |
| **Granola** [folders](https://docs.granola.ai/help-center/sharing/folders/spaces-and-folders.md), [chat](https://help.granola.ai/article/chatting-with-your-meetings) | Meetings → **Folders** / Spaces (team folders). **Recipes** (saved prompts) | **Chat scoped to a folder** ("chat with any folder… across meetings") | n/a | Cloud | **Folder = context scope for a query.** Recipes = named prompts. Meeting notes are a PM's main input stream, a natural inbox source. |
| **Obsidian + Claude Code (e.g., Claudesidian)** [okhlopkov](https://okhlopkov.com/second-brain-obsidian-claude-code/), [algolia repo index](https://docsearch.algolia.com/mcp/docs/repo/heyitsnoah/claudesidian) | **PARA folders** in a vault. Per project: `overview.md` (durable facts/strategy), `tasks.md`, `ideas.md`, `ai-docs/` (generated briefs) + root `CLAUDE.md` | Claude Code sessions run in the vault | Human reads the files | **Plain markdown on disk** | Proof that PMs and knowledge workers already run Claude Code over PARA-structured markdown. The per-project file primitives are close to what we need. |
| **"Chief of Staff" Claude Code setups** ([mimurchison/claude-chief-of-staff](https://www.sourcepulse.org/projects/24805494), [Harper Reed 2025-12-03](https://harper.blog/2025/12/03/claude-code-email-productivity-mcp-agents/), [The AI Corner](https://www.the-ai-corner.com/p/claude-code-chief-of-staff-system)) | Slash commands `/gm` (morning brief), `/triage`, `/my-tasks`. A **`goals.yaml`** filters decisions. One sub-agent per source (mail, calendar, tasks) | One home folder/session | Briefing + prioritized list with draft replies | Files in a folder | A **goals file the director consults** to rank and route. Morning brief as a ritual. |

### 4.1 GTD-family task managers (our *topics* ≈ Areas)
- **Things 3:** **Areas of Responsibility** are ongoing and never complete. **Projects** have a defined end and complete when their to-dos are done. Headings group within projects. Built-in lists: Inbox, Today, Upcoming, Anytime, Someday, Logbook ([URL scheme doc lists these IDs](https://culturedcode.com/things/support/articles/2803573/)); [Forte on project vs area people](https://fortelabs.com/blog/project-people-vs-area-people-are-you-running-a-sprint-or-a-marathon/).
- **OmniFocus:** Folders → Projects (**parallel / sequential / single-action list**) → actions. Sequential projects expose only the *next available* action. Each project has a **review interval**, and the **Review** perspective surfaces projects due for review ([reference manual](https://support.omnigroup.com/documentation/omnifocus/web/1.6/en/print)). Defer dates hide work until it is relevant.
- **PARA (Forte, 2017; book 2023):** Projects (short-term, goal + deadline) / **Areas** (ongoing standard to maintain) / Resources / **Archives**. Organized **by actionability, not topic** ([Workflowy summary](https://workflowy.com/help/para-method)).
- **GTD's Weekly Review** is the ritual that keeps the system trustworthy. The home agent can run it: collect → process the inbox → review each project's next action and health → review areas/topics.

### 4.2 File-based task stores built for agents (legibility prior art)
- **Backlog.md**: each task is `backlog/tasks/task-<id> - <title>.md` with frontmatter. Terminal Kanban + web UI + MCP. "Your attention is the bottleneck… you can read a screenful of task specs with acceptance criteria" ([README](https://cdn.jsdelivr.net/gh/MrLesk/Backlog.md@main/README.md)).
- **Beads** (Yegge): `.beads/issues.jsonl` in git. Dependency-typed links. **`bd ready`** gives a topologically sorted list of unblocked work ([morphllm](https://www.morphllm.com/beads-agent-memory)). Reportedly inspired Claude Code Tasks [secondary].
- **Kiro specs**: `.kiro/specs/<feature>/requirements.md` (EARS acceptance criteria), `design.md`, `tasks.md` (ordered checklist). `.kiro/steering/product.md|structure.md|tech.md` ([guide](https://medium.com/@arnab.kg.co.in/mastering-kiro-the-definitive-guide-to-spec-driven-ai-development-b14e82ff4ea5)). Spec→tasks fits PM work (PRD → task breakdown) even though Kiro targets code.
- **Conductor `.context/`**: per-workspace folder of plans, notes and attachments shared between chats.

---

## 5. Comparison table (condensed)

| | Hierarchy | Work ↔ session | Resume vs new | Parallel & attention | State location | Legible? |
|---|---|---|---|---|---|---|
| Claude Code CLI | dir → sessions | ad hoc | `--continue/--resume/--fork`; names | Agent View: Needs input / Review / Working / Done; peek+reply; `--json` | `~/.claude/projects/*.jsonl` (30-day TTL) | Partly (CLAUDE.md yes; transcripts internal JSONL) |
| Claude Desktop Code tab | folder → sessions; sidebar groups/sections | ad hoc; task chips | click to resume; side chats | status filters; OS notifs; Claude manages other sessions | same as CLI + app | Partly |
| Claude Code Projects | project conversation → threads | coordinator routes msgs → threads | threads persist; auto-resolve 1 wk | Overview: Review / Waiting on you / Working / Landing / Idle / Resolved | cloud + memory files | Memory files visible in UI, not on your disk |
| Cowork | project → tasks | task = run | sessions follow account | progress panel; approvals; Dispatch push | account/cloud (local-folder projects stay local) | Low |
| Codex / ChatGPT app | project(dir) → threads | thread = task | thread automations wake same thread | Triage inbox; auto-archive empty runs | `~/.codex`, cloud | Low–medium |
| Conductor | repo → workspace → chats | workspace = branch/PR | per workspace | sidebar git/CI/todos | `.context/`, `conductor.json` | Medium |
| Nimbalyst | workspace → items + sessions | item ↔ sessions + files | persistent, searchable, branchable | session kanban; menu-bar fleet; wait-time ranking; Ready view | repo docs + local DB | Medium |
| Vibe Kanban | project → task → attempts | task 1:N attempts | follow-ups | columns incl. In Review | local DB [unverified] | Low |
| Amp | threads + labels | thread; handoff; @refs | handoff instead of compaction | activity; Thread Map | server | Low (shareable URLs) |
| Linear | initiative → project → issue | issue delegated to agent session(s) | session per trigger | Triage verbs; agent states; health | server | Low |
| Notion Custom Agents | agent (instructions page) + triggers | run per trigger | reopen any run | run history; run-log DB | Notion | In-app |
| Things / OmniFocus | area/folder → project → to-do | n/a | n/a | Today/Review perspectives | local DB | Low (export only) |
| PARA / Obsidian | P/A/R/A folders | Claude sessions in vault | CLI resume | human reads files | **markdown** | **High** |
| Backlog.md / Beads / Kiro | folder of task files / jsonl / spec files | agent picks a task | n/a | `ready` views | **in repo** | **High** |

---

## 6. Concepts worth borrowing

Legend: **G** = general (non-code friendly). **C** = code-only (non-code analog given).

### Attention & review
| # | Concept | Source(s) | Rationale | G/C |
|---|---|---|---|---|
| A1 | **Attention-state lanes**: *Needs you* (question, approval, error) → *Ready for review* (deliverable produced) → *Working* → *Idle* → *Resolved* | Agent View, CC Projects, Warp, Linear | A PM running 6+ sessions needs one lane that answers "what's blocked on me." Same vocabulary as the substrate. | G (redefine "Ready for review" as *a deliverable or draft awaiting your read*, not a PR) |
| A2 | **Peek & reply inline** from the dashboard; numbered choices for multiple-choice questions | Agent View | Clears blocks in seconds without context-switching into a terminal | G |
| A3 | **Live one-line summary + "waiting Nm"**; rank needs-you by wait time | Agent View (Haiku summary), Nimbalyst Live Activity | Lets you triage without opening anything; wait time is a fair priority signal | G |
| A4 | **Three notification types**: Complete / Request / Error, per-project notification policy ("only when blocked or done") | Warp, CC Projects | Avoids notification spam at 6+ sessions | G |
| A5 | **Auto-resolve after inactivity** (1 week) and auto-archive empty automation runs | CC Projects, Codex Triage | Keeps lists short without manual hygiene | G |
| A6 | **Review of agent edits to documents as tracked changes** | Nimbalyst (markdown red/green), Notion | The non-code analog of diff review: PMs already understand "suggested edits" | G (diff review of code is C) |
| A7 | **Plan approval before execution, configurable** | Jules, Factory Missions, CC plan mode | Cheap checkpoint before an agent burns an hour on the wrong thing | G |
| A8 | **Trust ramp per action type** (draft-only → auto for whitelisted actions) | Lindy, Cowork approval modes, Codex sandbox modes | Lets PMs grow autonomy gradually per project | G |
| A9 | **Intervention signals** (repeated failures, scope creep, circular attempts, long silence) surfaced as warnings | GitHub Mission Control, Factory | The app can flag "stuck" sessions before you notice | G |

### Orchestration & the home agent
| # | Concept | Source(s) | Rationale | G/C |
|---|---|---|---|---|
| O1 | **Coordinator conversation + worker threads**: you talk to one place, it routes to a new or existing thread, sees reports not steps | CC Projects, Devin managed Devins, Factory, Dispatch | This is our home agent (cross-project) and optionally a per-project lead | G |
| O2 | **Suggested threads** (proposed, not started) + "propose and wait" vs "start without asking" | CC Projects, Jules suggestions | Keeps the PM in control of spend and scope | G |
| O3 | **Triage inbox verbs**: accept → (route to project/task), duplicate, decline, snooze, plus suggested routing with a reason | Linear Triage + Triage Intelligence, Codex Triage | Gives the home agent's inbox a crisp, keyboardable UX | G |
| O4 | **Cross-session messaging + notify-when-idle**; messages from peers never count as user consent | Claude Code | Native transport for home↔project coordination with the right safety model | G |
| O5 | **Goal ancestry**: every task traces to a project goal, every project to a topic and its goals; a `goals` file the director uses to rank | Paperclip, chief-of-staff `goals.yaml`, Linear initiatives | Lets the home agent prioritize and write status meaningfully | G |
| O6 | **Thread automations (heartbeat in the same session) vs standalone automations (fresh run → inbox)** | Codex app | Two different recurring-work needs: "keep watching this" vs "sweep and report" | G |
| O7 | **Playbooks distilled from successful sessions** | Devin, Notion run-log pattern | Turn a good session into a reusable skill or prompt file | G |
| O8 | **Milestone validation gates**: fresh worker per unit, validation pass at milestone | Factory Missions | Long PM projects (e.g., research synthesis) benefit from a check step | G |

### Sessions & continuity
| # | Concept | Source(s) | Rationale | G/C |
|---|---|---|---|---|
| S1 | **Handoff** (new session seeded with a distilled brief) instead of endless compaction; **@session references** to pull context from another session | Amp, CC `/branch`, CC "Continue as project" | Long PM work spans weeks; handoffs keep sessions focused and legible | G |
| S2 | **Session lineage/provenance**: spawned-by, dispatched-from, scheduled badges; a graph view later | Nimbalyst icon, Dispatch badge, Amp Thread Map | Answers "where did this session come from and why" | G |
| S3 | **Side chat** for quick questions that shouldn't enter the main thread | Claude Desktop `Cmd+;` / `/btw` | Protects a working session's context | G |
| S4 | **Spawn-task chip**: agent flags out-of-scope work as a one-click new task/session | Claude Desktop, CC `spawn_task` | Captures tangents without derailing; naturally creates task↔session links | G |
| S5 | **Promote ad-hoc session → task/project** ("Continue as project" / "Move to project") | CC Projects | Many sessions start before the task exists; attach afterwards | G |
| S6 | **Pin to keep warm; sleep instead of end** | Agent View pinning, Devin sleep | Pinned = sessions you're actively steering | G |
| S7 | **Definition of done per task as a /goal condition** | Claude Code `/goal` | An agent-checkable done condition, written in the task file | G |
| S8 | **Isolation for parallel edits** | Worktrees, containers | Prevent two sessions clobbering the same files | **C**. Non-code analog: write to `drafts/<session>/`, or produce "proposed edit" files, applied after review |

### Structure & state
| # | Concept | Source(s) | Rationale | G/C |
|---|---|---|---|---|
| F1 | **Areas vs projects**: topics are ongoing, never "done"; projects have an outcome and end and move to Archive | Things, PARA, OmniFocus | Matches the PM mental model; gives lifecycle semantics | G |
| F2 | **Review cadence + health** per project (On track/At risk/Off track + short update), drafted by the home agent | OmniFocus review intervals, Linear updates | Turns cross-project status into a ritual, not ad-hoc asking | G |
| F3 | **Task files with frontmatter** (status, owner, waiting_on, depends_on, sessions, due) + **Ready view** (unblocked) | Backlog.md, Beads, Nimbalyst, CC Tasks | Legible, greppable, agent-editable; dependency-aware "what next" | G |
| F4 | **Layered project context**: `CLAUDE.md` (instructions, human-owned) / `memory/` (agent-written, `MEMORY.md` index) / `deliverables/` ("Library") | CC Projects, Cowork, ChatGPT project-only memory | Clear ownership; no memory bleed; deliverables are findable | G |
| F5 | **Per-workspace context/handoff folder** | Conductor `.context/` | Where plans, attachments and session summaries live between sessions | G |
| F6 | **Recurring tasks as files** (prompt in a markdown file with frontmatter) | Desktop scheduled tasks `SKILL.md`, Notion instructions page | Legible and versionable; we should put *schedule too* in frontmatter (Anthropic doesn't) | G |
| F7 | **Labels over deep hierarchy for sessions**, plus pinning | Amp labels, Codex pins | Sessions are ephemeral; tag them rather than file them | G |
| F8 | **Folder-scoped chat** ("ask across everything in this topic/project") | Granola folders, Claude Projects | Lets a PM query a topic's notes, decisions and deliverables | G |
| F9 | **Board/task store exposed as an MCP server or CLI** so agents can create, move and read tasks | Vibe Kanban MCP, Backlog.md MCP, Beads CLI | The home agent and project sessions manipulate tasks through the same API the UI uses | G |

---

## 7. Anti-patterns to avoid

1. **Hiding the truth in system dirs or app DBs.** Claude Code keeps transcripts and auto memory under `~/.claude/projects/…`. Scheduled-task schedules live outside the `SKILL.md`. Agent-team files are "don't edit by hand". Nimbalyst and Vibe Kanban use local DBs. Our constraint says the app's own metadata lives in the project folder. **Watch out: Claude Code deletes transcripts after 30 days by default.** Set `cleanupPeriodDays` high and write a durable, human-readable session summary into the project folder.
2. **Coupling task = session = branch 1:1.** Conductor, Codex worktree threads, Vibe Kanban attempts, Jules and Terragon all do this. It suits PRs and fails a PM, whose task ("decide pricing for tier 2") spans several sessions, and whose sessions (a research run) feed several tasks.
3. **PR-defined "done" and "review" states.** "Ready for review = PR open" and "Landing = PR queued" mean nothing for documents, decisions or emails. Define review around deliverables and decisions.
4. **Using session phase as task status.** Nimbalyst's session kanban (backlog/planning/implementing/complete) blurs *task progress* with *session activity*. Keep two vocabularies: task status (todo/doing/waiting/done) and session state (working/needs-you/idle/done).
5. **Black-box dispatch.** Dispatch-style routing with "no board or log" breaks trust. Every routing decision by the home agent should leave a visible trail (an inbox entry with "routed to → project/task/session").
6. **Coordinator preferences as soft prompts only.** Claude Code Projects admits that a limit like "run at most two threads" is "not a hard cap". Enforce concurrency and approval policies in the app, and use prompts for style.
7. **Uploads as copies.** Cloud projects copy files, which then drift from the local originals. Point at the real folder.
8. **Memory bleed across projects.** Global memory that colors unrelated work. ChatGPT added project-only memory to fix this. Scope memory to project (and topic) by default.
9. **Notification firehose and tab soup.** A tmux grid or tab per agent with every turn-end pinging you. Notify only on Request/Error (and optionally Complete), per project.
10. **Over-eager auto-decomposition.** Factory says parallel effectiveness is "still under investigation", and GitHub advises sequential execution when tasks depend on each other. Default the home agent to *propose* splits, not execute them.
11. **Cloud-only lock-in for local work.** Cowork's 2026-10-06 shift to cloud execution and claude.ai Projects' server-side state reduce legibility. Local-first files are a differentiator. Remote access should be additive, through Remote Control.
12. **Unbounded flat session lists.** Without auto-resolve, archive and grouping, lists rot within a week.

---

## 8. Implications for our IA

### 8.1 Objects and their semantics
| Our object | Closest analogs | Semantics we should adopt |
|---|---|---|
| **Topic** | GTD/Things **Area**, PARA Area, Linear Initiative (when goal-shaped), Granola folder | Ongoing; **never completes**; has *standards/goals* and a review cadence; contains projects; has its own `CLAUDE.md` inherited by child projects (Claude Code loads CLAUDE.md hierarchically, so nesting project folders inside topic folders gives inheritance for free). Archive = move to `_archive/`. |
| **Project** | Things/PARA Project, Claude Code project (= folder), CC Projects "project", Linear Project | A **folder** where sessions start. Has goal, outcome, status/health, review interval. Completes, then archives. |
| **Task** | Linear issue, Backlog.md task, Things to-do, Vibe Kanban task | **A markdown file** with frontmatter: `status`, `owner` (human), `waiting_on`, `depends_on`, `done_when` (a `/goal`-style condition), `sessions: [...]`. A task can exist with zero sessions. |
| **Session** | Claude Code session, Amp thread, CC Projects thread, Linear agent session | Claude Code's resumable conversation in the project folder. App adds a **name**, **labels**, **provenance** (spawned by home agent / task / schedule / chip), **linked tasks**, and a durable **summary/handoff note**. State comes live from `claude agents --json` / hooks. |
| **Task ↔ session link** | Linear *delegation*; Vibe Kanban *attempts*; Nimbalyst item↔session links | Many:many. Make **one side canonical** to avoid drift. Recommendation: the session index in the project folder holds `tasks:`, and the app derives the reverse (or the task frontmatter holds `sessions:`, but not both hand-maintained). |
| **Home agent** | CC Projects coordinator, Dispatch, Devin coordinator, chief-of-staff setups, Codex Triage | A **project of its own** (a `home/` folder) with: `inbox.md` (triage queue with accept/route/snooze/decline), `goals.md`, routines (morning brief, weekly review), and a **routing log**. It creates tasks in project folders, spawns sessions there (`claude --bg` with project cwd), messages running sessions (`SendMessage`, `notify_when_idle`), and reads project status files to write cross-project status. |
| **Recurring work** | Desktop scheduled tasks, Codex automations, Notion triggers | A markdown file per routine (prompt body + frontmatter **including schedule, target folder, mode** — more legible than Anthropic's split). Two kinds: *heartbeat* (resume the same session) and *sweep* (fresh session → home inbox; auto-archive if nothing found). |

### 8.2 A file layout sketch (illustrative, not prescriptive)
```
~/Work/                           # workspace root (user-chosen)
  home/                           # the home/director agent's project
    CLAUDE.md                     # how the director triages, routes, reports
    inbox.md                      # triage queue (or inbox/*.md one per item)
    goals.md                      # quarter goals used for ranking (cf. goals.yaml)
    routines/morning-brief.md     # frontmatter: schedule, mode=sweep
    routines/weekly-review.md
    log/2026-10-03.md             # routing decisions: item → topic/project/task/session
  pricing/                        # TOPIC (area) — never "done"
    TOPIC.md                      # standards, goals, review cadence
    CLAUDE.md                     # inherited by child projects
    tier2-launch/                 # PROJECT (folder = Claude Code project)
      PROJECT.md                  # goal, outcome, health, last update, review interval
      CLAUDE.md                   # project instructions (human-owned)
      tasks/T-014-competitor-scan.md   # frontmatter: status, owner, waiting_on, done_when, ...
      sessions/                   # app-maintained, human-readable
        index.md                  # session id, name, labels, provenance, tasks, state snapshot
        2026-10-02-competitor-scan.summary.md   # durable handoff note (survives 30-day TTL)
      memory/MEMORY.md            # agent-written learnings (mirrors CC auto-memory shape)
      deliverables/               # "Library": outputs awaiting/after review
      drafts/                     # sandbox for parallel edits (non-code "worktree")
    _archive/
```

### 8.3 Attention model
- A **global "Needs you" lane** above everything merges three sources: (1) sessions in `blocked` state (`waitingFor`: permission/input) from `claude agents --json` or hooks; (2) tasks with `waiting_on: me` or deliverables pending review; (3) untriaged home-inbox items. Sort by wait time.
- **Per-project Overview** reuses CC Projects' groups with non-code meanings: *Needs you / Ready for review (deliverable or draft) / Working / Idle / Resolved*.
- **Peek-and-reply** on any row. Attach opens the terminal.
- **Notification policy** per project: Request + Error by default, Complete optional.

### 8.4 Lifecycle rules
- Sessions: auto-resolve after N days idle. Resolving writes or updates the summary note. Archive never deletes the transcript.
- Tasks: done when `done_when` is satisfied (agent-checkable) **and** the human accepts. The agent can only propose done.
- Projects: health and update drafted by the home agent on the project's review cadence. Complete → `_archive/`.
- Topics: reviewed on cadence; never complete.

### 8.5 Substrate hooks we can rely on (as of Oct 2026)
- `claude agents --json`: live state, waitingFor, names, cwd. `claude --bg --name … "<prompt>"` dispatches in a folder.
- `SendMessage` / `ListAgents` / `notify_when_idle` for director↔project coordination. Inbound `hold` is useful for sessions the user is driving manually.
- Hooks (`Notification`, `Stop`, `SessionStart`, `SessionEnd` with `transcript_path`) to write summaries and update state files.
- `/goal` for done conditions. Desktop scheduled tasks or our own scheduler for routines.
- `cleanupPeriodDays` **must be raised**, or our summaries must stand alone.
- Caveat: Agent View, channels, agent teams and CC Projects are research preview, experimental or beta. Their contracts may change.

---

## 9. Open questions / things I couldn't verify
- Nimbalyst tracker storage: files vs DB. The changelog mentions DB backups, and docs live in the repo. [unverified]
- Conductor and Superset app-level state location beyond `conductor.json` / `.context/`. [unverified]
- Codex app automation definition storage (file path). Docs don't specify. [unverified]
- Claude Code Tasks (`~/.claude/tasks`) details and the reported resume bug come only from secondary sources. [unverified]
- Cowork "folder instructions": file name and format. [unverified]
- Terragon's current status (hosted service vs OSS). [unverified]
- Vibe Kanban storage (SQLite). [unverified]
