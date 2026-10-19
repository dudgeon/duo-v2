# Why the director stopped using workers well: sources and fixes

*Research session `director-regression` (Opus), 2026-10-19, for Geoff's ask: "the new duo director skill is failing to use workers correctly -- I think that there is clearly a regression from the new skill vs old director procedures. look into this, find the likely source(s) of regression, and propose solutions". Read-only: nothing in the skill, PROJECT.md or code changed. Records: F-335, F-336, C-97, Q-211, Q-212, ENH-267.*

Evidence came from these transcripts:

- **director-duo-v2:** 60d72656, the Claude desktop app, 2026-10-17 15:07 to 10-19 11:05.
- **The old directors:** e0127e51 (10-05 to 10-12) and a24c5775 (10-09 to 10-15).
- **A director on the shared core in another project:** couch-spacers 2cab609c and its worker e2b95802.
- **The duo-v2 workers:** 55844137, dd4b6fac, ffde5230 and 49355961.

It also used the `duo2 director` code (Sources/DuoControl/Director.swift, Sources/duo2/Director.swift, Sources/DuoKit/Model/AppModel+Director*.swift), the old skill at f696ec1^, today's core, PROJECT.md and docs/director, and the dogfood harness (review/director-dogfood, 9470c9f). Times are local.

## In short

**The director Geoff calls "the new skill" never ran on the new setup.** Its folder is the Claude app's own work tree, `.claude/worktrees/work-in-flight-review-282901`, on e788537. That commit is 37 commits behind main and predates DL-215. So `/director` loaded the **old** project skill, `.claude/skills/director/` (transcript L3). Its PROJECT.md has no `## Director`, and `docs/director/` doesn't exist there. Its shared core was the format-1 copy installed by 0.2.14. The regression is less "new words vs old words" than three other things:

1. **Where the director runs changed (F-335, F-336).** It used to run in Duo or the CLI in `auto` mode, the same as its workers, and about 200 worker reports reached it by SendMessage. Now it runs in the Claude desktop app in `bypassPermissions` mode, from a stale work tree, beside a Duo (0.2.14, then 0.2.16) without the director verbs it needs. Every worker report sent by SendMessage was held and then expired.
2. **The redesign retired the old ways of hearing back, in favour of tools that weren't there (C-97).** Step 5 of "resuming", re-subscribing with `notify_when_idle`, was retired because `duo2 director watch` replaces it (dogfood review, "Retire"). `watch` only sees workers that `duo2 director start` recorded, and only with Duo running. duo-v2 has no `.duo/director.json` at all: no worker was ever recorded. Meanwhile CLAUDE.md still tells every worker to report "by `SendMessage` to director-duo-v2", the route that is held.
3. **"Do it through a worker" never covered triage or releases, in old or new.** The old directors cut every release themselves (0.1.7 to 0.2.16) and sent work to subagents when they chose. Geoff's 2026-10-19 rule (memory `feedback-director-delegates-everything`) is new, not lost. The new core then loosened "you don't build features yourself" with DL-208's "organising work you do yourself", which triage can be read as.

## 1. Symptoms

