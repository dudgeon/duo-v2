# Recurring jobs for Duo v2

*Evaluation and design, 2026-11-08 · task note `tasks/recurring-jobs.md` · branch `feature/recurring-jobs` · records F-615 to F-617, Q-472 to Q-477, C-167, DL-324, DL-325, ENH-328.*

**Ask (Geoff, 2026-11-08).** "Please have a worker evaluate the cron/recurring job feature from duo classic. I want to rebuild it in v2. I think it could be useful in the 'dreaming' application … Our work policy prohibits mechanically overriding human control -- so the automatic/scheduled/recurring jobs would only start/continue with a single canned prompt, and the human would need to take further action. sessions can start in auto, but this should not be allowed to advance arbitrary commands -- just the scheduled one." And later: "for users that have claude scheduled agents, that may be a stronger offering; but we don't have those at work yet."

This is a design. Nothing here is built, and every visible surface is a stand-in until drawn (§9).

## 1. The answer in one screen

- **What to build:** a job is a note in the project with a schedule and one fixed thing to do: a prompt, or a single shell command. When it comes due, Duo starts one new session (or command) in a background tab, and logs it. The scheduler has no code path that types anything further, or approves anything.
- **Who runs the clock (DL-324):** one job record, and each job names one runner. **Duo's own timer is the default**, as in legacy Duo, because it's the only runner that can keep all four rules and it works on the work Mac. **A Claude scheduled task is an option per job** where the account has one. Duo watches that job, but can't create it or hold it to the rules (§4).
- **Why Claude's scheduled agents aren't the primary path:** I looked at this as Geoff asked, and it's only half true. Cloud tasks are stronger in one way: they run with the Mac off. But they get a fresh clone, so they can't read local transcripts or an uncommitted `_knowledge/`, which rules out the dream. Desktop tasks need their app open and the Mac awake, as Duo does, so they gain little. They also run one catch-up after a miss, which breaks rule 3, and a Duo app can't create them.
- **Two things legacy had go away,** because they break the policy: "same session" jobs and the run-once catch-up. Shell jobs stay, fixed and approved (DL-325).
- **The line is on the scheduler, not on who else may act (DL-325).** Geoff: "the director may control scheduled jobs like any other -- only the scheduler must not approve claude commands."
- **A prompt in a project file could be changed by any agent, so the note alone can't fire (DL-324).** You approve a job in a Duo sheet, and that approval covers an exact hash of what it runs, its schedule, mode and model. If the note changes, the job stops firing and asks you again (§6).
- **The real limit:** this controls what the *schedule* does, not what the session does with its one prompt. In Auto, one prompt can still do a lot (§3, C-167).

## 2. What legacy Duo did (F-615)

ENH-223 shipped in v0.11.2 (2026-06-22); ENH-237 added shell jobs in v0.13.0 (2026-06-27). Sources are in the `duo` repo.

| Feature | How it worked | Where | For v2 |
|---|---|---|---|
| Schedules | Presets (Hourly, Daily, Weekdays, Weekly) or a custom 5-field cron, in local time, with its own parser and no dependency | `core/cron-schedule.ts` | **Keep.** Port the engine and its 350 lines of tests |
| English preview | A live label and next fire in the dialog; rejects a schedule that never fires (Feb 30) | `describeSchedule`, `cron-service.ts` `preview` | **Keep** |
| Store | One app-wide `~/.claude/duo/cron-jobs.json`, written atomically through a queue, and tolerant of bad entries | `core/cron-store.ts` | **Change** (§6) |
| Firing | Typed `claude --session-id <minted> '<prompt>'` into a new tab, always interactive | `core/cron-command.ts` | **Keep the idea**; v2 passes arguments directly, with no shell line to quote |
| "Same session" | The next run did `claude --resume <id> '<prompt>'`, falling back to fresh | `cron-service.ts` `fireJob` | **Drop.** It is a second prompt into an earlier session, which rule 1 forbids |
| Shell jobs | `duo cron add --run "<cmd>"` ran a raw line in a tab with no Claude (motivated by `qmd update && qmd embed`) | ENH-237; `buildShellCommand` | **Keep, fixed and approved** (DL-325, §6) |
| Headless gate | Refused `-p`, `--print`, `--bare`, `--output-format` | `assertInteractiveCommand` | **Keep the outcome.** v2 has no such path to gate |
| Scheduler | A 30 s tick in the app, jobs fire only with Duo open | `cron-service.ts` | **Keep** |
| Missed runs | Skip by default; opt-in "run once on next launch", collapsing many into one; a fire after sleep treated as a miss in the PRD, though the tick really fires it late | `runCatchUp`; PRD §7 | **Skip always**, and fix the sleep gap (§5) |
| Overlap | Guarded only while *starting*; the PRD's "skip if still running" was left as an open question | `firing` set; PRD §7 | **Build it** (§5) |
| Landing | A background tab with no focus steal, in the window showing that project, else the primary, else recorded as missed | `resolveCronLandingWindow`, D10 | **Keep** |
| Attention | ENH-225's amber dot for a stopped tab | hooks to socket | **Exists in v2** as needs-you |
| Home UI | "Scheduled" rows under project cards plus one block for the rest, with status chips (ran, never, missed, error, paused) and Run now, Pause, Delete | `CronSection.tsx`, `CronJobRow.tsx`, `NewCronJobModal.tsx` | **Redesign** (§9) |
| CLI | `duo cron list\|add\|edit\|run\|pause\|resume\|rm\|show` | `socket-server.ts:2373`, `cli/duo.ts` | **Keep the shape** as `duo2 job` (§7) |
| History | Last run and status only; a run history was deferred | PRD | **Build the log**: rule 4 needs it |

