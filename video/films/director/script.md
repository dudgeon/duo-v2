# Director explainer — script v1
<!-- Synced from the script Doc at rev 1937 on 2026-10-13 by pipeline/sync.mjs; edit the Doc, not this file. -->

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

> **v2 (Oct 12), after your notes on the first draft:** the hobby framing; the rest of your first prompt (the 10:25 message); real examples of a one-line ask becoming a brief and a landed feature; research and design sessions teaming before a builder; and the director as a standup. "Writing the job down", "What we added" and "Generalists" are folded in. Every example below is from the transcripts and git: quotes are verbatim, numbers are `git show --stat`. About 560 words, so roughly 3:30; tell me what to cut if you want 3:00. Your earlier version is in this Doc's history.

### S1 · The problem (about 25 s)

Topic: The problem

- I want to share a pattern that has been working really well for me: using a single claude code session as a "director agent" to make it easier to advance many different goals in parallel, providing high level instructions while preserving the ability to dig into details when needed.
- Duo is a personal project app that I build in my free time. I work on it after hours, in short bursts, and most ideas I send from my phone as they occur to me.
- Typically, I will spin up a new session every time an idea occurs to me: features to prototype, patterns to research, or bugs to squash as I encounter them during use.
- Worktrees have helped reduce the number of change collisions, but I still need to keep all of these sessions straight, give them repetitive starting prompts, and manage the rebasing, review, and merging as work completes.
- I typically spend as much time managing the merges and renumbering documented changes as i do providing direction to my agents.

Shot: on line 1, the title card animates in: "The director agent" with a small tree (canvas option T1, with "user" in place of "You"); its finished frame is frame 0, the thumbnail. On line 2, a card animates in with the intro's Duo logo build and a small screenshot of the app. On line 3, a phone opens a new Claude Code session for each idea as it's named: a feature to prototype, a pattern to research, a bug to squash; they stack up. On line 4, each session grows a worktree branch, and the chores pile onto you as they're named (a repeated starting prompt, a rebase, a review, a merge), each a needs-you tag, until you're the switchboard. On line 5, your time splits in two: managing merges and renumbering, and giving direction.

### S2 · A simple prompt (about 25 s)

Topic: A simple prompt

- I've spent a lot of time thinking of agent orchestrators -- where one director agent abstracts complexity for the user, but I wasn't ready to commit and lock into a specific pattern -- so I decided to start simple, and evolve according to my needs
- On October fifth, I started one more session and typed this.
- *There are many sessions in this repo, all in various states. You are now their director.*
- *I am the PM and you are the engineering manager. Please do a quick survey of the state of each of these active sessions.*
- Twenty minutes later, I added one more instruction.
- *You should be periodically watching all other agents in this space and reviewing their work, surfacing decisions to me as needed.*
- From then on, all of my interactions with live sessions, and every new task, went through the director.
- I tell it what I want, usually in a sentence or two from my phone.
- It briefs a new session, or passes the word to one already running, and tells me when the work is ready.
- It reviews and merges what comes back, and asks me only when something needs my decision.

Shot: on line 1, a big orchestrator (one agent over layers of agents) sketches itself faintly, then is set aside for one console: start simple. Then the first prompt goes onto the console, its ideas as bullets that build in time with the voice; then the pattern, step by step as it's said: your sentence from the phone goes to the director; a brief goes to a new or running session; the work comes back reviewed and merged; only decisions reach you. As it lands, the tangle from S1 settles into the tree of style frame B: you on the left, the director beside you, the sessions in a panel. The director's first survey runs down the sessions. One line reaches you now.

### S3 · A line becomes a brief (about 30 s)

Topic: From a line to a brief

- Most of my asks are a sentence or two, typed on my phone, and the director turns each one into a full brief for a new session -- with my words quoted, its own branch, and how to prove the work.
- When I asked for a close button on tabs, it briefed a session twenty-five seconds later, and the change was merged about half an hour after that.
- A one-sentence ask to review the whole codebase turned into an eight hundred word brief, and a full report about an hour later.

Shot: your ask arrives as a phone message, verbatim. It travels to the director, which unfolds it into a brief card; lines of the brief light up as the voice names them (your words quoted, the branch, the reserved records, how to prove it). The brief goes to a new session; a merge card lands with what changed and how long it took. Then the review: a 34-word ask beside an 872-word brief, drawn to scale, and the report it produced.

### S4 · Teams for bigger ideas (about 30 s)

Topic: Teams for bigger ideas

- For bigger ideas, I'll often ask the director to set up a small team.
- For chat mode, I sent one message asking for a research agent and a design agent, and the director started both of them, working side by side.
- The research agent passed what it learned to the design agent, so the mock-ups only showed what was feasible. I picked a design on the canvas, and the director assigned a builder.
- The whole feature, about a hundred files of changes, was merged about five hours after I first asked for it.
- For the Word viewer feature, my whole review was four words: looks good, build, test, ship.

