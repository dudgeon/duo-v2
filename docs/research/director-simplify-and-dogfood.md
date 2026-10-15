# Director: simplification plan and dogfood review

*Shared state between the duo-director build session (it owns `## Simplification plan`) and the dogfood reviewer (it owns `## Dogfood review`), set up by the director on 2026-10-15 so the review judges the plan, not code about to go. Both write `## Open questions / Geoff's answers`. The build session commits this file.*

## Simplification plan

Geoff, 2026-10-15: "consider that you may be overcomplicating things and explore options that achieve the same functional goals reliably with less complexity." Each part of the skill, the verbs and DL-199's carrying gets one of keep, cut or replace. Status is planned, doing or done (with its commit). Branch `feature/duo-director`.

### Done

| Part | Verdict | What replaces it | Status |
|---|---|---|---|
| The user's yes for `--adopt` and `--handed-back`: a keystroke in the director's own tab, found by `$CLAUDE_PID`, after an "ask" record with a 30-minute expiry | **replace** | Duo asks the user itself, with the confirm sheet merges already use (`AppModel.confirm`); the verb waits up to 600 s. Every question comes before anything is written. | done, ca34c2f |
| `ClientCaps.pid`, the `asked` record, `SubmitGuard.handedBack`, the in-memory "typed since the director's last message" | **cut** | (gone with the above) | done, ca34c2f |
| Background workers: a minted `--session-id` with a name fallback | **replace** | `claude --bg` ignores `--session-id` (measured, F-318). The worker is pending under a name unique to the start (`-n <task>-<6 hex>`), and Duo links it at the refresh when a session with that name appears. No link step, no `--adopt`. A pending worker frees its slot after 30 min. | done, ca34c2f |
| Which project: Duo's folder for the cwd, falling back to the project on screen, then Home | **replace** | `DirectorPlace.resolve(from:)`: the nearest `PROJECT.md` at or above (never above Home, else the folder itself) and the nearest `HOME.md`. The same rule with Duo closed; the app prefers the Duo folder it names; an unknown folder is refused. | done, ca34c2f |
| Rule sources: "(none yet)" for both a missing file and a missing section | **replace** | Says "no PROJECT.md yet: offer Make a Project" or "no ## Director section yet". | done, ca34c2f |
| Fixed name, `.duo/director.json`, stand-down, roles by session id, `start --take-over` | keep | | done, 24f06cf |
| Workers = sessions the director started or the user let it adopt (registry), never a note's linked sessions | keep | | done, 24f06cf |
| DL-199 ladder: SendMessage, background resume, headless turn, Duo's guarded Enter, resume in Duo, queue | keep | | done |
| Guarded Enter: directed task, idle, empty prompt, 2-minute quiet window after a keystroke, echo seen before Enter | keep | (the keystroke monitor stays for the quiet window only, once the next item lands) | done |
| `watch` (polls status, survives Duo restarts), `guide`, `retire`, the log and its metrics | keep | | done |
| `ClientCaps` probe (beacon, settings, Monitor's flag) | keep | | done |
| Harness: stand-in claude + profiles (tier 1), plugin-eval scenarios (tier 2) | keep | | done |
| Skill core text, Director sections (DL-207), organising work (DL-208), Done to log.md (DL-209), inboxes (DL-210), the Never section | keep | | done |

### Planned (from the dogfood reviewer's needs, agreed)

| Part | Verdict | What replaces it | Status |
|---|---|---|---|
| The pause (DL-200) triggered by keystrokes in Duo | **replace** | A user turn in the worker's transcript after the director's last message. Claude marks typed turns `origin: human`; on clients without origins, plain text that isn't meta or a `<…>` notice. Duo tags everything it delivers `[director-x]`, so the director's turns are told apart. It sees Remote Control and background workers, and permission answers (tool results), peer messages and task notifications don't count. The keystroke hook, its cache and `director.json`'s `paused` go; Hand Back records `handedBack`. Keystrokes stay for the 2-minute quiet window only. Reviewer item e. | done, 6d6737d |
| D11: export item 1's check | **add** | `status --json` gives each worker's `userTyping` and `userTurnAt`, and `watch` prints a line when the user takes a worker over ("don't stop or archive it"). | done, 6d6737d |
| The cap counts every recorded worker on an unfinished task, stopped ones too | **replace** | Count running workers plus pending ones. A worker stopped after its merge, waiting days for sign-off, frees its slot. Reviewer item 4. | planned |
| `start` needs Duo running | **replace** | With Duo closed, `duo2 director start <task> --background` records the pending worker in `director.json` itself (DuoControl only) and prints the command; Duo links it at its next refresh. The note is written by hand, as the skill already says. Reviewer item 5. | planned |
| `DirectorPlace` takes a git work tree as its own project | **replace** | A folder whose `.git` is a file naming `<main>/.git/worktrees/<x>` resolves to the main checkout. Reviewer item c. | planned |
| Offline "No Home" when Duo has a Home configured elsewhere | **replace** | With Duo closed, read Duo's configured Home from its state file before saying there's none. Reviewer item d. | planned |
| The worker's brief names `tasks/<slug>.md` relative to the project | **replace** | The note's absolute path, plus "if you can't write the note, put your Progress lines in your report". Reviewer item a. | planned |
| The verbatim Request through a shell argument | keep, document | `duo2` already reads an argument from stdin (`--request --stdin`); the skill says to use it for anything long or quoted. Reviewer item b. | planned |
| D10: "one request, one task" read as one task per question | **add** | One line in §2: a question about state (what's in flight, what's on my plate) is answered, not filed. | planned (with item 6) |
| D9: `duo2 session new --name <n>` | **add** | Passes `-n <n>` to the new session (a `name` on `TerminalCommand.newClaude`), so a director can be started in Duo with its fixed name (DL-200). 2.1.219 takes `-n` (P1). | planned (item 7) |
| D12: a `watch` line for a worker with no progress for a while | later | | later |

## Dogfood review

*The reviewer's section (a background session on Opus, briefed by the director on 2026-10-15, read-only). Geoff's question: how the shared `duo-director` skill (the **core**) plus our project skill `.claude/skills/director/` (the **overlay**) would and wouldn't work as the director of duo-v2 itself, what context it needs, and what to change. Judged against the plan above where it cuts or replaces something, and against the director's last six days: its transcript (2026-10-09 to 10-15), the records, and Geoff's feedback to it.*

### In short

- **The core fixes what has gone wrong most often here.** A fixed name with a registry ends the peer-name churn: three names in six days, and a retired director that woke up and messaged sessions (10-13). Task notes replace a seven-source resume checklist. `watch` replaces subscriptions that die at every compaction. Asking before archiving, with the transcript-based "user is here" check (planned, item e), would have kept reachable the sessions Geoff was still using.
- **It fights us on approval, and only there.** The core makes every push, delete and publish wait for a yes for that item "whatever the rules say". Our director pushes main after each checked merge on Geoff's standing OK, about 16 times a day. That's question 1.
- **Most of our job is rightly not in the core:** releases, the walk, the design system, records, the GPU lock, the voice repo, visible-test permission, the work Mac. The missing piece is the seam. The core reads only Director sections, and duo-v2's `PROJECT.md` has none, so a fresh director that loads `duo-director` alone never learns the overlay exists. A draft section is below.
- **The overlay can lose about half its text:** the reviews doc (3 updates in six days), peer-name broadcasting, re-subscribing after compaction, and, if Geoff agrees, the console (about 155 tool calls in six days, for a page whose buttons stopped reaching the director after its first day). The merge checks become one script.
- **Four core gaps this repo hit are now in the plan:** the cap counting stopped workers, offline starts, a worktree read as a project with "No Home" beside it, and a pause that can't see Remote Control. Three more are below (D9 to D11).

### The director's week in numbers

From its transcript, 2026-10-09 16:48 to 2026-10-15 12:43:

| What | Count |
|---|---|
| Sessions started: in the background with Remote Control / in Duo | 34 / 14 |
| Merge commands / pushes | 58 / 98 |
| Releases | 7 (0.2.10 to 0.2.16) |
| SendMessage / AskUserQuestion | 251 / 29 |
| Console upkeep (ArtifactData, ArtifactComments, publishes) / design-system sync | about 155 / 32 |
| GPU-lock runs / records checks | 67 / 83 |
| Monitor / ScheduleWakeup | 0 / 0 |
| Workers busy at once (ListAgents snapshots) / background sessions alive at once | 1 to 4 / up to 16 |
| Record numbers taken twice, renumbered by hand | at least 5 (F-289, DL-175, F-293, F-299, F-302) |

### Fit, job by job

Verdicts: **fits**; **fits with a change** (named); **conflicts**; **ours** (overlay only, rightly outside the core).

| Today's job | What the core does | Verdict |
|---|---|---|
| Take Geoff's asks | One task per request, his words verbatim (`--request --stdin`, planned item b), one clarifying question; several asks at once wait as suggested | **Fits with a change.** Geoff's asks are go-aheads, so "several at once wait for go" adds a round trip he has objected to. A Director-section line covers it. Questions about state ("what's the status?", "give me the link") get answers, not tasks (D10). |
| Start workers | `start --background`, linked by name; worker prompt points at the note | **Fits with a change.** The overlay must say the brief goes in the note (as `## Brief`), not in place of the printed prompt. Absolute note path: planned item a. |
| Hear back, wake up | `watch` under Monitor; survives Duo restarts | **Fits, and is better.** Monitor wasn't used once this week; `notify_when_idle` is re-armed by hand after every compaction. |
| Resume after compaction or a restart | `status`, the Director sections, task notes | **Fits, and is simpler**, once delegations are tasks. Today two task notes exist in duo-v2, neither directed. |
| Review | Check against Request and `done_when:`; never pass on an unchecked claim | **Fits.** Captures, diffs and the public-repo privacy check stay ours. |
| Merge checks | "Run the project's checks yourself, each as its own plain command" | **Fits with a change:** today about ten commands, a baseline step, a lock and a worktree, typed by hand each time. One `scripts/merge-gate.sh <sha>` makes it one plain command a Haiku subagent can run. |
| Merge, push, clean up | Accept checked work if a Director section allows; push, delete, publish wait for a per-item yes | **Conflicts** (Q1). |
| Records | — | **Ours.** Clashes are daily; provisional ids (below). |
| Releases | Never without the user's explicit go | **Fits**: they agree. |
| Acceptance walk and sign-off | Mark complete and archive by asking | **Fits with a change**: how sign-off is collected is Q4. |
| Design-system artifact | — | **Ours.** It needs the Artifact tools, which background sessions don't have, so the director can't be one. |
| Talk to Geoff | AskUserQuestion in its session; pages optional, never load-bearing (DL-198) | **Differs by default** (the console first, DL-166); Geoff's own use has moved to the core's way (Q3). |
| Session hygiene | Archive a task and its finished sessions only on a yes | **Fits with a change**: the pause and an archive check need the transcript (planned item e). Stopping after merge, and resuming with Remote Control on request, stay ours. |
| Geoff's Duo | Verbs need his Duo running with the director in it (0.2.16 on) | **Ours.** Offline starts (planned item 5) cover the hours his Duo is down, as it was when this review began. |
| GPU lock, geoff-voice, visible tests, the work Mac | — | **Ours.** For geoff-voice: a duo-v2 task whose worker runs in the voice checkout (edit the printed `cd`); no `PROJECT.md` or `tasks/` in that repo. |
| Away windows (10-13: nine hours, no questions) | Acts on nothing that needs a yes | **Conflicts** without a time-boxed standing yes (Q1). |
| Workers directing workers (intro video and demo fixtures, 10-11) | Only the director tasks workers | **Not covered, on purpose**: relay through the director. |
| Found work | A suggested task at once | **Fits with a mapping:** a record (ENH, C, Q) as CLAUDE.md says; a suggested task only when the director proposes starting it. |
| Decisions and Done | `## Decisions` and `## Done` in `PROJECT.md` | **Fits with a mapping.** Our `PROJECT.md` is committed to a public repo: decisions stay DL-n in `decisions.md`; Done is the merge on main plus Geoff's sign-off. |
| Who the director is | `director-<project>`, registry, stand-down | **Fits, the biggest gain.** As this review started, a background copy of the director, resumed a day earlier for one question, was alive beside it; the registry stops a copy with another session id from starting or sending. Duo can't yet start a named session (D9). |

### Where the core fights this project

1. **Approval (Q1).** Never 2 and 3, and §6, make a push, a delete or publishing wait for the user's yes for that item, "whatever the rules say". Geoff's standing OKs cover pushing main after a checked merge (2026-10-11), sweeping merged worktrees and branches and publishing the walk page and the design system (DL-166). Once they covered a whole night (2026-10-13: release 0.2.13 and publish both films). The overlay says it wins where the two disagree; the core says its Never list holds whatever a rule says. A director given both rules can't follow both, and a careful one asks anyway. Eval s17 is stricter still: its user types "commit and push to the website repo", and the passing answer asks again.
2. **The channel to Geoff (Q3).** The overlay makes the console the default. On its first day one test tap arrived; on 10-12 Geoff said its controls didn't reach the director and moved to one-at-a-time AskUserQuestion on his phone. Since then he has asked for status in chat (10-13, 10-14), and a one-off decision page with Send buttons worked from his phone (10-14). The core's way is what he has been using.

### What the core gives us

- A name that survives restarts, and a registry that makes a stale copy stand down.
- Task notes as the director's memory, replacing the reviews doc's log, the console's threads and a memory snapshot last updated on 10-12.
- `watch` instead of one-shot subscriptions.
- Asking before archiving and stopping, with the transcript check, instead of a rule broken three times (10-07, 10-13, and 10-15, when the director-skill session showed as archived while Geoff was still working with it).
- Stalls: two tries, then `waiting` and a question. On 10-14 Geoff spotted a frozen session and a paused one before the director did.
- The Never list where workers ask: ours ask the director for visible runs, deletes and pushes.

### Context to move or create

| What | From | To | Why |
|---|---|---|---|
| The cap; the standing yeses; "read the overlay next"; where Decisions and Done live; "Geoff's asks start at once" | The overlay and memory | A `## Director` section in `PROJECT.md` (draft below) | The core reads only Director sections, and `duo2 director` reads the cap there. |
| Geoff's habits for any director: Done / Needs you / Next digests; on the phone, one decision at a time; do the routine steps of a job he handed over; answer a question asked back, then wait; never archive or stop a session he's talking to | Memory notes in this repo's Claude project folder | `~/claude-home/HOME.md`, `## Director` (Q6) | DL-207's placement test: true in any project. Today only sessions in this repo see them. |
| Machine-local facts: the lock folder, the voice checkout, artifact ids | Memory | Stay in memory | Never in the public repo. |
| What's in flight | The director's head, the console's `threads`, the memory snapshot | One task note per delegation from the switch on, plus one handover note listing the older ones | "Your memory is the task notes." Don't adopt old workers: each `--adopt` is a sheet at the Mac. |
| The standing rules every worker gets (worktree, no push, isolation, the lock, models, visible runs, who to report to) | Repeated in each brief (12 items in `refs/delegating.md`) | CLAUDE.md, which every session loads anyway, with "report to `director-duo-v2`" | A brief shrinks to the job: Geoff's words, `done_when:`, branch, record range, proofs, who else is working where. |
| The merge checks | `refs/review-merge.md`, as prose | `scripts/merge-gate.sh <sha>` | One plain command, the same every time. |
| The reviews doc, and the console if retired | claude.ai | Left read-only | Replaced by task notes, git and AskUserQuestion. |

**Draft `## Director` for duo-v2's `PROJECT.md`** (public; each line restates a rule Geoff has already given, except the cap, which is Q5's subject, and the asks line, which formalises how he works):

