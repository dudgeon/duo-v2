# The director as a product

*Design study, 2026-10-12, version 4 (simplified). It replaces the 23-decision draft at commit 3d3d368, which is kept in git history with the full research notes. Builds on [director-agent.md](director-agent.md) and the director skill we run (`.claude/skills/director/SKILL.md`). The test harness is designed in [director-test-harness.md](director-test-harness.md). Geoff's answers will be recorded as DL-n, open questions as Q-n. Decision page: https://claude.ai/artifact/4S3xjcdySNGxytxvJMrz8Q. Nothing is built yet.*

## What Geoff asked for (2026-10-12)

1. A director skill that ships with Duo, installs at user scope and updates through the app.
2. It works in one project, or across Home.
3. It is managed like a product, with features, tests and measures.
4. It uses rich primitives (messaging, hooks), with solid fallbacks on pinned or locked-down clients. That includes his work Mac, which runs Claude Code 2.1.219 and allows no Claude artifacts.
5. The director we use to build Duo shares the same core.
6. It takes Claude Code Projects' patterns, with UX compatible enough that users can move to Projects later.
7. Tasks are the primitive directors orient to:
   - task folders hold a task's files;
   - the director encourages projects and tasks where they fit;
   - changing tasks is in scope, with his approval.
8. Round 4: "consider how we don't want to overfit to coding tasks or make the director or tasks primitives constricting in their conventions … simplify as needed."

## The idea in one paragraph

A director is a Claude session that takes work from you, turns each piece into a **Duo task**, starts a worker session for it, checks what comes back against what you asked for, and brings you only real decisions. Everything it needs to remember lives in things Duo already has:
- the project's brief (`PROJECT.md`) for how to work here;
- task notes for each piece of work;
- an optional task folder for its files;
- Duo's own session states for who is doing what.

Richer Claude Code features make it faster: messages that wake a session, background sessions, phone links. Without them it still works, by typing into a worker for you to send, or by asking you to. Nothing in it assumes the work is code. A code project adds checks, branches and merges on top, as the project's own guidance says.

## Round 4: what I dropped from my own draft

| Dropped | Why |
|---|---|
| A `DIRECTOR.md` overlay file | The project brief (`PROJECT.md`) already is the project's instructions; one more file per project is clutter. |
| A project memory folder | A new convention for a problem only worktree workers have. Project facts go in the brief's Notes; Claude Code's own memory does the rest. Revisit if workers miss knowledge. |
| `reports/` and `messages/` subfolders, and the "every message is a file first" mailbox | A worker's report is its last message, which Duo can already read. The task note's Progress is the record. A task folder is just a folder for files. |
| The Stop-hook inbox rung | Complex, and hooks may be disabled exactly where it would matter. Old clients use headless turns, or Duo types and you press Enter. |
| Heartbeat leases | Ownership is the task's `directed_by`. Taking over means rewriting it. |
| A compute lock and number reservations in the core | These are our needs. They stay in Duo dev's own guidance until a user asks. |
| Setup and teardown per worktree, a ready list, claims | Coding-shaped or pool-shaped machinery (see the Beads answer). |
| A mandatory three-part task note; "done never reopens" | Constricting. The note stays the user's; the director adds one Brief section and appends Progress. |
| Thirteen `duo2 director` verbs | Five are enough. |
| Export to Projects in v1 | Later. The shapes stay compatible now, so it's cheap when wanted. |
| Coding words in the core ("merge", "land", "review gate") | The core says **accept** the work, and **check** it against what was asked. A code project's guidance says accepting means merging and checking means its tests. |

## Decisions for Geoff

Ten decisions, each with my recommendation first. They merge the earlier letters as follows:

| Decision | Earlier letters |
|---|---|
| 1 | A, I, K, L |
| 2 | N, T, O, W |
| 3 | Beads |
| 4 | S |
| 5 | B |
| 6 | C, E |
| 7 | F, R |
| 8 | G, V |
| 9 | H, U, M |
| 10 | J, P, Q |

### 1. How it ships

**Recommended: one skill, `duo-director`, written and kept current by Duo at user scope, under the `duo2` skill's rules.** Duo regenerates it at launch unless you've edited it, and `duo2 uninstall` removes it.

