# Why the director stopped using workers well: sources and fixes

*Research session `director-regression` (Opus), 2026-10-19, for Geoff's ask: "the new duo director skill is failing to use workers correctly -- I think that there is clearly a regression from the new skill vs old director procedures. look into this, find the likely source(s) of regression, and propose solutions". Read-only: nothing in the skill, PROJECT.md or code changed. Records: F-335, F-336, C-97, Q-211, Q-212, ENH-267.*

Evidence came from these transcripts:

- **director-duo-v2:** 60d72656, the Claude desktop app, 2026-10-17 15:07 to 10-19 11:05.
- **The old directors:** e0127e51 (10-05 to 10-12) and a24c5775 (10-09 to 10-15).
- **A director on the shared core in another project:** couch-spacers 2cab609c and its worker e2b95802.
- **The duo-v2 workers:** 55844137, dd4b6fac, ffde5230 and 49355961.

It also used the `duo2 director` code (Sources/DuoControl/Director.swift, Sources/duo2/Director.swift, Sources/DuoKit/Model/AppModel+Director*.swift), the old skill at f696ec1^, today's core, PROJECT.md and docs/director, and the dogfood harness (review/director-dogfood, 9470c9f). Times are local.

## In short

**Geoff's expectation is the right one.** A new Claude Code session, desktop app or CLI, in which the user invokes the director, should run the latest released director. It didn't, and the user did nothing wrong. Five product defects made sure of it (F-335):