```markdown
## Director

- Read `.claude/skills/director/SKILL.md` next: Duo dev's habits (merges, records, releases, the walk, the design system, the GPU lock, the voice repo).
- Start as `claude -n director-duo-v2`. Workers run in the background with Remote Control (DL-201); design work runs in Duo.
- max workers: 6
- Models by job, as CLAUDE.md's Model efficiency says.
- Geoff's asks start at once, each as its own task, unless he says to hold.
- You may merge a branch that builds, passes `scripts/merge-gate.sh` and logs its stand-ins (D2), push main after it, and then remove its worktree and branch. Ask first when a merge would reverse a DL, or when two branches change the same behaviour differently.
- Stop a finished worker after its merge, to free memory, unless Geoff has typed in it since your last message: then ask. Never archive a worker's session before he signs off.
- Always ask: a release; a visible test run (the freeze-guard gate is pre-approved); anything on the work Mac.
- Decisions are DL-n in docs/design/decisions.md, and found work is a record (ENH, C, Q). Don't keep ## Decisions or ## Done here.
- Merged work waits for Geoff's sign-off as `waiting`; it's done when he signs off.
```

### Changes to our overlay

- **A "what the core's words mean here" table:** accept = merge under D2; the project's checks = `merge-gate.sh`; Decisions = DL-n; Done = the merge on main plus sign-off; found work = a record; complete = Geoff's sign-off; archive = after sign-off only.
- **Workers:** `duo2 director start <task> --background`, then add `--remote-control <name> --model <model>` before `--` and run it. The job's brief goes in the note's `## Brief`.
- **Run `duo2 director` from the main checkout**, not `director-check`, until planned item c lands.
- **Retire:** the reviews doc (`refs/resuming.md` step 2, the last line of `refs/delegating.md`, step 6 of `refs/review-merge.md`); broadcasting a new peer name after restarts (`refs/talking-to-geoff.md` §7); re-subscribing after compaction (`refs/resuming.md` step 5); the console, per Q3.
- **Records, the director's call:** provisional ids. Workers write `F-?`, `DL-?` and so on; a script at merge gives them the next free numbers and rewrites the references. Clashes then can't happen, and CLAUDE.md's "take the next after the highest anywhere" rule goes.
- **Keep:** releases, the walk, the design-system sync, the GPU lock, the voice repo, the lessons.

