# Organising work you do yourself (§3 in full)

Read this before you split, route or file notes, make tasks across projects, or propose changes to project files. The Never list in SKILL.md still holds above everything here.

**Splitting notes into passages, routing them, filing into inboxes, making tasks in the right projects, and proposing changes to project files** you do directly, with the user's approval, as one task per request (for example "File notes from the 14 Oct pricing sync"). Starting a worker for that would cost more than doing it and lose the context.

- **Save the input unchanged** in the task's folder first (the pasted notes, as they came).
- **Propose one plan, then stop until the user says yes:** each passage and where it goes, each inferred task and its project. The request to route or file is not approval of your plan: nothing lands in any inbox, project or task list before the user has seen the plan and said yes. The user approves the plan, not each passage.
- **Where things go comes from the destinations.** Each knowledge base's `_PROJECT.md` says what belongs in it; read those. With no descriptions yet, interview once ("I found six folders that look like knowledge bases; here's what I think each holds. Right?") and propose writing each answer into that destination's own file.
- **Privacy follows the destination (Never 2).** Check each destination before the plan: `git -C <folder> remote -v` (a remote means shared; a GitHub or similar host may mean public). The plan marks every shared or public destination, and a passage going there needs the user's explicit OK for that passage, given after they've seen the mark, even when they approved the rest. Private passages never go there by inference.
- **A filed passage lands as a new note in the destination's inbox** (its knowledge-base inbox where Duo marks one, else its `inbox/` folder): the passage, the date, and a link to its source. Name it so the same passage from the same source is recognised: filing the same notes twice must not duplicate them. Don't rewrite a knowledge base's pages; its own skills digest the inbox.
- **Curation skills:** where a knowledge base's Director section describes its own skills (say "file straight into the wiki with /ingest"), offer to run them. On yes, hand that passage to a worker in that folder (§4), where its skills load.
- **Inferred tasks** are `status: suggested` in the project they belong to, each linking back to the source note. If that project has its own director, ask it (§9).
- **Receipts** (this passage went there) go in the filing task's Progress, never in a project file.
- **Corrections:** move what the user corrects, note it in Progress, and don't ask about a rule each time. Once a correction repeats ("you've moved three Acme pricing passages to Work-Sales"), propose a scope line for the destination's file.
- **Long work, or work that needs a project's own tools or skills** (a build, deep research, a prototype, a knowledge base's curation skill), goes to a worker.
- Use the tools this client has (a calendar, mail) and say what you couldn't see. You can't wake on a schedule: a "remind me Friday" becomes a task with `waiting_on:`, and you say it won't nudge.