**What went wrong in legacy, from its record:**
- a job's tab stole focus until a background flag was added;
- catch-up was clobbered by session restore at launch;
- the dialog's errors were unreadable in light mode;
- a shell job looked the same as a Claude job in the list (still listed as a known issue);
- spring-forward times were silently skipped, flagged to the owner as behaviour rather than a defect.

The record shows no complaint about the feature's idea. **There is also no sign of use on this Mac:** `~/.claude/duo/` doesn't exist here, so there's no `cron-jobs.json`. The work Mac may differ. Asked what he used or missed, Geoff stated no preference (§12).

## 3. The policy, as rules the code keeps

Geoff's rules, from the brief:
1. A job starts a session with **one canned prompt**, fixed when the job was made and readable before each run. The schedule types nothing else into that session.
2. The session **may start in Auto**, but the schedule never advances anything past that prompt. What it asks or leaves undone waits for a person.
3. **Missed runs are skipped**, not queued.
4. **Every fire is logged** (job, time, prompt, session id, mode) and visible in Duo and by `duo2`.

**How each is kept, by construction rather than by care:**

| Rule | Mechanism |
|---|---|
| 1 | The scheduler's only output is `TerminalCommand.newClaude`. It can't reach `resumeClaude`, `duo-submit`, SendMessage or any terminal input. A DuoChecks test scans the job code for those calls. Each fire mints a new id (DL-14) and there's no "same session" option. A failed start isn't retried |
| 1, "fixed" | The approval hash (§6): an edited prompt can't fire until a person approves it |
| 1, "readable" | The note is the prompt. `duo2 job show` prints it, and the log keeps the exact text of each fire |
| 2 | Mode comes from the job, set explicitly with `--permission-mode` rather than inherited (F-605). **The scheduler never approves a Claude command:** it has no path to a permission prompt, and a job can't be set to `bypassPermissions` (`duo2 job` refuses it, and so does the fire path). A question or blocked action shows as needs-you like any session, and the scheduler doesn't answer it |
| 3 | A due time more than 10 minutes old when Duo next looks is logged `skipped: missed`, never run. There's no catch-up setting |
| 4 | One append-only log line for every due time, fired or skipped (§6) |

**Where `duo2 director send` sits.** The brief cites DL-199, where a director types into an idle worker. **DL-257 retired that typing**: `director send` now hands the director a SendMessage, or resumes a stopped worker. The distinction still holds and is simple:
- A director's message is a *decision made at the time, on a task a person directed*. Someone or something looked at the state and chose to say this.
- A schedule's second prompt would be *mechanical*: sent because the clock said so, whatever the session had done. Rule 1 forbids it, and the scheduler has no such path.

**May a director answer a job's session? Yes (DL-325).** I recommended holding directors back, on the reasoning that a director isn't a human. Geoff chose otherwise: "the director may control scheduled jobs like any other -- only the scheduler must not approve claude commands." So a job's session is an ordinary session once it has started. A director may read it, message it and answer it under its usual rules (DL-257), and a person may too. Only the scheduler is bound. The brief's rule 2, "a person takes the next action", is read accordingly: the *scheduler* never takes it.

**What this doesn't stop (C-167).** The schedule stops at one prompt; the session may not.
- **It could reschedule itself.** `/loop`, `CronCreate`, `ScheduleWakeup` and `/goal` keep a session going by itself, which is a schedule re-prompting by another route. On Duo's runner, jobs start with `CLAUDE_CODE_DISABLE_CRON=1` (documented: it removes the cron tools and `/loop`) and `--disallowedTools ScheduleWakeup`. Whether `/goal` can be held off needs checking at build. `tools:` and `dontAsk` (§8) can narrow a job further.
- **It can start others.** `claude --bg`, `duo2 session new` or `SendMessage` from a job session reach beyond it. That's allowed, like any session: it's the session's act under its mode and your rules, not the schedule's.
- **A director's replies aren't human review.** After DL-325, a job that asks a question may be answered by a director with no person involved. That's Geoff's call, and it should be checked against the written work policy before this ships at work. A project with no director still waits for a person.
- **One prompt can be large.** "Follow this procedure" in Auto is many actions. Rule 1 was never a limit on that; the limits are the mode you pick, your allow and ask rules, and reading the prompt when you approve it.

