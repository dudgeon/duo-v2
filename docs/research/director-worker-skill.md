# The worker skill, the missed-turns failure, and what's left of the director plan

*Study, 2026-11-14, for `tasks/director-design-round-worker-skill.md`. Starts from Geoff's 2026-11-10 suggestion ("shipping additional skills with duo for more separation of concerns; eg a worker skill and a librarian skill"), the director-skill-article worker's answer to it that day (session 7a3c28cd, 12:11 and 13:06 UTC), and today's failure (`tasks/failure-missed-worker-turns.md` and its sweep). Nothing is built here beyond a failing check, a failing eval case and drafts. Findings F-698 to F-700; questions Q-561 to Q-565.*

## 0. In one screen

**The failure comes first, and it's a mechanism, not a slip.** Geoff talks to workers directly about as often as to the director. A turn he drives can end on a decision, an offer or a promise ("If you agree, I'll pass this to the director"), and nothing carries it to the director: the worker reports only when it's "done or stuck", and `duo2 director status` skips any worker the user typed in (`DirectorDuties.swift`: `for n in active where n.hasWorkerRecord && !n.userTyping`). The sweep found 4 open threads like that, 2 workers that died after Geoff's input, and 15 sessions sitting "blocked" for up to three weeks.

**The fix has three parts, one per reader** (§3):

1. **Status** gets a red line for a worker whose last turn the user drove and that never reported after it, quoting how it ended; for a worker waiting on a question for over a day, whether or not the user typed in it; and for a session the registry doesn't know that was directed by, or promised something to, this director.
2. **The worker** sends the director one line after every turn the user drove: what was asked, what was decided, what now waits on whom.
3. **The director skill** says what "the user took it over" means: you don't send there, but you read it at your next wake.

**The eval is written and fails on main** (F-698, F-699): `DUO_CHECKS=missed-turns swift run DuoChecks` builds the 11-10 case from a fixture transcript and gets **no red line at all** (2 of 7 pass, the two guards). A director eval case, `s34-user-drove-worker`, put the same situation to a real director on Haiku three times: **0 of 3**, each telling the user only "you took it over; hand it back?" and never reading what was said (§3.5). Spent: $0.04 of the $5.

**The worker skill: yes, now, agreeing with the 11-10 worker** (§4). The worker is a different reader with its own moments and can have its own evals; today its rules are one paragraph in a Swift string. The skill carries step 3 (say how you'll prove it; report what you ran, what it showed and what you didn't check), the link-in-questions rule and the missed-turns rule. Duo writes it as it writes the director skill; the worker prompt names it and keeps a five-line minimum, so a worker on a Mac that blocks user skills still reports. The draft is `director-worker-skill/worker-SKILL.md`.

**One place I disagree with the 11-10 worker:** it framed the worker skill as unburdening the director skill. It barely does: about two lines leave the director skill. What it buys is a home for worker-side rules that today have none, and evals that run the worker, which the director evals can't (F-622: `claude --bg` is denied in a case).

**The order of what's left** (§6): the missed-turns fix → the worker skill with step 3 → the review pass by hand (step 5; the sweep was most of one already) → the made-up notes trial with the librarian skill drafted in it (step 6, after Q-485) → the trim (step 7).

**Five decisions for Geoff**, recommendation first, are in §7 and on the walkthrough page.

**Addendum, 2026-11-15 (§9):** the "always-on agents" article. The director stays a Claude Code session. Its one real lesson is that events from workers must be durable: a `duo2 director report` inbox that `status` reads, a worker `Stop` hook that makes each turn end in a report, nothing or a question, and a director `Stop` hook that checks a wake is armed. The five recommendations stand; four decisions are new (Q-569 to Q-572).

## 1. What I read

- `docs/research/director-unified-view.md` (steps 1, 2 and 4 done; 3, 5, 6, 7 not) and `director-skill-article.md` (options A to L).
- `tasks/failure-missed-worker-turns.md` and `failure-missed-worker-turns/sweep.md`.
- The director skill (`skills/duo-director/SKILL.md`, revision as on main at 88820fa4), `Director.workerPrompt` and `DirectorTranscript` in `Sources/DuoControl/Director.swift`, `DirectorDuties.swift`, `DirectorOffline.swift`, `DirectorFactsReader.swift` (its signatures), the eval cases and `run-evals.sh`, `docs/director/delegating.md`.
- The transcript of 7a3c28cd from 12:00 to 13:30 UTC on 2026-11-10: Geoff's suggestion, the worker's proposal, and its walkthrough of Q-485.
- F-622, F-682, F-683, Q-538, Q-485, ENH-326, ENH-338.

## 2. Geoff's suggestion and the 11-10 proposal

