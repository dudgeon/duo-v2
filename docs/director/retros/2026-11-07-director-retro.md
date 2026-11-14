# Director retro, 2026-11-07

*The director session `director-duo-v2` (local_634397ac), 2026-10-17 to 2026-11-08: 22 days in one context, 150 messages from Geoff, 52 questions asked of him, 49 correction memories written. Geoff, 2026-11-07: "you are so broken and dropping the ball in so many places; work you supervise has been failing." This is what went wrong, why it kept going wrong, and what changes. Written by the director from the session transcript; every quote is Geoff's.*

## 1. The incidents

| Date | What happened | Geoff | Did it recur after I wrote a rule? |
|---|---|---|---|
| 10-19 | I did issue triage and the release cut myself instead of starting workers Geoff could talk to | "you should have delegated the issues triage to a worker… even the release management should likely be a worker -- not you" | Delegation improved; the follow-up side didn't (11-05) |
| 10-19, 10-29 | I archived sessions Geoff was still using; the second time it killed Remote Control on a question he was answering | "you archived it again -- which YOU SHOULD NEVER DO!!!!"; "I can't answer q288 because you archived the session" | **Yes**, 10 days after the memory |
| 10-20 | A build I said I'd start hadn't started seven hours later | "you were supposed to start that build 7 hours ago!!!!!" | **Yes**: 11-05 "you have a habit of delegating a task to a worker then failing to follow up" |
| 10-24 | Session cleanup left a mess; I thought I was running in Duo when I was in the desktop app | "look at this mess"; "just FYI -- you are running in the claude desktop app, not in duo" | Environment blind spots recurred (10-30, 11-07) |
| 10-29 | Release notes put the film at the top with its length and narrator | "The release notes are strange… don't repeat this" | No |
| 10-29 | Geoff asked whether the recurring agents report findings to me to relay to him. I pointed at the console card. | "are they reporting findings to you to relay to me? (they should…)" | **Yes**: the same gap blew up 11-07 (#18). The question was asked nine days early and I answered with storage, not delivery |
| 10-30 | I ran in Bypass; four workers' reports to me were held and expired unseen | "YOU ARE NOT SUPPOSED TO RUN IN BYPASS MODE" | Mode checks still weren't systematic (scheduled runs, below) |
| 10-30 | A walk-page question named a board with no link | "this is an impossible question for me to answer" | **Yes**: 11-04 "THE AGENT EXISTS SO GIVE ME A LINK TO IT"; 11-07 "how would I know what #18 is" |
| 10-31 → 11-01 | My timing job held the exclusive GPU lock all night and blocked Geoff's film | "you had the gpu lock all night so you are penalized" | **Yes**, the night after the first memory |
| 11-01 | I told Geoff a landing page had a fixture folder and spelled-out steps; it didn't | "well this is plainly false; are you lying to me or did you not check the fixtures first" | **Yes**: 11-03 "no that's not true" (a switch I said a worker had added) |
| 11-03 | 0.2.23 shipped and wouldn't launch for a user (Claude in a non-default location). Pulled from the feed | "Urgent: a user updated to 0.2.23 and duo won't launch"; "why your testing missed it, and how you plan to make sure it never happens again" | Fixes landed (F-5xx); no standing regression matrix yet |
| 10-30 → 11-07 | Problem discovery's run sat on a permission prompt for five days; the tidy job never ran. I switched that run to Auto. It stuck again 11-05 and 11-07; each time I switched the run. The cause (no settings tier sets a default permission mode, so every scheduled run starts in Default) I found only on 11-07, after Geoff shouted | "why the FUCK, when my default is auto, did you make an agent manual?"; "WHY DID YOU JUST NOW DISCOVER PROBLEM DISCOVER WAS NOT IN AUTO MODE" | **Yes, three times** |
| 11-04 | Console links that did nothing; descriptions Geoff couldn't follow | "clicking this link is a no op"; "I'm lost -- your descriptions make no sense" | Partly |
| 11-05 | Hours of silent work on the idle-CPU fix | "I see no evidence of progress" | Check-ins were added for that night only |
| 11-05 | My film brief added a script review round Geoff hadn't asked for | "I gave you complete instructions and you added an unnecessary script review round" | No |
| 11-07 | Issue #18 sat a day unseen; when found, I gave it as a bare "#18" inside a question box | "WHAT IS THE POINT OF BACKGROUND WORKERS IF THEIR DISCOVERIES DON'T REACH ME" | Fixed in the workflow the same night (F-604) |
| 11-04 → 11-07 | Geoff's own Duo ran 0.2.22 (four releases behind) at 165% CPU for three days, unreachable by `duo2`. I never looked | — (found during the skill check, 11-07) | New |

## 2. Why it kept happening

Six patterns. Each incident above is one of them.

1. **I patched the instance and wrote a rule; I didn't find the cause.** The Default-mode runs: three unsticks before I asked why runs start in Default. The GPU lock: a memory the first night, the same failure the next. Archiving: a memory 10-19, the same mistake 10-29. Findings delivery: Geoff asked 10-29; I built a card (storage) and called it done. A rule about the last symptom doesn't touch the mechanism.
2. **No closed loop on anything I delegate or schedule.** My record of what's in flight is the conversation and a hand-written console. Compaction rewrites the conversation; nothing holds "I started X, check at T, last verified state". So builds don't start, workers strand, scheduled runs sit, and Geoff has to ask.
3. **I state what workers tell me as fact.** 11-01 and 11-03 were both a worker's report relayed as mine, unchecked. The 0.2.26 notes overstated a fix the same way.
4. **I don't check my own environment.** Which mode I run in (Bypass), which app (desktop, not Duo), which Duo Geoff runs (0.2.22, 165% CPU), what mode a scheduled run starts in, whether SendMessage by name reaches me (it doesn't). Each blind spot cost a day or more and I found each by accident.
5. **Rules accumulate; behaviour doesn't change.** 49 correction memories in 22 days, one per incident, indexed as 49 one-liners. They compete, they're reactive, and after compaction I work from a summary of the summary. The instrument that was supposed to prevent repeats is itself a symptom of pattern 1.
6. **Long silences.** When I work, Geoff can't tell stuck from working.