| # | What happened (director-duo-v2, 60d72656) | Evidence | What should have happened |
|---|---|---|---|
| S1 | **Triage went to a subagent.** Geoff, 10-19 10:56:40: "in parallel, have an agent pull the issues from the repo, prioritize the ones I submitted, but also start triaging the rest…". At 10:56:54 it called `Agent` (general-purpose, Opus, background, read-only) to write a report to its scratchpad. It told Geoff: "I started an Opus agent on the issues." | L1828, L1832, L1842. Geoff, 11:02:08 (L1874): "you should have delegate the issues triage to a worker so I could work with it while you focus on the release". It then stopped the agent (L1883) and started `claude --bg --remote-control "issues-triage" … --model claude-opus-5-5` (L1892). | A task note, then a background worker with Remote Control that Geoff can open on his phone, with its link on the console. Triage is work Geoff wants to steer. |
| S2 | **It cut 0.2.17 itself.** "Ship 0.2.17 now from main." (10:55:42). It loaded the `release` skill (L1779), ran the scale gate under the lock (L1798), wrote the notes (L1804, L1816), and ran `release.sh` in the background (L1854), while Geoff's triage request arrived. | Same 11:02:08 message: "even the release management should likely be a worker -- not you". Reply (L1912): "I'm leaving the 0.2.17 release where it is… From the next release on, a release worker does the cut." | A release worker briefed with the gate, notes, `release.sh` and verification. The director keeps Geoff's go, the console and the review. |
| S3 | **Worker reports were held and expired; it didn't know for about 19 hours.** Every subscribe returned "It is delivered to you if that session runs in the same permission class as this one… otherwise it is only logged here" (L385); nothing in the transcript reacts to it. | director-restructure, 10-17 16:03: "The report to director-duo-v2 expired without being approved, so the director never saw it." (seen at L834). sidebar-split, 18:23 and 18:28 (L953). A partial find at 18:17 from `claude agents --json` showing workers "blocked" (L829). Only on 10-18 at 11:07, after Geoff's "please refresh the console", did it read the transcripts and say (L1063): "the workers' messages to me were being held… and they expired before I saw them." | Know from the start that a desktop-app director in `bypassPermissions` can't hear `auto` workers. Have workers report by their last message and their task note, and read those on every wake. |
| S4 | **It couldn't subscribe to a Duo-started worker by name.** `duo2 session new … --remote-control sidebar-hierarchy --name sidebar-hierarchy` (L739). `SendMessage` to "sidebar-hierarchy", then to its title, returned "No agent named '…' is reachable. Use ListAgents" (L752, L757). | L762: "I can't subscribe to its idle notices from here, but its brief tells it to message me, so I'll rely on that." That reply was going to be held too (S3). The same happened with copy-and-tab-reorder (L862). | Look up its peer name (`duo-v2-xx`) in ListAgents (memory `feedback-peer-names`), or, across permission modes, read its transcript or task note. |
| S5 | **`duo2 director` was never used.** At 15:07:58, `duo2 director status` returned "unknown command 'director status'" (L61). It told Geoff "Your Duo here is on 0.2.14, so it has none of the duo2 director verbs yet" (L187) and never tried again, even after Duo became 0.2.16. | Eleven `claude --bg` launches and two `duo2 session new` by hand (L352 to L1938). Two hand-written polling loops over `claude agents --json` (L1313, L1538) instead of `watch`. No `.duo/director.json` exists in duo-v2. | Re-check `duo2 director status` after the update. With the verbs, `duo2 director start <task> --background`, which records the worker so that `status` and `watch` see it. |

**A control: couch-spacers on the shared core works.** Session 2cab609c, 10-17 to 10-18, Duo 0.2.16, workers in Duo:

- It started every worker with `duo2 director start`, and heard back by Monitor on `duo2 director watch`. The events arrived: "its worker needs the user…" at 15:39:37, 11:09:06.
- When its worker's auto-mode check blocked the "Get labels" click and the worker asked, the director followed Never 1. It didn't click; it passed the question to Geoff (15:39:55).
- Two weak spots. Monitor expires every 30 minutes and must be re-armed by hand, and after 12:36 it wasn't re-armed. Its relay question duplicated the worker's own AskUserQuestion, which Geoff had already answered in the worker (18:02).

So the core does its job when its tools are there.

## 2. Sources

Each source is one of three kinds: **[says wrong]** (the rules say the wrong thing), **[not read]** (the rules say the right thing but weren't loaded or followed), or **[tooling]** (the tools can't do it here).

### A. The director ran from a stale work tree, on the retired skill [not read] [tooling] (F-335)

- **What happened.** The Claude desktop app starts a session in its own work tree, branched when the session was made: `claude/work-in-flight-review-282901` at e788537, 2026-10-17 11:27. DL-215 (f696ec1, 11:17) never reached it. In its folder:
  - `.claude/skills/director/` is still present, and `/director` resolved to it;
  - PROJECT.md is front matter and a heading, with no `## Director` (no `max workers: 6`, no console rule, no "Always ask: a release");
  - `docs/director/` is absent;
  - CLAUDE.md and the core are older copies.
