# Duo — Design brief for Claude Design

Version 1 · 2026-10-03 · Owner: Geoff

This is the input package for Claude Design. It describes the product, the people it's for, the information architecture, the decisions already made, the constraints, and the open questions we want the design exploration to answer. It deliberately contains **no reference visuals**: the earlier wireframes were thinking aids, not a direction to emulate. Start fresh.

---

## 0. How to use this with Claude Design

Claude Design works best when you give it context up front and then brief it in short, specific prompts, iterating on the canvas rather than front-loading one giant prompt. What it accepts and what it rewards, per Anthropic's support docs and early guides:

- **Context files, attached at any point:** screenshots and images, DOCX/PPTX/XLSX, a linked code repository, a web capture of a live site, and a saved design system. "The more context you give Claude, the better your output will be."
- **A design system first.** Anthropic's own rollout guidance says the single most important preparatory step is having a design system set up; every project then inherits it. It extracts palette, typography, components and layout patterns from a codebase, a deck, individual assets or a finished page. Tip from the docs: *"Include real examples, not just specs. A finished landing page … tells Claude more about your brand's feel than a color palette alone."* We don't have one yet, so **step 1 is to have Claude Design propose and save a design system for Duo** (Section 7 gives the direction).
- **Brief structure that works:** goal, layout, content, audience, constraints. Specific beats vague. Name real fonts and hex values rather than "modern and clean".
- **Keep the first generation short** (a few sentences), then refine with inline comments on the canvas (targeted changes), chat (structural changes) and direct edits. Comments and chat are both fed back to Claude.
- **Exports:** interactive prototype URL, standalone HTML, ZIP, PDF/PPTX, and a **handoff to Claude Code** (local or web) that packages component structure, the design tokens actually used, layout hierarchy and assets as a machine-readable spec. That handoff is the path from the chosen design into the spec and build.

### Suggested sequence

1. Create a Claude Design project "Duo". Attach this document, plus `docs/research/agent-harness-landscape.md` and `docs/research/claude-code-session-path-binding.md` for background (optional; this doc summarises what matters).
2. **Design system prompt** (Section 7). Save it as the project's design system.
3. **Concept exploration prompt** (Section 8, prompt A): four structurally different takes on the main window, one per organizing principle, each as a single screen with the sample data from Section 6. Review, comment, pick.
4. **Deepen the winner** (Section 8, prompts B–F): states, flows, secondary screens, dark mode.
5. Export the handoff bundle to Claude Code; we write the spec from it.

---

## 1. What Duo is

**Duo is a desktop app (macOS first) for product managers who do their work with Claude Code.** At its core it is a terminal running Claude Code sessions, wrapped in affordances that solve the problems PMs hit when they run many sessions across many pieces of work:

- knowing which session needs them right now,
- finding the right existing project and session instead of starting a new one in a random folder,
- keeping tasks, deliverables and conversations attached to each other,
- reviewing and editing the documents Claude produces.

It is **not** a coding tool. The work is PRDs, research synthesis, competitive teardowns, stakeholder updates, decks, specs, triage of incoming asks. Some project folders are GitHub repos; many are just folders of markdown. Nothing in the design should assume code, diffs, branches or pull requests.

**One-line positioning:** a local-first workspace where a PM's projects, tasks and Claude Code sessions stay organized in plain files they can read.

## 2. Who it's for

**Primary user:** a product manager, individually, on their own Mac. Comfortable with Claude Code in a terminal; not an engineer. Juggles several topic areas and 5–15 active projects. Runs **6 or more Claude Code sessions in parallel** on a normal day. Works in long documents, reads a lot, context-switches constantly, is interrupted by Slack and email.

**What they value:** speed of orientation ("what's waiting on me?"), confidence that nothing is lost, low ceremony, and a tool that fits the way Claude Code already works rather than imposing a new system.

**Not designing for:** teams, admins, engineers reviewing code, mobile.

