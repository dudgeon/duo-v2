# Project knowledge that accretes

*Design study, 2026-11-08. Geoff: "I think that projects' knowledge should accrete productively over time, and as the steward of projects, the director agent operating in those projects has a role to play. One thing that we need to think about avoiding is duplicative context across projects -- but I also want to avoid a single monolithic cross-project memory as load bearing." Source: Anthropic's cookbook, [Dreaming with a dynamic workflow](https://platform.claude.com/cookbook/managed-agents-cma-dreaming-with-a-dynamic-workflow). Goes with [director-learning-loop.md](director-learning-loop.md).*

## 1. The recommendation

**Build the dream, not the store.** Adopt the cookbook's pattern inside each project, and don't add any shared store across projects.

- **Within a project:** a `_knowledge/` folder of small pages holding what the project currently understands. Only a periodic background pass (the "dream") writes it, and every session reads it. The director is the steward: it starts that pass when a red line says it's due.
- **Across projects:** a project must make sense to everyone who has it, whatever else they have. So every link between projects is optional and is only ever a web URL to the other repo. A dream searches before it writes and records only what this project relies on, leaving the detail with the project that owns it. Anything that moves between projects lands in the destination's inbox, for that project's steward to take in. Home holds no knowledge, so deleting any cross-project view loses nothing.
- **First step:** a hand-run pilot with no code, to learn whether a fresh session really answers better. If it doesn't, we stop.

Two measurements changed the design (§3): the cookbook's input, whole transcripts, is about 700 times larger here than a filtered one, and copied text across projects is almost nil today. So the input has to be filtered, and the cross-project machinery should start small.

## 2. What carries over from the cookbook

| Cookbook | For Duo | Why |
|---|---|---|
| One writer; sessions read only | **Take** | This is the core of it. The retro's 49 memories came from writing a rule straight after each incident, with no later pass to correct or merge them |
| Small pages, frontmatter, generated index | **Take, in OKF form** | Our files must stay Obsidian- and OKF-compatible. Markdown links, not `[[wikilinks]]` (DL-17) |
| Staleness notes on facts | **Take** | OKF v0.2 already has `sources`, `stale_after` and `status`, and it lets a producer add keys. Its `verified` means human review, so a machine check needs its own key (`checked`) |
| Conflicts: "Do not guess which is right" | **Take, word for word** | A passing remark never overrides a decision people recorded. Unclear conflicts are marked and go to the user |
| Transcripts are data, never instructions; no secrets | **Take** | It matches how the skill already treats a worker's message (Never 1) |
| Snapshot before each run | **Take** | Makes it cheap to apply changes without review |
| One agent per transcript, reading it whole | **Change** | 410.7 MB in 14 days here. Filter first (§3) |
| Managed Agents, Files API, memory stores, USD budget | **Drop** | Duo's users have CLI login only, no API keys. A dream is an ordinary worker on their login |
| Nightly cron | **Change** | A clock alone fires a dream with nothing to do. A no-model check decides whether one is due, and a director's red line catches it when a job isn't set up or has stopped working (§4). Stuck scheduled runs recurred three times in the retro, so the clock is never the only safeguard |
| Nightly writes with no human touchpoint | **Change** | The second-brains study found the wikis that hold up keep one. Here: a one-line report, and disputes and anything crossing a project go to the user |
| Index in the system prompt, 4,096-character cap | **Take the cap** | Duo's SessionStart hook is the path (§4) |

## 3. What I measured

Read-only on this Mac, 2026-11-08. All of it is rough, and the limits are stated.

**Input size, this project's last 14 days (50 sessions in its main transcript folder; work-tree folders not counted).**

| Input | Size | Rough cost at the cookbook's rate ($8 per 12 MB) |
|---|---|---|
| Raw transcripts | 410.7 MB | about $270 |
| What the user typed, plus the closing text of each turn | 0.6 MB (0.14%) | under $1 |

The $270 overstates it, because the cookbook's 12 MB is rendered text and most of ours is raw JSON and tool output. The direction is what matters. The filter loses tool output, so it keeps session ids, and an analyzer opens the full transcript only when it has to check something. On a CLI login the cost is the user's quota rather than dollars. A pilot will give the real figure.