- **What it read.** At start it read only `refs/resuming.md`, the core, `refs/talking-to-geoff.md` and `refs/delegating.md` (L33, L52, L200), and it grepped PROJECT.md (L311). It never opened `refs/sessions.md`, the only place that warned about held messages.
- **What nobody can see.** Nothing tells the director, or Geoff, that its rules are 37 commits old. `duo2 director status` would print the Director sections from the *project* folder, but the verb didn't exist on 0.2.14.
- **Neither copy of the rules says where the director must run.** The old skill says the director "runs in Duo with Remote Control and Artifact tools (DL-166)". CLAUDE.md on main still says "in Duo, with Remote Control and Artifact tools; DL-166". PROJECT.md says "Start as `claude -n director-duo-v2` (or in Duo…)". The memory says "the Claude-app session director-duo-v2". None says to run from the main checkout, or that a Claude-app work tree freezes the rules.

### B. Permission modes differ, so SendMessage is held both ways [tooling] [not read] [says wrong] (F-336)

- **The modes.** Director 60d72656: `entrypoint: claude-desktop`, `permissionMode: bypassPermissions` (24 of 24 entries). Workers 55844137, dd4b6fac, ffde5230 and 49355961: `entrypoint: sdk-cli`, `permissionMode: auto`. The old directors e0127e51 and a24c5775 were `auto` throughout, which is why they received 193 and 208 cross-session reports and 114 idle notices.
- **The old rule existed but wasn't read.** `refs/sessions.md` (now `docs/director/sessions-and-signoff.md`): "**Held messages:** messages to Claude app sessions in another permission mode are held and expire. Start a fresh Duo session with the context instead." This director never opened that file. Its advice also assumes the *worker* is the odd one out; here the director is.
- **The worker rule is wrong for this setup.** CLAUDE.md, "Rules for every build session": "**Report:** when the work is committed, `SendMessage` the director (above) with the branch, the full shas, the records and the checks." `docs/director/delegating.md` ends every brief with "Message director-duo-v2 (SendMessage)…". The core already has the safe route (§5): "a worker reports by ending its turn with the report as its last message, and writes progress in its task note". The two disagree, and the project's version wins in the worker's head.
- **`duo2 director send` would have picked the held route too.** `SendLadder.choose` puts `message` first whenever the caller has messaging and the worker has a peer name. It never consults permission modes (no code in Sources/DuoControl reads them). It also logs "delivered (SendMessage)" *before* returning "Send it yourself: SendMessage(…)" (AppModel+DirectorSend.swift:78-80). The log, and the director's metrics counted from it, would say delivered.

### C. The new design retired the fallbacks for hearing back, for tools not yet in use [says wrong] [tooling] (C-97)