## 3. Information architecture

### 3.1 The user's vocabulary

| Term | Meaning | Lifecycle |
|---|---|---|
| **Topic** | An area of responsibility (e.g. Payments, Growth, Platform). Ongoing; never "finishes". Like a GTD *Area*. | Permanent-ish. Reviewed, not completed. |
| **Project** | A related set of tasks with a common goal (e.g. "Checkout redesign"). Has a goal statement, a status/health, often a milestone. **Maps 1:1 to a Claude Code project, i.e. a folder on disk.** | Created, worked, completed or archived. |
| **Task** | A unit of work inside a project (e.g. "Draft PRD v2"). Has a human owner (the user), a state, optionally a done condition, "waiting on", dependencies. | Open → in progress → done. |
| **Session** | A Claude Code conversation, started in a project folder, resumable. The thing that actually runs in the terminal. | Created, running, idle (resumable), archived. |
| **Home** | A special-by-convention project (a plain folder, not a repo) where triage happens: incoming asks, routing to projects, cross-project status, personal ops. An emergent "director agent" pattern we want to support without forcing. | Permanent. |

### 3.2 Relationships

- Topic ⟶ contains projects. Projects live as folders, typically nested under a topic folder (`~/work/payments/checkout-redesign/`). Don't over-rotate on topics; they are light grouping, not a heavy hierarchy.
- Project ⟶ contains tasks and sessions.
- **Task ↔ Session is many-to-many.** A task can have several sessions over its life; a session can serve several tasks; a session can also be unlinked ("quick question"). Linking is explicit and cheap.
- Sessions always belong to exactly one project (the folder they were started in).
- Home is a project like any other in the data model; it may be starred/pinned and may get extra abilities (creating tasks and starting or resuming sessions in other projects).

### 3.3 Session states (the attention model)

Every session is in one of these states, and the UI organizes around them. The industry has converged on this ordering; keep it.

1. **Needs you** — waiting on an answer, approval or permission. Shows the exact pending question and how long it has waited. Longest wait first.
2. **Ready for review** — finished and produced something (a document, a draft) you haven't looked at.
3. **Working** — running; shows a one-line live summary of what it's doing.
4. **Idle** — not running, resumable. The default thing to do with an idle session is resume it.
5. **Resolved / archived** — explicitly closed or auto-resolved after long inactivity.

Tasks derive an attention state from their sessions (a task "needs you" if any of its sessions does), but **session phase is not task status**; a task can be in progress with no session running.

## 4. Behaviours the design must encourage

These are the product's reason to exist. Every concept should be judged on how naturally it produces them.

1. **Find before you create.** Existing projects and sessions must be extremely discoverable, so the user opens the right one instead of starting Claude Code in a random folder. Search/jump (⌘K-style) across projects, tasks and sessions is table stakes.
2. **New work gets a new project folder.** When a genuinely new piece of work arrives, the path of least resistance should be "create project" (which creates a folder), not "start a session wherever I am".
3. **Resume by default.** Starting a session should always show the resumable sessions for that project/task first. Proliferation of near-duplicate sessions is the failure mode.
4. **Tasks and sessions stay attached.** Linking a session to a task, or creating a session from a task, should be a one-step action. Unlinked sessions should be visible so they can be filed.
5. **Nothing is lost when folders move.** Users will rename and move project folders. The app must preserve the project ↔ session-history association through that (see Section 9). Design implication: moving/renaming a project is a first-class action in the app, and the app may need a "we noticed this project moved" moment.
6. **State lives in readable files near the work.** Project metadata, tasks and the session index are plain files in or next to the project folder (e.g. `PROJECT.md`, `tasks/*.md`, a session list), never hidden in system folders. The UI reads and writes those files; the user can too. Design implication: the UI should feel like a view over files, and it's fine to show the files.

## 5. Decisions already made

These are settled; design within them.

