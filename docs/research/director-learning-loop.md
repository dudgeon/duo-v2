# Director learning loop

*Design, 2026-11-08, for `tasks/director-learning-loop.md`. Input: `docs/director/retros/2026-11-07-director-retro.md`. Geoff: "I want a factory that gets smarter over time, takes existing responsibilities seriously, allows me to delegate tasks with confidence, and when things fail, proposes preventative approaches to avoid."*

## 1. The design in short

Today a failure becomes a memory in one director's instance. Other directors never see it, and the 22 days of lessons never reached the 23 evals we ship.

Three parts change that, and all three ship in Duo:

1. **A responsibility register** in the skill: nine duties a director owes without being asked. Each names the check that shows it's being neglected and the eval that proves the skill does it.
2. **Red lines** at the top of `duo2 director status`: a line for each duty being neglected right now, with what to do about it. Nothing red means nothing owed.
3. **A failure protocol** that replaces "write a memory": cause → duty → change → eval → ship. A failure is an ordinary Duo task, so it gets chased like any other work.

A DuoCheck ties them together: every duty must have a status check and an eval, or the build fails. The register can't quietly rot.

## 2. What I found in the repo today

These are readings from this Mac on 2026-11-08, and they shaped the design.

| Reading | What it means |
|---|---|
| 68 notes are unfinished by status. 12 have a Progress line from the last 7 days, 51 are older, and 5 have no dated line (one of those is `_record-reservations.md`, which isn't a task). | The brief's "63 live, perhaps ten are" holds up. Status has to group these, or the list is noise. |
| `.duo/director.json` lists **2 workers**. It was re-adopted at 07:59 today, and the older notes have no `sessions:` link. | Red lines can't rely on the registry. A note with no known worker has to count as a finding, not as "fine". |
| Status words in use include `in progress`, `building` and none at all. | `Director.unfinished` reads all of these as live. Status should flag them. |
| Old task notes exist inside a work tree (`markdown-review-design/tasks/`), although `tasks/` is git-ignored. | Status reads the main checkout and adds a work-tree note only when main has no note of that name. |
| The Claude desktop app keeps scheduled tasks and runs in `~/Library/Application Support/Claude/claude-code-sessions/<a>/<b>/`: `scheduled-tasks.json` (cron, `cwd`, `lastRunAt`, `lastScheduledFor`) and `local_*.json` (`scheduledTaskId`, `permissionMode`, `lastActivityAt`, `completedTurns`, `cliSessionId`). | Stuck and missed runs can be computed with Duo closed. **The format is private and undocumented** (decision 2). |
| Today's 07:15 discovery run: `permissionMode: default`, no completed turn, transcript silent since 07:16. Read at 08:02. | The failure the retro describes, happening during this study. A red line would have shown it. It started before the Auto setting changed at 07:56, so tonight's run is the first real test of that setting. |
| `duo2 director status` has two implementations: `directorStatusOffline` in `Sources/duo2/Director.swift` and `directorStatus` in `AppModel+Director.swift`. | Red lines must not become a third. One pure function in `DuoControl`, called from `duo2` in both cases. |

## 3. The responsibility register

Status can see behaviour. It can't judge the content of a message, so R4 and R5 are partly proved by evals alone, and the table says so.

| Duty | What a director owes | Red line in `status` | Eval |
|---|---|---|---|
| **R1 Watch workers to a conclusion** | Every worker's end is read and acted on | A worker stopped or idle with a last message newer than the note's last `Checked:` line. A worker on Needs you, with its question. A worker working with no transcript write for 2 h | new: stopped worker with no Progress line |
| **R2 Follow up by `check_by`** | Everything delegated or promised has a next look | `check_by` has passed. A background start that never appeared after 30 min. A live note with no worker and no `--no-worker` | new: overdue `check_by` |
| **R3 Watch recurring jobs** | Scheduled jobs are workers too | A run with no finished turn and no activity for 30 min (with its mode). A due time missed by over an hour. A finished run not yet checked | new: stuck scheduled run |
| **R4 Deliver findings** | Findings reach the user in chat, in plain words, with links | A report or run finished after your last message to the user (read from your own transcript). **Weak:** it shows you said something, not that you said this | new: finding not delivered; new: the links rule |
| **R5 Verify before "done"** | Nothing is called done, ready or true on a worker's word | A note at `review` or `done` with no `Checked:` line after the worker's last report | s04 (tests-pass claim) extended; s03 already covers a missing deliverable |
| **R6 Keep the record current** | Task notes are the one record | Unfinished, no `check_by`, nothing for 7 days, grouped into one line with a count and the first five (`--all` lists them). A status word Duo doesn't use | new: stale notes get resolved, not listed |
| **R7 Check in on a clock** | During long work, the user can tell stuck from working | Your own turn has run over 30 min with no text to the user | new: long job checks in |
| **R8 Keep your environment healthy** | Your mode, your client, the user's Duo | Bypass mode. Skill and Duo revisions differ. CLI logged out. A Duo process running while `duo2` can't reach it, Duo above 100% CPU, or its last update check over 48 h ago (F-606; the update-check source isn't verified yet) | new: bypass or unreachable Duo gets raised |
| **R9 Learn from failures** | A complaint is a signal that the system has a hole | An open failure task past `check_by`. Three or more `send`s to one task in 24 h with no `Checked:` line (the retro's "second time is the system") | new: user complaint runs the protocol and writes no memory |

Each red line reads: duty, what's wrong, what to do. For example:

```
RED R3 duo-problem-discovery: run started 07:15 in Default, no activity for 47 min. Stuck: unstick it, then find out why it started in Default (the failure protocol if this is the second time).
```

**When status runs.** The retro's definition goes into the skill: every turn the user didn't type, and the first turn after a compaction or restart. On a turn they typed, answer first, and run it in the same turn only if it's been over two hours.

**What a director does with red lines.** It clears what it can in that turn. Anything it can't clear goes in its next message to the user, in plain words with links.

## 4. Status red lines

**Sources, all readable with Duo closed:** task notes, `.duo/director.json`, `.duo/director-log.jsonl`, Claude's beacons and transcripts, the desktop app's task records.

**Output.** Red lines come first. The task list shrinks to running and red tasks (`--all` restores it). Rules and client lines stay. Every `duo2 director` verb ends with "N red lines: run status" when N is above zero, so a director that skips status still sees the count at no setup cost (decision 4).

**Judging the retro's two fields:**

- **`check_by`: keep.** It's the only way to catch a promise that nothing else records ("a build I said I'd start hadn't started seven hours later"). `duo2 director start` sets it, 2 h by default, and `--next` changes it.
- **`last_verified`: drop.** A timestamp isn't evidence, and a director could stamp it just to turn a line off. A Progress line beginning `Checked:` holds the evidence itself, and status reads its date.

Both are written by one new verb (decision 1):

```
duo2 director check <task> "what I verified, and the evidence" [--next 2h]
duo2 director check job:<id> "what the run found, or nothing new"
```

Job checks go in the log, because a job has no note. A finished run that found nothing therefore clears without pinging the user, which keeps the twice-daily discovery run from becoming noise.

**Cost.** Budget: the red-line pass adds under 200 ms on 100 notes, because it reads notes and only the tail of each live worker's transcript. I haven't measured it yet; the build will. The existing `claude auth status` call can already take up to 10 s, and I'd cache it for a few minutes.

## 5. The failure protocol

It lives in the skill, as a new section, so every director runs it. When something fails, or the user complains:

1. **Open a task** titled `Failure: <what happened>`, with the user's words in `## Request`. No new file type or ledger, and `check_by` chases it (R9).
2. **Cause:** the mechanism, not the last symptom. "Why did it start in Default?", not "switch it to Auto".
3. **Duty:** which one was breached, or which was missing. A missing duty is the most valuable result.
4. **Change:** the smallest change to the skill, `duo2` or the procedure that stops it recurring. A rule alone counts only if no check can see the failure.
5. **Eval:** a case that fails before the change and passes after.
6. **Ship and tell the user:** what failed, the hole, what changed, how we'd know. That message is the "preventative approach" Geoff asked for.

**Memory** keeps only the user's preferences and hard facts (how they like digests, an address). A correction about how directors behave isn't a memory.

**A director in a project with no harness** does steps 1 to 4 the same. Step 4's change goes in `_PROJECT.md` or `_HOME.md` `## Director`, on the user's yes, as the skill already requires. For step 5, the case is written in the task note: the situation, and what a good director does. Then, because that director can't change the product, it offers to send the case to Duo's public repo as an issue, with private details removed, and sends it only on the user's yes for that item (Never 2 and 3; decision 3). That route is what would let every other director benefit.

## 6. Where each retro fix goes

| Fix | Result |
|---|---|
| F1 ledger | **Absorbed**, without the ledger: task notes plus `check_by` (R2) |
| F2 second time is the system | **Absorbed**: the protocol and R9's repeat-send line |
| F3 health check | **Half absorbed**: R3 and R8. The GPU lock and session crons are duo-v2's and stay local |
| F4 evidence and links | **Absorbed**: R4, R5, `Checked:` lines and evals |
| F5 watchers that outlive the session | **Local.** duo-v2's scheduled task, not the skill |
| F6 consolidate the memories | **Local**, though the protocol stops the pile growing |
| F7 check-ins on a clock | **Absorbed**: R7 |
| F8 release regression matrix | **Local**: duo-v2's release process |

## 7. Pros, cons and cost

**How this removes complexity rather than adding a layer:**

- No ledger and no `health.py`, both of which the retro proposed.
- The status list shrinks to what needs action.
- Afterwards the director can retire `worker-links.py` from its wake routine. The console's rows can come from `status --json`, and `resuming.md` §0 shrinks from six steps to "status first". That's local follow-up, not this build.
- Failures use tasks, which already exist.

**Costs:**

- **Skill length:** about 30 new lines on 166, less about 15 I can cut from §1 and §5 where status now says the same thing.
- **Verbs:** one new (`check`).
- **Evals:** 9 new cases at 3 runs each, 27 runs added to today's 69. Each suite run is capped at $5 (`--max-cost-usd`). I don't have a measured cost per run yet.

**Limits, plainly:**

- **Status only helps if it's run.** The piggyback line narrows that gap and doesn't close it. Only a hook would, and a director can't install one for itself (Auto refuses self-modification).
- **R4 is weak.** It proves a message was sent, not what it said. The links rule and "evidence with every claim" rest on evals, and an eval shows the skill *can* behave, not that it did on a given day.
- **`check` can be gamed.** A director could write a hollow `Checked:` line to clear a red. The text stays in the note for anyone to read, which beats a bare stamp, but nothing stops it.
- **The desktop app's format can change.** If so, R3 goes blind. It must then say "can't read scheduled runs", never stay quiet.
- **Thresholds are guesses** (2 h, 30 min, 7 days) until they've run for a while.

## 8. Decisions for Geoff

Asked by AskUserQuestion, recommendation first; the answers are recorded in §9.

1. **The record:** `check_by` plus `Checked:` lines and a `check` verb (recommended), both retro fields, or `check_by` alone.
2. **Scheduled runs:** read the desktop app's private files and say so loudly when unreadable (recommended), or leave R3 to directors that have the session tools.
3. **Learning across directors:** offer an upstream issue on the user's yes for each one (recommended), or keep failures in the project.
4. **Getting status run:** skill, evals and the piggyback line now, with a hook as a later enhancement if the log shows it's being skipped (recommended); add an optional hook now; or skill and evals only.

## 9. Geoff's answers

*None yet.*