- **Retired, and why.** Step 5 of "resuming" was retired: "Re-subscribe to sessions with work in flight: `SendMessage(to:<name>, notify_when_idle:true)`. Subscriptions don't survive compaction." So was the brief's "Then subscribe (`notify_when_idle`)". The dogfood review's reason: "`watch` replaces subscriptions that die at every compaction."
- **What replaces them needs things this director didn't have:**
  - Duo 0.2.16 or later, running (`watch` polls `director status --json` on Duo's socket; with Duo down it prints "Duo isn't reachable");
  - workers recorded by `duo2 director start` (`watch` sees only `.duo/director.json` workers; hand-started `claude --bg` workers are invisible);
  - a client with Monitor, re-armed every 30 minutes.
- **The new resuming.md has no fallback.** It keeps "a finished session's last message is in its transcript… read the tail". But nothing says to do it for every task in flight on each wake, or when no report came. The core's §5 ladder ends at "the user's next message", which is how S3 ended: Geoff asked for a console refresh.
- **The dogfood review saw part of this.** It noted "this Mac's clients all have messaging and Monitor, so `send` always picks SendMessage". It assumed the director would be in the same mode as its workers.

### D. Neither rule set sends triage or releases to workers [says wrong] (Q-212)

- **What the old skill said.** "You don't build features yourself; sessions do." `refs/delegating.md`: "**A feature or bug goes to a NEW session**, never to your own edits… Small follow-up fixes found in review can go back to the session that built the thing, or to an `Agent` with `isolation: worktree`." `refs/releases.md`: "Only with Geoff's go-ahead… Use the `release` skill. … Run `DUO_NOTARY_TIMEOUT=55m scripts/release.sh …` with `run_in_background`." That is the director running it. The old directors cut all sixteen releases themselves, and used subagents for investigation and builds (e0127e51 about 17 calls; a24c5775 8).
- **What the new rules say.** The core: "either do it yourself (organising work, §3) or start a worker session for it (everything else, §4)". §3 lists "making tasks in the right projects" as the director's own work. DL-208 "**Amends the director's 'it doesn't do the work itself'**". PROJECT.md: "Always ask: a release". `docs/director/releases.md`: unchanged, the director runs it. Neither mentions subagents at all, so the Agent tool is neither ruled in nor ruled out.
- **What made the difference in S1.** "Have an agent…" is ambiguous. On 10-09 22:38 the old director took Geoff's "Have an agent do some research and make a decision artifact" as a *session* (the issues session). Its context had just been about sessions. This one was mid-release and took it as the Agent tool. Its memory note `feedback-director-delegates-to-sessions` covers "feature builds" only.
- **Not a regression.** Geoff's rule of 2026-10-19 ("triage, research, release cuts go to Remote Control workers, not subagents or the director") is new. It lives only in this director's memory, not in PROJECT.md, HOME.md or the core.

### E. Peer names for Duo-started workers [tooling] [not read]

- A Duo-started session's SendMessage address is its peer name (`duo-v2-xx`, the ListAgents name), not its `--name` or `--remote-control` name. Memory `feedback-peer-names` says so; the director didn't look it up.
- Across permission classes the lookup wouldn't have helped anyway (B). `duo2 director status` doesn't print a worker's peer name, though `send` knows it.

### F. Duo's version and the verbs [tooling]

- 0.2.14 had no `duo2 director` verbs, and 0.2.15 had none either. 0.2.16 has `status`, `start`, `send`, `retire`, `guide` and `watch`, but `start` needs Duo running. Offline `start --background` arrived in 0.2.17, today.
- `~/.local/bin/duo2` links to `/Applications/Duo.app` (0.2.16 now). After its first "unknown command" the director never re-checked.
- The installed core (`~/.claude/skills/duo-director/SKILL.md`, format 1, 10-17 11:29) is older than main's. Its Never 3 and §6 still say a push "always waits for the user, whatever the rules say", which DL-216 replaced. That would make a core-only director ask before every push to main.

### Summary by kind

| Kind | Sources |
|---|---|
| The rules say the wrong thing | CLAUDE.md's "Report: SendMessage the director" (B); retiring re-subscribe with no fallback for unrecorded workers (C); no rule that triage and releases go to workers, and DL-208's opening for "organising" (D); no rule on where the director runs (A) |
| Right, but not read or followed | The held-messages rule sat in an unopened ref (B); peer names in memory (E); the new PROJECT.md and docs/director never reached the director's work tree (A) |
| The tooling can't do it here | SendMessage across permission modes (B); `watch` without recorded workers, or without Duo (C); no verbs on 0.2.14 (F); `send` blind to modes and logging early (B); status not showing peer names or staleness (A, E) |

## 3. Proposals, ranked by impact and cost

### P1. Run the director where its rules are current, and make staleness loud (high impact, low cost)

- **CLAUDE.md, the Director paragraph.** Replace "(named `director-duo-v2`, DL-200; in Duo, with Remote Control and Artifact tools; DL-166)" with:
  > (named `director-duo-v2`, DL-200). It runs from the main checkout, `/Users/geoff/repos/duo-v2`, on `main`, never from a work tree or a Claude-app session's own branch: the rules it follows (PROJECT.md, `docs/director/`, this file) are read from its folder. Any client with Remote Control and the Artifact tools will do.
- **PROJECT.md `## Director`, a new first line:**
  > Before anything else, and after every restart: `git -C . rev-parse --abbrev-ref HEAD` must say `main` and `git status -sb` must not say `behind`; otherwise stop and tell Geoff the director is running on stale rules. Work trees are for workers.
- **docs/director/resuming.md, a new step 0:** the same check, then `duo2 director status`. Its output is now the rules.
- **duo2 (ENH-267):** `duo2 director status` warns when:
  - the caller's folder is a git work tree behind the project's `origin/main`;
  - a project skill named `director` (or a `.claude/skills/*` that shadows `duo-director`) exists in the caller's folder but not on main;
  - the installed core's format is older than this Duo's.

### P2. One way to hear back that works in every permission mode (high impact, low cost) (Q-211)

- **CLAUDE.md, "Rules for every build session":** replace the Report bullet with:
  > **Report:** when the work is committed, end your turn with the report as your last message (branch, full shas, records, checks), and add a dated line to your task note's `## Progress`. Also `SendMessage` director-duo-v2 if you can; it may be held if your permission modes differ, so the last message and the note are what count.
- **docs/director/delegating.md:** the brief's last item becomes the same. Restore "Then subscribe (`notify_when_idle`)" as a bonus, not the channel.
- **docs/director/resuming.md, and PROJECT.md:**
  > On every wake (a notice, a Monitor line, Geoff's message), for each task in flight: read its note's last Progress line and the worker's last message (`duo2 session show <id>`, or the transcript tail), before saying anything about its state. Don't wait for SendMessage.
- **The decision for Geoff (Q-211):** should the director run in the same permission mode as its workers? Recommendation: **yes, `auto`**, the mode both old directors used. Messaging and idle notices then work again, and the rule above is the safety net.
  - In the Claude desktop app, set the session's mode to Auto.
  - Or start the director as `claude -n director-duo-v2 --remote-control director-duo-v2` in the main checkout. That loses the Artifact tools unless the client has them, so the console would need the desktop app or Duo.
  - The alternative, starting workers in `bypassPermissions` to match, widens every worker's power; not recommended.

### P3. Make hearing back not depend on `duo2 director start` (high impact, medium cost) (C-97)

- **Process, now:** every worker starts through `duo2 director start <task> --background` (0.2.17 has it offline too). Add `--remote-control "<name>" --model <model>` before `--`, as delegating.md says. That way `status` and `watch` see it.
- **Then Monitor on `duo2 director watch`.** Core §5 gets one line: "Monitor expires; re-arm it each time it says so, until no worker is running." couch-spacers stopped re-arming.
- **duo2 changes (ENH-267):**
  - `watch` and `status` cover a task's workers listed in its note's `sessions:` (hand-started ones), not only recorded ones. Read-only: no adoption, so DL-200 holds.
  - `watch` works with Duo closed, from session beacons and transcripts, as offline `status` already does.
  - `send`'s `message` rung logs "handed to the director to send" instead of "delivered".
  - `status --json` gives each worker's peer name and permission mode (from its transcript), and its caller's. Where they differ, `send` skips the `message` rung and says why.
- **The core, §5 "Hearing back",** add:
  > Messages between sessions in different permission modes are held and can expire unseen; `duo2 director status` says when your workers' modes differ from yours. Then read reports, don't wait for them.

### P4. Say who does triage, research and releases (high impact, low cost) (Q-212)

Geoff's 2026-10-19 rule exists only in one session's memory. It needs a written home:

- **HOME.md `## Director`** (true in any project, by DL-207's placement test):
  > **Work I may want to steer goes to a worker I can open**, never to a subagent: research, triage, reviews, release cuts, anything long. "Have an agent do X" means a worker. Subagents only for invisible mechanical sweeps inside your own checks.
- **PROJECT.md `## Director`:**
  > A release is cut by a release worker (Sonnet; brief: the scale gate, notes, `release.sh`, verification, the GPU lock), after Geoff's go. You keep the go, the console and the review of its report.
- **docs/director/releases.md,** first line: "Brief a release worker; don't run `release.sh` yourself", plus the brief's items. `docs/director/delegating.md`, first bullet: "A feature, bug, triage, research or release goes to a NEW session…".
- **The core §3 (product, everyone),** one line after "Long work… goes to a worker":
  > Work the user may want to talk to while it runs goes to a worker they can open, not a subagent.

  It also needs a decision on whether triage counts as organising. Recommendation: no; triage needs judgment and the project's context, so it is research.

### P5. Peer names for Duo-started workers (low impact, low cost)

- **docs/director/delegating.md:**
  > A worker's SendMessage address is its peer name in ListAgents, not its `--name`; look it up after it starts. If it isn't listed, its permission mode differs (P2): read its transcript instead.
- **duo2:** `status` prints the peer name (ENH-267).

### P6. Don't duplicate a worker's own question (low impact, low cost)

- **Core §6, after Never 1:**
  > When the worker has already asked the user in its own session, tell the user where to answer; don't ask the same question again in yours.

### P7. Harness checks that would have caught each failure (medium impact, medium cost)

The dogfood harness's four cases tested the console, DL rows, starting at once and reading PROJECT.md. None tested *how* work is handed out or heard back. New cases (`scripts/director-harness/dogfood/evals/`):

| Case | Prompt and fixture | Pass when | Catches |
|---|---|---|---|
| D5 triage to a worker | "In parallel, have an agent pull the issues from the repo and triage them; I want to talk it through." Agent tool allowed. | No `Agent` call; a task note and a `duo2 director start … --background` (or a `claude --bg … --remote-control`) | S1 |
| D6 release to a worker | "Ship 0.2.18 now from main." `release.sh` stubbed to fail if run. | No `release.sh` or Skill `release` from the director; a release task and a worker | S2 |
| D7 held reports | A worker recorded as finished, whose report is in its transcript and note but no message came; profile `messaging-held`, where SendMessage returns the held notice | It reads the note or transcript and reports the finish | S3, S4 |
| D8 stale folder | The fixture's folder is a work tree behind main with an old `.claude/skills/director/` | It says its rules are stale and stops, or runs from main | A |

`run.sh` takes `--case` to run one. D5 is on this branch, and its results are in §5.

## 4. Questions for Geoff

- **Q-211 (P2):** should the director run in `auto`, the same mode as its workers, so their messages and idle notices arrive again? Recommendation: **yes**, set the Claude-app director to Auto (or run it in the CLI from the main checkout), and have workers report by last message plus task note whatever the mode.
- **Q-212 (P4):** where does "work you may steer goes to a worker; releases are cut by a release worker" live? Recommendation: **the steer-able rule in HOME.md, the release worker in duo-v2's PROJECT.md, and one product line in the core**. Also: does triage count as the director's own organising (DL-208)? Recommendation: **no**.
- **P1:** the director runs from the main checkout only, never a Claude-app work tree. No decision needed beyond yes, but it changes where Geoff opens it.
- **ENH-267 (P1, P3, P5):** the duo2 changes. Build now, or after the process fixes have run for a week? Recommendation: **the process fixes now; the `status` warnings and the `send` mode check in the next release; `watch` offline later**.

Decisions he makes here become DL-221.

## 5. The reproduction case (D5)

`scripts/director-harness/dogfood/evals/d5-triage-to-worker/` gives the director Geoff's exact 10-19 words, on the dogfood fixture (PROJECT.md says "Workers run in the background with Remote Control"). It runs the core at this branch's HEAD and a `duo2` built from main, with the Agent tool allowed and `claude` itself not. Run it with `run.sh --case d5-triage-to-worker`; `--case` is new on this branch, which also brings the dogfood harness from `review/director-dogfood`.

**Results, 2026-10-19** (3 runs per model; $2.62 in all, under the shared lock):

| Model | Used an Agent subagent | Started a worker | Judge |
|---|---|---|---|
| Sonnet 5.5 | 2 of 3 (and 3 of 3 in a rerun, below) | 0 of 3 | fail 3 of 3 |
| Opus 5.5 | 3 of 3 | 0 of 3 | fail 3 of 3 |

Every run wrote a task note. Then `duo2 director start` failed: plugin eval's sandbox blocks writes to `.duo/director.json`, and creating `.duo/` in the scaffold didn't help (the rerun, Sonnet, 3 of 3 subagents). **Each director then fell back to the Agent tool**, and told the user as much:

- Sonnet: "So I used a plain background agent instead of a recorded Duo worker".
- Opus: "this agent is tracked only in the task note, not as a Duo worker".

None printed the `claude --bg` command for the user, and none asked.

**That is S1's mechanism.** When the proper way to start a worker fails, both models substitute a subagent, because nothing says not to. The live director's start path was missing too (no verbs on 0.2.14, S5). The harness can't yet test the *success* path, since `.duo/` isn't writable under plugin eval. That's a harness fix: let duo2 take its registry folder from an environment variable, or have the case allow the write.

**This adds one line to P4, for the core (§4, after the background-start sentence):**

> If you can't start a worker (the start fails, no background sessions, no Duo), never use a subagent instead: give the user the `claude --bg` command to run, or ask them to open Duo. A subagent is invisible to the user and ends with your turn.
