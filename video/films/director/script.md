# Director explainer — script v1
<!-- Synced from the script Doc at rev 25 on 2026-10-12 by pipeline/sync.mjs; edit the Doc, not this file. -->

Oct 12, 2026 · @Geoff Dudgeon

A second film in your voice, on the same pipeline as the intro: how the Duo director works, told in infographics and motion graphics over the house background, with few or no Duo screenshots. Each build reads this doc; the rules below are what the build understands, and anything else is notes for us.

## The brief

Fill these four in first; I read them before every scene decision. (The build ignores this section.) I'll ask you for them by buttons.

|  |  |
| --- | --- |
| **One sentence** the viewer should remember | Not yet. Your call (Oct 12): no catch phrase for now, and no Claude-isms anywhere. |
| **Who it's for** | A wide spectrum of Claude Code users. The examples are about driving software development, but it should feel relevant to knowledge work in general. |
| **Length** | About 3 minutes: roughly 500 words. |
| **How it should feel** (and what it must not feel like) | Calm, clear and explanatory: something helpful you found and want to share with friends. Not bragging, not claiming to have invented it. No superlatives: say how many features, refactors and merges shipped, never that it was a lot. |

**Points you added (Oct 12):** workers took a wide variety of tasks without predefined specialist personae; and the film ends with a tease: two patterns that aren't common yet, persistent agents (like this one) and shared agents, and what the two together might do.

## How to write it

- **A scene is a `###` heading:** `### S1 · Title (about 20 s)`. Keep the `S` number at the front; it ties the scene to its shot. The time is a target; the real length comes from the voice.
- **Each bullet under a scene is one voiceover line,** voiced and checked on its own. One sentence or clause per bullet; long lines get rushed.
- **`Shot:` is a plain-English note of what we see.** Say what the viewer should notice, not how to animate it. I turn it into diagrams, motion and callouts, and every item in it gets built or named as a stand-in.
- **Callouts:** if a line names something a diagram should point at, put the phrase in *italics*. That's where the marker lands.
- **Diagrams explain, never decorate.** This film is infographics over the house background, not screenshots. Every shape stands for something real: a session, a branch, a message, a release.
- **Only real things.** Numbers and events come from the repo and the records (releases, merges, DL- and F-numbers). Nothing private: no work-Mac management details unless you OK the wording, no tokens, no private paths.
- **Anything else** (a paragraph, a question, a `> note`) is ignored by the build. Use it freely.
- **No shot ever cuts to the next.** Every scene change is a motion graphic where something on screen carries across into the next idea. The build refuses a plain cut or dissolve; a Shot: note can ask for a particular one.
- **Topic:** is the scene's name in the topic list at the left that comes up at each scene change. One short line under the heading, like `Topic: The problem`. `Topic: same` keeps a scene under the previous one's entry.

## The voice

The narrator is your own voice, the fine-tuned VoxCPM2 clone the intro uses (DL-173). The build reads this table: write the word as it appears in a line, and how it should be said. Add a row whenever a line comes out wrong.

| Written | Said |
| --- | --- |
| v2 | vee two |
| duo2 | duo two |
| cli | C L I |
| GPU | G P U |

## Scenes

> Eleven scenes: your six beats, plus why it works, generalist workers, the tease and the link to the skill. Lines are first drafts from the records and the director's answers; `(line)` is a slot for you. Numbers marked *(to check)* get confirmed before voicing. Aiming at about 500 words; the draft runs a little long, so expect cuts.

### S1 · The problem (about 20 s)

Topic: The problem

- Building Duo, I often had ten or more Claude Code sessions running at once.
- Each one needed me to brief it, check its work, merge it, and remember where it had left off.
- I had become the switchboard.

Shot: you as one node in the middle; sessions appear around you one by one, each tied to you by a line. Each time one finishes or asks a question, its line pulses toward you, until every line is pulling on the centre.

### S2 · One prompt (about 20 s)

Topic: A simple prompt

- On October fifth, I started one more session and typed this.
- *There are many sessions in this repo, all in various states. You are now their director. I am the PM and you are the engineering manager.*
- Then I asked it for a quick survey of where each session stood.

Shot: the prompt types itself onto a card, the director's own words. As it lands, the tangle from S1 reorganises into the tree of style frame B: you on the left, the director beside you, the sessions in a panel to its right. The director's first survey runs down the sessions. One line reaches you now.

> Verbatim, from the director's transcript (e0127e51, Oct 5, 10:08): "There are many sessions in this repo/project all in various states—you are now their director. I am the PM and you are the engineering manager. Please do a quick survey of the state of each of these active sessions". The line above trims "repo/project" for the voice.

### S3 · Writing the job down (about 20 s)

Topic: Along the way

- A long-running session gets compacted, and each time, the director lost its own job description.
- So on day three it wrote the job down as a skill: how to brief a session, how to review and merge, and when to ask me.
- Every decision I make goes into a numbered record, so no one asks me twice.

Shot: the director's card unfolds into its job description, one section per line (Taking work, Reviewing and merging, Records, Releases, Talking to me). Numbered records stack beside it like a ledger.

### S4 · What we added (about 40 s)

Topic: same

