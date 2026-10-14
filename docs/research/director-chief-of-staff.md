# The director beyond building: librarian and chief-of-staff work

**Decided 2026-10-14: DL-207 to DL-210** (Q-196, closed), all as recommended. DL-210 adds Geoff's note: "Director can offer to invoke curation skills — the project.md should describe how those work".

A design study, 2026-10-14, for the director decided in DL-193 to DL-204 (`director-product.md`). Decisions it raises are on the director-product page (13 to 16), and Q-196 tracks them.

## What Geoff asked

Geoff, 2026-10-14:

> "If I imagine opening my home project and talking to the home project director, I think it is intuitive that I would bring it a mix of builder tasks, so feature extensions on a software product that I'm maintaining, deep research tasks and prototyping tasks. But I think it would also make sense to bring it librarian or chief of staff tasks. For example, I just came out of a meeting. Here are the notes that I've taken. Please route the spans of these notes to the appropriate knowledge bases. Infer tasks. Create tasks within the right projects, etc."

He asked how well the director as designed handles that, and in particular how well its way of improving itself fits these jobs: proposing additions to `PROJECT.md`, and a preferences file for rules that aren't tied to one project. He also asked for the preferences file not to repeat what a project's file already says, and for a name for it. His example of a cross-project rule ("which spans of notes go in which knowledge base") is one he thinks could live in Home's file.

## Facts this rests on

- **Home's file is `HOME.md`, not `PROJECT.md`** (DL-42, DL-52). It carries the same fields. Home is a project whose folder holds your other projects (DL-83), so a director in Home can read and write their files without leaving its own folder. Folders outside Home can also be projects (DL-82); for those, Claude Code asks permission to write.
- **Knowledge bases** (DL-152) are decided but not built: any project or Home can be marked as one in Settings, with an inbox folder, an index, a log and a schema. The mark is Duo's own state, so nothing is written into the folder. Geoff ruled that users bring their own skills for maintaining a wiki (Q-133: "we don't want to limit their ability to do this").
- **A project's own skills load only for sessions running in that project's folder.** A director in Home doesn't get a knowledge base's ingest skill unless it reads the skill file itself, or hands the work to a worker running in that folder.
- **Decided for the director:** it asks in session (DL-198); proposed work is `status: suggested` (DL-194); found work links back to where it was found (DL-195); it records your decisions in `## Decisions` and completed work in `## Done` (DL-193, DL-204); it checks, then you say go (DL-202); one task per worker, at most three workers (DL-201).

## Walk-throughs

### 1. Day one: a new user, an empty `HOME.md`, meeting notes

You open Home, start the director and paste notes from a 30-minute meeting: four topics, two people's updates, a pricing question, three things you promised to do.

**What the design does well.** The director makes one task in Home, "File notes from the 14 Oct pricing sync", and saves the notes in its task folder unchanged (DL-194). Your three promises become suggested tasks, each in the project it belongs to, each linking back to the meeting note (DL-195). Nothing is filed until you approve (DL-202).

**Where it falls short.** To route a passage, the director needs to know which knowledge bases exist and what belongs in each. With knowledge bases unbuilt and `HOME.md` empty, it has neither. Its only sources are each project's `PROJECT.md` (often sparse, as you said), its `CLAUDE.md`, and its folder names. So the first run turns into an interview: "I found six folders that look like knowledge bases. Here's what I think each holds. Is that right?" That's the right behaviour (DL-193: propose, you accept), but it has to be designed in. Out of the box, a director built around builder work would just guess.

**What the answers should become.** "Work-Acme holds anything about Acme: pricing, contracts, people" describes a destination, so it goes in **Work-Acme's own `PROJECT.md`**, not in Home's file or a preferences file. Each knowledge base then describes itself, and routing means reading those descriptions. This is DL-193's rule ("project-specific guidance goes in the project") applied to the destinations, and it's what keeps the files from repeating each other.

### 2. Week three: routine filing, and a correction

Scopes are written down by now. You paste notes. The director proposes: "Five passages: three to Work-Acme, one to Reading, one to Home's own notes. Two new tasks: one in duo-v2, one in Work-Acme." You press File as proposed.

**Where it lands.** Each passage becomes a new note in the destination's inbox, holding the passage, the date and a link back to the meeting note. The director doesn't rewrite the knowledge base's pages. Your own skill for that knowledge base processes the inbox later, which is the line Q-133 drew. If a project's `## Director` rules say "file straight into the wiki with /ingest", the director hands that passage to a worker in that folder, where the skill loads.

**The correction.** You say "the pricing bit goes to Work-Sales, not Work-Acme". The director moves the note. The design so far would propose a rule on the spot, but in librarian work corrections are frequent, small and noisy, and a question after every one would be nagging. Better: it notes each correction in the filing task's Progress, and proposes a rule once a pattern repeats ("You've moved three Acme pricing passages to Work-Sales. Add 'Acme pricing' to Work-Sales's scope?"). The rule goes in the destination's `PROJECT.md`.

### 3. A mixed request

"From that meeting: (a) add CSV export to the app, (b) research how competitors price per seat, (c) file the rest."

- **(a) is builder work.** The director makes a task in the app's project. If that project has its own director, Home asks that director (DL-197), through messaging or with Duo carrying the message (DL-199). Otherwise it starts a worker there itself.
- **(b) is research.** It gets a task and a worker. If it belongs to no project, the task goes in Home, or the director offers Make a Project.
- **(c) is filing.** Starting a worker to move six passages would cost more than doing it, and the worker would lose the meeting's context. **The decided design has no room for the director doing work itself** (the glossary says "it doesn't do the work itself"). For organising work (splitting, routing, filing into inboxes, making tasks, proposing changes to project files) the director should do it directly, with your approval, as one task per request. Long work, and work that needs a project's own tools or skills, still goes to a worker.

