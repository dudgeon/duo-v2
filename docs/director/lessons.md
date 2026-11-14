# Lessons, and where things are

*Part of Duo's director procedures (`README.md`): Duo dev's habits on top of the shared duo-director core. Moved here from the project skill (retired) on 2026-10-17; the rules are in _PROJECT.md's `## Director`.*

## Lessons (2026-10-07/08: the 0.2.5–0.2.7 work-Mac freeze and a long night)

- **Field evidence first.** For a problem on a machine you can't reach (Geoff's work Mac), get Duo's own `~/Library/Application Support/Duo/logs/hangs.jsonl` (or a sample) before theorising. Check each record's `"version"` field. Read the START of the record (the innermost frames and `"ongoing"`). Symbolicate `Duo@0x…` against the exact release binary: `atos -o build/release/<v>/Duo.app/Contents/MacOS/Duo -arch arm64 -l 0x100000000 0x100<offset>`. 0.2.6 shipped a fix for a cause guessed from a sample; the hang log named the real loop (a lazy-stack re-anchor) at once.
- **A record with no Duo frames** means a SwiftUI-internal loop: look for modifiers that make SwiftUI act on its own (defaultScrollAnchor for sizeChanges, animations, lazy stacks' estimates), not Duo code.
- **"Can't reproduce" is a finding.** Say what the fix rests on (record and code, or a reproduction), add belt and braces when the user gets one try a day, and ship with the hang log as the safety net.
- **Work Mac rules:** no scripts or manual steps there, ever (fixes ship as releases that cope with the state the broken one left); its Claude Code is pinned months old, so test against that version too; a frozen app can't self-update, so the notes say "download the DMG".
- **Urgent fix releases stay minimal.** Hold feature merges; park a checked merge on a `staging/…` branch and reset main; merge the held work right after the cut.
- **Release gate:** build the release in a temporary work tree (never overwrite build/Duo.app) and run check-scale there. The release launch check registers copies with Launch Services, so run `check-launch-services.sh --clean` after every release and merge.
- **Caret differences** in chat captures: check the log's `trace capture … active=` before calling a regression. The caret only draws while Duo is the active app.
- **The first check-chat-perf after the heavy checks** often reads one over budget (machine load). Re-run it twice before acting. Exception: "replies at the bottom" in a **visible** run fails about one run in three on main itself (C-85, F-295). Judge a chat change on three visible runs against that baseline, not on one.
- **After a usage-limit reset,** read every session's last message: sessions stop mid-task silently (the test-model session sat stopped for hours).
- **Before archiving or stopping a session,** check its transcript for Geoff's own messages; if there are any, keep it.
- **Background sessions have no Design canvas:** design rounds run in Duo. **Test launches run in the background;** visible runs need Geoff's OK. **Models:** Opus plans, Sonnet executes scoped work, Haiku tests (CLAUDE.md).
- **Duo carries no dev logic:** test-model and similar rules live in scripts and agent instructions, never in the app.
- **When Geoff answers a button question with a question,** answer it and wait. Don't take it as a choice.
- **Record-table merges:** keep both sides; where both edited a row, prefer the newer content (usually the branch for rows it closed, main for rows others updated); regenerate generated files (Tokens.swift, duo2.md) instead of hand-merging them; union lists like Actions' switches.

## Where things are

| What | Where |
|---|---|
| Director console | https://claude.ai/artifact/MMmJ9BjomsKq9f9HpHK1ka (source `docs/director/console.html`) |
| Acceptance walk page | https://claude.ai/artifact/DfQ1rfxcxHuf3Zshy6UmXX (`docs/acceptance/2026-10-09-since-0-2-4/`); the old one, Wu4bb9tB7C4HH1UEfXgKMa, is superseded |
| Session phone links | `docs/director/session-links.py [id-prefix…]` |
| Design system artifact | https://claude.ai/artifact/QMapKeLYS3TVV36QKEc6MH |
| Records | `docs/design/decisions.md`, `docs/plan/findings.md`, `docs/plan/concerns-and-questions.md`, `docs/plan/enhancements.md` |
| Geoff's voice (a dependency, `voice-repo.md`) | private repo `dudgeon/geoff-voice`; its local checkout is in memory `reference-geoff-voice.md` |
| Checks | `scripts/check-records.sh`, `check-ui.sh`, `check-chat.sh`, `check-context.sh`, `check-reap.sh`, `check-motion.sh`, `check-*.mjs` |


## Lessons from the director's first 22 days (2026-10-04 to 2026-11-08, by principle)

Incidents behind the nine principle files in the director's memory (`principle-*.md`) and the retro `docs/director/retros/2026-11-07-director-retro.md`; quotes are Geoff's.

### P1 findings reach Geoff
- 2026-10-08 — After the retro, Geoff chose short end-of-block digests over long updates; his weekly token budget ran low that day.
- 2026-10-30 — Walk comment q135: "this acceptance walk artifact NEEDS to always contain links to artifacts that are referenced".
- 2026-10-30 — An answered 0.2.18 console card was still showing at 0.2.21; rule: delete answered needs cards and shipped release cards.
- 2026-10-31 — An AskUserQuestion about canvas boards carried no link; he answered "Can't answer without the artifact link" and asked for links immediately before every such question.
- 2026-11-07 — Issue #18 (chat-mode .md path looks like a link but won't open; paragraph overlaps) sat a day unseen: discovery had run three hours before it was filed, nothing watched GitHub until Monday, the run's own "reply to and close #16/#17" finding sat on the console, and I then wrote it as a bare "#18" inside a wrap_up box. "WHAT IS THE POINT OF BACKGROUND WORKERS IF THEIR DISCOVERIES DON'T REACH ME"; "how would I know what #18 is if you don't tell me???".

### P2 ask only real decisions, answerably
- 2026-10-04 — Asked whether I could download a 1 KB Apple CA cert after he'd said "get signing done": "you need me to spoon feed you permission?"
- 2026-10-05 — The reviews doc's dropdowns didn't work for him ("I can't interact with the UI"); an AskUserQuestion with nine decisions was answered at once.
- 2026-10-05 — I left quitting his Duo to him: "you can always quit [Duo] with my permission — then you do the rest".
- 2026-10-05 — He deferred the walk (134 cards untested) and asked the director to merge on its own and ping only for approvals.
- 2026-10-06 — He declined a design session's AUQ on feel/toggle and answered by canvas comments instead (picked B, asked for lighter variants, added ideas).
- 2026-10-12 — Console taps hadn't reached the director since 2026-10-09: "feed them to me one at a time … Remember I'm on a phone."
- 2026-10-12 — In director-product he rejected the first AUQ: "Update the artifact to accept my selections and send them directly from artifact to you". 2026-10-14: Send buttons proven from the iPhone Claude app.
- 2026-10-12 — Overnight mandate until 07:00: "Do not ask me questions that will block you"; the director decided, shipped 0.2.13 and both films, and logged its judgement calls.
- 2026-10-19 — A question pointed at "canvas board G" by link only: "if you need me to look at a board, open it".
- 2026-10-31 — A design session ended "still waiting on Geoff's yes": "Don't just wait if you are blocked — always re ask and provide any links needed for me to respond".

### P3 close the loop
- 2026-10-20 — tabs-design finished at 02:50 asking for its builds; unnoticed for 7 hours: "you were supposed to start that build 7 hours ago!!!!!"
- 2026-10-24 — director-session-links looked stalled; I resumed it, but its screen showed a live AUQ for Geoff. Earlier "stalls" (agents-know-duo-tasks 10-20, fork-attach-proof 10-23) may have been questions cut off by my resumes.
- 2026-10-29 — The first scheduled discovery run sat 9 hours on a permission prompt in default mode.
- 2026-10-30 — Four workers (classic-options, gdocs-frame, gdocs-landscape, feature-catalogue) finished or waited for hours unnoticed: director in Bypass, workers in Auto, so reports were held and expired; watchers named fixed ids. "we CANNOT have stranded workers".
- 2026-10-31 → 11-01 — split-view-slice2's exclusive editorperf run deadlocked (pipe read after waitUntilExit) and held the GPU lock ~10 h; duo-decks P2, split-view-build and release-video queued all night; workers flagged it and the director didn't act.
- 2026-11-01 — The 0.2.22 release worker, started without `--permission-mode auto`, stalled on `git worktree add`; Geoff couldn't open its Remote Control link from the question.
- 2026-11-02 — Landing-page buttons (card 2: cut 0.2.23 with Decks hidden; card 4: retire 14 sessions) got auto "On it" replies but I read only the named thread and nothing started: "you either aren't seeing them or are ignoring them".
- 2026-11-04 — The 2026-10-30 discovery run sat five days on its first prompt; every later run queued behind it and duo-weekly-tidy never ran. "you are a bad director for failing to check in on your background agents"; when I put the mode change on him: "THAT'S ON YOU?!"
- 2026-11-04 — duo2-isolation-guard (the fix for duo2 reaching Geoff's real Duo) showed "waiting" since 11-01 and was never merged; a test run's duo2 calls then changed his real Duo's settings.

### P4 verify before I say it
- 2026-10-07 — The 0.2.5 and 0.2.6 work-Mac freezes cost two releases and a night because I theorised from a partial sample; `hangs.jsonl` named the loop once I read the right record's start and `"version"`.
- 2026-10-12 — Overnight, main e605991 blanked every local HTML page (doc-safety's DL-175 regex disjunction, which WebKit refuses); the video session caught it in a recapture; the merge gates had no HTML-viewer capture.
- 2026-10-19/20 — Console cards claimed a macOS dialog was still up (inferred from a process) and that dark appearance waited on him (finished hours before): "dark appearance is not waiting for me; if it is, please drop a link here"; "I don't see it".
- 2026-10-30 — Voice input reached his hands-on test having run only on a recorded-file feed; the first real mic press crashed Duo Dev (installTap NSException; the Mac mini has no mic): "did you not test this at all?!?!?!?!"
- 2026-10-30 — I reached for the chat spike's mock API to avoid real turns: "this is a fake constraint -- you can use claude for testing".
- 2026-11-01 — I said a split-view Duo Dev had "a test folder of three sample files"; a plain folder isn't a project, so nothing showed: "this is plainly false; are you lying to me or did you not check the fixtures first before making this claim?"

### P5 delegate to sessions Geoff can join
- 2026-10-06 — "As director, I think your correct handling should be to delegate these feature builds to new sessions."
- 2026-10-07 — I archived chat scroll perf (6827c35f) as soon as it merged; he was still talking to it: "did you kill the scroll performance session? there were followups". Restored as duo-v2-c8.
- 2026-10-07 — "please make all of these sessions, and all going forward, available for remote control unless I specify to run them on duo"; by button: design rounds run in Duo (bg sessions have no canvas tool).
- 2026-10-11 — The intro-video session couldn't reach "demo-fixtures" (a Remote Control name, not a peer name); Geoff saw the two "having trouble communicating".
- 2026-10-13 — done-task-look was archived before he could give feedback from his phone: "update director to not archive sessions until I've signed off on the work"; by button: "Stop them; resume on request".
- 2026-10-19 — "you should have delegate the issues triage to a worker so I could work with it while you focus on the release; and even the release management should likely be a worker -- not you".
- 2026-10-24 — I archived 65 sessions in Duo but the `claude --bg` rows stayed in the app's list ("look at this mess: you still have a lot of cleanup to do"); I then drove claude.ai in his Chrome: "you are running in the claude desktop app, not in duo".
- 2026-10-28 — I stopped list-renumber after its merge while Q-288 was open on the console; his Remote Control was cut off and he couldn't reactivate it.
- 2026-10-29 — Seen: `claude --bg --resume <full-id> "<msg>"` with no flags wakes the same session with Remote Control; flags make a copy.
- 2026-10-31 — A brief containing backticked `duo2 split --with` and `swift build --product duo2` ran both in the main checkout and dropped them from the brief.

### P6 share the Mac and the budget
- 2026-10-07 — During the 0.2.5 hang root-cause: "be sure you're using sonnet/haiku for simple testing tasks so we don't run out of opus tokens".
- 2026-10-08 — "opus 5.5 for planning, sonnet 5.5 for execution of well scoped tasks, haiku 5.5 for test execution/validation" (DL-153 is a dev rule, not a shipped feature).
- 2026-10-08 — "It is impossible to get work done with those apps firing and stealing focus"; for visible runs: "you ask for permission and warn me".
- 2026-10-11 night — A Remotion render overlapping a smoke test swapped 21 GB and slowed voice training about 50×.
- 2026-10-12 — Running fine-tunes and Duo checks in parallel pushed swap to 43 of 46 GB; the VoxCPM2 LoRA stalled 1.5 h at step 0; the memory gate counted swapped pages as free.
- 2026-10-12 — Two jobs held the lock at once twice (old work-tree copies of the lock script); fixed by main's gpu-lock.sh by full path (F-296), shared/exclusive holds (F-298).
- 2026-10-12 — "Ok to test": the freeze-guard visible gate pre-approved. Same day: rebuilding main's ad-hoc-signed `build/Duo.app` under his running Duo made TCC prompts loop.
- 2026-10-13 — Voice v2 training thrashed in swap (192 s/step); a watchdog now stops it above 20 s/step.

### P7 films
- 2026-10-10 — v2 cut swapped his explicit morph transition for a camera pan, left out the PowerPoint and Word windows and drew a basic browser prototype.
- 2026-10-10 — Rejected as "low effort": generated wallpapers (chose High Sierra), UI-box callouts, the first voices ("sterile", "too high pitched"; chose the M2 baritone).
- 2026-10-11 — Re-offered callouts and reference studies: "all low effort and bad", then "I don't want the feature pop out; the outline is better than before".
- 2026-10-11 — No cuts between shots: navigate in the app or use a motion-graphics transition; a crossfade counts as a cut.
- 2026-10-11 — On NC licences: "this is an open source software project with a permissive license and no plans for commercialization."
- 2026-10-12 — Director-film drafts flagged as "a claude-ism -- not like how I would write" and "claude slop, please read the sections I wrote by hand".
- 2026-10-12 — Poster rule: frame 0 is the title card. Same day: "Save this link/video as a future style reference — esp the animation style" (Managed Agents film).
- 2026-10-13 — README couldn't show the poster from release assets (served as octet-stream); left as a Geoff task to drag films into the GitHub editor.
- 2026-10-29 — The 0.2.21 notes opened with the film's bare URL and a caption naming its length and narrator: "Please go fix this and don't repeat this in the future."
- 2026-10-31 — 0.2.22 film: "it is extremely important that transcription does not appear instant in the film".
- 2026-11-05 — My intro-v12 brief added a script review round: "this was a mistake on your part"; on order and length: "these are questions that you have sufficient context to handle yourself".

### P8 releases and repo hygiene
- 2026-10-05 — Work Mac reported Claude Code 2.1.219 (no cross-session messaging). 2026-10-07: "work management pins the claude code version, so we will always be months behind latest". 2026-10-28: "work is now pinned to 2.1.284".
- 2026-10-06 — Resolving a findings.md conflict to one side (c6aa7c8) dropped F-114 to F-119; the walk session restored them (7169ff9).
- 2026-10-06 — I proposed 0.3.0: "it will be a long time before we are at 0.3.0 -- stick to 0.2.2".
- 2026-10-07 — I offered a python stopgap for the work Mac: "it is not practical and likely against policy for me to run random scripts from my home machine at work".
- 2026-10-07 — "For everything we build, I want to maximize backwards compatibility with existing obsidian handling and/or OKF".
- 2026-10-11 — "I trust you to manage this in the usual course of business" (commits and pushes).
- 2026-10-12 — A voice-input research session pushed its branch to origin and hard-coded private takes/lock paths; the director deleted the branch and moved the paths to env vars.
- 2026-10-12 overnight — chat-219-answer found any chat send after Claude's dim prompt suggestion fails on 2.1.219 (likely often on the work Mac); targeted for 0.2.13.
- 2026-10-13 — DL-185's disclaim made every Claude Code update re-ask TCC; undone in 0.2.14 ("Duo answers for its terminals again").
- 2026-10-19 — 0.2.17 shipped; Sparkle relaunched his Duo and cut off sidebar-hierarchy, dark-appearance and tabs-design mid-turn; he saw the design session he was about to use as "archived": "which YOU SHOULD NEVER DO!!!!"
- 2026-10-30 — `git push origin $M:refs/heads/main` failed twice after passing gates (zsh `:r` modifier).
- 2026-11-01 — Workers kept colliding with numbers reserved in other briefs; the ledger `tasks/_record-reservations.md` was started.

### P9 fix the mechanism
- 2026-11-04, 11-05, 11-07 — I switched stuck scheduled runs to Auto by hand three times before finding the cause: no settings tier sets `permissions.defaultMode` (F-605). "WHY DID YOU JUST NOW DISCOVER PROBLEM DISCOVER WAS NOT IN AUTO MODE". Auto mode can't write that setting, so it's Geoff's one change.
- 2026-11-04 — My message about a setting read as blame: "your message read as blame, not a request for help; if you need me to change a setting on an agent seassion, ALWAYS WITHOUT FAIL give me a link to that session".
- 2026-11-07 — "don't manually bandaid an arbitrary GH issue -- fix the fucking workflow."