- New work goes to a new session. The director doesn't build; it delegates and reviews.
- Sessions run in the background with Remote Control, so I can follow any of them from my phone.
- A model rule: the larger model plans, a mid-size one builds, the smallest one runs the tests.
- Decisions come to me as buttons, with a recommendation first, on a console page I can open anywhere.
- And the piece everything else hangs on: sessions message each other. A worker tells the director when its work is committed, and the director wakes it with the next step.

Shot: a timeline from October fifth to today runs under the tree from S2. Each addition drops onto its date as the line names it, and the tree changes to match: sessions slide into a background lane; three model tiers colour the sessions; a phone appears between you and the director with the console's buttons on it.

> Dates: delegate-don't-build and Remote Control (DL-128), Oct 6; background sessions, buttons and the model rule (DL-153), Oct 7–8; the console (DL-166) and peer names (F-259), Oct 9; the GPU lock and geoff-voice, Oct 11–12.

### S5 · Why it works (about 25 s)

Topic: Why it works

- With subagents, one session can farm out many features at once, but the work stays out of reach until it comes back.
- Here, each worker is a full session. It works in its own branch, so features don't collide, and I can open any one of them and work alongside it.
- The director reads each worker's short report, not its whole transcript, so its own context stays small.
- (line: the messaging channel is what makes this work)

Shot: two diagrams side by side, then one. Left, subagents: small boxes inside the parent session's outline, their work flowing back into it until the outline swells. Right, the director: full sessions outside it, each on its own branch line, with only a short report arrow back, tagged "since Claude Code 2.1.224"; your figure steps into one session, then out again. The director's outline stays the same size the whole time.

> Your point (Oct 12): the director lets many features run one after another without collisions, like subagents, while keeping the ability to roll up your sleeves and work closely with any agent, without bloating the director's context window. And: the messaging channel between agents is important.

> Your call (Oct 12): name the version. The Shot shows a small tag on the messaging arrow: "since Claude Code 2.1.224".

### S6 · Generalists (about 15 s)

Topic: Generalists

- Many multi-agent setups give each worker a specialist persona.
- We didn't. Any worker could take a design study, a bug hunt, a release check or a research question, given a clear brief.

Shot: the worker sessions under the tree each take a different task card in turn (design, bug, release, research, video) without changing shape or label: the brief is what changes, not the worker.

### S7 · What got done (about 25 s)

Topic: What got done

- In the week since that first prompt, the director oversaw fifteen releases and a hundred and eighty-seven merges.
- (line: how many major features and refactors, named briefly)
- About a hundred sessions did the work; I made the decisions.

Shot: the timeline from S4 fills with what shipped: release tags as markers, merges as ticks, a few features named. Each count runs up as the line says it.

> From the director *(to check)*: 15 of 22 releases (0.1.7 to 0.2.11), 187 of 192 merges, 590 of 728 commits, about 100 sessions; records: \~179 decisions, \~293 findings. Candidates to name: the 0.2 line with chat mode; a work-laptop freeze found from field hang logs and fixed overnight; a design system with pixel-checked screens; this film's pipeline and voice; a whole-codebase review. I still need a count of major features and refactors.

### S8 · Patterns for your setup (about 30 s)

Topic: Patterns

- The pattern bends to what your Claude Code can do.
- On an older version, workers run as one-shot jobs and pass messages through files.
- Without Remote Control, you follow sessions in one app instead of on your phone.
- Without a page for buttons, the questions come in the chat.
- On a managed work laptop whose Claude Code is pinned months behind, the director still runs; only the way workers report back changes.

Shot: a grid of constraints (Claude Code version; Remote Control on or off; a page for buttons or not). For each cell, the director tree from S2 redraws to show what changes: which arrows become files, which move into the chat.

### S9 · Claude Code Projects (about 15 s)

Topic: Projects

- Claude Code now has Projects: one coordinator in charge of many sessions, built in.
- I don't have access yet. Everything here is built from pieces that ship with Claude Code today.

Shot: the home-built tree sits beside a second tree labelled Claude Code Projects; the shapes match, part for part.

### S10 · What's next (about 20 s)

Topic: What's next

- Two patterns I don't see often yet: a persistent agent, like this director, that keeps its job for weeks;
- and a shared agent, one that several people can talk to.
- (line: what the two together might do)

Shot: the director node gains a long trail back through the timeline (persistent); then a second and third person appear above it, each with a line to the same director (shared). Hold on that picture.

### S11 · Start with a prompt (about 15 s)

Topic: same

- You don't need anything special to start: a prompt like my first one is enough.
- I've put a plain version of that prompt in a gist, with a link to where ours ended up.

Shot: the first prompt's card from S2 comes back, alone on the paper. Beside it, a QR code to the gist draws itself, with its short address under it. The film ends on the two together.

> Your point (Oct 12): offer a link to the director skill, but this is sharing a pattern that doesn't need a skill to get started. Link: [the director skill](https://github.com/dudgeon/duo-v2/blob/main/.claude/skills/director/SKILL.md). Your call (Oct 12): last, after the tease, with a gist of a vanilla director prompt modelled on your first one and a QR code to it. The gist: https://gist.github.com/dudgeon/d8faa688683885a0aaad2be56a7b8084 (public; edit it freely, the QR code follows the address, not the text).
