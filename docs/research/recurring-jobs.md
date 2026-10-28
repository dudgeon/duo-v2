# Recurring jobs for Duo: which background agents should tend it

2026-10-28 · branch `research/recurring-jobs` · decision page https://claude.ai/artifact/EexV81q7iHtCe6BL4hmnhR (source `recurring-jobs-decisions.html`) · session df6c82a7 (Opus; two Sonnet subagents gathered the repo counts and the web sources) · records F-383, F-384, Q-273 to Q-278, ENH-281 to ENH-286 · Geoff's picks become DL-240.

**Ask (Geoff, 2026-10-28).** Find recurring jobs that would help with the tidy-up: an architecture review, a canonical feature-intent document, product-marketing and explainer-video proposals, a design-system maintainer, and others the evidence supports. "I don't want to create novel solutions just for the sake of it, and I don't want to create like a Rube Goldberg machine that is hard to maintain."

## The answer in one screen

Three scheduled or procedural jobs, one one-off build, and four mechanical checks. Everything else is a no.

| # | Job | Cadence and trigger | Model and cost | Lands on | Recommendation |
|---|---|---|---|---|---|
| A | **Weekly tidy-up.** One report with six sections: records and task notes, work trees and branches, doc drift (README, guide, design README, the design-system artifact), field logs (hangs, chat fallbacks), the Claude Code CLI watch, and how stale the performance budgets are. | Weekly, Monday morning. A desktop scheduled task. | Sonnet, with Haiku for check runs. About 40 turns and 30–45 min. | One console card, and no card when nothing is new. | **Build now** |
| B | **Release brief.** User notes, a README and guide delta, a launch tier for each feature, explainer-video candidates, whether the intro video is stale, and the design-system artifact sync. | Every release. A step in `releases.md`, done by the release worker. No new job. | Sonnet. About 15 extra turns per release. | The release card on the console, plus a docs branch to merge. | **Build now** |
| C | **Feature catalogue.** The canonical statement of each major feature's intent and how it should work, kept current as each feature merges. | Written once. After that, a row update in each feature's brief and merge, and a check in A. | Opus once, about half a day. After that, zero extra turns. | `docs/product/features.md` and the design-system artifact. | **Build now** (the one-off) |
| D | **Fortnightly deep review.** Alternates between code (architecture, simplification, performance) and design (patterns harvested from one-offs, design-system refactors). Each subject comes round monthly. | Every other Monday. A desktop scheduled task that starts a worker. | Opus leads, with 3–4 Sonnet reviewers. 1–2 h. Measurements run under the GPU lock. | `docs/research/<date>-review.md`, plus at most 5 proposals as console cards. | **Build after A** (first run in November) |
| — | **Mechanical checks** (ENH-281 to 284): record status, stand-in age, design README against `surfaces.md`, stale task notes, and a log of merge-gate runs. | On every merge, inside `check-records.sh`, `merge-gate.sh` and DuoChecks. | No turns. | The merge gate's output, which A then reads. | **Build now**, as one small Sonnet task |

**No:** a separate doc-drift agent, a separate CLI-watch job, a flaky-test triage job, a daily anything (problem discovery already runs daily), an auto-closing or auto-deleting cleaner, a standalone marketing agent, and any job that edits code or docs by itself.

**Why this shape.** The repo shows real drift in six areas this month (§1). The things that keep running for other teams have five traits (§2):
- they run on a schedule;
- they write one digest, or nothing;
- they report and never act;
- they are narrow;
- they turn every rule that can be mechanical into a check, rather than an LLM's opinion.

Folding six drift sweeps into one weekly report, and marketing into the release step Duo already has, gives Geoff two new scheduled things to look at instead of eight.

## 1. Introspection: where Duo drifts without anyone noticing (F-383)