1. **`/director` isn't the released skill.** Duo ships its director as `duo-director`, deliberately "never `director`, since a personal skill hides a project skill of the same name" (Installer.swift:37). So `/director` reached duo-v2's own project skill, `.claude/skills/director/`, which was still on main (transcript L3). The released skill was a different name nobody typed. duo-v2's project skill sat on main for four days after the core shipped: written 10-14, retired by DL-215 on a branch 10-17, merged 10-18 18:55. Every director session started in duo-v2 before then got it.
2. **The skill and the app it drives are released separately, and nothing checks they match.** At 15:07 on 10-17, `~/.claude/skills/duo-director/` held the 0.2.16 text (byte-identical to v0.2.16's). Geoff's running Duo was 0.2.14 (L180), three days after 0.2.16 shipped, because Duo updates only when the user clicks Install Now. Step 1 of the skill, `duo2 director status`, answered "unknown command" (L61). duo2 doesn't say "this Duo is too old for the director; update", and the skill doesn't say what to do when the verbs are missing. So the director did what it could by hand, and never re-checked once Duo was updated (couch-spacers was on 0.2.16 by 15:30 that day).
3. **A running director never picks up a newer skill.** A skill is read once into the conversation. This director ran from 10-17 to 10-19, through the restructure's merge (10-18) and 0.2.17 (10-19), on the text it loaded on 10-17. The Claude app also gave it a work tree branched at 15:07, so even re-reading files after a restart got 10-17's copies. Nothing (`status`, `watch`, Duo) tells a director its rules or skill changed.
4. **The director's permission mode decides whether it can hear its workers, and nothing checks it.** The Claude app session ran in `bypassPermissions`; the `claude --bg` workers run in `auto`. Messages between modes are held and expire, so the workers' reports never arrived (F-336). The old directors ran in `auto` and got about 200. Neither the skill nor `duo2 director` knows about modes; `send` even logs "delivered" before anything is sent.
5. **When a worker can't be started, the skill lets the director use a subagent.** Nothing in the old or new rules rules it out. The new dogfood case reproduces it in 8 of 9 runs on Sonnet and Opus (§5): the start fails, and the director starts "a plain background agent" instead.

Rule text played a smaller part:

- The redesign retired re-subscribing for `duo2 director watch` (C-97), so with the verbs missing nothing was left for hearing back.
- CLAUDE.md still tells workers to report by SendMessage.
- No rule ever sent triage or releases to workers. Geoff's 10-19 rule is new, and lives only in that director's memory (Q-212).

## 1. Symptoms

| # | What happened (director-duo-v2, 60d72656) | Evidence | What should have happened |
|---|---|---|---|
| S1 | **Triage went to a subagent.** Geoff, 10-19 10:56:40: "in parallel, have an agent pull the issues from the repo, prioritize the ones I submitted, but also start triaging the rest…". At 10:56:54 it called `Agent` (general-purpose, Opus, background, read-only) to write a report to its scratchpad. It told Geoff: "I started an Opus agent on the issues." | L1828, L1832, L1842. Geoff, 11:02:08 (L1874): "you should have delegate the issues triage to a worker so I could work with it while you focus on the release". It then stopped the agent (L1883) and started `claude --bg --remote-control "issues-triage" … --model claude-opus-5-5` (L1892). | A task note, then a background worker with Remote Control that Geoff can open on his phone, with its link on the console. Triage is work Geoff wants to steer. |
| S2 | **It cut 0.2.17 itself.** "Ship 0.2.17 now from main." (10:55:42). It loaded the `release` skill (L1779), ran the scale gate under the lock (L1798), wrote the notes (L1804, L1816), and ran `release.sh` in the background (L1854), while Geoff's triage request arrived. | Same 11:02:08 message: "even the release management should likely be a worker -- not you". Reply (L1912): "I'm leaving the 0.2.17 release where it is… From the next release on, a release worker does the cut." | A release worker briefed with the gate, notes, `release.sh` and verification. The director keeps Geoff's go, the console and the review. |
| S3 | **Worker reports were held and expired; it didn't know for about 19 hours.** Every subscribe returned "It is delivered to you if that session runs in the same permission class as this one… otherwise it is only logged here" (L385); nothing in the transcript reacts to it. | director-restructure, 10-17 16:03: "The report to director-duo-v2 expired without being approved, so the director never saw it." (seen at L834). sidebar-split, 18:23 and 18:28 (L953). A partial find at 18:17 from `claude agents --json` showing workers "blocked" (L829). Only on 10-18 at 11:07, after Geoff's "please refresh the console", did it read the transcripts and say (L1063): "the workers' messages to me were being held… and they expired before I saw them." | `duo2 director status` should have said that its workers' permission mode differs from its own, so their messages would be held. Workers should report by last message and task note, which `watch` reads whatever the mode. |
| S4 | **It couldn't subscribe to a Duo-started worker by name.** `duo2 session new … --remote-control sidebar-hierarchy --name sidebar-hierarchy` (L739). `SendMessage` to "sidebar-hierarchy", then to its title, returned "No agent named '…' is reachable. Use ListAgents" (L752, L757). | L762: "I can't subscribe to its idle notices from here, but its brief tells it to message me, so I'll rely on that." That reply was going to be held too (S3). The same happened with copy-and-tab-reorder (L862). | Look up its peer name (`duo-v2-xx`) in ListAgents (memory `feedback-peer-names`), or, across permission modes, read its transcript or task note. |
| S5 | **`duo2 director` was never used.** At 15:07:58, `duo2 director status` returned "unknown command 'director status'" (L61). It told Geoff "Your Duo here is on 0.2.14, so it has none of the duo2 director verbs yet" (L187) and never tried again, even after Duo became 0.2.16. | Eleven `claude --bg` launches and two `duo2 session new` by hand (L352 to L1938). Two hand-written polling loops over `claude agents --json` (L1313, L1538) instead of `watch`. No `.duo/director.json` exists in duo-v2. | duo2 should have said "this Duo is older than the director skill: update it", and the skill should have said to check again after the update. With the verbs, `duo2 director start <task> --background`, which records the worker so that `status` and `watch` see it. |

**A control: couch-spacers on the shared core works.** Session 2cab609c, 10-17 to 10-18, Duo 0.2.16, workers in Duo:

- It started every worker with `duo2 director start`, and heard back by Monitor on `duo2 director watch`. The events arrived: "its worker needs the user…" at 15:39:37, 11:09:06.
- When its worker's auto-mode check blocked the "Get labels" click and the worker asked, the director followed Never 1. It didn't click; it passed the question to Geoff (15:39:55).
- Two weak spots. Monitor expires every 30 minutes and must be re-armed by hand, and after 12:36 it wasn't re-armed. Its relay question duplicated the worker's own AskUserQuestion, which Geoff had already answered in the worker (18:02).

So the core does its job when its tools are there.

## 2. Sources

Each source is one of three kinds: **[says wrong]** (the rules say the wrong thing), **[not read]** (the rules say the right thing but weren't loaded or followed), or **[tooling]** (the tools can't do it here).

### A. The released skill never ran: wrong name, mismatched app, no refresh [tooling] (F-335)

- **The name.** The installer names the shared core `duo-director` on purpose (Installer.swift:37: "never `director`, since a personal skill hides a project skill of the same name"). duo-v2 kept a project skill called `director` on main until 10-18 18:55 (f696ec1 committed 10-17 11:17 on `director/restructure`, merged via `integrate/2026-10-18`). `/director` on 10-17 15:07 therefore loaded the old project skill (L2-3), from the session's folder. The released skill was installed, but under a name the user didn't type. The old skill told it to read the core too, and it did (`cat skills/duo-director/SKILL.md` from the repo, L52). It still followed the old skill's Duo-dev habits.
- **The app version.** The installed core (`~/.claude/skills/duo-director/SKILL.md`, written 10-17 11:29) is byte-identical to v0.2.16's. Geoff's running Duo was 0.2.14 (L180: `0.2.14 … /Applications/Duo.app`). The skill's first step failed with "duo2: unknown command 'director status'" (L61), and duo2 gave no hint that it was too old. The update path is a question the user must answer (AppModel+Update.swift: Install Now, or Later). The installer writes skills into `~/.claude` without checking that the duo2 on PATH has the verbs they call. By 15:30 Duo was 0.2.16 (couch-spacers' `status` worked); the duo-v2 director had decided at 15:09 that the verbs didn't exist and never looked again (L187).
- **No refresh.** The Claude app runs each session in its own work tree, branched at start (`claude/work-in-flight-review-282901`, e788537 = main at 15:07). Through 10-19 the session kept the 10-17 skill in context and 10-17 files on disk, while main gained PROJECT.md's `## Director` and `docs/director/` (10-18) and 0.2.17 shipped (10-19). Nothing tells a director that its skill, its Duo or its project's rules changed. `duo2 director status` does resolve a work tree to the main checkout (Director.swift:465), but only if it runs, and only when asked.

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
- The installed core is 0.2.16's: it was the released one until today. It predates DL-216, so its Never 3 and §6 still say a push "always waits for the user, whatever the rules say". A core-only director on 0.2.16 asks before every push to main, whatever PROJECT.md says, until Geoff installs 0.2.17.