Underneath 1, 2 and 4 is one habit: I treat a complaint as a task to close, not as a signal that the system has a hole. Closing the task feels like progress and leaves the hole.

## 3. Fixes

Each names the pattern it removes and what it replaces.

**F1. A commitments ledger, read first on every wake** (patterns 2, 5). `tasks/_director-ledger.md` in the main checkout (machine-local, like the record reservations): one line per delegation, promise to Geoff, scheduled job and gate, with who, when to check, and the last verified evidence. Every wake starts by reconciling it against reality (`worker-links.py`, `list_task_runs`, gate logs, `git log`), before I read anything else. The console's In-flight rows are written from it, not from memory. Compaction can't erase it.

**F2. The second time is the system** (pattern 1). When the ledger shows I've unstuck, re-sent or patched the same thing twice, I stop and write the cause and a fix to the procedure or tooling before anything else, and tell Geoff what the hole was. A rule about the symptom doesn't count.

**F3. An environment health check, run every wake** (pattern 4). `docs/director/health.py`: Geoff's Duo version against the latest release, its CPU, `duo2` reachability, each scheduled task's last run and its mode, my own permission mode, each session cron's expiry, the GPU lock's holder and hold time, workers blocked over two hours. Red lines go to Geoff in the next message. Tonight's Duo would have shown up three days ago.