## 4. Claude's scheduled agents against Duo's own timer (DL-324)

**Why v2 deferred this.** DL-9 said to lean on Claude Code's own scheduling. That was reasonable and is still right for many jobs. Three things have changed: the work Mac has no scheduled agents, the dream needs a per-project inspectable job, and the director's runs have stalled unseen (F-605, F-604).

**Facts from Claude's docs** (fetched 2026-11-08, F-616; [desktop](https://code.claude.com/docs/en/desktop-scheduled-tasks), [cloud](https://code.claude.com/docs/en/routines), [session](https://code.claude.com/docs/en/scheduled-tasks)):

| | Duo's timer | Claude desktop task | Claude cloud task | `/loop`, CronCreate |
|---|---|---|---|---|
| Needs | Duo open, Mac awake | Claude Desktop open, Mac awake | Nothing local | An open session |
| Available on the work Mac | **Yes, once built** | No (per Geoff) | No (per Geoff); owners can turn it off | Don't use: see below |
| Local files and transcripts | Yes | Yes | **No, a fresh clone** | Yes |
| Fresh session each run | Yes | Yes | Yes | **No, same session** |
| **Rule 1, nothing further typed** | Kept by construction | Kept | Kept for scheduled runs, except a run in a project "can continue a thread" | **Broken** by design |
| **Rule 1, prompt fixed** | Approval hash | **No**: `SKILL.md` on disk is editable and "changes take effect on the next run"; the self-edit tool does need approval | Edited in the app | n/a |
| **Rule 2, mode per job** | Yes | Yes, per task (unset means your settings, which is what bit F-605) | Auto by default | Inherited |
| **Rule 3, missed runs skipped** | Yes | **No**: "exactly one catch-up run" within 7 days, on launch or wake | Doesn't miss | No catch-up |
| **Rule 4, log** | In Duo and `duo2` | In the Desktop app with skip reasons; no public way to read it | In the web app | No |
| Needs-you in Duo | Native | Only if Duo can see the session's state | No | Native |
| Can Duo create one | Yes | **No public way.** A Desktop session can by asking Claude, and the form can; the schedule lives in private files | `/schedule` in a session, or the web | A session can |
| Cost to Duo | The build (§10) | A read-only link | A read-only link | None |