**The pace.** From 09-28 to 10-28, main took 1,050 commits. By ISO week they ran 110, 555, 277, 91, then 17 so far. Merges ran 3, 169, 77, 37 and 5. There were 31 release tags, v0.1.0 (10-04) to v0.2.20 (10-28), and since 10-14 a release has come every 2–5 days. At this pace a weekly job sees about 40–170 merges. A monthly job would see 300 or more, too many to read well.

**What drifted, with counts from origin/main** (the grep counts are approximate):

1. **The design docs lag the merges.** Since 10-12, 132 commits touched `Sources/` and 26 touched `docs/design/system/`.
   - `docs/design/README.md:29` still says chat mode is "Target (DL-119); not built". Chat mode shipped weeks ago, and the 10-12 codebase review flagged exactly this line. Sixteen days later it is still there.
   - The design-system artifact (QMapKeLYS…) is republished by hand by the director after merges (`sessions-and-signoff.md`). Git can't show how far it lags, which is the problem: nothing measures it.
   - Counter-evidence: when a feature brief names the design-system docs, the docs move in the same commit (DL-229 a9283154, DL-233 1b5d0628, the tabs work b8a4a33d). **Drift happens where no brief or gate names the doc.**
2. **Records are left open.** About 130 of 207 Q rows and 13 of 97 C rows have an "open" status cell.
   - The oldest open Q rows (Q-11, Q-12, Q-17, Q-20, Q-27 to Q-30) are three to four weeks old.
   - Some open rows already carry their answer in the notes, Q-43 and Q-47 among them. So the status column itself is unreliable.
   - `check-records.sh` checks only two things: no id appears twice, and no id is lost in a merge. It doesn't look at status or age.
   - Record-number collisions show up in **about 12 commits** that renumber records (4aec4426, f38cf351, 38ad8ed1, 7d4d150b, f3c7570d and 9d04bed4 among them). All were caught at merge.
3. **Stand-ins are never revisited.** 63 Q rows say "stand-in" or "nothing drawn", and **38 are still open**. Examples: Q-30 (Move to Project ▸ New Project…, open 24 days), Q-39, Q-44, Q-46 and Q-50. No procedure brings them back to Geoff.
4. **Task notes go stale.** 46 notes: 24 `in-progress`, 10 `review`, 7 `done`, 3 `suggested` and 2 `open`.
   - 19 of the in-progress notes have no date after 10-20.
   - Several are plainly shipped: dark appearance, the tabs scroll strip and the sidebar hierarchy all shipped in 0.2.18 (10-20), and their notes still say `in-progress`.
   - The director reads notes to judge what's in flight, so a stale note costs it time and misleads it.
5. **The README and user guide lag the features.** README.md last changed on 10-13, and `docs/guide/` on 10-20.
   - The README never mentions dark appearance, scrolling tabs, the sidebar's Later fold, GitHub issue links, forks, the Trust this folder notice, the Make a Project interview, Word documents in the Google Docs look, or the chat-fallback Debug button. All of these shipped from 0.2.18 to 0.2.20.
   - The guide mentions two of them, once each.
6. **Nobody re-runs the performance budgets.** The budgets exist: `check-chat-perf.sh` (open 600 ms; replies at the bottom measured 467–525 ms against 600) and `check-scale.sh`.
   - No budget run is recorded after 10-12.
   - The worst regression of the month, an idle Duo burning 45–150% CPU (C-79), was found by sampling Geoff's own Duo during the one-off codebase review. No budget caught it.
7. **The architecture review was a one-off.** The 10-12 review named ten changes. Five shipped within days:
   - the idle burn, 7d040930;
   - the correctness batch, 69bb5d22;
   - web view safety, f3b6e471;
   - notices, 44f1b2ad;
   - search, 3c3e0d48.

   Five have no merge yet: bounded chat memory, the two-speed refresh (32.5% of a core idle at 600 sessions), no disk reads in view bodies, the file splits and checks registry, and debug code out of release. Since then 1,050 commits have landed. **The review was the most productive single document of the month, and no job brings it back.**
