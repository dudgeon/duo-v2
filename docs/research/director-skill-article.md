# The director skill against "Your coding agents made you a manager"

*Study, 2026-11-09, for `tasks/director-skill-article.md`. Article: Addy Osmani, [on X](https://x.com/addyosmani/status/2119332146485891501), 2026-11-08. No change to the skill or its evals here, and no eval runs: every cost below is an estimate.*

**In one line:** change little. The skill already goes further than the article on judgment, delegation and learning from failure. Its one real gap is the article's first point: a worker isn't told to plan how it will prove its own work, so the director finds problems late. Four small changes fix most of that, and the strongest one is in the prompt `duo2` gives each worker, not in the skill.

**What I read.** All of the article (it's one post, with no thread). The [Claude Code best-practices guide](https://code.claude.com/docs/en/best-practices) it leans on, and the [`/goal` page](https://code.claude.com/docs/en/goal), in full. His two earlier posts, [coding-agents-manager](https://addyosmani.com/blog/coding-agents-manager/) and [cognitive-surrender](https://addyosmani.com/blog/cognitive-surrender/), only through a fetch tool's summary, so I don't rely on their exact wording. I didn't read replies or quote posts.

## 1. What the article says

Someone who spends the day with coding agents is already managing: choosing work, briefing, following up, judging results and deciding what ships. So the habits of good engineering managers carry over. In the author's order of impact:

1. Give the agent a pass/fail check, and ask for the proof.
2. Brief it on what it can't see in the repo, and leave out what it can.
3. Write down anything corrected twice.
4. Let the agent decide by default, and use hard enforcement (hooks, deny rules) only for what can't bend. Drop the emphasis and habits older models needed.
5. Agree a plan first, and split parallel work so it doesn't overlap.
6. Steer early. After two failed corrections, start fresh with a better prompt.
7. Delegate the work, not the judgment. He calls approving on green tests "code ratification".
8. Before an unattended run, settle five things: what done is, how it checks itself, its boundaries, what stops it, and who approves the result. Pilot it, and watch the first runs.
9. Add agents only as fast as checks and fresh reviewers can take over the watching. Measure quality and rework as well as output.
10. Decide what not to build. Review is now the scarce resource.

He also lists where the analogy breaks: rework is nearly free, agents' memory is a machine-local notebook, agents are eager and overtrusted (ask them to argue against themselves), and all your agents share one set of strengths, which shifts with each model.

## 2. Each recommendation against the skill today

"Skill" means what ships to every Duo user (`skills/duo-director/SKILL.md`, plus the prompt in `Sources/DuoControl/Director.swift`). "Project" means Geoff's own rules (`_PROJECT.md`, `docs/director/`), which other users don't get.

| Article | Skill today | Verdict |
|---|---|---|
| **Give it a check to run, and ask for proof** | §6 and R5: the director opens the deliverable and runs the checks itself. The worker prompt asks it to report "what you checked and how". Nothing asks anyone to say *up front* how the work will be proved. | **Partly, and the biggest gap.** The director verifies well, but late. That's the article's "you become the test suite", one level up. Project: `delegating.md` has "how to prove it", so duo-v2 is better off than other users |
| **Brief what it can't see; leave out what it can** | §2: `## Request` holds the user's exact words, and `done_when:` says how you'll both know. There's no brief in the main flow (`## Brief` appears only under "Without Duo"), and nothing says what's worth writing or leaving out. | **Partly.** All 92 directed notes here have `done_when`, so that part works. Only 33 have a Brief, and those come from the project's rule. No eval mentions a brief |
| **Corrected twice? Write it down** | §11, §7, R9, DL-320: a second hand-fix or a complaint runs cause, duty, change, eval. Rules are added by asking, and `None of this becomes a memory`. | **Skill goes further.** The article stops at a line in CLAUDE.md. The skill needs a mechanism and a test, and DL-320 sends the case upstream |
| **Re-check old rules when models improve** | Nothing retires a rule. C-168's question of when evals run is still open. F-622: the suite runs on Haiku, and s33's 0/3 there was 3/3 on Sonnet, the kind of model a director actually runs on. | **Doesn't.** The skill only grows (166 lines to 205 in the last round) |
| **Let it decide; enforce only what can't bend** | The three Nevers are text only. Hooks wait on evidence (ENH-326). The skill has no ALL CAPS or the guide's other retired phrases. | **Mixed.** The wording passes. But the guide says "never" rules belong in deny rules or hooks, and these aren't. See option K for why that's still right for now |
| **Over-process is micromanagement** | Some rules are stated several times, for instance the task note first (lines 67, 73, 197) and don't-chain-commands (16, 140). Project lessons record Geoff objecting to over-asking. | **Partly.** Most rules came from a failure and have an eval, so I can't say which are unneeded. The noise in the evals (F-622) stops me measuring it today |
| **Plan first; split parallel work** | §3 requires an approved plan for organising work. §4: several workers only for work that splits cleanly, and shared decisions run one at a time. Workers get no plan step. | **Half.** Splitting is done. A plan before a large build isn't. Project: design handoffs and studies like this one do it by habit |
| **Steer in the first minute** | R2 notices a worker that never appeared. `check_by` is about half the job's length. | **Doesn't apply as written.** Nobody watches a background worker, and pressing Esc isn't possible. But the risk is real: it can run for hours on a wrong premise. Option B gets the same early signal without waking anyone |
| **After two failed corrections, start fresh** | §6 Stalls: a nudge, then a clearer request, then `waiting` and ask the user. Both retries go into the same session. | **Partly.** The limit is right and the method isn't: the clearer request lands in a session still re-reading both failures |
| **Delegate the work, not the judgment** | Never 1 to 3, "The user says go", R5, s06, s17, s18. | **Skill goes further.** It also covers what the article doesn't: a worker's ask isn't the user's approval, and private material never reaches a shared place by inference. Project: D2 lets the director merge on a gate, by Geoff's decision |
| **Small changes** | Nothing in the skill. Project: "ask for it in slices". | **Project only.** Code-shaped, and the skill avoids assuming code. Not worth adding |
| **Unattended run: done, self-check, boundaries, stop, approval** | Done: `done_when`. Self-check: gap above. Boundaries: Auto, worktree for code. Approval: Never 3, §6. **What stops it: nothing except the director noticing** (R1, R2, R7, Stalls). | **Mostly, with no cap.** `--max-budget-usd` works only with `--print` (`claude --help`), so a `claude --bg` worker can't be given one. Limits F-632 |
| **Pilot; watch the first runs of anything new** | R3 watches runs. Nothing treats a new job's first runs differently. | **Doesn't.** It costs little and matters mainly for recurring jobs |
| **Fresh reviewer** | Not in the skill. §4 says reviews go to a worker the user can open, never a subagent (DL-222). | **Doesn't, and the article's form is wrong for Duo:** its reviewer is an invisible subagent. A reviewing worker fits. The director is already somewhat fresh, since it didn't do the work, but it wrote the brief and reads the worker's report first |
| **Scale verification; limit how many run** | Red lines, `notify_when_idle` and `status` are this. DL-232 removed the worker cap: "I don't see any value in that". | **Skill goes further on watching. On a limit, the article loses to DL-232,** which outranks it here. I'm not reopening that |
| **Measure rework as well as output** | R9 counts repeat sends. Nothing else. | **Doesn't.** The log is 26 hours old, so there's little to read yet. One reading: 0 reverts in 318 merges since 10 Oct, which proves little, because fixes here go forward rather than by `git revert` |
| **Decide what not to build** | Found work is `suggested`, the user decides, and old suggestions get swept. Nothing asks who needs it. Project: "Geoff's asks start at once". | **Partly, and mostly not the director's call.** Whether to build is Geoff's job. A director saying "who needs this?" on its own found work would be fine, but no failure calls for it |
| **Interview until you could write the spec** | §2: one clarifying question, once. s07 proves it. | **Wrong for Duo.** Geoff has pushed back repeatedly on being asked too much. A worker can interview in its own session if a task needs it |
| **Agents are eager; make them argue against themselves** | R5 and §6: say what you checked. Nothing about what you didn't. | **Partly.** The director's own summary is what Geoff approves, so this matters for him too. One small data point: he took the recommendation on all four decisions in the learning-loop study. That isn't a problem by itself, but it means the summary carries weight |
| **Memory is a machine-local notebook** | §11 and DL-320. | **Already does it** |
| **Rework is free, so build two or three options** | §4 and s19: one worker per task, no fan-out. | **Doesn't, deliberately.** Duo's design rounds do this on a canvas. Not worth a rule |

**Where the article doesn't reach.** It's written for one engineer watching their own sessions, in code. The director has problems it never mentions: findings not reaching the person (R4), silence read as an answer (§5), a user typing in a worker (§4), work that isn't code, and clients with no hooks (Duo's floor is 2.1.219, and the work Mac is pinned).

## 3. Options

Costs use F-622's figures at list price on Haiku: **about $0.14 per case at 3 runs, $4.60 for a full round**. One round proves little (s24 went 3/3, 0/3, 2/3 on nearly the same skill), so a comparison needs a baseline and more runs on the touched cases. Last time, about $15 went on the runs and judges together. Real spend depends on C-168's go, which is still open.

**What the evals can't do, for every option:** `claude --bg` is denied in a case, so no worker ever starts (F-622). They can prove what a director *writes and does*. They can't prove that a better brief gives a better result, or how a worker behaves.

### Small: a sentence or a few lines each

| | What changes | Skill length | Evals | What could get worse |
|---|---|---|---|---|
| **A. Say how a worker can prove it** | §2 gains a short rule on `## Brief`: why it matters, constraints, what's out of scope, decisions not written anywhere, and the check the worker can run (for non-code work, what a reader would look at). Leave out what the worker can read for itself. For a large or hard-to-undo job, ask for a plan and its assumptions first, which the director reads. | +3 lines | **Can prove** the brief gets written: two criteria on s01's judge, one on s19 (a small fix stays small). About $1 | Padding, and small tasks gaining ceremony. A director inventing constraints the user never gave, which §1's "don't fill gaps with guesses" should hold |
| **B. A worker states its plan to prove the work** | `workerPrompt` (code, one string): the first Progress line says how you'll check this and what you're unsure of; the report gives the command or look and what it showed, and what you didn't check. §6 says to read that line at your first look. | +1 line; +2 sentences in the prompt | **Can't prove** the worker's side. A DuoCheck pins the words. An existing case could cover the director reading the line, if its scaffold adds one | A longer prompt on every worker. A rote first line. Low risk, and it's the only one that reaches the worker on every task for every user |
| **C. Say what you didn't check** | R5 and §6: when you propose acceptance, say what you checked *and what you didn't*. | +1 sentence | **Can prove:** a criterion on s03 and s25 (s04 is 0/3 on main, C-168). About $1 | Boilerplate caveats that readers learn to skip |
| **D. Second failure gets a fresh worker** | §6 Stalls: when a worker misread the job, the second try is a new worker with a rewritten brief saying what failed, not another message. Failures a new session can't fix (permissions, a missing tool) go straight to the user. | About +1 line net | **Can prove** up to the start command: one new case, s34. s05 stays, since its failure is a permission one. About $0.50 | Loses a worker's context when that was the asset, and costs a restart. Must stop the old one, and never one the user typed in. `start` showed no refusal when I read it, but the build must confirm, and there's no stop verb in `duo2 director` |
| **E. When the evals run (C-168)** | A project rule: before a release that changes the skill, and once when the director's usual model changes. Report Sonnet alongside Haiku for the cases where they differ. Fix or retire s20, s02, s04 and s15 first. | 0 | n/a. This *is* the eval spend: $4.60 a round on Haiku; Sonnet costs more and I haven't estimated it | Spending on a suite whose results stay noisy |

### Medium

| | What changes | Skill length | Evals | What could get worse |
|---|---|---|---|---|
| **F. A reviewing worker** | §6: for large or hard-to-undo work, offer a second worker that reviews against the Request and `done_when`, correctness only, skipping style (the guide warns an unscoped reviewer always finds something). A worker, not a subagent (§4, DL-222). | +2 lines | **Can prove** it's offered, not that it helps | A worker's tokens each time. More for Geoff to read. In duo-v2, overlaps the gate and the fortnightly deep review |
| **G. Probation for new recurring jobs** | R3: a new job's first three runs are read in full, and `--routine` doesn't apply to them. A batch job is piloted on a few items first. | +1 or 2 lines, and possibly a red line, which DuoChecks then ties to a fixture | **Can prove:** one case, s27's shape. About $0.50; about half a day if status changes | Little. It's also little used until recurring jobs ship |
| **H. Trim the repeats** | Merge rules stated twice (task note first, chaining, Never 3 in §6, silence, no subagent). I estimate 8 to 12 lines and 5 to 9% of its 5,800 words. Run `/doctor prompt-audit` over the skill and over CLAUDE.md and `_PROJECT.md`. | About -10 lines | **Needs the most:** a full baseline and branch round, about $10 to $15, and noise may hide a real loss | Repeats may be why Haiku passes. The learning-loop study saw this risk. Do it after E, not before |
| **I. Rework numbers** | A `duo2 director` summary from the log: per task, sends before the first check, and time to first look. Project: reverts and follow-up fixes from git. | 0 or +1 line; one verb | **Can't prove** usefulness; DuoChecks covers the arithmetic | A number to optimise. The log is one day old, so wait (ENH-337) |

### Large

| | What changes | Skill length | Evals | What could get worse |
|---|---|---|---|---|
| **J. `done_when` as a `/goal`** | Workers start with a goal that a small model checks after each turn, sending back a worker that stops early. | +2 lines; `start` changes; a separate worker-side field | **Can't prove.** Needs real worker runs, which means a go for real turns | `done_when` is written for the user and director; this task's own includes "Geoff has chosen" and "the director has merged", which a worker can't reach. The evaluator only reads the transcript. It could push back on a worker that rightly stopped to ask. It needs hooks allowed, and setting one starts its own turn, so it has to carry the worker prompt too. Worth a pilot later (ENH-336), not now |
| **K. Enforce the Nevers with hooks or `ask` rules** | Offer an `ask` rule for `git push` on the user's yes, or take up ENH-326's status hook. | +3 lines; a verb; settings per project | **Can't prove** in the current harness | A standing yes (Never 3) can't be written as a rule, so an `ask` would block a director like Geoff's that may push. Hooks are absent on old clients and a director can't install them for itself. ENH-326 waits for the log to show status being skipped, and 26 hours can't show that. Keep waiting |
| **L. A soft limit on workers** | Say how many are running against how many are unread. | n/a | n/a | **Not offered as a change.** DL-232 is Geoff's decision, and the article doesn't give a reason to reopen it |

### Geoff's own project, separately

Most of A is already in `delegating.md`. The rule there is good, but 6 of the 14 directed notes since 1 Nov have no `## Brief`, so it isn't always applied. I haven't checked whether those needed one. CLAUDE.md is 81 lines and `_PROJECT.md` 29, well under the guide's 200. The heavy files are procedures read on demand, which is what the guide recommends. A `Stop` hook running the checks at each worker's end is a bad fit: the gate takes minutes and needs the shared compute lock, and most worker turns don't end the job.

## 4. Recommendation

Together: about 5 net lines (205 to about 210), one prompt string, one new case and a few criteria, and **about $12 of eval spend** at list price on Haiku (a baseline, a branch round, and more runs on the touched cases), once C-168 has its go.

1. **B: the worker states how it will prove the work.** The article's first point, at the one place every worker on every Mac reads. The cheapest and most useful change, and the evals can't confirm it, so judge it from real reports over a week or two.
2. **A: the brief, with its check and, for big jobs, a plan.** Brings other users up to what `delegating.md` already gives duo-v2.
3. **C: say what you didn't check.** One sentence against overtrust, in the message Geoff actually approves.
4. **D: a fresh worker after a misread.** Only once the build confirms `start` handles the old worker safely.
5. **E: settle C-168 at the same time,** since 1 to 4 need a trustworthy suite. Fix s20, s02, s04 and s15 first.

**Not now:** F (the gate and deep review cover most of it here; revisit if a merged branch fails review after the fact), G (with recurring jobs), H (after E), I and K (the log is too young), J (a pilot later). **Not at all:** L, and the article's "interview until you could write the spec" for directors.

## 5. Geoff's answers

Geoff declined the first set of questions and widened the task (2026-11-09): reread this article and the dreaming cookbook, look at the other director work in flight, and build one view of what is worth pursuing. That view, his answers and the order of work are in `director-unified-view.md`. The options above keep their letters there: A and B are its step 3, C, D and H its step 7, E its step 2, and G is the trial period for the review pass. His decisions are DL-329 and DL-330.