- **Three panes:** **left** = projects and tasks (organisation and attention), **middle** = the console (terminal running Claude Code sessions), **right** = view/edit (the document or deliverable being worked on, plus project context). A file explorer is useful but secondary; it does **not** own the left pane.
- **Fleet-board attention model.** The app must make it obvious, at a glance and across all projects, which of 6+ sessions need the user, which are working, which are done, which are idle. Sort by state, then by wait time.
- **A rich representation of the focused project** (goal, status/health, next milestone, tasks with their linked sessions, resume/new actions, key files) exists somewhere prominent, most likely in the right pane.
- **Work with Claude Code's primitives, not against them.** Project = folder. Session = resumable conversation. No parallel universe of concepts.
- **Home is supported, not mandated.** The UI must work for someone who never uses a director agent, and feel purpose-built for someone who does.

## 6. Sample content (use this, not lorem ipsum)

Claude Design does better with real content. Use this consistent fixture everywhere.

**User:** Geoff, PM. Today is Friday 3 Oct 2026, 9:40.

**Topics and projects**

| Topic | Project (folder) | Goal | Health | Next |
|---|---|---|---|---|
| Payments | `checkout-redesign` | Cut guest-checkout abandonment 15% by Q1 | On track | Exec review Oct 14 |
| Payments | `refunds-api-spec` | Ship refunds API spec to eng by Oct 10 | At risk | Spec review Oct 8 |
| Payments | `fraud-rules-review` | Audit and simplify fraud rules | On track | — |
| Growth | `onboarding-v3` | Lift day-7 activation to 40% | On track | Copy freeze Oct 6 |
| Growth | `pricing-experiment-q4` | Decide Q4 pricing test | Done pending readout | Readout Oct 7 |
| Platform | `api-deprecations` | Comms plan for v1 API sunset | Off track | — |
| — | `home` (★, not a repo) | Triage, dispatch, status, personal ops | — | Weekly status due 4pm |

**Tasks in `checkout-redesign`:** Draft PRD v2 (in progress; done when approved by eng + design) · Competitive teardown (in progress) · Align with risk team (ready to start, no session yet) · Exec review deck (blocked on Draft PRD v2) · Kickoff deck (done).

**Sessions, with state**

| Project | Session | State | Detail |
|---|---|---|---|
| home | Morning triage | **Needs you** · waited 1h | "5 new asks — route 3 to projects?" |
| onboarding-v3 | Copy review pass 2 | **Needs you** · 12m | "Approve these 6 string changes?" |
| checkout-redesign | PRD v2 edits | **Needs you** · 4m | "Two interviewees said saved cards are the main reason they abandon guest checkout; that conflicts with non-goal #2. Move saved cards into scope, or keep it out and log an open question?" |
| pricing-experiment-q4 | Results readout | Ready for review | wrote `readout.md`, 1.2k words |
| onboarding-v3 | Funnel SQL | Ready for review | 3 files |
| checkout-redesign | Teardown research | Working · 6m | Reading stripe.com/docs/checkout |
| refunds-api-spec | Edge-case matrix | Working · 14m | Writing tables in `spec.md` |
| fraud-rules-review | Rule audit | Working · 31m | — |
| home | Weekly status draft | Working · 2m | due 4pm |
| checkout-redesign | Interview synth | Idle · 2d | linked to Draft PRD v2 |
| checkout-redesign | quick q about tax rules | Idle · 3d | not linked to a task |
| … | 12 more idle | | |

**Home's triage inbox this morning:** "Legal wants a call re: saved cards" (Slack, Priya, 8:12; suggested → checkout-redesign, new task) · "1:1 notes with Dana" (Granola, 9:00; suggested → home/personal-ops) · "Refund SLA question" (routed → refunds-api-spec, task created, session started) · "Q4 pricing numbers?" (routed → pricing-experiment-q4, resumed "Results readout") · one duplicate, ignored.