**So on "stronger offering", my honest read:**
- **Cloud is stronger only for jobs that need nothing local.** It's the one option that runs with the Mac off. A repo-only report suits it. The dream doesn't, since it reads local transcripts and `_knowledge/` stays out of git by default (Geoff's answer, knowledge study §10).
- **Desktop tasks are already built and have good touches:** connectors configured per task, a skip history, Keep computer awake, saved approvals. But they share Duo's constraint of an open app on an awake Mac. A user running Duo all day gains little, and loses the rules above.
- **`/loop` and `CronCreate` are not a fit at all.** They re-prompt one session on a clock, which is exactly what the policy forbids. This matters at work: nothing in Duo stops someone using them, but Duo shouldn't offer them as jobs.

**Geoff's decision (DL-324): one job record, one runner per job, Duo's timer by default, as in legacy Duo.**

```
_jobs/dream.md          the one record: prompt, schedule, mode, model, runner
   runner: duo          Duo's timer fires it. All four rules hold.
   runner: desktop      Claude's task fires it. Duo checks and shows it.
   runner: cloud        Claude's cloud task fires it. Duo links to it.
```

**No two sources of truth, and no double fires:**
- **One clock per job.** Duo's timer only ever fires `runner: duo`.
- **The note is the definition for every runner.** For `desktop`, Duo compares the note's body with `~/.claude/scheduled-tasks/<name>/SKILL.md`, whose place and format Claude's docs state. If they differ it says so, and never overwrites either one silently.
- **The rules are stated per runner.** A `desktop` job's row says "may run once after a miss" and "the prompt can be edited outside Duo". Duo doesn't pretend to enforce what it can't.
- **The log covers every runner, with honest gaps.** For `desktop`, Duo can see a session in the project and try to tie it to the task. That means reading Claude's private files, so it says "can't read" when they change rather than going quiet (the learning-loop study reached the same conclusion for R3).

**Where this differs from the director's example.** The relay suggested Duo "creates a Claude scheduled agent when the account offers it". I can't find a public way to do that, or to tell whether an account has them:
- Local tasks are created in the Desktop form or by asking Claude in a Desktop session, and a background session or Duo terminal doesn't have that tool.
- The cloud route, `/schedule`, needs a claude.ai login and fails in several documented ways.
- Writing Claude's private `scheduled-tasks.json` would be brittle and would act behind a person's back.

So Duo can *offer* it: show the job's text ready to paste, or start a session the user can ask. Then it links to the result once it's there. Detection can only be a hint: Desktop installed, or `~/.claude/scheduled-tasks/` present.

**What Claude's scheduling still does better, so Duo should defer to it:** anything that must run with the Mac off (cloud); anything triggered by a GitHub event or API call (cloud); polling within one session you're attending (`/loop`). Duo's timer shouldn't try to grow into these.

## 5. Duo's runner: the mechanism

**Recommended: an in-app timer, as LR-12 says.** A plain 30 s wall-clock check, separate from the UI refresh so DL-318's back-off doesn't affect it.

| Option | For | Against | Verdict |
|---|---|---|---|
| **In-app timer** | One process, no install footprint. Interactive sessions and needs-you work as usual. Legacy proved the shape. Isolated test instances are safe by default (below) | Nothing fires with Duo closed; the run is logged as skipped at next launch | **Yes** |
| **launchd** | Fires with Duo closed | Writes a plist outside Duo's folders (against F-113's spirit); managed Macs may block it; launchd runs a missed interval on wake, so rule 3 needs extra work; and it must either launch Duo, which takes focus unless handled carefully, or start `claude --bg`, which ignores `--session-id` and so breaks DL-14 (F-318) | **Later, only if asked** (ENH-328, the heir of legacy's ENH-222) |
| **A Claude desktop task calling `duo2`** | No timer to write | Needs the Desktop app, so it does nothing for the work Mac. Each fire is itself a Claude turn with a mode problem (F-605). It adds an agent between the clock and the job | **No** |

**Against the brief's cases:**
- **Sleep:** the Mac isn't woken. On wake, a due time older than 10 minutes is `skipped: missed`, and a newer one fires. This closes legacy's gap, where the tick fired late runs of any age.
- **Duo closed:** the same. Duo doesn't reconstruct every missed time; the next launch logs one line per job, "skipped since <time>".
- **A job that keeps missing:** a laptop asleep at 03:00 would miss forever. After 3 misses in a row, the job's row says so in Duo. It doesn't fire. It tells you to move the time.
- **Work Mac without Duo running:** no fires, the same as above. That's the honest limit of a Duo feature, and it's why ENH-328 exists.
- **F-605's mode problem:** `--permission-mode` is passed on every fire from the job's record, whatever the settings say. If Auto is unavailable (an organisation can turn it off), Claude starts in another mode and the first action waits: a needs-you, not a silent stall. The log records the mode asked for. **To check at build:** `--permission-mode auto` on the work Mac's 2.1.284; this Mac has 2.1.316.
- **`DUO_ISOLATED` and scripted runs:** approvals live in the support folder, so an isolated instance has none and fires nothing, even when pointed at a real project. Tests make their own approvals and use an injected clock, on Haiku through the job's `model`.
- **Two Duos at once (F-606):** a fire is claimed by creating a marker for `<job>/<due time>` exclusively, so a second instance can't double-fire.

**Many jobs at one time:** each job gets a small fixed offset of up to 5 minutes from its id, as Claude's desktop tasks do, so projects sharing a time don't all start together on one person's quota.

**A fire, step by step:**
1. The job is due. Check approved, enabled, and within 10 minutes.
2. If the job has a `when:` check (§8), run it. If not due: log `skipped: not-due`.
3. If the job's last session is still working or needs you: log `skipped: still-open`. This also stops a neglected job piling up sessions.
4. Mint an id, then start `claude --session-id <id> -n "<job> <date>" --permission-mode <mode> [--allowedTools <rules>] [--model <m>] [--remote-control <name>] -- <prompt>` with `DUO_JOB=<id>` in its environment, in a background tab of that project, not focused.
5. Log the fire. Done. **The scheduler forgets the session from here.**

**Code notes for the build (F-617):**
- `Terminals.swift`'s `newClaude` appends the prompt with no `--`, so a prompt starting with `-` would read as a flag. `resumeClaude` already guards this; a job's start must too.
- `newClaude` has no mode or model yet. They're per-job fields the user sets, so Duo still doesn't choose a model (DL-153).
- A hidden tab may wait until shown to start its process (`keep-running` "starts at launch instead of waiting to be shown"). A job's tab must start at once. Parking must not end a working job session.
- Legacy typed a shell line and quoted it. v2 passes arguments directly, so there's no quoting to get wrong.

## 6. Where jobs live, and the record

**Geoff's decision (DL-324): a note per job in the project at `_jobs/<slug>.md`, plus machine-local approval, state and log in Duo's support folder.**

| Place | For | Against |
|---|---|---|
| **`_jobs/<slug>.md`** | Readable in Obsidian and any editor. Travels with the project. Sits with `_PROJECT.md` and `_knowledge/` by the underscore convention. Doesn't touch the task board | A new folder; any session can edit it (solved below) |
| `tasks/` with `type: job` | No new folder | A job isn't work to finish. Every task view and Obsidian board would need a filter (DL-6, DL-148) |
| `_knowledge/` | The dream is near it | Only the dream writes there, by that study's core rule. A job isn't knowledge |
| Duo's support folder only | Harder for an agent to change; legacy's choice | Invisible in the project and Obsidian, lost on a new Mac, and against "a project stands alone" |

```markdown
---
type: job
id: 01J...
title: Dream
schedule: "0 13 * * 1"
mode: auto
runner: duo
---
Run this project's knowledge dream: follow `duo2 knowledge guide`, then stop.
```

**The body is the prompt, all of it.** What you read is what runs. Frontmatter links, if any, follow DL-17.

**Shell jobs (DL-325)** have `kind: command`, and their body is one line, for example `qmd update && qmd embed`:
- They run in a background shell tab through Duo's runner only; Claude's schedulers have no equivalent. There's no session id, mode or model, and the log records the exit status.
- Newlines are refused when it's written and again at fire time, as legacy did, so a job can't hide a second line.
- Approval works the same way, and the sheet shows the command in full.
- **A command that names `claude` is refused,** best effort. `claude -p … --dangerously-skip-permissions` in a shell job would be the scheduler approving Claude commands by another route. A script that calls `claude` inside it can't be seen from here, so the sheet says plainly that the command runs with your full permissions (C-167).

**Optional fields:**
- `when:` a named built-in check (§8), never a command.
- `tools:` the built-in tools the session has, passed as `--tools`.
- `allow:` permission rules, passed as `--allowedTools`. With `mode: dontAsk` this is a true allowlist: anything outside it is denied, and the session never waits (§8). Approving the job approves the list, so this is a person's approval made in advance, not the scheduler approving commands (DL-325).
- `pins:` files the prompt relies on, whose contents join the approval hash (below).

**Fields the brief listed that aren't in the note, on purpose:**
- `last fire`, `next fire`: derived or machine-local, so a repo doesn't churn every run.
- `enabled`: machine-local (`duo2 job pause` on this Mac), so pausing here doesn't pause a colleague.
- `skip-missed`: not a field. It's always on, per rule 3.
- `project`: it's the folder the note is in. The session runs at the project's root, never in a work tree.

**Approval is what makes the note safe.** A prompt in a project file can be changed by any session in Auto, or arrive by `git pull` from a colleague or a stranger's repo. Without approval, cloning a repo could arm a scheduled Auto session on your Mac. So:
- A job fires only if `<support>/jobs/approved.json` holds the SHA-256 of its fired fields (prompt or command, pinned files, schedule, `when`, mode, `tools`, `allow`, model), with who and when.
- Only a Duo sheet writes that (through `SheetCenter`), the way `duo2 session delete` makes the user confirm in Duo. A session can run `duo2 job approve`, which opens the sheet; it can't approve by itself. `DUO_AUTOCONFIRM=1` answers in scripted runs, so isolated tests work.
- If the note changes, the job stops firing and shows one needs-you: "Dream changed. Approve?" with a diff.
- **A prompt that names a file is only as fixed as that file** (found by the learning-loop worker). With `Follow docs/x.md`, any session can edit the procedure and the next fire runs it, with no change to the prompt and no question to anyone. Geoff's decision (Q-477, DL-324): `pins:` lists such files, and a change to one stops the job until approved again. When the prompt names a file that isn't pinned, the sheet says so plainly. Detecting a named file is best effort; a guide shipped inside Duo avoids the problem. A pin can't reach what that file itself reads.
- A committed job is off on every other Mac until that person approves it. A job can't fire on two people's Macs unless both chose that.

**Machine-local files**, all under `<support>/jobs/`: `approved.json`, `state.json` (paused, last due time, misses in a row), `fires.jsonl`. Each log line has: job, project, due time, time acted, result (`fired` or `skipped: missed|still-open|not-due|check-failed|changed|no-claude`, with a one-line reason), trigger (`schedule` or `manual`), runner, session id, mode, model, and the prompt's exact text.

```json
{"job":"01J…","title":"Dream","project":"<root>","due":"2026-11-09T13:00:00-05:00","at":"2026-11-09T13:00:21-05:00","result":"fired","trigger":"schedule","runner":"duo","session":"<uuid>","mode":"dontAsk","model":null,"prompt":"Run this project's knowledge dream: …"}
```

**Readers use `duo2 job log --json`, which works with Duo closed.** The log says what the scheduler did and never follows the session. A reader who wants to know how a run ended uses its session id, as `duo2 director status` does. Directors' red lines should read the verb rather than the file, so the format can change.

**Importing legacy `cron-jobs.json` (LR-66): not worth it.** This Mac has none. A legacy `same` job can't carry over, nor a shell job nor catch-up. Each import would need a fresh approval anyway, so retyping a job is about the same effort. If the work Mac turns out to have some, `duo2 job import` can list them for a person to recreate. **Recommendation:** drop the cron file from LR-66; the rest of LR-66 is unaffected.

## 7. `duo2` verbs (DL-71)

| Verb | What it does | UI |
|---|---|---|
| `duo2 job list [--project <p>]` | Jobs with schedule in English, next fire, last outcome, approval, runner | jobs list |
| `duo2 job show <job>` | The prompt, schedule, mode, model, recent fires | job row |
| `duo2 job new <title> --project <p> (--every … \| --cron …) [--at] [--on] (--prompt <t> \| --prompt-file <f> \| --run <command>) [--when <check>] [--mode <m>] [--allow <rule>…] [--model <m>] [--runner duo\|desktop\|cloud]` | Writes the note. **Off until approved** | job editor |
| `duo2 job edit <job> …` | Changes the note, which needs approval again | job editor |
| `duo2 job approve <job>` | Opens Duo's sheet with the prompt and schedule; waits for the user | Approve |
| `duo2 job run <job>` | Fires now with the same prompt, logged `manual`. No `--prompt` | Run Now |
| `duo2 job pause <job>`, `resume <job>` | On this Mac | Pause, Resume |
| `duo2 job rm <job>` | Removes note and state; the note goes to the Trash, and `duo2 undo` restores it. Sessions stay | Delete |
| `duo2 job log [<job>] [--project <p>] [--sessions] [--json]` | Every due time, fired or skipped, with the reason and session id. `--sessions` lists only the job sessions' ids, for `gather` to leave out. Works with Duo closed | fire log |
| `duo2 job preview --every … \| --cron …` | English and next fire | editor's preview |

**Verbs that deliberately don't exist:** `job send`, `job continue`, `job answer`, `--session same`, `--catch-up`, `--mode bypassPermissions`. DuoChecks should assert their absence, so a later convenience can't quietly undo the policy. The verbs write through the same code with Duo closed where they can (`list`, `show`, `log`, `new`), like `director status`; `approve` and `run` need Duo.

## 8. The dream as the first job

### Requirements from the learning loop

*From director-learning-loop-39b71d, by message, 2026-11-08, condensed but in its words; its study is `docs/research/project-knowledge.md` at 139887f on `director/learning-loop`.*

- **Status:** "The dream isn't approved to build. Geoff chose a hand-run pilot after the learning loop merges, and we build only if fresh sessions answer clearly better with the pages (DL-322, ENH-325). None of its verbs exist yet. Treat it as a likely first customer, and don't let recurring jobs' scope depend on it." And: "the dream needs nothing from this feature until its pilot finishes."
- **Cadence:** "Check daily per project, expect a dream about weekly on a busy project and rarely on a quiet one." Time of day: "check daily at a time the Mac is normally on. A miss then costs a day."
- **Trigger:** "a clock job plus a built-in due check serves me, and I'd recommend it to Geoff. Keep the director's red line as the backstop, not the only trigger." The red line "still fires when a dream is due and no job is set up, or the job has stopped working, which covers Duo being closed for days."
- **Due means** (guesses until the pilot): "5 or more tasks closed since the last dream, or 14 days with at least one closed, or an inbox note waiting, or a page past `stale_after`." It reads "`_knowledge/log.md`'s newest entry, task notes' status and dates, the inbox count, and page frontmatter. No model, no network." It wants "named built-in checks", not a shell command, and owns what the check decides.
- **Prompt:** "Run this project's knowledge dream: follow `duo2 knowledge guide`, then stop." The same for every project. "No dates, no arguments. State is on disk", and `log.md`'s newest entry "advances only when the run's check passes, so a skipped or failed run loses nothing."
- **Reads:** "through `duo2 knowledge gather` only", plus `duo2 search`, read-only. **Writes:** "`_knowledge/` only, a snapshot under `.duo/`, and `status: suggested` Failure tasks in `tasks/`." "It never commits or pushes." It runs "at the project root of the main checkout, never a work tree".
- **Refused:** "it doesn't try another route. It keeps what's done, says what was refused in its last message, and stops."
- **Tool limits:** "a dream reads untrusted transcripts, unattended, in Auto, so a successful injection has whatever Auto allows." It asks for an optional field, "included in the hash and shown in the sheet", and for the restricting flag to be checked. "Subagents have to stay available."
- **Result:** "A dream can finish well with zero human action." `_knowledge/log.md`, the session's last message and the fire log carry it, "none of them a message from the dream." `duo2 director status` is the main path: it "reads `duo2 job log --json`, works out each session's state from its id, and shows a red line for a finished run nobody has checked."
- **Disputes:** "disputes about facts still go to the user. The director relays them and doesn't settle them (DL-322), even though DL-325 lets it answer the session. It also can't approve a permission for a job session (Never 1)."
- **Concurrency:** "One dream per project is enough. If the last is still running at fire time: skip and log".
- **Asks of the log:** "keep the check's one-line reason on `skipped: not-due`, and add a separate `skipped: check-failed`. A broken check must not read as 'nothing to do'." Session ids in the log meet its need for `gather` to leave dream sessions out.
- **What the policy costs it, "all acceptable":** it must finish in one turn, so `gather` caps each run at the oldest 20 closed tasks, and a run that dies leaves a marker for the next to restore from. "Nothing in the dream needs a second prompt."

### How the design meets them

Geoff chose the trigger below (Q-476).

| Need | Design | Gap |
|---|---|---|
| Daily check, fire only when due | `schedule` daily plus `when: knowledge-due`: a named check compiled into Duo, sharing one function in DuoControl with R10's red line | The check waits on `duo2 knowledge due`, which isn't built |
| Broken check is visible | `skipped: not-due` keeps the check's reason; `skipped: check-failed` is separate and shows in the job's row | |
| The clock isn't the only safeguard | Every due time leaves a log line, so R10 can see a job has gone quiet. The mode is on the command line, so F-605 can't recur | Needs Duo open: R10 covers the rest |
| One fixed prompt | The body of the note. Its guide ships inside Duo, so it avoids the named-file gap below | None |
| Tool limits | `tools:` and `allow:` in the note (below) | Checked from `--help` only |
| Reads and writes, root only | The session runs at the project's root; `allow:` can hold the writes to `_knowledge/`, `.duo/` and `tasks/` | `duo2 knowledge` is the worker's to build |
| Result with no message | `duo2 job log --json` gives job, result and session id, with Duo closed. `duo2 director status` works out the session's state. A `watch` line is an extra. F-604 still applies: the director has to say it to you | |
| Disputes and permissions | DL-325 lets a director answer a job's session; DL-322 keeps fact disputes with the user, and the skill's Never 1 keeps permission approvals from the director | The scheduler never answers anyway |
| Overlap | `skipped: still-open` | |
| A dream's own output as evidence | `duo2 job log --sessions` lists job sessions; `DUO_JOB` marks them too | |
| A job only on the user's yes | The approval sheet, including when a director proposes the job | |
| `_jobs/dream.md` stays private | Whoever creates it adds it to `.gitignore` in a repo with a remote, as with `_knowledge/` | `duo2 job new --private` could do this; a build detail |

**The dream's note, as the design stands (thresholds and rules are the worker's to settle after the pilot):**