### Summary by kind

| Kind | Sources |
|---|---|
| The rules say the wrong thing | CLAUDE.md's "Report: SendMessage the director" (B); retiring re-subscribe with no fallback for unrecorded workers (C); no rule that triage and releases go to workers, and DL-208's opening for "organising" (D); nothing that rules out a subagent when a worker can't start (§5) |
| Right, but not read or followed | The held-messages rule sat in an unopened ref (B); peer names in memory (E) |
| The product didn't deliver the released director | `/director` reaches a project skill, not `duo-director`; skill and app versions unchecked, with no hint when duo2 is too old; no refresh for a running director (A) |
| The tooling can't do it here | SendMessage across permission modes (B); `watch` without recorded workers, or without Duo (C); no verbs on 0.2.14 (F); `send` blind to modes and logging early (B); status not showing peer names (E) |

## 3. Proposals, ranked by impact and cost

### P1. A new session gets the released director, and a running one knows when it's stale (high impact, low to medium cost) (ENH-267)

Product changes, so Geoff's expectation holds without any habit on his part:

- **`/director` reaches the released skill.** Either name the shared core `director`, with the installer refusing (or asking) where a project skill `director` exists, or keep `duo-director` and also install a `director` personal skill that only says "use the duo-director skill". Today a personal skill named `director` would hide project skills of that name. That is the point for duo-v2 now that its project skill is gone, but a choice for other projects. **Question for Geoff (Q-212 adds it).**
- **The skill and the app check each other.**
  - The installed skill gets the version it came with (`format`, plus Duo's version in the header comment).
  - `duo2 director status` prints both and warns when they differ, or when Duo is older than the skill expects.
  - Any `duo2 director …` on a Duo without the verbs says "this Duo (0.2.14) has no director; update Duo (Duo › Check for Updates…)". That needs the message in the unknown-command path, for the future; a 0.2.14 can't be fixed after the fact.
  - The skill's step 1 adds: "If `duo2` says unknown command, Duo is older than this skill: tell the user to update Duo, and work by hand until then; check again after each of their messages."
- **A Duo update tells running directors.** When Duo updates (or its installer rewrites the skill), `watch` prints one line: "the duo-director skill changed (0.2.16 → 0.2.17): re-read it (`duo2 director guide`)". `status` says the same.
- **A running director re-reads its rules.** `status` already prints the Director sections from the main checkout (it resolves work trees). Add a line to PROJECT.md and the core §1: "On every wake, run `duo2 director status`; it carries the current rules, not the copy in your context or work tree." For a project's own `docs/director/` files, status names the main checkout's path, so the director reads them there, not in its work tree.

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
| D8 skill ahead of Duo | The fixture's duo2 answers "unknown command" to `director` | It tells the user Duo needs updating, works by hand with task notes, and starts no subagent | A, S5 |
| Installer check (DuoChecks) | An install into a scratch `~/.claude` that holds a project skill `director` | `/director` resolves to the released core (or the install warns) | A |

`run.sh` takes `--case` to run one. D5 is on this branch, and its results are in §5.

## 4. Questions for Geoff

- **Naming (P1, Q-212):** how should `/director` reach the released skill? Recommendation: **name the shipped skill `director`**, and have the installer ask before it hides a project skill of that name (duo-v2 no longer has one). Keep `duo-director` as an alias for a release.
- **Q-211 (P2):** hearing back shouldn't depend on which permission mode Geoff opens the director in. Recommendation: **the product fix** (workers report by last message plus task note; `watch` and `status` read them for every worker, including hand-started ones, and warn when modes differ). Running the director in Auto, as the old directors did, is a stopgap until then, not a requirement.
- **Q-212 (P4):** where does "work you may steer goes to a worker; releases are cut by a release worker" live? Recommendation: **the steer-able rule in HOME.md, the release worker in duo-v2's PROJECT.md, and a core line that never substitutes a subagent for a worker**. Is triage the director's own organising work (DL-208)? Recommendation: **no**.
- **ENH-267 (P1, P3, P5):** the duo2 and installer changes. Recommendation: **P1's naming and version check in the next release (0.2.18)** with P2's wording, then `watch` for hand-started workers and offline.

Geoff decided on 2026-10-19: DL-222, §6.

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

## 6. Geoff's decision (DL-222, 2026-10-19)

- **Naming.** "Ship it as `director`". The installer asks before it would hide a project skill of that name; `duo-director` stays as an alias for one release.
- **0.2.18 carries all four groups:**
  - the naming and the version check (P1);
  - hearing back in any permission mode (P2, P3);
  - the worker rules (P4 and the §5 core line);
  - the harness cases (P7).
- **Geoff added:** "Work machine disables dangerously skip permissions so we should avoid its use." So nothing in the director may rely on `bypassPermissions`. The design and its tests assume `auto`, and the stopgap of matching modes means running the director in Auto, never the workers in bypass.
- **Numbering.** DL-221 was taken the same morning by the issues triage (dark appearance, `research/issues-triage` eefd764). This decision is DL-222.