**The document in focus:** `checkout-redesign/docs/prd-v2.md`, sections Problem · Goals · What we heard (just added by Claude) · Requirements · Non-goals · Open questions.

## 7. Visual direction and constraints

We have no brand yet. Ask Claude Design to propose a design system within these constraints and save it.

- **Terminal-centric, dense, calm.** The console is the heart; chrome around it should be quiet. Think the information density of Linear or Warp, not a marketing dashboard. No cards-for-the-sake-of-cards, no decorative illustration.
- **Typography:** a real monospace for the console and file paths, a compact humanist sans for UI. Name specific faces; avoid Inter/Roboto defaults.
- **Colour:** a near-neutral UI with **one** accent reserved for "needs you". Everything else communicates with weight, position and small glyphs. Light **and** dark themes; dark is the likely default for a terminal app.
- **State glyphs** for the five session states that work at 8–10px, in both themes, and without colour (shape differs).
- **Density and sizing:** macOS desktop, design at 1440×900, must hold at 1280×800. Three panes with resizable splits; the left and right panes can each collapse.
- **Motion:** minimal; state changes should be noticeable but not animated for their own sake.
- **Accessibility:** WCAG AA contrast in both themes; full keyboard operation; attention never conveyed by colour alone.
- **Tone of copy:** plain, short, no exclamation marks. Session questions are quoted verbatim.

## 8. What we want designed

Each prompt below is written to be pasted into Claude Design, in order. Keep the first generation of each short; refine on the canvas.

### Prompt A — Four concepts for the main window (explore widely)

> Design the main window of Duo, a macOS desktop app for product managers who run many Claude Code sessions at once. Three panes: projects & tasks on the left, a terminal console in the middle, a document viewer/editor on the right. Produce **four structurally different concepts**, one screen each, using the sample data in the attached brief (Section 6). Each concept should be organized around a different principle:
> 1. **by attention** — the left pane is a queue of sessions by state (needs you / ready for review / working / idle), and project structure is secondary;
> 2. **by project** — the left pane is the project list; the console and right pane belong to the selected project; attention across other projects is shown but subordinate;
> 3. **by a "Home" director agent** — the left pane is Home's triage inbox and dispatched work; Home is the first console tab; the right pane shows whatever Home is discussing;
> 4. **by task** — the left pane is tasks across all projects grouped by state; the console shows the selected task's sessions; the right pane shows the task's deliverable.
>
> Show, in every concept, where the "focused project" card lives (goal, health, next milestone, tasks with linked sessions, resume/new). Dark theme. Terminal-centric, dense, one accent colour reserved for "needs you". Don't optimise for code: no diffs, branches or PRs.

Review criteria to apply on the canvas: Does it make the 6+ session problem obvious in one glance? Does starting new work naturally land in a project folder? Is "resume" the default? Could someone who never uses Home ignore it without the layout feeling broken?

### Prompt B — Deepen the chosen concept: states

> Take concept [N]. Show the main window in five states: (1) morning, three sessions need me; (2) nothing needs me, four working; (3) a session just finished a document, ready for review, right pane shows the doc with Claude's additions marked; (4) focused on one project with two of its sessions open; (5) empty state for a brand-new install with no projects.

### Prompt C — Flows

> Design these flows as sequences of screens or overlays, keeping the three-pane window underneath:
> 1. **Jump** (⌘K): find a project, task or session by typing; recent and starred first; "create new project folder" is always one of the options.
> 2. **New work:** from an incoming ask, choose or create the project, choose or create the task, then **resume an existing session or start a new one**, with resume offered first.
> 3. **Link a session to a task** from either side (from a task: "add session"; from an unlinked session: "file under…").
> 4. **Create a project:** name, topic (folder location), goal; show the files it creates (`PROJECT.md`, `tasks/`).
> 5. **Project moved:** the app notices a project folder was renamed or moved and reconciles; design the notice and the fix action.

### Prompt D — Home / triage