```markdown
---
type: job
title: Dream
schedule: "30 12 * * *"
when: knowledge-due
mode: dontAsk
tools: [Read, Glob, Grep, Edit, Write, Bash, Agent]
allow: ["Edit(_knowledge/**)", "Write(_knowledge/**)", "Bash(duo2 knowledge *)", "Bash(duo2 search *)", "Agent"]
runner: duo
---
Run this project's knowledge dream: follow `duo2 knowledge guide`, then stop.
```

**Which flag truly restricts** (worker's C-164, checked 2026-11-08; `--help` on 2.1.219, 2.1.284 and 2.1.316, and the permission-modes doc; **no session was run**):
- All three versions accept `--tools`, `--allowedTools`, `--disallowedTools` and `--permission-mode dontAsk`.
- **`--allowedTools` alone doesn't restrict.** In Auto it pre-approves, other actions still go to the classifier, and Auto drops broad rules on entry ("`Agent` allow rules", blanket `Bash(*)`).
- **`--tools` removes built-in tools** from the session. It's coarse: `Bash` is all of Bash.
- **`dontAsk` with an allow list is the true allowlist.** Docs: it "auto-denies every tool call that would otherwise prompt you", and "the session never waits for input". Reads inside the working folders and read-only Bash still run. It also denies `AskUserQuestion`, so a job in this mode can't ask anything: it reports in its last message.
- **To test at build, on Haiku with approval:** whether subagents inherit `dontAsk` (the doc doesn't say), whether path rules hold through `Write`, and all of this on 2.1.284. Auto's built-in default needs 2.1.228, so a work Mac at the old 2.1.219 floor may differ. `dontAsk` is why this doesn't have to rely on Auto.

Geoff said sessions *can* start in Auto; a job picks its mode, and the dream would pick the narrower one. `tools:` and `allow:` are in the approval hash and shown in the sheet.

**A named check is not a shell job.** `when:` takes a name from a short list compiled into Duo, with no way to supply a command, and a job with no `when:` always fires at its time. Shell jobs exist separately, as their own kind, by Geoff's choice (DL-325).

**A dream a day means a log line a day.** Most will be `skipped: not-due`. They don't count as misses, and the job's row should say the last *fire* as well as the last check (Q-474).

**Order matters.** The pilot is by hand and comes first, and the dream may not survive it. **Recurring jobs shouldn't wait for the dream, nor be justified only by it.**

### The director's own jobs (discovery, tidy, deep review): later, not now

They stay on Claude desktop tasks (DL-240). They're already nearly one-canned-prompt ("follow `docs/director/<job>.md`"). Moving them needs all of:
1. Duo's runner has run real jobs for weeks with no missed-while-open or stuck fires.
2. Geoff's Duo is reliably open and current (F-606 showed three days on an old build).
3. Each job's connector access works from a Duo terminal session, as it does on Desktop.

Deep review's "starts a worker" raises no problem: a job's session may start others like any session (DL-325).

The gain would be real: R3 could read Duo's log rather than Claude's private files.

## 9. What needs a design round (DL-26)

Nothing below is drawn. Each is a stand-in and a question until Geoff approves a canvas.

- **Q-472, the jobs list.** Where do a project's jobs show (sidebar, Home, the project's page), and what does a row say (schedule in English, next fire, last outcome, runner, approval)? Legacy had rows under Home's project cards.
- **Q-473, the job editor and approval sheet.** Presets and cron with the English preview, the prompt or command, mode, model, runner. The approval sheet shows the prompt or command in full, and a diff when it changed. It also has to say what `runner: desktop` doesn't enforce, and that a shell job runs with your full permissions. Legacy created shell jobs only by CLI (its D13); whether v2's editor offers them is part of this question. A shell job must look different from a prompt job in the list, legacy's known issue.
- **Q-474, the fire log.** Per job or per project, and how a skipped line reads. Does it open the session?
- **Q-475, job sessions and needs-you.** How a job's session is marked ("scheduled", never inferred, as ENH-231 did), how its needs-you reads, and where many sessions from one job go: a group per job, a fold, or something else. A daily job makes 30 sessions a month in the project's list.

## 10. Pros, cons, cost

**For:** the same feature on the work Mac and at home; the policy is visible and testable; the dream gets a place that doesn't depend on a director waking; legacy's engine and tests port across.

**Against:** a new scheduler to keep working; no fires with Duo closed; an approval step for every change; a job that asks a question costs you a look, on purpose; and jobs add session clutter until Q-475 is settled.

**How the policy keeps you in control without making the feature useless.** Most useful jobs are one prompt: a report, a scan, a dream. They finish alone in Auto with nothing further needed. The policy only bites at the moment a job needs a decision, which is when you'd want it to stop. The real cost is a job that stalls overnight on something trivial, and the remedy is your allow rules, not the schedule.

**Cost (Sonnet, after the design round):**
- Schedule engine and tests, ported to Swift and DuoChecks: small.
- Note, approval, state, log, timer, fire path, `duo2 job`, the policy checks: medium, one or two sessions.
- `runner: desktop` and `cloud` as read-only links: small, and can follow.
- Surfaces: per the design round.
- No background cost when no job is due, beyond a 30 s clock check.

## 11. Decisions for Geoff

Asked by AskUserQuestion, recommendation first; answers are in §12. None is open.

## 12. Geoff's answers (2026-11-08, by AskUserQuestion)

1. **Runner** (DL-324). He first asked "how did duo v1 do this?". Told it was a 30 s timer inside the app, with fires typed into a background tab and no launchd or Claude scheduler, he chose "Like v1, Claude optional": the recommendation.
2. **Directors** (DL-325). Not the recommendation, in his words: "the director may control scheduled jobs like any other -- only the scheduler must not approve claude commands".
3. **Shell jobs** (DL-325). "Keep, fixed and approved": not the recommendation.
4. **Where a job lives** (DL-324). "`_jobs/` note + approval": the recommendation.
5. **What he used in legacy.** No preference given, so the design doesn't rely on an assumed habit.
6. **The dream's trigger, if it survives its pilot** (Q-476). "Daily clock + check": the recommendation, and what the learning-loop worker asked for. The director's red line stays as backstop.
7. **A prompt that names a file** (Q-477, DL-324). "Pin the files": the recommendation.
