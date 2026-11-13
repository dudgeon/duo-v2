# The director: one session that runs the others

**A director is a Claude session that takes your requests, turns each into a task, starts a worker session for it, and checks what comes back. You talk to one session; it runs the rest.** You don't need one to use Duo.

## The problem

Once you have five or six sessions going, you become the project manager: remembering which session is doing what, whether the work matches what you asked, and which ones are stuck. That bookkeeping is the part that falls off first.

## In Duo

A director is an ordinary Claude session, usually named `director-<project>`, with the director skill loaded. There is no button for it: you start it by typing **be the director** in a session in the project (or `/director`). The skill then runs `duo2 director start`, which makes the session the project's director.

From then on, you give the director a request in your own words. For each piece of it, the director:

1. **Makes a task** (a note in the project's `tasks` folder) holding your request and what "done" means.
2. **Starts a worker**: a new Claude session on that task, to do the work.
3. **Checks what comes back** against what you asked, and records what it verified in the task's progress.
4. **Brings you only the decisions**: the choices that are really yours, not the bookkeeping.

The director is marked in the project's session list. Its workers are normal sessions, linked to their tasks, so [what needs you](what-needs-you.md) works as it always does: a worker that stops to ask you something shows up there.

The director is a convention, not a mode: Duo shows it and keeps its notes, and everything it does goes through the same `duo2` commands you can use yourself.

## Good to know

- You can stop a director any time with `duo2 director retire`. Its workers stay on their tasks.
- Start one when you have several pieces of work running at once. For one quick question, a plain session is simpler.
- [Tasks](tasks.md) explains the notes a director makes; [Sessions](sessions.md) explains the sessions it starts.
- There is a film of one in use: the director film, in Help › Watch the Director Film.

## For power users

`duo2 director start <task>` starts a worker on a task; `duo2 director status` lists what the director is neglecting; `duo2 director send` reaches a worker; `duo2 director check` records that you looked; `duo2 director guide` prints the skill. The full list is in the [duo2 reference](../cli/duo2.md).

Next: [Tasks](tasks.md)
