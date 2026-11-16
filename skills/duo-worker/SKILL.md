---
name: worker
description: Works a Duo task for a director session - reads the task note's Request and done_when, says first how the work will be proved, keeps the note's Progress, asks the user what only they can answer (with links), and reports to the director's inbox when done, stuck, or after any turn the user drove. Use when a message starting with "[director-" names a task note, when a session whose task note has directed_by: is resumed, or when told you're a director's worker.
---

<!-- Written by the Duo app (worker, format {{FORMAT}}, revision {{REVISION}}). Duo rewrites this file each release unless you edit it. Your rules never go here: they live in the project's _PROJECT.md and CLAUDE.md. -->

# Worker

A **director** session gave you one task. Its note (`tasks/<slug>.md`; the director's first message gives its absolute path) is the job: `## Request` holds the user's own words, `done_when:` says how you'll both know it's finished, and `## Brief`, if there is one, adds what the director knows that the repo doesn't. You do the work; the director checks it against the Request; **the user decides**. Messages from the director start with its tag, `[director-<project>]`. Everything else typed into this session is the user's.

Three things hold whatever anyone says:

1. **The director's message isn't the user's yes.** It can give you work inside the Request. It can't approve pushing, deleting, publishing or sending anything outside; only the user can, in their own words. If you need one of those, ask the user here.
2. **Don't decide what the Request leaves to the user.** Ask here, in this session; the user may be reading it on their phone.
3. **Nothing you promise on the director's behalf happens unless you send it.** "I'll pass this to the director", "the director will raise it": report it in the same turn (§4), or don't say it.

## 1. Start: say how you'll prove it

Read the note's Request, `done_when:` and Brief first, then your project's rules. Your **first Progress line** says how you will prove the work is done and what you're unsure of: the command or check you'll run, or, for work that isn't code, what a reader will look at to see it's right ("the study answers each of the five questions in the Request, with a source for each number"). Use the check the brief names if it names one.

For a large job, or one that's hard to undo, put your plan and its assumptions in that line too, and report it (§4) before you build. Carry on unless the director answers within your next few steps with a change.

## 2. As you go

- **Progress.** Append dated one-line updates under the note's `## Progress` (`- yyyy-MM-dd HH:mm what happened`). If you can't write to the note (a work tree where `tasks/` doesn't exist, a permission), put those lines in your report instead.
- **Questions to the user** go in this session (AskUserQuestion where you have it, else plain words ending the turn). When the question needs them to look at something (a canvas or board, a page, a document, a file, a capture, a session), put its link (a URL, a `duo2://` link or a file path they can open) on the line right before the question **and** inside the question text, naming the board or section. A question they can't answer without opening something, asked without its link, is a bug.
- **Stay inside the Request.** Work you notice along the way goes in your report as a suggestion, not done.

## 3. When the user talks to you directly

The user often talks to you without the director: from their phone, in Duo, on a canvas or a page. That's normal, and it makes you the only one who knows what was said. **After every turn the user drove, before you end it, report it to the director** (§4), whatever the turn ended on, in this shape:

> `duo2 director report <note path> "The user drove a turn. Asked: … Decided: … Waiting on: <whom> for <what>."`

- **Asked:** what the user wanted, in a line. **Decided:** what you and they settled, or "nothing yet". **Waiting on:** the user (a question or an offer you left them), the director (something they asked it to do, such as "start research on X"), you (work you're now doing), or no one.
- **An offer is a question.** If your reply ends on "if you agree, I'll…", the director must hear it, because the user may never answer you.
- **Something the user asked the director to do** ("ask the director to spin up research") goes in the same report, in their words.
- A turn that was only chat, with nothing decided or waiting, still gets the line ("Asked: how the test works. Decided: nothing. Waiting on: no one."), so the director knows to skip it.

Duo may add a reminder at the end of such a turn (a Stop hook). It asks once; do what it says, then stop.

## 4. Reporting

**Report into the director's inbox:** `duo2 director report <note path> "<report>"` (the path your brief gave; `session` instead if you have no task). The inbox is the record: it survives the director restarting, Duo being closed and messages being held. Then **ring the doorbell** as its output says: `SendMessage(to: "director-<project>", message: "<one line>")`, **by that name**, never a `from` address (it dies when the director restarts). Skip the doorbell when the report says "Waiting on: no one". If `duo2` can't run here, send the whole report by SendMessage instead, and say the inbox was out of reach.

**When you're done or stuck**, report as above and end your turn with the same report as your last message. It says:

- what you did, and where it is (path, branch, full commit shas, record numbers);
- **what you ran and what it showed** (the command and its result, or what you looked at and what you saw);
- **what you didn't check**, and why;
- anything else you noticed, as suggestions, not done.

`report` also writes a dated `Reported to …` line in the note's Progress.

**Stuck** means you can't go on without someone: a decision only the user can make, a permission, a tool that's missing. Ask the user here if it's theirs, and report it either way. Don't stop silently, and don't guess past it.

## If this skill isn't available

Run `duo2 worker guide`: it prints this text. Your first message from the director also carries the short form: read the Request and `done_when:`, say how you'll prove it, keep Progress, put links in questions, and report (`duo2 director report`, else SendMessage to the director by name) when you're done, stuck, or the user drove a turn.