8. **Other drift.**
   - `git worktree list` has 43 entries, and 19 of the 21 remote branches are older than 10-16. The oldest is `claude/menu-bar`, from 10-05.
   - The acceptance walk `2026-10-17-since-0-2-4` has been open for 11 days, across 7 releases.
   - Three late CLI-version fixes came from the field, not from any watch: the 2.1.293 dialogs (F-176), `/fork` on 2.1.309 (F-363), and each CLI update breaking the responsible-process key (F-306).
9. **Well guarded already:** duo2.md parity. DuoChecks enforces it, and only one follow-up fix was needed this month (cb37086d). Tokens are generated, and the video pipeline has its own `--check`, which reports stale framing. **Mechanical guards work here; every area that drifts lacks one.**

## 2. What other teams run and keep running (F-384)

The evidence is mixed. The primary sources are GitHub's, Google's, OpenAI's, Anthropic's and Airtable's own pages. The rest are practitioner blogs, marked as such.

- **Mechanical checks beat periodic reviews of prose.**
  - Evolutionary architecture's *fitness functions* encode an architectural rule as an automated check, either triggered or continuous ([Ford et al., ch. 4](https://www.oreilly.com/library/view/building-evolutionary-architectures/9781492097532/ch04.html)).
  - *Living documentation* derives docs from the source so they can't drift ([Martraire, InfoQ](https://www.infoq.com/fr/news/2015/06/ddd-living-documentation/)).
  - Spec-driven tools are criticised because the specs still go stale ([Fowler's site on SDD tools](https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html); [blog](https://dev.to/kunalsharda/spec-driven-development-with-ai-is-real-now-the-stale-spec-is-the-part-nobody-fixed-2001)).
  - Duo's own record agrees (§1.9).
- **Scheduled agents that last are report-first and gated by a person.**
  - GitHub Agentic Workflows are read-only by default and write only through "safe outputs". Their PRs are never auto-merged, and the flagship example is a daily status report. GitHub advises starting with low-risk outputs (comments, drafts, reports) before PRs ([GitHub blog](https://github.blog/ai-and-ml/automate-repository-tasks-with-github-agentic-workflows/), [gh-aw](https://github.github.com/gh-aw/)).
  - Codex automations report to an inbox and **archive themselves when there's nothing to report** ([OpenAI](https://developers.openai.com/codex/app/automations)).
  - A third-party warning: daily automations that keep re-reporting the same unfixed issue become inbox noise ([blog](https://codex.danielvaughan.com/2026/07/18/codex-automations-lightweight-ci-scheduled-agents-github-actions-boundary-unsupervised-risk/)).
- **Broad AI reviewers are mostly noise; narrow, capped ones aren't.** Practitioner reports say a general-purpose reviewer gets muted, and capping comments and narrowing scope raises signal. One anecdote: a bot was disabled after 3 days at 94% false positives, then fell to 12% once capped at 3 comments ([blog](https://dev.to/hopkins_jesse_cdb68cfa22c/the-5-mistakes-i-made-building-an-ai-code-review-bot-so-you-dont-have-to-37ch), [blog](https://tianpan.co/blog/2026-04-17-ai-code-review-at-scale-false-positive-trap)). These are anecdotes, not a study.
- **Batch and slow the cadence.**
  - Dependabot's own advice: group updates, slow the cadence, keep security updates fast ([GitHub](https://github.blog/security/supply-chain-security/tame-dependabot-group-your-updates-slow-the-cadence-keep-security-fast/)).
  - Renovate's noise-reduction guide says the same ([docs](https://docs.renovatebot.com/noise-reduction/)).
  - The UK Ministry of Justice treats weekly as a reasonable upper limit ([guideline](https://developer-portal.service.justice.gov.uk/guidelines/dependabot-guidelines)).
- **Every alert must be actionable.** Google SRE: a page must need human judgement, a robotic response should be automated rather than paged, and noisy alerts should be removed ([SRE book](https://sre.google/sre-book/monitoring-distributed-systems/)).
- **Report stale things, never auto-close them.** Stale bots that auto-close lose information-rich reports and drive away contributors ([Drew DeVault](https://drewdevault.com/blog/stalebot/), [fvsch](https://fvsch.com/stale-bots), [actions/stale#861](https://github.com/actions/stale/issues/861)). Gutenberg's contributors leaned toward labelling only ([WP Tavern](https://wptavern.com/gutenberg-contributors-consider-implementing-a-bot-to-close-stale-issues)).
- **Flaky tests get a daily digest and automatic quarantine at scale** ([Airtable](https://medium.com/airtable-eng/how-airtable-manages-flaky-tests-in-a-large-scale-monorepo-5fe09922e90c); Google measured about 1.5% of runs as flaky, [Testing blog](https://testing.googleblog.com/2016/05/)). At Duo's scale (one known flaky check, C-85; no "flaky" commits this month) a separate job isn't warranted. A merge-gate log the weekly report reads is enough.
- **Launches are tiered.** Tier 1 gets the full treatment, and a rule of thumb allows 2–3 a quarter. Tier 3 gets a release note ([Pragmatic Institute](https://www.pragmaticinstitute.com/blog/post/prioritize-product-launch-resources-with-launch-tiers)). Changelogs go out on a regular schedule ([Linear](https://linear.app/now/startups-write-changelogs)). release-please keeps a person as the release gate ([release-please](https://github.com/googleapis/release-please)). An explainer video belongs to Tier 1 only.
- **Design-system governance** is mostly about contribution models (central, federated, hybrid). Heavyweight contribution processes get bypassed: one team saw 4 requests in 12 weeks ([Société Générale](https://medium.com/societe-generale-design/taming-design-system-chaos-66bcadbf43e1)). I found no credible source on audit cadence, or on keeping design-system docs current for AI design tools. Generated tokens, which Duo already has, are the strongest guard. Anthropic's advice is to keep instructions concise and link to one source of truth ([Claude Code best practices](https://www.anthropic.com/engineering/claude-code-best-practices)).
- **Claude Code's scheduling primitives** ([scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks), [desktop scheduled tasks](https://code.claude.com/docs/en/desktop-scheduled-tasks)):
  - Cloud routines can't see local sessions.
  - `/loop` and CronCreate die with their session.
  - **Desktop scheduled tasks** run locally, in a fresh session each time, while the app is open. A run missed while the app was closed happens at the next launch.

  The problem-discovery design already chose desktop scheduled tasks, so these jobs use them too.

**Five traits, used as the filter for §3:**
1. a schedule or a procedure step, never a per-event trigger;
2. one output, silent when clean;
3. it reports and a person acts (the director, Geoff for decisions);
4. a narrow scope with a cap on how much it says;
5. a mechanical check wherever the rule can be written down.

## 3. The candidates, each on its merits

### Geoff's four

**1. The architecture review. Yes, as half of job D, fortnightly and alternating.**
- *Evidence for:* the 10-12 review shipped five of its ten changes in days, and found the month's worst regression. Five changes are still open, and 1,050 commits have landed since.
- *Evidence against:* broad AI reviews are noisy.
- *So:*
  - each run reads only what changed since the last one (`git diff <last-review-sha>..main`, and the merged branches);
  - it re-measures with the committed `codebase-review-tools/`;
  - it follows up the previous run's open items first;
  - it reports **at most 5 proposals**, each with file:line evidence and a size, and the previous run's unfinished items carried forward;
  - Opus leads, with 3–4 Sonnet reviewers (the 10-12 review used 8; a diff-scoped run needs fewer);
  - its timing measurements run `--exclusive` under the GPU lock.
- *Silent when:* no proposal clears the bar ("a measured cost or a confirmed bug"). The run then writes a one-line "nothing new" into the review log and posts no card.

**2. A canonical feature-intent document. Yes, but as a one-off build plus a merge rule, not a recurring agent.**
- *Evidence:* living docs stay true when the change that alters behaviour also changes the doc (§2). A periodic agent that rewrites a spec is the pattern the SDD critiques describe going stale. Duo has decisions (DL), handoffs and intent pages (DL-236's), but no one place that says "here are Duo's features and how each should work". Geoff asked for exactly that place.
- *So:*
  - **C, once:** an Opus session writes `docs/product/features.md`. For each major feature: its intent in two or three sentences, how it should work (the user-visible rules), the DLs and handoffs that govern it, its status and release, and its `duo2` verbs. Duo has about 25 major features, by the README, the guide and the surfaces.
  - **Then a rule:** a feature brief names its catalogue row, and the merge carries the row's update. This is the same pattern that keeps design-system docs current when a brief names them.
  - **Then a check, in A:** a feature merge with no catalogue change shows up in the weekly report.
  - The catalogue is also published inside the design-system artifact, so Claude Design reads intent alongside looks.
- *Precedence:* it restates DLs. Where it disagrees with a DL, the DL wins, and the weekly report flags the disagreement.

**3. Product marketing and explainer videos. Yes, as part of B, the release brief. No standalone agent.**
- *Evidence:* launch tiers (§2). With a release every 2–5 days, most features are Tier 3 (a note), a few are Tier 2 (a README line and a guide page), and Tier 1 should come round 2–3 times a quarter. Tracked changes in Markdown, which Geoff called out, would be Tier 1.
- *So:* the release worker, which already writes the notes, adds three things to the release card:
  - a tier for each feature in the release, with a one-line reason;
  - for any Tier 1, a **video proposal**: the story in three sentences, the states to capture, and whether it extends the intro film or stands alone;
  - **intro-video staleness:** `node video/build.mjs --check` reports stale framing and shots whose states changed. If the film shows a surface that has since changed, or a Tier 1 feature it doesn't show, the card says "the intro film is out of date: these scenes".

  Geoff decides on the card, and a video is then a `product-video` worker as today.
- *Cost:* the check takes about 2 s and needs no GPU. Writing the tiers takes about 10 turns.

**4. The design-system maintainer. Yes, split in two: the mechanical sync goes in A, and the thinking goes in D's design half.**
- *Mechanical:*
  - the design-system artifact against `docs/design/system/` on main (the memory procedure already does a file-by-file `cmp`);
  - `surfaces.md` statuses against the handoff table in `docs/design/README.md`, the drift that has been open since 10-12;
  - `gen-design-system.py` producing no changes.

  A reports these, and the director runs the sync it already owns. The design-README check becomes a script (ENH-283).
- *Thinking (D, design month):*
  - read the month's merged UI;
  - find one-off decisions that recur (the same spacing, chip, sheet or empty state solved twice);
  - propose at most 5 changes: harvest a pattern, merge two components, or rename for intuitiveness;
  - each proposal goes on a Design canvas with the Duo design system, every mark [P].

  Design work runs in Duo (background sessions have no canvas), so job D's design runs start a Duo session, not a background one. Geoff answers on the canvas, as he already does. Nothing is built until he approves (CLAUDE.md, "Never invent a design").
- *Also:* the stand-in questions (38 open) belong to design. The design month brings the oldest five back to Geoff as a canvas round.

### Others the evidence supports, folded into A

- **Records and task-note hygiene:**
  - Q and C rows whose notes carry an answer but whose status still says open;
  - stand-in questions older than 14 days;
  - task notes `in-progress` with no Progress line for 7 days, or whose branch has merged.

  A proposes the closures, and the director makes them. **Why:** 130 open Q rows, and stale notes mislead the director.
- **Work trees and branches:** merged branches and their work trees, and branches with no commit in 14 days, each with the session that owns it. It is report-only, because sessions stay reachable until sign-off. **Why:** 43 work trees, and auto-cleaning is the documented anti-pattern.
- **Field logs:**
  - new signatures in `hangs.jsonl` and `chat-fallbacks.jsonl`, grouped by version, with only new ones reported;
  - read with Duo's own verbs or read-only from Geoff's logs folder, symbolicated against the exact release as `lessons.md` says.

  **Why:** "field evidence first" is a standing lesson, and the chat-fallback log is new (DL-234). This is internal telemetry, which problem discovery's GitHub issues don't cover.
- **The Claude Code CLI watch:**
  - new `claude` versions since last week;
  - changelog lines touching what Duo depends on (the TUI screen, hooks, `--session-id`, Remote Control, `/fork`, dialogs);
  - a note whether the work Mac's pin (2.1.219) is still in DL-155's range.

  If a risky line appears, the card proposes a compatibility worker, and the director delegates it. **Why:** three field-found CLI breaks this month (F-176, F-306, F-363). Weekly matches Dependabot practice. A separate job isn't worth its upkeep.
- **Performance-budget staleness:** if 20 or more merges touched `Sources/` since the last recorded budget run, the card recommends a run. Running the timing checks needs the `--exclusive` lock and a quiet machine, so A doesn't run them by default. Q-276 asks Geoff whether it should. **Why:** C-79 was found by accident.
- **The open acceptance walk:** its age, and the releases since. One line.

### Said no

| Candidate | Why not |
|---|---|
| A separate doc-drift agent | It's a section of A, and the README half is B's. Two jobs reading the same docs would report twice. |
| A separate CLI-watch job | A section of A; weekly is enough, and problem discovery's daily run catches field reports of a break. |
| A flaky-test triage job | One known flaky check (C-85) and none this month. A log of merge-gate runs (ENH-284) and a line in A cover it. |
| Auto-cleaning branches, work trees or sessions | The documented anti-pattern. It would also break "sessions stay until sign-off". |
| A standalone marketing agent | Its input is the release; the release worker already writes the notes. |
| A periodic agent rewriting the feature spec | The pattern that goes stale (§2); a merge rule does it at the moment of change. |
| Anything daily besides problem discovery | At this pace a daily digest repeats itself; noise is what gets muted. |
| Jobs that edit code or docs, or message workers | Unchanged from the problem-discovery design: jobs report, and the director acts. Relaying a job's text to a worker is the director's call (prompt injection, DL-222). |

## 4. The jobs in detail

All follow the problem-discovery shape:
- a procedure doc in `docs/director/`;
- a desktop scheduled task created by the director, whose prompt is "follow `docs/director/<job>.md`";
- results on the console or a page;
- actions through the director;
- no job edits code, pushes, archives, or sends text to a worker.

### A. Weekly tidy-up (`docs/director/tidy-up.md`)

- **Purpose:** catch the drift in §1 before it costs anything, as one weekly report.
- **Cadence and trigger:** Monday at 08:00, as a desktop scheduled task. If the Mac or app was asleep, it runs at the next launch. At 37–169 merges a week, weekly is the slowest cadence that still reads well.
- **Inputs:**
  - `git log` since the last run's sha;
  - `git worktree list` and the branches;
  - the record files and `tasks/*.md`;
  - `gh release list` and the notes;
  - README, `docs/guide/` and `docs/design/README.md`;
  - the design-system artifact's file list (an `Artifact read` and `cmp`);
  - Duo's two field logs;
  - `npm view @anthropic-ai/claude-code versions` and the CLI changelog;
  - the merge-gate log (ENH-284);
  - the open walk ledger.
- **Output:** one console `needs` card, kind `look`, "Tidy-up, week of <date>". It has up to six sections, and each item carries a suggested action the director can take:
  - "close Q-43 (answered in notes)";
  - "stop and remove work tree claude/menu-bar (merged 10-07)";
  - "republish the design-system artifact: surfaces.md, chat.md differ";
  - "2.1.312 changes the dialog footer: delegate a compatibility check".

  The options are **Do all** (recommended), **Pick in the note**, and **Snooze a week**. The director carries out what Geoff picks, through its own procedures. Everything the director may already do under D2 and its standing approvals, such as the design-system republish, closing records and stopping finished workers, it does without the card. **The card carries only what needs Geoff.** The rest goes in the card as a "done for you" line.
- **Who acts:** the director, and Geoff only for decisions.
- **Guard against noise:**
  1. Each item has a key, such as `wt:claude/menu-bar` or `q:Q-43`, kept in the console db under `tidy/<key>` with first-seen, last-reported and snoozed-until. An item is reported once, and again only when its state changes or a week's snooze ends.
  2. With nothing new, the job posts no card, only `meta/console.updated`.
  3. Each section is capped at 5 items, with "and N more" linking to the run's log.
  4. The thresholds are numbers in the procedure (14 days, 7 days, 20 merges), not judgement.
- **Cost:** Sonnet, about 40 turns. Most of the work is scripts, and Haiku subagents run any checks. No GPU lock is needed, since it runs no builds. If it runs the budgets (Q-276), add an `--exclusive` lock and about 15 min.
- **Maintenance:** one procedure doc and one script, `scripts/tidy-scan.sh`, which emits the facts as JSON. The scheduled task's prompt is one line. If a section stays empty for 4 weeks, the director proposes dropping it.
- **Overlap:** problem discovery reads GitHub issues daily, and A reads internal state weekly. A never reads issues. Both link items to live workers through the console `threads`. The design-system republish stays the director's job; A only says when it's due.

### B. The release brief (a section of `docs/director/releases.md`)

- **Purpose:** make each release carry its words (notes, README, guide), its launch tier, and the video question.
- **Cadence and trigger:** every release. It is a step in the release worker's brief, before Geoff's go. It is not a separate job.
- **Inputs:**
  - merges since the last tag;
  - the feature catalogue (C);
  - README and the guide;
  - `node video/build.mjs --check`;
  - the design-system diff.
- **Output:**
  - the release card on the console gains *Tiers* (each feature with T1, T2 or T3 and a reason), *Docs* (a branch `docs/release-<v>` with README and guide edits for Tier 1 and 2 features, which the director merges under D2), *Video* (a proposal for any T1, and the intro film's staleness), and *Design system* (artifact in sync, or the files to republish);
  - Geoff's go now covers the notes and the tier picks; a video is a separate yes.
- **Guard against noise:** a release with only Tier 3 items gets one line ("T3 only; docs unchanged"). A video is proposed only for T1, and a Tier 1 should come round no more than about once a month.
- **Cost:** Sonnet, about 15 turns more per release. There is no new scheduled task.
- **Maintenance:** a paragraph in `releases.md` and the brief template.
- **Overlap:** A's README and guide section reports drift *between* releases. B fixes it *at* the release.

### C. The feature catalogue (one-off, then a merge rule)

- **Purpose:** the canonical statement of each feature's intent and rules (Geoff: "a canonical articulation of the major features and how they should work").
- **Build:** one Opus session, about half a day. It reads the DLs, handoffs, intent pages, guide and `surfaces.md`, and writes `docs/product/features.md`. Each feature gets a row: id (FEAT-n), name, intent, how it should work (rules), governing DLs and handoffs, status and release, `duo2` verbs, and the explainer film if any. Geoff reviews it once on a page.
- **Keeping it current:**
  - `delegating.md`'s brief template gains "the catalogue row(s) this changes";
  - the merge carries the update;
  - A's doc-drift section lists feature merges with no catalogue change;
  - the director publishes the catalogue into the design-system artifact.
- **Guard against noise:** none needed, since it is not a recurring job.
- **Cost:** half a day once, then a line per feature merge.
- **Overlap:** B reads it for tiers, and D reads it as the intent the architecture and design should serve.

### D. The fortnightly deep review (`docs/director/deep-review.md`)

- **Purpose:** the thinking the mechanical jobs can't do. In code months: refactors and simplifications for reliability, maintainability and performance. In design months: patterns harvested from one-offs, design-system refactors, and the oldest stand-ins back to Geoff.
- **Cadence and trigger:** every other Monday, alternating code and design. A desktop scheduled task starts **a worker** rather than doing the review itself, because review work Geoff may steer goes to a session he can open (DL-222):
  - code runs start a background Opus session with Remote Control;
  - design runs start a Duo session, for the canvas.

  The scheduled task's own session only starts the worker and posts a console thread.
- **Inputs:**
  - the diff since the last review of the same kind;
  - the previous review's open items;
  - `codebase-review-tools/` measurements (under the `--exclusive` lock);
  - the catalogue;
  - for design months: the month's merged UI captures and `docs/design/system/`.
- **Output:** `docs/research/<date>-<code|design>-review.md` on a branch the director merges, and **at most 5** console cards, each with evidence, size, risk and a recommendation. Each card says build now, later or no, and a "build" becomes a task note. Design proposals are [P] boards on a canvas.
- **Guard against noise:**
  - it carries forward the previous run's unshipped items before adding new ones;
  - the bar is a measured cost, a confirmed bug or a duplicated pattern, never taste alone;
  - a run with nothing clearing the bar says so in one line and posts no cards;
  - if two runs in a row produce nothing Geoff builds, the director proposes slowing to monthly.
- **Cost:** Opus leads, with 3–4 Sonnet reviewers and Haiku for measurement loops. It takes 1–2 h, about twice a month, and is the most expensive job here. That is why it starts after A, and why its cadence is the first thing to cut.
- **Maintenance:** one procedure doc. The review method is the 10-12 review's, already written down.
- **Overlap:** A finds drift, and D finds design and structure. D never re-reports A's items. Problem discovery's clusters are an input to D: a cluster of bug reports in one area is a reason to look there.

## 5. Mechanical checks to add (ENH-281 to ENH-284)

These make A cheap, and some drift impossible:

- **ENH-281** — `check-records.sh` adds warnings, never failures, for a Q or C row whose notes say "answered", "built" or "DL-n" while its status says open, and for a stand-in Q older than 14 days.
- **ENH-282** — a task-note check: an `in-progress` or `review` note whose branch is merged into main, or with no Progress line for 7 days. It goes in `tidy-scan.sh`, with a DuoChecks-style unit check.
- **ENH-283** — `docs/design/README.md`'s status column against `surfaces.md`, as a script; the merge gate warns on any mismatch.
- **ENH-284** — `merge-gate.sh` appends one line per gate per run to a machine-local log (outside the repo), with pass, fail and pass-on-retry. A reads it for flaky gates.
- **ENH-285** — (for C) the brief template's "catalogue rows" line, and a feature-merge detector in `tidy-scan.sh`.
- **ENH-286** — (later) a fitness function for the idle budget: a background `check-scale` idle-CPU reading in the merge gate on `Sources/` merges, so the next C-79 fails a gate instead of waiting for a review. It needs the exclusive lock, so it waits until merges are calmer.

## 6. Questions for Geoff (Q-273 to Q-278)

- **Q-273** — Build A, the weekly tidy-up, as one job with sections? (Recommended: yes, Monday 08:00, a console card only when something is new.)
- **Q-274** — Add B, the release brief, to the release procedure, with launch tiers, video proposals and intro-film staleness? (Recommended: yes.)
- **Q-275** — Build C, the feature catalogue, once, then keep it by merge rule? (Recommended: yes, with an Opus session now.)
- **Q-276** — Should A also *run* the performance budgets weekly under the exclusive lock, or only say when they're stale? (Recommended: only say, until ENH-286.)
- **Q-277** — Start D, the fortnightly deep review alternating code and design? (Recommended: yes, after A's first two runs, so November.)
- **Q-278** — Does A's card go on the console, or on its own page? (Recommended: the console. One place, and problem discovery already has its page.)

Picks become **DL-240**. Each picked job becomes a `status: suggested` task note for the director, which writes the procedure doc and creates the scheduled task. This study schedules nothing.