> Design Home's triage inbox: incoming items from Slack, email and meeting notes, each with Home's suggested destination (project → task) and reason, with verbs Accept / Pick another / Snooze / Decline. Show the log of what Home did overnight. Show how a session Home started in another project is labelled when you encounter it elsewhere. Make it clear what Home is allowed to do.

### Prompt E — Components

> Produce a component sheet: session row/card in all five states and both themes; task row with linked-session indicators; project row with rolled-up attention; the focused-project card; console tab; quick-reply bar for answering a session without typing; the state glyph set at 8, 10 and 14px.

### Prompt F — Light theme pass

> Apply the light theme to the main window states from prompt B and fix anything that only worked in dark.

## 9. Technical realities that shape the design

Findings from our research that the design should respect (details in `docs/research/`).

- **Claude Code stores session history by the project folder's absolute path.** If a folder is renamed or moved, `claude --continue` and the session picker lose its history; resuming by explicit session ID still works. Duo will own session IDs and keep a stable project ID in a manifest file in the folder, so it can detect moves and keep the association. The UI needs a place for "project moved/renamed, re-associated" and for an explicit "move/rename project" action.
- **Session transcripts are deleted after 30 days by default.** Duo will raise retention and keep its own readable summary per session inside the project, so the design can assume long-lived history and a per-session summary line.
- **Session state is machine-readable.** Claude Code exposes per-session `working / blocked / done` and *what it is waiting for* (permission, input). The attention model can be exact, and the pending question can be shown and answered without opening the session.
- **Home is a normal folder** (`~/work/home`), not a repo. If Home gets extra abilities (create tasks, start/resume sessions in other projects), they are tools Duo provides, and every action is logged to a readable file.
- **Files are the source of truth.** `PROJECT.md` (goal, status), `tasks/*.md` with frontmatter (status, owner, waiting_on, done_when, linked sessions), and a per-project session index. The UI is a view over these; showing the file behind a UI element is encouraged.
- **Claude Code's own cloud "Projects" feature** uses the same coordinator-and-workers idea as Home and the same attention vocabulary (Ready for review / Waiting on you / Working / Idle / Resolved). Duo's difference is local, file-based and PM-shaped. Don't copy its UI; do keep the vocabulary compatible.

## 10. Out of scope for this pass

- File-tree navigation and the editor's internals (we'll do that next; just reserve a sensible place for it on the right).
- Settings, onboarding beyond "create your first project", accounts, sharing, teams.
- Anything specific to code: diffs, branches, PRs, CI.
- Mobile or web.

## 11. What we want back

1. A saved **design system** for Duo (tokens, type, components) in Claude Design.
2. The **four concept screens** with your notes on trade-offs.
3. For the chosen concept: the **state set**, the **flows**, **Home/triage**, the **component sheet**, both themes.
4. An **interactive prototype** of the main window (click between sessions, open ⌘K, run the "new work" flow).
5. The **Claude Code handoff bundle** (component spec, tokens, layout hierarchy), which we'll use to write the build spec.

---

### Sources on Claude Design inputs and workflow

- Anthropic support: [Get started with Claude Design](https://support.claude.com/en/articles/14604416-get-started-with-claude-design) · [Set up your design system](https://support.claude.com/en/articles/14604397-set-up-your-design-system-in-claude-design) · [Admin guide](https://support.claude.com/en/articles/14604406)
- [Claude Design to Claude Code handoff](https://claudefa.st/blog/guide/mechanics/claude-design-handoff) · [How to use Claude Design (Shelby AI)](https://www.shelby-ai.com/guides/how-to-use-claude-design/) · [Complete guide (tosea.ai)](https://tosea.ai/blog/claude-design-complete-guide) · [Prompt tips (Techsy)](https://techsy.io/en/blog/claude-design-tutorial) · [Charlie Hills on the launch](https://charliehills.substack.com/p/anthropic-just-dropped-claude-design)