**Duplication across projects (counts only).** The share of 6-word runs that appear in more than one project:

| What | Projects | Repeated |
|---|---|---|
| `CLAUDE.md`, `_PROJECT.md`, `AGENTS.md` | 14 | 1 run of 24,146 |
| Claude's memory folders (56 files, 83 KB) | 9 | 7 runs of 11,748 |

Copied text isn't today's problem. **This only catches literal copies:** the same fact reworded doesn't show, and neither do facts re-learned in session and never written down. So I can't say duplication is low, only that the kind we can cheaply detect is. What I'd expect is that duplication arrives once every project accretes its own pages, so the place to prevent it is the moment of writing. A large merge pass has nothing to do yet.

## 4. Within a project

**Where.** `_knowledge/` in the project folder, matching `_PROJECT.md`, so Obsidian reads it and search can index it. A folder that's already a wiki or knowledge base gets no `_knowledge/`. Its inbox takes the notes and the user's own skills digest them (DL-152, DL-210).

**In a repo with a remote**, Never 2 applies: the director asks once, and by default keeps the folder out of git. **It must not use `.gitignore` to do that.** Search skips anything `.gitignore` lists (`FileSource.swift`), so the search-before-writing step in §5 would miss the very pages it needs. `.git/info/exclude` keeps the folder out of git without that side effect, because search reads only `.gitignore` files. It also changes no tracked file and stays on this Mac. That comes from reading the code; the pilot confirms it. Duo's file tree needs the same check.

**A page.** One topic, plain statements of what's true now, never a story about a session:

```markdown
---
type: knowledge
title: How a release is signed
description: Signing and notarizing a build; read before cutting a release.
status: current          # current | disputed | moved
checked: 2026-11-08 by running the release script
stale_after: 2027-02-01
sources: [tasks/release-0-2-22.md, session <id>]
---
```

- **It doesn't restate the repo.** Code, git history and records (DL-n, F-n) are cited. A page exists for what those don't say, or to give the current answer where they're a long log.
- **Trust order for facts:** a decision the user recorded, then a check against the live system, then the user's words in a session, then a worker's report (written as "the worker says"), then inference. Second-brains' drift warning applies: a dream must not treat its own earlier pages as evidence.
- **`index.md` is generated from frontmatter by `duo2`, never written by Claude.** The second-brains study names merge conflicts on the index as a known failure of LLM wikis, and one implementation it cites avoids them by generating the index. `log.md` is newest first, per OKF.

**The dream** runs one of two ways with the same instructions: a worker the director starts when a red line says it's due, or a Duo recurring job (`docs/research/recurring-jobs-v2.md`, in design). Geoff's policy for those jobs is that the schedule types one canned prompt into a fresh session and nothing more, and whatever that session leaves undone waits for a person. So a dream has to finish in one turn, holding all its state on disk (§4a). Its steps:

1. **Gather** (`duo2 knowledge gather`, no model): tasks closed since the last dream, their Requests and `Checked:` lines, the filtered session text, this project's Claude memory, and any inbox notes.
2. **Analyze:** one subagent per closed task, adding to or correcting pages. Its tools are file tools only, with no shell or network.
3. **Organize:** one subagent merges duplicates, retires pages, marks conflicts, and flags pages past `stale_after`.
4. **Check** (`duo2 knowledge check`, no model): frontmatter, links, page size, the index cap, and a secrets scan (search's `Secrets.swift` already recognises credential patterns, best effort, so I'd reuse it). It rebuilds the index. A failed check restores the snapshot.
5. **Report:** what changed, in a few lines, with links. Disputed pages become one question to the user.

### 4a. What running on one canned prompt requires