### 4. Chief of staff: "what's on my plate?" and "prep me for 2pm"

- **"What's on my plate"** reads well from what exists: open and suggested tasks across projects (`duo2`), sessions that need you, and recent `## Done` lines. That fits.
- **"Prep me for my 2pm with Sam"** needs your calendar, which is a connector the user may or may not have. The director should use the tools it has, the way DL-198 treats artifacts, and say what it couldn't see. Nothing in the skill should assume a calendar.
- **"Remind me Friday to chase Sam"** needs something to wake on Friday. A director that isn't running can't. The decided pieces give it a task with `waiting_on:` and a note, which shows on the board but doesn't nudge. Scheduled reminders are a separate feature and are out of scope here.

### 5. A director in a project, with rules in Home

You're in duo-v2's director, and it's about to ask you something. Your rule "ask me one question at a time, recommendation first" lives somewhere that isn't duo-v2's file. Under DL-193 that's `~/.claude/duo-director.md`. Under decision 13's recommendation it's `HOME.md`'s `## Director` section, which every director reads wherever it runs.

## What this shows

**What fits as decided, with no changes:**
- **Suggested tasks** are exactly what inferred tasks from a meeting should be: proposals you accept or delete (DL-194).
- **Found-from links** give every filed passage and inferred task a way back to the meeting note (DL-195).
- **Ask, then act** (DL-202) is right for routing: you approve one plan per meeting, not each passage.
- **A task with a folder** is a good home for a filing job: the raw notes are its file, and the plan and corrections are its Progress (DL-194).
- **Completing and archiving with your say-so** (DL-204) keeps filing tasks from piling up. These will be the most numerous tasks a chief-of-staff director makes.
- **Propose-and-accept edits to project files** (DL-193) is the right way to teach routing, as long as the description lands in the destination's own file.

**What needs changing or adding** (decisions 13 to 16, then commitments):

1. **Where your cross-project rules live (decision 13).** Most cross-project rules that matter here are about your world, not about how a director behaves: which knowledge bases exist, what goes where, what's private. Home is the project whose subject is everything, so those are Home's project rules, and they belong in `HOME.md`. What's left for a separate preferences file is small ("one question at a time", "cap me at five workers"), and it fits in the same place. **Recommended: `HOME.md`'s `## Director` section is where your rules for every director live.** It uses the same heading as a project's rules, so there's one name for the whole idea: the Director section. A project's section wins inside that project. This drops `~/.claude/duo-director.md` from DL-193. Without a Home, a director offers to set Home up (Duo already prompts for one, DL-84) or saves the rule in the current project. Rules for every Claude session, not just directors, stay in your `~/.claude/CLAUDE.md`, which is Claude Code's own file.
2. **The director does organising work itself (decision 14).** See walk-through 3.
3. **Logs mustn't swamp the rules (decision 15).** A chief-of-staff director in Home could add dozens of `## Done` lines a week to `HOME.md`, which every director reads in full at start and which Duo shows in Home's header. **Recommended:** `## Decisions` stays in the project file, because decisions are guidance. `## Done` keeps the latest 20 lines there, and older lines move to a `log.md` beside it, which the director searches before new work (DL-204's scan). Filing receipts (passage → destination) never go in the project file; they stay in the filing task's note.
4. **How a filed passage lands (decision 16).** **Recommended:** a new note in the destination's inbox (Duo's knowledge-base inbox when marked, otherwise its `inbox/`), with the passage, the date and a link to its source. Your own skills digest it from there. The director edits a knowledge base's pages directly only when that project's Director section says how.

**Commitments (no question needed):**
- **What belongs where lives with the destination.** Each knowledge base's `PROJECT.md` says what belongs in it. The first time it routes, the director proposes those lines in one interview. After that, it proposes a scope change only once a correction repeats, never after every correction.
- **Privacy follows the destination.** The routing plan shows when a destination is shared or published (a git repo with a remote, a public repo), and a passage going there always needs your explicit OK. An example: duo-v2 is public, so a 1:1 note must never land there by inference.
- **Filing the same notes twice doesn't duplicate them.** Each filed note records its source and passage, so re-pasted notes are recognised.
- **Knowledge bases before DL-152 is built:** the director works from each project's own description and from what it sees in the folder (an `index.md`, a `log.md`, an `inbox/`). Once knowledge bases are built, `duo2 kb list` gives it the inbox, index and log paths exactly.
- **The core skill stays generic.** It knows how to split, route, file into an inbox, infer tasks and ask. It knows nothing about any knowledge base's format; that's the user's skills and Director sections. This keeps the "not constricting" line from round 4.

## Failure modes, and what catches them

| What goes wrong | What catches it |
|---|---|
| A passage filed in the wrong place | The plan is approved before filing; moves are undoable; repeated corrections become a scope line |
| A private passage lands in a shared or public folder | The destination's visibility is shown in the plan, with an explicit OK for each one |
| `HOME.md` turns into a log | Decision 15 |
| The same rule in `HOME.md` and a project file | Placement test: if it would be true in another project, it goes in `HOME.md`; if it describes this project, it goes in the project's file. The director names where it will save a rule when it asks |
| The director nags with rule proposals | It proposes only once a correction repeats |
| A knowledge base's own skill is never used | Its Director section names the skill, and the director hands that passage to a worker in its folder |
| Inferred tasks pile up as suggestions | Suggested tasks go through the same sweep as completed ones (DL-204): "these five suggestions are two weeks old. Keep or delete?" |
| Work in a folder outside Home stalls on a permission prompt | The director delegates that work to a worker in the folder |