### Core changes beyond the plan

| # | Change | Why | Cost | Recommendation |
|---|---|---|---|---|
| D1 | The standing yes (Q1). | Above | A paragraph in Never and §6; s17 rewritten; one new case (a standing line: it pushes; none: it asks); the s18 and s21 gates re-run on Haiku and Sonnet (about $7) | Per Q1 |
| D9 | `duo2 session new --name <n>`, passing `-n`. | DL-200 wants directors started with a fixed name, and Duo can't start a named session. Ours must run where the Artifact tools are (in Duo, or interactive). Until then, `claude -n director-duo-v2 --remote-control` typed in a Duo shell tab should do (DL-8; untested). | Small | Do |
| D10 | §2: a question about state is answered, not filed. | "One request, one task" reads as one per question. | One line | Do |
| D11 | Export item e's check: `status --json` gives each worker's last user turn, and `watch` says when the user types in a worker. | The overlay's "never archive or stop a session Geoff is using" needs the same check | Small | Do |
| D12 | `watch` says when a worker has shown no progress for a while. | Stalls Geoff noticed first | Small | Later |
| — | Dogfooding here covers only the top rungs: this Mac's clients all have messaging and Monitor, so `send` always picks SendMessage. | The work Mac's rungs (Duo pressing Enter, headless turns) get no daily use from us; workers in Duo wouldn't change that. | — | Keep the harness's pinned-219 profile in the release gate; Geoff's work-Mac test is the only real exposure. |