Project-specific guidance comes from what the project already has:
- its brief (`PROJECT.md`), with an optional `## Director` section for standing rules, such as "you may accept checked work without asking";
- its `CLAUDE.md`;
- its project skills.

**Your preferences for every director on this Mac** live in a local file the skill reads and Duo never writes over, `~/.claude/duo-director.md` (Geoff, 2026-10-14: preferences kept in the skill would be wiped by its updates). A project's `## Director` rules win over it where they disagree. **Decided: DL-193.**

**It doesn't depend on `PROJECT.md` being there or being full** (Geoff, 2026-10-13: "most projects will not initially have a project.md, and often the project.md will be sparse"). A missing or thin `PROJECT.md` is normal, and the director works from what you tell it. It doesn't fill gaps with guesses. Instead it grows the file in two ways:
- **Proposals you accept.** When it notices a standing rule or a fact worth keeping ("always ask before publishing", "the goal is a draft by Friday"), it proposes the addition by AskUserQuestion, and only writes it if you accept. That includes creating `PROJECT.md` (Make a Project) when there isn't one.
- **A record of your decisions.** Decisions you make while it directs are appended with their date to a section of `PROJECT.md` (for example `## Decisions`), so later sessions see what you chose and why, rather than the director's own conclusions.

**Duo dev's extras live in our project's skill folder** as references and scripts: releases, the walk page, the design system, the voice repo, records, the GPU lock. The "Duo dev director" is the shipped skill plus those. This is the shape Geoff described: "the duo dev specific context is just an additional ref or set of scripts, but the instruction set is common".

**The deterministic parts are five `duo2 director` verbs,** tested in DuoChecks:

| Verb | What it does |
|---|---|
| `status` | Who is directing, what's in flight, and what this client can do |
| `start` | Creates a task and its worker, within the cap |
| `send` | Reaches a worker the best way available, and logs it |
| `retire` | Retires the current director |
| `guide` | Prints the skill's text, for clients where user skills are blocked |

**The name:** "Director" in Duo, and `duo-director` as the skill. Not `director`, because a user-scope skill silently replaces a project skill of the same name.

**Other options:**
- a `DIRECTOR.md` overlay per project (my earlier recommendation; one more file);
- a fork for Duo dev (users would get the director from before our lessons).

### 2. Tasks are the unit of work

**Recommended: one delegated piece of work is one Duo task, with light conventions.**