Shot: your ask splits into two sessions, research and design, side by side; a message passes from research to design. A canvas card with three looks; your pick ticks one. A builder appears under the director on its own branch, and a merge card lands. Then the Word viewer: a canvas card with your comment on it, in your words, and two build slices merging.

### S5 · A standup (about 25 s)

Topic: Catching up

- When I come back to it, I don't open ten sessions one by one -- I just ask the director where things stand.
- It answers like a standup, with what's done, what needs me, and what's next, and the decisions come as buttons with its recommendation first.
- One evening I tapped four answers, and two new sessions were running within a minute.

Shot: your question arrives from the phone, verbatim. The director's answer comes back as a digest card, Done / Needs you / Next, with real lines from it. Four buttons follow, recommendation first; your four taps; two new sessions start on the tree.

### S6 · Why it works (about 25 s)

Topic: Why it works

- This works better for me than subagents, because each worker is a full session on its own branch, so features don't collide and I can jump into any of them.
- The sessions message each other, so the director only reads short reports, and its own context stays small.

Shot: two diagrams side by side, then one. Left, subagents: small boxes inside the parent session's outline, their work flowing back into it until the outline swells. Right, the director: full sessions outside it, each on its own branch line, with only a short report arrow back, tagged "since Claude Code 2.1.224"; your figure steps into one session, then out again. The director's outline stays the same size the whole time.

### S7 · What got done (about 20 s)

Topic: What got done

- In its first week, the director oversaw fifteen releases and a hundred and eighty seven merges, done by about a hundred sessions.
- The work ranged from small fixes to whole new features like chat mode and the Word viewer, and the same workers took on design studies, bug hunts and research, without any specialist personas.

Shot: the first week's timeline fills with what shipped: merges as cells over their days, release tags under them, a few features named. Each count appears as the line says it.

### S8 · Patterns for your setup (about 25 s)

Topic: Patterns

- The pattern also bends to what your setup allows.
- On an older version of Claude Code, like the one on a managed work laptop that's pinned months behind, workers run as one-shot jobs and report back through files.
- And without Remote Control or a page for buttons, the questions just come in the chat instead.

Shot: a grid of constraints. For each cell, the director tree redraws to show what changes: which arrows become files, which move into the chat.

### S9 · How far it goes (about 35 s)

Topic: How far it goes

- The director pattern can be as simple or as sophisticated as you need it to be.
- At its most basic, it's just a prompt -- one session that you ask to act as the director, and you talk to it in a normal chat.
- The next step for me was moving that prompt into a director skill, so the job could survive long sessions and restarts, and I could keep improving it over time.
- From there, the skill started using shared artifacts, like a console page where I answer decisions with buttons from my phone, and agent to agent messaging, so sessions could report back to the director directly.
- At the far end is something like Claude Code projects, where the coordinator and its threads are built right in -- I don't have access to it yet, but it looks like the natural home for this pattern.

Shot: the same tree, with a piece added at each level (canvas option L2, https://claude.ai/artifact/GCWec8D9T3DtqGt4ZDzQcF): level 1, a prompt on one console; level 2, the skill page beside the director; level 3, a console page of buttons on a phone, and the sessions messaging the director; level 4, the tree drawn inside Claude Code, a coordinator and threads. A rail counts the levels 1 to 4 as the voice moves up.

### S10 · What's next (about 15 s)

Topic: What's next

- I've been really impressed with how helpful the director agent pattern has been in my own life, and how much value it can offer starting with even the most simple prompt -- and it's fun to evolve it to your needs.
- Director agents are one of two patterns that I think will offer a step change to teams that adopt them.
- One agent, advancing your work, while task-specific agents share artifacts, collaborate, and only surface issues that need the user, like review or resolving conflicts.
- The other is shared agents -- where multiple human team members can collaborate with a single shared agent.
- Combining the two patterns seems extremely promising.

Shot: on line 1, the director's trail runs back through the weeks it has kept its job. On line 2, two circles open: director agents and shared agents. On line 3, inside the first, task agents pass artifacts between them, and only the review and conflict calls rise to you. On line 4, inside the second, several people gather around one shared agent. On line 5, the circles slide together, and their overlap becomes a team of people sharing one director over many agents. Hold on that picture.

### S11 · Start with a prompt (about 15 s)

Topic: same

- You don't need anything special to start: a prompt like my first one is enough.
- I've put a plain version of that prompt in a gist, with a link to where ours ended up.
- If you choose to try out the director agent pattern, or have suggestions for how I can improve my own implementation, please let me know!

Shot: the first prompt's card from S2 comes back, alone on the paper. Beside it, a QR code to the gist draws itself, with its short address under it. The film ends on the two together.