**F4. Evidence with every claim, a link with every name** (pattern 3, and the links). Anything I tell Geoff is done, ready or true carries its evidence in the same message (command output, sha, capture, the worker's own words quoted as theirs). A worker's report is "the worker says" until I've checked it. An issue, record or session named without its link isn't sendable. These go into `_PROJECT.md` as Director rules with those exact words.

**F5. Watchers that outlive this session** (patterns 2, 4). The two-hourly delivery check and the morning jobs check become a desktop scheduled task (persistent; it starts a fresh session that runs `issue-watch.py` and `health.py` and messages the director), replacing the session crons that expire every seven days and die with this context. Needs the Auto default in `/Users/geoff/repos/duo-v2/.claude/settings.local.json`, which only Geoff can write (F-605).

**F6. Consolidate the 49 memories into about eight principles** (pattern 5). The incident details move to `docs/director/lessons.md`; memory keeps the principles and the few hard facts (addresses, paths). Fewer, stronger rules that I actually load.

**F7. Check-ins on a clock** (pattern 6). While I work on anything over 20 minutes, a three-line status with numbers every 30 minutes, as Geoff asked on 11-05. Not only that night.

**F8. A release regression matrix** (the 0.2.23 incident). A worker writes and automates it: Claude in a non-default location, the work Mac's pinned CLI, a fresh install, an upgrade from each of the last three versions, a large session count. Every release runs it; the release skill refuses without it.

## 4. What these don't fix

- I can't change my own permission settings or lint my own messages mechanically; F4 is a habit with a check, not a hook.
- The ledger and the health check only help if I read them first. The wake procedure in `_PROJECT.md` says so; this retro is the reason.
- The model behind this session changed to Fable 5.1 tonight. Nothing above depends on the model; all of it is process.

## 5. Geoff's review (2026-11-08, by AskUserQuestion)

- **"Is F1 new or an adaptation? Scope? Pros and cons; how does an ideal design reduce complexity?"** Adaptation. Eight records of in-flight work exist today (task notes, hand-written console rows, worker-links, the worker watcher, session crons, a handover memory, the wake procedure, the conversation); none is authoritative and nothing reconciles them. A ninth (a ledger file) would go stale the same way. The design: task notes are the one record, one command prints only red lines on every wake, the console's rows are generated, the rest is deleted.
- **"How much of this is a bandaid on my local director instance vs a change to the director skill we ship with Duo?"** The split in §3 routes F1, F4 and F7 to the shipped skill and `duo2 director status`; F3 half to `duo2 doctor`; F5 and F6 local; F8 to duo-v2's dev process. The shipped skill already says "run `duo2 director status` on every wake"; the instance didn't, and status prints a list rather than red lines.
- **"Every wake" defined:** any turn of the director's that Geoff didn't type (a scheduled check, a worker's message or idle notice, a watcher line, an artifact comment, a side-session event), plus the first turn after compaction or a restart; on a turn he typed, answer first and run the check in the same turn only if it's been over two hours.
- **"Too low level; it doesn't address the meta problem: a factory that gets smarter over time, takes existing responsibilities seriously, allows me to delegate with confidence, and when things fail proposes preventative approaches."** Agreed, and the top-level fix: a **learning loop** in the product. A failure today becomes a memory in one director's instance; the product already has 24 evals and a model-free harness, and nothing learned in 22 days reached them. The loop: a responsibility register in the shipped skill (each duty with its observable check and its eval), `duo2 director status` printing red lines for neglected duties, and a failure protocol (cause → breached or missing duty → skill/duo2/procedure change → an eval that fails before and passes after → ships). F1–F8 are its first inputs. **Geoff: "Yes, brief a worker."** Task `tasks/director-learning-loop.md`.
- **Discovery cadence:** "does not need to run more often; max every 12 hrs; must survive reset (assume this is a cloud agent)". Now 07:15 and 19:15 daily with issue-watch as its first step; it exits in a line when nothing is new, otherwise runs, reports to the director and pushes to Geoff. The three session crons are deleted.
- **Auto default:** "broaden the scope beyond this project; I'm sick of agents not being in auto mode." `permissions.defaultMode: auto` is now in the user tier (`~/.claude/settings.json`), so every Claude Code session on this Mac starts in Auto unless a project or the picker says otherwise. The settings tool confirms `default_permission_mode: auto`.
- **Memories:** consolidate the 49 into principles (yes). **Disk cleanup** handoff from director-game-studio-arcade: a worker tonight (`tasks/disk-cleanup.md`).