- **The brief.** The director adds a `## Brief` section to the note: your words verbatim, plus anything it was told not to decide. It also fills the existing `done_when:` key. Duo's hooks already tell every linked session "its note is the task's brief" (DL-116).
- **Progress.** The director appends `## Progress`, one dated line per step: what it asked, what came back, what it checked.
- **Ownership.** `directed_by:` links the director session.
- **Propose first.** New work is proposed as `status: suggested`. Duo already shows an unknown status as its own column, so this works today. You start it, and it moves on.
- **Files.** A task folder `tasks/<slug>/` beside the note, made only when the task has files: inputs, deliverables, a `decisions.md`. Nothing is prescribed inside it.
- **The rest is yours.** Everything else in the note stays yours: no restructuring, and reopening or moving it is as free as for any task.
- **Playbooks.** A brief that worked can be saved as a task template (Duo's templates, DL-146). This is Devin's "playbooks", at no cost.
- **Encouragement.** The director encourages tasks and projects:
  - it turns a request into a task before starting work;
  - it offers Make a Task for sessions doing task-sized work;
  - it offers Make a Project for folders that have sessions but no brief;
  - it keeps the project's `goal` and `next` current.

**Other options:**
- a fixed three-part note (Brief / Facts & decisions / Progress), which is constricting;
- a ledger separate from tasks, which means two lists of work.

### 3. What to take from Beads

Beads is an issue tracker for coding agents, kept in a Dolt database. It has:
- hash ids;
- links between issues (blocks, parent, discovered-from);
- a `ready` query for work with no open blockers;
- an atomic claim;
- priorities;
- compaction of old closed issues;
- messages stored as issues.

**Recommended: take one behaviour and nothing structural.**

- **Take: found work becomes a suggested task.** A worker that notices other work says so in its report. The director files it as `status: suggested`, with a link back to where it was found (Beads' "discovered-from"). Nothing gets lost in a report, and you decide whether it's worth doing. No new field: the link goes in the note's body or `references:`.
- **Already there: dependencies.** Duo's task format has `depends_on:` (links to other tasks) and `waiting_on:`. The director writes them when they're real and reads them before starting work.
- **Not worth it:**

  | Beads feature | Why we don't need it |
  |---|---|
  | `ready` list | With a few tasks in flight the director reads the notes. A query earns its place only with dozens of agents pulling from a pool. |
  | Atomic claims | Our workers don't pull work; the director assigns it. |
  | Hash ids | Slugs and Duo's `id:` already avoid collisions. |
  | Priorities | Order is computed on the board (DL-148). A second ordering would need keeping in sync. |
  | Compaction | Done tasks are archived; the director reads only open ones. |
  | Messages as issues | Progress covers it. |
  | Dolt | Plain notes are the point. |

- **Push back.** Most of Beads exists because its agents share one pool of issues with no coordinator. A director is the coordinator, so that machinery has no job here.

**Other options:**
- also show `depends_on` as a "blocked" mark on the board (cheap; a later task-board change);
- add priorities.

### 4. Changes to tasks' UX, for a design round

Each change is designed on a canvas with Geoff before it's built. Until then, the director runs on the conventions in decision 2.

- **S1, the folder follows its note.** Rename, move, archive and delete carry `tasks/<slug>/` along. A card shows when its task has a folder.
- **S2, directed tasks.** "Directed by …" on the card and the note. The suggested column comes first whenever it has cards.
- **S3, actions on a directed task.** Start (for suggested tasks), Open worker, Send back (with a note), Accept, Resolve. These are the buttons users know from Projects and from parallel-agent tools, in Duo's form. Each is a `duo2 task …` verb that tells the director, as from you.
- **S4, Direct this.** On a session or task, it hands the work to the project's director. This is Projects' "Continue as project".
- **S5, decisions in Duo.** A director's `decisions.md` with open boxes raises Needs you, and ticking a box tells the director.

**Recommended order:** S1 and S2 first, since they're small and make the conventions visible. Then S3. Then S4 and S5.

### 5. Where it works: a project, or Home

**Recommended: the same skill in both.**
- In a project, it directs that project.
- In Home, it sees every project and directs work directly in projects without their own director.
- A project's director takes precedence. Home never directs another director's workers; it asks that director.

**Other options:**
- Home works only through project directors: cleaner, but needs a director in every small project;
- Home directs everything: forty projects in one context.

### 6. One owner per worker, and restarts

**Recommended: a worker is directed only by the director named on its task.**
- Sessions not on a director's task are yours, and a director never tasks them.
- When you type into a worker, the director stops messaging it until you hand it back.
- **A director is started with an explicit name,** `director-<project>`. Evidence (harness doc, P3): a name given with `-n` survived a stop and a background resume on 2.1.296. The session id changed, though, and an unnamed session's derived name (`duo-v2-ef` → `duo-v2-b0`) changes on every restart. That is how the old name went stale.
- `.duo/director.json` names the current director: its name, its current session id, and the retired ones. A retired director that wakes stands down and points to the new one. That would have prevented the `*DUO DIRECTOR*` incident.
- Workers find the director through `duo2 director status`, and otherwise reply to whoever messaged them last.

**Other options:**
- heartbeat leases: more machinery than the problem needs;
- the name alone, with no registry: two sessions can share a name, and the id moves on a resume.

### 7. How it talks to you

**Recommended: the same everywhere, the work Mac included.**
1. **One question:** asked in its own session (AskUserQuestion, which works in Duo and on the phone through Remote Control), with Needs you raised in Duo.
2. **Several decisions at once:** a `decisions.md` in the task folder. Each decision has a heading, the options as checkboxes with the recommendation first, and a Notes line. Tick it in Duo's editor or in Obsidian.
3. **A page, where Claude artifacts exist and you want one:** like this page, with Send buttons. Answers are written back into `decisions.md`.

The file is always the record; the page is a mirror.

**For us:** this page is the test of whether Send reaches the session reliably, since the console's taps stopped arriving after Oct 9. If your Sends arrive, a page with buttons stays our default for batches of decisions. If not, we go back to AskUserQuestion, one question at a time.

**Other options:**
- artifacts first: fails at work;
- chat only: decisions get lost in scrollback.

### 8. Workers

**Recommended:**
- **Where they run.** Users' workers run in Duo by default, so you see them. They run in the background when you ask, when Duo isn't running, or for long jobs. Ours run in the background with Remote Control (already decided); design work stays in Duo.
- **One worker per task by default.** Parallel workers only for work that splits cleanly: separate files, research, tests. Anything that shares decisions runs one at a time. Cognition: "actions carry implicit decisions". Anthropic: several agents cost about 15 times the tokens of a chat.
- **A cap of 3 workers per director** by default. `duo2 director start` enforces it, and the brief's Director section can change it.
- **A worktree** only for code in a git repo.
- **The model is your default** unless the project's guidance says otherwise. Duo itself never picks one.

**Other options:**
- background by default;
- fan out freely up to the cap.

### 9. Accepting work

**Recommended:**
- **Check before accepting.** The director checks what came back against the brief and `done_when`. For code, it runs the project's checks too. It never passes on a claim it hasn't checked.
- **You say go.** It proposes acceptance, saying what it checked. A standing rule in the brief can let it accept checked work itself; our own dev director has one.
- **Anything public or hard to undo always waits for you:** a push, a release, publishing, sending a message.
- **Stalls.** When a worker makes no progress, or fails the same way twice, the director tries at most twice: a nudge, then a clearer brief. Then it sets the task to `waiting` with the reason, and asks you. (Stripe's Minions cap retries at two; Magentic-One replans after two stalls.)
- **Messages from workers.** A worker's message is never your approval. A worker can't get the director to do what its own permissions refused.

**Other options:**
- accept checked work by default;
- no retry cap.

### 10. Claude Code Projects

**Recommended: take its patterns, keep Duo's words, and stand down where Projects runs.**

Each Projects concept has one Duo home, so a move later is a copy, not a rethink:

| Projects | Duo |
|---|---|
| Instructions | The brief and `CLAUDE.md` |
| Memory | The brief's Notes, plus Claude Code's memory |
| Threads | Tasks |
| Suggested threads | The suggested column |
| Library | Task folders |
| Status groups | Columns |
| Card buttons | S3 |
| "Continue as project" | S4 |

An export can come when someone wants it. In a repo you run as a Projects project, the Duo director starts nothing, and says so.

**Other options:**
- rename Duo's columns to Projects' words: changes a built UI for users who don't have Projects;
- a memory folder now.

### 11. Finishing and archiving tasks

Geoff, 2026-10-13: one task per worker means tasks stack up, so the director must be diligent about marking tasks complete and archiving them. Both need the user's say-so and must be reversible. Completed tasks are listed in the `PROJECT.md` log, and the director scans that log before starting new work, in case an existing task has context it needs.

**Recommended:**
- **Mark complete.** When the director has checked a task's work (decision 9) and you've accepted it, it proposes "mark complete" by AskUserQuestion, several tasks to a question when there are several. On yes it runs `duo2 task status <task> done`, which writes `status: done` and `completed:` and is undone by `duo2 undo` or by setting the status back.
- **Archive.** It proposes archiving completed tasks the same way: right after completion, and in a sweep when it starts, for anything done and not yet archived. On yes, `duo2 task archive`. Its sessions are archived too, never a running one. `duo2 task unarchive` or `duo2 undo` reverses it.
- **Where archived tasks go.** Keep Duo's archive as built (DL-115): the note gets `archived: true` and stays in `tasks/`. It leaves the lists and counts, stays searchable, and shows in the project's Archived fold with Unarchive Task. Nothing moves, so links, the task's folder and Obsidian's view all keep working.
- **The log.** On completion, the director appends one dated line to a `## Done` section of `PROJECT.md`: a link to the task (Copy Link's `duo2://task/<id>` form, which survives renames and moves), and what came of it in a sentence. It creates the section the first time it's needed, and the line is part of what you approve.
- **Scan before new work.** Before writing a new task, the director reads `## Done` and `## Decisions`, and opens any archived task that looks related, so that it reuses context rather than redoing work. The new task links to the old one in its Request when it does.

**Other options:**
- **Move archived notes to `tasks/archive/`** (with their folders). This is what Geoff literally described. It changes DL-115 and the task scanner, and breaks plain path links. Worth it only if a cluttered `tasks/` folder in Finder or Obsidian is the real problem.
- Archive without asking once you've accepted the work, still undoable. Faster, but against "require user input".

### 12. When sessions can't message each other

Geoff, 2026-10-14: "I'm concerned we are not yet talking about graceful fallbacks when the client Claude code does not support session to session messaging, which feels like a critical piece of functionality. What is the work-around?"

The ladder below under Commitments does fall back, but on a client without messaging (the pinned 2.1.219 has no `SendMessage`, no inbox and no idle notices) its working rung for reaching a live worker was "Duo types the message and you press Enter". That stalls the director whenever you're away, which defeats the point.

**Recommended: Duo carries the messages.** Duo already owns the workers' terminals, reads their transcripts and knows each session's state, so it can do the three jobs messaging does:
- **Director to worker.** `duo2 director send <task> "<text>"`. For a worker in Duo, Duo types the text into the worker's prompt and submits it, but only when all of these hold: the session is on a task this director directs, Claude is idle with an empty prompt, and you haven't typed there recently (decision 6). That's the check Duo's model chip already makes before it sends `/model` (DL-168). If the worker isn't running, Duo resumes it in its tab with the text as its first prompt. A background worker that has stopped gets a headless turn (`claude -p --resume <id>`), never while its process is running. Otherwise the text waits in the task note's Progress, and the send is retried when the worker next goes idle.
- **Worker to director.** The worker doesn't need to send anything. It ends its turn with its report as its last message and writes progress in the task note. Duo sees it go idle and reads that message (`duo2 session show`).
- **Waking the director.** The director runs Monitor on `duo2 director watch`, which prints one line whenever one of its workers goes idle, needs you, or its task note changes. Monitor and ScheduleWakeup are in 2.1.219's code (seen in the binary; a harness run confirms they work). Without Monitor, ScheduleWakeup checks `duo2 director status` every few minutes. Without either, Duo types a one-line "worker finished" into the director's own prompt, under the same idle rules. Last of all, your next message.
- **If hooks are switched off** (Q-192), Duo tells a session's state from its transcript and screen instead.

On a client with messaging, `SendMessage` and idle notices come first and Duo's route is the fallback. Every send is logged with the route it took. A director outside Duo, on a client without messaging, can only use headless turns for stopped workers and asks you for the rest, so on such clients its workers start in Duo (decision 8 already makes that the default).

New ground: Duo would submit a prompt on the director's behalf. Today Duo only types and leaves the Enter to you (`duo2 send text`), and its hooks never send a turn (DL-116). Recommended limits: only into sessions on a task this director directs, only when idle, and each one logged in the task's Progress.

**Other options:**
- Keep "Duo types it, you press Enter": safe, but the director waits on you for every message.
- A file mailbox the worker reads at each turn through a hook: dropped earlier, because hooks may be off exactly where this matters.

## Commitments that aren't questions

**It works on every client.** At start, `duo2 director status` sees what this session can do. Each job then has a ladder, best rung first:
- **Reaching a worker:**
  1. `SendMessage`;
  2. resuming into a background session (2.1.285+);
  3. a headless turn (`claude -p --resume`), for workers it started that way;
  4. Duo submits it into an idle worker in Duo, or resumes a stopped one with it (decision 12);
  5. it asks you to pass it on.
- **Hearing back:**
  1. `SendMessage`;
  2. the idle notice;
  3. Duo's session state plus the worker's last message (`duo2 session show`).
- **Waking itself:**
  1. the idle notice;
  2. Monitor on `duo2 director watch`;
  3. ScheduleWakeup;
  4. Duo types a one-line notice into the director when it's idle;
  5. your next message.

On the work Mac: AskUserQuestion, `decisions.md` and the bottom rungs, with nothing scripted.

**It's measured** from a log that the `duo2 director` verbs write as a side effect:
- decisions asked versus answered, and the time to answer;
- questions asked twice;
- two directors on one worker;
- messages sent to a wrong address;
- tasks unaccounted for after a compaction;
- claims checked;
- which rung each send used;
- the time from a report to acceptance;
- cost per task.

**It's tested** as [director-test-harness.md](director-test-harness.md) describes:
1. a stand-in `claude` plus settings that switch features off, at no token cost;
2. scenario evals on Haiku;
3. running it on Duo every day.

## Appendix A: what Projects and other orchestrators taught (rounds 2 and 3, condensed)

- **Claude Code Projects** (docs read 2026-10-12).
  - Patterns taken:
    - one conversation to talk to;
    - routing ("answer here, new thread, or existing thread, and say which");
    - suggested threads;
    - setup recommendations;
    - status groups;
    - card buttons;
    - approvals made in the thread itself;
    - a status prompt ("what you asked, what it assumed, what it's waiting on");
    - instructions and memory;
    - a worktree per thread;
    - "Continue as project";
    - pause and restart.
  - User complaints the design answers:
    - briefs lost to summarising (#97924);
    - a coordinator that only relays;
    - the coordinator's session id changing (#100714);
    - local threads missing memory (#97464);
    - caps that are only preferences.
  - There's no import or API, so compatibility is in shape.
- **BMAD.** A human-driven chain of personas. Its lasting idea, a self-contained story file for a fresh session, is our task note. We skip the personas.
- **Goose.** Delegation inside one process, with no durable record. Its "lead/worker" setting is model routing.
- **Stripe's Minions.** Fixed checks around the agent, two retries, and a human review of every PR. This confirms decision 9. HazyResearch's Minions is unrelated.
- **Gas Town.** A warning about role sprawl. Keep only "one acceptance at a time" and "a plan you approve first".
- **Beads.** See decision 3.
- **Parallel-agent tools** (Vibe Kanban, Conductor, Claude Squad, Cursor, Codex, …). These are a person handing out work, and they set the conventions users expect: one workspace per task, a review column, a chat per task, and Accept / Send back / Retry. Devin alone has a coordinator, with playbooks. None of the sources shows a tool that gates acceptance on approval or enforces one owner per worker.
- **Frameworks and write-ups.**
  - Magentic-One: a ledger of facts and plan, a ledger of progress, and a replan after two stalls.
  - Anthropic: briefs with an objective, an output, sources and boundaries; effort scaled to the job; poor fit where work shares context.
  - Cognition: one thread per piece of work.
  - MAST: missing or wrong verification is the leading failure.
  - A2A: its task states map onto our columns.
- **Not taken:**
  - personas and role hierarchies;
  - group chats;
  - handing control to a worker;
  - graph databases, daemons, YAML workflows and VM fleets;
  - running the same task N ways;
  - auto-accept;
  - new columns.

## Appendix B: capability matrix

| Setup | Start a worker | Reach it | Hear back | Ask you | Phone |
|---|---|---|---|---|---|
| Current CLI | Duo or background | SendMessage | SendMessage, idle notice | All three ways | Remote Control |
| Pinned 2.1.219 (work Mac) | Duo; background unless disabled | Headless turn, or Duo types + you press Enter | Duo state + last message | AskUserQuestion, `decisions.md` | If allowed |
| Messaging off | Same | Resume into background (2.1.285+), headless, or Duo types | Duo state + last message | Same | Same |
| No background sessions | Duo, or headless turns | Same | Same | Same | Same |
| Remote Control off | Same | Same | Same | At the Mac | None |
| Hooks disabled | Same | Same | Duo state from beacons + last message | Same | Same |
| No artifacts | Same | Same | Same | AskUserQuestion, `decisions.md` | Same |
| Sandboxed | Same; a worktree worker also gets its task folder as an added directory | SendMessage works; Bash can't reach sockets | Same | Same | Same |
| Claude Code Projects | Stands down in that repo | | | | |

## Open questions (they become Q-n once answers are in)

- How the harness's real runs log in without copying credentials (harness doc: `plugin eval` now; a `claude setup-token` token for multi-session runs, which Geoff would make once).
- Whether Duo's session states hold up when management disables hooks.
- The designs for S1–S5.
