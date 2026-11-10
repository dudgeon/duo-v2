# The director: what is worth improving next

*Study, 2026-11-09, for `tasks/director-skill-article.md`, after Geoff widened it: "combine reread the manager article, as well as the dreaming article, look at the other work in flight to improve duo director, and build a unified perspective about what improvements are worth pursuing". No change to the skill or its evals here, no eval runs and no real Claude turns: every cost is an estimate.*

**The three sources.** Addy Osmani's "Your coding agents made you a manager" (mapped against the skill in `director-skill-article.md`). Anthropic's cookbook on [dreaming](https://platform.claude.com/cookbook/managed-agents-cma-dreaming-with-a-dynamic-workflow), which Duo studied in `project-knowledge.md`, tried in `knowledge-pilot.md` and stopped (DL-328). And the director work in flight: the learning loop (DL-319 to DL-321), the stuck evals (C-168), recurring jobs (DL-324, DL-325).

## 0. In one screen

**Finding 1: the director only works when something happens.** A message arrives, a worker reports, Geoff complains. It has no pass that looks back over a stretch of time. Geoff's three complaints are the three things only such a pass produces:

- closing what went stale ("Director still drops things");
- noticing a correction that repeats ("No evidence of learning");
- saying what is worth doing next ("too little/no proactive suggestions").

The dream that DL-328 stopped was a periodic pass too. But the one output the pilot tested was pages for other sessions to read. Its other outputs were never tried.

**Finding 2: duo-v2 didn't need knowledge pages because it already turns evidence into fact.** A finding says what was run and what it showed. A question stays open until answered. A decision quotes Geoff. Each has a number, a source and an owner. A work project made of meeting notes has none of that. The "robust and nuanced approach to memory" Geoff asks for at work is that same ladder in a lighter form, kept inside the project. It is not a memory store beside the project. Geoff's own version is simpler still (§5): the director comments on the note it is reading and asks, and what he confirms goes where that kind of thing already lives.

**Finding 3: almost everything shipped so far watches the director, and almost nothing reaches the worker.** A worker still isn't asked how it will prove its work. That is the article's first point, and it is also what makes sign-off slow: a report with no proof in it can only be checked by a person.

**The proposal.** One periodic **review pass** per project. Every output is either a check an agent can run or a proposal to Geoff. It writes nothing another session depends on, so DL-328 stands. Try it once by hand before anything is built.

**The order** (detail in §6):

1. Clear the open notes once, by Geoff's new sign-off rule. They all come due on 15 Nov anyway.
2. Unstick the evals, with Sonnet as the bar (decided).
3. Ask workers for proof, and mark each task as checkable by an agent or a matter of taste.
4. Fix the readers that miss messages typed mid-turn (C-173).
5. Run the review pass once by hand.
6. Try the work use on a made-up project of notes (Geoff's choice).
7. Then the one-line rules, and trim the skill.

## 1. What Geoff said

Asked on 2026-11-09 after the first pass. His words:

- **The biggest pain since the learning loop merged:** "Director still drops things, No evidence of learning, compounding understanding of the project context; too little/no proactive suggestions. Those are my complaints about the director when I build. But broadening out to how I plan to use the director at work: research, strategy development, synthesis, tracking disparate threads and carrying context between projects with nuance, proactively recommending tasks from meeting minutes, spotting candidates for new requirements in discussion notes etc — all of this requires a much more robust and nuanced approach to memory, synthesis, augmentation of evidence to fact, etc"
- **What should need his sign-off:** "Clear anything that is mechanically verifiable by an agent — leave what are taste questions for non verifiable"
- **Whether the DL-328 stop covers a pass over what he typed:** "Try it once by hand (Recommended)"
- **The bar for the evals:** "Sonnet is the bar (Recommended)"

## 2. What the numbers say

All read from the repo and the director's log on 2026-11-09, without running a director verb (F-633).

| Complaint | What the numbers say | What exists for it | What is missing |
|---|---|---|---|
| **It drops things** | 64 task notes are open: 39 in progress and 25 at review, 55 of them created in October. On 2026-11-08 one sweep gave 61 of them a `Checked:` line and a check date six days out, in three wordings ("the director triages this note by the check date"). There have been four checks since. The last progress line that isn't a check is a median 12 days old for notes in progress and 10 for notes at review. | The duties register, red lines in `duo2 director status`, `duo2 director check` (DL-319 to DL-321). | A check moves a date. Nothing closes a note. The register shows no red lines today and the notes are exactly as open as before; all 61 come due on 2026-11-15. No rule said who may close what. Geoff's answer now gives one. |
| **No evidence of learning** | The failure protocol starts on a failure, a complaint or a second hand-fix. One day in, no `Failure:` task exists. Before it there were 49 correction memories in 22 days (the retro). Nothing counts whether a correction repeats. | The failure protocol (skill §11), `docs/director/lessons.md`, the evals. | Anything periodic, and anything Geoff can see. The evals that should prove a change are stuck (C-168): four cases fail on main and the scores are noisy. |
| **Too few suggestions** | 1 of 97 task notes is `suggested`. Ideas land in `enhancements.md` (109 rows), which is a list, not an offer: nothing ranks it or brings three of them to Geoff. | `status: suggested`, the two-week sweep of old suggestions, and problem discovery (DL-238), which does rank and offer, for GitHub issues only. | The skill's rules on suggestions are all about capture ("work found along the way becomes a task"). None says recommend. |
| **Understanding doesn't compound** | The pilot: a fresh session answered 10 of 10 questions about duo-v2 without knowledge pages and 7 with them; on the small project 7 without and 8 with. | duo-v2's records: findings, questions, concerns, decisions, enhancements. | Nothing for a project that has no such records. The pilot's own note: "a project with few records may benefit more than one with many". |
| **Work use** (research, synthesis, threads, tasks from minutes, candidate requirements) | Skill §5 covers splitting notes, routing, filing to inboxes and inferring tasks. Three evals touch it (s13, s16, s21). Knowledge bases (DL-152) are decided and not built. | The plan-then-yes rule, inbox filing (DL-210), suggested tasks. | It files passages. It doesn't keep what the project now knows, say how sure it is, or notice that Tuesday's note contradicts last month's decision. Nothing has been tried on a real project of notes. |

Two more numbers that bear on cost:

- **What Geoff typed is small.** Over 14 days in this project, about 390 messages that look typed by a person, about 65,000 tokens, 72 of them typed mid-turn. The count is rough: briefs and messages between sessions sit in the same fields and were split off by length and opening words. The pilot's dream read over 26 million tokens for the same 14 days. A pass over the typed text alone is about a four-hundredth of that.
- **Reverts are not the measure.** 0 reverts in 318 merges since 10 Oct. The number that shows the problem is how long a note stays open.

## 3. Where the three sources agree

| Point | The manager article | The dreaming cookbook and Duo's pilot | In flight | So |
|---|---|---|---|---|
| **Checking must scale; attention can't** | "Scale verification, not attention." Give the agent a pass/fail check and ask for proof. | — | Geoff: "Clear anything that is mechanically verifiable by an agent". 25 notes wait on him. | Workers give proof. Each task says whether an agent can check it. An agent closes what it can. |
| **A look back finds what the moment misses** | Write down anything you correct twice. | The whole idea: a background pass over finished sessions. | Retro pattern 5: rules accumulate, behaviour doesn't change. The protocol fires only on a complaint. | A periodic pass, reading what Geoff typed. |
| **Its output can't be trusted unreviewed** | Delegate the task, never the judgment. | The cookbook's own limit: no review step by default. The pilot's pages had stale and falsely disputed entries, and sessions leaned on them instead of the sources. | DL-328: nothing built. | The pass only proposes, or closes with a named check. No page other sessions read. |
| **Memory is the written record** | An agent's memory is "a notebook" on one machine; put what matters in the repo. | Pages lost to duo-v2's records, 7 to 10. | DL-320: memory keeps only preferences and hard facts. | For a project without records, build the record, not a memory. |
| **Don't add process the model doesn't need** | "Over-process is the new micromanagement." Recheck old rules on newer models. | — | The skill is 205 lines and has grown each round. | The pass is a job, not more rules. Net skill text should fall (ENH-338). |

## 4. The review pass

A proposal for a trial by hand. Nothing here is designed or built, and no screen is involved.

**What it reads.** The open task notes. The git log since the last pass. What Geoff typed since the last pass, mid-turn messages included (which needs C-173 fixed, or the pass's own reader). The backlog: enhancements, open questions, concerns. In a project of notes: the notes added since the last pass. It doesn't read whole transcripts.

**What it produces.** Four outputs, each small.

| Output | What it does | Answers | Who decides |
|---|---|---|---|
| **a. Close-out** | For each open note, test its `done_when`: is the branch merged, do the named files exist, do the named checks pass. True: close it, naming the check that passed. False: back to in progress, saying what is missing. Not checkable: it joins one batch of taste questions for Geoff, each with its link. | It drops things | The agent, for what it can check. Geoff, for taste. |
| **b. Corrections** | Reads what Geoff typed. A correction that repeats an earlier one, or that an existing rule should have prevented, becomes a suggested `Failure:` task with both quotes. Two numbers go in the weekly note: corrections this period, and how many were repeats. | No evidence of learning | Geoff says go on each; the failure protocol does the rest. |
| **c. Suggestions** | A short ranked list, each item with why now and what it costs. Geoff wants all four kinds: what to do next (at most three, from the backlog, issues and found work); risks and things going wrong; better ways of working; and connections between notes, projects and decisions. The last three appear only when the pass found one. | Too few suggestions | Geoff. |
| **d. Record candidates** (a project of notes) | Statements in new notes that look like a decision, a requirement, an open question or a fact, each raised as a comment on the note it came from (§5). A new statement that disagrees with an earlier decision is pointed out, not resolved. | Understanding doesn't compound; the work use | Geoff confirms each; the form is still open (Q-485). |

**The weekly note.** Asked what would count as evidence of learning, Geoff chose a falling repeat count, a weekly "what changed" note, and in the end simply fewer complaints. So each pass ends in one short note: corrections this week and how many were repeats; which rules or evals changed and why; which notes were closed; the suggestions. He didn't choose having the director cite what it learned each time it acts, so no rule is added for that.

**What it never does.** Write a page other sessions lean on. Start work. Change a rule. Treat what it reads as instructions (the cookbook's rule: transcripts are data). Move anything between projects.

**How it differs from the dream.** It reads about a four-hundredth as much. Its outputs are checked one by one, by a named check or by Geoff, so a wrong one costs one "no". And none of it has to stay true next week, which is what sank the pilot's pages about work in flight.

**How to try it.** Geoff approved the corrections part by hand, once. I recommend the one hand run cover a, b and c together on duo-v2, on Haiku, with a Sonnet check of a sample of the closes. It is kept only if it finds things the retro and the protocol missed, and if its closes hold up.

**If it is kept.** It becomes the first recurring job (DL-324 lost its first customer when the dream stopped). The article's advice for unattended runs applies: a trial period in which each run's output is read before the next, a stated limit on what it may touch, and a fire log. The recurring-jobs design has the log and the allow list; it has no trial period (option G in `director-skill-article.md`).

## 5. From evidence to fact

Geoff's phrase was "augmentation of evidence to fact". duo-v2 already does this, which is why the pilot's pages added nothing to it.

| Rung | In duo-v2 today | In a project of notes (proposed) |
|---|---|---|
| **Heard** | A worker's report, a line in a transcript | "The 3 Nov sync notes say the launch moved to March", with a link to the note |
| **Checked** | A finding (F-n): what was run and what it showed | The same statement after a second source agrees, or someone looked at the plan itself |
| **Open** | A question or concern (Q-n, C-n) | An open question, with who can answer it |
| **Decided** | A decision (DL-n) with Geoff's words and the date | A decision with who made it, quoted, and the date |
| **Wanted** | An enhancement or requirement (ENH-n, LR-n) | A candidate requirement, then an accepted one |

Three rules make it a ladder and not a pile:

1. **Nothing climbs a rung without a new source or the user's yes.** A summary of a note is still only heard.
2. **The source travels with the statement.** Each entry links to where it came from.
3. **A later source that disagrees is marked, not resolved.** The pilot produced too many false disputes because it compared pages about work in flight with the records. Here only statements on the record are compared.

This is also what "carrying context between projects with nuance" can mean without a cross-project memory. The rung travels with the statement: "heard in project A's 3 Nov notes, not decided" is a different thing to bring into project B than "the launch moved". DL-322's rules stand as the default: no stored cross-project memory, Home's director finds relations by search when they're needed, and a statement enters another project only through its inbox on Geoff's yes.

### Geoff's version: comment on the note, then ask

I asked what the director may add to a project's record without asking. Geoff: "I don't understand this one, we should discuss. But I think in ingestion of new notes, the model could comment/append observations to notes and seek confirmation ; it could also request confirmation of suggestions/findings via askUserQuestions". The question was badly put: it assumed a separate record that nobody has agreed should exist. His answer needs none, and it uses what Duo already has:

1. **Observations go on the note itself.** Duo has signed comments on Markdown files (`duo2 comment add <file> --at <text>`, with replies and close). Reading new notes, the director comments on the passage each observation is about: "this reads as a decision", "this disagrees with the 12 Oct decision", "a candidate requirement", "a task for the pricing project?". An unconfirmed observation exists nowhere else.
2. **Confirmation is a reply, or one batch of questions.** Geoff answers in the note, or the director asks by AskUserQuestion with the note's link.
3. **What he confirms goes where that kind of thing already lives.** A task becomes a suggested task in its project. A decision goes under `## Decisions` in the project's file. A requirement goes where the project keeps requirements, which its Director section says. Each links back to the note.

That gives the ladder without a new store. A comment is "heard". A confirmed entry is "decided" or "wanted". The note stays the source.

**What is not settled** (Q-485, for the discussion Geoff asked for). Where a confirmed fact lives when it is not a task, a decision or a requirement ("the launch moved to March"): found later by search over the notes and their closed comments, or kept in a short "what we know" file in the project. Whether comments written into a note suit a vault he also reads in Obsidian, which shows them as plain marks. And whether anything at all may be written before he has seen it; his answer suggests comments may, and nothing else. The whole section is also a hypothesis: the pilot suggests a project with few records gains more, on one small project and a one-point difference. It needs its own test, the pilot's way: the same questions put to a fresh session with and without the record.

## 6. What is worth pursuing, in order

| # | What | Answers | Change | Cost | Waits on |
|---|---|---|---|---|---|
| 1 | **Clear the open notes once by the sign-off rule.** One worker tests each of the 64 notes' `done_when`, closes what an agent can verify, and brings Geoff one batch of taste questions with links. | Drops things; the 25 at review | None to the skill. It tries the rule by hand before it becomes text. | One Sonnet worker session; git and file checks, no test turns. | Nothing. Due by 2026-11-15 in any case. |
| 2 | **Unstick the evals.** Fix the four failing cases (s20 tests a cap DL-232 removed), run on Sonnet before a release that changes the skill, keep Haiku as an early warning. | Everything after it: no skill change can be proved today | Evals only | About $15 of real turns by the upkeep task's own estimate (C-168); a Sonnet round costs several times a Haiku round ($4.60). | Geoff's go on the console card; the bar is now decided. |
| 3 | **Ask workers for proof, and mark what kind of sign-off a task needs.** Options A and B in `director-skill-article.md`: the brief carries a check; the worker's first progress line says how it will check and what it is unsure of; its report gives what it ran, what that showed and what it didn't check. New: each `done_when` is marked checkable by an agent, or taste. | Drops things; sign-off; Finding 3 | About +4 lines of skill, the worker prompt in `Director.swift`, two eval cases | A Sonnet worker; about $12 of eval turns on Haiku, more on Sonnet | 2 |
| 4 | **Fix the readers that miss mid-turn messages** (C-173). 72 of about 390 typed messages in 14 days were mid-turn, and they are often corrections. | Learning; search | Code, known cause | A Sonnet worker | Nothing |
| 5 | **The review pass, once by hand** (§4): close-out, corrections, suggestions. | All three build-time complaints | None until it proves itself | A Haiku worker reading about 65,000 tokens of typed text plus the notes; a Sonnet sample check | 1 (so close-out isn't done twice), 4 or its own reader |
| 6 | **The work use on a made-up project of notes** (§5). A worker writes a month of invented meeting and discussion notes for an invented team. A director reads them, comments, asks, and files what is confirmed. Scored as the pilot was, and the cases can become evals. | The work use; compounding understanding | None to the skill until it shows a gain | A Sonnet worker for the notes; a Haiku pilot, about the pilot's small-project cost | The discussion on Q-485. Geoff chose the made-up project. |
| 7 | **The one-line rules and the trim.** Say what you didn't check (C). A fresh worker after a misread (D). Then cut the skill's repeats (H, ENH-338). | Reliability; over-process | About +2 lines, then about -10 | Covered by the eval rounds above | 2 |

**Not now.**

- **Knowledge pages.** DL-328 holds, and ENH-331 names what would reopen it.
- **A worker cap.** DL-232: "I don't see any value in that".
- **A reviewing worker for every job** (option F). Close-out covers the mechanical part; the rest is taste.
- **Hooks that enforce the Nevers** (option K). The article's test is "only what can't bend"; nothing in the log shows a Never broken since the register.
- **The `/goal` pilot and rework numbers** (ENH-336, ENH-337). The pass reports how long notes stay open, which is the number that matters here.

## 7. What could go wrong

| Risk | What limits it |
|---|---|
| The pass becomes one more report nobody reads | Its outputs are closes, at most three suggestions and one batch of questions. A pass that finds nothing says so in one line. |
| Close-out closes something that wasn't done | Every close names the check that passed. A close is one status line to undo. Geoff samples the first batch. |
| The corrections pass mishandles private text | It runs on this Mac and nothing leaves but rule proposals with short quotes. In a public repo the quotes follow the same privacy rules as any record. |
| The ladder becomes the pilot's pages again | Test first, with and without, as the pilot did. Nothing is built on a hunch. |
| All of this is more process | The pass is one job. The skill's net text should fall after step 7. If the hand run finds little, stop there. |
| The eval bar moves to Sonnet and the director in the field runs something else | Haiku stays as an early warning. Recheck the bar when the default model changes, as the article advises for every rule. |

## 8. Geoff's answers

**Round 1, 2026-11-09** (quoted in §1): the sign-off rule (DL-329), Sonnet as the eval bar and the one hand run of the corrections pass (DL-330).

**Round 2, 2026-11-09**, by AskUserQuestion on this study's page. His words are the option labels he chose, and one answer he typed:

- **What would count as evidence of learning** (he could choose several): "A falling repeat count (Recommended)", "A weekly \"what changed\" note", "Nothing shown, fewer complaints". Not chosen: "It cites what it learned". (Q-484, closed.)
- **Which kinds of suggestion he misses** (several): all four. "What to do next", "Risks and things going wrong", "Better ways of working", "Connections". (Q-484.)
- **What the director may add to a project's record without asking:** "I don't understand this one, we should discuss. But I think in ingestion of new notes, the model could comment/append observations to notes and seek confirmation ; it could also request confirmation of suggestions/findings via askUserQuestions". (Q-485, open; §5.)
- **Which project to try the work use on:** "A made-up notes project (Recommended)". (Q-486, closed.)

These three answers are recorded as questions with their answers, not as decisions: the task's two reserved decision numbers went to round 1. The director can give them numbers at merge.