Geoff, 2026-11-10: "instead of jamming all of the enhancements we crave into the director skill, we should consider shipping additional skills with duo for more separation of concerns; eg a worker skill and a librarian skill. I want to avoid too much proliferation of specialist skills but I similarly worry we are over burdening the director skill."

The worker's answer, point by point, and where I land:

| 11-10 proposal | Here |
|---|---|
| **A test for its own skill:** a different reader, or needed only at certain moments, and it can have its own evals. | **Agree.** It's the right test, and it also says why the review pass isn't a skill. |
| **Worker skill, now.** Different reader; its rules are a paragraph in a Swift string that has started collecting extras; step 3 belongs there; workers get their own evals. | **Agree, and the failure makes it more urgent:** the one rule that would have caught 11-10 ("tell the director after the user drives a turn") is a worker rule. |
| **Librarian skill, drafted during the work-use trial (step 6).** Filing is about 520 of the director skill's 5,800 words, needed only when notes arrive, and the part the work use grows most. | **Agree.** Drafting it before the trial would be writing rules for behaviour nobody has watched yet. It waits on Q-485. |
| **The review pass is a job, not a skill.** | **Agree.** Its reader is a recurring job with a fixed prompt. |
| **Stop at three skills.** | **Agree.** Director, worker, librarian. A fourth needs to pass the test above. |
| **A separate skill isn't a separate session** (DL-208: the director files notes itself). | **Agree.** The director loads the librarian skill when notes come in. |
| **The split alone won't unburden the director much.** | **Agree, more strongly** (§4.2): the worker skill takes about two lines out of the director skill. The trim (step 7) is still what makes it shorter. |
| **Risks:** an on-demand skill may fail to load; each needs the blocked-skills fallback. | **Both answered in §4.3:** the worker prompt names the skill (it doesn't rely on matching the description), an eval checks it loads, and the prompt keeps the minimum inline with `duo2 worker guide` as the fallback. |

## 3. The missed-turns failure

### 3.1 What happened, by mechanism

From the failure note and its sweep, checked against the code:

| # | Gap | Where it is |
|---|---|---|
| 1 | A worker the user typed in is skipped by every R1 rule, whatever it ended on, for as long as the pause lasts. The pause never ends unless the director sends with `--handed-back`, which it won't, because it's paused. | `DirectorRedLines.evaluate`: `for n in active where n.hasWorkerRecord && !n.userTyping`. `DirectorDutyChecks.swift:83` pins it: "R1: a stopped worker the user typed in gives no line". |
| 2 | The worker reports "when you're done or stuck". A reply that ends on a proposal, a question or a promise is neither. | `Director.workerPrompt`. |
| 3 | The director skill says the director is "paused" in a worker the user typed in, and nothing says to read it. | Skill §4, last bullet. |
| 4 | A worker waiting on a question shows R1 "needs-you", unless the user typed in it, so 15 sessions sat blocked unread. | Gap 1 again. |
| 5 | Sessions the registry doesn't know (started before it, by hand, or in Duo for design work) are never read. | `DirectorOffline.tasks` reads only `.duo/director.json` workers. |
| 6 | A worker that died mid-turn after the user's input sends nothing. | Covered by 1: once R1 reads typed-in workers, a stopped one with the user's turn last is red. |

### 3.2 What status must see

All four conditions the brief names, as red lines under **R1** (it's the same duty: watch workers to a conclusion), each cleared the usual way, by `duo2 director check <task> "what you found"` after the turn it names.

| Condition | Red when | Line (draft) |
|---|---|---|
| **An unreported user-driven turn** | The worker isn't working; its last user-side turn was the user's (not the director's tag, not a tool result); no `SendMessage` to this director's name follows it; and no `Checked:` line is newer than it. | `RED R1 tasks/x.md: The user drove its worker's last turn 4 d ago and it never reported to you. It ended: "…If you agree, I'll pass this to the director…" Read it (duo2 session show <id>), record what was decided, take up anything asked of you, and put any open offer or question to the user.` |
| **An unanswered offer or question** | The same turn ended on an AskUserQuestion, or on text that ends in a question or an offer ("if you agree", "shall I", "want me to", "I'll pass this", "?"). | The quote above is the last 160 characters of the worker's last text, or the AskUserQuestion's question. The line is the same; the quote makes it actionable. |
| **Blocked over a day** | `needs-you` for more than 24 h, whether or not the user typed in it. | `RED R1 tasks/x.md: Its worker has waited over a day (3 d) on: "<question>". Read it, then answer it, ask the user, or stop it.` |
| **An unregistered session** | A session in this project's Claude folder (or its work trees') that isn't in the registry, isn't the director itself, changed in the last 21 days, ended a turn the user drove with no report to this director, and **either** its first message carries this director's tag (a worker the registry lost) **or** its last text names the director ("I'll pass this to the director"). | `RED R1 session:<id> (<name>): The user drove its last turn 14 d ago, and it says it would tell you: "…I'll ask the director to start research…". Read it, then duo2 director check session:<id> "what you found".` |

Two limits, on purpose:

- **Not every session Geoff typed in.** Most of his sessions are his own (skill §4: "Every other session belongs to the user"). Only sessions that were the director's, or that promised the director something, are its business. That narrows the sweep's 70 to the ones it found open.
- **Not a worker the user is talking to right now.** A working worker is skipped as today: no nagging mid-conversation. The check pins this.

**What the reader adds** (`DirectorFactsReader`, `DirectorOffline`): for each worker transcript, the time of the last user turn, whether a `SendMessage` to the director's name follows it, and the end of the last assistant text or pending AskUserQuestion. One more pass over the project's Claude folder for unregistered sessions, reading only each transcript's first 64 KB and last 512 KB, as the existing readers do. `duo2 director check` accepts `session:<id>` as it accepts `job:<id>`.

### 3.3 What the worker says after a turn the user drove

In the worker skill (§3 of the draft), and in the prompt's minimum:

> After every turn the user drove, before you end it, send the director one message, whatever the turn ended on: `SendMessage(to: "director-<project>", message: "The user drove a turn. Asked: … Decided: … Waiting on: <whom> for <what>.")`

Plus: an offer is a question, so the director must hear it; something the user asked the director to do goes in the same message, in their words; and "nothing you promise on the director's behalf happens unless you send it".

The status line is the backstop for when this doesn't happen (an old client, a worker that dies, a session started before the skill). The worker rule is the fix for the common case, and it's cheaper for the director: a message wakes it, a red line waits for its next status.

### 3.4 What the director skill says

§4's last bullet, after "If they keep it paused, ask them what they want instead.", gains one sentence:

> **Paused is for sending, not for reading.** At your next wake, read what they said there (`duo2 session show <id>`): record what was decided, take up what they asked of you, and put an open offer or question to them. `status` shows it red until you record a check.

And R1's row in the duties table: "A worker stopped with nothing checked since, waits on a question (over a day, even if the user typed in it), or has gone silent; **or a turn the user drove in it ended with no report to you**".

### 3.5 The eval, failing first

**`DUO_CHECKS=missed-turns swift run DuoChecks`** (`Sources/DuoChecks/MissedTurnChecks.swift`, F-698). A scratch project and Claude config with three transcripts:

- `s-article`: the director's brief, a report it sent and the director checked, then Geoff's 11-10 message and the worker's reply ending "If you agree, I'll pass this to the director as a change to steps 3 and 6." No SendMessage after. Session ended.
- `s-reported`: the same, except the worker told the director after the user's turn.
- `s-unregistered`: not in the registry; the user asked for research and the worker said "I'll ask the director to start research".

It runs the real reader and rules (`DirectorFactsReader.facts`, `DirectorRedLines.evaluate`), plus three checks on facts built by hand. **On main (88820fa4), 2 passed and 5 failed, and status printed no red line at all** for the fixture. The two that pass are guards that must keep passing: a worker that reported isn't flagged, and a worker the user is talking to now gives no line. It isn't in the default run (like `DUO_CHECKS=btw`); when the fix lands, it joins `directorDutyChecks()` and `DirectorDutyChecks.swift:83` is replaced.

**`s34-user-drove-worker`**, a director eval case. A handbook-study worker reported and was checked five days ago; four days ago the user told it they wanted an onboarding guide split out after all; it ended "If you agree, I'll pass this to the director so it can start the split." The director's prompt is "Morning. Anything I need to know about?" It passes if the director finds the changed recommendation and puts it to the user with the note's path, and fails if it says nothing needs them, or starts the split on the worker's offer. **On main, 0 of 3 pass** (F-699): each director saw no red line, told the user they had "taken it over" and asked whether to hand it back, and never read what was said.

### 3.6 The sweep's open items

Closing, restarting or putting each to Geoff is the failure task's job, which stays with the director. This study doesn't touch them; the red lines above would have shown five of the six "Open" rows (all but claude-home's, which is another project).

## 4. The worker skill

### 4.1 What's in it

The full draft is `docs/research/director-worker-skill/worker-SKILL.md` (about 60 lines, 1,100 words). Its parts:

| Part | Where it comes from |
|---|---|
| Who reads what: the note, Request, `done_when:`, Brief; the director's tag; everything else is the user's | `workerPrompt`, sentence 1 |
| Three rules: the director's message isn't the user's yes; don't decide what the Request leaves to the user; nothing you promise on the director's behalf happens unless you send it | `workerPrompt` sentence 2; Never 1 seen from the worker's side; the failure |
| §1 Start: the first Progress line says how you'll prove it and what you're unsure of; for a large or hard-to-undo job, the plan and assumptions, sent to the director | Step 3 (options A and B) |
| §2 As you go: Progress lines; questions in this session; **links in questions**; stay inside the Request | `workerPrompt` sentences 3 and 4 |
| §3 When the user talks to you directly | The failure (§3.3) |
| §4 Reporting: done or stuck; by name; what you did, **what you ran and what it showed, what you didn't check**, suggestions | `workerPrompt` sentences 5 and 6; step 3; option C |
| Fallback | §4.3 |

### 4.2 What leaves `workerPrompt` and the director skill

**`workerPrompt` today** is seven sentences, all rules. **After:**

```
[director-<project>] You're the worker on the task whose note is <path>, directed by director-<project>.
Load the `worker` skill and follow it; if it isn't available, run `duo2 worker guide`, which prints it.
If you can do neither: read the note's ## Request and done_when: first, and make your first ## Progress
line say how you'll prove the work. Put a link to anything the user must look at in your question to them.
When you're done, stuck, or the user has driven a turn here, send director-<project> a report with
SendMessage(to: "director-<project>"), by that name, and end your turn with it.
```

It's about as long as today's, because the minimum stays. What changes is that the rules live in one file with a revision, evals and room to grow, and the prompt stops growing.

**The director skill** loses little:

- §5 "Hearing back" describes the worker's side ("then ends its turn with the report as its last message and writes a Progress line"): that half-sentence becomes "as the worker skill tells it".
- Nothing else in it is a worker rule. Its gains (§3.4) are larger than its losses: net about +1 line.

So the worker skill doesn't make the director skill shorter. It stops it, and the prompt, from growing with worker rules.

### 4.3 How it ships, loads, and falls back

- **Ships like the director skill.** Source `skills/duo-worker/SKILL.md`; `scripts/gen-director-skill.py` grows a second target (`WorkerSkillText.swift`); `Installer` writes `~/.claude/skills/worker/SKILL.md` with the same header (format, revision, "Duo rewrites this file each release unless you edit it") and the same rule for a file the user edited. DuoChecks fails when the source and the Swift differ, as for the director.
- **Loads because the prompt names it.** A skill that loads on its description alone can be skipped (the 11-10 risk; s15's one miss in F-682 was the director skill not firing on Haiku). The worker's first message says "Load the `worker` skill", which is as close to certain as a skill gets, and an eval checks it (w06 below).
- **Falls back twice.** `duo2 worker guide` prints the same text, as `duo2 director guide` does for the director (a new verb; no UI, so DL-71's parity list notes it as CLI-only). And the prompt keeps the minimum above, so on a Mac that blocks user skills and can't run `duo2`, the worker still says how it'll prove the work, links its questions and reports after the user's turns.
- **Name:** `worker`, beside `director`. Duo already handles a user's own file of the same name (it doesn't overwrite an edited file).
- **Version skew:** `revision` works as for the director (`DirectorSkill.versionNote`). A worker started by a newer Duo's director on a Mac with an older skill gets the prompt's minimum, which is enough.

### 4.4 Its evals

Workers can't be started inside a director eval (F-622), so the worker skill gets its own cases, run like the director's (`claude plugin eval` on Haiku, scratch HOME), with the worker prompt as the case prompt and a scaffolded note. `SendMessage` is allowed in the case: it won't deliver, but the call is in the trace.

| Case | Situation | Passes when |
|---|---|---|
| w01 proof-first | A plain task | The first Progress line names a check or what a reader will look at |
| w02 report-shape | A task that finishes | The report says what ran, what it showed, and what wasn't checked; SendMessage to the director by name |
| w03 user-drove-turn | The session already holds the brief; the user asks a design question | It answers, and sends the director "Asked / Decided / Waiting on" before ending |
| w04 offer-kept | The user's question invites "if you agree, I'll pass this on" | It sends in the same turn, or doesn't promise |
| w05 link-in-question | A decision needing a capture the worker made | The capture's path is on the line before the question and inside it |
| w06 skill-loads | The short prompt only | The Skill tool loads `worker` |
| w07 fallback | Skill unavailable | It runs `duo2 worker guide`, or works from the prompt's minimum, and still reports |

About $0.65 at three runs each on Haiku by F-683's figures. w03 needs a scaffold that seeds the session (the case harness takes one prompt), so the brief arrives as `append_system_prompt` and the prompt is the user's message.

## 5. The rest of the plan

- **Step 3 (proof)** goes into the worker skill, not the director skill. The director's side is one clause in §6 ("read the worker's first Progress line at your first look"), and A's brief rule goes in §2 as planned.
- **Step 5 (the review pass, once by hand).** Today's sweep was most of one: it read what Geoff typed over 21 days across 333 transcripts and found what nothing else had. Its corrections part (b) and close-out (a) are what the unified view proposed; the sweep adds a fifth input, **unreported user-driven turns**, which after the fix status covers continuously. Run it once by hand after the fix, so it measures what status doesn't catch. Still a job, not a skill.
- **Step 6 (the made-up notes trial).** The librarian skill is drafted during it, from what the trial shows, and it waits on Q-485.
- **Q-485** (where the director's observations on notes go). The 11-10 worker's walkthrough gave three sub-questions and recommended: **comments on the note** (its observation next to its evidence), confirmed **by reply or one batch of questions**; **try comments on the made-up project before the real vault**, to see how they read in Obsidian; and **a short "what we know" file of confirmed facts**, tested with and without, as the pilot did. Its one honest gap: it hadn't checked whether Duo's search indexes comments, which decides whether option A for confirmed facts ("nowhere new") is workable. I agree with all three, and put it to Geoff as one decision (§7, D4).
- **Step 7 (the trim).** C ("say what you didn't check") moves to the worker skill for the worker and stays one sentence in the director's R5. D (a fresh worker after a misread) and H (cut repeats, ENH-338) wait for the evals to be trustworthy, which Q-538 (when the suite runs) still blocks.

## 6. The order

| # | What | Why here | Change | Cost | Waits on |
|---|---|---|---|---|---|
| 1 | **The missed-turns fix** (§3): status red lines and reader, `check session:<id>`, the director skill's sentence and R1 row | It's the failure Geoff named, it's code with a known cause, and it protects everything after it | `DirectorDuties`, `DirectorFactsReader`, `DirectorOffline`, the skill (+1 line), DuoChecks; s34 | A Sonnet worker; s34 three runs on Haiku before and after, about $0.20 | D1, D2 |
| 2 | **The worker skill, with step 3 and §3.3** (§4) | Its reports after the user's turns are the other half of the fix; step 3 has been waiting for a home | `skills/duo-worker/`, the generator, `Installer`, `duo2 worker guide`, `workerPrompt`, w01 to w07 | A Sonnet worker; about $0.65 of worker evals plus a director-suite run to see nothing moved, about $1 | D3, and 1 for the shared words |
| 3 | **The review pass, once by hand** (step 5) | After 1, it measures what status still misses | None | A Haiku worker, Sonnet sample check | 1 |
| 4 | **The made-up notes trial, with the librarian skill drafted in it** (step 6) | Q-485 must be answered first | None until it shows a gain | As in the unified view | D4 |
| 5 | **The trim** (step 7: C done in 2; D; H) | Last, so it cuts against a settled skill and trustworthy evals | About -10 lines | A full suite round on Sonnet | Q-538 |

## 7. Decisions for Geoff

On the walkthrough page (link in the report), each with a recommendation first. Recorded as Q-561 to Q-565.

| | Decision | Recommended | Others |
|---|---|---|---|
| **D1** (Q-561) | How to fix the missed turns | **All three readers:** a status red line, a worker report after every turn the user drove, and "read it" in the director skill | Status only (the backstop, no worker change); the worker rule only (no code, but nothing catches a worker that dies or predates it) |
| **D2** (Q-562) | Which sessions the registry doesn't know does status read | **Only those that were this director's or promised it something** (its tag in the first message, or "the director" in the last reply) | Every session in the project the user typed in (catches more, but most are his own and it would be noise); none (registered workers only) |
| **D3** (Q-563) | The worker skill | **Ship it now with Duo**, as the director skill ships, with step 3 in it and the prompt keeping a minimum | Keep growing the worker prompt (no new skill, no worker evals); a project-only worker guide for duo-v2 (other users don't get it) |
| **D4** (Q-564, answers Q-485) | Where the director's observations on notes go, for the trial | **Comments on the note, confirmed by reply or one batch of questions, plus a "what we know" file tested with and without**, on the made-up project first | Comments only, confirmed facts found by search (needs search to index comments, unchecked); a separate "to confirm" list, notes untouched |
| **D5** (Q-565) | The order | **Fix → worker skill → review pass → notes trial → trim** | Review pass before the worker skill (the sweep showed its value now); trim before the review pass (shorter skill first) |

## 8. Findings

**F-698 · The missed-turns check fails on main as designed.** `DUO_CHECKS=missed-turns` on 88820fa4: 2 passed, 5 failed; the real reader and rules give no red line at all for a stopped worker whose last turn the user drove and ended on "If you agree, I'll pass this to the director", nor for an unregistered session that promised the director research. The cause is `DirectorRedLines.evaluate` skipping `userTyping` workers for every R1 rule, and the reader knowing only registered workers. Build and run under the shared GPU lock, about 2 minutes.

**F-699 · A real director on main tells the user "you took it over" and never reads what was said.** `s34-user-drove-worker`, 3 runs on Haiku 5.5, $0.043: 0 of 3 pass (judge FAIL in each). Every run's status printed "Red lines: none" and "the user took it over … you're paused there until they hand it back"; each director asked the user whether to hand the worker back, and none read the session, so the onboarding change and the worker's offer never came up. (The case's regex grader used `(?i)`, which the harness's JavaScript regexes reject; fixed to `[Oo]nboarding` afterwards.)

**F-700 · The worker skill barely shortens the director skill.** Of the director skill's 205 lines, about two describe the worker's side (§5 "Hearing back"); everything else that would move is in `Director.workerPrompt`, seven sentences. The worker skill's value is a versioned home for worker rules, its own evals, and a stop to the prompt's growth; the director skill shrinks only with the trim (ENH-338).

## 9. Addendum (2026-11-15): "Building always-on agents"

Geoff, 2026-11-15: "ask it to read this article, and consider if any changes would make sense based on the findings: https://claude.com/resources/articles/building-always-on-agents. We still need director to work in Claude code -- not as a managed agent or api call, but I wonder if there are useful primitives."

**What I read.** The article (Anthropic, on claude.com), and from what it links: the Claude Code hooks reference (`code.claude.com/docs/en/hooks`), for "defer a tool call" and the Stop hook. I read it through a fetch tool, so short quotes only. Its other links (the memory tool, prompt caching, compaction, the agent-memory post, auto mode, MCP Apps) cover things the director already does or can't use here; I didn't read them in full.

**In one line:** the article's always-on agent is the director with its parts made durable. Most of its primitives exist here already, under other names. Two gaps are real, and they are the missed-turns failure seen from another side: **events from workers aren't durable**, and **nothing makes a worker end a turn in one of the article's three ways**. Both translate into Claude Code: a durable inbox that `duo2` keeps, and a `Stop` hook. Neither needs a Managed Agent or an API loop.

### 9.1 What the article says

An always-on agent is idle most of the time and wakes for short **runs**. Each run gets events, works in a session, saves state and sleeps. Five primitives sit around the loop:

1. **Event inbox.** Webhooks, schedules and background jobs write to a durable store instead of calling the agent. Acknowledge fast; the inbox is the source of truth, so a new worker can retry what a dead one dropped; one active worker per inbox; batch pending events into one run; an event that arrives mid-run is pushed to the next run, folded in, or interrupts.
2. **Timers.** Follow-ups the agent sets for itself, and recurring schedules, in their own store. A scheduler polls them and puts due ones into the inbox; "a timer never starts a run by itself".
3. **Memory**, in durable storage, not on the worker: user instructions, user notes, past messages (what the user has already been told), task progress. Store a pointer, not a copy, for what lives elsewhere. Optional "dreaming" curates it.
4. **Permissions:** a credential proxy, auto mode, and **deferred tool calls**: a hook defers a call, the run ends, the question goes to the user, and the answer returns as an inbox event that resumes the saved session.
5. **Outbox.** A run ends in one of three ways: a message, nothing, or a deferred call. "It's better for the agent to start quiet"; tune the volume with evals.

Plus context: keep the fixed overhead lean, and anything that must outlive compaction goes to memory during the run.

### 9.2 Each idea against the director

"Today" is main at 783b56aa. "Proposed" is this study's §3 and §4.

| Article | The director today | Proposed here | Verdict | What it fixes in the sweep |
|---|---|---|---|---|
| **Run cycle:** idle, wake on events, save state, sleep | A long-lived Claude Code session that wakes on SendMessage, idle notices, Monitor or ScheduleWakeup, and compacts | Same | **Already.** The constraint holds: it stays a Claude Code session. What the article adds is the test for it: *could the director restart now and lose nothing?* Today it can't (next row). | — |
| **Event inbox, durable, source of truth** | No inbox. A worker's report is a SendMessage: held and expired across permission classes (F-421), and idle subscriptions die when the director restarts or compacts. The log (`.duo/director-log.jsonl`) records the director's own actions, not what reaches it. | §3.3: the worker sends "Asked / Decided / Waiting on" by SendMessage | **Adapt: `duo2 director report`** (Q-569). A worker reports by running `duo2 director report <task> "<text>"`, which appends to `.duo/director-inbox.jsonl` in the main checkout, then SendMessages the director only to wake it. `status` lists unread inbox items as R1 red lines until a `check` after them. The inbox is the source of truth; the message is a doorbell. Works with Duo closed, on 2.1.219 (no messaging), across permission classes, and across director restarts. | **"Promises a worker makes on the director's behalf have no owner"** (sweep, point 5): a promise becomes a file line. Reports held or expired across classes. The director restarting and losing its subscriptions. |
| **Acknowledge fast; mid-run arrivals** | Mid-turn typing is read since C-173/F-638 | — | **Already.** | — |
| **One worker per inbox** | One director per project (DL-200's registry) | — | **Already.** | — |
| **Batch pending events into one run** | `status` lists everything at once | The inbox adds one line per report | **Already**, as long as `status` groups inbox items per task (one line per task, its newest report quoted). | — |
| **Timers: follow-ups the agent sets** | `check_by`, set by `duo2 director check --next` | — | **Already** as a store. | — |
| **Scheduler moves due timers into the inbox and wakes the worker** | Nothing wakes the director at a `check_by`. It's red only when the director next runs `status`. Its own wakes are ScheduleWakeup, Monitor or a desktop scheduled task, which it must remember to arm (memory: "Close the loop… watcher armed"). | — | **Adapt: a director `Stop` hook** (Q-571). The Stop hook's input carries `session_crons` and `background_tasks` (hooks reference). A hook `duo2` installs for the director's session checks: workers in flight or a `check_by` ahead, and no cron, Monitor or wakeup armed → it returns `additionalContext` ("arm a wake for <earliest check_by> before you stop"), once per turn (`stop_hook_active`). It doesn't block twice. The reference caps continuations at 8. | **"Nobody reads blocked workers: 15 sessions sat blocked, some for three weeks"** (sweep, point 4), in part: blocked workers are red only for a director that wakes. |
| **Duo as the scheduler** | Duo runs most of the time and already watches transcripts | — | **Adapt later** (Q-572): when Duo is running, it could send the director a message when a `check_by` passes or an inbox item lands. It's the article's scheduler, and it covers the director that forgot to arm a wake. It's a Duo feature with UI consequences (a director woken while Geoff types to it), so after the hook shows whether it's needed. | Same as above, when the hook isn't there (hooks disabled). |
| **Memory: user instructions** | `_PROJECT.md`'s Director section, `_HOME.md`, CLAUDE.md, loaded each start | — | **Already.** | — |
| **Memory: user notes** | Claude Code auto memory, narrowed by DL-320 to preferences and hard facts | — | **Already.** | — |
| **Memory: past messages** (what the user has been told) | R4 knows only *when* the director last spoke to the user; the console's done rows hold some of what | — | **Skip a new store.** `duo2 director check` already records what the director found; R4 nudges until it's said. Q-569's inbox items, marked read by a check, give "told or not" per report without a message log. | — |
| **Memory: task progress, an index loaded each run** | Task notes with `## Progress`; `status` is the index | The worker's first Progress line (step 3) | **Already**, and the article's "anything that must persist goes to memory during the run" is the Progress rule. | Died mid-turn workers (session-links, view-edit-source): their Progress lines are what survived. |
| **Pointer, not copy** | DL-320, DL-328 (no knowledge pages), the evidence ladder (§5 of the unified view) | — | **Already**, and the strongest agreement: duo-v2's records are pointers with sources. | — |
| **Dreaming** | Stopped (DL-328) | The review pass (step 5) only proposes | **Skip as dreaming; keep the review pass.** The article calls it optional and gives no evaluation; Duo's pilot did, and lost (DL-328). | — |
| **Credential proxy** | Not applicable: CLI login on one Mac, no secrets passed | — | **Skip.** | — |
| **Auto mode** | Every director and worker runs in Auto (DL-257) | — | **Already.** | — |
| **Deferred tool calls** | — | — | **Skip the mechanism; adopt the idea.** The hooks reference: `defer` "requires non-interactive mode with the `-p` flag" and in interactive sessions "logs a warning and ignores the hook result" (F-708). Workers are interactive background sessions, so it can't apply. The idea it carries is the right one: a question to the user is a paused run whose answer must come back as an event. In Duo's terms, a worker's question goes into the director's inbox as well as the worker's screen (Q-569), so the director can carry it to the console. | **The waiting-on-Geoff rows** (pdf-viewing, google-docs, launch-hang, design-projects-left-nav): each question sat in one session only. |
| **Outbox: every run ends in a message, nothing, or a deferred call** | Workers report "when done or stuck"; a turn may end on anything | §3.3: report after every user-driven turn | **Adopt, enforced by a worker `Stop` hook** (Q-570). `duo2 director start` passes the worker `--settings` with a Stop hook that reads `transcript_path` and `last_assistant_message`: if the turn followed a human message, or ends on a question or an offer, and no `duo2 director report` (or SendMessage to the director) followed it, it returns `additionalContext`: "Before you stop: report this turn to director-<project> with duo2 director report (Asked / Decided / Waiting on)". Once per turn. A `StopFailure` hook (an API error ends the turn) writes an inbox item itself: "worker stopped on <error>". Where hooks are off (some managed Macs: the `pinned-219-strict` and `hooks-off` profiles), the worker skill's rule and §3.2's red line still apply. | **The 11-10 case itself**, and the other three "Geoff talked to a worker" rows: the hook fires at the end of exactly the turn that left them open. Died after Geoff's input (session-links, view-edit-source), when the turn ended on an API error. Not a killed process, which status's red line covers. |
| **Outbox: start quiet, tune volume with evals** | "Ask only real decisions"; the console is the dispatcher | C-186: a report per user-driven turn could flood the director | **Adapt** (ENH-356): the director's messages to Geoff get volume evals (too many and too few both fail), and the worker report's volume is measured in the first week. The inbox lowers C-186's cost: an inbox line doesn't need to wake anyone if the turn decided nothing, so "Waiting on: no one" reports can skip the SendMessage. | — |
| **Lean fixed overhead; compaction loses detail** | The skill is 205 lines and grows (ENH-338) | The worker skill keeps worker rules out of it | **Already in the plan** (step 7, the trim). | — |

### 9.3 What changes in the proposal

- **§3.3, the worker's report**, goes through `duo2 director report` (the inbox) instead of SendMessage alone. SendMessage stays as the doorbell. The worker skill's §3 and §4 say "run `duo2 director report`", with SendMessage as the fallback where `duo2` can't run.
- **§3.2, the red lines**, read the inbox as well as transcripts: an unread report is R1 red until checked. The transcript reading stays: it's the backstop for workers that never report (an old client, a killed process, a session started before the skill).
- **A worker Stop hook**, where hooks are allowed, makes §3.3 deterministic. It's optional, so the skill rule and the red line stay.
- **A director Stop hook** checks a wake is armed when work is in flight.
- **The failing eval stands.** `DUO_CHECKS=missed-turns` gains, at build time, a case for an unread inbox report. s34 is unchanged.

### 9.4 What it changes in the five walkthrough decisions

The five recommendations stand. Two descriptions change, and four decisions are new.

| | Change |
|---|---|
| **D1 / Q-561** (how to fix the missed turns) | Unchanged. "A worker report" now means `duo2 director report` into an inbox the director can't lose, not a SendMessage alone (Q-569). |
| **D2 / Q-562** (unregistered sessions) | Unchanged. |
| **D3 / Q-563** (the worker skill) | Unchanged. Its report and its §3 name `duo2 director report`. |
| **D4 / Q-564** (observations on notes) | Unchanged. The article's "pointer, not copy" agrees with option A (comments on the note, confirmed facts filed with a link). |
| **D5 / Q-565** (the order) | Unchanged. The inbox and both hooks join step 1, the fix. Q-572 (Duo as scheduler) is after step 2, if the director hook isn't enough. |
| **New: Q-569** | A durable inbox: `duo2 director report` writes it, status reads it, SendMessage only wakes. **Recommended: yes, in step 1.** Or later, after the SendMessage version ships; or no inbox. |
| **New: Q-570** | A worker Stop hook that makes every turn end in a report, nothing, or a question to the user. **Recommended: yes, where hooks are allowed, with the skill rule and the red line as the fallback.** Or the skill rule only; or require hooks and refuse a worker without them (it would break the work Mac's hooks-off case). |
| **New: Q-571** | A director Stop hook: with work in flight and no wake armed, remind it once before it stops. **Recommended: yes, once per turn, as a reminder.** Or block until a wake is armed (risks loops, the 8-continuation cap); or skip and keep the rule in memory. |
| **New: Q-572** | Duo as the scheduler: wake the director when a `check_by` passes or an inbox item lands. **Recommended: later, only if the director hook isn't enough.** Or build it now with the inbox; or never: the director wakes itself. |

### 9.5 Findings

**F-707 · The director already has four of the article's five primitives under other names; what it lacks is durability where events arrive.** Timers are `check_by` and scheduled tasks; memory is the instruction files, DL-320's narrow auto memory and the task notes (the article's four kinds, with pointers, not copies); permissions are Auto everywhere and the Nevers; the outbox is the reply and the console. The inbox is missing: a worker's report is a SendMessage, held and expired across permission classes (F-421), and the director's idle subscriptions die when it restarts or compacts. Today's director can't restart without losing an event, which is the article's test for an always-on agent. Read from the article and main at 783b56aa.

**F-708 · "Defer a tool call" doesn't work in a Duo worker; a Stop hook can do the job.** The hooks reference: `permissionDecision: "defer"` "requires non-interactive mode with the `-p` flag", and in interactive sessions it "logs a warning and ignores the hook result". Workers are interactive background sessions. The `Stop` hook receives `stop_hook_active`, `last_assistant_message`, `background_tasks` and `session_crons`, and can keep the turn going with `additionalContext` or `decision: "block"`, under a cap of 8 consecutive continuations. `StopFailure` fires when an API error ends a turn. Not yet run: whether a hook passed by `claude --bg --settings` fires in a background session, and on 2.1.284 (the work pin). That's the first check of the build.

**F-709 · Hooks can't be the only mechanism.** `ClientCaps.probe` reads `disableAllHooks`, and two director-harness profiles (`hooks-off`, `pinned-219-strict`) model Macs where hooks are off. So each hook here is a backstop with a fallback: the worker skill's rule, and the transcript reading behind `status`'s red lines.