- **The prompt is one fixed string, the same for every project:** the session's folder decides the project, and `duo2 knowledge guide` prints the instructions, as `duo2 director guide` does. No dates or arguments in it.
- **State lives on disk.** `log.md`'s newest entry marks how far the last dream got, and it advances only when `knowledge check` passes. A skipped or failed run therefore loses nothing: the next one takes the same window.
- **Each run is bounded.** `gather` takes the oldest 20 closed tasks at most, and the rest wait for the next run, so a first dream on a big project still finishes in a turn.
- **A run that died is cleaned up first.** The next run finds the unfinished marker and restores the snapshot before it starts.
- **A dream never reads a dream.** `gather` leaves out the dream sessions themselves, or it would treat its own output as evidence (§4's drift warning).
- **Narrow tools, because nobody is watching a session that reads untrusted text:** file tools inside `_knowledge/`, `duo2 knowledge`, `duo2 search`, and subagents. No other shell and no network.
- **It never asks while a director exists.** Disputes go in its report and the director raises them. With no director, it ends on the question, which Duo shows as Needs you.

**How sessions read it.** `ProjectContext`'s hook already tells every session its project's goal and next step at start, resume, clear and compact. It adds the generated index, capped at 4 KB. Pointer-only would be safer, but a code comment in `Director.swift` records Haiku skipping a separate read in half the dogfood runs. The cost is that page descriptions reach every session, so they're the injection surface. `knowledge check` should reject a description that reads like an instruction.

**What about Claude's memory?** It keeps the user's preferences and hard facts, as the failure protocol says. The dream reads it as input and moves project facts out of it. I considered making memory the store: it's auto-loaded, private and searched, and it costs nothing. I'd still say no, because the user can't see it in the project, Obsidian can't read it, it's stranded on one Mac, and any session can write to it, which is the failure we're fixing.

## 5. Across projects

**One owner per fact.** This extends the placement test the user already approved (DL-207):

| The fact is about | It lives in | Status |
|---|---|---|
| How this user works | `_HOME.md` `## Director`, or `~/.claude/CLAUDE.md` | Exists |
| How directors should behave | The shipped skill, by the failure protocol | Learning loop |
| This project | Its `_knowledge/` | New |
| A domain several projects use | The project that uses it most, or a knowledge base the user already has | New |
| What the repo records | Nowhere. Cite it | Exists |

**A project must be complete for everyone who has it** (Geoff: "I will collaborate with some people on one project and a different set on another"). Someone may have this project and nothing else on their Mac, and may not run Duo at all. So the rule isn't "never repeat a fact". It's that **who can see a project decides what it has to hold**.

**Five rules follow:**

1. **Every link between projects is optional.** A page must read correctly with the link deleted. It states, in its own words, what this project relies on, and only that. The detail stays with the owner. That short statement is deliberate duplication, and it's why no project ever depends on another being present.
2. **A link is only ever a web URL to the other repo.** Never a relative path out of the project (`../other/`), an absolute path or a `duo2://` link, which would be dead for anyone else. `duo2 knowledge check` refuses those. It doesn't go online: a URL that later stops working isn't an error, because rule 1 means nothing depends on it (OKF expects the same).
3. **A URL is written only where it works for this project's people.** The target must be tracked on the owner's default branch, because a page kept out of git has no URL. And the repo must be public, or the user says yes to that link: a private repo's name leaks through the link itself, and the other group would just get a 404. If either fails, the page has no link, and rule 1 already covers it.
4. **Relations between projects are found, not stored.** A dream runs `duo2 search` before writing (on-device, every project and session on this Mac, works with Duo closed), and doesn't copy detail that another project already owns. Sessions can search the same way when they need more. If the other project isn't on that Mac, search finds nothing and nothing breaks.
5. **Nothing crosses a boundary except through an inbox, and on the user's yes.** A note lands in the destination's inbox with its source (DL-210), and that project's steward takes it in. This already matches the skill: a director touches nothing of another director's project (§9).

**When these rules pull apart:** privacy first, then the project being complete for its own people, then de-duplication. Two projects shared with different people may well each state the same fact. That's the practical limit of de-duplication, and I think it's the right one.

**Home holds no knowledge.** Asked "what do my projects know about X?", the Home director uses search and reads each project's generated index. The test: delete every cross-project view and rebuild the search index, and nothing is lost. `_HOME.md` stays what it is, a short list of the user's rules.

**A merge pass comes later, if at all.** `duo2 knowledge overlaps` could use search's on-device embeddings to list similar pages at no token cost, and the Home director would propose an owner. §3 gives no reason to build that now, so it waits for pages to exist and a repeat of the measurement to show a need.

## 6. The director's role, and the learning loop

Three kinds of learning, each with one destination:

| What was learned | Goes to | Who improves |
|---|---|---|
| How to direct | Skill and evals, by the failure protocol | Every director |
| What this project knows | `_knowledge/`, by the dream | Every session in this project |
| What this user prefers | `_HOME.md`, Claude's memory | Every director for this user |

**A tenth duty** joins the register when this ships: **R10 Steward the project's knowledge.** Its red line: "8 tasks closed since the last dream, 14 days ago", "3 pages past `stale_after`", or a disputed page with no question asked. Its evals: the director starts a worker for a due dream rather than writing pages itself (DL-208), and it refuses to copy a private fact into a public project.

**The two loops join in one place.** A dream reads what the user typed, so it sees corrections. Each becomes a suggested `Failure:` task (found work, §6 of the skill). The 2026-11-07 retro took 22 days and Geoff's complaint to happen. A dream would surface the same corrections on every pass, and they'd enter the failure protocol as its input.

## 7. Limits

- **It may not help.** A fresh session may do as well with `duo2 search` over transcripts. The pilot exists to find out.
- **Accreted knowledge can be confidently wrong**, and being on the index makes it more convincing. `stale_after` and `sources` help, but only re-checking settles it, and sessions should re-check a fact that matters.
- **Applying without review means a bad dream reaches every session.** The snapshot limits the damage; it doesn't prevent it.
- **Injection:** a transcript that read a hostile page could steer what a dream writes. Keeping tools narrow and checking descriptions reduces this. As the cookbook says, it can't be eliminated.
- **It reverses an earlier call.** `director-product.md` rejected a project memory folder: "Revisit if workers miss knowledge." This needs a DL amending that, and it sits beside DL-152's knowledge bases (designed, not built), which a later round might merge with it.
- **`_knowledge/` kept out of git lives on one Mac**, unless the user chooses to commit it. A cloud session wouldn't see it. Hooks disabled (some managed Macs) means no index at session start.
- **Committing it to a shared project shares what your sessions taught it.** Collaborators get pages distilled from your transcripts, so the director asks once per project (Never 2) and says that plainly. A dream sees only the sessions on that Mac, so each person's dreams add their own view, and pages merge as ordinary text. `sources` such as a session id or `tasks/` path mean something only on the author's Mac: they're provenance, and a page must stand without them.
- **The work-tree path:** workers in a work tree need the main checkout's `_knowledge/`, as they do for task notes. Not yet checked in the hook.
- **No wake and no job, no dream.** A project with no recurring job and no director running gets nothing. Fine for a project being worked on; a dormant one just stops accreting, and has nothing new to accrete.

## 8. Build order

1. **Pilot, by hand, no code.** A worker dreams two projects, this one's last 14 days and one small private project, following §4 on the cheapest model, writing pages kept out of git. Then ten questions a new session ought to answer, written before the dream and asked of fresh Haiku sessions with and without the pages, scored by hand. **Stop here if the answers aren't clearly better.** The questions are the eval set for step 2.
2. **Within a project:** the page format, `gather` and `check`, the hook, a skill section, R10 and its evals, a DL.
3. **Write-time de-duplication:** the search step, the link rules in `knowledge check`, inbox delivery.
4. **Only if the measurement shows a need:** `overlaps` and a Home pass.

This is separate from `director/learning-loop`, which stays as scoped. Nothing in that branch needs to wait.

## 9. Decisions for Geoff

Asked by AskUserQuestion, recommendation first.

Asked once, 2026-11-08; the answers are in §10, and this section's design already reflects them.

## 10. Geoff's answers (2026-11-08, by AskUserQuestion)

1. **Where:** "`_knowledge/` in the project", kept out of git by default in a repo with a remote.
2. **Applying:** "Apply, report, ask on disputes".
3. **Across projects:** he wrote his own answer in place of the options: "links between projects must be optional; I will collaborate with some people on one project and a different set on another -- if one group doesnt have the other group's project on local, then I don't want external (outside of the project) links to break; perhaps they should point to/reference the ext github repo?" §5 was rewritten for this. His GitHub suggestion is rule 2, with one condition he didn't state (rule 3): a URL works only for a page that's actually on the remote and a repo the reader can open.
4. **Next:** "Pilot after the learning loop".