### Will do (no decision needed)

- After Geoff's answers: the `## Director` section and the overlay changes above (the director, or the build lead where a change rides with core code).
- `scripts/merge-gate.sh`; retire the reviews doc.
- CLAUDE.md: report to `director-duo-v2`, drop "its peer name changes whenever it restarts", and keep the standing worker rules in one place.
- Workers stay in the background (DL-201): not re-asked.
- The switch comes with the release that puts the director into Geoff's Duo: one handover note for work in flight, new delegations through `duo2 director start`, no adopting.
- Prune memory notes that the overlay or `PROJECT.md` then holds, so each rule lives in one place.

## Open questions / Geoff's answers

1. **Standing yes** (the reviewer puts this one to Geoff): Never 3 and §6 say a push, delete or publish waits for the user "whatever the rules say", but Geoff's standing OK covers pushing main after a checked merge and sweeping merged work trees. Proposal: a yes counts when the user gave it for that action, in their own words naming it or as a standing line in a Director section (it can be time-boxed); a worker's ask or the director's own inference never does.
2. **Duo's two new questions** (the build session's): `--adopt` and `--handed-back` now show Duo's existing confirm sheet with new wording ("Let director-x take this on?", "Hand “…” back to director-x?"). No new surface was drawn. Is the existing sheet fine, or should these be designed? Not yet asked; the director may bundle it with the install-question re-ask. **The director asked the reviewer to put it to Geoff in the same round, recommending the existing sheet (a sheet he approved, new words: a stand-in under our rules).**
3. **The console** (the reviewer's): the console's buttons stopped reaching the director after its first day; Geoff has since answered by AskUserQuestion and asked for status in chat, and its upkeep was about 155 tool calls in six days. Options: retire it (decisions by AskUserQuestion, digests in chat with session links, a page with Send buttons only for a big batch, Duo's board for what's in flight; recommended); keep it as a read-only status board; keep it as the default channel (DL-166).
4. **Sign-off** (the reviewer's): merged work waits for Geoff's sign-off before its task is done and its sessions can be archived. How is it collected? Options: one batched question in each digest, with his word in a worker's session or a walk verdict also counting (recommended); only when he says so; done at merge, with the walk tracking sign-off separately.
5. **The cap** (the reviewer's; it counts running workers once the plan's item lands): 6 (recommended), 4 or 8. This week 1 to 4 workers were busy at once.
6. **Geoff's habits for every director** (the reviewer's): move the cross-project ones (digests, one decision at a time on the phone, routine steps of a job he handed over, answer a question asked back and wait, never archive or stop a session he's talking to) from this repo's Claude memory into `~/claude-home/HOME.md`'s `## Director` (recommended, DL-207), or keep them in memory.
